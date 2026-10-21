import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

const ink = Color(0xff183e37);
const teal = Color(0xff087f6b);
const muted = Color(0xff70847e);

String statusLabel(dynamic value) =>
    {
      'QUEUED': 'Đang gửi yêu cầu',
      'ACCEPTED': 'Thiết bị đã nhận',
      'DISPENSING': 'Đang cấp thức ăn',
      'SUCCESS': 'Đã cấp thức ăn',
      'PARTIAL': 'Chưa cấp đủ',
      'REJECTED': 'Yêu cầu bị từ chối',
      'INTERRUPTED': 'Phiên bị gián đoạn',
      'COMMAND_EXPIRED': 'Yêu cầu đã hết hạn',
      'DELIVERY_UNKNOWN': 'Đang chờ xác nhận',
      'TIMEOUT': 'Đã dừng do quá thời gian',
      'SENSOR_ERROR': 'Cần kiểm tra cảm biến',
      'OVER_PORTION': 'Lượng cấp vượt mức',
      'FOOD_LEFT': 'Thức ăn vẫn còn trong bát',
      'WEIGHT_DECREASED': 'Khối lượng bát giảm',
      'UNKNOWN': 'Chưa xác định được',
      'FOOD_STALE': 'Đến lúc kiểm tra thức ăn',
      'MISSED_SCHEDULE': 'Đã bỏ lỡ một lịch',
      'CONFIG_APPLIED': 'Thiết bị đã cập nhật',
      'TIME_INVALID': 'Đang chờ đồng bộ giờ',
      'RECONCILED': 'Đã kiểm tra thiết bị',
      'BLOCKED_DUPLICATE': 'Đã nhận diện yêu cầu gửi lại',
    }[value] ??
    'Cập nhật từ thiết bị';

String reasonLabel(dynamic code) =>
    {
      'UNKNOWN_PET': 'Chưa có thiết bị xác minh thú cưng.',
      'UNVERIFIED': 'Bạn cần xác nhận thức ăn trong Cài đặt.',
      'OFFLINE': 'Thiết bị đang mất kết nối.',
      'BUSY': 'Thiết bị đang thực hiện một phiên khác.',
      'COOLDOWN': 'Chưa hết khoảng chờ giữa hai lần cấp.',
      'DAILY_LIMIT': 'Đã chạm giới hạn khẩu phần hôm nay.',
      'RECONCILIATION_REQUIRED': 'Cần kiểm tra thiết bị sau phiên gián đoạn.',
      'SENSOR_ERROR': 'Chưa đọc được số cân đáng tin cậy.',
      'COMMAND_EXPIRED': 'Yêu cầu cũ đã hết hạn.',
      'FOOD_EMPTY': 'Cần kiểm tra lượng hạt trong hộp.',
      'UNKNOWN_CAUSE': 'Chưa xác định nguyên nhân giảm khối lượng.',
      'TIME_INVALID': 'Thiết bị chưa có giờ hợp lệ.',
      'AWAITING_DEVICE_RESULT':
          'Chưa có kết quả từ thiết bị. Hãy kiểm tra trước khi cấp thêm.',
    }[code] ??
    (code == null ? '' : 'Cần kiểm tra lại yêu cầu hoặc thiết bị.');

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.api});
  final ApiService api;
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final portion = TextEditingController(text: '20');
  final food = TextEditingController();
  final weight = TextEditingController(text: '0');
  final Map<String, TextEditingController> configFields = {};
  static const labels = {
    'max_portion_g': 'Tối đa mỗi lần (g)',
    'daily_limit_g': 'Tối đa mỗi ngày (g)',
    'min_interval_s': 'Khoảng chờ (giây)',
    'observation_s': 'Theo dõi sau cấp (giây)',
    'food_stale_s': 'Nhắc thức ăn cũ (giây)',
    'command_ttl_s': 'Hạn yêu cầu (giây)',
    'feed_timeout_s': 'Thời gian cấp tối đa (giây)',
    'tolerance_g': 'Sai số cân (g)',
    'timezone_offset_min': 'Múi giờ (phút)',
  };
  Timer? timer;
  Map<String, dynamic>? data, pending;
  int tab = 0;
  bool polling = false,
      working = false,
      initialized = false,
      backendAvailable = false;
  bool foodConfirmed = false,
      requirePet = false,
      online = true,
      timeValid = true,
      autoFeed = true;

  @override
  void initState() {
    super.initState();
    refresh();
    timer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  @override
  void dispose() {
    timer?.cancel();
    portion.dispose();
    food.dispose();
    weight.dispose();
    for (final c in configFields.values) {
      c.dispose();
    }
    widget.api.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (polling) return;
    polling = true;
    try {
      final next = await widget.api.state(), saved = await widget.api.pending();
      if (!mounted) return;
      setState(() {
        data = next;
        pending = saved;
        backendAvailable = true;
        if (!initialized) {
          final cfg = next['config'];
          food.text = cfg['food_label'];
          foodConfirmed = cfg['food_confirmed'];
          requirePet = cfg['require_pet'];
          for (final k in labels.keys) {
            configFields[k] = TextEditingController(text: '${cfg[k]}');
          }
          initialized = true;
        }
      });
    } catch (_) {
      if (mounted) setState(() => backendAvailable = false);
    } finally {
      polling = false;
    }
  }

  Future<bool> action(Future<dynamic> Function() fn) async {
    if (working) return false;
    setState(() => working = true);
    try {
      final result = await fn();
      if (mounted) {
        final text = result is Map && result.containsKey('status')
            ? '${statusLabel(result['status'])}${result['error_code'] == null ? '' : '. ${reasonLabel(result['error_code'])}'}'
            : 'Đã lưu thay đổi.';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(text)));
      }
      await refresh();
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Chưa thực hiện được. Kiểm tra kết nối và thông tin nhập; nếu đang chờ kết quả cấp, hãy dùng Gửi lại cùng mã.')));
        final saved = await widget.api.pending();
        if (mounted) setState(() => pending = saved);
      }
      return false;
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  double grams(TextEditingController c) {
    final n = double.tryParse(c.text);
    if (n == null || !n.isFinite || n <= 0) {
      throw const FormatException('Khẩu phần không hợp lệ');
    }
    return n;
  }

  String amount(dynamic n) => n is num
      ? (n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(1))
      : '—';
  String timeText(dynamic epoch, {bool date = false}) {
    if (epoch is! num || epoch <= 0) return 'Chưa đồng bộ giờ';
    final t =
        DateTime.fromMillisecondsSinceEpoch(epoch.toInt() * 1000, isUtc: true)
            .add(Duration(
                minutes: (data?['config']['timezone_offset_min'] as num? ?? 420)
                    .toInt()));
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return date ? '$hm · ${t.day}/${t.month}/${t.year}' : hm;
  }

  Widget panel(List<Widget> children,
          {EdgeInsets padding = const EdgeInsets.all(20)}) =>
      Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: padding,
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xffe4eae5))),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children));
  Widget heading(String title, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: ink))),
        if (trailing != null) trailing
      ]));
  Widget primary(String label, Future<dynamic> Function() fn, {Key? key}) =>
      FilledButton(
          key: key,
          onPressed: working || !backendAvailable ? null : () => action(fn),
          child: Text(label));
  Widget notice(String text,
          {IconData icon = Icons.info_outline, VoidCallback? onTap}) =>
      Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: const Color(0xfffff2db),
              borderRadius: BorderRadius.circular(16)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: const Color(0xff9a6423)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xff775126)))),
            if (onTap != null)
              IconButton(
                  onPressed: onTap, icon: const Icon(Icons.chevron_right))
          ]));

  Widget home(Map<String, dynamic> state) {
    final commands = state['commands'] as List,
        events = state['events'] as List;
    final own = pending == null
        ? null
        : commands
            .where((c) => c['command_id'] == pending!['command_id'])
            .firstOrNull;
    final now = state['device']?['occurred_at'];
    final today = now is num && now > 0
        ? timeText(now, date: true).split(' · ').last
        : null;
    final completed = commands
        .where((c) =>
            ['SUCCESS', 'PARTIAL', 'OVER_PORTION'].contains(c['status']) &&
            c['actual_weight_g'] is num &&
            today != null &&
            timeText(c['occurred_at'], date: true).endsWith(' · $today'))
        .toList();
    final total = (state['daily']?['actual_dispensed_g'] as num?)?.toDouble() ??
        completed.fold<double>(
            0, (sum, c) => sum + (c['actual_weight_g'] as num).toDouble());
    final sessionCount =
        state['daily']?['confirmed_sessions'] ?? completed.length;
    final limit = (state['config']['daily_limit_g'] as num).toDouble();
    final connected = backendAvailable && state['connection'] == 'ONLINE';
    final busy = backendAvailable && state['connection'] == 'BUSY';
    final canFeed =
        connected && !working && state['config']['food_confirmed'] == true;
    final latest = own ?? commands.firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Chăm bữa ăn,\nan tâm mỗi ngày.',
          style: TextStyle(
              fontSize: 29,
              height: 1.18,
              fontWeight: FontWeight.w800,
              color: ink,
              letterSpacing: -.8)),
      const SizedBox(height: 8),
      const Text('Theo dõi thiết bị và khẩu phần của thú cưng.',
          style: TextStyle(color: muted, fontSize: 13)),
      const SizedBox(height: 22),
      Container(
          padding: const EdgeInsets.all(22),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xff137c68), Color(0xff17574d)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(26)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.restaurant_rounded,
                  color: Color(0xffc9e9ca), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                  child: Text('LƯỢNG MÁY ĐÃ CẤP HÔM NAY',
                      style: TextStyle(
                          color: Color(0xffd1e7db),
                          fontSize: 10,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w700)))
            ]),
            const SizedBox(height: 18),
            Text('${amount(total)} g',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.5,
                    height: 1.1)),
            const SizedBox(height: 8),
            Text('Giới hạn ${amount(limit)} g / ngày',
                style: const TextStyle(color: Color(0xffd1e7db), fontSize: 13)),
            const SizedBox(height: 16),
            ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                    value: (total / limit).clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: Colors.white24,
                    color: const Color(0xffc8e8a4))),
            const SizedBox(height: 12),
            const Text('Tính theo các phiên có lượng cấp đã xác nhận.',
                style: TextStyle(color: Color(0xffd1e7db), fontSize: 11)),
          ])),
      Row(children: [
        Expanded(
            child: panel([
          const Icon(Icons.scale_outlined, color: teal, size: 22),
          const SizedBox(height: 10),
          const Text('Trong bát', style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
              state['device']?['weight_g'] == null
                  ? 'Chưa xác định'
                  : '${amount(state['device']['weight_g'])} g',
              style: const TextStyle(
                  color: ink, fontSize: 22, fontWeight: FontWeight.w700)),
        ], padding: const EdgeInsets.all(16))),
        const SizedBox(width: 12),
        Expanded(
            child: panel([
          const Icon(Icons.check_circle_outline, color: teal, size: 22),
          const SizedBox(height: 10),
          const Text('Phiên đã xác nhận',
              style: TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text('$sessionCount lần',
              style: const TextStyle(
                  color: ink, fontSize: 22, fontWeight: FontWeight.w700)),
        ], padding: const EdgeInsets.all(16)))
      ]),
      if (!state['config']['food_confirmed'])
        notice('Xác nhận loại thức ăn trước khi cấp.',
            onTap: () => setState(() => tab = 3)),
      if (state['device']?['locked'] == true)
        notice('Thiết bị cần được kiểm tra sau một phiên gián đoạn.'),
      panel([
        heading('Cấp thức ăn',
            trailing: const Icon(Icons.pets_outlined, color: teal, size: 21)),
        const Text('Chọn lượng cấp thêm',
            style: TextStyle(color: muted, fontSize: 13)),
        const SizedBox(height: 12),
        Row(children: [
          for (final n in [10, 20, 30])
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                        label: Center(child: Text('$n g')),
                        selected: double.tryParse(portion.text) == n,
                        onSelected: working
                            ? null
                            : (_) => setState(() => portion.text = '$n'))))
        ]),
        const SizedBox(height: 14),
        Row(children: [
          IconButton.filledTonal(
              tooltip: 'Giảm khẩu phần',
              onPressed: working
                  ? null
                  : () => setState(() => portion.text =
                      '${((double.tryParse(portion.text) ?? 20) - 5).clamp(1, 500).round()}'),
              icon: const Icon(Icons.remove)),
          const SizedBox(width: 10),
          Expanded(
              child: TextField(
                  key: const Key('portion'),
                  controller: portion,
                  textAlign: TextAlign.center,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Khẩu phần', suffixText: 'g'),
                  onChanged: (_) => setState(() {}))),
          const SizedBox(width: 10),
          IconButton.filledTonal(
              tooltip: 'Tăng khẩu phần',
              onPressed: working
                  ? null
                  : () => setState(() => portion.text =
                      '${((double.tryParse(portion.text) ?? 20) + 5).clamp(1, 500).round()}'),
              icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: 16),
        FilledButton.icon(
            key: const Key('feed-new'),
            onPressed: canFeed
                ? () => action(() => widget.api.feed(grams(portion)))
                : null,
            icon: Icon(busy ? Icons.hourglass_top_rounded : Icons.restaurant),
            label: Text(busy ? 'Thiết bị đang cấp…' : 'Cấp ${portion.text} g')),
        const SizedBox(height: 10),
        const Text(
            'Thiết bị xác nhận lượng đã cấp. Việc này chưa chứng minh thú đã ăn.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 11, height: 1.5)),
        if (pending != null)
          TextButton.icon(
              onPressed: working || !backendAvailable
                  ? null
                  : () => action(widget.api.retry),
              icon: const Icon(Icons.refresh, size: 17),
              label: const Text('Gửi lại cùng mã')),
      ]),
      if (latest != null)
        panel([
          heading('Phiên gần nhất'),
          Text(statusLabel(latest['status']),
              style: const TextStyle(
                  color: ink, fontSize: 17, fontWeight: FontWeight.w600)),
          if (latest['actual_weight_g'] != null)
            Text('Lượng thực cấp: ${amount(latest['actual_weight_g'])} g',
                style: const TextStyle(color: muted)),
          if (latest['error_code'] != null)
            Text(reasonLabel(latest['error_code']),
                style: const TextStyle(color: muted)),
          TextButton(
              onPressed: () => setState(() => tab = 2),
              child: const Text('Xem lịch sử'))
        ]),
      if (events.any((e) => e['status'] == 'FOOD_STALE'))
        notice('Có cảnh báo thức ăn tồn. Xem lịch sử và kiểm tra bát.'),
    ]);
  }

  Future<void> scheduleEditor([Map<String, dynamic>? existing]) async {
    var selectedTime = TimeOfDay(
        hour: existing?['hour'] ?? 8, minute: existing?['minute'] ?? 0);
    final selectedDays =
        Set<int>.from(existing?['days'] ?? [0, 1, 2, 3, 4, 5, 6]);
    final quantity =
        TextEditingController(text: '${existing?['target_portion_g'] ?? 20}');
    bool saving = false;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheet) => StatefulBuilder(
            builder: (sheet, update) => Padding(
                padding: EdgeInsets.fromLTRB(
                    24, 6, 24, 24 + MediaQuery.viewInsetsOf(sheet).bottom),
                child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Text(
                          existing == null
                              ? 'Thêm lịch cho ăn'
                              : 'Sửa lịch cho ăn',
                          style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                              color: ink)),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                          icon: const Icon(Icons.schedule),
                          label: Text(selectedTime.format(sheet)),
                          onPressed: saving
                              ? null
                              : () async {
                                  final picked = await showTimePicker(
                                      context: sheet,
                                      initialTime: selectedTime);
                                  if (picked != null && sheet.mounted) {
                                    update(() => selectedTime = picked);
                                  }
                                }),
                      const SizedBox(height: 12),
                      Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: List.generate(
                              7,
                              (i) => FilterChip(
                                  label: Text([
                                    'CN',
                                    'T2',
                                    'T3',
                                    'T4',
                                    'T5',
                                    'T6',
                                    'T7'
                                  ][i]),
                                  selected: selectedDays.contains(i),
                                  onSelected: saving
                                      ? null
                                      : (on) => update(() => on
                                          ? selectedDays.add(i)
                                          : selectedDays.remove(i))))),
                      const SizedBox(height: 16),
                      TextField(
                          controller: quantity,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Khẩu phần (g)')),
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  if (selectedDays.isEmpty ||
                                      double.tryParse(quantity.text) == null ||
                                      double.parse(quantity.text) <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Chọn ngày và nhập khẩu phần hợp lệ.')));
                                    return;
                                  }
                                  update(() => saving = true);
                                  final s = {
                                    'schedule_id': existing?['schedule_id'] ??
                                        'app-${DateTime.now().microsecondsSinceEpoch}',
                                    'hour': selectedTime.hour,
                                    'minute': selectedTime.minute,
                                    'days': selectedDays.toList()..sort(),
                                    'target_portion_g': grams(quantity),
                                    'enabled': existing?['enabled'] ?? true
                                  };
                                  final ok = await action(
                                      () => widget.api.request('schedules', {
                                            'schedules': [
                                              ...(data!['schedules'] as List)
                                                  .where((x) =>
                                                      x['schedule_id'] !=
                                                      s['schedule_id']),
                                              s
                                            ]
                                          }));
                                  if (sheet.mounted) {
                                    if (ok) {
                                      Navigator.pop(sheet);
                                    } else {
                                      update(() => saving = false);
                                    }
                                  }
                                },
                          child: Text(saving ? 'Đang lưu…' : 'Lưu lịch')),
                    ])))));
    // Disposed after the sheet transition so its TextField is no longer mounted.
    Future.delayed(const Duration(milliseconds: 400), quantity.dispose);
  }

  Widget schedulePage(Map<String, dynamic> state) {
    final items = state['schedules'] as List;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      heading('Bữa ăn đúng giờ'),
      const Text(
          'Thiết bị giữ lịch để thực hiện khi mất mạng, nếu đồng hồ vẫn hợp lệ.',
          style: TextStyle(color: muted, height: 1.5)),
      const SizedBox(height: 18),
      FilledButton.icon(
          onPressed:
              working || !backendAvailable ? null : () => scheduleEditor(),
          icon: const Icon(Icons.add),
          label: const Text('Thêm lịch cho ăn')),
      const SizedBox(height: 20),
      if (items.isEmpty)
        panel([
          const Icon(Icons.schedule_outlined, size: 42, color: teal),
          const SizedBox(height: 16),
          const Text('Chưa có lịch nào',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text('Thêm giờ và những ngày bạn muốn máy cấp thức ăn.',
              textAlign: TextAlign.center, style: TextStyle(color: muted))
        ]),
      for (final s in items)
        panel([
          Row(children: [
            Expanded(
                child: Text(
                    '${s['hour'].toString().padLeft(2, '0')}:${s['minute'].toString().padLeft(2, '0')}',
                    style: const TextStyle(
                        color: ink,
                        fontSize: 32,
                        fontWeight: FontWeight.w700))),
            Switch(
                value: s['enabled'],
                onChanged: working || !backendAvailable
                    ? null
                    : (on) => action(() => widget.api.request('schedules', {
                          'schedules': items
                              .map((x) => x['schedule_id'] == s['schedule_id']
                                  ? {...x, 'enabled': on}
                                  : x)
                              .toList()
                        })))
          ]),
          Text(
              '${amount(s['target_portion_g'])} g · ${(s['days'] as List).map((d) => [
                    'CN',
                    'T2',
                    'T3',
                    'T4',
                    'T5',
                    'T6',
                    'T7'
                  ][d]).join(', ')}',
              style: const TextStyle(color: muted)),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(
                onPressed: working || !backendAvailable
                    ? null
                    : () => scheduleEditor(Map<String, dynamic>.from(s)),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Sửa')),
            const Spacer(),
            IconButton(
                tooltip: 'Xóa lịch',
                icon: const Icon(Icons.delete_outline),
                onPressed: working || !backendAvailable
                    ? null
                    : () => action(() => widget.api.request('schedules', {
                          'schedules': items
                              .where(
                                  (x) => x['schedule_id'] != s['schedule_id'])
                              .toList()
                        })))
          ]),
        ]),
      const Text(
          'Mặc định UTC+7. Lịch trễ từ 60 giây sẽ được ghi là bỏ lỡ, không tự cấp dồn.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
    ]);
  }

  Widget historyPage(Map<String, dynamic> state) {
    final events = state['events'] as List;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      heading('Mỗi bữa đều rõ ràng'),
      const Text('Lịch sử cấp và thay đổi tại bát.',
          style: TextStyle(color: muted)),
      const SizedBox(height: 20),
      if (events.isEmpty)
        panel([
          const Icon(Icons.history_rounded, size: 44, color: teal),
          const SizedBox(height: 12),
          const Text('Chưa có hoạt động',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('Kết quả từ thiết bị sẽ xuất hiện tại đây.',
              textAlign: TextAlign.center, style: TextStyle(color: muted))
        ]),
      for (final e in events.take(100))
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: CircleAvatar(
                      backgroundColor: const Color(0xffeaf2e9),
                      child: Icon(
                          e['status'] == 'SUCCESS'
                              ? Icons.check_rounded
                              : Icons.notifications_none,
                          color: teal)),
                  title: Text(statusLabel(e['status']),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text(timeText(e['occurred_at'], date: true),
                      style: const TextStyle(fontSize: 12, color: muted)),
                  trailing: e['actual_weight_g'] == null
                      ? const Icon(Icons.chevron_right, size: 18)
                      : Text('${amount(e['actual_weight_g'])} g',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, color: teal)),
                  onTap: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      useSafeArea: true,
                      builder: (_) => Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(statusLabel(e['status']),
                                    style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 12),
                                Text(timeText(e['occurred_at'], date: true)),
                                if (e['actual_weight_g'] != null)
                                  Text(
                                      'Lượng thực cấp: ${amount(e['actual_weight_g'])} g'),
                                if (e['error_code'] != null)
                                  Text(reasonLabel(e['error_code'])),
                                const SizedBox(height: 16),
                                ExpansionTile(
                                    title: const Text('Thông tin kỹ thuật'),
                                    children: [
                                      SelectableText(
                                          'Trạng thái: ${e['status']}\nMã phiên: ${e['command_id'] ?? '—'}\nMã sự kiện: ${e['event_id']}\nChi tiết: ${e['error_code'] ?? '—'}')
                                    ]),
                              ]))),
                ))),
      const SizedBox(height: 10),
      const Text('Khối lượng bát giảm chưa đủ để xác nhận thú đã ăn.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
    ]);
  }

  Future<dynamic> saveConfig() {
    final cfg = <String, dynamic>{
      'food_label': food.text,
      'food_confirmed': foodConfirmed,
      'require_pet': requirePet
    };
    for (final k in labels.keys) {
      final n = num.tryParse(configFields[k]!.text);
      if (n == null || !n.isFinite) throw const FormatException();
      cfg[k] = n;
    }
    return widget.api.request('config', cfg);
  }

  Widget settingsPage(Map<String, dynamic> state) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        heading('Chăm sóc theo cách của bạn'),
        panel([
          heading('Thức ăn trong hộp'),
          TextField(
              controller: food,
              decoration: const InputDecoration(
                  labelText: 'Tên loại thức ăn',
                  hintText: 'Ví dụ: Hạt cho mèo trưởng thành')),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: foodConfirmed,
              title: const Text('Tôi đã kiểm tra thức ăn',
                  style: TextStyle(fontSize: 14)),
              onChanged:
                  working ? null : (v) => setState(() => foodConfirmed = v!)),
          const Text(
              'Đây là xác nhận của chủ, không phải kết quả phân loại hoặc kiểm nghiệm từ cảm biến.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.5))
        ]),
        panel([
          heading('Nhận diện thú cưng'),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: requirePet,
              title: const Text('Yêu cầu xác minh trước khi cấp',
                  style: TextStyle(fontSize: 14)),
              onChanged:
                  working ? null : (v) => setState(() => requirePet = v)),
          const Text(
              'Hiện chưa có RFID/camera. Khi bật, máy sẽ từ chối cấp nếu chưa xác minh được thú.',
              style: TextStyle(color: muted, fontSize: 12, height: 1.5))
        ]),
        primary('Lưu cài đặt', saveConfig),
        const SizedBox(height: 18),
        panel([
          ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Cài đặt nâng cao',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              subtitle: const Text('Giới hạn và thời gian kiểm thử',
                  style: TextStyle(fontSize: 12)),
              children: [
                for (final entry in labels.entries)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TextField(
                          controller: configFields[entry.key],
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          decoration: InputDecoration(labelText: entry.value))),
                primary('Lưu giới hạn', saveConfig),
                const SizedBox(height: 8),
              ])
        ]),
        if (state['mode'] == 'DEMO')
          panel([
            ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Công cụ mô phỏng',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                subtitle: const Text('Dành cho kiểm thử 18 kịch bản',
                    style: TextStyle(fontSize: 12)),
                children: [
                  const Text(
                      'Các thao tác dưới đây thay đổi thiết bị giả lập, không phải cảm biến thật.',
                      style: TextStyle(color: muted, fontSize: 12)),
                  const SizedBox(height: 14),
                  TextField(
                      controller: weight,
                      decoration: const InputDecoration(
                          labelText: 'Khối lượng giả lập (g)'),
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 8),
                  primary(
                      'Đặt khối lượng',
                      () => widget.api.request(
                          'demo', {'weight_g': double.parse(weight.text)})),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: online,
                      title: const Text('Có mạng'),
                      onChanged: (v) => setState(() => online = v)),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: timeValid,
                      title: const Text('Giờ hợp lệ'),
                      onChanged: (v) => setState(() => timeValid = v)),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: autoFeed,
                      title: const Text('Tự tăng hạt khi cấp'),
                      onChanged: (v) => setState(() => autoFeed = v)),
                  primary(
                      'Áp dụng mô phỏng',
                      () => widget.api.request('demo', {
                            'online': online,
                            'time_valid': timeValid,
                            'auto_feed': autoFeed
                          })),
                  Wrap(spacing: 8, children: [
                    for (final sec in [5, 61, 181, 36000])
                      TextButton(
                          onPressed: working || !backendAvailable
                              ? null
                              : () => action(() => widget.api
                                  .request('demo', {'advance_s': sec})),
                          child: Text('+$sec giây'))
                  ]),
                  TextButton(
                      onPressed: working
                          ? null
                          : () => action(() =>
                              widget.api.request('demo', {'weight_g': null})),
                      child: const Text('Giả lập cân mất tín hiệu')),
                  TextButton(
                      onPressed: working
                          ? null
                          : () => action(() =>
                              widget.api.request('demo', {'restart': true})),
                      child: const Text('Khởi động lại thiết bị giả lập')),
                  TextButton(
                      onPressed: working
                          ? null
                          : () => action(() =>
                              widget.api.request('demo', {'reconcile': true})),
                      child: const Text('Đã kiểm tra phiên gián đoạn')),
                ])
          ]),
      ]);

  @override
  Widget build(BuildContext context) {
    final state = data;
    final connected = backendAvailable && state?['connection'] == 'ONLINE';
    final busy = backendAvailable && state?['connection'] == 'BUSY';
    final content = Scaffold(
        backgroundColor: const Color(0xfff5f7f2),
        appBar: AppBar(
            backgroundColor: const Color(0xfff5f7f2),
            scrolledUnderElevation: 0,
            titleSpacing: 20,
            title: Row(children: [
              const Icon(Icons.pets_rounded, color: teal, size: 23),
              const SizedBox(width: 9),
              Expanded(
                  child: Text(
                      ['PetFeeder', 'Lịch cho ăn', 'Hoạt động', 'Cài đặt'][tab],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: ink)))
            ]),
            actions: [
              Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                          color: connected || busy
                              ? const Color(0xffe5f0e4)
                              : const Color(0xfff5e6dd),
                          borderRadius: BorderRadius.circular(30)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.circle,
                            size: 7,
                            color: connected || busy
                                ? teal
                                : const Color(0xffad694b)),
                        const SizedBox(width: 6),
                        Text(
                            connected
                                ? 'Đã kết nối'
                                : busy
                                    ? 'Đang cấp'
                                    : 'Mất kết nối',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: ink))
                      ])))
            ]),
        body: state == null
            ? Center(
                child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.pets_outlined, size: 50, color: teal),
                      const SizedBox(height: 20),
                      const Text('Đang kết nối máy cho ăn',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: ink)),
                      const SizedBox(height: 10),
                      const Text(
                          'Hãy kiểm tra backend đang chạy, sau đó thử lại.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: muted)),
                      const SizedBox(height: 20),
                      OutlinedButton(
                          onPressed: refresh, child: const Text('Thử lại')),
                    ])))
            : RefreshIndicator(
                onRefresh: refresh,
                child: ListView(
                    key: ValueKey(tab),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      if (!backendAvailable)
                        notice(
                            'Mất kết nối máy chủ. Đang hiển thị dữ liệu lần cuối; tạm khóa thao tác cấp.'),
                      if (state['mode'] == 'DEMO')
                        Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(children: [
                              const Icon(Icons.science_outlined,
                                  size: 16, color: muted),
                              const SizedBox(width: 7),
                              const Text('Chế độ mô phỏng',
                                  style: TextStyle(fontSize: 11, color: muted))
                            ])),
                      if (working)
                        const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: LinearProgressIndicator(minHeight: 2)),
                      switch (tab) {
                        0 => home(state),
                        1 => schedulePage(state),
                        2 => historyPage(state),
                        _ => settingsPage(state)
                      },
                    ])),
        bottomNavigationBar: NavigationBar(
            height: 72,
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xffe2efdc),
            selectedIndex: tab,
            onDestinationSelected: (i) => setState(() => tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Trang chủ'),
              NavigationDestination(
                  icon: Icon(Icons.schedule_outlined),
                  selectedIcon: Icon(Icons.schedule_rounded),
                  label: 'Lịch ăn'),
              NavigationDestination(
                  icon: Icon(Icons.history_outlined),
                  selectedIcon: Icon(Icons.history_rounded),
                  label: 'Lịch sử'),
              NavigationDestination(
                  icon: Icon(Icons.tune_outlined),
                  selectedIcon: Icon(Icons.tune_rounded),
                  label: 'Cài đặt'),
            ]));
    // Same mobile layout on a phone; desktop web is a narrow preview of that app.
    return ColoredBox(
        color: const Color(0xffe4eae5),
        child: Center(
            child: ConstrainedBox(
                key: const Key('mobile-shell'),
                constraints: const BoxConstraints(maxWidth: 460),
                child: SafeArea(child: content))));
  }
}
