# Bật thông báo đẩy cho PetFeeder

App dùng Firebase Cloud Messaging (FCM). Khi App ở nền hoặc đã đóng, Android hiển thị push do FCM gửi; khi App đang mở, App hiển thị thông báo foreground trong notification tray. App hỏi quyền khi người dùng bật **Cài đặt → Thông báo → Cho phép thông báo đẩy**.

Hiện project Flutter có cấu hình Android. Thông báo chỉ được gửi cho sự kiện mất điện quá 1 giờ (`POWER_OUTAGE_RETRY_REQUIRED`); các sự kiện khác tiếp tục hiển thị trong App như hiện tại.

## 1. Tạo cấu hình Firebase cho Android

1. Tạo hoặc chọn Firebase project, rồi thêm Android app có package name `com.example.petfeeder_app` (đang khai báo trong `petfeeder_app/android/app/build.gradle.kts`).
2. Mở Firebase project settings và lấy `apiKey`, `appId`, `messagingSenderId`, `projectId` của Android app.
3. Bật Firebase Cloud Messaging API (HTTP v1) trong project.
4. Build App, truyền bốn giá trị ở bước 2 qua Dart defines. Ví dụ trong PowerShell:

```powershell
cd F:\NgDuyLinh\Do_an\IoT\petfeeder_app
flutter build apk --release `
  --dart-define=FIREBASE_API_KEY=AIza... `
  --dart-define=FIREBASE_APP_ID=1:123456789:android:abcdef `
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=123456789 `
  --dart-define=FIREBASE_PROJECT_ID=petfeeder-project
```

Không đặt service-account key trong App hoặc trong các Dart defines. Firebase Android API key/app ID là giá trị cấu hình client; service-account JSON chỉ được dùng phía backend.

## 2. Bật gửi push ở backend

Tạo service account có quyền gửi FCM trong Firebase/Google Cloud project và bật Cloud Messaging API v1. Đặt toàn bộ JSON của service account vào biến môi trường `FIREBASE_SERVICE_ACCOUNT_JSON` ở máy chạy backend hoặc trong phần Environment của Render. Không commit JSON này.

Backend lưu Firebase Installation ID (FID) theo từng lần cài đặt và chỉ gửi thông báo sau khi sự kiện đã được lưu thành công. Nếu FCM chưa cấu hình, đăng ký vẫn được lưu nhưng API trả `push_enabled: false`; màn Cài đặt sẽ báo rằng backend chưa bật dịch vụ gửi. Backend log lỗi khởi tạo hoặc gửi FCM mà không in FID.

## 3. Kiểm tra trên điện thoại

1. Cài APK vừa build lên Android có Google Play services.
2. Kết nối App tới đúng backend, mở **Cài đặt → Thông báo** và bật công tắc. Chọn **Cho phép** trong hộp thoại Android.
3. Kiểm tra Android Settings → Apps → PetFeeder → Notifications đang bật.
4. Để App xuống nền hoặc đóng bình thường. Khi backend nhận sự kiện `INTERRUPTED` cùng mã `POWER_OUTAGE_RETRY_REQUIRED`, điện thoại sẽ nhận push để mở App và xác nhận cấp phần còn thiếu.

Nếu tắt công tắc trong App, server ngừng gửi tới lượt cài đặt đó và App xóa token FCM hiện tại. Tắt quyền ở Android Settings cũng chặn hiển thị; cần mở lại quyền và bật công tắc trong App để đăng ký lại.

Project chưa có thư mục `ios/`. Muốn build iOS cần thêm iOS Runner, cấu hình APNs credentials trong Firebase và khai báo iOS app/options tương ứng trước khi phát hành.
