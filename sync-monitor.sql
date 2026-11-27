create table if not exists public.sync_page_state (
 page_id text primary key, page_ten text not null,
 checkpoint timestamptz, bat_dau timestamptz, thanh_cong timestamptz,
 trang_thai text not null default 'chua_chay', so_doc integer default 0,
 so_moi integer default 0, doi_tag integer default 0, doi_ad integer default 0,
 bo_qua integer default 0, loi text, run_url text, cap_nhat timestamptz default now()
);
create table if not exists public.sync_page_runs (
 id bigserial primary key, page_id text not null, run_url text,
 bat_dau timestamptz not null default now(), ket_thuc timestamptz,
 trang_thai text not null default 'dang_chay', tu_luc timestamptz, den_luc timestamptz,
 so_doc integer default 0, so_moi integer default 0, doi_tag integer default 0,
 doi_ad integer default 0, bo_qua integer default 0, loi text
);
create index if not exists sync_page_runs_page_time on public.sync_page_runs(page_id,bat_dau desc);
alter table public.sync_page_state enable row level security;
alter table public.sync_page_runs enable row level security;
create or replace view public.gop_sync_page as
select page_id,page_ten,
 to_char(bat_dau at time zone 'Asia/Bangkok','YYYY-MM-DD HH24:MI:SS') as bat_dau,
 to_char(thanh_cong at time zone 'Asia/Bangkok','YYYY-MM-DD HH24:MI:SS') as thanh_cong,
 trang_thai,so_doc,so_moi,doi_tag,doi_ad,bo_qua,coalesce(loi,'') as loi,
 coalesce(run_url,'') as run_url,
 to_char(cap_nhat at time zone 'Asia/Bangkok','YYYY-MM-DD HH24:MI:SS') as cap_nhat
from public.sync_page_state order by page_ten;
revoke all on public.gop_sync_page from anon,authenticated;

create or replace view public.gop_sync_counts as select page_id,count(*) as tong_hoi_thoai,to_char(max(cap_nhat_luc) at time zone 'Asia/Bangkok','YYYY-MM-DD HH24:MI:SS') as khach_cap_nhat from public.hoi_thoai group by page_id; revoke all on public.gop_sync_counts from anon,authenticated;
