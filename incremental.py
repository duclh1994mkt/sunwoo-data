"""Hourly incremental sync. Credentials remain exclusively in Actions secrets."""
import json
import os
import sys
from pathlib import Path
from datetime import datetime, timedelta, timezone
from concurrent.futures import ThreadPoolExecutor, as_completed
import psycopg2
from keo_pancake import lay_mot_page, ghi_hoi_thoai, mo_nhat_ky, dong_nhat_ky, chup_sao_luu


def run_page(page_id, config, end, mode, run_url):
    conn = psycopg2.connect(os.environ['DATABASE_URL'])
    name = config.get('ten') or page_id
    page_run = None
    try:
        with conn.cursor() as cur:
            cur.execute('select checkpoint from sync_page_state where page_id=%s', (page_id,))
            row = cur.fetchone()
            checkpoint = row[0] if row else None
            if mode == 'day-du':
                start = datetime.fromisoformat(os.environ.get('LAY_TU_NGAY', '2026-10-21') + 'T00:00:00+07:00')
            elif checkpoint:
                start = checkpoint - timedelta(minutes=30)
            else:
                # Old importer committed only completed pages. Overlap covers its fetch duration.
                cur.execute('select max(lay_luc) from hoi_thoai where page_id=%s', (page_id,))
                prior = cur.fetchone()[0]
                start = prior - timedelta(hours=2) if prior else datetime.fromisoformat('2026-10-21T00:00:00+07:00')
            cur.execute("""insert into sync_page_state(page_id,page_ten,bat_dau,trang_thai,loi,run_url)
                values(%s,%s,now(),'dang_chay',null,%s) on conflict(page_id) do update set
                page_ten=excluded.page_ten,bat_dau=now(),trang_thai='dang_chay',loi=null,
                run_url=excluded.run_url,cap_nhat=now()""", (page_id,name,run_url))
            cur.execute("""insert into sync_page_runs(page_id,run_url,tu_luc,den_luc)
                values(%s,%s,%s,%s) returning id""", (page_id,run_url,start,end))
            page_run = cur.fetchone()[0]
        conn.commit()
        print(f'[{page_id} | {name}] tu {start.isoformat()}', flush=True)
        data = lay_mot_page(page_id, config['token'], int(start.timestamp()), int(end.timestamp()))
        new, tags, ads, skip = ghi_hoi_thoai(conn,page_id,name,data)
        with conn.cursor() as cur:
            cur.execute("""update sync_page_state set checkpoint=%s,thanh_cong=now(),trang_thai='xong',
                so_doc=%s,so_moi=%s,doi_tag=%s,doi_ad=%s,bo_qua=%s,loi=null,cap_nhat=now()
                where page_id=%s""", (end,len(data),new,tags,ads,skip,page_id))
            cur.execute("""update sync_page_runs set ket_thuc=now(),trang_thai='xong',so_doc=%s,
                so_moi=%s,doi_tag=%s,doi_ad=%s,bo_qua=%s where id=%s""",
                (len(data),new,tags,ads,skip,page_run))
        conn.commit()
        print(f'[{page_id} | {name}] doc={len(data)} moi={new} doi_tag={tags} doi_ad={ads} bo_qua={skip}',flush=True)
        return len(data),new,len(data)-new-skip
    except Exception as exc:
        conn.rollback()
        # Do not print request URLs, tokens or connection strings in public job logs.
        if isinstance(exc, PermissionError):
            reason = 'TOKEN_HET_HAN: cap lai page_access_token'
        elif isinstance(exc, RuntimeError):
            reason = str(exc)[:300]
        else:
            reason = 'Loi ' + type(exc).__name__ + '; kiem tra ket noi/du lieu'
        with conn.cursor() as cur:
            cur.execute("""update sync_page_state set trang_thai='loi',loi=%s,cap_nhat=now()
                where page_id=%s""", (reason,page_id))
            if page_run:
                cur.execute("""update sync_page_runs set ket_thuc=now(),trang_thai='loi',loi=%s where id=%s""",(reason,page_run))
        conn.commit()
        print(f'LOI [{page_id} | {name}] {reason}',flush=True)
        raise RuntimeError(f'{page_id}: {reason}') from None
    finally:
        conn.close()


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else 'tang-dan'
    if mode not in ('tang-dan','day-du'):
        raise SystemExit('Che do khong hop le')
    pages = json.loads(os.environ['PANCAKE_TOKENS'])
    pages.update(json.loads(os.environ.get('PANCAKE_TOKENS_THEM') or '{}'))
    overrides = json.loads(os.environ.get('PANCAKE_TOKENS_SUA') or '{}')
    for page_id, replacement in overrides.items():
        if page_id in pages and isinstance(replacement, dict) and replacement.get('token'):
            pages[page_id] = {**pages[page_id], **replacement}
    pages = {str(k):v for k,v in pages.items() if v.get('active',True)}
    if not pages:
        raise SystemExit('Chua co page API')
    run_url = ('https://github.com/' + os.environ.get('GITHUB_REPOSITORY','duclh1994mkt/sunwoo-data')
               + '/actions/runs/' + os.environ.get('GITHUB_RUN_ID','local'))
    db = psycopg2.connect(os.environ['DATABASE_URL'])
    try:
        with db.cursor() as cur:
            cur.execute('select pg_try_advisory_lock(782461109)')
            if not cur.fetchone()[0]:
                raise SystemExit('Da co luot dong bo khac; khong chay trung')
            cur.execute(Path(__file__).with_name('sync-monitor.sql').read_text(encoding='utf-8'))
        db.commit()
        log = mo_nhat_ky(db,mode,'checkpoint rieng tung page; chi ghi moi/tag/Ad ID')
        end = datetime.now(timezone.utc)
        errors, totals = [], [0,0,0]
        with ThreadPoolExecutor(max_workers=max(1,min(len(pages),int(os.environ.get('SO_LUONG','4'))))) as pool:
            jobs = [pool.submit(run_page,p,c,end,mode,run_url) for p,c in pages.items()]
            for future in as_completed(jobs):
                try:
                    counts = future.result()
                    totals[:] = [a+b for a,b in zip(totals,counts)]
                except Exception as exc:
                    errors.append(str(exc))
        chup_sao_luu(db)
        dong_nhat_ky(db,log,*totals,'loi' if errors else 'xong',' | '.join(errors))
        print(f'TONG: doc={totals[0]}, moi={totals[1]}, sua={totals[2]}, page_loi={len(errors)}',flush=True)
        if errors:
            raise SystemExit(1)
    finally:
        db.close()


if __name__ == '__main__':
    main()
