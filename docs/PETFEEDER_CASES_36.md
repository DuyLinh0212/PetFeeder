# PetFeeder — 36 case để triển khai

Tài liệu này gom **8 case hiện tại** và **28 case bổ sung** thành danh sách việc có thể phân công và code. Mỗi thành viên nhận 18 case: 4 case hiện tại và 14 case mới.

## Phạm vi và cách hiểu

Code hiện tại có app Flutter, backend Node.js, MQTT và firmware ESP32 với nút bấm, servo, cảm biến siêu âm và cân HX711. Những phần này có thể xử lý việc cấp hạt và theo dõi cân nặng. Hiện hệ thống **chưa có cảm biến nhận diện thú, cảm biến bát hiện diện hoặc cảm biến xác định thành phần/chất lạ trong thức ăn**. Với các case đó, cần xác định giới hạn và phần cứng phù hợp; không được coi việc đo cân nặng hay khoảng cách là đã nhận diện được thú/thức ăn/chất độc.

Trong tài liệu, “cấp thành công” nghĩa là thiết bị xác nhận lượng thức ăn đã rơi xuống bát theo ngưỡng cho phép. Việc đó không tự chứng minh thú đã ăn. Các ngưỡng thời gian, lượng ăn tối đa/ngày và khoảng theo dõi phải được đưa vào cấu hình, không rải thành số cố định trong nhiều nơi.

## Phân công

| Thành viên | Phần việc chính | Case được giao |
|---|---|---:|
| **Ngô Công Danh (Danh)** | Firmware ESP32, nút bấm, cơ cấu cấp, cảm biến và xử lý an toàn tại thiết bị | C03, C05, C07, C08; N01–N14 (**18 case**) |
| **Lê Hoàng Bảo Long (Long)** | Flutter, REST API, backend/MQTT, lịch, lịch sử và trạng thái sau cấp | C01, C02, C04, C06; N15–N28 (**18 case**) |

Hai người thống nhất tên trạng thái, trường sự kiện và mã yêu cầu trước khi ghép code. Các case nhận diện hoặc phân loại cần phần cứng mới được ghi rõ là **cần phần cứng**; trong phạm vi code hiện tại, hệ thống phải báo “chưa xác minh” hoặc từ chối cấp theo chính sách an toàn.

## 8 case hiện tại

| ID | Thành viên | Case / câu hỏi | Hướng xử lý và kết quả mong đợi |
|---|---|---|---|
| C01 | Long | Có cần xác minh thú cưng trước khi cấp thức ăn không? | Theo quyết định hiện tại, không xác minh danh tính thú trước khi cấp. Nút trên mạch tiếp tục cấp 20 g; app và lịch dùng khẩu phần đã chọn. Tất cả lệnh vẫn phải qua kiểm tra cân, khoảng chờ và hạn mức. |
| C02 | Long | Làm sao biết thú muốn ăn/đang đói? | Xem nút, app và lịch là yêu cầu cấp thức ăn, không phải kết luận thú đói. Trước khi gửi lệnh, kiểm tra giới hạn khẩu phần/ngày, thời gian an toàn và lượng còn trong bát nếu đã biết. |
| C03 | Danh | Nhấn hai lần có cấp hai lần không? | Chống dội nút, không nhận thêm lần nhấn khi phiên trước đang chạy, và dùng `command_id` để nhận biết lệnh gửi lại. Chỉ lệnh hợp lệ sau khi hết thời gian bảo vệ mới được chạy. |
| C04 | Long | Đã cấp nhưng thú không ăn thì sao? | Theo dõi cân bát trong khoảng cấu hình; ghi `FOOD_LEFT`, `WEIGHT_DECREASED` hoặc `UNKNOWN`. Không tự cấp bù liên tục và không ghi “thú đã ăn” chỉ từ kết quả servo. Cần nhận diện bát/khối lượng đáng tin cậy để tăng độ chắc chắn. |
| C05 | Danh | Hộp hết thức ăn thì sao? | Dừng trước khi mở servo nếu mức hạt đã được xác nhận là hết. Nếu hết/không tăng khối lượng giữa phiên, dừng, tính lượng thực cấp và phát sự kiện lỗi hoặc cấp thiếu. Lệnh override không được bỏ qua lỗi cảm biến hay trạng thái cơ cấu nguy hiểm. |
| C06 | Long | Làm sao biết thứ được nạp là thức ăn phù hợp? | Không thể kết luận bằng cảm biến siêu âm và cân hiện có. Có thể yêu cầu chủ xác nhận loại thức ăn và lưu loại/ảnh/nhãn lô nếu cần. Muốn tự phân loại phải bổ sung phần cứng và kiểm thử. **Cần phần cứng nếu tự nhận diện.** |
| C07 | Danh | Nếu nạp vật khác/hạt lạ vào hộp thì sao? | Không để khoảng cách đo được đồng nghĩa với “có thức ăn đúng loại”. Yêu cầu nắp nạp có khóa/cảm biến mở nắp hoặc bước xác nhận; nếu chưa xác minh, giữ trạng thái chờ kiểm tra và không tự cấp. **Cần phần cứng để phát hiện tự động.** |
| C08 | Danh | Làm sao phát hiện chất lạ hoặc thức ăn có vấn đề? | Cân và cảm biến khoảng cách hiện có không xác nhận được thành phần, chất độc hay vi sinh. Nếu chưa có phương pháp kiểm nghiệm phù hợp, không tuyên bố thức ăn an toàn. **Cần phần cứng/quy trình kiểm tra phù hợp.** |

## 28 case bổ sung

### Danh — firmware, cảm biến và cơ cấu cấp (N01–N14)

| ID | Case | Cách xử lý cần triển khai |
|---|---|---|
| N01 | Nếu bát còn thức ăn khi có yêu cầu cấp mới thì xử lý thế nào? | Xác định khẩu phần là **lượng cấp thêm** hay **mức cần đạt trong bát**. Chặn/bù theo đúng quy ước đã chọn; không cộng cả khẩu phần mới một cách mù quáng. |
| N02 | Nếu thú nhấn lặp lại sau mỗi lần chờ 180 giây thì sao? | Bổ sung giới hạn tổng lượng và số lần cấp trong ngày; từ chối khi vượt ngưỡng, kể cả khi mỗi lần riêng lẻ qua được khoảng chờ. |
| N03 | Nếu app, nút và lịch phát lệnh cùng lúc thì hệ thống xử lý thế nào? | Dùng một khóa trạng thái phiên cấp dùng chung. Khi đang cấp, từ chối hoặc xếp hàng lệnh mới theo một chính sách duy nhất; không cho hai luồng cùng điều khiển servo. |
| N04 | Nếu đang cấp thì bị kẹt giữa chừng, sau đó có lệnh thử lại thì sao? | Báo lượng đã cấp và mã lỗi. Không khởi động lại nguyên khẩu phần; lần thử tiếp theo phải tính phần còn thiếu và vẫn tuân giới hạn tổng lượng. |
| N05 | Nếu đã đạt giới hạn nhịp cấp mà vẫn chưa đủ khẩu phần thì sao? | Trả `PARTIAL` hoặc `TIMEOUT` kèm `target_g` và `actual_g`; chỉ trả `SUCCESS` khi lượng thực cấp nằm trong sai số cho phép. |
| N06 | Làm sao tránh cấp quá lượng khi hạt vẫn rơi sau khi servo đóng? | Gần mục tiêu thì giảm lượng mỗi nhịp, chờ cân ổn định rồi đo lại. Nếu vượt ngưỡng tối đa, dừng cơ cấu và phát cảnh báo `OVER_PORTION`. |
| N07 | Nếu thú ăn trong lúc thiết bị đang cân hoặc cấp thì sao? | Đặt giới hạn cứng cho số nhịp và thời gian. Nếu cân không ổn định, tạm dừng hoặc trả lỗi đo; muốn cấp chính xác khi thú tiếp cận cần thay đổi bố trí/phần cứng. |
| N08 | Nếu thú tì chân, đẩy hoặc rung bát làm số cân bất thường thì sao? | Kiểm tra độ ổn định và thay đổi bất thường của cân; đợi ổn định có thời hạn. Hết thời hạn thì trả lỗi đo, không tiếp tục cấp để bù theo số đo sai. |
| N09 | Nếu bát bị lấy ra trước hoặc giữa phiên cấp thì sao? | Tạm dừng servo ngay khi phát hiện bát vắng mặt; báo `BOWL_MISSING`, giữ lượng đã cấp và chờ bát được đặt lại/phiên được xác nhận. **Cần cảm biến hiện diện bát.** |
| N10 | Nếu HX711 không sẵn sàng hoặc trả số đo lỗi thì sao? | Trả trạng thái cảm biến riêng, không biến “chưa đọc được” thành `0g`. Chặn cấp định lượng bằng cân; cho phép tiếp tục chỉ khi có một chế độ an toàn được thiết kế rõ ràng. |
| N11 | Nếu HC-SR04 mất tín hiệu hoặc timeout thì sao? | Phân biệt `SENSOR_ERROR` với `EMPTY`. Đọc lại có giới hạn; nếu vẫn lỗi thì dừng lệnh cần kiểm tra mức hạt và phát cảnh báo. |
| N12 | Nếu hộp còn hạt nhưng hạt không rơi xuống thì xử lý thế nào? | Sau một số nhịp không tăng cân, thử gỡ kẹt theo giới hạn đã đặt; hết số lần thì đóng servo, trả `JAM_ERROR` và chờ kiểm tra. |
| N13 | Nếu chủ thêm thức ăn trực tiếp vào bát thì sao? | Nhận biết cân tăng ngoài phiên cấp (nếu có thể), không tính phần tăng là lượng máy vừa cấp; cập nhật trạng thái bát sau khi cân ổn định. |
| N14 | Nếu thức ăn bị đổ, bị lấy đi hoặc cân bát giảm vì lý do khác thì sao? | Ghi nhận “khối lượng giảm”, không khẳng định thú đã ăn. Nếu cần xác định nguyên nhân, bổ sung cảm biến/nhận diện; khi chưa có thì lưu `UNKNOWN_CAUSE`. |

### Long — app, backend, MQTT, lịch và lưu trạng thái (N15–N28)

| ID | Case | Cách xử lý cần triển khai |
|---|---|---|
| N15 | Nếu thức ăn còn trong bát quá lâu thì xử lý thế nào? | Theo dõi thời điểm lần cuối xác nhận có thức ăn; nhắc chủ kiểm tra/vệ sinh khi quá thời gian cấu hình. Không tự đổ thêm chỉ vì thức ăn cũ còn trong bát. |
| N16 | Nếu mất điện rồi bật lại ngay sau lần cấp thì sao? | Lưu thời điểm/kết quả cấp gần nhất vào bộ nhớ bền vững để bảo vệ chống lặp không bị xóa khi khởi động lại; kiểm tra và đồng bộ lại trạng thái thiết bị. |
| N17 | Nếu mất điện giữa phiên cấp thì khi khởi động lại xử lý thế nào? | Khi khởi động lại, đóng servo trước, đánh dấu phiên `INTERRUPTED`, đọc lại cảm biến và yêu cầu đối soát. Không chạy lại toàn bộ khẩu phần tự động. |
| N18 | Nếu khởi động lại khi trong bát đã có thức ăn thì sao? | Không tare cân trong mọi lần khởi động theo cách làm mất số đo thức ăn đang có. Tách hiệu chuẩn khỏi khởi động và lưu/truy hồi trạng thái cân phù hợp. |
| N19 | Nếu mất mạng đúng giờ ăn thì sao? | Lưu lịch trên thiết bị theo cách còn dùng được sau khi khởi động lại; chạy lịch offline một lần đúng giờ và đưa sự kiện vào hàng đợi gửi lại khi có mạng. |
| N20 | Nếu thiết bị chưa đồng bộ được giờ sau khi khởi động thì sao? | Không chạy lịch bằng giờ không hợp lệ. Báo `TIME_INVALID`; chờ đồng bộ NTP hoặc dùng RTC nếu yêu cầu lịch hoạt động offline sau mất điện. |
| N21 | Làm sao để lịch chỉ chạy vào đúng những ngày đã chọn? | Gửi trường `days` trong payload MQTT và kiểm tra ngày trước khi kích hoạt lịch tại firmware. Kiểm tra giá trị ngày hợp lệ ở API. |
| N22 | Làm sao tránh lịch đã chạy bị chạy lại sau khi đồng bộ danh sách? | Giữ dấu đã chạy bằng khóa `schedule_id + ngày`; không đặt lại dấu thực thi chỉ vì nhận payload đồng bộ mới trong cùng ngày. |
| N23 | Nếu mất điện qua nhiều giờ ăn thì khi bật lại có cấp bù tất cả không? | Định nghĩa cửa sổ bù rõ ràng. Mặc định bỏ qua lịch quá hạn ngoài cửa sổ, ghi sự kiện `MISSED_SCHEDULE` và không dồn nhiều khẩu phần vào một lần bật lại. |
| N24 | Nếu app không nhận phản hồi và người dùng gửi lại lệnh thì sao? | Tạo `command_id` ở app và truyền qua API/MQTT đến ESP32. Gửi lại cùng ID phải trả trạng thái phiên cũ, không tạo phiên cấp thứ hai. |
| N25 | Nếu lệnh đến thiết bị quá muộn thì sao? | Gửi thời điểm hết hạn trong lệnh; thiết bị từ chối và ghi `COMMAND_EXPIRED` nếu lệnh đến sau hạn. Không thực thi lệnh cũ sau khi mạng phục hồi. |
| N26 | Nếu backend nhận lại một sự kiện MQTT cũ thì xử lý thế nào? | Thêm `event_id` duy nhất và thời điểm phát sinh; backend lưu một lần theo ID, không tạo lịch sử hoặc cảnh báo trùng. Kiểm tra retained message cho topic sự kiện. |
| N27 | Nếu thiết bị bị báo offline vì phiên cấp kéo dài thì sao? | Không để xử lý cấp chặn vòng MQTT/heartbeat. Chia phiên thành các bước không chặn hoặc phát trạng thái bận định kỳ để backend phân biệt `BUSY` với `OFFLINE`. |
| N28 | Nếu giờ, khẩu phần, ngày lịch hoặc cấu hình gửi lên sai thì sao? | Kiểm tra giá trị ở API **và** firmware, vì thiết bị có thể nhận lệnh MQTT ngoài app. Từ chối trường thiếu/sai miền và trả mã lỗi cụ thể; không dùng giá trị mặc định để âm thầm cấp. |

## Giao kèo ghép code

Trước khi tích hợp, Danh và Long thống nhất một cấu trúc lệnh và sự kiện. Đề xuất mỗi lệnh có `command_id`, `source`, `target_portion_g`, `override`, `created_at`, `expires_at`. Sự kiện trả về có `command_id`, `status`, `target_portion_g`, `actual_weight_g`, `started_at`, `completed_at`, `error_code`.

Các trạng thái tối thiểu cần dùng nhất quán: `ACCEPTED`, `REJECTED`, `DISPENSING`, `SUCCESS`, `PARTIAL`, `BLOCKED_DUPLICATE`, `FOOD_EMPTY`, `SENSOR_ERROR`, `JAM_ERROR`, `INTERRUPTED`, `COMMAND_EXPIRED`. Theo dõi việc ăn là sự kiện riêng, ví dụ `FOOD_LEFT`, `WEIGHT_DECREASED`, `UNKNOWN`; không tái sử dụng `SUCCESS` của phiên cấp để chỉ việc thú đã ăn.

Mỗi case cần có tối thiểu một kịch bản kiểm tra: điều kiện đầu vào, thao tác gây tình huống, trạng thái/mã lỗi mong đợi và dữ liệu lịch sử sau xử lý. Ưu tiên ghép theo giao kèo trạng thái ở trên để app không báo “đã cho ăn thành công” ngay khi backend mới chỉ nhận được yêu cầu.

## Vị trí code liên quan

- Firmware và cảm biến/servo: `PetFeeder/src/main.cpp`.
- API cho ăn và lịch sử: `petfeeder_backend/src/routes/feeding.js`.
- MQTT, telemetry và sự kiện: `petfeeder_backend/src/mqttClient.js`.
- Lưu trạng thái/lịch sử: `petfeeder_backend/src/storage.js`.
- Giao diện cho ăn: `petfeeder_app/lib/screens/dashboard_screen.dart`.
- Gọi API từ Flutter: `petfeeder_app/lib/services/api_service.dart`.
- Tạo/sửa lịch: `petfeeder_backend/src/routes/schedules.js`.
