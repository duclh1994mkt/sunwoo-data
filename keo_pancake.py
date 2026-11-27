#!/usr/bin/env python3
"""
SUNWOO · Kéo dữ liệu khách từ Pancake về Supabase.

Chạy trên GitHub Actions, không có giới hạn 6 phút như Apps Script.

Hai chế độ:
  python keo_pancake.py day-du      -> kéo toàn bộ từ ngày cấu hình (chạy tay, ~1-2 tiếng)
  python keo_pancake.py tang-dan    -> kéo cửa sổ N ngày gần nhất (chạy theo lịch)

Các page được kéo SONG SONG, mỗi page một luồng riêng, vì phần chậm là
chờ Pancake trả lời chứ không phải tính toán. Ghi vào Postgres thì vẫn
lần lượt (có khoá), nên một kết nối là đủ và không sợ tranh chấp.

Biến môi trường cần có (đặt trong GitHub Secrets):
  DATABASE_URL     chuỗi kết nối Postgres của Supabase
  PANCAKE_TOKENS   JSON: {"<page_id>": {"ten": "...", "token": "..."}, ...}
  LAY_TU_NGAY      tuỳ chọn, mặc định 2026-09-01 (chỉ dùng cho day-du)
  SO_NGAY_KEO      tuỳ chọn, mặc định 30 (chỉ dùng cho tang-dan)
  SO_LUONG         tuỳ chọn, mặc định 11 — số page kéo cùng lúc.
                   Hạ xuống 1 nếu Pancake chặn tốc độ theo IP.
"""

import json
import os
import sys
import threading
import time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta, timezone

import psycopg2
import psycopg2.extras
import requests

VN = timezone(timedelta(hours=7))
API = "https://pages.fm/api/public_api/v2/pages/{page_id}/conversations"
CO_MOI_TRANG = 60
NGHI_GIUA_TRANG = 0.15
FIELDS = 'id,type,page_id,inserted_at,updated_at,from{id,name},customer_id,tags,tag_histories,ad_ids,ads'


# ----------------------------------------------------------------------
# Lấy dữ liệu từ Pancake
# ----------------------------------------------------------------------
def lay_mot_page(page_id, token, tu_giay, den_giay, ghi_tien_do=None):
    """Lấy hết hội thoại của một page trong khoảng thời gian, trả về list."""
    ket_qua = {}
    con_tro = ""
    vong = 0

    while vong < 5000:
        vong += 1
        tham_so = {
            "page_access_token": token,
            "since": tu_giay,
            "until": den_giay,
            "order_by": "updated_at",
            "fields": FIELDS,
        }
        if con_tro:
            tham_so["last_conversation_id"] = con_tro

        du_lieu = None
        for lan in range(4):
            try:
                r = requests.get(
                    API.format(page_id=page_id), params=tham_so, timeout=90
                )
                if r.status_code != 200:
                    raise RuntimeError(f"HTTP {r.status_code}")
                du_lieu = r.json()
                if not isinstance(du_lieu, dict) or du_lieu.get('success') is False or not isinstance(du_lieu.get('conversations'), list):
                    message = str(du_lieu.get('message') or '') if isinstance(du_lieu, dict) else ''
                    if any(x in message.lower() for x in ('token', 'permission', 'unauthorized')):
                        raise PermissionError('API token/quyen khong hop le; can cap lai token cho page')
                    raise RuntimeError('Pancake tra du lieu khong hop le; vui long thu lai')
                break
            except PermissionError:
                raise
            except Exception:
                if lan == 3:
                    raise RuntimeError('Pancake khong tra loi hop le sau 4 lan thu') from None
                time.sleep(2 * (lan + 1))

        # Pancake tra ve 200 kem success=false khi token het han hoac bi
        # thu hoi. Khong bat o day thi page do lang le tra ve 0 hoi thoai
        # va bao cao cu the dung so cu, khong ai biet.
        if isinstance(du_lieu, dict) and du_lieu.get("success") is False:
            raise RuntimeError(
                "Pancake tu choi: " + str(du_lieu.get("message") or du_lieu)[:200]
            )

        khoi = du_lieu.get("conversations") or []
        if not khoi:
            break

        for hoi_thoai in khoi:
            if hoi_thoai and hoi_thoai.get("id"):
                ket_qua[str(hoi_thoai["id"])] = hoi_thoai

        if ghi_tien_do and vong % 20 == 0:
            ghi_tien_do(len(ket_qua))

        moi = str(khoi[-1].get("id") or "")
        if not moi or moi == con_tro:
            raise RuntimeError('Con tro phan trang bi lap; khong nang checkpoint')
        if len(khoi) < CO_MOI_TRANG:
            break
        con_tro = moi
        time.sleep(NGHI_GIUA_TRANG)

    else:
        raise RuntimeError('Vuot gioi han phan trang; khong nang checkpoint')
    return list(ket_qua.values())


# ----------------------------------------------------------------------
# Chuẩn hoá để ghi vào bảng
# ----------------------------------------------------------------------
def doc_thoi_diem(gia_tri):
    if not gia_tri:
        return None
    chuoi = str(gia_tri).strip().replace(" ", "T")
    if chuoi.endswith("Z"):
        chuoi = chuoi[:-1] + "+00:00"
    try:
        thoi_diem = datetime.fromisoformat(chuoi)
    except ValueError:
        return None
    if thoi_diem.tzinfo is None:
        thoi_diem = thoi_diem.replace(tzinfo=timezone.utc)
    return thoi_diem


def tach_lich_su_tag(page_id, hoi_thoai):
    """Lấy các mốc gắn/gỡ tag.

    Cấu trúc Pancake trả về, đã kiểm chứng trên dữ liệu thật:
        tag_histories: [
          { "inserted_at": "...",
            "conversation_id": "...",
            "payload": { "tag": {"text": "Q3", ...},
                         "action": "add",
                         "editor_name": "..." } },
          ...
        ]
    Tên tag nằm trong payload.tag.text chứ không ở ngoài.
    """
    ra = []
    lich_su = hoi_thoai.get("tag_histories")
    if not isinstance(lich_su, list):
        return ra
    for muc in lich_su:
        if not isinstance(muc, dict):
            continue
        payload = muc.get("payload")
        if not isinstance(payload, dict):
            continue
        tag = payload.get("tag")
        ten = str(tag.get("text") or "").strip() if isinstance(tag, dict) else ""
        luc = doc_thoi_diem(muc.get("inserted_at"))
        if not ten or not luc:
            continue
        ra.append(
            (
                page_id,
                str(hoi_thoai["id"]),
                ten,
                luc,
                str(payload.get("action") or "").strip() or None,
                str(payload.get("editor_name") or "").strip() or None,
            )
        )
    return ra


def ad_id_cuoi(hoi_thoai):
    quang_cao = [
        q
        for q in (hoi_thoai.get("ads") or [])
        if isinstance(q, dict) and q.get("ad_id") and q.get("inserted_at")
    ]
    if quang_cao:
        quang_cao.sort(key=lambda q: str(q.get("inserted_at")))
        return str(quang_cao[-1]["ad_id"])
    danh_sach = hoi_thoai.get("ad_ids") or []
    return str(danh_sach[-1]) if danh_sach else None


# ----------------------------------------------------------------------
# Ghi vào Supabase
# ----------------------------------------------------------------------
def dau_van_tag(hoi_thoai):
    """Order-independent tags/history: chat-only changes do not rewrite old rows."""
    return tuple(tuple(sorted(json.dumps(v, sort_keys=True, ensure_ascii=False)
                              for v in (hoi_thoai.get(k) or [])))
                 for k in ('tags', 'tag_histories'))


def ghi_hoi_thoai(ket_noi, page_id, page_ten, danh_sach):
    if not danh_sach:
        return 0, 0, 0, 0

    with ket_noi.cursor() as cur:
        cur.execute('select id,du_lieu from hoi_thoai where page_id=%s and id=any(%s)',
                    (page_id, [str(h['id']) for h in danh_sach]))
        cu = dict(cur.fetchall())
    moi = doi_tag = doi_ad = bo_qua = 0

    hang = []
    tag_hang = []
    for hoi_thoai in danh_sach:
        ma = str(hoi_thoai["id"])
        hoi_thoai = dict(hoi_thoai)
        hoi_thoai["ad_id_cuoi"] = ad_id_cuoi(hoi_thoai)
        truoc = cu.get(ma)
        if truoc is None:
            moi += 1
        else:
            tag_doi = dau_van_tag(truoc) != dau_van_tag(hoi_thoai)
            ad_doi = ad_id_cuoi(truoc) != hoi_thoai['ad_id_cuoi']
            doi_tag += int(tag_doi)
            doi_ad += int(ad_doi)
            if not tag_doi and not ad_doi:
                bo_qua += 1
                continue
            # Preserve historical fields already used by reports; new fetch omits phone/message bodies.
            hoi_thoai = {**truoc, **hoi_thoai}
        hang.append(
            (
                page_id,
                page_ten,
                ma,
                doc_thoi_diem(hoi_thoai.get("inserted_at")),
                doc_thoi_diem(hoi_thoai.get("updated_at")),
                json.dumps(hoi_thoai, ensure_ascii=False),
            )
        )
        tag_hang.extend(tach_lich_su_tag(page_id, hoi_thoai))

    with ket_noi.cursor() as con_tro:
        if hang:
          psycopg2.extras.execute_values(
            con_tro,
            """
            insert into hoi_thoai
              (page_id, page_ten, id, tao_luc, cap_nhat_luc, du_lieu)
            values %s
            on conflict (page_id, id) do update set
              page_ten     = excluded.page_ten,
              tao_luc      = coalesce(excluded.tao_luc, hoi_thoai.tao_luc),
              cap_nhat_luc = excluded.cap_nhat_luc,
              du_lieu      = excluded.du_lieu,
              lay_luc      = now()
            """,
            hang,
            page_size=500,
        )

        if tag_hang:
            tag_hang = list({r[:4]: r for r in tag_hang}.values())
            psycopg2.extras.execute_values(
                con_tro,
                """
                insert into lich_su_tag
                  (page_id, hoi_thoai, tag, gan_luc, hanh_dong, nguoi_gan)
                values %s
                on conflict (page_id, hoi_thoai, tag, gan_luc) do update set
                  hanh_dong = excluded.hanh_dong,
                  nguoi_gan = excluded.nguoi_gan
                """,
                tag_hang,
                page_size=1000,
            )

    ket_noi.commit()
    return moi, doi_tag, doi_ad, bo_qua


def mo_nhat_ky(ket_noi, loai, pham_vi):
    with ket_noi.cursor() as con_tro:
        con_tro.execute(
            "insert into nhat_ky_chay (loai, pham_vi, ket_qua) values (%s, %s, %s) returning id",
            (loai, pham_vi, "dang chay"),
        )
        ma = con_tro.fetchone()[0]
    ket_noi.commit()
    return ma


def dong_nhat_ky(ket_noi, ma, so_dong, dong_moi, dong_sua, ket_qua, ghi_chu=""):
    with ket_noi.cursor() as con_tro:
        con_tro.execute(
            """
            update nhat_ky_chay
               set ket_thuc = now(), so_dong = %s, dong_moi = %s,
                   dong_sua = %s, ket_qua = %s, ghi_chu = %s
             where id = %s
            """,
            (so_dong, dong_moi, dong_sua, ket_qua, ghi_chu[:2000], ma),
        )
    ket_noi.commit()


def chup_sao_luu(ket_noi):
    with ket_noi.cursor() as con_tro:
        con_tro.execute(
            """
            insert into sao_luu_ngay (ngay, so_hoi_thoai, so_lich_su_tag, so_dong_ads)
            select current_date,
                   (select count(*) from hoi_thoai),
                   (select count(*) from lich_su_tag),
                   (select count(*) from chi_tieu_ads)
            on conflict (ngay) do update set
              so_hoi_thoai   = excluded.so_hoi_thoai,
              so_lich_su_tag = excluded.so_lich_su_tag,
              so_dong_ads    = excluded.so_dong_ads,
              chup_luc       = now()
            """
        )
    ket_noi.commit()


# ----------------------------------------------------------------------
def chay():
    from incremental import main
    main()


if __name__ == '__main__':
    chay()
