import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../constants.dart';

enum BleConnState { disconnected, connecting, connected }

/// Bọc FlutterBluePlus - kết nối 1 van qua BLE làm kênh CỤC BỘ (không cần
/// Internet): ghép nối, cấu hình WiFi, điều khiển/giám sát dự phòng khi mất
/// MQTT. Tái dùng đúng bộ lệnh text đã có (PING, GOTO:n, WIFI_SCAN, ...) -
/// xem ble_manager.ino bên firmware. Mỗi dòng nhận qua Notify được ghép lại
/// và tách theo '\n' rồi phát ra qua [lines] - đưa thẳng vào
/// TelemetryParser.parse() y hệt payload MQTT (không cần parser riêng).
class BleService {
  // [NEW] Dem TOAN CUC (khong rieng theo instance) so ket noi GATT dang mo -
  // man hinh "Quan Ly Van" dung 1 BleService RIENG chi de quet tin hieu (RSSI)
  // cho ca danh sach van, doc lap voi BleService cua dashboard dang giu ket
  // noi dieu khien/giam sat qua Bluetooth. Tren nhieu chipset BLE thuc te,
  // QUET (scan) trong luc dang co 1 KET NOI GATT khac mo se lam gian doan/rot
  // ket noi do (tranh chap song radio) - phai biet co ket noi nao dang song o
  // BAT KY BleService nao truoc khi cho phep quet, khong the biet duoc chi tu
  // rieng instance dang quet.
  static int _activeGattConnections = 0;
  static bool get anyGattConnectionActive => _activeGattConnections > 0;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _cmdChar;
  BluetoothCharacteristic? _txChar;
  BluetoothCharacteristic? _fileChar;
  StreamSubscription? _notifySub;
  StreamSubscription? _connSub;
  bool _countedActive = false;

  void _markActive() {
    if (_countedActive) return;
    _countedActive = true;
    BleService._activeGattConnections++;
  }

  void _markInactive() {
    if (!_countedActive) return;
    _countedActive = false;
    BleService._activeGattConnections--;
  }

  final _linesController = StreamController<String>.broadcast();
  final _stateController = StreamController<BleConnState>.broadcast();
  final List<int> _rxBuffer = [];

  Stream<String> get lines => _linesController.stream;
  Stream<BleConnState> get connectionState => _stateController.stream;

  BleConnState _state = BleConnState.disconnected;
  BleConnState get state => _state;
  String? get connectedDeviceId => _device?.remoteId.str;

  void _setState(BleConnState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  /// Quét các van gần đây (tên quảng bá bắt đầu bằng "van_"). Tự động dừng
  /// sau [timeout] (FlutterBluePlus tự stopScan khi hết giờ).
  Stream<ScanResult> scan({Duration timeout = const Duration(seconds: 8)}) {
    FlutterBluePlus.startScan(timeout: timeout);
    return FlutterBluePlus.scanResults
        .expand((results) => results)
        .where((r) => _advName(r).toLowerCase().startsWith(kBleNamePrefix));
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  String _advName(ScanResult r) {
    final n = r.advertisementData.advName;
    if (n.isNotEmpty) return n;
    return r.device.platformName;
  }

  /// Kết nối bằng BluetoothDevice lấy từ kết quả scan (màn hình ghép nối).
  Future<bool> connectDevice(BluetoothDevice device) => _connect(device);

  /// Kết nối lại bằng remoteId đã lưu trước đó - KHÔNG cần quét lại. Dùng cho
  /// fallback tự động khi mất MQTT (xem DashboardProvider.tryBleFallback()).
  Future<bool> connectById(String remoteId) => _connect(BluetoothDevice.fromId(remoteId));

  Future<bool> _connect(BluetoothDevice device) async {
    await disconnect();
    _setState(BleConnState.connecting);
    try {
      await device.connect(timeout: const Duration(seconds: 10), autoConnect: false);
      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _markInactive();
          _setState(BleConnState.disconnected);
        }
      });

      try {
        await device.requestMtu(247);
      } catch (_) {
        // Một số máy/OS từ chối request MTU lớn hơn - vẫn tiếp tục với MTU mặc định,
        // ble_manager.ino bên firmware tự chia nhỏ theo MTU thực tế đã thương lượng.
      }

      // [FIX TOC DO] Android mac dinh dung connection interval "balanced"
      // (~30-50ms/lan trao doi) tru khi ung dung chu dong xin uu tien cao -
      // moi lan ghi CO RESPONSE (vd tung goi firmware trong sendFirmwareOverBle())
      // phai cho tron 1 vong trao doi nay, nen truyen file lon qua BLE cam
      // giac "treo" vi cham (~30-50ms/goi 200 byte = vai phut cho 1 file
      // ~1.5MB). Xin CONNECTION_PRIORITY_HIGH giam interval xuong con
      // ~11-15ms, tang thong luong 2-4 lan. Khong co tac dung tren iOS (API
      // rieng cua Android) nhung du an nay chi build Android - bo qua loi neu
      // khong ho tro.
      try {
        await device.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high);
      } catch (_) {}

      final services = await device.discoverServices();
      final svc = services.firstWhere(
        (s) => s.uuid.str.toLowerCase() == kBleServiceUuid,
        orElse: () => throw Exception('Không tìm thấy service BLE của van (sai firmware?)'),
      );
      _cmdChar = svc.characteristics.firstWhere((c) => c.uuid.str.toLowerCase() == kBleCmdCharUuid);
      _txChar = svc.characteristics.firstWhere((c) => c.uuid.str.toLowerCase() == kBleTxCharUuid);
      _fileChar = svc.characteristics.firstWhere((c) => c.uuid.str.toLowerCase() == kBleFileCharUuid);

      await _txChar!.setNotifyValue(true);
      _rxBuffer.clear();
      _notifySub = _txChar!.onValueReceived.listen(_onNotify);

      _device = device;
      _markActive();
      _setState(BleConnState.connected);
      return true;
    } catch (_) {
      _setState(BleConnState.disconnected);
      await disconnect();
      return false;
    }
  }

  // Ghép các gói Notify (đã bị ble_manager.ino chia nhỏ theo MTU) và tách
  // theo '\n' - port trực tiếp cùng pattern line-buffering đã dùng trong
  // uart_bridge.ino cho UART1<->CH32X035, không phát minh logic mới.
  void _onNotify(List<int> chunk) {
    _rxBuffer.addAll(chunk);
    while (true) {
      final nlIdx = _rxBuffer.indexOf(10); // '\n'
      if (nlIdx < 0) break;
      final lineBytes = _rxBuffer.sublist(0, nlIdx);
      _rxBuffer.removeRange(0, nlIdx + 1);
      if (lineBytes.isEmpty) continue;
      final line = utf8.decode(lineBytes, allowMalformed: true);
      if (!_linesController.isClosed) _linesController.add(line);
    }
  }

  /// Xác thực bằng mã PIN dùng chung - BẮT BUỘC là lệnh đầu tiên sau khi
  /// connect (ble_manager.ino từ chối mọi lệnh khác cho tới khi AUTH đúng).
  Future<bool> authenticate({String pin = kBleAuthPin}) async {
    if (_cmdChar == null) return false;
    final completer = Completer<bool>();
    late StreamSubscription sub;
    sub = lines.listen((line) {
      final t = line.trim();
      if (t == 'OK AUTH' && !completer.isCompleted) {
        completer.complete(true);
      } else if (t == 'ERR AUTH' && !completer.isCompleted) {
        completer.complete(false);
      }
    });
    try {
      await writeCommand('AUTH:$pin');
      return await completer.future.timeout(const Duration(seconds: 3), onTimeout: () => false);
    } finally {
      await sub.cancel();
    }
  }

  /// Gửi 1 lệnh text - tương đương DashboardProvider.publish() cho MQTT. Mỗi
  /// lệnh nằm gọn trong 1 lần ghi GATT (ble_manager.ino xử lý ngay, không cần
  /// khung/kết thúc dòng ở chiều ghi).
  Future<void> writeCommand(String cmd) async {
    final chr = _cmdChar;
    if (chr == null) return;
    try {
      await chr.write(utf8.encode(cmd), withoutResponse: true);
    } catch (_) {}
  }

  /// [NEW] Truyen 1 file firmware NHI PHAN cho ESP32 qua Bluetooth - dien
  /// thoai da TU TAI file nay qua mang rieng cua no (khong qua van, xem
  /// ApiService.getLatestFirmware()/file nguoi dung tu chon) truoc khi goi
  /// ham nay. [target] la "ch32" (ESP32 se nap lai cho CH32 qua UART sau khi
  /// nhan du - tai dung ch32.flashFirmware() da co san) hoac "esp32" (ESP32
  /// ghi thang vao vung OTA cua chinh no). [onStatus] duoc goi voi cac dong
  /// text nhan duoc tu ESP32 trong luc cho (bleflash_ready/progress/err...) -
  /// KHONG can tu parse, DashboardProvider._onBleLine da tu dua vao
  /// TelemetryParser roi cap nhat otaPercent/otaInProgress/otaOk nhu binh
  /// thuong (xem telemetry_parser.dart) - tham so nay chi de UI biet request
  /// dang o buoc nao neu can. Tra ve true neu nap thanh cong (ota_ok/
  /// esp_ota_ok), false neu that bai/timeout/huy.
  Future<bool> sendFirmwareOverBle({
    required String target,
    required List<int> bytes,
    void Function(String rawLine)? onStatus,
    Duration chunkTimeout = const Duration(seconds: 10),
    Duration finishTimeout = const Duration(seconds: 60),
  }) async {
    if (_cmdChar == null || _fileChar == null) return false;

    final linesSub = lines.listen((l) => onStatus?.call(l));
    try {
      // Buoc 1: bao truoc target+kich thuoc, cho ESP32 xac nhan san sang.
      final readyCompleter = Completer<bool>();
      late StreamSubscription readySub;
      readySub = lines.listen((line) {
        if (line.contains('bleflash_ready') && !readyCompleter.isCompleted) {
          readyCompleter.complete(true);
        } else if ((line.contains('bleflash_busy') || line.contains('bleflash_err')) && !readyCompleter.isCompleted) {
          readyCompleter.complete(false);
        }
      });
      await writeCommand('BLEFLASH:$target:${bytes.length}');
      final ready = await readyCompleter.future.timeout(const Duration(seconds: 5), onTimeout: () => false);
      await readySub.cancel();
      if (!ready) return false;

      // Buoc 2: chia nho va ghi tuan tu - CHO tung goi ghi xong (write co
      // response) truoc khi gui goi tiep theo, dam bao thu tu + khong lam
      // nghen ngan xep BLE cua ESP32 (giong cach bleNotifyLine() ben firmware
      // tu gioi han toc do chieu nguoc lai).
      // [FIX TOC DO - QUAN TRONG] flutter_blue_plus dung 1 MUTEX TOAN CUC va
      // CHO platform channel + callback "onCharacteristicWritten" xac nhan
      // truoc khi tra ve cho MOI lan goi write() - CA khi withoutResponse:true
      // (xem bluetooth_characteristic.dart: "wait until the packet has been
      // sent, to prevent iOS & Android dropping packets"). Nghia la chi phi
      // co dinh (~vai chuc ms) tinh THEO SO LAN GOI write(), khong phai theo
      // so byte - giam connection interval (requestConnectionPriority o tren)
      // khong giai quyet duoc phan chi phi nay. Cach duy nhat giam thoi gian
      // tong the la GIAM SO LAN GOI: dung allowLongWrite:true (chi hoat dong
      // voi write CO response - dung sac voi thiet ke hien tai) de goi 1 lan
      // Dart duoc toi da 512 byte (co che "Queued Write" chuan BLE, khong phu
      // thuoc MTU da thuong luong) thay vi bi gioi han theo MTU-3 (~244 byte)
      // - giam gan 1 nua so lan goi cho cung 1 dung luong file.
      const int chunkSize = 512;
      for (int off = 0; off < bytes.length; off += chunkSize) {
        final end = (off + chunkSize < bytes.length) ? off + chunkSize : bytes.length;
        try {
          await _fileChar!
              .write(bytes.sublist(off, end), withoutResponse: false, allowLongWrite: true)
              .timeout(chunkTimeout);
        } catch (_) {
          return false; // mat ket noi hoac ghi that bai giua chung - huy, khong gui BLEFLASH_END
        }
      }

      // Buoc 3: bao ket thuc, cho ket qua nap THAT SU (ota_ok/ota_err hoac
      // esp_ota_ok/esp_ota_err) - co the mat toi vai chuc giay cho CH32 IAP.
      final doneCompleter = Completer<bool>();
      late StreamSubscription doneSub;
      doneSub = lines.listen((line) {
        if (doneCompleter.isCompleted) return;
        if (line.contains('ota_ok')) {
          doneCompleter.complete(true);
        } else if (line.contains('ota_err') || line.contains('bleflash_err')) {
          doneCompleter.complete(false);
        }
      });
      await writeCommand('BLEFLASH_END');
      final ok = await doneCompleter.future.timeout(finishTimeout, onTimeout: () => false);
      await doneSub.cancel();
      return ok;
    } finally {
      await linesSub.cancel();
    }
  }

  /// Huy 1 phien truyen dang do dang (vd nguoi dung tu bam Huy) - xem
  /// BLEFLASH_ABORT trong ble_manager.ino.
  Future<void> abortFirmwareTransfer() => writeCommand('BLEFLASH_ABORT');

  Future<void> disconnect() async {
    _markInactive();
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel();
    _connSub = null;
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    _cmdChar = null;
    _txChar = null;
  }

  void dispose() {
    disconnect();
    _linesController.close();
    _stateController.close();
  }
}
