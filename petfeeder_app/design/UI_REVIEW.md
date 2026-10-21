# Rà soát giao diện mobile PetFeeder

Đã rà soát toàn bộ `lib/`: app shell, theme, 4 màn hình, model và API service. Model và hợp đồng backend giữ nguyên. Không thêm dependency giao diện.

| Khu vực | Thay đổi |
| --- | --- |
| Điều hướng | Một app bar duy nhất, Material 3 NavigationBar có nhãn; giữ nội dung và vị trí cuộn khi đổi tab. |
| Tổng quan | Hero xanh đậm, trạng thái tiếng Việt, mức hạt và cân bát rõ ràng; dữ liệu ngoại tuyến hiển thị chưa xác định. |
| Cho ăn | Chọn nhanh khẩu phần và nút ngắn gọn; khóa thao tác lúc gửi; ghi đè chỉ áp dụng cho một yêu cầu sau cảnh báo ăn trùng. |
| Lịch ăn | Giờ ăn nổi bật, công tắc bật/tắt, chọn ngày lặp, biểu mẫu cuộn theo bàn phím; kiểm tra kết quả trước khi xóa. |
| Nhật ký | Ngày giờ, lượng thực cấp, mục tiêu và nguồn lệnh phân cấp rõ; xác nhận xóa, lỗi tải có nút thử lại. |
| Cài đặt | Kiểm tra URL trước khi áp dụng; địa chỉ thất bại không thay địa chỉ đang dùng; chi tiết phát triển và phần cứng nằm trong mục mở rộng. |
| Thành phần chung | Theme, khung trang giới hạn 680 px, heading, card, badge, empty state và portion selector dùng chung. |

Điều chỉnh theo phản hồi: nút chính/phụ và chip bo cong dạng viên thuốc; nút chính cao tối thiểu 56 px; nút biểu tượng hình tròn; thẻ bo 28 px; ô nhập bo 22 px; chip đang chọn có nền xanh, chữ trắng và dấu chọn; thanh trượt bỏ các vạch chia; thanh điều hướng bo góc trên; biểu mẫu thêm lịch có nút đóng rõ ràng. Quy tắc này cũng đã cập nhật trong skill dùng lại.

Ảnh trong `previews/` được render từ widget thật với API giả lập, không phải trạng thái máy cho ăn thật: `dashboard.png`, `feeding.png`, `schedules.png`, `schedule-editor.png`, `history.png`, `settings.png`.

## Kiểm tra

- `flutter analyze`
- `flutter test` — 11 widget tests: 320 px, 390 px, 768 px; chữ tới 200%; bốn tab; ngoại tuyến; trạng thái lỗi/rỗng; giữ state; chống gửi lặp; ghi đè một lần; bàn phím; chọn ngày; xóa thất bại; kiểm tra URL.
- Skill được kiểm tra bằng `skill-creator/scripts/quick_validate.py`.
- SDK máy kiểm tra: Flutter với Dart 3.11.0. `flutter pub get --offline` cập nhật bốn dependency gián tiếp bị SDK ghim phiên bản trong lockfile: characters, matcher, material_color_utilities, test_api. Không thay khai báo dependency trong pubspec.yaml.

Để render lại ảnh, đặt `PETFEEDER_PREVIEW_DIR` tới thư mục xuất ảnh và `PETFEEDER_PREVIEW_FONT` tới `roboto-regular.ttf` trong `bin/cache/artifacts/material_fonts/` của Flutter SDK, rồi chạy:

```powershell
flutter test --plain-name 'four tab previews'
```

Chưa xác minh trên điện thoại hoặc ESP32 thật. Địa chỉ kết nối vẫn có hiệu lực trong phiên chạy hiện tại, theo cơ chế sẵn có của ứng dụng.

## Tối ưu bố cục theo phản hồi tiếp theo

- Bỏ khối giới thiệu lớn; dùng dải trạng thái ngắn, hai ô số liệu cạnh nhau khi đủ chỗ và khối cho ăn ngay bên dưới. Trên khung 390 × 844 ở cỡ chữ mặc định, thấy nút cho ăn và hai số liệu mà không cần cuộn.
- Hai ô số liệu tự xếp dọc khi màn hình hẹp hoặc phóng lớn chữ. Thời điểm cho ăn gần nhất vẫn hiển thị dưới khối thao tác.
- Khẩu phần được chọn thể hiện bằng màu nền và chữ đậm, giữ chiều rộng ổn định; đủ năm nút chọn nhanh trên một hàng ở điện thoại 390 px.
- Tiêu đề các trang rõ tác vụ hơn; rút gọn chiều cao app bar, khoảng cách, thẻ lịch và nhật ký; cài đặt có tiêu đề kết nối gọn trong một hàng.
- Đối chiếu mã trước/sau xác nhận các hàm hành động của bốn màn hình, API service và model giữ nguyên. Không thay đổi chức năng trong đợt tối ưu bố cục này.
- Bộ kiểm thử được mở rộng lên 11 bài, thêm điện thoại 320 px ở chữ 200% và khả năng thấy nút cho ăn ngay màn hình đầu.

Quy tắc dùng lại nằm tại `skills/petfeeder-mobile-ui/SKILL.md` ở gốc repository; `petfeeder_app/AGENTS.md` yêu cầu áp dụng khi sửa UI.
