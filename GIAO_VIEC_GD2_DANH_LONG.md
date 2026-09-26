# GIAO VIỆC GIAI ĐOẠN 2 – NHÓM 7
## Đề tài: Hệ thống cho thú cưng ăn tự động

Kiến trúc hệ thống tại **Mục 2.1** đã được chốt. Hai phần còn lại cần bám đúng kiến trúc này để tránh đổi qua đổi lại và tránh conflict.

---

# 1. Kiến trúc đã chốt – không tự ý thay đổi

Luồng tổng thể:

```text
Mobile App
    ⇅ REST API
Backend / Server
    ⇅ MQTT qua Wi-Fi
ESP32 – Feeding Controller
    ⇅
Cảm biến / cơ cấu chấp hành
```

Các điểm bắt buộc giữ:

- Chỉ dùng **Mobile App**, không có Web.
- ESP32 là bộ điều khiển trung tâm tại thiết bị.
- Ba nguồn yêu cầu cho ăn:
  - Mobile App.
  - Lịch tự động.
  - Push Button trên thiết bị.
- HC-SR04 dùng để theo dõi mức thức ăn trong hộp.
- HX711 + Load Cell dùng để đo lượng thức ăn thực tế tại bát.
- Có cơ chế chống cho ăn trùng.
- Có phản hồi tại chỗ bằng OLED/LED/Buzzer.
- Có cơ chế phát hiện kẹt/cấp thiếu và thử tự chống kẹt trước khi báo lỗi.
- Khẩu phần được kiểm tra theo hướng closed-loop: cấp → cân lại → thiếu thì cấp bổ sung.
- Khi thao tác bằng Button, nếu lệnh bị chặn phải phản hồi tại máy; có thể dùng thao tác giữ nút để Override.

Nếu cần thay đổi một trong các điểm trên phải trao đổi cả nhóm trước.

---

# 2. NGÔ CÔNG DANH – PHẦN CỨNG VÀ WOKWI

## Phần cần hoàn thiện trong Word

```text
2.2. THIẾT KẾ PHẦN CỨNG VÀ MÔ HÌNH WOKWI

2.2.1. Lựa chọn linh kiện
2.2.2. Sơ đồ khối phần cứng
2.2.3. Mô hình Wokwi dự kiến
```

## 2.2.1. Lựa chọn linh kiện

Hai thành phần đã chốt:

- **HC-SR04**: đo mức thức ăn trong hộp.
- **HX711 + Load Cell**: đo khối lượng thức ăn thực tế tại bát.

Danh cần chốt các thành phần còn lại:

- ESP32 cụ thể dùng trong Wokwi.
- Cơ cấu cấp thức ăn chính: ưu tiên Servo nếu phù hợp mô hình.
- Cơ cấu chống kẹt: Servo phụ / motor phụ / cơ cấu tương đương có thể mô phỏng.
- Push Button.
- OLED.
- LED.
- Buzzer.
- Giải pháp giữ thời gian/lịch cục bộ nếu cần thêm RTC; phải giải thích rõ có thật sự cần hay không.

Với **mỗi linh kiện**, cần có:

| Nội dung | Yêu cầu |
|---|---|
| Tên linh kiện | Tên đầy đủ |
| Vai trò | Nó giải quyết chức năng nào |
| Lý do chọn | Vì sao phù hợp đề tài |
| Input/Output | Gửi/nhận gì với ESP32 |
| Wokwi | Có được Wokwi hỗ trợ hay không |
| Phương án thay thế | Nếu linh kiện thật không mô phỏng trực tiếp |

### Lưu ý

Không chọn linh kiện chỉ vì “thấy hay”. Mỗi linh kiện phải map được vào kiến trúc Mục 2.1.

Ví dụ:

```text
HC-SR04
→ FR-05 Theo dõi mức thức ăn

Load Cell
→ Đo lượng cấp thực tế
→ Closed-loop Portion Control
→ Hỗ trợ phát hiện kẹt/cấp thiếu
```

## 2.2.2. Sơ đồ khối phần cứng

Sơ đồ tối thiểu phải thể hiện:

```text
HC-SR04 ────────────┐
HX711 + Load Cell ──┤
Push Button ─────────┤
                     ▼
                   ESP32
                     │
        ┌────────────┼────────────┐
        ▼            ▼            ▼
Cơ cấu cấp      Cơ cấu chống    OLED/LED/
thức ăn         kẹt             Buzzer
```

Không cần viết firmware hoàn chỉnh ở GĐ2.

## 2.2.3. Mô hình Wokwi dự kiến

Cần:

- Tạo project Wokwi nháp.
- Đặt đủ linh kiện chính.
- Nối chân dự kiến.
- Kiểm tra tối thiểu rằng project mở được và linh kiện không lỗi.
- Chụp/xuất hình mô hình để đưa vào Word.
- Gửi link Wokwi cho nhóm.

### Deliverable

```text
02_Hardware_Wokwi/
├── hardware.md
├── hardware-block.png
├── wokwi-model.png
└── wokwi-link.txt
```

### Deadline

- **18:00 Thứ hai 14/09/2026:** chốt danh sách linh kiện.
- **22:00 Thứ hai 14/09/2026:** hoàn thành 2.2.1 + 2.2.2 + project Wokwi nháp.
- **18:00 Thứ ba 15/09/2026:** gửi bản hoàn chỉnh để merge.

---

# 3. LÊ HOÀNG BẢO LONG – LUỒNG HOẠT ĐỘNG

## Phần cần hoàn thiện trong Word

```text
2.3. LUỒNG HOẠT ĐỘNG CỦA HỆ THỐNG

2.3.1. Luồng cho ăn từ lịch, Mobile App và Push Button
2.3.2. Luồng chống cho ăn trùng và phản hồi tại chỗ
2.3.3. Luồng phát hiện kẹt và tự phục hồi
2.3.4. Đối chiếu yêu cầu Giai đoạn 1 với thiết kế Giai đoạn 2

2.4. KẾT LUẬN CHƯƠNG
```

Long có thể bắt đầu flow logic ngay từ kiến trúc 2.1. Sau khi Danh chốt phần cứng thì cập nhật tên linh kiện cụ thể vào flow.

## 2.3.1. Luồng cho ăn chung

Không vẽ ba flow độc lập cho App, Schedule và Button.

Ba nguồn phải hội tụ vào một **Feeding Controller**:

```text
Mobile App ────┐
Schedule ───────┼──→ Feeding Controller
Push Button ────┘
```

Flow chính nên có:

```text
Nhận yêu cầu FEED
        ↓
Kiểm tra chống cho ăn trùng
        ↓
HC-SR04 kiểm tra mức thức ăn
        ↓
Đọc Load Cell trước khi cấp
        ↓
Kích hoạt cơ cấu cấp
        ↓
Đọc Load Cell sau khi cấp
        ↓
Đạt khẩu phần?
   ├─ Có → SUCCESS
   └─ Không → cấp bổ sung / kiểm tra lỗi
```

## 2.3.2. Chống cho ăn trùng và phản hồi tại chỗ

Phải thể hiện trường hợp:

```text
18:00 Schedule đã cấp thức ăn
18:03 người dùng bấm Button
```

Kết quả:

```text
BLOCKED
↓
OLED hiển thị lý do
LED/Buzzer phản hồi
Mobile App nhận sự kiện
```

Nếu giữ cơ chế Override:

```text
Giữ Button đủ thời gian
→ BUTTON_OVERRIDE
→ cho ăn
→ ghi log
→ gửi thông báo Mobile App
```

## 2.3.3. Phát hiện kẹt và tự phục hồi

Logic phải phân biệt tối thiểu:

### Hết thức ăn

```text
HC-SR04 → EMPTY
→ không cấp
→ cảnh báo
```

### Nghi kẹt / cấp thất bại

```text
HC-SR04 → vẫn còn thức ăn
Cơ cấu cấp → đã kích hoạt
Load Cell → gần như không tăng
→ JAM SUSPECTED
```

Sau đó:

```text
Đảo/lắc cơ cấu cấp
        ↓
Kích hoạt cơ cấu chống kẹt
        ↓
Thử cấp lại
        ↓
Load Cell xác minh
     ┌──────┴──────┐
     ↓             ↓
SUCCESS        JAM ERROR
```

## 2.3.4. Mapping GĐ1 → GĐ2

Lập bảng tương tự:

| Yêu cầu GĐ1 | Thành phần/logic đáp ứng ở GĐ2 |
|---|---|
| FR-01 Quản lý lịch | Mobile App + Backend + lịch cục bộ ESP32 |
| FR-02 Khẩu phần | Mobile App + Closed-loop Portion Control |
| FR-03 Cho ăn tự động | ESP32 + cơ cấu cấp |
| FR-04 Mất Internet | Lịch cục bộ trên ESP32 |
| FR-05 Mức thức ăn | HC-SR04 |
| FR-06 Bất thường | HC-SR04 + Load Cell + trạng thái cơ cấu |
| FR-07 Thông báo | Backend + Notification + Local Feedback |
| FR-08 Điều khiển từ xa | Mobile App → Backend → MQTT → ESP32 |
| FR-09 Cho ăn tại chỗ | Push Button |
| FR-10 Lịch sử | Backend/Database + nguồn lệnh + kết quả |

Có thể điều chỉnh sau khi phần cứng của Danh được chốt.

## 2.4. Kết luận chương

Viết ngắn khoảng 1 đoạn, chỉ sau khi 2.2 và 2.3 hoàn chỉnh.

Nội dung:

- Đã chốt kiến trúc.
- Đã lựa chọn phần cứng/mô hình Wokwi.
- Đã xác định các luồng vận hành chính.
- Đây là đầu vào cho giai đoạn lập trình, mô phỏng và kiểm thử tiếp theo.

### Deliverable

```text
03_Flow/
├── flow.md
├── system-flow.png
├── anti-duplicate-flow.png        # nếu tách hình
├── jam-recovery-flow.png          # nếu tách hình
└── requirement-mapping.md
```

### Deadline

- **22:00 Thứ hai 14/09/2026:** flow logic bản nháp 60–70%.
- **Sau khi Danh chốt linh kiện:** cập nhật tên phần cứng thật vào flow.
- **22:00 Thứ ba 15/09/2026:** hoàn thành toàn bộ Mục 2.3 + 2.4.

---

# 4. MỐC REVIEW CHUNG

## 22:00 Thứ ba 15/09/2026

Freeze nội dung kỹ thuật.

Kiểm tra chéo:

- Linh kiện của Danh có xuất hiện đúng trong kiến trúc/flow không?
- Flow của Long có dùng chức năng mà phần cứng không hỗ trợ không?
- Có linh kiện nào được chọn nhưng không phục vụ chức năng nào không?
- Các yêu cầu quan trọng ở GĐ1 đã được map chưa?

## Thứ tư 16/09/2026

- Trước **12:00**: merge vào Word.
- **12:00–18:00**: review nội dung và hình.
- Sau **18:00**: chỉ sửa format, caption, mục lục, chính tả.
- **23:00**: deadline cứng.

---

# 5. QUY TẮC CHỐNG CONFLICT

```text
01_Architecture/      → Linh
02_Hardware_Wokwi/    → Danh
03_Flow/              → Long
Final/                → chỉ một người merge
```

Không sửa trực tiếp file phần của người khác.

Nếu Danh thay linh kiện làm thay đổi logic, phải báo Long và Linh.
Nếu Long cần thêm chức năng/phần cứng mới để hoàn thành flow, phải báo trước khi thêm.
