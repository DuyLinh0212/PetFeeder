# Bật thông báo đẩy cho PetFeeder

App dùng Firebase Cloud Messaging (FCM). Khi App ở nền hoặc đã đóng, Android hiển thị push do FCM gửi; khi App đang mở, App hiển thị thông báo foreground trong notification tray. App hỏi quyền khi người dùng bật **Cài đặt → Thông báo → Cho phép thông báo đẩy**.

Hiện project Flutter có cấu hình Android. Thông báo chỉ được gửi cho sự kiện mất điện quá 1 giờ (`POWER_OUTAGE_RETRY_REQUIRED`); các sự kiện khác tiếp tục hiển thị trong App như hiện tại.

## 1. Cấu hình Firebase cho Android

Android đã đăng ký với project `petfeeder-iot-20261108-duytn` bằng package name `com.example.petfeeder_app`. Cấu hình client nằm tại `petfeeder_app/android/app/google-services.json`; Google Services Gradle plugin tạo các giá trị Firebase mà app đọc khi khởi động. Build Android bình thường, không cần truyền `--dart-define`.

Không đặt service-account key trong App hoặc trong Dart defines. `google-services.json` chứa định danh client không bí mật; service-account JSON chỉ dùng phía backend.

## 2. Bật gửi push ở backend

Backend hiện chưa gửi được push nếu thiếu thông tin xác thực. Tài khoản service account cần role gửi FCM. Ở máy local có thể đặt `FIREBASE_SERVICE_ACCOUNT_FILE=../<ten-file-key>.json`; trên Render đặt nội dung key vào `FIREBASE_SERVICE_ACCOUNT_JSON`. Không commit JSON key này.

Backend lưu Firebase Installation ID (FID) theo từng lần cài đặt và chỉ gửi thông báo sau khi sự kiện đã được lưu thành công. Nếu FCM chưa cấu hình, đăng ký vẫn được lưu nhưng API trả `push_enabled: false`; màn Cài đặt sẽ báo rằng backend chưa bật dịch vụ gửi. Backend log lỗi khởi tạo hoặc gửi FCM mà không in FID.

## 3. Kiểm tra trên điện thoại

1. Cài APK vừa build lên Android có Google Play services.
2. Kết nối App tới đúng backend, mở **Cài đặt → Thông báo** và bật công tắc. Chọn **Cho phép** trong hộp thoại Android.
3. Kiểm tra Android Settings → Apps → PetFeeder → Notifications đang bật.
4. Để App xuống nền hoặc đóng bình thường. Khi backend nhận sự kiện `INTERRUPTED` cùng mã `POWER_OUTAGE_RETRY_REQUIRED`, điện thoại sẽ nhận push để mở App và xác nhận cấp phần còn thiếu.

Nếu tắt công tắc trong App, server ngừng gửi tới lượt cài đặt đó và App gỡ đăng ký Firebase Installation ID (FID). Tắt quyền ở Android Settings cũng chặn hiển thị; cần mở lại quyền và bật công tắc trong App để đăng ký lại.

Project chưa có thư mục `ios/`. Muốn build iOS cần thêm iOS Runner, đăng ký iOS app, thêm `GoogleService-Info.plist` và cấu hình APNs credentials trong Firebase trước khi phát hành.
