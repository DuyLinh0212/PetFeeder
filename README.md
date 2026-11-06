# PetFeeder Nhóm 7

Ứng dụng Flutter gửi lệnh qua REST API và MQTT tới ESP32. Nút trên mạch vẫn cấp khẩu phần 20 g như hiện tại; app cho ăn và lịch ăn cũng hoạt động bình thường. Không cần nhận diện thú cưng trước khi cấp. Mọi lệnh vẫn chịu giới hạn cân, khẩu phần, số lần ăn và khoảng chờ của thiết bị.

## Chạy dự án

Cần Node.js >=22.13, Flutter SDK, PlatformIO và Wokwi Simulator.

1. Trong `petfeeder_backend`: `npm ci`, rồi `npm start`. Mặc định backend ở `http://127.0.0.1:3000`.
2. Trong `petfeeder_app`: `flutter pub get`, rồi `flutter run -d chrome --dart-define=API_URL=http://127.0.0.1:3000`.
3. Trong `PetFeeder`: `pio run`.
4. Mở `PetFeeder/diagram.json` và chạy Wokwi.
5. Mở Serial Monitor ở 115200 baud; gõ `status` để xem số cân, giờ và kết nối.

Android Emulator dùng `http://10.0.2.2:3000`. Điện thoại thật dùng IP LAN máy tính; backend cần `HOST=0.0.0.0`. Có thể đổi địa chỉ máy chủ trong mục Cài đặt của app.

Broker mặc định là `broker.emqx.io:1883`, prefix `duylinh0212/petfeeder/v1`. Khi dùng broker công cộng, mỗi máy/nhóm nên đặt prefix riêng trong backend `.env` và `PetFeeder/include/secrets.h`.

## Ứng dụng

Thanh điều hướng có ba mục **Lịch sử cho ăn**, **Cho ăn** và **Kế hoạch cho ăn**. Cài đặt mở từ biểu tượng bánh răng. Lịch sử đọc các lần cấp đã lưu ở backend; lịch ăn được đồng bộ lên ESP32 và vẫn chạy khi mất mạng nếu đồng hồ đã đồng bộ.

Lệnh từ app giữ nguyên mã và nội dung khi cần truy vấn lại kết quả, tránh cấp lặp. Các giới hạn bắt buộc gồm khoảng chờ tối thiểu, tổng lượng và số lần ăn trong ngày, sức chứa bát, thời hạn lệnh và trạng thái cân.

## Mạch và chế độ mô phỏng

Mạch dùng servo GPIO 13, nút GPIO 4, HX711 DT/SCK GPIO 19/23, OLED SDA/SCL GPIO 21/22, LED GPIO 2/15 và còi GPIO 14. Nút mạch gửi yêu cầu 20 g qua cùng bộ điều khiển an toàn. Bộ lọc HX711 lấy trung bình trượt 5 mẫu và chờ số cân ổn định trước khi tiếp tục cấp.

`DEMO_AUTO` mô phỏng khối lượng HX711 tăng theo nhịp servo; đây không phải số đo thật. Gõ `sim manual` để thay đổi cân bằng tay trong Wokwi. Tải HX711 là khối lượng tổng trong bát; khẩu phần là lượng cấp thêm.

Thiết bị thật dùng `pio run -e esp32dev-hardware`; Wokwi dùng `pio run -e esp32dev`. Hiệu chuẩn cân bằng `tare EMPTY`; firmware không tự tare lúc khởi động.

## Các xử lý an toàn

- **C03:** chống dội nút, không chạy song song hai phiên, chống lặp bằng `command_id` và áp dụng khoảng chờ.
- **N01/N02:** kiểm tra sức chứa bát, giới hạn gram và số phiên mỗi ngày.
- **N07:** số cân không ổn định thì tạm dừng; cân thay đổi bất thường sẽ dừng phiên để tránh tính sai lượng cấp.
- **N09:** khi HX711 cho thấy bát đã rời cân, servo dừng và phiên chờ kiểm tra.
- **N19:** lịch và dấu chạy theo ngày được lưu trên LittleFS; sự kiện được gửi lại khi mạng phục hồi.

API cấp thức ăn dùng `POST /api/feeding/feed`; lấy ID và giờ bằng `GET /api/id`. Kết quả từng mã xem tại `GET /api/commands/:id`; lịch sử đọc qua `GET /api/feeding/history`. Xem [tài liệu backend](petfeeder_backend/README.md).
