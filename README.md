# Kho dữ liệu Sunwoo

Kéo dữ liệu khách từ Pancake và chi tiêu quảng cáo từ Meta về một cơ sở dữ liệu
thật (Supabase / PostgreSQL), thay cho việc chứa dữ liệu thô trong Google Sheets.

## Vì sao đổi

Hệ thống cũ chạy bằng Google Apps Script và chứa toàn bộ dữ liệu thô trong file
báo cáo. Ba giới hạn làm nó hỏng đi hỏng lại:

| Giới hạn | Hậu quả thực tế |
|---|---|
| Apps Script tối đa 6 phút mỗi lượt | Lượt chạy bị cắt giữa chừng, có hôm đứng 7 tiếng |
| Google Sheets tối đa 10 triệu ô | File báo cáo đã dùng ~7,2 triệu ô |
| Sheets tính lại cả file mỗi lần ghi | Ghi một bảng mất 2,5–5 phút, càng nhiều dòng càng chậm |

Hệ thống mới: GitHub Actions cho 6 tiếng mỗi lượt, Postgres không giới hạn dòng,
và Sheets chỉ nhận số đã gộp sẵn (vài nghìn dòng thay vì 41.000).

## Các phần

| File | Việc |
|---|---|
| `schema.sql` | Tạo bảng và view trong Supabase. Chạy một lần ở SQL Editor |
| `keo_pancake.py` | Kéo hội thoại khách từ Pancake |
| `.github/workflows/keo-du-lieu.yml` | Lịch chạy mỗi giờ |

## Chạy

Mỗi giờ GitHub Actions tự chạy chế độ `tang-dan`, chỉ lấy phần thay đổi.

Kéo lại toàn bộ từ 01/09 thì vào tab **Actions** → **Kéo dữ liệu Sunwoo** →
**Run workflow** → chọn `day-du`.

## Cấu hình

Đặt trong **Settings → Secrets and variables → Actions**:

| Tên | Nội dung |
|---|---|
| `DATABASE_URL` | Chuỗi kết nối Postgres của Supabase |
| `PANCAKE_TOKENS` | JSON: `{"<page_id>": {"ten": "...", "token": "..."}}` |

Không có token nào nằm trong code. Toàn bộ nằm ở Secrets.

## Thiết kế đáng chú ý

**Giữ nguyên JSON gốc.** Mỗi hội thoại lưu cả khối dữ liệu thô vào cột `du_lieu`.
Cần thêm trường nào thì đọc lại bằng SQL, không phải kéo lại từ đầu.

**Đếm booking theo thời điểm gắn tag.** Bảng `lich_su_tag` giữ mốc giờ gắn từng
tag, nên báo cáo đếm theo đúng ngày khách được gắn Booking, không đếm theo ngày
hội thoại.

**Có nhật ký và sao lưu.** Bảng `nhat_ky_chay` ghi từng lượt chạy; `sao_luu_ngay`
chụp số lượng mỗi ngày để phát hiện nếu dữ liệu tụt bất thường.
