# Kịch bản xử lý tình huống

File này giữ đúng 5 tình huống cần mô phỏng. Nút vật lý trên mạch vẫn dùng để cấp thức ăn như bình thường.

## Chuẩn bị Wokwi

- Mở Serial Monitor ở 115200 baud và chờ ESP32 kết nối.
- Gõ `status` để xem trạng thái thiết bị.
- Gõ `dump state` để in JSON đang lưu trong NVS của ESP32 mô phỏng.
- Gõ `sim manual` để tự chỉnh cân HX711; giá trị `0.14` tương ứng khoảng 140 g.
- Đặt bát rỗng lên cân và gõ `tare EMPTY` trước khi thử các tình huống liên quan đến cân.
- Khi thử lệnh từ App, backend và firmware cần dùng cùng MQTT topic prefix.

### **Kịch bản 1: Bấm cấp thức ăn liên tục khi máy vẫn đang cấp**

- **Nguyên lý:** Chỉ chạy một phiên cấp tại một thời điểm. Lệnh mới gửi trong lúc servo đang cấp bị từ chối; gửi lặp lại cùng mã lệnh không tạo thêm phiên.
- **Các bước test trên Wokwi và App:**
  1. Chọn `sim auto`, rồi gửi một lệnh cấp từ App.
  2. Khi thiết bị báo **ĐANG CẤP**, bấm cấp thêm lần nữa trên App và nhấn nút trên mạch.
  3. Nếu có thể, gửi lại cùng mã lệnh của yêu cầu đầu tiên.
- **Kết quả:**
  - Phiên đầu tiếp tục chạy bình thường.
  - Các yêu cầu mới bị từ chối với trạng thái `BUSY`.
  - Lệnh trùng mã không làm servo chạy thêm một lượt.

### **Kịch bản 2: Thú cưng làm rung bát khiến số cân dao động**

- **Nguyên lý:** Firmware lọc số cân HX711 bằng trung bình trượt 5 mẫu (MA5). Nếu phát hiện khối lượng giảm bất thường trong lúc cấp, servo dừng và giữ nguyên hạn mức cho phiên cũ. Khi cân ổn định liên tục 2 giây, firmware tự tiếp tục phần còn thiếu của phiên đó một lần.
- **Các bước test trên Wokwi:**
  1. Chọn `sim manual`, đặt cân về mức ổn định và chờ Serial báo cân ổn định lúc khởi động.
  2. Bắt đầu cấp thức ăn.
  3. Trong lúc cấp, kéo HX711 lên xuống nhẹ vài lần để mô phỏng bát bị rung hoặc xê dịch.
  4. Dừng thay đổi tải; giữ số cân ở mức không thấp hơn khối lượng bát trước khi cấp và chờ ít nhất 2 giây sau khi cân ổn định.
- **Kết quả:**
  - Serial báo `CẢNH BÁO CÂN DAO ĐỘNG` khi MA5 vượt ngưỡng.
  - Sau `WEIGHT_DROP_DETECTED`, cân ổn định đủ 2 giây sẽ có log `tự tiếp tục phiên cũ` và servo cấp phần còn thiếu, không tạo lệnh hoặc khẩu phần mới.
  - Lệnh cho ăn mới trong lúc phiên cũ đang tiếp tục nhận `BUSY`, thay vì bị từ chối khóa an toàn.
- **Lưu ý:** Nếu số cân ổn định thấp hơn mức trước khi cấp, cảm biến báo bát bị lấy ra, hoặc cùng phiên đã tự phục hồi một lần, thiết bị vẫn khóa để kiểm tra thủ công. Cảm biến không xác định được nguyên nhân làm cân giảm.

### **Kịch bản 3: Bát đầy thì không cho cấp thêm**

- **Nguyên lý:** Trước khi mở servo, thiết bị cộng lượng thức ăn đang có trong bát với khẩu phần được yêu cầu. Nếu tổng vượt sức chứa đã cài đặt, lệnh bị từ chối.
- **Các bước test trên Wokwi và App:**
  1. Đặt sức chứa bát là 150 g.
  2. Chọn `sim manual`, đặt HX711 ở `load=0.14 kg` (140 g).
  3. Yêu cầu App cấp thêm 20 g.
- **Kết quả:**
  - 140 g + 20 g vượt sức chứa 150 g.
  - Thiết bị báo `BOWL_FULL`; servo không mở.

### **Kịch bản 4: Mất mạng, dùng lịch offline để cấp đúng giờ**

- **Nguyên lý:** ESP32 lưu lịch và hàng đợi sự kiện trong NVS. Khi mất kết nối MQTT, lịch vẫn chạy theo đồng hồ đã đồng bộ; sự kiện nằm trong hàng đợi trên ESP32 cho tới khi MQTT kết nối lại. PostgreSQL chỉ nhận dữ liệu sau khi sự kiện được đồng bộ.
- **Các bước test trên Wokwi:**
  1. Gõ `sim auto` trong Serial Monitor để dùng cân giả lập.
  2. Tạo lịch ăn sắp đến giờ từ App; chờ Serial báo `CONFIG_APPLIED` trước khi tiếp tục.
  3. Trước giờ ăn, gõ `sim offline`. Lệnh ngắt MQTT nhưng giữ ESP32 bật, giữ Wi-Fi/đồng hồ và không nhấn reset.
  4. Chờ lịch chạy; Serial sẽ ghi nhận phiên cấp trong lúc MQTT đang ngắt.
  5. Gõ `sim online`, chờ MQTT kết nối lại rồi kiểm tra lịch sử trên App/backend.
- **Kết quả:**
  - ESP32 dùng lịch đã lưu để cấp thức ăn khi MQTT giữa ESP32 và backend bị ngắt; App/backend vẫn có thể chạy.
  - Sự kiện được gửi lên sau khi mạng trở lại, không tạo lịch sử trùng.
  - Lịch trễ từ 60 giây trở lên bị bỏ qua, không cấp dồn.
- **Lưu ý:** Giữ tốc độ Wokwi ở 100% và không dừng/chạy lại mô phỏng giữa hai lệnh; NVS là bộ nhớ flash của ESP32 mô phỏng, độc lập với PostgreSQL backend.

### **Kịch bản 5: Mất điện giữa phiên cấp đang chạy**

- **Nguyên lý:** Khi mất điện, phiên đang cấp được lưu để phục hồi. Nếu có điện lại trong vòng 1 giờ, thiết bị kiểm tra số cân đã ổn định rồi tự cấp tiếp phần còn thiếu của khẩu phần; không đổ lại nguyên khẩu phần từ đầu. Nếu mất điện quá 1 giờ, thiết bị không tự mở servo mà gửi thông báo đến App. Người dùng xem phiên bị gián đoạn và chủ động bấm **Cấp lại** trên App.
- **Các bước test trên Wokwi:**
  1. Chọn `sim auto`, đặt bát ở mức cân dưới sức chứa rồi bắt đầu cấp khẩu phần 100 g.
  2. Khi Serial báo `DISPENSING`, nhập `sim powerloss 30` để lưu phiên vào NVS và khởi động lại với thời gian mất điện giả lập là 30 giây.
  3. Chờ cân ổn định sau khi khởi động. Quan sát servo tự chạy tiếp phần còn thiếu của chính khẩu phần đó.
  4. Thử lại từ đầu, nhưng nhập `sim powerloss 3601` để giả lập mất điện 1 giờ và 1 giây.
  5. Mở App; trên trang **Cho ăn**, bấm **Cấp lại** để gửi lệnh cho phần còn thiếu.
- **Các bước test trên ESP32 thật:**
  1. Bắt đầu cấp thức ăn, rồi ngắt nguồn giữa phiên.
  2. Bật lại trong vòng 1 giờ để thiết bị tự tiếp tục sau khi cân ổn định; ở lần thử khác, để mất điện hơn 1 giờ rồi bật lại.
  3. Với lần mất điện quá 1 giờ, mở App và bấm **Cấp lại**.
- **Kết quả:**
  - Điện trở lại trong 1 giờ: thiết bị tự cấp phần còn thiếu, không cấp trùng lượng đã cân được.
  - Mất điện quá 1 giờ: thiết bị chờ người dùng quyết định; App nhận thông báo và chỉ cấp lại sau khi người dùng bấm nút.
  - Lịch sử ghi nhận phiên cũ bị gián đoạn và kết quả của lượt cấp tiếp theo.
- **Lưu ý:** `sim powerloss GIÂY` chỉ có trong firmware Wokwi. ESP32 thật dùng thời gian từ heartbeat cuối backend nhận được; nếu chưa đồng bộ được với máy chủ, thiết bị dùng tuổi phiên làm ngưỡng bảo thủ. Cân phải ổn định để tính đúng phần còn thiếu.

## Ghi chú triển khai

Khi mất điện quá 1 giờ, App nhận trạng thái phiên gián đoạn sau khi thiết bị kết nối lại với backend. Thông báo hiện hiển thị trong App; gửi thông báo đẩy khi App đã đóng cần cấu hình dịch vụ push riêng.
