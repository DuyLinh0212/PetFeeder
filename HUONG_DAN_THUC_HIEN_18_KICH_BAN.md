# Hướng dẫn thực hiện 18 kịch bản PetFeeder

Tài liệu này đối chiếu `Danh_18KichBan.docx` với source hiện tại. Phạm vi gồm C03, C05, C07, C08 và N01–N14. Đây là hướng dẫn chuẩn bị và kiểm tra, không phải biên bản xác nhận đã chạy đạt. Không thay đổi firmware, backend hay chức năng mobile trong lần đối chiếu này.

## 1. Chuẩn bị hệ thống

1. Terminal thứ nhất: vào `D:\IoT\PetFeeder\petfeeder_backend`, chạy `npm install` nếu chưa cài thư viện, rồi `npm start`.
2. Mở `http://localhost:3000/health`, xác nhận API hoạt động và kiểm tra `mqtt_connected`.
3. Mở thư mục `D:\IoT\PetFeeder\PetFeeder` trong VS Code. Cần PlatformIO và Wokwi. Build trước khi chạy mô phỏng:

```powershell
cd D:\IoT\PetFeeder\PetFeeder
& "$env:USERPROFILE\.platformio\penv\Scripts\platformio.exe" run
```

4. Nhấn F1, chọn `Wokwi: Start Simulator`. Theo dõi Serial ở 115200 baud và OLED. Backend và firmware hiện dùng `broker.emqx.io:1883`, topic gốc `duylinh0212/petfeeder/v1`.
5. Để xem kết quả trên điện thoại Android qua USB, bật gỡ lỗi USB, kết nối điện thoại rồi chạy:

```powershell
$adb = "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe"
& $adb devices
& $adb reverse tcp:3000 tcp:3000
cd D:\IoT\PetFeeder\petfeeder_app
flutter run
```

Trong app chọn địa chỉ máy chủ `http://localhost:3000` và nhấn **Lưu kết nối**. Giữ backend, mô phỏng và kết nối USB hoạt động.

Mỗi case lưu ba loại bằng chứng: Serial/OLED, payload MQTT `FEED_RESULT` hoặc `BOWL_EVENT`, và nhật ký/cảnh báo backend. Kết quả HTTP gửi lệnh thành công chỉ xác nhận máy chủ nhận yêu cầu; cần sự kiện từ ESP32 để kết luận phiên cấp.

## 2. Các điểm phải hiểu trước khi thử

### Cân Wokwi chưa được chuẩn hóa sang gram

`diagram.json` dùng HX711 với thuộc tính mặc định. Tài liệu Wokwi cho biết loại mặc định là 50 kg, raw từ 0 đến 21000. Firmware gọi `set_scale()` không truyền hệ số, sau đó lấy kết quả chia 420 và gắn đơn vị gram. Với toàn dải mặc định, phép tính này chỉ cho khoảng 0–50 đơn vị sau khi tare ở tải 0, không phải 0–50000 g. Vì thế không thể coi giá trị trên thanh trượt là số gram OLED, hoặc yêu cầu kéo đến 135 g theo Word mà chưa kiểm tra hiệu chuẩn.

Trước các case cân, cần xác nhận tải điều khiển tương ứng bao nhiêu gram trên OLED/Serial. N01 yêu cầu 135 g, các case lỗi/quá lượng và các giá trị âm cần nguồn số đo kiểm thử phù hợp. Nếu chưa hiệu chuẩn hoặc chưa có bộ điều khiển số đo, ghi **chưa đủ điều kiện**, không ghi đạt.

Nguồn: https://docs.wokwi.com/parts/wokwi-hx711 ; mã `readStableWeight()`, `getFastWeight()` và `setup()` trong `PetFeeder/src/main.cpp`.

### Chế độ demo và cảm biến đang có hai nguồn số đo

`platformio.ini` bật `PETFEEDER_WOKWI_SIMULATION=1`. Servo tăng biến `simulatedBowlWeightGrams`, nhưng khi HX711 sẵn sàng, hàm đọc cân ưu tiên số đo của HX711. Hai giá trị không tự đồng bộ. Vì vậy servo quay không bảo đảm thanh trượt/cân Wokwi tự tăng theo.

Khi HX711 không sẵn sàng hoặc siêu âm không trả tín hiệu, chế độ này còn dùng dữ liệu giả thay thế, che các lỗi cần kiểm tra ở N10/N11. Muốn kiểm tra lỗi cảm biến, cần bản build kiểm thử không bật cờ này, build lại và chạy lại mô phỏng. Đây chỉ là lựa chọn bản build để thử; hướng dẫn này không sửa cấu hình hiện tại. Khi bỏ cờ, không còn chức năng tự tăng cân giả; cần chủ động điều khiển đầu vào cân.

### Điều kiện đầu vào chung

- Để khoảng cách siêu âm nhỏ hơn 20 cm, chẳng hạn 12 cm, trừ case hết hạt.
- Tare ở trạng thái không tải trước khi đặt tải thử, trừ case cố ý tạo số đo âm.
- Không có lịch tự động khác kích hoạt xen vào bài thử.
- Không có khóa an toàn, không vướng khoảng chờ 180 giây hoặc hạn mức ngày, trừ khi đó chính là điều kiện đang thử.
- Nút xanh nhấn rồi thả sau ít nhất 50 ms và dưới 2,5 giây luôn yêu cầu **30 g**. Khẩu phần 40/50/60 g phải chọn trên app hoặc gửi MQTT, không phải chỉ bấm nút xanh như một số đoạn Word mô tả.
- Không dùng override để bỏ qua bước chuẩn bị các case bảo vệ: source hiện cho override bỏ qua cả một số bảo vệ cần kiểm tra.
- Có thể khởi động lại mô phỏng giữa các case độc lập. Không khởi động lại giữa chuỗi tích lũy hạn mức N02 hoặc giữa hai lượt kẹt và retry của N04, vì các biến liên quan đang lưu trong RAM.

## 3. Thực hiện lần lượt 18 kịch bản

### 1. C03 Chống lặp lệnh và nút bấm

Cho ăn một lần, sau khi phiên thành công nhấn lại trong 180 giây. Mong đợi lệnh thường bị chặn với `BLOCKED_DUPLICATE` và `SAFE_INTERVAL_ACTIVE`. Có thể kiểm tra command ID bằng cách gửi lại cùng ID trên MQTT; firmware chỉ nhớ ID đã xử lý gần nhất.

Phần nhấn liên tiếp **trong lúc servo quay** của Word chưa được bảo đảm: vòng cấp đang chạy chặn nên `loop()` không đọc nút liên tục. Không có cơ sở yêu cầu Serial phải in đúng câu `[BUTTON] ... DANG CAP HAT` trong Word; câu đó không có trong source. Phân biệt bài thử khoảng chờ và bài thử nút trong phiên.

### 2. C05 Hết thức ăn

Click HC-SR04, chỉnh khoảng cách lên 22 cm rồi gửi lệnh thường hoặc bấm nút xanh. Đợi hết bảo vệ lần ăn trước nếu có. Mong đợi không cấp và sự kiện `FOOD_EMPTY/HOPPER_EMPTY` từ firmware. Nếu dùng app, backend cũng có thể từ chối ngay trước khi gửi xuống thiết bị; dùng nút để xác minh nhánh firmware.

Thử riêng nhấn giữ hơn 2,5 giây để quan sát override. **Source hiện kiểm tra hết hạt bằng điều kiện có `!isOverride`, nên không đáp ứng yêu cầu Word rằng override cũng phải bị chặn.** Không đánh dấu phần đó đạt.

Khoảng cách HC-SR04 có thể thay bằng thanh trượt khi đang chạy: https://docs.wokwi.com/parts/wokwi-hc-sr04 .

### 3. C07 Nạp hạt chưa xác minh

Chỉnh HC-SR04 từ 18 cm xuống 5 cm như Word, quan sát trạng thái. Source hiện khởi tạo `isHopperVerified = true`, có nhánh từ chối khi cờ false nhưng chưa có logic tự chuyển false do mức hạt tăng. Vì vậy thao tác này chưa kích hoạt được quy trình mong đợi.

Cần bổ sung cơ chế phát hiện/đầu vào kiểm thử đặt cờ false trước khi xác minh toàn case. Gửi `verify_refill: true` chỉ mở khóa; không tạo được tình huống chưa xác minh. Không thể xác định hạt lạ hay chất lượng thực phẩm chỉ bằng số đo khoảng cách.

### 4. C08 Khóa an toàn

Khi firmware đang nghỉ và MQTT đã kết nối, gửi qua backend:

```powershell
Invoke-RestMethod -Method Put -Uri 'http://localhost:3000/api/device/config' `
  -ContentType 'application/json' -Body '{"lockdown":true}'
```

Nhấn nút thường: mong đợi `REJECTED/SAFETY_LOCKOUT`. Mở khóa sau bài thử:

```powershell
Invoke-RestMethod -Method Put -Uri 'http://localhost:3000/api/device/config' `
  -ContentType 'application/json' -Body '{"lockdown":false}'
```

Đây là bài thử khóa do chủ ra lệnh, không phải phát hiện chất độc. Source hiện cho override bỏ qua khóa này, nên phần “mọi lệnh đều bị chặn” của Word chưa đạt. App hiện cũng không có nút khóa riêng; dùng API trên.

### 5. N01 Bát còn thức ăn

Sau khi chuẩn hóa đầu vào cân, đặt số đo ban đầu 135 g rồi yêu cầu cấp thêm 30 g. Trong phiên, mô phỏng cân tăng đến 150 g. Mong đợi firmware điều chỉnh lượng cần cấp còn 15 g, báo thực cấp khoảng 15 g. Thử riêng bát đã đầy để nhận `BOWL_FULL`.

Với thang cân mặc định và phép chia hiện tại, không thể chỉ kéo thanh trượt để đạt 135 g như Word. Cần xử lý điều kiện cân trước. Servo không tự đổ hạt thật lên cảm biến Wokwi.

### 6. N02 Hạn mức trong ngày

Trong cùng một lần chạy ESP32, hoàn thành sáu phiên 30 g. Sau mỗi phiên, đưa cân bát về mức phù hợp, đợi hết 180 giây rồi cấp tiếp. Không reset ESP32 giữa các phiên. Lần thứ bảy dùng lệnh thường phải bị từ chối `DAILY_LIMIT_EXCEEDED` do đủ sáu lần.

Bài thử hạn mức 200 g là bài riêng: tạo các phiên thành công sao cho yêu cầu tiếp theo làm tổng vượt 200 g. Source kiểm tra `dailyDispensedGrams + targetPortion`, không cần chờ đã cấp vượt 200 g mới chặn. Không dùng override vì nó bỏ qua kiểm tra hạn mức.

### 7. N03 App nút bấm và lịch cùng lúc

Bắt đầu phiên cấp rồi gửi lệnh thứ hai từ app/MQTT hoặc để lịch đến hạn. Kiểm tra có phát sinh phiên mới hay không.

Source hiện không gọi `mqttClient.loop()` và không đọc nút trong vòng cấp. Lệnh MQTT có thể đợi đến sau phiên rồi mới được xử lý; nó có thể bị chặn do khoảng chờ, thay vì trả `DEVICE_BUSY` ngay như Word. Muốn chứng minh phản hồi bận trong lúc đang chạy cần bộ điều khiển cấp không chặn hoặc đầu vào kiểm thử tương ứng. Không đồng nhất việc lệnh bị trì hoãn với bài thử mutex đạt.

### 8. N04 Kẹt dở và cấp bù

Yêu cầu 50 g; điều khiển số đo tăng từ 0 lên 20 g rồi giữ nguyên trong các nhịp tiếp theo. Sau ba lần nghi kẹt liên tiếp, mong đợi `JAM_ERROR` cùng lượng thực cấp khoảng 20 g. Không reset ESP32; giữ bát ở mức đó, gửi MQTT RETRY với mục tiêu 50 g rồi mô phỏng cân tăng thêm 30 g.

App hiện không có nút RETRY riêng. Dùng payload và topic ở mục 4. Đảm bảo không vướng khóa/hạn mức; một phiên kẹt không tự xóa thời gian bảo vệ còn lại từ phiên thành công trước đó.

### 9. N05 Đạt 15 nhịp nhưng vẫn thiếu

Yêu cầu 60 g và điều khiển đầu vào cân để mỗi nhịp chỉ tăng khoảng 1,5 g. Từng nhịp phải tăng ít nhất 1 g để tránh rẽ sang nhánh kẹt trước. Sau 15 nhịp, mong đợi `PARTIAL/MAX_PULSES_REACHED`.

Cần đầu vào theo nhịp có kiểm soát; kéo tay không đúng thời điểm có thể gây `JAM_ERROR`. Sửa mỗi hằng `SIM_PULSE_GRAMS` không đủ khi hàm cân vẫn đọc HX711 thật trong mô phỏng.

### 10. N06 Vi chỉnh và quá lượng

Yêu cầu 30 g. Điều khiển cân tăng dần; khi còn không quá 10 g, tìm log `[FINE PULSE]`. Sau đó thử làm lượng thực cấp vượt mục tiêu trên 3 g trước lần đọc cân tiếp theo, ví dụ 35 g khi ban đầu 0 g.

Mong đợi dừng servo; code hiện gửi `SUCCESS` kèm `error_code=OVER_PORTION`. Cần đọc cả hai trường. Hàm tăng hạt giả có giới hạn theo lượng còn thiếu nên không tự tạo được quá lượng; cần đầu vào cân độc lập. Các log/chuỗi OLED có thể khác câu minh họa trong Word.

### 11. N07 Cân giảm trong phiên

Chọn 40 g trên app/MQTT. Làm cân tăng đến 15 g, sau đó giảm xuống 5 g trước lần đọc nhịp kế tiếp. Mong đợi `INTERRUPTED/INTERRUPTED_PET_FEEDING` và servo đóng.

Đây là phát hiện biến động cân, không xác minh được thú đang ăn. Số thực cấp mà source gửi hiện tính từ cân cuối trừ cân đầu, nên không bảo đảm sẽ bằng 15 g như đoạn minh họa Word khi thức ăn đã bị lấy khỏi bát.

### 12. N08 Cân không ổn định

Làm cân dao động trước khi gửi lệnh và tiếp tục hơn 3 giây trong bước đọc ổn định ban đầu. Dao động phải làm biên độ các mẫu lớn hơn 3 g. Mong đợi `REJECTED/SCALE_UNSTABLE`, không mở phiên cấp.

Hàm kiểm tra ban đầu chỉ lấy năm mẫu cách nhau 30 ms, không phải 500 ms như Word. Kéo chậm có thể tạo ra một nhóm mẫu ổn định và được chấp nhận. Muốn kết quả lặp lại cần đầu vào dao động có kiểm soát.

### 13. N09 Mất bát

Cần tạo số đo âm không lớn hơn -10 g theo giá trị firmware thực nhận rồi gửi lệnh thường. Mong đợi `REJECTED/BOWL_MISSING`.

Thang slider không bảo đảm có giá trị âm; có thể nghiên cứu mô phỏng tare có tải rồi giảm tải, hoặc dùng đầu vào kiểm thử. `readStableWeight()` kiểm tra số âm lúc đầu, nhưng `getFastWeight()` dùng trong phiên lại ép số âm về 0. Vì vậy bài “lấy bát giữa phiên” chưa có cùng bảo đảm như bài trước phiên và cần kiểm tra riêng.

### 14. N10 HX711 mất kết nối

Dùng bản build kiểm thử không có cờ mô phỏng fallback. Dừng Wokwi, tạo tình trạng DT không sẵn sàng theo mạch thử, rồi chạy lại và gửi lệnh. Chỉ tháo một dây không phải lúc nào cũng tạo mức logic xác định; kiểm tra thực tế `scale.is_ready()`.

Mong đợi `SENSOR_ERROR/HX711_OFFLINE` khi hết thời gian chờ. Giữ cờ mô phỏng hiện tại có thể thay lỗi bằng cân giả nên không đủ để đánh giá case này. `scale.tare()` lúc khởi động cũng có thể chờ nếu cảm biến mất ngay từ đầu; cần tách việc thiết bị khởi động được và việc phát hiện lỗi trong lúc chạy.

### 15. N11 HC-SR04 timeout

Dùng bản build không có fallback, tạo lỗi đường ECHO GPIO 18 với mức logic xác định, rồi gửi yêu cầu cấp để chạy nhánh kiểm tra cảm biến. Mong đợi `SENSOR_ERROR/ULTRASONIC_TIMEOUT`, phân biệt với `FOOD_EMPTY`.

Chỉ đứng ở trạng thái nghỉ có thể thấy số khoảng cách lỗi mà chưa có FEED_RESULT. Với cờ mô phỏng hiện tại, timeout bị thay bằng dữ liệu hộp giả nên không thử đúng được nhánh này.

### 16. N12 Kẹt hạt

Đặt cân ổn định, yêu cầu 30 g, giữ nguyên số đo qua các nhịp. Hạt trong hộp vẫn phải được xác nhận còn. Mong đợi nhánh gỡ kẹt khi mức tăng dưới 1 g, ba lần nghi kẹt liên tiếp thì `JAM_ERROR/JAM_RECOVERY_FAILED`.

Phân biệt số lần gọi thử gỡ kẹt với ba chu kỳ lắc bên trong `triggerAntiJam()`. Nếu đang dùng cân giả tự tăng thì phải có đầu vào chặn tăng; không coi servo Wokwi bị “giữ bằng chuột” là hạt đã bị tắc.

### 17. N13 Thêm trực tiếp vào bát

Khi nghỉ, đặt cân ở một mốc khác 0, ví dụ 10 g; đợi ít nhất hai vòng giám sát (khoảng hơn 3 giây), sau đó tăng lên 45 g. Mong đợi `BOWL_EVENT`, `type=MANUAL_REFILL`, `delta_g` khoảng +35 g. Servo không chạy.

Word mô tả 0→45 g, nhưng source dùng `lastIdleBowlWeight == 0` làm mốc chưa khởi tạo, nên lần tăng đầu từ 0 có thể chỉ đặt mốc mà không phát sự kiện. Có thể dùng 10→45 g để kiểm tra nhánh sự kiện, nhưng phải ghi bài 0→45 g chưa đạt đúng tài liệu.

### 18. N14 Khối lượng giảm khi nghỉ

Đặt cân ổn định 45 g, đợi giám sát nhận mốc rồi giảm xuống 15 g và đợi ít nhất một vòng giám sát 1,5 giây. Mong đợi `BOWL_EVENT`, `type=WEIGHT_DECREASED`, `delta_g` khoảng -30 g, `cause=UNKNOWN_CAUSE`.

Backend có nhánh chuyển BOWL_EVENT thành thông báo. App đọc thông báo ở Cài đặt; kéo làm mới để xem. Không ghi là đã xác nhận thú ăn.

## 4. Gửi FEED và RETRY khi cần

Dùng MQTT client có sẵn của bạn, kết nối `broker.emqx.io`, cổng 1883. Không cần cài Mosquitto broker để dùng broker này. Dùng client MQTT mà bạn có sẵn; hướng dẫn này không gửi lệnh thật.

Topic lệnh là `duylinh0212/petfeeder/v1/command`. Publish lệnh thử với **retain tắt**, mỗi yêu cầu mới có ID mới:

```json
{"command":"FEED","portion":50,"override":false,"source":"app","command_id":"demo-n04-001"}
```

Sau khi N04 đã kẹt ở 20 g, giữ nguyên phiên chạy ESP32, khắc phục điều kiện gây kẹt và gửi:

```json
{"command":"RETRY","portion":50,"override":false,"source":"retry","command_id":"demo-n04-retry-001"}
```

Chỉ dùng lại cùng ID cho bài kiểm tra lệnh trùng. Theo dõi `duylinh0212/petfeeder/v1/events` và `duylinh0212/petfeeder/v1/telemetry` để đọc kết quả. Một sự kiện retained nhận lúc vừa subscribe có thể là kết quả cũ; cần đối chiếu command ID và thời điểm bài thử.

## 5. Cách ghi kết quả

Mỗi case ghi: điều kiện đầu, thao tác thực tế, số đo firmware nhận, mã kết quả, command ID nếu có, ảnh Serial/OLED, bản ghi backend, và kết luận **đạt / không đạt / chưa đủ điều kiện**.

Ưu tiên thử kết nối, bài khóa C08 bằng lệnh thường, bài hết hạt C05 bằng lệnh thường, N12, rồi các case cân sau khi chuẩn hóa số đo. Không trình bày đủ 18 case đã đạt chỉ dựa trên việc biên dịch thành công. Các khác biệt ở C07, đường override, xử lý lệnh đồng thời, thang cân và fallback cần được xử lý hoặc ghi nhận trước khi đánh giá đủ bộ theo Word.
