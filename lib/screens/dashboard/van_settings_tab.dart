import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../constants.dart';
import '../../models/van.dart';
import '../../state/dashboard_provider.dart';
import '../../widgets/common.dart';

class VanSettingsTab extends StatefulWidget {
  const VanSettingsTab({super.key});

  @override
  State<VanSettingsTab> createState() => _VanSettingsTabState();
}

class _VanSettingsTabState extends State<VanSettingsTab> {
  final Map<int, TextEditingController> _timeCtrls = {for (var i = 1; i <= 5; i++) i: TextEditingController()};
  final Map<int, TextEditingController> _flowCtrls = {for (var i = 1; i <= 5; i++) i: TextEditingController()};
  final _h10Ctrl = TextEditingController();
  final _fxxCtrl = TextEditingController();
  final _cxxCtrl = TextEditingController();
  DateTime? _pickedDateTime;
  // [FIX] Truoc day dung 1 co "_synced" CHI cho phep dong bo DUNG 1 LAN -
  // gio doi sang so sanh thoi diem (giong cach da sua wifiScanUpdatedAt o
  // esp_settings_tab.dart) de co the dong bo lai NHIEU LAN: moi khi co ban
  // ##CFG## MOI ve (sau khi vao tab, hoac sau khi bam Luu de xac nhan gia
  // tri THAT SU tren van), khong chi dung 1 lan luc mo dashboard.
  DateTime? _appliedCfgAt;

  @override
  void initState() {
    super.initState();
    // Xin du lieu cai dat ngay khi tab nay duoc tao (dashboard cung tu xin
    // luc moi ket noi, nhung goi them o day de chac chan co du lieu moi
    // nhat neu nguoi dung mo thang toi tab nay).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DashboardProvider>().publish('SETTINGS?');
    });
  }

  @override
  void dispose() {
    for (final c in _timeCtrls.values) {
      c.dispose();
    }
    for (final c in _flowCtrls.values) {
      c.dispose();
    }
    _h10Ctrl.dispose();
    _fxxCtrl.dispose();
    _cxxCtrl.dispose();
    super.dispose();
  }

  /// [FIX] Dong bo lai MOI KHI co ban ##CFG## MOI (so sanh cfgUpdatedAt),
  /// khong chi 1 lan duy nhat - de "Lưu" xong hoac vao lai tab co the tu
  /// dong cap nhat cac o nhap theo gia tri THAT SU tren van, khong can nut
  /// "Tải Lại Giá Trị" thu cong nua.
  void _syncFromState(dynamic t) {
    final updatedAt = t.cfgUpdatedAt as DateTime?;
    if (updatedAt == null) return; // ##CFG## chua ve lan nao - thu lai o lan build sau
    if (_appliedCfgAt != null && !updatedAt.isAfter(_appliedCfgAt!)) return; // da ap dung ban nay roi
    _appliedCfgAt = updatedAt;
    if (t.cfgWm != null) {
      for (var i = 1; i <= 5 && i <= t.cfgWm.length; i++) {
        _timeCtrls[i]!.text = t.cfgWm[i - 1].toString();
      }
    }
    if (t.cfgQl != null && t.cfgQr != null) {
      for (var i = 1; i <= 5 && i <= t.cfgQl.length; i++) {
        final whole = t.cfgQl[i - 1] as int;
        final frac = t.cfgQr[i - 1] as int;
        _flowCtrls[i]!.text = '$whole.${frac.toString().padLeft(2, '0')}';
      }
    }
    if (t.cfgH10 != null) _h10Ctrl.text = t.cfgH10.toString();
    if (t.cfgFxx != null) _fxxCtrl.text = t.cfgFxx.toString();
    if (t.cfgCxx != null) _cxxCtrl.text = t.cfgCxx.toString();
  }

  int? _asInt(TextEditingController c) => int.tryParse(c.text.trim());

  /// Parse "25.5", "25,50", "25" -> (whole: 25, frac: 50). SETFLOW gui 2 so
  /// nguyen rieng (phan nguyen m3 + phan tram thap phan), nhung nguoi dung
  /// nhap 1 so thap phan duy nhat cho tu nhien - tach ra o day.
  ({int whole, int frac})? _parseFlow(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    final value = double.tryParse(normalized);
    if (value == null || value < 0 || value > 99.99) return null;
    final whole = value.floor();
    final frac = ((value - whole) * 100).round();
    return (whole: whole, frac: frac);
  }

  /// Gui lenh + phan hoi truc quan (rung nhe + snackbar xac nhan) de nguoi
  /// dung luon biet chac da bam duoc hay chua, khong chi im lang gui lenh.
  /// [FIX] Dung chung 1 ham cho MOI nut "Luu" trong tab nay (SETH10/SETFXX/
  /// SETCXX/SETMODEA/SETMODEB/SETPOS/SETFLOW/SETDATETIME/MODEL) - kiem tra
  /// isConnectionStale TRUOC KHI gui o DAY se tu dong bao ve tat ca, thay
  /// vi truoc day cu goi thang publish() roi hien "Đã lưu..." du van co the
  /// da mat ket noi tu truoc, khien nguoi dung tuong da luu thanh cong.
  /// [NEW] Sau khi gui xong (tru chinh ban than SETTINGS?), tu dong xin lai
  /// ##CFG## sau 1 khoang tre ngan de xac nhan gia tri THAT SU da duoc van
  /// ap dung/ghi EEPROM - _syncFromState() se tu dong dien lai cac o nhap
  /// khi ban ##CFG## moi nay ve, thay cho nut "Tải Lại Giá Trị" thu cong.
  void _publish(BuildContext context, String cmd, [String? confirmMsg]) {
    final prov = context.read<DashboardProvider>();
    if (prov.isConnectionStale) {
      HapticFeedback.heavyImpact();
      showSnack(context, 'Mất kết nối với van — đang thử kết nối lại, vui lòng chờ rồi thử lại.', isError: true);
      prov.refreshAll();
      return;
    }
    HapticFeedback.lightImpact();
    prov.publish(cmd);
    if (confirmMsg != null) showSnack(context, confirmMsg);
    if (cmd != 'SETTINGS?') {
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) prov.publish('SETTINGS?');
      });
    }
  }

  Future<void> _pickDateTime(BuildContext context) async {
    final now = _pickedDateTime ?? DateTime.now();
    final date = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(2020), lastDate: DateTime(2099));
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(now));
    if (time == null) return;
    setState(() {
      _pickedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute, now.second);
    });
  }

  void _sendDateTime(BuildContext context, DateTime d) {
    final yy = d.year % 100;
    final wd = d.weekday % 7; // Dart: Mon=1..Sun=7 -> can 0(CN)-6(T7) giong Date.getDay()
    _publish(context, 'SETDATETIME:$yy:${d.month}:${d.day}:$wd:${d.hour}:${d.minute}:${d.second}', 'Đã gửi lệnh đồng bộ ngày giờ...');
  }

  /// [NEW] "DD/MM/YY" (##MON## gui 2 chu so nam) -> "DD/MM/20YY" de doc de hon.
  String _fullDate(String? d) {
    if (d == null) return '--';
    final parts = d.split('/');
    if (parts.length == 3) return '${parts[0]}/${parts[1]}/20${parts[2]}';
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DashboardProvider>();
    final t = prov.telemetry;
    _syncFromState(t);
    final isFlowValve = isFlowValveModel(t.mcuVan);

    // [FIX] Bo nut "Làm Mới" o AppBar (dashboard_screen.dart) - dung
    // RefreshIndicator (keo-de-lam-moi) o day, dong bo cach lam voi tab
    // Giam Sat (monitor_tab.dart) thay vi 2 co che khac nhau tren 2 tab.
    return RefreshIndicator(
      onRefresh: () => prov.refreshAll(),
      child: ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        SectionCard(
          title: 'Đồng Bộ Ngày Giờ Van',
          icon: Icons.schedule,
          children: [
            // [NEW] Hien ngay gio HIEN TAI cua van (tu ##MON## - cap nhat
            // dinh ky), de nguoi dung biet van dang chay dung/sai gio truoc
            // khi quyet dinh co can dong bo lai hay khong.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.access_time_filled_rounded, size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Giờ hiện tại trên van', style: Theme.of(context).textTheme.bodySmall),
                        Text(
                          t.monDate != null && t.monTime != null ? '${_fullDate(t.monDate)}  ${t.monTime}' : 'Chưa có dữ liệu',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_pickedDateTime != null
                  ? '${_pickedDateTime!.day}/${_pickedDateTime!.month}/${_pickedDateTime!.year} '
                      '${_pickedDateTime!.hour.toString().padLeft(2, '0')}:${_pickedDateTime!.minute.toString().padLeft(2, '0')}'
                  : 'Chưa chọn ngày giờ'),
              trailing: OutlinedButton(onPressed: () => _pickDateTime(context), child: const Text('Chọn')),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _pickedDateTime == null ? null : () => _sendDateTime(context, _pickedDateTime!),
                    child: const Text('Áp Dụng Giờ Đã Chọn'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final ok = await confirmDialog(context,
                          title: 'Đồng bộ giờ điện thoại?',
                          message: 'Đồng bộ giờ van theo giờ hiện tại của điện thoại (${now.toString()})?');
                      if (ok && context.mounted) _sendDateTime(context, now);
                    },
                    child: const Text('Dùng Giờ Điện Thoại (NTP)'),
                  ),
                ),
              ],
            ),
          ],
        ),
        SectionCard(
          title: 'Cấu Hình Chế Độ A / B',
          icon: Icons.settings_suggest,
          children: [
            Text('Chế độ A hiện tại: A-${(t.cfgModeA ?? t.monModeA ?? 0).toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 1, label: Text('A-01')), ButtonSegment(value: 2, label: Text('A-02'))],
              selected: {t.cfgModeA ?? t.monModeA ?? 1},
              onSelectionChanged: (s) => _publish(context, 'SETMODEA:${s.first}', 'Đã lưu Chế Độ A-${s.first.toString().padLeft(2, '0')}.'),
            ),
            const SizedBox(height: 14),
            Text('Chế độ B hiện tại: B-${(t.cfgModeB ?? t.monModeB ?? 0).toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 1, label: Text('B-01')), ButtonSegment(value: 2, label: Text('B-02'))],
              selected: {t.cfgModeB ?? t.monModeB ?? 1},
              onSelectionChanged: (s) => _publish(context, 'SETMODEB:${s.first}', 'Đã lưu Chế Độ B-${s.first.toString().padLeft(2, '0')}.'),
            ),
          ],
        ),
        SectionCard(
          title: 'H10, Fxx & Cxx',
          icon: Icons.exposure,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _h10Ctrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'H10 (0-99 phút)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final v = _asInt(_h10Ctrl);
                  if (v == null || v < 0 || v > 99) return showSnack(context, 'Giá trị phải 0-99.', isError: true);
                  _publish(context, 'SETH10:$v', 'Đã lưu H10 = $v.');
                },
                child: const Text('Lưu'),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _fxxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Fxx (0-20 chu kỳ)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final v = _asInt(_fxxCtrl);
                  if (v == null || v < 0 || v > 20) return showSnack(context, 'Giá trị phải 0-20.', isError: true);
                  _publish(context, 'SETFXX:$v', 'Đã lưu Fxx = $v.');
                },
                child: const Text('Lưu'),
              ),
            ]),
            const SizedBox(height: 12),
            // [NEW] Cxx: so chu ky giua 2 lan canh bao het vat lieu - dat lai
            // gia tri (kem ca 0) se RESET so chu ky con lai ve day du, xoa
            // luon canh bao dang bip (xem SETCXX: trong uart1_rx.c firmware).
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _cxxCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Cxx (0-99 chu kỳ, cảnh báo hết vật liệu)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  final v = _asInt(_cxxCtrl);
                  if (v == null || v < 0 || v > 99) return showSnack(context, 'Giá trị phải 0-99.', isError: true);
                  _publish(context, 'SETCXX:$v', 'Đã lưu Cxx = $v (đã reset số chu kỳ còn lại).');
                },
                child: const Text('Lưu'),
              ),
            ]),
          ],
        ),
        SectionCard(
          title: isFlowValve ? 'Lưu Lượng Theo Từng Vị Trí' : 'Thời Gian Theo Từng Vị Trí',
          icon: Icons.list_alt,
          children: [
            if (isFlowValve)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'Nhập lưu lượng cho từng vị trí, ví dụ 25.5 (tối đa 99.99 m³).',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            for (final entry in kWaterModes.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(width: 90, child: Text('${entry.value.icon} P${entry.key} ${entry.value.name}', style: const TextStyle(fontSize: 11))),
                    if (!isFlowValve) ...[
                      Expanded(
                        child: TextField(
                          controller: _timeCtrls[entry.key],
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Phút', isDense: true, border: OutlineInputBorder()),
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: TextField(
                          controller: _flowCtrls[entry.key],
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}([.,]\d{0,2})?$'))],
                          textAlign: TextAlign.right,
                          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), suffixText: 'm³'),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.save),
                      onPressed: () {
                        final label = entry.value.name;
                        if (!isFlowValve) {
                          final v = _asInt(_timeCtrls[entry.key]!);
                          if (v == null || v < 0 || v > 99) return showSnack(context, 'Số phút phải 0-99.', isError: true);
                          _publish(context, 'SETPOS:${entry.key}:$v', 'Đã lưu $label = $v phút.');
                        } else {
                          final parsed = _parseFlow(_flowCtrls[entry.key]!.text);
                          if (parsed == null) return showSnack(context, 'Lưu lượng phải từ 0 đến 99.99 m³.', isError: true);
                          _publish(context, 'SETFLOW:${entry.key}:${parsed.whole}:${parsed.frac}',
                              'Đã lưu $label = ${parsed.whole}.${parsed.frac.toString().padLeft(2, '0')} m³.');
                        }
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
        SectionCard(
          title: 'Đổi Mã Van (Model)',
          icon: Icons.swap_horiz,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: Van.modelLabels.entries.map((e) {
                final modelNum = {'F021': 1, 'F023': 2, '5021': 3, '5023': 4}[e.key]!;
                final selected = t.mcuVan == e.key;
                return ChoiceChip(
                  label: Text('${e.key} — ${e.value}'),
                  selected: selected,
                  onSelected: (_) async {
                    final ok = await confirmDialog(context,
                        title: 'Chuyển sang ${e.key}?',
                        message: 'Chuyển sang mã van "${e.value}" (Mã $modelNum)? MCU sẽ lưu EEPROM và khởi động lại.');
                    if (ok && context.mounted) _publish(context, 'MODEL:$modelNum', 'Đã gửi lệnh chuyển mã van sang ${e.key}...');
                  },
                );
              }).toList(),
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
      ),
    );
  }
}
