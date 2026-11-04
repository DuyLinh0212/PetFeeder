# Đèn báo tiếp cận

Đèn ở GPIO 26 chỉ bật khi cảm biến khoảng cách/PIR phát hiện vật thể đến gần **và** LDR báo môi trường tối. Trạng thái tối cần ba lần đọc liên tiếp để tránh chập chờn. Khi hết tín hiệu tiếp cận, đèn tắt sau tối đa 5 giây. Cảm biến chỉ nhận biết vật thể/khoảng cách; nó không quyết định lệnh cấp thức ăn.

## Phần cứng thật

- Dùng breakout VL53L1X; nối SDA GPIO 21, SCL GPIO 22, chung bus I²C với OLED và nối GND chung. Cấp nguồn theo yêu cầu của breakout.
- Dùng module LDR có ngõ ra số DO; nối VCC 3V3, GND và DO GPIO 34. Chỉnh biến trở ngưỡng trên module; chân AO không dùng.
- Nối GPIO 26 tới MOSFET logic-level để điều khiển đèn trắng chiếu vùng khay. Dùng mạch driver/điện trở phù hợp; không cấp đèn công suất trực tiếp từ chân ESP32.
- Đặt LDR tránh hướng thẳng vào đèn để ánh sáng của đèn không làm cảm biến đổi trạng thái.

## Wokwi

Wokwi dùng PIR tại GPIO 27 làm tín hiệu mô phỏng thay cho VL53L1X. Module photoresistor dùng VCC 3V3, GND và DO GPIO 34; chân AO không dùng. Bấm PIR rồi chọn **Simulate Motion** để báo có vật thể tiếp cận. Giảm `lux` xuống dưới khoảng 100 để mô phỏng môi trường tối; LED trắng GPIO 26 sẽ sáng khi có tiếp cận. Tăng `lux` để mô phỏng môi trường sáng và xác nhận đèn không bật.

Nút trên mạch vẫn gửi lệnh cấp 20 g như trước. Việc có vật thể tiếp cận chỉ bật đèn, không phải điều kiện để cấp thức ăn.
