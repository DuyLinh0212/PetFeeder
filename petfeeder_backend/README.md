# PetFeeder Backend & MQTT Gateway

Node.js >=22.13 (SQLite tích hợp), Express và MQTT. Chạy `npm ci`, `npm start`; mặc định `http://127.0.0.1:3000`. Điện thoại qua LAN cần `HOST=0.0.0.0` và địa chỉ IP LAN trong app. Broker/prefix cấu hình qua `.env`; xem `.env.example` và README gốc.

## Cấu trúc mã nguồn

- `src/server.js`: khởi động HTTP server và nạp cấu hình môi trường.
- `src/app.mjs`: kết nối SQLite, xử lý lệnh, MQTT và REST API.
- `src/routes/index.mjs`: các endpoint cho thiết bị, cấp thức ăn, lịch và thông báo.
- `src/services/feedingService.mjs`: quản lý lệnh, trạng thái, chống trùng và hạn mức.
- `src/domain/feedingPolicy.mjs`: quy tắc an toàn và kiểm tra dữ liệu.
- `src/storage/`: SQLite và chuyển dữ liệu JSON cũ.
- `test/helpers/deviceSimulator.mjs`: mô hình thiết bị dành cho kiểm thử.

Các module dùng ES modules (`.mjs`); entry point và cấu hình hiện có vẫn dùng CommonJS. Dữ liệu tiếp tục ở `data/main/backend.sqlite` và JSON gốc ở `data/database.json`; việc sắp xếp mã nguồn không đổi vị trí dữ liệu.

## REST API

| Phương thức | Đường dẫn | Chức năng |
|---|---|---|
| GET | `/api/id` | Lấy `command_id`, `now`, `ttl_s` trước khi gửi yêu cầu mới |
| POST | `/api/feeding/feed` | Yêu cầu cấp thêm, chưa phải xác nhận đã cấp |
| GET / DELETE | `/api/feeding/history` | Đọc/ẩn nhật ký; GET hỗ trợ `limit` 1–200 |
| GET / POST | `/api/schedules` | Đọc/tạo lịch; tối đa 10 lịch |
| PUT / DELETE | `/api/schedules/:id` | Sửa/xóa lịch |
| PATCH | `/api/schedules/:id/toggle` | Bật/tắt lịch |
| GET | `/api/device/status` | Telemetry; số đo chưa biết là `null` |
| GET / PUT | `/api/device/config` | Cấu hình chung, đồng bộ xuống ESP32 |
| GET / DELETE | `/api/notifications` | Đọc/ẩn cảnh báo và quan sát sau cấp |
| PATCH | `/api/notifications/:id/read` | Đánh dấu đã đọc |
| GET | `/api/state`, `/api/history` | Trạng thái và đối soát lệnh/sự kiện |
| GET | `/health` | Trạng thái server/MQTT |

Payload cấp thức ăn, với thời gian epoch giây từ `/api/id`:

```json
{"command_id":"uuid-da-luu","portion":30,"override":false,"created_at":1792500000,"expires_at":1792500060}
```

App lưu payload **trước** khi POST. Khi mất phản hồi, gửi lại đúng ID, khẩu phần và thời hạn cũ. Cùng ID nhưng payload khác bị từ chối `COMMAND_ID_CONFLICT`. Lệnh mới quá hạn không được thực thi; gửi lại ID đã hoàn tất chỉ lấy kết quả cũ.

`override:true` bị từ chối `OVERRIDE_NOT_SUPPORTED`. Khoảng chờ, giới hạn ngày, xác nhận thức ăn, khóa cấp, cảm biến và khóa phiên không được bỏ qua. HTTP 200/QUEUED chỉ xác nhận backend nhận yêu cầu. Kết quả cuối phải đến từ sự kiện ESP32; PARTIAL/OVER_PORTION/lượng chưa xác định không được coi là SUCCESS.

Để cấp phần còn thiếu, tạo **ID mới**, thêm `retry_of` bằng ID phiên PARTIAL/JAM_ERROR/TIMEOUT và `portion` đúng bằng mục tiêu trừ lượng thực cấp đã xác nhận. Không cho phép hai yêu cầu cấp bù đang hoạt động/đã cấp cho cùng một phiên. Nếu phiên cấp bù tiếp tục bị lỗi, đối soát và dùng ID của phiên cấp bù đó. Mọi giới hạn an toàn vẫn được áp dụng.

Tạo lịch phải có `name`, `time` (HH:mm), `portion_g`, `days` (T2–T7/CN), `enabled` boolean. Cấu hình dùng `min_interval_s`; giữ alias `safe_interval_sec`, `lockdown` và `verify_refill` để tích hợp phần cũ. `verify_refill:true` là xác nhận của chủ, không phải kết luận từ cảm biến.

## MQTT và lưu trữ

Prefix mặc định `duylinh0212/petfeeder/v1`, phải khớp `secrets.h` của firmware:

| Hậu tố topic | Hướng | Payload |
|---|---|---|
| `/command` | Backend → ESP32 | `command_id`, `source` APP/BUTTON/SCHEDULE, `target_portion_g`, `override:false`, `created_at`, `expires_at`, tùy chọn `retry_of` |
| `/sync` | Backend → ESP32 | `config`, `schedules`, `version`; ngày CN=0 đến T7=6 |
| `/telemetry` | ESP32 → Backend | `occurred_at`, `busy`, `weight_g`, mức hạt, khóa, chế độ cảm biến, phiên boot và phiên bản cấu hình |
| `/events` | ESP32 → Backend | `event_id`, `seq`, `occurred_at`, `status`; phiên cấp có ID, mục tiêu, lượng thực cấp hoặc null và mã lỗi |
| `/ack` | Backend → ESP32 | `event_id` sau khi SQLite đã commit |

Sự kiện retained bị bỏ qua; trùng event_id không nhân đôi lịch sử/hạn mức. Kết quả cuối không bị sự kiện tiến độ đến muộn ghi đè. MQTT có thể phát lại cùng lệnh; chỉ một phiên được chạy.

SQLite tại `data/main/backend.sqlite`. Lần chạy đầu nhập `data/database.json` trong transaction, không sửa/xóa tệp gốc. Có thể chọn thư mục bằng `DATA_DIR`; thư mục tùy chọn không tự nhập dữ liệu repository. Lưu runtime và thông tin broker nằm ngoài Git. `npm test` dùng cơ sở dữ liệu tạm, mô hình thiết bị và broker cục bộ.
