# PetFeeder - Hệ Thống Cho Thú Cưng Ăn Tự Động (IoT)

Đồ án môn Internet of Things - Khoa Công nghệ Thông tin, Trường Đại học Công Thương TP. HCM.

## 👥 Thành viên nhóm thực hiện (Nhóm 7)
1. **Nguyễn Duy Linh** - 2001230443 (14DHTH04)
2. **Ngô Công Danh** - 2001230091 (14DHTH13)
3. **Lê Hoàng Bảo Long** - 2001230404 (14DHTH10)

---

## 🏛️ Kiến trúc tổng thể hệ thống

```
Mobile App (Flutter)
       │
       │ HTTP / REST API (Port 3000)
       ▼
Backend (Node.js Express)
       │
       │ MQTT Publish / Subscribe (Port 1883)
       ▼
Mosquitto Broker (Ubuntu WSL / Localhost / Cloud Broker)
       │
       │ Push / Telemetry
       ▼
ESP32 Controller trên Wokwi (Servo vòng kín, Anti-jam, HX711, HC-SR04, OLED, Nút bấm)
```

---

## 📁 Cấu trúc thư mục dự án

```
IoT/
├── PetFeeder/              # Mã nguồn firmware ESP32 (PlatformIO & Wokwi Simulation)
│   ├── src/main.cpp        # Logic điều khiển vòng kín, chống kẹt, lọc lệnh trùng, MQTT
│   ├── diagram.json        # Sơ đồ kết nối phần cứng mô phỏng trên Wokwi
│   └── platformio.ini      # Cấu hình PlatformIO & thư viện
│
├── petfeeder_backend/      # REST API & MQTT Gateway (Node.js Express)
│   ├── src/server.js       # Khởi chạy Express Server
│   ├── src/mqttClient.js   # Kết nối Mosquitto MQTT broker
│   ├── src/storage.js      # Hệ thống lưu trữ dữ liệu & bộ nhớ bền vững (Memory Systems)
│   └── src/routes/         # Các API: feeding, schedules, device, notifications
│
├── petfeeder_app/          # Ứng dụng di động (Flutter)
│   ├── lib/main.dart       # Ứng dụng chính với 4 tab điều khiển
│   ├── lib/screens/        # Dashboard (Giám sát & Cho ăn), Schedules, History, Settings
│   ├── lib/theme/          # Ngôn ngữ thiết kế (Terracotta, Slate, Sage Green)
│   └── lib/services/       # API Service kết nối Backend
│
└── BaoCaoGiaiDoan2.docx    # Báo cáo kiến trúc và thiết kế hệ thống Giai đoạn 2
```

---

## ⚙️ Các tính năng cốt lõi

1. **Điều khiển cấp thức ăn định lượng vòng kín (Closed-loop)**: Đo khối lượng thực tế rơi xuống bát bằng Load Cell + HX711, cấp theo từng nhịp nhỏ cho tới khi đạt đúng khẩu phần mục tiêu (FR-02, FR-03).
2. **Cơ chế chống cho ăn trùng & Ghi đè (Duplicate Feed Protection & Override)**: Chặn cấp thêm nếu bữa trước diễn ra cách đó ít hơn ngưỡng an toàn $T_{safe}$ (180s); cho phép người dùng nhấn giữ nút tại chỗ > 2.5s hoặc gạt Switch Override trên ứng dụng để cưỡng bức cấp (Section 2.3.2).
3. **Cơ chế tự phục hồi chống kẹt hạt (Anti-Jam Recovery)**: Tự động phát hiện khi khối lượng không tăng, đảo chiều Servo chính và kích hoạt cơ cấu phụ lắc phễu 3 lần liên tiếp trước khi báo lỗi (Section 2.3.3).
4. **Hoạt động ngoại tuyến khi mất Internet (FR-04)**: Đồng bộ danh sách lịch từ Backend vào bộ nhớ ESP32, tự động kích hoạt cấp hạt đúng giờ kể cả khi mất kết nối mạng.
5. **Theo dõi mức thức ăn & Cân bát theo thời gian thực (FR-05, FR-06)**: Cảm biến siêu âm HC-SR04 đo lượng hạt còn lại trong phễu chứa, cân Load Cell báo gram thức ăn trong bát.

---

## 🚀 Hướng dẫn cài đặt và chạy thử nghiệm

### 1. Khởi chạy Mosquitto Broker (Ubuntu WSL)
```bash
sudo service mosquitto start
```

### 2. Khởi chạy Backend Server
```bash
cd petfeeder_backend
npm install
npm start
```
* Backend API hoạt động tại: `http://localhost:3000`
* Tài liệu endpoint tại: `http://localhost:3000/api`

### 3. Mô phỏng ESP32 trên Wokwi
* Mở thư mục `PetFeeder` trong VS Code.
* Mở file `diagram.json` và nhấn nút **Start Simulation** (phím tắt `F1` -> `Wokwi: Start Simulator`).

### 4. Khởi chạy Mobile App (Flutter)
```bash
cd petfeeder_app
flutter pub get
flutter run -d chrome  # hoặc flutter run trên thiết bị / emulator
```
