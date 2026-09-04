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
  BluetoothDevice? _device;
  BluetoothCharacteristic? _cmdChar;
  BluetoothCharacteristic? _txChar;
  StreamSubscription? _notifySub;
  StreamSubscription? _connSub;

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
          _setState(BleConnState.disconnected);
        }
      });

      try {
        await device.requestMtu(247);
      } catch (_) {
        // Một số máy/OS từ chối request MTU lớn hơn - vẫn tiếp tục với MTU mặc định,
        // ble_manager.ino bên firmware tự chia nhỏ theo MTU thực tế đã thương lượng.
      }

      final services = await device.discoverServices();
      final svc = services.firstWhere(
        (s) => s.uuid.str.toLowerCase() == kBleServiceUuid,
        orElse: () => throw Exception('Không tìm thấy service BLE của van (sai firmware?)'),
      );
      _cmdChar = svc.characteristics.firstWhere((c) => c.uuid.str.toLowerCase() == kBleCmdCharUuid);
      _txChar = svc.characteristics.firstWhere((c) => c.uuid.str.toLowerCase() == kBleTxCharUuid);

      await _txChar!.setNotifyValue(true);
      _rxBuffer.clear();
      _notifySub = _txChar!.onValueReceived.listen(_onNotify);

      _device = device;
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

  Future<void> disconnect() async {
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
