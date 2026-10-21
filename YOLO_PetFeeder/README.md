# YOLO PetFeeder

Dự án độc lập nhận diện chó/mèo từ webcam laptop hoặc camera USB bằng YOLO11n. Dự án phục vụ trang web camera và cung cấp API để backend PetFeeder đọc kết quả. Model YOLO đã được đặt trong `models/yolo11n.pt`; không cần train lại hoặc tải model khi chạy.

## Chạy camera

Mở PowerShell trong thư mục `YOLO_PetFeeder` và chạy:

```powershell
powershell -ExecutionPolicy Bypass -File .\start-yolo.ps1
```

Script tự tạo môi trường Python và cài thư viện nếu thiếu. Khi terminal báo `Application startup complete`, mở **http://localhost:8002**, nhấn **Mở camera**, rồi cho phép sử dụng camera. Model chạy trên CPU theo mặc định. Dừng camera trong trang trước khi đóng tab.

Máy cần Python 3.13. Lần đầu cài dependencies cần Internet; file trọng số pretrained đã được đóng gói trong `models/`.

## API cho PetFeeder

| Phương thức | Endpoint | Mục đích |
|---|---|---|
| `POST` | `/api/detect` | Nhận khung ảnh JPEG/PNG dạng `multipart/form-data`; trả nhãn, độ tin cậy và bounding box |
| `GET` | `/api/status` | Kết quả mới nhất; hết hạn sau 3 giây không nhận ảnh |
| `GET` | `/api/health` | Kiểm tra server và model |
| `GET` | `/docs` | Thử API qua Swagger UI |

Ví dụ backend Node.js lấy trạng thái thú cưng:

```javascript
const response = await fetch('http://127.0.0.1:8002/api/status');
if (!response.ok) throw new Error('YOLO unavailable');
const pet = await response.json();
if (pet.fresh && pet.pet_detected) {
  console.log('Loài nhận diện:', pet.pet_type);
}
```

`pet_type` là `dog`, `cat`, hoặc `null` nếu không có thú cưng, camera chưa gửi hình mới, hoặc cùng lúc thấy cả hai loài. `confidence` nằm trong khoảng 0–1. Bounding box `[x1, y1, x2, y2]` dùng pixel theo đúng kích thước ảnh đầu vào. `/api/detect` chỉ xử lý ảnh; trang camera tự gửi ảnh chụp từ webcam mỗi 250 ms.

YOLO chạy trên laptop; phần cho ăn tiếp tục đi qua PetFeeder backend/MQTT và ESP32. Endpoint này báo sự hiện diện, không tự gửi lệnh servo. Khi nối điều khiển cho ăn, kiểm tra `fresh`, xác nhận nhiều khung hình liên tiếp và giữ giới hạn chống cho ăn trùng hiện có.

Để đọc trạng thái từ máy khác cùng mạng, khởi động với `$env:YOLO_HOST = '0.0.0.0'`, rồi dùng `http://<IP-laptop>:8002/api/status`. Trang camera nên mở trên laptop tại `http://localhost:8002` vì trình duyệt giới hạn quyền webcam trên HTTP qua IP LAN.
