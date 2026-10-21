# Kiểm chứng tích hợp ba nhánh — 21/10/2026

Nguồn: main `41c0e7a`, firmware `19d5f4a`, mobile `e170220`, long `f522ae9`.
Merge giữ lịch sử; nhánh mobile đã chứa các commit firmware. Tài liệu 36 case do chủ dự án cung cấp là tiêu chí xử lý hành vi khác nhau.

## Quyết định tích hợp

- Giữ giao diện, bốn tab, trạng thái tab, kiểm tra địa chỉ và timeout của mobile. Ghép lưu kết nối, mã lệnh bền vững và cấu hình an toàn của Long.
- Giữ bộ điều khiển không chặn, LittleFS, SQLite, lịch offline, outbox/ACK, chống lặp và thời hạn lệnh của Long. Ghép cấp thô/tinh, sức chứa bát, giới hạn số lần/ngày và nhịp cấp, chống kẹt, theo dõi biến động bát của firmware.
- Theo C03/C05: khoảng chờ bảo vệ bắt buộc, mặc định 180s; `override:true` bị từ chối, không có nút ép cấp. Không bỏ qua lỗi cảm biến, khóa cấp hoặc hạn mức.
- Khẩu phần là lượng cấp thêm; không âm thầm cộng đủ khẩu phần khi vượt sức chứa bát. Cấp bù có xác nhận, chỉ phần còn thiếu đã biết, ID mới và `retry_of`; gửi lại qua mạng giữ nguyên ID/payload cũ.
- Mặc định: tối đa 100g/yêu cầu (có thể cấu hình), bát 150g, 200g/ngày, 6 phiên/ngày, 15 nhịp/phiên, ngưỡng chuyển nhịp tinh 10g, 3 lần chống kẹt. API, mô hình và ESP32 dùng cùng cấu hình; tối đa 10 lịch.
- Lượng đã cấp trước lỗi vẫn được tính vào tổng ngày. Lượng không xác định giữ null và dự trù bảo thủ, không biến thành 0g. Xóa nhật ký/cảnh báo chỉ ẩn, giữ dữ liệu chống lặp.
- JSON cũ nhập một lần bằng transaction, giữ nguyên tệp gốc và ID dữ liệu; nhập lỗi không tạo trạng thái nhập dở. Cập nhật state ESP32 cũ không reset lịch, hiệu chuẩn hoặc hạn mức.

## Kết quả tự động

| Kiểm tra | Kết quả |
|---|---|
| Node.js 24.14.0, `npm ci`, `npm test` | 37/37 đạt; gồm 25 bài gốc của Long và 12 bài hồi quy tích hợp/chuyển dữ liệu |
| Flutter 3.38.7 / Dart 3.10.7, `flutter analyze` | Không có vấn đề |
| `flutter test` | 19/19 đạt; gồm các bài gốc của hai nhánh và kiểm tra lưu kết nối, lệnh chưa rõ kết quả, số đo chưa biết, cấp bù, cấu hình an toàn trên màn hình hẹp/chữ lớn |
| `flutter build web --no-wasm-dry-run --no-web-resources-cdn` | Thành công |
| `flutter build apk --release` | Build local gặp cache Kotlin khác ổ đĩa (Pub cache C:, dự án F:); theo yêu cầu chủ dự án, xác minh APK bằng CI/CD Ubuntu sau push main |
| `pio run -e esp32dev -e esp32dev-hardware` | Cả hai thành công; có firmware.bin và firmware.merged.bin cho từng môi trường |
| Giao diện | Đã xem ảnh dựng; kiểm tra 320/390/768px, chữ đến 200%, trạng thái tab, màn hình đầu, bàn phím sheet lịch và các thao tác đang chờ |
| Mạch | Test xác nhận giữ nguyên các linh kiện, vị trí, toàn bộ dây nối và hai servo so với main gốc |

MQTT kiểm tra bằng broker Aedes cục bộ, transport giả và cơ sở dữ liệu tạm; không phát lệnh lên thiết bị thật. Mô hình JavaScript kiểm chứng hợp đồng/chính sách, không mô phỏng thời gian điện hay thay thế chạy firmware trên ESP32.

## Đối chiếu đủ 36 case

“Tự động” dưới đây nghĩa là test mô hình/API/MQTT/Flutter tương ứng đã chạy. Mọi phần cơ khí, độ chính xác đo, flash và mất điện vật lý vẫn cần thử trên thiết bị.

| Case | Hành vi được giữ/tích hợp và bằng chứng | Giới hạn kiểm chứng |
|---|---|---|
| C01 | Bật yêu cầu nhận diện sẽ từ chối UNKNOWN_PET; test chính sách | Chưa có RFID/camera, chưa nhận diện thật |
| C02 | Kiểm tra khẩu phần, khoảng chờ, dự trù/tổng ngày và lượng bát; test C02, N01/N02 | Không suy ra thú đói từ lệnh |
| C03 | Khóa phiên chung, chống lặp ID và khoảng chờ bắt buộc; test đồng thời/replay và UI | Cần thử dội nút vật lý |
| C04 | FOOD_LEFT/WEIGHT_DECREASED/UNKNOWN là quan sát riêng, không ghi thú đã ăn; test C04 | Chưa xác định được nguyên nhân ăn/đổ hạt bằng cân |
| C05 | Hết hạt khác lỗi cảm biến, dừng/cấp thiếu khi lỗi; test cảm biến và PARTIAL | Cần thử hộp thật hết hạt giữa phiên |
| C06 | Chủ xác nhận loại thức ăn và nhãn; thiếu xác nhận trả UNVERIFIED; test C06 | Chưa có phân loại thức ăn tự động |
| C07 | Nguồn hạt chưa xác nhận bị chặn; giữ xác nhận của chủ, khóa cấp | Chưa có cảm biến nắp/dị vật; không tự phát hiện lần nạp mới |
| C08 | Không tuyên bố thức ăn an toàn từ cân/siêu âm; khóa cấp ngăn lệnh và dừng phiên; test lockdown | Chưa phát hiện độc chất/vi sinh |
| N01 | Lượng cấp thêm, kiểm tra sức chứa bát trước cấp; test BOWL_FULL | Cần hiệu chuẩn bát/cân thực tế |
| N02 | Giới hạn gram và số phiên trong ngày, còn qua reboot và đổi ngày; test hạn mức | Dự trù giữ bảo thủ khi chưa biết lượng thật |
| N03 | App/nút/lịch dùng một phiên; lệnh khác khi bận bị chặn; test ba nguồn | Cần thử cạnh tranh nguồn trên ESP32 thật |
| N04 | Giữ lượng thực cấp khi kẹt; cấp bù chỉ phần thiếu với retry_of, không nhận bù trùng; test mô hình và REST | Firmware chỉ đối soát được phiên còn trong lịch sử cục bộ; không tự cấp bù khi lượng chưa rõ |
| N05 | Giới hạn nhịp/thời gian, trả PARTIAL/TIMEOUT; test giới hạn nhịp | Mô hình không kiểm chứng xung điện servo |
| N06 | Nhịp thô/tinh, chờ ổn định và OVER_PORTION riêng; test quá lượng + build firmware | Quán tính hạt và độ chính xác phải thử cơ cấu thật |
| N07 | Cân giảm bất thường khi cấp thì dừng, lượng chưa biết giữ null; test can thiệp cân | Không khẳng định thú đang ăn chỉ từ cân giảm |
| N08 | Cửa sổ mẫu cân và chờ ổn định có thời hạn, lỗi đo khi dao động; test mô hình | Cần kiểm tra nhiễu/rung thực tế |
| N09 | Mô hình có đầu vào bát vắng và test dừng; firmware giữ phát hiện cân âm sâu nghi mất bát | CHƯA ĐỦ PHẦN CỨNG để xác nhận hiện diện bát đáng tin cậy |
| N10 | HX711 lỗi/chưa sẵn sàng khác 0g; ngừng cấp khi mất đo; test cảm biến | Chưa rút dây HX711 thực tế |
| N11 | Siêu âm đọc lại có giới hạn, timeout khác EMPTY; test trạng thái | Chưa kiểm tra tín hiệu echo trên mạch |
| N12 | Chống kẹt hữu hạn, đóng cơ cấu khi JAM_ERROR; test mô hình + build firmware | Cần thử kẹt thật, hai servo và lực cơ khí |
| N13 | Cân tăng ngoài phiên sinh MANUAL_REFILL riêng; test thay đổi cân | Không xác định được chủ/loại vật chỉ từ cân tăng |
| N14 | Cân giảm ngoài phiên ghi WEIGHT_DECREASED/UNKNOWN_CAUSE; test quan sát | Chưa phân biệt thú ăn với bị đổ/lấy đi |
| N15 | Thức ăn còn lâu sinh một cảnh báo, bát rỗng reset theo dõi; test FOOD_STALE | Cần thử thời gian dài trên thiết bị |
| N16 | Giữ ID/kết quả/cooldown qua reboot; test lưu trữ | Chưa cắt điện vật lý/đo độ bền flash |
| N17 | Boot đóng servo, phiên đang cấp thành INTERRUPTED, khóa chờ đối soát; test reboot giữa phiên | Chưa cắt nguồn đúng lúc ghi flash/servo mở |
| N18 | Không tare lúc boot; tare EMPTY là thao tác hiệu chuẩn riêng; test mô hình + rà soát/build firmware | Cần cân thật để xác nhận hiệu chuẩn |
| N19 | Lịch lưu bền, chạy offline khi giờ hợp lệ, sự kiện xếp outbox; test offline/replay | Không có RTC; không bảo đảm lịch sau mất điện khi chưa lấy lại giờ |
| N20 | Giờ chưa hợp lệ trả TIME_INVALID, không chạy lịch; test thời gian | Chưa có RTC dự phòng |
| N21 | API/firmware kiểm tra days, lọc đúng thứ, không cắt mất lịch thứ 9/10; test ngày và 10 lịch | Chưa chạy đủ tuần trên ESP32 |
| N22 | Giữ khóa lịch + ngày qua sync/reboot; test dấu đã chạy | Cần thử reset vật lý quanh giờ lịch |
| N23 | Giữ cửa sổ trễ 60s, đối soát tối đa 7 ngày; MISSED_SCHEDULE, không cấp dồn; test lịch quá hạn | Hiện giữ các cửa sổ của Long; chưa có giao diện chỉnh hai giá trị này |
| N24 | App lưu ID/payload trước gửi; restart/retry cùng ID không tạo phiên mới, body khác bị chặn; test API/Flutter | Không tự gửi lại lệnh chưa rõ kết quả khi nhấn tạo bữa mới |
| N25 | API và ESP32 kiểm tra hạn; lệnh cũ mới đến không chạy; test hết hạn | Replay ID đã hoàn tất chỉ trả kết quả cũ |
| N26 | event_id duy nhất, ACK sau commit, bỏ retained, giữ trạng thái cuối; test MQTT/SQLite restart | Chưa thử broker mất điện thật |
| N27 | MQTT/heartbeat tiếp tục trong phiên và chống kẹt; BUSY khác OFFLINE; test heartbeat dài | Chưa đo độ trễ trên mạng/mạch thật |
| N28 | Kiểm tra kiểu/miền dữ liệu ở API và firmware; không âm thầm cấp bằng mặc định; test dữ liệu sai | Firmware đã build, chưa fuzz trực tiếp trên ESP32 |

## Các phần chưa được coi là hoàn thành bằng phần mềm

Nhận diện thú, phát hiện vật nạp/chất độc, xác nhận bát hiện diện bằng cảm biến chuyên dụng, RTC sau mất điện và kiểm thử mất điện/flash/cơ khí chưa có bằng chứng phần cứng ở các nhánh. Bản tích hợp giữ luồng từ chối/an toàn, không tự khẳng định đã có các khả năng này. Hành vi suy đoán bát qua cân âm chỉ là dấu hiệu, không thay cảm biến hiện diện.

Không tự format LittleFS hoặc nạp firmware khi kiểm chứng merge. `INIT_NEW_DEVICE` chỉ dành cho thiết bị mới; `reconcile CHECKED` chỉ dùng sau kiểm tra thật. Cập nhật backend/app/firmware cùng phiên bản vì hợp đồng lệnh thống nhất yêu cầu ID và thời hạn.
