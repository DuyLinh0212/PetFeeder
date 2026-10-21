# PetFeeder phần Lê Hoàng Bảo Long

Bản triển khai độc lập gồm app Flutter, backend Node.js và firmware ESP32/Wokwi cho 18 case C01, C02, C04, C06, N15–N28. Các thư mục ở gốc repository là bản tích hợp nhóm; chạy bản này từ thư mục `PetFeeder_Long/`.

## Chuẩn bị

- Node.js >=22.13, Flutter SDK và PlatformIO trong PATH.
- Wokwi Simulator có license hợp lệ để mô phỏng trong VS Code.
- Trong `petfeeder_backend`: chạy `npm ci`.
- Trong `petfeeder_app`: chạy `flutter pub get`, rồi `flutter build web --no-wasm-dry-run --no-web-resources-cdn`.

## Chạy demo

Từ thư mục này, mở PowerShell và chạy:

```powershell
powershell -ExecutionPolicy Bypass -File .\CHAY_DEMO.ps1 -Mode demo
```

Mở http://127.0.0.1:8080 để xem Flutter. Nếu chưa build Flutter, mở http://127.0.0.1:8080/debug để dùng bảng thử API. Có thể đổi cổng bằng `$env:PORT='8090'` trước khi chạy.

Vào Cài đặt, xác nhận đã kiểm tra thức ăn và lưu. Giữ yêu cầu nhận diện thú tắt khi thử cấp bình thường: bản này chưa có camera/RFID; bật yêu cầu nhận diện sẽ bị từ chối UNKNOWN_PET. DEMO là mô hình phần mềm, chưa phải mạch Wokwi.

## Chạy mạch Wokwi

1. Dừng demo; từ thư mục này chạy `CHAY_DEMO.ps1 -Mode broker` trong Terminal 1 và `CHAY_DEMO.ps1 -Mode mqtt` trong Terminal 2.
2. Trong thư mục `PetFeeder`, chạy `pio run` để build firmware.
3. Mở thư mục `PetFeeder` trong VS Code, F1 → Wokwi: Start Simulator.
4. Broker mặc định là `host.wokwi.internal:1883`; cần gateway Wokwi phù hợp để kết nối broker trên máy.
5. Chỉ ở bộ nhớ mới: nếu báo STORAGE_NOT_INITIALIZED, gửi `INIT_NEW_DEVICE` để khởi tạo. Chờ giờ hợp lệ, xác nhận thức ăn từ app.
6. Khi servo mở, chỉnh HX711 từ 0kg lên 0.020kg và giữ ổn định để mô phỏng cấp 20g. Wokwi không tự làm tăng cân theo servo.

Có thể chép `PetFeeder/include/secrets.example.h` thành `secrets.h` để tùy chỉnh broker/device ID. Không đưa mật khẩu hay file secrets.h lên Git. Sau mất điện và chưa đồng bộ giờ, thiết bị chờ TIME_INVALID; chưa có RTC.

## Kiểm tra

```powershell
# Chạy từ thư mục này
$env:HOST='127.0.0.1'
powershell -ExecutionPolicy Bypass -File .\CHAY_DEMO.ps1 -Mode test
# Trong petfeeder_app
flutter analyze
flutter test
```

`tools/TEST_TAY.ps1` chứa hàm hỗ trợ API/MQTT. Các tài liệu trong `docs/` mô tả giao tiếp MQTT, vị trí xử lý 18 case và kết quả kiểm tra. File Word được lưu riêng. Build và test phần mềm không thay thế kiểm thử Wokwi/ESP32 thật.
