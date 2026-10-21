# Đối chiếu phần Long

Các vị trí dưới đây là code mới trong dự án này. “Test mô hình” kiểm tra backend và thiết bị giả lập Node; không có nghĩa là đã chứng minh mất điện/flash/độ chính xác cân trên ESP32 thật.

| Case | Nơi xử lý chính | Cách kiểm chứng |
|---|---|---|
| C01 | `service.js`, `deviceSimulator.js`, firmware `receive()`; app bật chính sách | Test UNKNOWN_PET; thiếu phần cứng thì từ chối, không nhận diện giả |
| C02 | `receive()`, dự trù tổng ngày và khoảng chờ; API kiểm tra trước | Test hạn ngày/cooldown; thiết bị quyết định cuối |
| C04 | `tick()`/observations và firmware sau cấp; app lịch sử | Test FOOD_LEFT, WEIGHT_DECREASED, UNKNOWN; không gọi là thú đã ăn |
| C06 | `policy.js`, cấu hình/app; firmware food_confirmed | Test UNVERIFIED và nhãn chủ xác nhận; không phân loại tự động |
| N15 | food_since/stale_alert trong mô hình và firmware | Test một cảnh báo cho mỗi đợt thức ăn tồn; cần test cảm biến thật |
| N16 | SQLite mô hình; LittleFS firmware history/last_end/used_g | Test reboot mô hình; firmware build; cắt nguồn thật chưa chạy |
| N17 | active/locked + INTERRUPTED; giao diện đối soát | Test reboot giữa cấp, actual=null, giữ dự trù; test servo sau mất điện còn cần làm |
| N18 | factor/offset/calibrated lưu riêng, không tare ở setup | Test mô hình không thay đầu vào; build firmware; chưa xác minh loadcell thực |
| N19 | schedules/runs/outbox + ACK ở firmware; SQLite backend | Test lịch offline và phát lại mô hình; MQTT thật cục bộ đã test ACK/dedup |
| N20 | validTime()/TIME_INVALID, heartbeat.time_valid | Test mô hình chặn giờ sai; chưa có RTC để chạy sau mất điện offline |
| N21 | schedules() ở API; scheduleValid()/days ở firmware | Test ngày được chọn/không được chọn và miền 0–6 |
| N22 | device_schedule_runs, LittleFS runs không xóa khi sync | Test resync/reboot mô hình không chạy lặp; cần đối chiếu flash trên thiết bị |
| N23 | scanSchedules(): quá hạn >=60s ghi MISSED_SCHEDULE | Test bỏ lỡ nhiều lịch; đối soát tối đa 7 ngày trong bản demo |
| N24 | app SharedPreferences, service.feed(), device history | Test app timeout→tạo service mới→retry payload nguyên vẹn; test API và bấm UI demo |
| N25 | policy.command(), firmware receive() và đồng hồ hợp lệ | Test lệnh quá hạn gửi trực tiếp vào mô hình; firmware có validation đã build |
| N26 | SQLite khóa event_id, seq và trạng thái cuối; mqttClient.js | Test trùng, restart DB, sự kiện cũ, broker MQTT thật và retained replay |
| N27 | loop() không có vòng cấp chặn; heartbeat 5s; API offline >20s | Test mô hình BUSY rồi mất mạng; firmware build; chưa đo heartbeat Wokwi thực |
| N28 | policy.js, commandValid/configValid/scheduleValid và app nhập liệu | Test sai kiểu/giới hạn ở backend/mô hình; firmware build; cần test payload trực tiếp trên Wokwi |

API trạng thái `QUEUED` hoặc `DELIVERY_UNKNOWN` không khẳng định servo đã chạy hay chưa. Chỉ kết quả thiết bị mới xác nhận lượng. Trạng thái sau cấp là sự kiện độc lập nên không ghi đè SUCCESS của phiên.

Phần Long có thay đổi firmware để demo độc lập. Các cơ cấu/cảm biến của Danh cần ghép theo `GIAO_KEO_MQTT.md`; bản demo chưa bao phủ trọn N01–N14 của Danh, đặc biệt bát hiện diện, rung/ăn khi cấp và xác minh thức ăn.
