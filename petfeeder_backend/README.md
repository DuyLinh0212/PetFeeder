# PetFeeder Backend & MQTT Gateway

Node.js >=22.13, Express, SQLite tích hợp và MQTT. Chạy `npm ci`, rồi `npm start`; mặc định ở `http://127.0.0.1:3000`. Dùng `HOST=0.0.0.0` để app điện thoại truy cập qua LAN.

Camera dùng dịch vụ YOLO11n riêng ở `http://127.0.0.1:8002` (có thể đổi bằng `YOLO_URL`). Khởi động từ thư mục dự án bằng `CHAY.ps1 -Mode yolo`; sau đó app mở Camera AI trong Cài đặt. Dịch vụ phát hiện chó/mèo, không nhận dạng đúng cá thể thú nuôi.

## API

| Phương thức | Đường dẫn | Chức năng |
|---|---|---|
| GET | `/api/id` | Tạo ID, giờ máy chủ và thời hạn cho lệnh mới |
| POST | `/api/feeding/feed` | Gửi yêu cầu cấp lượng thức ăn thêm |
| GET | `/api/commands/:id` | Đọc trạng thái của một mã lệnh |
| GET / PUT | `/api/device/config` | Đọc/cập nhật giới hạn và chính sách được giữ |
| GET | `/api/device/status` | Trạng thái kết nối, cân, giới hạn và tổng trong ngày |
| GET / POST | `/api/schedules` | Đọc/tạo lịch; tối đa 10 lịch |
| PUT / DELETE | `/api/schedules/:id` | Sửa/xóa lịch |
| PATCH | `/api/schedules/:id/toggle` | Bật/tắt lịch |
| GET | `/health` | Trạng thái server/MQTT |
| POST | `/api/vision/start` | Mở phiên xử lý ảnh camera |
| POST | `/api/vision/detect` | Gửi khung ảnh và nhận kết quả YOLO |
| POST | `/api/vision/stop` | Đóng phiên, thu hồi bằng chứng hiện diện |

Yêu cầu cấp dùng thời gian epoch giây từ `/api/id`:

```json
{"command_id":"uuid-da-luu","portion":30,"created_at":1792500000,"expires_at":1792500060}
```

App lưu payload trước khi gửi. Khi chưa rõ kết quả, gửi lại cùng ID và payload. Backend/ESP32 không tạo phiên cấp thứ hai với cùng `command_id`; gửi cùng ID với nội dung khác trả `COMMAND_ID_CONFLICT`. Lệnh quá hạn bị từ chối. API không nhận `override` hoặc `retry_of`.

Khẩu phần là lượng cấp thêm. Backend kiểm tra khoảng chờ, giới hạn gram/ngày, số phiên/ngày và sức chứa bát trước khi gửi; firmware kiểm tra lại. Nếu bật `require_pet`, backend và firmware yêu cầu kết quả YOLO còn hạn xác nhận chó/mèo hiện diện. Đây không phải nhận dạng cá thể.

## MQTT và lưu trữ

Prefix mặc định `duylinh0212/petfeeder/v1`; cấu hình cùng prefix ở backend và firmware.

| Topic | Hướng | Payload chính |
|---|---|---|
| `/command` | Backend → ESP32 | `command_id`, `source`, `target_portion_g`, `created_at`, `expires_at` |
| `/sync` | Backend → ESP32 | `config`, `schedules`, `version`, `server_time` |
| `/telemetry` | ESP32 → Backend | `occurred_at`, `busy`, `weight_g`, khóa, giờ, boot ID và version |
| `/events` | ESP32 → Backend | `event_id`, `seq`, thời gian, trạng thái và lượng thực cấp |
| `/ack` | Backend → ESP32 | `event_id` sau khi SQLite đã ghi sự kiện |
| `/identity` | Backend → ESP32 | Bằng chứng hiện diện chó/mèo có hạn 5 giây |

Lịch và sự kiện dùng hàng đợi bền vững phía ESP32; backend loại sự kiện trùng theo `event_id`. SQLite ở `data/main/backend.sqlite`. Lần chạy đầu nhập lịch sử cũ từ `data/database.json` để giữ dữ liệu cần cho hạn mức; tệp JSON gốc không bị sửa.

Các phần chính: `src/domain/feedingPolicy.mjs` kiểm tra cấu hình/lệnh/lịch; `src/services/feedingService.mjs` áp dụng giới hạn và đồng bộ; `src/routes/index.mjs` cung cấp API cấp thức ăn; `src/routes/vision.mjs` chuyển khung ảnh và bằng chứng hiện diện; `src/storage/` lưu trạng thái.
