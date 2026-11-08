# Kịch bản xử lý tình huống

File này giữ đúng 5 tình huống cần mô phỏng. Nút vật lý trên mạch vẫn dùng để cấp thức ăn như bình thường.

## Chuẩn bị Wokwi

- Mở Serial Monitor ở 115200 baud và chờ ESP32 kết nối.
- Gõ `status` để xem trạng thái thiết bị.
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

- **Nguyên lý:** Firmware lọc số cân HX711 bằng trung bình trượt 5 mẫu (MA5), theo dõi biên độ dao động và chỉ xem cân ổn định lại sau khi các mẫu nằm trong ngưỡng ổn định.
- **Các bước test trên Wokwi:**
  1. Chọn `sim manual`, đặt cân về mức ổn định và chờ Serial báo cân ổn định lúc khởi động.
  2. Bắt đầu cấp thức ăn.
  3. Trong lúc cấp, kéo HX711 lên xuống nhẹ vài lần để mô phỏng bát bị rung hoặc xê dịch.
  4. Dừng thay đổi tải và chờ cân ổn định lại.
- **Kết quả:**
  - Serial báo `CẢNH BÁO CÂN DAO ĐỘNG` khi MA5 vượt ngưỡng.
  - Khi cân hết rung, Serial báo `Cân ổn định trở lại`.
  - Trong lúc số cân chưa ổn định, servo tạm dừng; khi cân ổn định, phiên cấp tiếp tục.
- **Lưu ý:** Cảm biến chỉ nhận biết số cân dao động, không xác định được nguyên nhân là thú cưng rung bát hay tác động khác.

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

- **Nguyên lý:** ESP32 vẫn có điện và lịch đã được lưu trong NVS trước khi mất mạng. Vì vậy thiết bị tự kiểm tra giờ và chạy lịch tại chỗ; sự kiện cho ăn được giữ lại để đồng bộ khi mạng trở lại.
- **Các bước test trên Wokwi hoặc thiết bị:**
  1. Tạo lịch ăn sắp đến giờ và chờ thiết bị nhận lịch, xác nhận Serial có `CONFIG_APPLIED`.
  2. Ngắt Wi-Fi hoặc MQTT nhưng giữ ESP32 đang bật; không nhấn reset.
  3. Chờ đến giờ ăn trong lịch.
  4. Nối mạng lại và kiểm tra lịch sử trên App/backend.
- **Kết quả:**
  - Thiết bị dùng lịch đã lưu để cấp thức ăn dù App/backend đang mất kết nối.
  - Sự kiện được gửi lên sau khi mạng trở lại, không tạo lịch sử trùng.
  - Lịch trễ từ 60 giây trở lên bị bỏ qua, không cấp dồn.

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
