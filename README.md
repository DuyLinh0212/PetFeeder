# PetFeeder Nhóm 7 — hệ thống cho thú cưng ăn tự động

## Camera YOLO chó/mèo

Camera Flutter → REST `/api/vision/detect` → YOLO11n trên laptop (cổng 8002). Đã kèm code AI và model tại `YOLO_PetFeeder/models/yolo11n.pt`. Backend mặc định gọi `http://127.0.0.1:8002`, có thể đổi bằng `YOLO_URL`.

Tại thư mục PetFeeder, chạy ba terminal: `./CHAY.ps1 -Mode yolo`, `./CHAY.ps1 -Mode backend`, và `./CHAY.ps1 -Mode app`. Lần đầu cần Python và các thư viện trong `YOLO_PetFeeder/requirements.txt`. Trong app chọn **Cài đặt → Camera · YOLO chó/mèo → Mở camera thật**, cho phép camera rồi đưa chó/mèo hoặc ảnh chó/mèo vào khung hình. App hiển thị nhãn và độ tin cậy thực của model; ảnh chỉ gửi đến YOLO trên laptop.

Model nhận diện loài, chưa xác minh danh tính từng con thú và chưa phân biệt ảnh chụp với thú thật. Kết quả AI tự động cho qua bước phát hiện thú sau 2 khung ảnh liên tiếp đạt từ 50%; mất thú, tắt camera hoặc kết quả quá 5 giây sẽ chặn lệnh mới. Đã bỏ các nút giả lập và vô hiệu endpoint xác minh thủ công. AI không tự phát lệnh cấp; chủ vẫn cần yêu cầu cấp hoặc dùng lịch. Các giới hạn thức ăn/khẩu phần/thời gian chờ trên backend và ESP32 được giữ nguyên.

Thành viên: Nguyễn Duy Linh, Ngô Công Danh, Lê Hoàng Bảo Long.

Tích hợp giao diện `feature/mobile-ui`, bảo vệ `feature/firmware-safety-and-dispensing` và lưu trữ/giao thức của `long` trên main. Flutter → REST API Node.js → MQTT → ESP32. Chỉ có một sơ đồ PetFeeder/diagram.json; giữ nguyên toàn bộ 10 linh kiện, vị trí và dây nối: ESP32, HX711, HC-SR04, hai servo, OLED, nút bấm, hai LED và còi.

## Mở đúng dự án

Mở `PetFeeder_Main_Long.code-workspace` tại thư mục repository. Flutter SDK và PlatformIO lấy từ môi trường máy, không dùng đường dẫn riêng của thành viên.

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
5. Wokwi tự khởi tạo khi toàn bộ phân vùng LittleFS còn trắng; không cần gõ INIT_NEW_DEVICE cho mô phỏng mới. Nếu đã có dữ liệu thì giữ nguyên và chỉ mount lại. Bộ nhớ có dữ liệu nhưng lỗi đọc vẫn khóa cấp; firmware không tự format. Thiết bị thật mới chỉ được khởi tạo thủ công bằng INIT_NEW_DEVICE sau khi xác nhận không có dữ liệu cần giữ.
6. Wi-Fi và MQTT tự kết nối khi chạy; chờ dòng MQTT_CONNECTED và OLED MQTT: ON. Có thể gõ status trong Wokwi Terminal để kiểm tra time_valid=1, wifi=1, mqtt=1; firmware hiện ký tự đang gõ và nhận Enter CR/LF. Trên app, vào Cài đặt, nhập tên thức ăn, xác nhận đã kiểm tra và lưu. Chờ CONFIG_APPLIED hoặc xem config_version trong /api/state.
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

Thiết bị thật: build `pio run -e esp32dev-hardware`, hiệu chuẩn cân và kiểm tra cơ cấu. Wokwi dùng `pio run -e esp32dev` (mặc định), với firmware.merged.bin riêng. Chưa có RTC, camera, RFID hoặc cảm biến hiện diện bát chuyên dụng.

## Hành vi sau tích hợp

- Giữ bốn tab, trạng thái tab đã mở, giao diện tiếng Việt và kiểm tra kết nối trước khi lưu địa chỉ. Địa chỉ và yêu cầu cho ăn chưa rõ kết quả được lưu qua lần mở app tiếp theo.
- Khoảng chờ 180 giây là bắt buộc theo C03; không có nút ép cấp hoặc nhấn giữ để vượt bảo vệ. API vẫn nhận trường `override` và từ chối `true` bằng `OVERRIDE_NOT_SUPPORTED`.
- Khẩu phần là lượng **cấp thêm**. Mặc định bát tối đa 150g, tối đa 200g/ngày, 6 phiên/ngày, 15 nhịp/phiên; kiểm tra bát trước khi cấp. Các ngưỡng này nằm trong cấu hình chung của API và firmware.
- Cấp thô/tinh, chờ cân ổn định, dừng khi cân giảm bất thường, lỗi cảm biến, hết hạt, quá lượng hoặc hết nhịp. Không báo SUCCESS cho phiên cấp thiếu/quá lượng.
- “Gửi lại cùng mã” chỉ gửi lại payload cũ, không cấp một bữa mới. “Cấp phần còn thiếu” trong Nhật ký tạo yêu cầu có `retry_of` cho đúng phần còn thiếu của phiên PARTIAL/JAM_ERROR/TIMEOUT đã biết lượng thực cấp; không tự gửi, không dùng khi lượng chưa xác định và không cấp bù trùng cùng phiên.
- Giữ tối đa 10 lịch; lịch, chống lặp, hạn mức, hiệu chuẩn, outbox và phiên gián đoạn tồn tại qua reset. Các sự kiện cân tăng/giảm ngoài phiên và theo dõi thức ăn cũ vẫn được ghi riêng.
- Backend tự nhập dữ liệu `data/database.json` sang SQLite một lần, giữ nguyên tệp gốc, lịch, lịch sử, cảnh báo và trạng thái đã đọc. Xóa nhật ký chỉ ẩn hàng, không xóa khóa chống lặp hoặc hạn mức.

## Các phần Long đã ghép

- C01/C06: kiểm tra yêu cầu xác minh thú và xác nhận thức ăn của chủ. Chưa có nhận dạng thú hoặc phân loại thức ăn bằng cảm biến.
- C02: khoảng chờ, hạn mức mỗi lần/ngày và dự trù phiên đang cấp. Mọi nút cấp đều qua kiểm tra; không có override vượt các giới hạn này.
- C04/N15: ghi nhận còn thức ăn, cân giảm chưa rõ nguyên nhân, mất số đo và nhắc kiểm tra thức ăn cũ. Quan sát nằm trong cảnh báo/sự kiện; không kết luận thú đã ăn chỉ từ cân giảm.
- N16–N18: LittleFS lưu mã phiên, kết quả, lịch, hiệu chuẩn và dự trù; đóng servo lúc boot, khóa phiên gián đoạn chờ kiểm tra, không tare lúc boot.
- N19–N23: lịch chạy offline khi còn giờ hợp lệ; lọc CN=0 đến T7=6; giữ dấu đã chạy qua sync/reset; bỏ lịch trễ từ 60 giây, không cấp dồn; đối soát tối đa 7 ngày.
- N24/N25: app lưu ID và payload trước khi gửi, retry giữ nguyên cả thời hạn; API và ESP32 cùng kiểm tra hạn.
- N26/N27: event_id chống ghi trùng, giữ trạng thái cuối trước sự kiện tiến độ muộn, outbox chờ ACK đã lưu, bỏ retained replay; MQTT/heartbeat chạy trong lúc cấp và chống kẹt.
- N28: kiểm tra dữ liệu ở API và ESP32; giữ null khi lượng chưa xác định.

POST /api/feeding/feed yêu cầu command_id, portion, override:false, created_at và expires_at; `retry_of` là tùy chọn khi cấp phần còn thiếu. Lấy ID/giờ tại /api/id. Dùng nút Gửi lại cùng mã khi phản hồi chưa rõ. Cấu hình/lịch dùng /sync, sự kiện dùng /events và xác nhận dùng /ack trên cùng prefix MQTT. Xem [giao thức backend](petfeeder_backend/README.md).

## Kiểm tra

Chạy lại: `npm ci` và `npm test` trong petfeeder_backend; `flutter pub get`, `flutter analyze`, `flutter test`, `flutter build apk --release` và `flutter build web --no-wasm-dry-run --no-web-resources-cdn` trong petfeeder_app; `pio run -e esp32dev -e esp32dev-hardware` trong PetFeeder.

Xem [bảng đối chiếu đủ 36 case và kết quả kiểm tra](MERGE_VALIDATION.md). Test dùng mô hình thiết bị và broker MQTT cục bộ; không phát lệnh lên máy cho ăn thật. Chưa xác nhận các kịch bản trên phần cứng/Wokwi tương tác. Cắt nguồn, độ bền flash, hiệu chuẩn và cơ cấu cần thử thực tế.
