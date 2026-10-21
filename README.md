# PetFeeder Nhóm 7 — mạch main ghép phần Long

Thành viên: Nguyễn Duy Linh, Ngô Công Danh, Lê Hoàng Bảo Long.

Lấy từ main tại commit 41c0e7a, ghép phần Long vào cùng mạch. Chỉ có một sơ đồ PetFeeder/diagram.json. Giữ nguyên toàn bộ 10 linh kiện, vị trí và dây nối: ESP32, HX711, HC-SR04, hai servo, OLED, nút bấm, hai LED và còi.

## Mở đúng dự án

Trên máy Long, mở D:\long2026\IOT\PetFeeder_Main_Long\PetFeeder_Main_Long.code-workspace.

| Linh kiện | GPIO giữ theo main |
|---|---|
| HC-SR04 TRIG / ECHO | 5 / 18 |
| HX711 DT / SCK | 19 / 23 |
| Servo cấp / chống kẹt | 13 / 12 |
| OLED SDA / SCL | 21 / 22 |
| Nút bấm | 4 |
| LED xanh / LED đỏ / còi | 2 / 15 / 14 |

## Chạy mạch và app

Cần Node.js >=22.13, Flutter SDK, PlatformIO và Wokwi Simulator có license hợp lệ.

1. Trong petfeeder_backend: npm ci, rồi npm start. Backend ở http://127.0.0.1:3000.
2. Trong petfeeder_app: flutter pub get, rồi flutter run -d chrome --dart-define=API_URL=http://127.0.0.1:3000.
3. Trong PetFeeder: pio run. Trên máy Long có thể chạy CHAY.ps1 -Mode build từ thư mục gốc.
4. Mở PetFeeder/diagram.json, F1 → Wokwi: Start Simulator.
5. Nếu Serial báo STORAGE_NOT_INITIALIZED, gửi INIT_NEW_DEVICE để tạo bộ nhớ thiết bị mới. Lệnh này format bộ nhớ; không dùng trong bài giữ dữ liệu qua reset.
6. Gửi status, chờ time_valid=1 và MQTT kết nối. Trên app, vào Cài đặt, nhập tên thức ăn, xác nhận đã kiểm tra và lưu. Chờ CONFIG_APPLIED hoặc xem config_version trong /api/state.
7. Cấp 20g từ app hoặc nhấn nút; xem OLED, Serial và Nhật ký. API nhận lệnh chưa phải kết quả SUCCESS.

Broker và prefix giữ theo main: broker.emqx.io:1883, duylinh0212/petfeeder/v1. Có thể sao chép petfeeder_backend/.env.example thành .env và PetFeeder/include/secrets.example.h thành secrets.h để đặt broker riêng. Broker và prefix hai phía phải khớp; chỉ chạy một phiên mạch cùng device/topic.

Để backend phục vụ giao diện tại /, chạy flutter build web --no-wasm-dry-run --no-web-resources-cdn trong petfeeder_app trước. Android Emulator dùng http://10.0.2.2:3000. Điện thoại thật dùng IP LAN máy tính trong Cài đặt; backend phải chạy với HOST=0.0.0.0.

## Hai chế độ trên cùng mạch

DEMO_AUTO giữ cách main tự mô phỏng hạt rơi: mỗi xung cộng tối đa 5g vào bát và trừ kho. OLED và app ghi rõ số liệu demo. Đây không phải bằng chứng HX711 hay cơ cấu thật đã đo/cấp chính xác.

Gửi sim manual trên Serial để thử cảm biến bằng tay. Chỉnh HC-SR04 còn hạt, đợi cân ổn định rồi yêu cầu cấp. Khi servo chạy, tăng HX711 từ 0kg tới 0.020kg và giữ ổn định ít nhất 0,7 giây để thử 20g. Cân không tăng sẽ kích hoạt chống kẹt rồi có thể trả JAM_ERROR. Tải HX711 là tổng khối lượng bát, còn khẩu phần là lượng cấp thêm.

| Serial | Tác dụng |
|---|---|
| status | Cân, hiệu chuẩn, giờ hợp lệ, busy |
| sim auto / sim manual | Chọn nguồn dữ liệu Wokwi khi không cấp |
| sim empty | Dọn bát demo auto, không xóa tổng đã cấp |
| sim jam on / sim jam off | Bật/tắt tình huống không rơi hạt trong demo auto |
| food CONFIRMED | Chủ xác nhận thức ăn qua Serial; app sync có thể ghi đè |
| tare EMPTY | Lưu offset khi bát rỗng; không tự chạy lúc boot |
| factor N | Đổi hệ số cân rồi hiệu chuẩn lại |
| reconcile CHECKED | Sau kiểm tra phiên gián đoạn, mở khóa và giữ dự trù khẩu phần ngày |

Thiết bị thật: bỏ build flag WOKWI_SIM=1, hiệu chuẩn cân và kiểm tra cơ cấu. Chưa có RTC, camera hoặc RFID.

## Các phần Long đã ghép

- C01/C06: kiểm tra yêu cầu xác minh thú và xác nhận thức ăn của chủ. Chưa có nhận dạng thú hoặc phân loại thức ăn bằng cảm biến.
- C02: khoảng chờ, hạn mức mỗi lần/ngày và dự trù phiên đang cấp. Mọi nút cấp đều qua kiểm tra; không có override vượt các giới hạn này.
- C04/N15: ghi nhận còn thức ăn, cân giảm chưa rõ nguyên nhân, mất số đo và nhắc kiểm tra thức ăn cũ. Quan sát nằm trong cảnh báo/sự kiện; không kết luận thú đã ăn chỉ từ cân giảm.
- N16–N18: LittleFS lưu mã phiên, kết quả, lịch, hiệu chuẩn và dự trù; đóng servo lúc boot, khóa phiên gián đoạn chờ kiểm tra, không tare lúc boot.
- N19–N23: lịch chạy offline khi còn giờ hợp lệ; lọc CN=0 đến T7=6; giữ dấu đã chạy qua sync/reset; bỏ lịch trễ từ 60 giây, không cấp dồn; đối soát tối đa 7 ngày.
- N24/N25: app lưu ID và payload trước khi gửi, retry giữ nguyên cả thời hạn; API và ESP32 cùng kiểm tra hạn.
- N26/N27: event_id chống ghi trùng, giữ trạng thái cuối trước sự kiện tiến độ muộn, outbox chờ ACK đã lưu, bỏ retained replay; MQTT/heartbeat chạy trong lúc cấp và chống kẹt.
- N28: kiểm tra dữ liệu ở API và ESP32; giữ null khi lượng chưa xác định.

POST /api/feeding/feed yêu cầu command_id, portion, override:false, created_at và expires_at. Lấy ID/giờ tại /api/id. Dùng nút Gửi lại cùng mã khi phản hồi chưa rõ. Cấu hình/lịch dùng /sync, sự kiện dùng /events và xác nhận dùng /ack trên cùng prefix MQTT. App main đã đổi tương ứng.

## Kiểm tra

Ngày 21/10/2026: firmware ESP32 build thành công, có firmware.merged.bin. 25 bài Node đã qua, gồm mô hình 18 case, REST app main, so sánh mạch gốc và MQTT cục bộ. Flutter analyze không báo vấn đề; 3 bài Flutter đã qua; Web build thành công.

Chưa ghi nhận chạy đủ 18 case trên Wokwi sau ghép. Cắt nguồn, độ bền flash, hiệu chuẩn và cơ cấu cần thử thực tế. File Word trước đó mô tả bản độc lập; dùng hướng dẫn main này khi thử mạch chung.

Chạy lại: npm test trong petfeeder_backend; flutter analyze và flutter test trong petfeeder_app; pio run trong PetFeeder.
