# Giao kèo ghép code với Danh

Phần Long: C01, C02, C04, C06, N15–N28. Driver servo, nút, HC-SR04 và HX711 trong bản này giúp demo độc lập; Danh thay bằng phần đã kiểm thử của mình khi tích hợp. Chưa tuyên bố đã xử lý toàn bộ 18 case của Danh.

## Topic

Root mặc định `petfeeder/long-petfeeder-20261020-7bf19c`. Backend đặt `DEVICE_ID`; ESP32 đặt trong `include/secrets.h`, copy từ `secrets.example.h`. Hai phía phải giống nhau.

| Topic đuôi | Hướng | Payload |
|---|---|---|
| `/command` | Backend → ESP32 | Lệnh cấp có ID/thời hạn |
| `/sync` | Backend → ESP32 | `{config, schedules, version}` đầy đủ |
| `/event` | ESP32 → Backend | Sự kiện có ID duy nhất, seq, thời điểm |
| `/ack` | Backend → ESP32 | `{event_id}` sau khi commit SQLite |
| `/telemetry` | ESP32 → Backend | Heartbeat mỗi 5 giây, cân, busy, giờ, khóa |

Tất cả `retain=false`. Backend subscribe QoS1. PubSubClient publish QoS0 nên độ bền sự kiện dùng outbox và ACK ở tầng ứng dụng: ESP32 lưu ra LittleFS trước khi gửi; chỉ xóa phần tử đầu khi nhận đúng ACK; backend deduplicate bằng khóa SQLite. Backend restart hoặc gửi ACK bị mất không làm nhân đôi lịch sử. Giữ vòng `mqtt.loop()` chạy trong lúc cấp.

## Lệnh

```json
{"command_id":"unique-uuid","source":"APP","target_portion_g":20,"override":false,"created_at":1792458000,"expires_at":1792458060}
```

Thời gian Unix **giây**, số đo **gram**. `source`: `APP`, `SCHEDULE`, `BUTTON`. Lượng là **cấp thêm**, không phải mức cuối cần đạt trong bát. `override=true` chưa được hỗ trợ và bị từ chối. Nút demo dùng 20g; khẩu phần nút cuối cùng cần Danh chuyển thành cấu hình khi tích hợp.

App lưu toàn bộ payload trước HTTP. Retry giữ nguyên ID, lượng, created_at và expires_at. API trả bản ghi cũ kể cả lệnh đã hết hạn; ID trùng mà nội dung khác trả lỗi. ESP32 chỉ giữ cache hữu hạn; không xóa ID chưa hết hạn để lấy chỗ. Lệnh cũ ngoài cache vẫn bị hạn thời gian chặn. Backend giữ lịch sử lâu dài. Cache thiết bị đầy thì từ chối; không cấp để đổi chỗ.

Các trạng thái: `QUEUED` ở backend là đang chờ thiết bị; `DELIVERY_UNKNOWN` là chưa có kết quả sau hạn gửi, **không chứng minh chưa cấp**. `ACCEPTED`/`DISPENSING` chỉ là tiến độ. `SUCCESS` chỉ sau đo lượng trong sai số. `PARTIAL`, `TIMEOUT`, `OVER_PORTION`, `SENSOR_ERROR`, `REJECTED`, `COMMAND_EXPIRED`, `INTERRUPTED` là kết quả riêng. Kết quả cuối không bị sự kiện tiến độ đến muộn ghi đè.

## Sự kiện

```json
{"event_id":"device:random-id","seq":12,"occurred_at":1792458005,"command_id":"unique-uuid","source":"APP","status":"SUCCESS","target_portion_g":20,"actual_weight_g":19.5}
```

`actual_weight_g=null` nghĩa là chưa xác định; tuyệt đối không đổi thành 0g. `seq` tăng và được lưu bền vững. `event_id` duy nhất cho từng sự kiện, giữ nguyên khi gửi lại. Backend ACK cả bản gửi trùng sau khi xác nhận có trong SQLite. Không dùng retained event để phát sinh kết quả.

## Lịch và cấu hình

`schedules` tối đa 8 phần tử, mỗi lịch có `schedule_id`, `hour` (0–23), `minute` (0–59), `days` (0=CN…6=T7, không rỗng/không trùng), `enabled`, `target_portion_g`. Mặc định múi giờ +420 phút.

Giữ khóa `schedule_id + ngày` bền vững trước khi mở cơ cấu. Đồng bộ không xóa khóa. Chỉ chạy lịch trễ dưới 60 giây; ngoài cửa sổ ghi `MISSED_SCHEDULE`, không cấp dồn. Bản demo đối soát tối đa 7 ngày gần nhất sau lần quét cuối; mất điện lâu hơn cần đối soát thêm ở backend. Không có NTP/RTC hợp lệ thì dừng lịch và báo `TIME_INVALID`. ESP32 giữ lịch khi mất mạng đang còn nguồn; chưa có RTC nên không thể chạy lịch offline ngay sau mất điện.

Khóa an toàn tại thiết bị là nơi quyết định cuối: cấu hình, khẩu phần ngày, khoảng chờ, cảm biến, nhận diện, xác nhận thức ăn. API kiểm tra trước nhưng không thay thế thiết bị. Bật `require_pet` khi chưa có phần cứng sẽ từ chối `UNKNOWN_PET`; chưa có luồng xác minh danh tính thật. `food_confirmed` chỉ là chủ xác nhận loại thức ăn, không kiểm nghiệm an toàn.

Backend gửi hash `version` của cấu hình+lịch. Thiết bị báo `config_version` trong heartbeat. Nếu lệch, backend gửi lại; thiết bị đang BUSY chưa áp dụng cấu hình, và sẽ nhận lại sau khi phiên kết thúc. Không lấy việc API đã lưu cấu hình làm bằng chứng firmware đã áp dụng.

Mất điện giữa phiên: servo đóng trước khi đọc trạng thái, ghi `INTERRUPTED`, giữ phần khẩu phần đã dự trù vào tổng ngày vì không biết chính xác lượng rơi. Chỉ mở khóa sau kiểm tra thủ công (`reconcile CHECKED`); không tự cấp lại hoặc tự giải phóng phần dự trù. Hiệu chuẩn được lưu riêng; boot không tare.

Outbox firmware tối đa 96 sự kiện, cache lệnh tối đa 32. Nếu đầy thì khóa/từ chối cấp. Kết nối backend để thoát hàng đợi rồi kiểm tra và mở khóa. Cần đo độ bền flash, tình huống cắt nguồn và hiệu chỉnh cân trên phần cứng thật trước khi sử dụng cơ cấu cuối.
