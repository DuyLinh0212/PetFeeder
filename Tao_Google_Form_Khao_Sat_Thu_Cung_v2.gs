/**
 * GOOGLE APPS SCRIPT
 * Tạo tự động Google Form:
 * "KHẢO SÁT NHU CẦU SỬ DỤNG HỆ THỐNG CHO THÚ CƯNG ĂN TỰ ĐỘNG"
 *
 * Cách dùng:
 * 1. Vào https://script.google.com
 * 2. Tạo New project
 * 3. Xóa code mặc định và dán toàn bộ file này vào
 * 4. Chạy hàm createPetFeederSurvey()
 * 5. Cấp quyền cho script
 * 6. Mở Execution log để lấy link chỉnh sửa và link gửi khảo sát
 */

function createPetFeederSurvey() {
  const form = FormApp.create(
    'KHẢO SÁT NHU CẦU SỬ DỤNG HỆ THỐNG CHO THÚ CƯNG ĂN TỰ ĐỘNG'
  );

  form.setDescription(
    'Xin chào! Chúng tôi đang thực hiện đề tài "Hệ thống cho thú cưng ăn tự động" ' +
    'trong học phần Internet of Things (IoT).\n\n' +
    'Khảo sát này nhằm tìm hiểu thói quen cho thú cưng ăn, những khó khăn mà người nuôi ' +
    'thường gặp và nhu cầu đối với một hệ thống cho ăn tự động.\n\n' +
    'Thông tin thu thập chỉ được sử dụng cho mục đích học tập và nghiên cứu. ' +
    'Thời gian hoàn thành khảo sát khoảng 2–3 phút.\n\n' +
    'Xin chân thành cảm ơn sự hỗ trợ của bạn!'
  );

  form.setConfirmationMessage(
    'Cảm ơn bạn đã tham gia khảo sát! Câu trả lời của bạn sẽ được sử dụng cho mục đích học tập và nghiên cứu.'
  );

  form.setProgressBar(true);
  form.setShuffleQuestions(false);


  // PHẦN 1 - THÔNG TIN NGƯỜI THAM GIA
  form.addSectionHeaderItem()
      .setTitle('PHẦN 1 — THÔNG TIN NGƯỜI THAM GIA')
      .setHelpText('Thông tin chỉ phục vụ cho việc phân tích kết quả khảo sát và không yêu cầu cung cấp họ tên.');

  form.addMultipleChoiceItem()
      .setTitle('5. Độ tuổi của bạn?')
      .setChoiceValues([
        'Dưới 18 tuổi',
        '18–22 tuổi',
        '23–30 tuổi',
        '31–40 tuổi',
        'Trên 40 tuổi'
      ])
      .setRequired(true);

  form.addMultipleChoiceItem()
      .setTitle('6. Nghề nghiệp hiện tại của bạn?')
      .setChoiceValues([
        'Học sinh/Sinh viên',
        'Nhân viên văn phòng',
        'Kinh doanh/Tự do',
        'Nội trợ',
        'Khác'
      ])
      .setRequired(true);

  form.addMultipleChoiceItem()
      .setTitle('7. Trung bình mỗi ngày bạn vắng nhà trong bao lâu?')
      .setChoiceValues([
        'Dưới 2 giờ',
        '2–4 giờ',
        '4–8 giờ',
        'Trên 8 giờ',
        'Không cố định'
      ])
      .setRequired(true);

  form.addMultipleChoiceItem()
      .setTitle('8. Bạn hiện đang nuôi bao nhiêu thú cưng?')
      .setChoiceValues([
        '1',
        '2',
        '3',
        'Trên 3',
        'Hiện không nuôi'
      ])
      .setRequired(true);

  // PHẦN 2 - HIỆN TRẠNG VÀ THÓI QUEN CHĂM SÓC
  form.addPageBreakItem()
      .setTitle('PHẦN 2 — HIỆN TRẠNG VÀ THÓI QUEN CHĂM SÓC')
      .setHelpText('Các câu hỏi sau nhằm tìm hiểu hiện trạng cho thú cưng ăn.');

  form.addMultipleChoiceItem()
      .setTitle('5. Bạn hiện có đang nuôi thú cưng không?')
      .setChoiceValues([
        'Có',
        'Đã từng nuôi',
        'Chưa từng nuôi'
      ])
      .setRequired(true);

  form.addCheckboxItem()
      .setTitle('6. Bạn đang nuôi hoặc từng nuôi loại thú cưng nào?')
      .setChoiceValues([
        'Chó',
        'Mèo',
        'Chó và mèo',
        'Khác'
      ])
      .setRequired(true);

  form.addMultipleChoiceItem()
      .setTitle('7. Bạn thường cho thú cưng ăn bao nhiêu lần mỗi ngày?')
      .setChoiceValues([
        '1 lần',
        '2 lần',
        '3 lần',
        'Trên 3 lần',
        'Không theo thời gian cố định'
      ])
      .setRequired(true);

  form.addMultipleChoiceItem()
      .setTitle('8. Hiện tại bạn thường cho thú cưng ăn bằng cách nào?')
      .setChoiceValues([
        'Cho ăn trực tiếp bằng tay',
        'Chuẩn bị sẵn thức ăn trước khi đi',
        'Nhờ người khác cho ăn',
        'Sử dụng thiết bị/máy cho ăn tự động',
        'Khác'
      ])
      .setRequired(true);

  form.addScaleItem()
      .setTitle('9. Bạn có thường xuyên vắng nhà vào thời điểm cần cho thú cưng ăn không?')
      .setBounds(1, 5)
      .setLabels('1 - Không bao giờ', '5 - Rất thường xuyên')
      .setRequired(true);

  form.addMultipleChoiceItem()
      .setTitle('10. Bạn đã từng quên hoặc cho thú cưng ăn trễ chưa?')
      .setChoiceValues([
        'Chưa bao giờ',
        'Hiếm khi',
        'Thỉnh thoảng',
        'Thường xuyên'
      ])
      .setRequired(true);

  form.addCheckboxItem()
      .setTitle('11. Khi không có mặt ở nhà, bạn thường làm gì để đảm bảo thú cưng được ăn đúng giờ?')
      .setChoiceValues([
        'Chuẩn bị sẵn thức ăn',
        'Nhờ người thân/bạn bè',
        'Cho ăn trước giờ',
        'Cho ăn sau khi trở về',
        'Sử dụng máy cho ăn tự động',
        'Không có giải pháp cụ thể',
        'Khác'
      ])
      .setRequired(true);

  form.addCheckboxItem()
      .setTitle('12. Bạn thường gặp vấn đề nào khi cho thú cưng ăn?')
      .setChoiceValues([
        'Quên cho ăn',
        'Cho ăn không đúng giờ',
        'Không thể cho ăn khi vắng nhà',
        'Khó kiểm soát lượng thức ăn mỗi bữa',
        'Thú cưng ăn quá nhiều',
        'Không biết thức ăn trong máy/bát còn hay hết',
        'Thức ăn dễ bị ẩm hoặc hỏng',
        'Không gặp vấn đề nào',
        'Khác'
      ])
      .setRequired(true);

  // PHẦN 2
  form.addPageBreakItem()
      .setTitle('PHẦN 3 — NHU CẦU ĐỐI VỚI HỆ THỐNG CHO ĂN TỰ ĐỘNG')
      .setHelpText('Phần này nhằm xác định những chức năng người dùng mong muốn ở hệ thống IoT.');

  form.addMultipleChoiceItem()
      .setTitle('13. Bạn đã từng sử dụng máy cho thú cưng ăn tự động chưa?')
      .setChoiceValues([
        'Đang sử dụng',
        'Đã từng sử dụng',
        'Biết nhưng chưa sử dụng',
        'Chưa từng biết đến'
      ])
      .setRequired(true);

  form.addScaleItem()
      .setTitle('14. Mức độ quan tâm của bạn đối với một hệ thống cho thú cưng ăn tự động?')
      .setBounds(1, 5)
      .setLabels('1 - Hoàn toàn không quan tâm', '5 - Rất quan tâm')
      .setRequired(true);

  form.addCheckboxItem()
      .setTitle('15. Bạn mong muốn một hệ thống cho thú cưng ăn tự động có những chức năng nào?')
      .setChoiceValues([
        'Cài đặt giờ cho ăn tự động',
        'Cài đặt khẩu phần thức ăn cho mỗi lần',
        'Cho ăn ngay bằng nút bấm trên thiết bị',
        'Điều khiển cho ăn từ điện thoại',
        'Theo dõi lịch sử các lần cho ăn',
        'Cảnh báo khi sắp hết thức ăn',
        'Cảnh báo khi thức ăn bị kẹt/không cấp được',
        'Hiển thị trạng thái thiết bị',
        'Theo dõi lượng thức ăn còn lại',
        'Hoạt động được khi mất kết nối Internet',
        'Khác'
      ])
      .setRequired(true);

  form.addMultipleChoiceItem()
      .setTitle('16. Theo bạn chức năng nào quan trọng nhất?')
      .setChoiceValues([
        'Cho ăn đúng giờ',
        'Kiểm soát khẩu phần',
        'Điều khiển từ xa',
        'Theo dõi lượng thức ăn',
        'Cảnh báo hết thức ăn',
        'Cảnh báo lỗi thiết bị'
      ])
      .setRequired(true);

  form.addMultipleChoiceItem()
      .setTitle('17. Bạn có muốn điều khiển và theo dõi máy cho ăn thông qua điện thoại không?')
      .setChoiceValues([
        'Có',
        'Không',
        'Không quan trọng'
      ])
      .setRequired(true);

  form.addCheckboxItem()
      .setTitle('18. Bạn muốn hệ thống gửi cảnh báo khi xảy ra trường hợp nào?')
      .setChoiceValues([
        'Sắp hết thức ăn',
        'Hết thức ăn',
        'Thức ăn bị kẹt',
        'Thiết bị mất kết nối',
        'Đã cho thú cưng ăn thành công',
        'Thú cưng chưa được cho ăn đúng lịch',
        'Không cần cảnh báo'
      ])
      .setRequired(true);

  form.addParagraphTextItem()
      .setTitle('19. Bạn có đề xuất thêm chức năng nào cho hệ thống cho thú cưng ăn tự động không?')
      .setRequired(false);

  // Liên kết Sheet tự động để lưu câu trả lời
  const spreadsheet = SpreadsheetApp.create(
    'Kết quả khảo sát - Hệ thống cho thú cưng ăn tự động'
  );
  form.setDestination(FormApp.DestinationType.SPREADSHEET, spreadsheet.getId());

  Logger.log('=== GOOGLE FORM ĐÃ ĐƯỢC TẠO ===');
  Logger.log('Link chỉnh sửa Form: ' + form.getEditUrl());
  Logger.log('Link gửi khảo sát: ' + form.getPublishedUrl());
  Logger.log('Google Sheet lưu kết quả: ' + spreadsheet.getUrl());
}
