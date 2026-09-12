import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../constants.dart';
import '../../services/api_service.dart';
import '../../state/dashboard_provider.dart';
import '../../widgets/common.dart';

/// Tab "Cập Nhật" - GOM CHUNG cap nhat firmware cho CA CH32 (qua UART) LAN
/// ESP32 (tu cap nhat chinh no) vao 1 noi duy nhat (truoc day chi co rieng
/// CH32, ten tab la "Nap CH32"). Moi loai chip tu dong kiem tra phien ban
/// moi nhat dang co trong "kho Firmware" (trang admin quan ly, xem
/// /api/firmware/latest) ngay khi mo tab, kem nut kiem tra lai thu cong -
/// khong con phai tu go URL tay hay quan ly file thu cong trong LittleFS
/// nhu truoc (da bo hoan toan, chuyen sang quan ly tap trung o trang admin).
class OtaTab extends StatefulWidget {
  const OtaTab({super.key});

  @override
  State<OtaTab> createState() => _OtaTabState();
}

class _OtaTabState extends State<OtaTab> {
  final _api = ApiService();

  Map<String, dynamic>? _latestCh32;
  Map<String, dynamic>? _latestEsp32;
  bool _checkingCh32 = false;
  bool _checkingEsp32 = false;
  String? _ch32Error;
  String? _esp32Error;

  @override
  void initState() {
    super.initState();
    // [NEW] Tu dong kiem tra phien ban ngay khi vao tab - yeu cau chinh cua
    // tinh nang nay, khong bat nguoi dung phai tu bam kiem tra moi lan.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVersion('ch32');
      _checkVersion('esp32');
    });
  }

  Future<void> _checkVersion(String target) async {
    setState(() {
      if (target == 'ch32') {
        _checkingCh32 = true;
        _ch32Error = null;
      } else {
        _checkingEsp32 = true;
        _esp32Error = null;
      }
    });
    final data = await _api.getLatestFirmware(target);
    if (!mounted) return;
    setState(() {
      if (target == 'ch32') {
        _latestCh32 = data;
        _checkingCh32 = false;
        if (data == null)
          _ch32Error = 'Chưa có firmware nào trong kho để so sánh.';
      } else {
        _latestEsp32 = data;
        _checkingEsp32 = false;
        if (data == null)
          _esp32Error = 'Chưa có firmware nào trong kho để so sánh.';
      }
    });
  }

  String _uptimeStr(int? sec) {
    if (sec == null) return '--';
    final d = sec ~/ 86400, h = (sec % 86400) ~/ 3600, m = (sec % 3600) ~/ 60;
    if (d > 0) return '${d}ng ${h}h ${m}m';
    return '${h}h ${m}m';
  }

  String _resetCauseLabel(String? cause) {
    switch (cause) {
      case 'power':
        return 'Mất/cấp lại nguồn';
      case 'pin':
        return 'Nút Reset/chân RST';
      case 'software':
        return 'Lệnh RESET từ app';
      case 'iwdg':
      case 'wwdg':
        return 'Watchdog (treo chương trình)';
      case 'lowpower':
        return 'Chế độ tiết kiệm điện';
      default:
        return 'Không rõ';
    }
  }

  /// true khi dang co 1 phien tai/truyen dang chay - dung de khoa nut, tranh
  /// bam lap trong luc dang tai qua mang dien thoai hoac truyen qua Bluetooth.
  bool _transferBusy = false;

  /// Nap firmware la thao tac "CAI DAT" (thay doi vinh vien thiet bi, rui ro
  /// cao hon dieu khien thong thuong) - chan neu van chia se khong cap quyen
  /// nay, giong van_settings_tab.dart/esp_settings_tab.dart. Dung chung cho
  /// ca 2 duong: URL truc tiep (MQTT that) VA tai+truyen qua Bluetooth.
  bool _checkCanConfigure(BuildContext context) {
    if (context.read<DashboardProvider>().van.canConfigure) return true;
    showSnack(
      context,
      'Bạn không có quyền Cài Đặt van này — không thể cập nhật firmware.',
      isError: true,
    );
    return false;
  }

  /// [FIX] Truoc day CHI gui lenh DOWNLOAD:/ESPOTA: (bat buoc chinh VAN phai
  /// co Internet de tu tai) - gio phan biet cac duong: dang MQTT that thi giu
  /// nguyen nhu cu; dang o che do Bluetooth (van da mat mang) thi DIEN THOAI
  /// tu tai file bang MANG RIENG cua no truoc, sau do CH32 truyen THANG qua
  /// BLE (xem DashboardProvider.sendFirmwareOverBle()), con ESP32 chuyen sang
  /// nap qua AP cuc bo (_flashEspViaAp() ben duoi - BLE qua cham cho ESP32,
  /// da tat, xem ble_manager.ino "[DISABLED - NGHIEN CUU]").
  Future<void> _startUpdate(
    BuildContext context, {
    required String target,
    required String url,
    required String label,
  }) async {
    if (!_checkCanConfigure(context)) return;
    final prov = context.read<DashboardProvider>();
    final isCh32 = target == 'ch32';
    final chipName = isCh32 ? 'MCU CH32X035' : 'ESP32-C3';
    final viaBle = prov.activeTransport == ActiveTransport.ble;

    if (!viaBle) {
      final ok = await confirmDialog(
        context,
        title: 'Cập nhật $chipName?',
        message:
            'Nạp firmware "$label" cho $chipName?\n\nKHÔNG tắt nguồn van trong lúc nạp!'
            '${isCh32 ? '' : ' ESP32 sẽ tự khởi động lại sau khi xong - app sẽ mất kết nối vài giây, đây là bình thường.'}',
      );
      if (!ok || !context.mounted) return;
      prov.publish('${isCh32 ? 'DOWNLOAD' : 'ESPOTA'}:$url');
      showSnack(context, 'Đã gửi lệnh cập nhật $chipName - theo dõi tiến trình bên dưới.');
      return;
    }

    if (isCh32) {
      final ok = await confirmDialog(
        context,
        title: 'Cập nhật $chipName?',
        message: 'Nạp firmware "$label" cho $chipName?\n\nKHÔNG tắt nguồn van trong lúc nạp!'
            '\n\nVan đang mất mạng - điện thoại sẽ tự tải file này qua mạng của điện thoại rồi truyền qua Bluetooth (có thể mất vài phút).',
      );
      if (!ok || !context.mounted) return;
      setState(() => _transferBusy = true);
      showSnack(context, 'Đang tải firmware qua mạng điện thoại...');
      final bytes = await _api.downloadFirmwareBytes(url);
      if (!context.mounted) return;
      if (bytes == null) {
        setState(() => _transferBusy = false);
        showSnack(context, 'Tải firmware thất bại - kiểm tra mạng của điện thoại.', isError: true);
        return;
      }
      await _sendBytesOverBle(context, target: target, bytes: bytes, label: label);
      return;
    }

    // ESP32 + dang o che do Bluetooth (van mat mang) - tai bytes qua mang
    // dien thoai TRUOC, roi chuyen sang nap qua AP cuc bo (xem _flashEspViaAp).
    final ok = await confirmDialog(
      context,
      title: 'Cập nhật $chipName?',
      message: 'Nạp firmware "$label" cho $chipName qua AP cục bộ (nhanh hơn Bluetooth nhiều)?'
          '\n\nĐiện thoại sẽ tự tải file này qua mạng riêng trước, sau đó bạn cần tự chuyển WiFi điện thoại sang AP của van để truyền thật nhanh.'
          '\n\nKHÔNG tắt nguồn van trong lúc nạp!',
    );
    if (!ok || !context.mounted) return;
    setState(() => _transferBusy = true);
    showSnack(context, 'Đang tải firmware qua mạng điện thoại...');
    final bytes = await _api.downloadFirmwareBytes(url);
    if (!context.mounted) return;
    if (bytes == null) {
      setState(() => _transferBusy = false);
      showSnack(context, 'Tải firmware thất bại - kiểm tra mạng của điện thoại.', isError: true);
      return;
    }
    setState(() => _transferBusy = false); // _flashEspViaAp tu bat lai busy
    await _flashEspViaAp(context, bytes: bytes, label: label);
  }

  /// [NEW] Nap ESP32 qua chinh AP cua van - thay the duong Bluetooth (da tat
  /// vi qua cham voi file ~1-2MB, xem ble_manager.ino "[DISABLED - NGHIEN
  /// CUU]": flutter_blue_plus cho MOI lan ghi (ca "khong can response") deu
  /// phai cho xac nhan platform channel qua 1 mutex TOAN CUC, chi phi CO DINH
  /// theo SO LAN GOI chu khong theo bang thong - khong cach nao tang toc du
  /// dung goi lon hon/uu tien ket noi cao hon, xem ble_service.dart). Luong:
  /// (1) gui AP_ON qua bat ky kenh dieu khien nao dang co (BLE hoac MQTT) de
  /// bat AP cua van, (2) huong dan nguoi dung TU CHUYEN WiFi dien thoai sang
  /// AP do (Android hien dai khong cho app tu dong chuyen WiFi nen khong co
  /// gi de "tu dong" that su ma khong them plugin/quyen rieng - de nguoi dung
  /// tu lam la cach don gian, dang tin cay nhat), (3) upload THANG file .bin
  /// (da co san trong RAM - tai truoc do qua mang dien thoai hoac nguoi dung
  /// tu chon) toi endpoint /upload_esp_ota cuc bo tren chinh ESP32 (khong qua
  /// backend/Internet nua o buoc nay).
  Future<void> _flashEspViaAp(
    BuildContext context, {
    required List<int> bytes,
    required String label,
  }) async {
    final prov = context.read<DashboardProvider>();
    final telemetry = prov.telemetry;
    prov.publish('AP_ON');
    if (!context.mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Chuyển sang WiFi của van'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Đã gửi lệnh bật điểm phát WiFi (AP) trên van. Trên điện thoại:'),
            const SizedBox(height: 10),
            const Text('1. Mở Cài Đặt WiFi của điện thoại'),
            // [FIX] Ten AP gio la devicePrefix cua CHINH van nay (= mqttPrefix,
            // khop ten quang ba BLE) thay vi 1 ten co dinh dung chung "VAN_C3_
            // OTA" cho MOI thiet bi - de dung khi co nhieu van gan nhau. AP gio
            // la mang MO (khong con mat khau) nen bo luon dong huong dan go
            // mat khau.
            SelectableText('2. Kết nối vào mạng "${prov.van.mqttPrefix}" (không cần mật khẩu)'),
            const Text('3. Quay lại đây và bấm "Đã Kết Nối - Nạp Ngay"'),
            const SizedBox(height: 10),
            Text(
              // [NEW] Yeu cau nguoi dung: khuyen tat 4G/mobile data trong luc
              // nay - AP cua van khong co Internet, mang dien thoai (4G) VAN
              // BAT thi Android co the dinh tuyen request sang 4G thay vi WiFi
              // cuc bo tuy thiet bi/phien ban Android, khien upload that bai
              // du da ket noi dung SSID. Khong the "dam bao" tu phia app ma
              // khong them plugin/quyen native rieng (ConnectivityManager.
              // bindProcessToNetwork) - neu can chac chan hon, tat han 4G la
              // cach don gian, dang tin cay nhat luc nay.
              'Lưu ý: NÊN tắt 4G/dữ liệu di động của điện thoại trong lúc nạp (AP của van không có Internet - nếu 4G vẫn bật, điện thoại có thể gửi nhầm qua 4G thay vì qua WiFi này tuỳ máy). Điện thoại đã tải sẵn firmware trong máy nên mất Internet tạm thời không sao.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Đã Kết Nối - Nạp Ngay')),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;

    setState(() => _transferBusy = true);
    telemetry.addLog('[AP OTA] Bắt đầu tải "$label" lên ESP32 qua AP cục bộ ($kApGatewayHost)...');
    // [FIX] Truoc day chi dung showSnack() cho ca lúc bắt đầu lẫn ket qua -
    // nguoi dung bao "không hiển thị tiến trình và thông báo thành công gì"
    // du firmware da nap xong that su (xac nhan qua log Serial). SnackBar de
    // bi BO LO neu nguoi dung dang thao tac man hinh khac (vd vua tu Cai Dat
    // WiFi quay lai) dung luc no tu bien mat (chi hien 3s). Doi sang dialog
    // CHAN MAN HINH khi dang tai + dialog ket qua rieng (khong tu dong tat) -
    // khong the "bo lo" duoc, VA luon ghi vao telemetry.addLog() (hien trong
    // tab Terminal) de co dau vet ngay ca khi dialog vi ly do gi khong hien
    // duoc (vd context loi thoi luc thao tac WiFi xong quay lai app).
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 16),
            Expanded(child: Text('Đang tải "$label" lên ESP32 qua WiFi cục bộ...\nKHÔNG rời khỏi màn hình này.')),
          ],
        ),
      ),
    );

    String? errorMsg;
    try {
      await _api.uploadEspOtaViaLocalAp(bytes);
    } catch (e) {
      errorMsg = e.toString();
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dong dialog "dang tai"
    setState(() => _transferBusy = false);
    if (!context.mounted) return;

    if (errorMsg == null) {
      telemetry.addLog('[AP OTA] Nạp "$label" thành công.');
    } else {
      telemetry.addLog('[AP OTA] Nạp "$label" thất bại: $errorMsg');
    }
    final successMsg = 'Đã nạp "$label" thành công! ESP32 đang khởi động lại (mất vài giây) - bạn có thể chuyển WiFi điện thoại về mạng bình thường.';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(errorMsg == null ? 'Thành công' : 'Thất bại'),
        content: Text(errorMsg ?? successMsg),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  /// [NEW] Cho chon 1 file .bin tren may roi nap ESP32 qua AP cua van (xem
  /// _flashEspViaAp()) - dung khi nguoi dung da tai san file tu truoc hoac
  /// muon nap 1 ban rieng/thu nghiem chua co trong kho.
  Future<void> _pickAndFlashEspViaAp(BuildContext context) async {
    if (!_checkCanConfigure(context)) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bin'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final file = result.files.single;
    if (!context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Nạp ESP32-C3 qua AP?',
      message: 'Nạp file "${file.name}" (${(file.size / 1024).toStringAsFixed(1)} KB) cho ESP32-C3 qua AP cục bộ của van?\n\nKHÔNG tắt nguồn van trong lúc nạp!',
    );
    if (!ok || !context.mounted) return;
    await _flashEspViaAp(context, bytes: file.bytes!, label: file.name);
  }

  /// [NEW] Cho chon 1 file .bin BAT KY co san trong may (khong nhat thiet
  /// phai la ban trong kho firmware) roi truyen qua Bluetooth - dung khi
  /// nguoi dung da tai san file tu truoc (khong can mang luc nay) hoac muon
  /// nap 1 ban firmware rieng/thu nghiem chua co trong kho.
  Future<void> _pickAndSendOverBle(BuildContext context, String target) async {
    if (!_checkCanConfigure(context)) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bin'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null) return;
    final file = result.files.single;
    if (!context.mounted) return;
    final chipName = target == 'ch32' ? 'MCU CH32X035' : 'ESP32-C3';
    final ok = await confirmDialog(
      context,
      title: 'Nạp $chipName qua Bluetooth?',
      message: 'Truyền file "${file.name}" (${(file.size / 1024).toStringAsFixed(1)} KB) qua Bluetooth và nạp cho $chipName?\n\nKHÔNG tắt nguồn van trong lúc nạp!',
    );
    if (!ok || !context.mounted) return;
    await _sendBytesOverBle(context, target: target, bytes: file.bytes!, label: file.name);
  }

  Future<void> _sendBytesOverBle(
    BuildContext context, {
    required String target,
    required List<int> bytes,
    required String label,
  }) async {
    setState(() => _transferBusy = true);
    final ok = await context.read<DashboardProvider>().sendFirmwareOverBle(target: target, bytes: bytes);
    if (!mounted) return;
    setState(() => _transferBusy = false);
    if (!context.mounted) return;
    showSnack(
      context,
      ok ? 'Đã nạp "$label" thành công qua Bluetooth!' : 'Nạp "$label" qua Bluetooth thất bại - xem "Tiến Trình Cập Nhật" bên dưới.',
      isError: !ok,
    );
  }

  /// 1 the "Cap Nhat Phan Mem" cho 1 loai chip - hien version dang chay,
  /// version moi nhat trong kho (neu co), va nut cap nhat khi phat hien
  /// khac nhau. Luu y: so sanh CHUOI NHAN admin tu dat khi tai firmware len
  /// voi chuoi version THAT van bao ve qua ##MCU##/##ESPINFO## - chi chinh
  /// xac neu nhan khop dung dinh dang (vd "v1.3.0-C3"), khong phai so sanh
  /// semver that su.
  Widget _buildUpdateCard(
    BuildContext context, {
    required String target,
    required String chipName,
    required IconData icon,
    required String? currentVersion,
    required Map<String, dynamic>? latest,
    required bool checking,
    required String? error,
    required bool canConfigure,
    required bool viaBle,
  }) {
    final latestLabel =
        latest?['label']?.toString() ??
        latest?['original_filename']?.toString();
    final hasUpdate =
        latest != null &&
        currentVersion != null &&
        latestLabel != currentVersion;
    return SectionCard(
      title: chipName,
      icon: icon,
      trailing: IconButton(
        icon: checking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh),
        tooltip: 'Kiểm tra phiên bản mới nhất',
        onPressed: checking ? null : () => _checkVersion(target),
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Đang chạy',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Text(
              currentVersion ?? '--',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (checking)
          Text(
            'Đang kiểm tra phiên bản mới nhất...',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Colors.grey),
          )
        else if (latest == null)
          Text(
            error ?? 'Chưa kiểm tra.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Colors.grey),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Mới nhất trong kho',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Text(
                latestLabel ?? '--',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasUpdate && !canConfigure)
            Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Có bản mới nhưng bạn không có quyền Cài Đặt để cập nhật — liên hệ chủ van.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            )
          else if (hasUpdate)
            FilledButton.icon(
              icon: !viaBle
                  ? const Icon(Icons.system_update_alt)
                  : (target == 'ch32' ? const Icon(Icons.bluetooth_connected_rounded) : const Icon(Icons.wifi_tethering_rounded)),
              label: Text(
                !viaBle
                    ? 'Cập Nhật Lên $latestLabel'
                    : (target == 'ch32' ? 'Tải & Nạp Qua Bluetooth: $latestLabel' : 'Tải & Nạp Qua AP: $latestLabel'),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: _transferBusy
                  ? null
                  : () => _startUpdate(
                      context,
                      target: target,
                      url: latest['url'] as String,
                      label: latestLabel ?? '',
                    ),
            )
          else
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Đã là bản mới nhất',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
        ],
        // [NEW] Chi hien khi dang o che do Bluetooth (van mat mang that su) -
        // cho phep chon 1 file .bin BAT KY tren may (khong bat buoc phai la
        // ban trong kho firmware phia tren). CH32 truyen thang qua Bluetooth
        // (khong bi anh huong boi han che toc do - chi truyen tu ESP32 sang
        // CH32 qua UART noi bo sau khi da nhan du qua BLE); ESP32 chuyen sang
        // nap qua AP cuc bo (xem _flashEspViaAp() - BLE qua cham cho ESP32).
        if (viaBle && canConfigure) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text('Chọn File Khác Trên Máy...'),
            onPressed: _transferBusy
                ? null
                : () => target == 'ch32'
                    ? _pickAndSendOverBle(context, target)
                    : _pickAndFlashEspViaAp(context),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DashboardProvider>();
    final t = prov.telemetry;
    final canConfigure = prov.van.canConfigure;
    final viaBle = prov.activeTransport == ActiveTransport.ble;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // [FIX] Truoc day khoa CA TAB neu khong phai MQTT that (kê cả BLE) -
        // gio CH32/ESP32 deu cap nhat duoc qua Bluetooth (dien thoai tu tai +
        // truyen qua BLE, xem _startUpdate()), nen CHI khoa khi THAT SU
        // khong co ket noi nao (ActiveTransport.none), khong con khoa o che
        // do Bluetooth nua.
        OfflineLockNotice(
          locked: prov.activeTransport == ActiveTransport.none,
          message: 'Cập nhật firmware cần có kết nối tới van (Internet hoặc Bluetooth) - hiện không có kết nối nào, tính năng này tạm khoá.',
          child: Column(
            children: [
              _buildUpdateCard(
                context,
                target: 'ch32',
                chipName: 'MCU CH32X035',
                icon: Icons.memory,
                currentVersion: t.mcuFw,
                latest: _latestCh32,
                checking: _checkingCh32,
                error: _ch32Error,
                canConfigure: canConfigure,
                viaBle: viaBle,
              ),
              _buildUpdateCard(
                context,
                target: 'esp32',
                chipName: 'ESP32-C3 (WiFi/Bluetooth)',
                icon: Icons.settings_input_antenna,
                currentVersion: t.espFw,
                latest: _latestEsp32,
                checking: _checkingEsp32,
                error: _esp32Error,
                canConfigure: canConfigure,
                viaBle: viaBle,
              ),
              SectionCard(
                title: 'Tiến Trình Cập Nhật',
                icon: Icons.timeline,
                trailing: StatusPill(
                  text: t.otaInProgress
                      ? 'ĐANG NẠP ${t.otaPercent ?? 0}%'
                      : (t.otaOk == true
                            ? 'THÀNH CÔNG'
                            : (t.otaOk == false ? 'THẤT BẠI' : 'SẴN SÀNG')),
                  color: t.otaInProgress
                      ? Colors.orange
                      : (t.otaOk == true
                            ? Colors.green
                            : (t.otaOk == false
                                  ? Colors.red
                                  : Colors.blueGrey)),
                ),
                children: [
                  LinearProgressIndicator(value: (t.otaPercent ?? 0) / 100),
                  const SizedBox(height: 8),
                  Text(
                    t.otaStatusText,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              // [FIX] Chan doan phan cung CH32 - thong tin THAM KHAO, khong phai
              // thao tac chinh cua tab nay (da chuyen "Cap Nhat Phan Mem" thanh
              // trong tam, day xuong duoi cung).
              SectionCard(
                title: 'Thông Số Vận Hành CH32X035',
                icon: Icons.tune,
                children: [
                  statGrid([
                    StatBox(
                      label: 'RAM Khả Dụng',
                      value: '${t.heap ?? '--'} B',
                      sub: 'Min Free: ${t.heapMin ?? '--'} B',
                    ),
                    StatBox(
                      label: 'Mã Van',
                      value: t.mcuVan != null ? '#${t.mcuVan}' : '--',
                      sub: t.mcuId != null ? 'Chip ID: ${t.mcuId}' : null,
                    ),
                    StatBox(
                      label: 'Ngoại Vi',
                      value:
                          'RTC: ${(t.mcuRtc ?? '--').toUpperCase()} • EEPROM: ${(t.mcuEe ?? '--').toUpperCase()}',
                    ),
                    StatBox(
                      label: 'Số Lần Reset',
                      value: t.mcuResetCount != null
                          ? '${t.mcuResetCount}'
                          : '--',
                      sub: 'Gần nhất: ${_resetCauseLabel(t.mcuResetCause)}',
                    ),
                    StatBox(
                      label: 'Thời Gian Hoạt Động',
                      value: _uptimeStr(t.mcuUptimeSec),
                      sub: 'Kể từ lần khởi động gần nhất',
                    ),
                  ]),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
