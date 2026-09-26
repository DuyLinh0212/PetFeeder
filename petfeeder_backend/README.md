# PetFeeder Backend & MQTT Gateway

Backend REST API và MQTT Gateway cho Đề tài IoT **Hệ thống cho thú cưng ăn tự động** (Nhóm 7 - ĐH Công Thương TP.HCM).

## 1. Kiến trúc hệ thống
```
Mobile App (Flutter)
       │
       │ HTTP / REST API (port 3000)
       ▼
petfeeder_backend (Node.js Express)
       │
       │ MQTT Publish / Subscribe (port 1883)
       ▼
Mosquitto Broker (Ubuntu WSL / Localhost / Cloud Broker)
       │
       │ MQTT Push & Telemetry
       ▼
ESP32 (Wokwi Simulation / Hardware)
```

## 2. Cài đặt và khởi chạy

### Bước 1: Khởi động Mosquitto Broker trên Ubuntu WSL
Nếu chưa bật dịch vụ Mosquitto trên Ubuntu WSL:
```bash
sudo service mosquitto start
sudo service mosquitto status
```

> **Lưu ý cấu hình Mosquitto 2.0+**: Để cho phép kết nối từ ngoài localhost (hoặc từ máy ảo/mô phỏng), kiểm tra file cấu hình `/etc/mosquitto/conf.d/default.conf` có 2 dòng sau:
> ```conf
> listener 1883
> allow_anonymous true
> ```
> Sau đó khởi động lại: `sudo service mosquitto restart`

### Bước 2: Cài đặt và chạy Backend
```bash
cd F:\NgDuyLinh\Do_an\IoT\petfeeder_backend
npm install
npm start
```
Server sẽ chạy tại: `http://localhost:3000`  
Kiểm tra API tại: `http://localhost:3000/api`

## 3. Danh sách REST API

| Phương thức | Đường dẫn | Chức năng | Payload / Query |
|---|---|---|---|
| `POST` | `/api/feeding/feed` | Gửi lệnh Cho ăn ngay xuống ESP32 | `{"portion": 30, "override": false}` |
| `GET` | `/api/feeding/history` | Lấy lịch sử các lần cho ăn | `?limit=50` |
| `DELETE` | `/api/feeding/history` | Xóa nhật ký cho ăn | Không |
| `GET` | `/api/schedules` | Lấy danh sách lịch cho ăn | Không |
| `POST` | `/api/schedules` | Tạo lịch mới (tự đồng bộ ESP32) | `{"name": "Bữa sáng", "time": "07:30", "portion_g": 40}` |
| `PUT` | `/api/schedules/:id` | Cập nhật lịch cho ăn | `{"time": "08:00", "portion_g": 50}` |
| `PATCH` | `/api/schedules/:id/toggle` | Bật / tắt lịch cho ăn | Không |
| `DELETE` | `/api/schedules/:id` | Xóa lịch cho ăn | Không |
| `GET` | `/api/device/status` | Lấy thông số thời gian thực | Không |
| `GET` | `/api/device/config` | Lấy cấu hình ngưỡng an toàn | Không |
| `PUT` | `/api/device/config` | Cập nhật cấu hình ESP32 | `{"safe_interval_sec": 180}` |
| `GET` | `/api/notifications` | Lấy cảnh báo kẹt hạt / hết thức ăn | Không |

## 4. Các Topic MQTT quy chuẩn

| Topic | Hướng | Mô tả |
|---|---|---|
| `petfeeder/command` | Backend -> ESP32 | Gửi lệnh cấp thức ăn: `{"command": "FEED", "portion": 40, "override": false}` |
| `petfeeder/schedules/sync` | Backend -> ESP32 | Đồng bộ danh sách lịch để ESP32 tự chạy khi mất mạng (FR-04) |
| `petfeeder/config` | Backend -> ESP32 | Đồng bộ tham số cấu hình (T_safe, ngưỡng khoảng cách) |
| `petfeeder/telemetry` | ESP32 -> Backend | Dữ liệu cảm biến định kỳ: mức hạt (%), khoảng cách (cm), cân nặng bát (g) |
| `petfeeder/events` | ESP32 -> Backend | Kết quả thực tế bữa ăn (`SUCCESS`, `JAM_ERROR`, `EMPTY`, `BLOCKED`) |
| `petfeeder/alerts` | ESP32 -> Backend | Cảnh báo tức thời lỗi phần cứng |
