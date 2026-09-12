import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/van.dart';
import '../state/auth_provider.dart';
import '../state/van_list_provider.dart';
import '../widgets/common.dart';
import 'ble_pair_screen.dart';

/// Noi dung tab "Quan Ly Van" trong MainShell - danh sach toan bo van, moi
/// the hien thong tin nhanh (tin hieu, vi tri, dang chay) + nut NEXT dieu
/// khien nhanh. Truoc day day la 1 SCREEN RIENG duoc PUSH tu ngoai vao (mo
/// dashboard = push tiep 1 screen khac chong len); gio la 1 TAB trong cung 1
/// shell nen chon 1 van chi don gian la goi [onSelectVan] de MainShell doi
/// "van dang xem" - khong con Navigator.push nao ca.
class VanListTab extends StatefulWidget {
  final void Function(Van van) onSelectVan;
  const VanListTab({super.key, required this.onSelectVan});

  @override
  State<VanListTab> createState() => _VanListTabState();
}

class _VanListTabState extends State<VanListTab> {
  Future<void> _openAddDialog() async {
    final codeCtrl = TextEditingController();
    final prefixCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String? model;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm Van Mới'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Mã van (vd: VAN-01)')),
              const SizedBox(height: 10),
              TextField(
                controller: prefixCtrl,
                decoration: const InputDecoration(labelText: 'MQTT Topic Prefix (vd: van_E6EBAC)'),
              ),
              const SizedBox(height: 10),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên hiển thị (tuỳ chọn)')),
              const SizedBox(height: 10),
              StatefulBuilder(
                builder: (ctx, setSt) => DropdownButtonFormField<String>(
                  initialValue: model,
                  decoration: const InputDecoration(labelText: 'Model van (tuỳ chọn)'),
                  items: Van.modelLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setSt(() => model = v),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Thêm')),
        ],
      ),
    );

    if (ok != true) return;
    if (codeCtrl.text.trim().isEmpty || prefixCtrl.text.trim().isEmpty) {
      if (mounted) showSnack(context, 'Vui lòng nhập đủ mã van và MQTT prefix.', isError: true);
      return;
    }
    if (!mounted) return;
    final provider = context.read<VanListProvider>();
    final success = await provider.addVan(
      code: codeCtrl.text.trim(),
      mqttPrefix: prefixCtrl.text.trim(),
      model: model,
      name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
    );
    if (!mounted) return;
    if (!success) {
      showSnack(context, provider.error ?? 'Không thêm được van.', isError: true);
    }
  }

  Future<void> _openAddMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(alignment: Alignment.centerLeft, child: Text('Thêm Van Mới', style: TextStyle(fontWeight: FontWeight.w700))),
            ),
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: const Text('Ghép nối qua Bluetooth'),
              subtitle: const Text('Tự nhận mã van, cài WiFi trực tiếp từ điện thoại - không cần biết trước mã van'),
              onTap: () => Navigator.pop(ctx, 'ble'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Nhập mã van thủ công'),
              subtitle: const Text('Dùng khi đã biết mã van và MQTT prefix'),
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'ble') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlePairScreen()));
    } else if (choice == 'manual') {
      _openAddDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final vanList = context.watch<VanListProvider>();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => vanList.load(),
        child: vanList.loading
            ? const Center(child: CircularProgressIndicator())
            : vanList.vans.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 100),
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.water_drop_outlined, size: 44, color: Theme.of(context).colorScheme.onPrimaryContainer),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: Text(
                          auth.user != null ? 'Chào ${auth.user!['username']}!' : 'Chưa có van nào',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          'Bấm nút + để thêm van đầu tiên của bạn.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88, top: 8),
                    itemCount: vanList.vans.length,
                    itemBuilder: (ctx, i) {
                      final v = vanList.vans[i];
                      return _VanCard(van: v, onSelect: widget.onSelectVan);
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddMenu,
        icon: const Icon(Icons.add),
        label: const Text('Thêm Van'),
      ),
    );
  }
}

/// The hien thi 1 van trong "Quan Ly Van" - ngoai ten/trang thai online, con
/// hien truc tiep 1 so thong tin nhanh (tin hieu, vi tri hien tai, dang chay
/// hay khong) va 1 nut NEXT dieu khien nhanh, KHONG can mo dashboard day du.
/// Tach rieng thanh StatefulWidget de tu quan ly trang thai "dang gui NEXT"
/// cua rieng no (khong lam rebuild ca danh sach khi 1 the dang gui lenh).
class _VanCard extends StatefulWidget {
  final Van van;
  final void Function(Van van) onSelect;
  const _VanCard({required this.van, required this.onSelect});

  @override
  State<_VanCard> createState() => _VanCardState();
}

class _VanCardState extends State<_VanCard> {
  bool _sendingNext = false;

  /// Chuyen dBm WiFi thanh 1 trong 3 muc icon "vach song" - nguong tham khao
  /// theo quy uoc pho bien (-60 tot, -75 trung binh, con lai yeu) giong het
  /// _rssiIcon() da dung trong esp_settings_tab.dart. BLE khong co bo icon
  /// vach song chuan nen dung 1 icon Bluetooth co dinh + so dBm (xem _signalChip).
  IconData _wifiIcon(int rssi) {
    if (rssi >= -60) return Icons.wifi_rounded;
    if (rssi >= -75) return Icons.wifi_2_bar_rounded;
    return Icons.wifi_1_bar_rounded;
  }

  Color _signalColor(BuildContext context, int rssi) {
    if (rssi >= -60) return Colors.green;
    if (rssi >= -75) return Colors.orange;
    return Colors.red;
  }

  /// 1 chi bao cuong do song DUY NHAT cho the van - uu tien song WiFi cua
  /// CHINH VAN (qua MQTT) neu van dang online qua kenh do, khong thi dung
  /// song BLE (phone quet truc tiep) neu con "nhin thay" van gan do; khong co
  /// gi ca thi hien "khong co tin hieu".
  Widget _signalChip(BuildContext context, {required bool isOnline, int? wifiRssi, int? bleRssi}) {
    if (isOnline && wifiRssi != null) {
      return _infoChip(context, _wifiIcon(wifiRssi), '$wifiRssi dBm', _signalColor(context, wifiRssi));
    }
    if (bleRssi != null) {
      return _infoChip(context, Icons.bluetooth_rounded, '$bleRssi dBm', _signalColor(context, bleRssi));
    }
    return _infoChip(context, Icons.signal_cellular_off_rounded, 'Không có tín hiệu', Colors.grey);
  }

  Future<void> _deleteVan(BuildContext context, Van v) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Xoá van?',
      message: 'Xoá "${v.displayName}" khỏi tài khoản của bạn?'
          '${v.isOwner ? ' Mọi người đang được bạn chia sẻ van này cũng sẽ mất quyền truy cập.' : ''}',
    );
    if (!confirmed || !context.mounted) return;
    final provider = context.read<VanListProvider>();
    final ok = await provider.deleteVan(v.id);
    if (!ok && context.mounted) {
      showSnack(context, provider.error ?? 'Không xoá được van.', isError: true);
    }
  }

  /// [NEW] Nguoi DUOC chia se (khong phai chu) roi khoi 1 van - khac han
  /// xoa (chi chu so huu xoa duoc), xem VanListProvider.leaveVan().
  Future<void> _leaveVan(BuildContext context, Van v) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Rời khỏi van?',
      message: 'Bạn sẽ không còn thấy "${v.displayName}" trong danh sách nữa. '
          'Chủ van (${v.ownerUsername ?? '?'}) có thể chia sẻ lại cho bạn bất cứ lúc nào.',
    );
    if (!confirmed || !context.mounted) return;
    final auth = context.read<AuthProvider>();
    final myId = auth.user?['id'] as int?;
    if (myId == null) return;
    final provider = context.read<VanListProvider>();
    final ok = await provider.leaveVan(v, myId);
    if (!ok && context.mounted) {
      showSnack(context, provider.error ?? 'Không thực hiện được thao tác này.', isError: true);
    }
  }

  Future<void> _openShareDialog(BuildContext context, Van v) async {
    await showDialog(
      context: context,
      builder: (_) => _ShareVanDialog(van: v),
    );
  }

  Future<void> _sendNext(BuildContext context, Van v) async {
    if (!v.canControl) {
      showSnack(context, 'Bạn chỉ được chia sẻ quyền giám sát van này — không thể điều khiển.', isError: true);
      return;
    }
    setState(() => _sendingNext = true);
    HapticFeedback.lightImpact();
    final ok = await context.read<VanListProvider>().sendQuickCommand(v, 'NEXT');
    if (!mounted) return;
    setState(() => _sendingNext = false);
    if (!context.mounted) return;
    showSnack(
      context,
      ok ? 'Đã gửi lệnh NEXT tới "${v.displayName}".' : 'Không gửi được lệnh - van có thể đang offline.',
      isError: !ok,
    );
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.van;
    final vanList = context.watch<VanListProvider>();
    final status = vanList.onlineStatus[v.mqttPrefix];
    final pos = vanList.posByPrefix[v.mqttPrefix];
    final wifiRssi = vanList.wifiRssiByPrefix[v.mqttPrefix];
    final bleRssi = vanList.bleRssiByPrefix[v.mqttPrefix];
    final running = vanList.runningByPrefix[v.mqttPrefix] ?? false;
    final scanning = vanList.scanningByPrefix[v.mqttPrefix] ?? false;
    // [FIX] Van.model (v.model) chi la gia tri NHAP 1 LAN luc them van vao
    // app - se LECH neu model vat ly tren thiet bi bi doi sau do (vd cai lai
    // valve khac, hoac nhap sai luc them) ma khong ai sua lai trong app. Uu
    // tien model SONG (tu ##MCU##/##MON##, xem VanStatusChecker) - chi dung
    // v.model khi van dang offline/chua nhan duoc gi ca.
    final effectiveModel = vanList.liveModelByPrefix[v.mqttPrefix] ?? v.model;
    // [FIX] Vi tri VO NGHIA trong luc dang quet (xem chu thich isScanning
    // trong monitor_tab.dart/control_tab.dart) - khong tra bang 1 vi tri cu/
    // sai con sot lai tu truoc do. Dung modeForPosition() (khong phai
    // kWaterModes truc tiep) de van 3 cua (F041/F043) hien dung nhan "Rua
    // Xuoi" o vi tri 3 thay vi "Hoan Nguyen" sai hoan toan.
    final mode = (!scanning && pos != null) ? modeForPosition(effectiveModel, pos) : null;
    final isOnline = status == VanOnlineStatus.online;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onSelect(v),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.water_drop, color: Theme.of(context).colorScheme.onPrimaryContainer),
                      ),
                      // [FIX] Icon bao online/offline goc duoi-phai avatar - tu dong
                      // kiem tra ngay khi vao man hinh nay (xem VanListProvider.load()).
                      Positioned(right: -2, bottom: -2, child: _OnlineDot(status: status)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        // [FIX] Bo hien thi "Prefix: ..." theo yeu cau - chi con Ma van
                        // (va model neu co), Prefix la chi tiet ky thuat khong can thiet
                        // cho nguoi dung thuong.
                        Text(
                          'Mã: ${v.code}${effectiveModel != null ? ' • ${Van.modelLabels[effectiveModel] ?? effectiveModel}' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        // [NEW] Van duoc NGUOI KHAC chia se - ghi ro chu thuc
                        // su + quyen dang co (giam sat luon co, dieu khien/cai
                        // dat co the bi tat), tranh nham tuong day la van cua
                        // chinh minh (xem [[them tinh nang chia se]]).
                        if (!v.isOwner)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Được chia sẻ bởi ${v.ownerUsername ?? '?'} • '
                              '${v.canControl ? 'Giám sát + Điều khiển' : 'Chỉ giám sát'}'
                              '${v.canConfigure ? ' + Cài đặt' : ''}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.blueAccent, fontWeight: FontWeight.w600),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // [NEW] Van cua chinh minh: nut Chia Se + Xoa. Van duoc
                  // NGUOI KHAC chia se: chi co nut "Roi khoi van" (khong xoa
                  // duoc van cua nguoi khac, backend cung chan o tang API).
                  if (v.isOwner) ...[
                    IconButton(
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      tooltip: 'Chia sẻ van',
                      onPressed: () => _openShareDialog(context, v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deleteVan(context, v),
                    ),
                  ] else
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, color: Colors.red),
                      tooltip: 'Rời khỏi van',
                      onPressed: () => _leaveVan(context, v),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // [FIX] Chi hien 1 chi bao cuong do song DUY NHAT - lay theo dung
              // kenh dang THAT SU dung de lien lac voi van luc nay (online qua
              // MQTT -> song WiFi cua van toi router; khong thi neu con "nhin
              // thay" qua quet BLE -> song Bluetooth), thay vi hien ca 2 gay
              // roi vi 2 con so khong lien quan (song WiFi cua VAN toi router
              // nha, khac hoan toan song Bluetooth cua DIEN THOAI toi van).
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _signalChip(context, isOnline: isOnline, wifiRssi: wifiRssi, bleRssi: bleRssi),
                  // [FIX] Dang quet (vi tri THUC SU vo nghia luc nay - xem
                  // chu thich isScanning trong monitor_tab.dart/control_tab.dart)
                  // uu tien hien THAY vi chip vi tri/che do, ro rang hon "Vị
                  // trí: --" chung chung. Se tu chuyen ve chip che do binh
                  // thuong ngay khi co vi tri MOI (quet xong).
                  if (scanning)
                    _infoChip(context, Icons.travel_explore_rounded, 'Đang quét', Colors.blueAccent)
                  else if (mode != null)
                    _infoChip(context, Icons.water_drop_outlined, '${mode.icon} ${mode.name}', Theme.of(context).colorScheme.primary)
                  else
                    _infoChip(context, Icons.help_outline_rounded, 'Vị trí: --', Colors.grey),
                  // [NEW] Bao dong co dang chay truc tiep tren the - dung chung
                  // 1 nguon trang thai voi nut NEXT ben duoi (VanStatusChecker).
                  if (running && !scanning)
                    _infoChip(context, Icons.settings_ethernet_rounded, 'Đang chạy', Colors.blueAccent),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  // [FIX] Khoa nut NEXT trong luc dong co dang chay HOAC dang
                  // quet (firmware tu choi ca 2 lenh GOTO/NEXT khi chua quet
                  // xong - "ERR: chua quet", xem uart1_rx.c) - tranh bam lap
                  // gay lenh chong lenh hoac gui lenh chac chan bi tu choi.
                  onPressed: (!isOnline || !v.canControl || _sendingNext || running || scanning) ? null : () => _sendNext(context, v),
                  icon: (_sendingNext || running || scanning)
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.skip_next_rounded, size: 18),
                  label: Text(!v.canControl ? 'Chỉ xem' : (scanning ? 'Đang quét' : (running ? 'Đang chạy' : 'NEXT'))),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(BuildContext context, IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// Cham tron nho bao trang thai online/offline tren avatar cua van, dat goc
/// duoi-phai (kieu "presence dot" quen thuoc). Xam = dang kiem tra/chua ro.
class _OnlineDot extends StatelessWidget {
  final VanOnlineStatus? status;
  const _OnlineDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (status) {
      case VanOnlineStatus.online:
        color = Colors.green;
        break;
      case VanOnlineStatus.offline:
        color = Colors.red;
        break;
      case VanOnlineStatus.checking:
      case null:
        color = Colors.grey;
        break;
    }
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
      ),
    );
  }
}

/// Dialog "Chia Sẻ Van" - chi mo duoc tu the cua van MA MINH LA CHU SO HUU
/// (xem nut Icons.person_add_alt_1_outlined trong _VanCardState o tren).
/// Hien danh sach nguoi dang duoc chia se (kem quyen, co the thu hoi tung
/// nguoi) + form them 1 nguoi moi voi 2 quyen rieng: Dieu Khien va Cai Dat -
/// Giam Sat luon duoc cap ngam dinh khi da chia se (khong co checkbox rieng).
class _ShareVanDialog extends StatefulWidget {
  final Van van;
  const _ShareVanDialog({required this.van});

  @override
  State<_ShareVanDialog> createState() => _ShareVanDialogState();
}

class _ShareVanDialogState extends State<_ShareVanDialog> {
  final _identifierCtrl = TextEditingController();
  bool _canControl = true;
  bool _canConfigure = false;
  bool _sharing = false;
  List<Map<String, dynamic>>? _shares;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadShares();
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadShares() async {
    try {
      final shares = await context.read<VanListProvider>().listVanShares(widget.van.id);
      if (mounted) setState(() => _shares = shares);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Không tải được danh sách chia sẻ.');
    }
  }

  Future<void> _share() async {
    final id = _identifierCtrl.text.trim();
    if (id.isEmpty) {
      showSnack(context, 'Vui lòng nhập tên đăng nhập hoặc số điện thoại.', isError: true);
      return;
    }
    setState(() => _sharing = true);
    final provider = context.read<VanListProvider>();
    final ok = await provider.shareVan(widget.van.id, id, canControl: _canControl, canConfigure: _canConfigure);
    if (!mounted) return;
    setState(() => _sharing = false);
    if (ok) {
      _identifierCtrl.clear();
      showSnack(context, 'Đã chia sẻ van cho "$id".');
      _loadShares();
    } else {
      showSnack(context, provider.error ?? 'Không chia sẻ được.', isError: true);
    }
  }

  Future<void> _revoke(int userId, String username) async {
    final confirmed = await confirmDialog(context, title: 'Thu hồi chia sẻ?', message: 'Thu hồi quyền truy cập của "$username" với van này?');
    if (!confirmed || !mounted) return;
    final provider = context.read<VanListProvider>();
    final ok = await provider.revokeShare(widget.van.id, userId);
    if (!mounted) return;
    if (ok) {
      showSnack(context, 'Đã thu hồi.');
      _loadShares();
    } else {
      showSnack(context, provider.error ?? 'Không thực hiện được.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Chia Sẻ "${widget.van.displayName}"'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Đang chia sẻ với', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              if (_shares == null && _loadError == null)
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: CircularProgressIndicator()))
              else if (_loadError != null)
                Text(_loadError!, style: const TextStyle(color: Colors.red))
              else if (_shares!.isEmpty)
                Text('Chưa chia sẻ cho ai.', style: Theme.of(context).textTheme.bodySmall)
              else
                ..._shares!.map((s) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(s['username'] as String),
                      subtitle: Text(
                        '${s['can_control'] == 1 ? 'Điều khiển' : 'Chỉ giám sát'}${s['can_configure'] == 1 ? ' + Cài đặt' : ''}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, size: 18, color: Colors.red),
                        onPressed: () => _revoke(s['user_id'] as int, s['username'] as String),
                      ),
                    )),
              const Divider(height: 24),
              Text('Chia sẻ cho người mới', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              TextField(
                controller: _identifierCtrl,
                decoration: const InputDecoration(labelText: 'Tên đăng nhập hoặc số điện thoại', isDense: true),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _canControl,
                title: const Text('Cho phép Điều khiển (mở/đóng, chuyển vị trí)'),
                onChanged: (v) => setState(() => _canControl = v ?? true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _canConfigure,
                title: const Text('Cho phép Cài đặt (WiFi, hẹn giờ, cập nhật firmware...)'),
                onChanged: (v) => setState(() => _canConfigure = v ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
        FilledButton(
          onPressed: _sharing ? null : _share,
          child: _sharing
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Chia Sẻ'),
        ),
      ],
    );
  }
}
