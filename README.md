# PetFeeder Nhóm 7

Flutter → REST API Node.js → MQTT → ESP32. Firmware, backend và app giữ các case C01, C03, N01, N02, N07, N09 và N19.

## Chạy dự án

Cần Node.js >=22.13, Flutter SDK, PlatformIO và Wokwi Simulator.

1. Trong `petfeeder_backend`: `npm ci`, rồi `npm start`. Mặc định backend ở `http://127.0.0.1:3000`.
2. Trong `petfeeder_app`: `flutter pub get`, rồi `flutter run -d chrome --dart-define=API_URL=http://127.0.0.1:3000`.
3. Trong `PetFeeder`: `pio run`.
4. Mở `PetFeeder/diagram.json`, chạy Wokwi.
5. Gõ `status` trong Serial Monitor để xem trạng thái cân, giờ và kết nối. App cho phép đặt địa chỉ máy chủ, mở camera AI và chỉnh giới hạn cấp.

## Camera AI YOLO

Camera AI chạy thành dịch vụ riêng trên máy tính. Mở một terminal tại thư mục dự án và chạy `.\CHAY.ps1 -Mode yolo`; lần đầu script tạo môi trường Python và cài gói cần thiết, sau đó phục vụ YOLO tại cổng 8002. Chạy backend và app như các bước trên rồi vào **Cài đặt → Camera AI · YOLO**. Điện thoại thật cần kết nối tới backend qua IP LAN của máy tính.

YOLO11n phát hiện chó/mèo từ ảnh camera. Hai khung hình liên tiếp mới bật xác nhận hiện diện; kết quả hết hạn sau 5 giây. Đây là nhận diện loài, chưa xác minh đúng cá thể thú đã đăng ký. Bật **Bắt buộc camera phát hiện chó/mèo** để C01 yêu cầu bằng chứng mới trước khi cấp; các giới hạn cân, hạn mức và thời gian chờ vẫn được áp dụng.

Android Emulator dùng `http://10.0.2.2:3000`. Điện thoại thật dùng IP LAN máy tính; backend cần `HOST=0.0.0.0`.

Broker mặc định là `broker.emqx.io:1883`, prefix `duylinh0212/petfeeder/v1`. Khi dùng broker công cộng, mỗi máy/nhóm nên dùng prefix riêng ở `MQTT_TOPIC_PREFIX` trong backend `.env` và `PetFeeder/include/secrets.h`. Chạy chung prefix có thể nhận cấu hình và trạng thái từ phiên mô phỏng khác. Firmware tạo MQTT client ID theo prefix và device.

Backend gửi lại đồng bộ theo heartbeat tối đa mỗi 15 giây khi chưa có xác nhận. Cấu hình mới được áp dụng sau khi phiên cấp kết thúc. Firmware chỉ ghi `CONFIG_APPLIED` khi cấu hình/lịch thay đổi; hiệu chỉnh giờ định kỳ không ghi thêm `CLOCK_SYNCED` vào outbox sau lần đầu trong phiên boot.

## Mạch và chế độ mô phỏng

Mạch dùng servo cấp GPIO 13, nút GPIO 4, HX711 DT/SCK GPIO 19/23, OLED SDA/SCL GPIO 21/22, LED GPIO 2/15 và còi GPIO 14. HC-SR04 và servo chống kẹt đã được gỡ.

`DEMO_AUTO` mô phỏng khối lượng HX711 tăng theo nhịp servo; đây không phải số đo thật. Gõ `sim manual` để thay đổi cân bằng tay trong Wokwi. Tải HX711 là khối lượng tổng trong bát, còn khẩu phần là lượng cấp thêm.

Thiết bị thật dùng `pio run -e esp32dev-hardware`; Wokwi dùng `pio run -e esp32dev`. Hiệu chuẩn cân bằng `tare EMPTY`; firmware không tự tare lúc khởi động.

N09 hiện suy luận bát bị lấy khỏi cân từ giá trị HX711 âm sau khi cân chỉnh. Mạch chưa có cảm biến hiện diện bát riêng, nên phép suy luận này không thay thế cảm biến chuyên dụng.

## Các luồng được giữ lại

- **C01:** camera YOLO xác nhận chó/mèo đang hiện diện; chưa xác minh danh tính cá thể. Nếu bật yêu cầu camera, lệnh cần bằng chứng mới, nếu thiếu sẽ bị từ chối bằng `UNKNOWN_PET`.
- **C03:** chống dội nút, không chạy song song hai phiên, chống lặp bằng `command_id` và áp dụng khoảng chờ.
- **N01:** khẩu phần là lượng cấp thêm; kiểm tra sức chứa bát trước khi mở servo.
- **N02:** giới hạn gram và số phiên mỗi ngày được kiểm tra ở backend và ESP32.
- **N07:** cân mất ổn định thì servo dừng để chờ; mỗi phiên có giới hạn cứng về số nhịp và thời gian.
- **N09:** khi HX711 cho thấy bát đã rời cân, servo dừng và phiên bị khóa chờ kiểm tra.
- **N19:** lịch và dấu chạy theo ngày được lưu trên LittleFS; lịch chạy khi thiết bị mất mạng nếu giờ đã đồng bộ. Sự kiện được lưu trong outbox và gửi lại sau khi có mạng.

App có màn hình Tổng quan, Lịch ăn và Cài đặt; Camera AI mở từ Cài đặt. Nút “Gửi lại cùng mã” chỉ tra/gửi lại cùng yêu cầu, không tạo phiên cấp mới. Backend vẫn lưu trạng thái lệnh nội bộ để chống gửi trùng và tính giới hạn ngày; lịch sử riêng, cảnh báo, xác nhận thức ăn, theo dõi hộp hạt, quan sát sau cấp và cấp bù đã được gỡ.

API cấp thức ăn dùng `POST /api/feeding/feed` với `command_id`, `portion`, `created_at` và `expires_at`; lấy ID/giờ bằng `GET /api/id`. Kết quả từng mã xem tại `GET /api/commands/:id`. Cấu hình/lịch dùng MQTT `/sync`, sự kiện dùng `/events`, xác nhận outbox dùng `/ack`. Xem [tài liệu backend](petfeeder_backend/README.md).
