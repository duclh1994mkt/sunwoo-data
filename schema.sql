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

-- =====================================================================
-- 10. KHACH CHI TIET (co moc gio tag) + 15 LAT 4.000 DONG cho Sheets
-- =====================================================================
-- Google chan IMPORTDATA khi mot lan tai qua lon: 37.557 dong x 12 cot
-- bi tu choi ("Tai nguyen tai cac noi dung url da vuot qua kich thuoc
-- toi da"). Nguong do duoc: ~12.000 dong x 8 cot va 7.608 dong x 12 cot
-- chay duoc; 22.097 dong x 12 cot thi khong. Nen cat thanh lat nho.
--
-- Trong tab "SB - Khach chi tiet", lat k nam o dong 2 + (k-1)*4000, nen
-- cac lat noi lien nhau thanh mot bang lien tuc khong co dong tieu de
-- chen giua (Edge Function nhan &tieu_de=0 thi bo dong tieu de).
-- 15 lat x 4.000 = suc chua 60.000 dong; nap day mat khoang 60-90 giay.
--
-- Thu tu row_number theo tao_luc tang dan: hoi thoai moi luon roi vao
-- lat cuoi, cac lat truoc gan nhu khong doi.

drop view if exists gop_kc_ds cascade;
drop view if exists gop_khach_chi_tiet cascade;

create view gop_khach_chi_tiet as
with t as (
  select page_id, hoi_thoai,
         min(gan_luc) filter (where hanh_dong = 'add')                           as tag_dau,
         max(gan_luc)                                                            as tag_cuoi,
         min(gan_luc) filter (where hanh_dong = 'add' and tag = 'CHẤT LƯỢNG')    as cl,
         min(gan_luc) filter (where hanh_dong = 'add' and tag = 'BOOKING')       as bk,
         min(gan_luc) filter (where hanh_dong = 'add' and tag = 'KO QUAN TÂM')   as kqt,
         count(*)                                                                as so_lan
  from lich_su_tag
  group by 1, 2
)
select h.page_id,
       h.id as ma_hoi_thoai,
       h.page_ten,
       case when h.page_ten ~* 'dental|implant|crown|wisdom|rang'
            then 'Dental' else 'Beauty' end as mang,
       to_char(h.tao_luc      at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD HH24:MI') as tao_luc,
       to_char(h.cap_nhat_luc at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD HH24:MI') as cap_nhat_luc,
       coalesce(h.du_lieu ->> 'type', 'khong ro')     as loai,
       (h.du_lieu ->> 'has_phone') = 'true'           as co_sdt,
       h.du_lieu ->> 'ad_id_cuoi'                     as ad_id,
       h.du_lieu ->> 'customer_id'                    as ma_khach,
       nullif(h.du_lieu ->> 'message_count', '')      as so_tin_nhan,
       (select string_agg(distinct x.value ->> 'text', ' | ')
          from jsonb_array_elements(
                 case when jsonb_typeof(h.du_lieu -> 'tags') = 'array'
                      then h.du_lieu -> 'tags' else '[]'::jsonb end) x) as tag_hien_tai,
       to_char(t.tag_dau  at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD HH24:MI') as tag_dau_luc,
       to_char(t.tag_cuoi at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD HH24:MI') as tag_cuoi_luc,
       to_char(t.cl       at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD HH24:MI') as chat_luong_luc,
       to_char(t.bk       at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD HH24:MI') as booking_luc,
       to_char(t.kqt      at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD HH24:MI') as ko_quan_tam_luc,
       coalesce(t.so_lan, 0) as so_lan_doi_tag
from hoi_thoai h
left join t on t.page_id = h.page_id and t.hoi_thoai = h.id;

alter view gop_khach_chi_tiet set (security_invoker = off);
grant select on gop_khach_chi_tiet to anon, authenticated, service_role;

create view gop_kc_ds as
select *, row_number() over (order by tao_luc, ma_hoi_thoai) as rn
from gop_khach_chi_tiet;

-- Sinh gop_kc1 ... gop_kc15, moi lat 4.000 dong (suc chua 60.000).
-- Khi vuot 54.000 dong thi tang 15 len va them cong thuc IMPORTDATA
-- tuong ung trong tab "SB - Khach chi tiet" (o T7 co bao "SAP DAY").
do $$
declare i int;
        c text := 'page_id,ma_hoi_thoai,page_ten,mang,tao_luc,cap_nhat_luc,'
                  'loai,co_sdt,ad_id,ma_khach,so_tin_nhan,tag_hien_tai,'
                  'tag_dau_luc,tag_cuoi_luc,chat_luong_luc,booking_luc,'
                  'ko_quan_tam_luc,so_lan_doi_tag';
begin
  for i in 1..15 loop
    execute format(
      'create or replace view gop_kc%s as select %s from gop_kc_ds '
      'where rn > %s and rn <= %s', i, c, (i-1)*4000, i*4000);
    execute format('alter view gop_kc%s set (security_invoker = off)', i);
    execute format(
      'grant select on gop_kc%s to anon, authenticated, service_role', i);
  end loop;
end $$;

-- Kiem tra: cac so nay phai khop voi khoi T1:U5 trong tab Sheets.
--   tong 37.557 | co moc tag 33.974 | CHAT LUONG 10.504 | BOOKING 1.054
