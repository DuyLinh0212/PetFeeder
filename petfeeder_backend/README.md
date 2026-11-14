# PetFeeder Backend & MQTT Gateway

Node.js >=22.13, Express, PostgreSQL và MQTT. Backend cần `DATABASE_URL`; chạy `npm ci`, rồi `npm start`. Mặc định server chạy tại `http://127.0.0.1:3000`. Dùng `HOST=0.0.0.0` để app trên điện thoại truy cập qua mạng LAN.

## API

| Phương thức | Đường dẫn | Chức năng |
|---|---|---|
| GET | `/api/id` | Tạo ID, giờ máy chủ và thời hạn cho lệnh mới |
| POST | `/api/feeding/feed` | Gửi yêu cầu cấp lượng thức ăn thêm |
| GET | `/api/feeding/history` | Đọc các lần cấp đã ghi nhận |
| GET | `/api/commands/:id` | Đọc trạng thái của một mã lệnh |
| GET / PUT | `/api/device/config` | Đọc/cập nhật giới hạn cấp thức ăn |
| GET | `/api/device/status` | Trạng thái kết nối, cân và giới hạn trong ngày |
| GET / POST | `/api/schedules` | Đọc/tạo lịch; tối đa 10 lịch |
| PUT / DELETE | `/api/schedules/:id` | Sửa/xóa lịch |
| PATCH | `/api/schedules/:id/toggle` | Bật/tắt lịch |
| GET | `/health` | Trạng thái server/MQTT |

Yêu cầu cấp dùng thời gian epoch giây từ `/api/id`:

```json
{"command_id":"uuid-da-luu","portion":30,"created_at":1792500000,"expires_at":1792500060}
```

App giữ lại payload trước khi gửi. Khi kết quả chưa rõ, truy vấn lại cùng ID; backend và ESP32 không mở phiên cấp thứ hai với cùng `command_id`. Lệnh quá hạn bị từ chối. Không cần xác minh thú cưng trước khi gửi yêu cầu.

Khẩu phần là lượng cấp thêm. Backend kiểm tra kết nối, khoảng chờ, giới hạn gram/ngày, số phiên/ngày và sức chứa bát trước khi gửi; firmware kiểm tra lại cảm biến, lượng cân, thời hạn, khoảng chờ và giới hạn tại thiết bị. Nút vật lý trên mạch tiếp tục gửi khẩu phần 20 g qua bộ kiểm tra này.

## MQTT và lưu trữ

Prefix mặc định `duylinh0212/petfeeder/v1`; cấu hình cùng prefix ở backend và firmware.

| Topic | Hướng | Payload chính |
|---|---|---|
| `/command` | Backend → ESP32 | `command_id`, `source`, `target_portion_g`, `created_at`, `expires_at` |
| `/sync` | Backend → ESP32 | `config`, `schedules`, `version`, `server_time` |
| `/telemetry` | ESP32 → Backend | `occurred_at`, `busy`, `weight_g`, khóa, giờ, boot ID và version |
| `/events` | ESP32 → Backend | `event_id`, `seq`, thời gian, trạng thái và lượng thực cấp |
| `/ack` | Backend → ESP32 | `event_id` sau khi PostgreSQL đã ghi sự kiện |

Lịch và sự kiện dùng hàng đợi bền vững phía ESP32; backend loại sự kiện trùng theo `event_id` và lưu dữ liệu vận hành trong PostgreSQL qua `DATABASE_URL`. `backend.sqlite` không được dùng khi backend chạy bình thường. Script `npm run migrate:sqlite` chỉ đọc một bản SQLite cũ nếu bạn chủ động cần nhập dữ liệu sang PostgreSQL; chế độ test cũng dùng SQLite riêng. Lần chạy đầu có thể nhập lịch sử cũ từ `data/database.json` để giữ dữ liệu cần cho hạn mức; tệp JSON gốc không bị sửa.

Các phần chính: `src/domain/feedingPolicy.mjs` kiểm tra cấu hình/lệnh/lịch; `src/services/feedingService.mjs` áp dụng giới hạn và đồng bộ; `src/routes/index.mjs` cung cấp API; `src/storage/` lưu trạng thái.
