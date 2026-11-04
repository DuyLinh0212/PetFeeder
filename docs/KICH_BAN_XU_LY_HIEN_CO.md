# Các kịch bản xử lý tình huống đang có

Các luồng đang giữ: **C03, N01, N02, N07, N09 và N19**. Bên dưới là cách hệ thống xử lý và cách thử từng tình huống theo mẫu bạn đưa. Nút vật lý được giữ như hiện tại và không cần xác minh thú cưng. Ba kịch bản cuối là nhánh an toàn đã có trong code, chưa có mã case riêng.

## Chuẩn bị Wokwi

- Mở Serial Monitor ở 115200 baud, chờ thiết bị kết nối rồi gõ `status`.
- Gõ `sim manual` để chỉnh cân HX711 bằng mục `load` trên Wokwi. Giá trị `0.14` tương ứng khoảng 140 g.
- Đặt bát rỗng lên cân rồi gõ `tare EMPTY`. Chờ số cân ổn định trước khi gửi lệnh.
- `sim auto` tự tăng cân để minh họa servo; số cân này là giả lập.
- Nếu thử cấp qua app, backend và firmware cần dùng cùng MQTT topic prefix.

### **Kịch bản 1: Nhấn nút vật lý để cấp thức ăn**

- **Nguyên lý:** Nút trên mạch gửi lệnh cấp 20 g như trước. Lệnh không cần nhận diện thú cưng; firmware vẫn kiểm tra giờ, cân, khoảng chờ, sức chứa bát và giới hạn trong ngày.
- **Các bước test trên Wokwi:**
  1. Đặt bát lên cân, hiệu chuẩn bằng `tare EMPTY` và chờ số cân ổn định.
  2. Chờ ESP32 kết nối, đồng hồ hợp lệ và không ở trong khoảng chờ.
  3. Nhấn nút GPIO 4 một lần.
  4. Thử lại khi thiết bị đang cấp hoặc trước khi hết khoảng chờ để kiểm tra các khóa an toàn hiện có.
- **Kết quả:**
  - Lệnh nút được tiếp nhận với khẩu phần 20 g và chạy servo nếu các điều kiện an toàn đều đạt.
  - Nếu thiết bị đang bận, cân chưa ổn định, bát quá đầy hoặc chưa hết khoảng chờ, lệnh bị từ chối; nút không tạo phiên cấp thứ hai.

### **Kịch bản 2: Nhấn nút hoặc gửi lệnh cấp nhiều lần (C03)**

- **Nguyên lý:** App, nút bấm và lịch dùng chung một trạng thái cấp. Lệnh khác đến khi máy đang cấp bị `BUSY`; gửi lại cùng `command_id` không tạo thêm phiên.
- **Các bước test trên Wokwi và app:**
  1. Chọn `sim auto` rồi gửi một lệnh cấp từ app.
  2. Khi màn hình báo **ĐANG CẤP**, nhấn nút trên mạch hoặc gửi thêm một lệnh từ app.
  3. Gửi lại cùng `command_id` của lệnh đầu qua API/MQTT.
- **Kết quả:**
  - Lệnh mới bị từ chối `BUSY`.
  - Lệnh trùng được nhận ra là `BLOCKED_DUPLICATE`; servo không cấp thêm lần nữa.

### **Kịch bản 3: Bát gần đầy, khẩu phần mới sẽ làm tràn bát (N01)**

- **Nguyên lý:** Khẩu phần là lượng thức ăn cấp thêm. Nếu cân hiện tại cộng khẩu phần vượt sức chứa bát, hệ thống từ chối trước khi mở servo.
- **Các bước test trên Wokwi:**
  1. Cân chỉnh bát rỗng bằng `tare EMPTY`.
  2. Chọn `sim manual`, đặt HX711 ở `load=0.14 kg`.
  3. Trong app, yêu cầu cấp 20 g khi sức chứa bát đang đặt là 150 g.
- **Kết quả:**
  - 140 g + 20 g vượt sức chứa 150 g.
  - App/thiết bị báo `BOWL_FULL`; servo không mở.
- **Ghi chú:** `PetFeeder/test/n01.yaml` hiện đặt cân ở 140 g và đọc trạng thái thiết bị; file này chưa tự gửi lệnh cấp để kiểm tra `BOWL_FULL`.

### **Kịch bản 4: Yêu cầu cấp quá sớm hoặc vượt hạn mức trong ngày (N02)**

- **Nguyên lý:** Mặc định thiết bị chờ ít nhất 180 giây giữa hai lần cấp, giới hạn 200 g và tối đa 6 phiên mỗi ngày. Các giá trị này có thể chỉnh trong cấu hình và được lưu qua khởi động lại.
- **Các bước test trên app/backend:**
  1. Cấp một khẩu phần hợp lệ và đợi phiên kết thúc.
  2. Gửi lệnh thứ hai trước khi hết 180 giây.
  3. Để thử nhanh hạn mức ngày, giảm `min_interval_s`, rồi đặt `daily_limit_g` hoặc `max_daily_feeds` xuống thấp trong Cài đặt an toàn.
  4. Cấp đến ngưỡng, khởi động lại thiết bị rồi thử thêm lần nữa.
- **Kết quả:**
  - Cấp quá sớm: `COOLDOWN`.
  - Vượt tổng gram trong ngày: `DAILY_LIMIT`.
  - Vượt số phiên trong ngày: `DAILY_FEED_LIMIT`.
  - Khởi động lại không xóa phần hạn mức đã dùng.

### **Kịch bản 5: Thú cưng làm rung hoặc đẩy bát khi đang cấp (N07)**

- **Nguyên lý:** HX711 được đọc mỗi 100 ms. Firmware lấy trung bình trượt 5 mẫu; cân cần có 3 mẫu liên tiếp nằm trong sai số 2 g và ổn định thêm 700 ms. Cân dao động thì servo tạm dừng. Nếu số cân lọc giảm hơn 2 g giữa hai mẫu, phiên bị dừng vì không còn biết chính xác lượng đã cấp.
- **Các bước test trên Wokwi:**
  1. Chọn `sim manual`, đặt tải ở `0.040 kg` và chờ ổn định.
  2. Gửi lệnh cấp 20 g từ app.
  3. Khi servo đang chạy, đổi `load` lên `0.050 kg` khoảng 0,3 giây rồi trả về `0.040 kg` để mô phỏng rung nhẹ.
  4. Chờ cân ổn định; sau đó đặt `load=0.060 kg` để mô phỏng 20 g thức ăn đã rơi xuống.
  5. Thử nhánh rung mạnh trong phiên khác: làm cân giảm từ `0.040 kg` xuống `0.020 kg` khi servo đang chạy.
- **Kết quả:**
  - Rung nhẹ: servo chờ cân ổn định rồi tiếp tục cấp.
  - Cân giảm mạnh: thiết bị dừng với `INTERRUPTED`; lượng thực cấp được để trống và thiết bị chờ kiểm tra.
- **Lưu ý:** Hệ thống chỉ nhìn biến động HX711, chưa có cảm biến nhận ra nguyên nhân là thú đẩy bát, thú ăn hay bát bị xê dịch.

### **Kịch bản 6: Bát bị nhấc khỏi cân giữa phiên cấp (N09)**

- **Nguyên lý:** Mạch chưa có cảm biến hiện diện bát riêng. Firmware dùng dấu hiệu cân HX711 âm từ 10 g trở xuống so với mức tare để suy luận bát đã bị nhấc. Khi không còn số đo tin cậy, servo dừng và lượng cấp được ghi là chưa biết.
- **Các bước test trên Wokwi:**
  1. Đặt bát rỗng lên cân, chỉnh `load=0.020 kg` rồi gõ `tare EMPTY`.
  2. Tăng tải lên `0.060 kg` để mô phỏng 40 g thức ăn trong bát.
  3. Bắt đầu cấp; khi servo đang chạy, đưa tải về `0.000 kg` để mô phỏng nhấc bát.
  4. Đặt bát lại lên cân, chờ số đo hợp lệ rồi gõ `reconcile CHECKED` sau khi đã kiểm tra thiết bị.
- **Kết quả:**
  - Thiết bị báo `BOWL_MISSING`, đóng servo và khóa lệnh cấp mới.
  - Sau khi đặt bát lại và xác nhận kiểm tra, thiết bị mở khóa nhưng vẫn giữ phần hạn mức đã dự trữ để tránh cấp trùng.

### **Kịch bản 7: Đến giờ ăn khi MQTT mất kết nối (N19)**

- **Nguyên lý:** Lịch đã đồng bộ được lưu trên ESP32. Nếu đồng hồ còn hợp lệ, lịch vẫn chạy khi MQTT mất kết nối; sự kiện được giữ trong hàng đợi và gửi lại khi mạng phục hồi. Lịch trễ từ 60 giây trở lên bị bỏ qua, không cấp dồn.
- **Các bước test bằng backend simulator hoặc Wokwi:**
  1. Tạo lịch cho ngày hiện tại, đặt giờ chạy sắp tới và chờ ESP32 nhận lịch.
  2. Ngắt MQTT trước giờ ăn, nhưng giữ thiết bị bật và đồng hồ hợp lệ.
  3. Chờ qua giờ lịch, kiểm tra servo và hàng đợi sự kiện trên thiết bị.
  4. Nối MQTT lại rồi kiểm tra backend nhận sự kiện.
  5. Đồng bộ lại lịch hoặc khởi động lại để chắc rằng lịch hôm đó không chạy lần hai.
- **Kết quả:**
  - Lịch trong cửa sổ 60 giây chạy một lần; sự kiện được gửi lại sau khi có mạng.
  - Lịch trễ từ 60 giây trở lên ghi `MISSED_SCHEDULE` và không cấp bù.
  - Nếu đồng hồ chưa hợp lệ, thiết bị chờ đồng bộ giờ rồi mới xét lịch.

## Ba tình huống an toàn khác đã có trong code

### **Kịch bản 8: Lệnh sai dữ liệu, quá hạn hoặc thiết bị chưa có giờ**

- **Nguyên lý:** Thiết bị kiểm tra trường bắt buộc, thời hạn lệnh và giờ hiện tại trước khi cấp.
- **Các bước test:**
  1. Gửi lệnh thiếu trường hoặc có khẩu phần sai miền giá trị.
  2. Gửi lệnh có `expires_at` đã qua.
  3. Thử gửi lệnh khi ESP32 chưa đồng bộ được giờ.
- **Kết quả:** Lệnh sai báo `INVALID_FIELD`, lệnh cũ báo `COMMAND_EXPIRED`, giờ chưa hợp lệ báo `TIME_INVALID`; servo không chạy.

### **Kịch bản 9: Cân báo cấp đủ, cấp thiếu, cấp quá lượng hoặc không rơi hạt**

- **Nguyên lý:** Servo cấp theo nhịp, cân đo lượng tăng thực tế rồi quyết định trạng thái phiên.
- **Các bước test trên Wokwi:**
  1. Chọn `sim auto`, yêu cầu cấp 20 g để xem cân giả lập tăng đến mục tiêu.
  2. Chọn `sim manual` để thử riêng: tăng cân đến gần 20 g; tăng vượt 22 g; tăng một phần rồi giữ nguyên; hoặc không tăng cân.
  3. Để cân đứng yên đến khi thiết bị chạm giới hạn nhịp hoặc thời gian.
- **Kết quả:** Đạt mục tiêu báo `SUCCESS`; vượt mục tiêu hơn sai số báo `OVER_PORTION`; có cấp nhưng chưa đủ báo `PARTIAL`; không có thức ăn rơi xuống báo `TIMEOUT` khi hết giới hạn. Servo đóng khi phiên kết thúc.
- **Lưu ý:** `sim auto` chỉ tạo số cân giả lập. Độ chính xác khi hạt rơi và quán tính servo cần thử trên mạch thật.

### **Kịch bản 10: Mất điện giữa phiên cấp**

- **Nguyên lý:** Khi khởi động lại, nếu bộ nhớ ghi nhận còn phiên cấp dang dở, ESP32 đóng servo, đánh dấu gián đoạn và khóa cấp để chờ kiểm tra. Thiết bị không tự chạy lại khẩu phần cũ.
- **Các bước test trên Wokwi:**
  1. Chọn `sim manual`, bắt đầu cấp và chờ trạng thái `DISPENSING`.
  2. Khởi động lại ESP32 trước khi cân đạt mục tiêu.
  3. Kiểm tra trạng thái sau khi thiết bị khởi động.
  4. Kiểm tra bát và cơ cấu; đặt cân về số đo hợp lệ rồi gõ `reconcile CHECKED`.
- **Kết quả:** Phiên cũ ghi `INTERRUPTED` kèm `RECONCILIATION_REQUIRED`; thiết bị không cấp lại cho đến khi được kiểm tra và xác nhận.

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
