-- SUNWOO · Kho du lieu tren Supabase (PostgreSQL)
-- Chay mot lan trong Supabase > SQL Editor

-- =====================================================================
-- 1. HOI THOAI THO  (moi hoi thoai mot dong, giu nguyen JSON goc)
-- =====================================================================
create table if not exists hoi_thoai (
  page_id      text        not null,
  page_ten     text,
  id           text        not null,
  tao_luc      timestamptz,
  cap_nhat_luc timestamptz,
  du_lieu      jsonb       not null,
  lay_luc      timestamptz not null default now(),
  primary key (page_id, id)
);

create index if not exists hoi_thoai_cap_nhat_idx on hoi_thoai (cap_nhat_luc desc);
create index if not exists hoi_thoai_tao_idx      on hoi_thoai (tao_luc);
create index if not exists hoi_thoai_page_idx     on hoi_thoai (page_id);

comment on table hoi_thoai is
  'Hoi thoai Pancake. Cot du_lieu giu nguyen JSON tu API nen khong bao gio mat du lieu, '
  'moi truong moi deu doc lai duoc bang SQL ma khong phai keo lai.';

-- =====================================================================
-- 2. LICH SU TAG  (moc gio gan tung tag — cai de dem booking dung ngay)
-- =====================================================================
create table if not exists lich_su_tag (
  page_id   text        not null,
  hoi_thoai text        not null,
  tag       text        not null,
  gan_luc   timestamptz not null,
  hanh_dong text,
  nguoi_gan text,
  primary key (page_id, hoi_thoai, tag, gan_luc)
);

alter table lich_su_tag add column if not exists hanh_dong text;
alter table lich_su_tag add column if not exists nguoi_gan text;

create index if not exists lich_su_tag_gan_idx on lich_su_tag (gan_luc);
create index if not exists lich_su_tag_tag_idx on lich_su_tag (tag);

comment on table lich_su_tag is
  'Moc gio gan/go tag, tach tu tag_histories. Ten tag nam o payload.tag.text, '
  'hanh dong o payload.action (add/remove), nguoi thao tac o payload.editor_name. '
  'Dong 28 bao cao thang (Tong booking thuc te) dem tu bang nay, theo thoi diem '
  'gan tag, chu khong theo ngay hoi thoai.';

-- =====================================================================
-- 3. CHI TIEU ADS  (mot dong moi ad moi ngay)
-- =====================================================================
create table if not exists chi_tieu_ads (
  ngay          date    not null,
  ad_id         text    not null,
  tai_khoan     text,
  campaign_ten  text,
  ad_ten        text,
  chi_tieu      numeric default 0,
  hien_thi      bigint  default 0,
  tiep_can      bigint  default 0,
  click         bigint  default 0,
  mess          bigint  default 0,
  lead          bigint  default 0,
  du_lieu       jsonb,
  lay_luc       timestamptz not null default now(),
  primary key (ngay, ad_id)
);

create index if not exists chi_tieu_ads_ngay_idx on chi_tieu_ads (ngay desc);

-- =====================================================================
-- 4. BANG TRA AD  (ad_id -> ma content, ma dich vu, nhan su, thi truong)
-- =====================================================================
create table if not exists tra_ad (
  ad_id        text primary key,
  ad_ten       text,
  campaign_ten text,
  thuong_hieu  text,
  thi_truong   text,
  dich_vu      text,
  nhan_su      text,
  ma_dich_vu   text,
  ma_content   text,
  cap_nhat_luc timestamptz not null default now()
);

comment on table tra_ad is
  'Bang tra nho, tach tu ten campaign. Day la thu ma script cu phai keo 28.000 dong '
  'IMPORTRANGE moi co — o day chi vai nghin dong va khong lam nang gi.';

-- =====================================================================
-- 5. NHAT KY CHAY  (lich su keo va lich su xuat — yeu cau cua anh Duc)
-- =====================================================================
create table if not exists nhat_ky_chay (
  id        bigserial primary key,
  bat_dau   timestamptz not null default now(),
  ket_thuc  timestamptz,
  loai      text not null,
  pham_vi   text,
  so_dong   integer default 0,
  dong_moi  integer default 0,
  dong_sua  integer default 0,
  ket_qua   text,
  ghi_chu   text
);

create index if not exists nhat_ky_chay_idx on nhat_ky_chay (bat_dau desc);

-- =====================================================================
-- 6. SAO LUU HANG NGAY  (chup lai so luong de biet neu du lieu tut bat thuong)
-- =====================================================================
create table if not exists sao_luu_ngay (
  ngay           date primary key,
  so_hoi_thoai   integer,
  so_lich_su_tag integer,
  so_dong_ads    integer,
  chup_luc       timestamptz not null default now()
);

-- =====================================================================
-- 7. VIEW GOP SAN  (Sheets chi doc tu day, khong doc dong tho)
-- =====================================================================

-- Khach theo ngay va ma content
create or replace view gop_content as
select
  (h.tao_luc at time zone 'Asia/Ho_Chi_Minh')::date as ngay,
  coalesce(t.ma_content, 'CHUA CO MA')              as ma_content,
  coalesce(t.dich_vu, 'chua ro')                    as dich_vu,
  count(*)                                          as tong_kh,
  count(*) filter (where h.du_lieu ->> 'chat_luong' = '1') as kh_chat_luong
from hoi_thoai h
left join tra_ad t on t.ad_id = h.du_lieu ->> 'ad_id_cuoi'
group by 1, 2, 3;

-- Booking dem theo thoi diem GAN TAG, khong theo ngay hoi thoai
create or replace view gop_booking as
select
  (l.gan_luc at time zone 'Asia/Ho_Chi_Minh')::date as ngay,
  l.tag,
  count(distinct (l.page_id, l.hoi_thoai))          as so_khach
from lich_su_tag l
where upper(l.tag) like '%BOOKING%'
  and coalesce(l.hanh_dong, 'add') = 'add'
group by 1, 2;

-- Moi tag theo ngay, ke ca luot go tag
create or replace view gop_tag_ngay as
select
  (l.gan_luc at time zone 'Asia/Ho_Chi_Minh')::date as ngay,
  l.tag,
  l.hanh_dong,
  count(distinct (l.page_id, l.hoi_thoai))          as so_khach
from lich_su_tag l
group by 1, 2, 3;

-- Chi tieu ads theo ngay va ma content
create or replace view gop_ads as
select
  a.ngay,
  coalesce(t.ma_content, 'CHUA CO MA') as ma_content,
  coalesce(t.dich_vu, 'chua ro')       as dich_vu,
  sum(a.chi_tieu)                      as chi_tieu,
  sum(a.mess)                          as mess,
  sum(a.lead)                          as lead_meta
from chi_tieu_ads a
left join tra_ad t on t.ad_id = a.ad_id
group by 1, 2, 3;

-- =====================================================================
-- 8. BANG RONG  (de Sheets tu pivot, khong phai nho sua SQL)
-- =====================================================================

-- Moi dong: mot to hop ngay x mang x page x loai x co SDT x tag x hanh dong
-- Tu bang nay pivot ra duoc gan het bao cao hien tai ma khong can SQL moi.
create or replace view gop_rong as
with kh as (
  select h.page_id, h.id,
         (h.tao_luc at time zone 'Asia/Ho_Chi_Minh')::date as ngay,
         h.page_ten,
         case when h.page_ten ~* 'dental|implant|crown|wisdom|rang'
              then 'Dental' else 'Beauty' end as mang,
         coalesce(h.du_lieu ->> 'type', 'khong ro') as loai,
         (h.du_lieu ->> 'has_phone') = 'true' as co_sdt
  from hoi_thoai h
)
select kh.ngay, kh.mang, kh.page_ten, kh.loai, kh.co_sdt,
       l.tag, coalesce(l.hanh_dong, 'add') as hanh_dong,
       count(distinct (kh.page_id, kh.id)) as so_khach
from kh
join lich_su_tag l on l.page_id = kh.page_id and l.hoi_thoai = kh.id
group by 1, 2, 3, 4, 5, 6, 7;

-- Tong khach theo ngay, khong phu thuoc tag
create or replace view gop_khach_ngay as
select (h.tao_luc at time zone 'Asia/Ho_Chi_Minh')::date as ngay,
       case when h.page_ten ~* 'dental|implant|crown|wisdom|rang'
            then 'Dental' else 'Beauty' end as mang,
       h.page_ten,
       coalesce(h.du_lieu ->> 'type', 'khong ro') as loai,
       count(*) as so_khach,
       count(*) filter (where (h.du_lieu ->> 'has_phone') = 'true') as co_sdt
from hoi_thoai h
group by 1, 2, 3, 4;

-- =====================================================================
-- 9. QUYEN VA KIEU NGAY  (de Edge Function va Google Sheets doc duoc)
-- =====================================================================
-- Cot ngay tra ve dang chuoi 'YYYY-MM-DD' chu khong phai kieu date:
-- qua CSV, kieu date bi tuan tu hoa thanh chuoi JS dai dong va Google
-- Sheets khong hieu la ngay. Chuoi YYYY-MM-DD thi Sheets tu nhan.
--
-- security_invoker = off: view chay bang quyen chu so huu, nen chi can
-- cap quyen tren view, bang tho van khoa kin.

alter view gop_booking    set (security_invoker = off);
alter view gop_khach_ngay set (security_invoker = off);
alter view gop_rong       set (security_invoker = off);
alter view gop_tag_ngay   set (security_invoker = off);
alter view gop_content    set (security_invoker = off);
alter view gop_ads        set (security_invoker = off);

grant usage on schema public to anon, authenticated, service_role;
grant select on
  gop_rong, gop_khach_ngay, gop_booking, gop_tag_ngay,
  gop_content, gop_ads, nhat_ky_chay, sao_luu_ngay
to anon, authenticated, service_role;
