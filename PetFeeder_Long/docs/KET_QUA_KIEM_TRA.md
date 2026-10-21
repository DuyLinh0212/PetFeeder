# Kết quả kiểm tra — 20/10/2026 (UTC+7)

Đây là kết quả thực tế đã chạy trong lần tạo dự án, tách khỏi 18 kịch bản kết quả mong đợi.

| Kiểm tra | Kết quả |
|---|---|
| Node `node --test test/*.test.js` | **24/24 PASS** sau cập nhật giao diện mobile |
| Flutter `flutter analyze` | **No issues found** |
| Flutter `flutter test` | **4/4 PASS** sau cập nhật giao diện mobile |
| Flutter `flutter build web --no-wasm-dry-run --no-web-resources-cdn` | **SUCCESS** |
| Android Gradle `assembleDebug` | **BUILD SUCCESSFUL**; APK debug đã tạo, chưa cài/chạy trên điện thoại thật |
| PlatformIO ESP32 `python -m platformio run` | **SUCCESS**, RAM 46.432 byte, flash 869.153 byte |
| Image ghép bootloader/partition/app | `firmware.merged.bin` đã được tạo |
| HTTP server thật trên cổng tạm | PASS: trả UI, validation, cấp 20g, retry, reboot mô hình, giữ một phiên/lịch sử |
| Broker MQTT cục bộ thật (Aedes) | PASS: truyền lệnh, gửi event 3 lần chỉ lưu 1, ACK, bỏ retained event phát lại khi subscribe |
| Trình duyệt bảng điều khiển demo | Đã lưu xác nhận, cấp 20g, bấm gửi lại cùng mã; trả SUCCESS cũ, không thêm phiên cấp |
| App Flutter Web trong trình duyệt | Đã tải và hiển thị dashboard, kết nối API ở chế độ DEMO; ảnh `FLUTTER_PREVIEW.png` |

## Cập nhật bố cục điện thoại

- Trang gốc `http://127.0.0.1:8080` phục vụ app Flutter đã build; bảng HTML kiểm thử cũ chuyển sang `/debug`.
- Bố cục một cột, khung xem trước máy tính tối đa 460px, thanh điều hướng dưới với 4 tab Trang chủ/Lịch ăn/Lịch sử/Cài đặt. JSON chỉ còn trong chi tiết kỹ thuật, công cụ mô phỏng trong mục nâng cao.
- Đã kiểm thử ở màn hình 320×740, chữ phóng 130%, chuyển tab và mở sheet thêm lịch: không tràn bố cục.
- Đã kiểm thử mất kết nối API sau lần tải đầu: bỏ nhãn đã kết nối, báo dữ liệu cũ và khóa nút cấp.
- Tổng ngày được tính từ toàn bộ phiên đã xác nhận, không bị giới hạn bởi danh sách 100 phiên gần nhất; có test 105 phiên.
- App vẫn là mã Flutter, có target Android mới và bản xem trước Web. Ảnh mới `FLUTTER_MOBILE.png`.

## Phạm vi kiểm thử tự động

Test Node có bài cho từng C01/C02/C04/C06/N15–N28, thêm kiểm tra SQLite sau mở lại, mất số cân, cấu hình cập nhật trong BUSY, HTTP thật và MQTT thật.

Bốn test Flutter kiểm tra:

1. Timeout sau gửi cấp → tạo lại API service như sau đóng/mở app → retry giữ nguyên `command_id`, khẩu phần và hạn lệnh từ SharedPreferences.
2. Dashboard hiển thị cân chưa xác định và không gắn nhãn “đã cho ăn thành công” chỉ vì nhận yêu cầu.
3. Bố cục điện thoại 320px với chữ 130%, chuyển tab và mở màn hình thêm lịch không bị tràn.
4. Mất backend sau khi đã có dữ liệu phải bỏ trạng thái online và khóa nút cấp.

Test mô hình N18 giữ đầu vào cảm biến qua reboot; nó **không** chứng minh HX711 vật lý được hiệu chuẩn đúng. Kiểm thử trên MQTT dùng client giả thiết bị để kiểm tra transport/backend, không chạy firmware ESP32.

## Chưa kiểm tra thực tế

- Chưa chạy simulator Wokwi trong VS Code: không có phiên Wokwi/giấy phép hoặc token được xác nhận cho lần chạy này. Đã chuẩn bị sơ đồ, image và hướng dẫn khởi động; không đánh dấu 18 case Wokwi là đã PASS.
- Chưa cắt nguồn ESP32 thật, đo độ bền LittleFS/flash, kiểm chứng cân, cơ cấu, kẹt hạt hoặc heartbeat trong phiên Wokwi.
- Chưa có camera/RFID, cảm biến bát hiện diện, RTC hoặc phần cứng phân loại thức ăn/chất độc.
- Chưa ghép firmware cuối của Danh; driver trong bản này là nền demo có giới hạn thời gian/khẩu phần.

Vì vậy có thể dùng bản này để xem code, chạy app/backend và bắt đầu mô phỏng; cần thực hiện tiếp các bước phần cứng được ghi trong bản Word 18 kịch bản kiểm thử trong thư mục gốc trước khi báo cáo chúng đã chạy thành công.
