# PHÂN CÔNG CÔNG VIỆC – GIAI ĐOẠN 2
## Đề tài: Hệ thống cho thú cưng ăn tự động

**Nhóm 7**
- Nguyễn Duy Linh – 2001230443
- Ngô Công Danh – 2001230091
- Lê Hoàng Bảo Long – 2001230404

**Thời gian thực hiện:** từ Chủ nhật **13/09/2026** đến hết Thứ tư **16/09/2026**

---

# 1. Mục tiêu Giai đoạn 2

Giai đoạn 2 tập trung vào **thiết kế kiến trúc và mô hình hệ thống IoT**, chưa đi sâu vào cài đặt hoàn chỉnh.

Các đầu việc chính:

1. Thiết kế kiến trúc tổng thể của hệ thống.
2. Lựa chọn phần cứng phù hợp để mô phỏng trên Wokwi.
3. Xây dựng sơ đồ khối phần cứng và mô hình Wokwi dự kiến.
4. Xây dựng luồng hoạt động chính của hệ thống.
5. Đối chiếu thiết kế Giai đoạn 2 với các yêu cầu đã xác định ở Giai đoạn 1.

> **Không làm sâu trong Giai đoạn 2:** code ESP32 hoàn chỉnh, MQTT topic chi tiết, database schema hoàn chỉnh, kiểm thử hiệu năng, demo hoàn chỉnh hoặc đánh giá kết quả. Các phần này để dành cho Giai đoạn 3 và Giai đoạn 4.

---

# 2. Quy ước chung để tránh conflict

Trước khi chia ra làm riêng, cả nhóm thống nhất một **Interface Contract** và không tự ý thay đổi khi chưa báo nhóm.

## 2.1. Interface Contract

### Bộ điều khiển chính
- ESP32.

### Input của thiết bị
- Mức thức ăn.
- Khối lượng thức ăn tại bát.
- Nút cho ăn tại chỗ.
- Lịch cho ăn.
- Khẩu phần.
- Lệnh cho ăn ngay từ hệ thống.

### Output của thiết bị
- Servo cấp thức ăn.
- LED trạng thái.
- Buzzer cảnh báo.

### Server/App gửi xuống ESP32
- Lịch cho ăn.
- Khẩu phần.
- Lệnh cho ăn ngay.

### ESP32 gửi lên Server/App
- Mức thức ăn.
- Khối lượng tại bát.
- Trạng thái thiết bị.
- Kết quả cho ăn.
- Trạng thái lỗi/cảnh báo.

---

# 3. Phân công cho Nguyễn Duy Linh

## Vai trò
**Kiến trúc hệ thống + tích hợp báo cáo cuối**

## Phần phụ trách

### 3.1. Kiến trúc tổng thể hệ thống IoT

Thiết kế sơ đồ kiến trúc gồm tối thiểu các thành phần:

```text
Người dùng
    ↓
Web / Mobile App
    ↓
Server / IoT Service
    ↓
Wi-Fi / Internet
    ↓
ESP32
    ├── Cảm biến
    └── Cơ cấu chấp hành
```

Cần mô tả rõ:

- Người dùng thao tác ở đâu.
- App/Web gửi thông tin gì.
- Server/IoT Service giữ vai trò gì.
- ESP32 nhận dữ liệu gì.
- ESP32 gửi trạng thái gì về hệ thống.
- Các cảm biến và cơ cấu chấp hành nằm ở lớp thiết bị.

### 3.2. Luồng dữ liệu ở mức tổng quan

Chỉ mô tả mức tổng quan, chưa cần topic MQTT hoặc JSON chi tiết.

Ví dụ:

```text
App → Server:
- Lịch cho ăn
- Khẩu phần
- Lệnh cho ăn ngay

Server → ESP32:
- Lịch đã lưu
- Khẩu phần
- Lệnh điều khiển

ESP32 → Server:
- Mức thức ăn
- Khối lượng
- Trạng thái thiết bị
- Kết quả cho ăn

Server → App:
- Trạng thái
- Lịch sử
- Cảnh báo
```

### 3.3. Sản phẩm phải bàn giao

- `architecture.md`
- `architecture.png`
- Phần mô tả kiến trúc khoảng 1–2 trang.
- Luồng dữ liệu mức tổng quan.
- Kiểm tra tính thống nhất giữa kiến trúc với phần cứng và flow của hai thành viên còn lại.

### 3.4. Trách nhiệm cuối

Linh là **Integrator**:

- Chỉ Linh sửa file Word/Markdown tổng cuối.
- Danh và Long gửi phần đã hoàn thành để Linh ghép.
- Chuẩn hóa tên hình, số mục, font và cách trình bày.
- Kiểm tra thuật ngữ giữa ba phần không bị mâu thuẫn.

### Không được tự ý làm

- Không tự đổi linh kiện của Danh.
- Không tự thay đổi flow xử lý của Long nếu chưa trao đổi.
- Không tự thêm công nghệ mới sau khi Interface Contract đã chốt.

---

# 4. Phân công cho Ngô Công Danh

## Vai trò
**Phần cứng + mô hình Wokwi dự kiến**

## Phần phụ trách

### 4.1. Lựa chọn phần cứng

Nghiên cứu và đề xuất tối thiểu:

| Linh kiện | Vai trò dự kiến |
|---|---|
| ESP32 | Bộ điều khiển trung tâm |
| Servo Motor | Cơ cấu cấp thức ăn |
| HC-SR04 | Theo dõi mức thức ăn |
| HX711 + Load Cell | Đo lượng thức ăn tại bát |
| Push Button | Cho ăn tại chỗ |
| LED | Hiển thị trạng thái |
| Buzzer | Cảnh báo lỗi |
| RTC | Xem xét dùng cho lịch cục bộ/offline |

Với mỗi linh kiện cần ghi:

- Chức năng.
- Lý do chọn.
- Input/Output chính.
- Có mô phỏng được trên Wokwi hay không.
- Nếu chưa chắc mô phỏng được, ghi rõ cần thay bằng phần tử tương đương nào.

### 4.2. Sơ đồ khối phần cứng

Thiết kế sơ đồ theo dạng:

```text
HC-SR04 ─────┐
HX711 ───────┤
Button ──────┤
             ▼
           ESP32
             │
      ┌──────┼──────┐
      ▼      ▼      ▼
    Servo   LED   Buzzer
```

### 4.3. Mô hình Wokwi dự kiến

Ở Giai đoạn 2 chỉ cần:

- Tạo project Wokwi nháp.
- Thêm các linh kiện dự kiến.
- Bố trí sơ đồ kết nối ở mức mô hình.
- Chưa bắt buộc viết code hoàn chỉnh.
- Có thể dùng code tối thiểu để kiểm tra linh kiện nếu cần.

### 4.4. Sản phẩm phải bàn giao

- `hardware.md`
- `hardware-block.png`
- Link/project Wokwi nháp.
- Bảng linh kiện.
- Ghi chú các điểm cần kiểm chứng ở Giai đoạn 3.

### Không được tự ý làm

- Không đổi kiến trúc Server/App.
- Không tự thêm chức năng ngoài Interface Contract.
- Nếu cần thêm/bớt sensor phải báo cả nhóm trước.

---

# 5. Phân công cho Lê Hoàng Bảo Long

## Vai trò
**Luồng hoạt động + đối chiếu yêu cầu Giai đoạn 1**

## Phần phụ trách

### 5.1. Luồng hoạt động tổng quát

Thiết kế một flow chính:

```text
Bắt đầu
   ↓
Đọc lịch cho ăn
   ↓
Đến giờ?
   ├── Không → Tiếp tục chờ
   │
   └── Có
        ↓
Kiểm tra mức thức ăn
        ↓
Còn thức ăn?
   ├── Không → Cảnh báo
   │
   └── Có
        ↓
Kích hoạt Servo
        ↓
Cấp thức ăn
        ↓
Kiểm tra kết quả
        ↓
Cập nhật trạng thái
        ↓
Kết thúc
```

### 5.2. Các luồng phụ cần mô tả

Không cần vẽ quá nhiều sơ đồ; chỉ cần mô tả ngắn hoặc gắn nhánh vào flow chính.

Các tình huống:

1. Cho ăn theo lịch.
2. Cho ăn bằng nút tại thiết bị.
3. Sắp hết thức ăn.
4. Hết thức ăn.
5. Cấp thức ăn thất bại/kẹt.
6. Mất Internet nhưng lịch local vẫn tiếp tục chạy.

### 5.3. Đối chiếu với yêu cầu Giai đoạn 1

Lập bảng mapping:

| Yêu cầu | Thiết kế GĐ2 hỗ trợ bằng |
|---|---|
| Quản lý lịch | App/Server + lịch lưu xuống ESP32 |
| Cho ăn tự động | ESP32 + Servo |
| Hoạt động khi mất Internet | Lịch cục bộ trên ESP32 |
| Theo dõi mức thức ăn | HC-SR04 |
| Phát hiện bất thường | Load Cell/HX711 + logic kiểm tra |
| Cho ăn tại chỗ | Push Button |
| Cảnh báo | Buzzer/LED + trạng thái gửi lên Server |

### 5.4. Kết luận Giai đoạn 2

Viết khoảng 1 đoạn ngắn:

- Giai đoạn 2 đã xác định được kiến trúc.
- Đã chọn được phần cứng.
- Đã xây dựng được luồng hoạt động.
- Đây là cơ sở để sang Giai đoạn 3 triển khai mô phỏng và lập trình.

### 5.5. Sản phẩm phải bàn giao

- `flow.md`
- `system-flow.png`
- Bảng mapping yêu cầu.
- Đoạn kết luận Giai đoạn 2.

### Không được tự ý làm

- Không tự đổi linh kiện.
- Không tự thay kiến trúc App/Server/ESP32.
- Nếu phát hiện flow không thể hiện thực với phần cứng hiện tại thì báo cả nhóm để thống nhất sửa.

---

# 6. Cấu trúc thư mục chung

```text
GiaiDoan2/

├── 01_Architecture/
│   ├── architecture.md
│   └── architecture.png
│
├── 02_Hardware_Wokwi/
│   ├── hardware.md
│   ├── hardware-block.png
│   └── wokwi-link.txt
│
├── 03_Flow/
│   ├── flow.md
│   └── system-flow.png
│
└── Final/
    └── Nhom7_GiaiDoan2.docx
```

## Quy tắc

- Linh chỉ sửa `01_Architecture` và `Final`.
- Danh chỉ sửa `02_Hardware_Wokwi`.
- Long chỉ sửa `03_Flow`.
- Không sửa trực tiếp file của người khác.
- Nếu cần thay đổi Interface Contract phải báo cả nhóm trước.
- File `Final` chỉ có một người merge để tránh conflict.

---

# 7. Timeline và Deadline

## Chủ nhật – 13/09/2026

### Trước 18:00
Cả nhóm:

- Chốt Interface Contract.
- Chốt danh sách phần cứng dự kiến.
- Chốt cấu trúc báo cáo Giai đoạn 2.
- Tạo thư mục chung.

### Trước 23:00
Mỗi người phải có bản nháp đầu tiên:

**Linh**
- Vẽ bản nháp kiến trúc.
- Viết outline phần kiến trúc.

**Danh**
- Chốt khoảng 80% danh sách linh kiện.
- Tạo project Wokwi nháp.

**Long**
- Vẽ flowchart bản nháp.
- Liệt kê các luồng phụ.

---

## Thứ hai – 14/09/2026

### Deadline: 22:00

Mục tiêu: **hoàn thành khoảng 60–70% phần cá nhân**.

**Linh**
- Hoàn thành sơ đồ kiến trúc.
- Hoàn thành phần mô tả luồng dữ liệu tổng quan.

**Danh**
- Hoàn thành bảng linh kiện.
- Hoàn thành sơ đồ khối phần cứng.
- Wokwi đã có đầy đủ linh kiện chính.

**Long**
- Hoàn thành flowchart.
- Hoàn thành mô tả các tình huống chính.
- Bắt đầu bảng đối chiếu yêu cầu GĐ1.

### 22:00–22:30
Cả nhóm review chéo nhanh:

- Kiến trúc có khớp phần cứng không?
- Phần cứng có đủ để chạy flow không?
- Flow có chức năng nào nằm ngoài kiến trúc không?

---

## Thứ ba – 15/09/2026

### Deadline: 22:00

Mục tiêu: **100% nội dung cá nhân hoàn thành**.

**Linh**
- Hoàn thiện `architecture.md`.
- Export `architecture.png`.

**Danh**
- Hoàn thiện `hardware.md`.
- Export `hardware-block.png`.
- Gửi link Wokwi nháp.

**Long**
- Hoàn thiện `flow.md`.
- Export `system-flow.png`.
- Hoàn thiện bảng mapping yêu cầu.
- Viết kết luận Giai đoạn 2.

### Sau 22:00
Không thêm chức năng mới, trừ khi có lỗi nghiêm trọng.

---

## Thứ tư – 16/09/2026

### Trước 12:00
Linh bắt đầu merge nội dung của cả ba thành viên.

### 12:00–18:00
Cả nhóm review bản ghép:

Kiểm tra:

- Tên linh kiện có thống nhất.
- Tên thành phần kiến trúc có thống nhất.
- Sơ đồ kiến trúc và sơ đồ phần cứng không mâu thuẫn.
- Flow sử dụng đúng các sensor/actuator đã chọn.
- Nội dung không lặp lại quá nhiều Giai đoạn 1.
- Không viết lấn quá sâu sang Giai đoạn 3.

### Deadline nội dung cuối: 18:00

Sau 18:00 chỉ sửa:

- Chính tả.
- Hình ảnh.
- Đánh số mục.
- Caption.
- Format.

### Deadline bản hoàn chỉnh: 21:00

File cần có:

```text
Nhom7_GiaiDoan2_Final.docx
```

### 21:00–23:00
Khoảng đệm để:

- Kiểm tra lần cuối.
- Export PDF nếu cần.
- Backup lên Drive/Git.
- Chuẩn bị nộp.

### DEADLINE CỨNG: 23:00 – Thứ tư 16/09/2026

Sau thời điểm này không chỉnh nội dung lớn nữa.

---

# 8. Checklist hoàn thành

## Nguyễn Duy Linh
- [ ] Kiến trúc tổng thể
- [ ] Sơ đồ kiến trúc
- [ ] Luồng dữ liệu tổng quan
- [ ] Merge báo cáo cuối
- [ ] Kiểm tra tính thống nhất

## Ngô Công Danh
- [ ] Danh sách linh kiện
- [ ] Lý do lựa chọn linh kiện
- [ ] Sơ đồ khối phần cứng
- [ ] Project Wokwi nháp
- [ ] Ghi chú vấn đề cần xử lý ở GĐ3

## Lê Hoàng Bảo Long
- [ ] Flowchart hệ thống
- [ ] Các tình huống xử lý
- [ ] Mapping yêu cầu GĐ1 → thiết kế GĐ2
- [ ] Kết luận GĐ2

## Cả nhóm
- [ ] Interface Contract được chốt
- [ ] Không conflict file
- [ ] Không trùng nội dung
- [ ] Không làm lấn quá nhiều sang GĐ3
- [ ] Final review
- [ ] Backup trước khi nộp
