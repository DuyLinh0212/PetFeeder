# Các kịch bản xử lý tình huống đang có

Các luồng đang giữ: **C03, N01, N07, N09 và N19**. Bên dưới là cách hệ thống xử lý và cách thử từng tình huống theo mẫu bạn đưa. Nút vật lý vẫn hoạt động như hiện tại. Ba kịch bản cuối là nhánh an toàn đã có trong code, chưa có mã case riêng.

## Chuẩn bị Wokwi

- Mở Serial Monitor ở 115200 baud, chờ thiết bị kết nối rồi gõ `status`.
- Gõ `sim manual` để chỉnh cân HX711 bằng mục `load` trên Wokwi. Giá trị `0.14` tương ứng khoảng 140 g.
- Đặt bát rỗng lên cân rồi gõ `tare EMPTY`. Chờ số cân ổn định trước khi gửi lệnh.
- `sim auto` tự tăng cân để minh họa servo; số cân này là giả lập.
- Nếu thử cấp qua app, backend và firmware cần dùng cùng MQTT topic prefix.

### **Kịch bản 1: Nhấn nút hoặc gửi lệnh cấp nhiều lần (C03)**

- **Nguyên lý:** App, nút bấm và lịch dùng chung một trạng thái cấp. Lệnh khác đến khi máy đang cấp bị `BUSY`; gửi lại cùng `command_id` không tạo thêm phiên.
- **Các bước test trên Wokwi và app:**
  1. Chọn `sim auto` rồi gửi một lệnh cấp từ app.
  2. Khi màn hình báo **ĐANG CẤP**, nhấn nút trên mạch hoặc gửi thêm một lệnh từ app.
  3. Gửi lại cùng `command_id` của lệnh đầu qua API/MQTT.
- **Kết quả:**
  - Lệnh mới bị từ chối `BUSY`.
  - Lệnh trùng được nhận ra là `BLOCKED_DUPLICATE`; servo không cấp thêm lần nữa.

### **Kịch bản 2: Bát gần đầy, khẩu phần mới sẽ làm tràn bát (N01)**

- **Nguyên lý:** Khẩu phần là lượng thức ăn cấp thêm. Nếu cân hiện tại cộng khẩu phần vượt sức chứa bát, hệ thống từ chối trước khi mở servo.
- **Các bước test trên Wokwi:**
  1. Cân chỉnh bát rỗng bằng `tare EMPTY`.
  2. Chọn `sim manual`, đặt HX711 ở `load=0.14 kg`.
  3. Trong app, yêu cầu cấp 20 g khi sức chứa bát đang đặt là 150 g.
- **Kết quả:**
  - 140 g + 20 g vượt sức chứa 150 g.
  - App/thiết bị báo `BOWL_FULL`; servo không mở.
- **Ghi chú:** `PetFeeder/test/n01.yaml` hiện đặt cân ở 140 g và đọc trạng thái thiết bị; file này chưa tự gửi lệnh cấp để kiểm tra `BOWL_FULL`.

### **Kịch bản 3: Thú cưng làm rung hoặc đẩy bát khi đang cấp (N07)**

- **Nguyên lý:** HX711 được đọc mỗi 100 ms. Firmware lấy trung bình trượt 5 mẫu (`MA5`); cân cần có 3 mẫu liên tiếp nằm trong sai số 2 g và ổn định thêm 700 ms. Cân dao động thì servo tạm dừng. Nếu số cân lọc giảm hơn 2 g giữa hai mẫu, phiên bị dừng vì không còn biết chính xác lượng đã cấp.
- **Các bước test trên Wokwi:**
  1. Chọn `sim manual` trong Serial Monitor.
  2. Mở điều khiển HX711 `scale` trong Wokwi, đặt `load=0.000 kg`, rồi gõ `tare EMPTY` để lấy mức cân rỗng.
  3. Đặt `load=0.040 kg` và chờ Serial báo `ỔN ĐỊNH`.
  4. Gửi lệnh cấp 20 g từ app hoặc nhấn nút trên mạch.
  5. Khi servo đang chạy, dùng điều khiển `load` đặt `0.050 kg` trong khoảng 0,3 giây rồi trả về `0.040 kg` để tạo một cú rung giả lập. Có thể lặp lại vài lần.
  6. Sau khi rung kết thúc, đặt `load=0.060 kg` để mô phỏng 20 g thức ăn đã rơi xuống.
  7. Thử nhánh rung mạnh trong phiên khác: làm cân giảm từ `0.040 kg` xuống `0.020 kg` khi servo đang chạy.
- **Kết quả:**
  - Serial in mẫu đo và `MA5`; khi đặt tải nhảy lên, `MA5` thay đổi từ từ qua các mẫu thay vì nhảy ngay theo tải.
  - Rung nhẹ: servo chờ cân ổn định rồi tiếp tục cấp.
  - Cân giảm mạnh: thiết bị dừng với `INTERRUPTED`; lượng thực cấp được để trống và thiết bị chờ kiểm tra.
- **Lưu ý:** Hệ thống chỉ nhìn biến động HX711, chưa có cảm biến nhận ra nguyên nhân là thú đẩy bát, thú ăn hay bát bị xê dịch.

### **Kịch bản 4: Bát bị nhấc khỏi cân giữa phiên cấp (N09)**

- **Nguyên lý:** Mạch chưa có cảm biến hiện diện bát riêng. Firmware dùng dấu hiệu cân HX711 âm từ 10 g trở xuống so với mức tare để suy luận bát đã bị nhấc. Khi không còn số đo tin cậy, servo dừng và lượng cấp được ghi là chưa biết.
- **Các bước test trên Wokwi:**
  1. Đặt bát rỗng lên cân, chỉnh `load=0.020 kg` rồi gõ `tare EMPTY`.
  2. Tăng tải lên `0.060 kg` để mô phỏng 40 g thức ăn trong bát.
  3. Bắt đầu cấp; khi servo đang chạy, đưa tải về `0.000 kg` để mô phỏng nhấc bát.
  4. Đặt bát lại lên cân, chờ số đo hợp lệ rồi gõ `reconcile CHECKED` sau khi đã kiểm tra thiết bị.
- **Kết quả:**
  - Thiết bị báo `BOWL_MISSING`, đóng servo và khóa lệnh cấp mới.
  - Sau khi đặt bát lại và xác nhận kiểm tra, thiết bị mở khóa nhưng vẫn giữ phần hạn mức đã dự trữ để tránh cấp trùng.

### **Kịch bản 5: Mất mạng, dùng lịch offline để cấp thức ăn đúng giờ (N19)**

- **Nguyên lý:** Đây là trường hợp chỉ mất kết nối mạng: ESP32 vẫn có điện và tiếp tục chạy. Lịch đã nhận được lưu trong NVS, nên thiết bị tự kiểm tra giờ và cấp thức ăn dù Wi-Fi, MQTT, backend hoặc app không kết nối. Sự kiện được giữ trong hàng đợi NVS để gửi lên backend khi mạng trở lại. Lịch trễ từ 60 giây trở lên bị bỏ qua, không cấp dồn.
- **Các bước test bằng backend simulator hoặc thiết bị Wokwi/phần cứng:**
  1. Tạo lịch cho ngày hiện tại, đặt giờ chạy sắp tới và chờ ESP32 nhận cấu hình; xác nhận có sự kiện `CONFIG_APPLIED`.
  2. Ngắt kết nối mạng trước giờ ăn; giữ ESP32 đang bật và không nhấn reset.
  3. Chờ đến giờ lịch. Thiết bị dùng lịch đã lưu để cấp nếu cân ổn định, bát còn chỗ và các giới hạn an toàn cho phép.
  4. Nối mạng lại, chờ thiết bị gửi sự kiện đã lưu rồi kiểm tra lịch sử trên backend.
  5. Xác nhận lịch sử ghi nhận đúng một phiên cấp; lịch không bị chạy lại sau khi sự kiện được đồng bộ.
- **Kết quả:**
  - Đến giờ, thiết bị dùng lịch NVS để cấp tự động dù app/backend không kết nối.
  - Sự kiện được lưu offline và gửi lại sau khi có mạng; gửi lặp không tạo lịch sử trùng.
  - Lịch trễ từ 60 giây trở lên ghi `MISSED_SCHEDULE` và không cấp bù.
  - Nếu đồng hồ chưa hợp lệ hoặc thiết bị mất nguồn trước giờ ăn, lịch không thể tự chạy cho đến khi có giờ hợp lệ và thiết bị hoạt động.

## Hai tình huống an toàn khác đã có trong code

### **Kịch bản 6: Cân báo cấp đủ, cấp thiếu, cấp quá lượng hoặc không rơi hạt**

- **Nguyên lý:** Servo cấp theo nhịp, cân đo lượng tăng thực tế rồi quyết định trạng thái phiên.
- **Các bước test trên Wokwi:**
  1. Chọn `sim auto`, yêu cầu cấp 20 g để xem cân giả lập tăng đến mục tiêu.
  2. Chọn `sim manual` để thử riêng: tăng cân đến gần 20 g; tăng vượt 22 g; tăng một phần rồi giữ nguyên; hoặc không tăng cân.
  3. Để cân đứng yên đến khi thiết bị chạm giới hạn thời gian cấp.
- **Kết quả:** Đạt mục tiêu báo `SUCCESS`; vượt mục tiêu hơn sai số báo `OVER_PORTION`; có cấp nhưng chưa đủ báo `PARTIAL`; không có thức ăn rơi xuống báo `TIMEOUT` khi hết thời gian cấp. Servo đóng khi phiên kết thúc.
- **Lưu ý:** `sim auto` chỉ tạo số cân giả lập. Độ chính xác khi hạt rơi và quán tính servo cần thử trên mạch thật.

### **Kịch bản 7: Mất điện giữa phiên cấp đang chạy**

- **Nguyên lý:** Khác với kịch bản 5, ở đây ESP32 bị mất nguồn trong lúc servo đang cấp. Lúc không có điện, thiết bị chưa thể ghi sự kiện mới; trạng thái phiên `active` đã được lưu trước đó trong NVS. Khi khởi động lại, firmware phát hiện phiên dang dở, ghi `INTERRUPTED` vào lịch sử và thêm sự kiện vào hàng đợi NVS để gửi backend sau khi có mạng. Thiết bị khóa cấp để chờ kiểm tra; phần khẩu phần còn thiếu không được tự xếp hàng để cấp tiếp.
- **Các bước test trên Wokwi:**
  1. Chọn `sim manual`, bắt đầu một phiên cấp và chờ trạng thái `DISPENSING`.
  2. Khi vẫn thấy `DISPENSING`, bấm nút reset màu xanh trên thanh Wokwi. Reset này mô phỏng ESP32 khởi động lại và giữ vùng flash/NVS; đây là cách thử luồng phục hồi, không phải cắt nguồn vật lý thật.
  3. Sau khi boot xong, kiểm tra phiên cũ được ghi `INTERRUPTED` kèm `RECONCILIATION_REQUIRED`, sự kiện nằm trong outbox NVS và servo không tự mở lại.
  4. Kiểm tra lượng thức ăn trong bát và cơ cấu; đặt cân về số đo hợp lệ rồi gõ `reconcile CHECKED`.
- **Kết quả:** Nếu mạng chưa có và outbox còn chỗ, sự kiện `INTERRUPTED` vẫn nằm trong hàng đợi; khi kết nối lại, ESP32 gửi sự kiện và xóa khỏi hàng đợi sau ACK. Nếu outbox đầy, firmware không ghi đè sự kiện cũ mà tăng bộ đếm tràn. Thiết bị chỉ nhận phiên cấp mới sau khi người dùng kiểm tra và xác nhận; không tự cấp phần còn thiếu của phiên trước.

## Những việc hệ thống chưa tự xử lý

- Cảm biến HC-SR04 hiện gửi mức hạt lên telemetry; firmware chưa dùng nó để xác nhận hộp hết thức ăn trước khi mở servo. Cân không tăng sẽ kết thúc theo nhánh `PARTIAL` hoặc `TIMEOUT`, chưa phân biệt được hết hạt với kẹt hạt.
- Hệ thống chưa theo dõi sau cấp để xác nhận thú đã ăn.
- HX711, HC-SR04 và cảm biến tiếp cận hiện tại không nhận dạng loại thức ăn, dị vật, độc chất hay vi sinh.
- Cân giảm không cho biết chắc thú đang ăn hay bát bị rung, đẩy hoặc thức ăn bị lấy đi.

## File liên quan

- [README.md](../README.md) — các case đang được giữ.
- [main.cpp](../PetFeeder/src/main.cpp) — firmware ESP32, lọc HX711, servo và lịch.
- [feedingService.mjs](../petfeeder_backend/src/services/feedingService.mjs) — kiểm tra lệnh và trạng thái backend.
- [active-cases.test.mjs](../petfeeder_backend/test/active-cases.test.mjs) — mô phỏng các tình huống xử lý phía backend.
- [n01.yaml](../PetFeeder/test/n01.yaml) — kịch bản Wokwi cân 140 g.
