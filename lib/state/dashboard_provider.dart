import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/telemetry_state.dart';
import '../models/van.dart';
import '../services/ble_service.dart';
import '../services/mqtt_service.dart';
import '../services/prefs_service.dart';
import '../services/telemetry_parser.dart';

enum MqttConnState { disconnected, connecting, connected, error }

/// Kenh dang thuc su dung de gui/nhan lenh cho van nay - MQTT (qua Internet)
/// la uu tien mac dinh, BLE (cuc bo, khong can Internet) chi la du phong khi
/// MQTT mat (xem tryBleFallback()). "none" = khong co kenh nao san sang.
enum ActiveTransport { mqtt, ble, none }

/// Boc MqttService + TelemetryState cho 1 van dang mo dashboard. Tuong duong
/// phan connectMqtt()/publishMqttCmd()/manualRefreshMqtt() trong web client.
class DashboardProvider extends ChangeNotifier {
  final Van van;
  final PrefsService prefsService;
  final MqttService _mqtt = MqttService();
  late final TelemetryState telemetry;
  late final TelemetryParser _parser;

  // Thong bao roi rac cho cac buoc CHUYEN DOI transport (mat Internet -> BLE,
  // BLE -> khoi phuc Internet, khong tim thay van qua Bluetooth...) - can
  // BuildContext (ScaffoldMessenger) de hien SnackBar ma DashboardProvider
  // (ChangeNotifier thuan, khong phai Widget) khong co san. Phat qua Stream,
  // DashboardScreen subscribe va tu hien SnackBar (xem initState() o do).
  final _events = StreamController<String>.broadcast();
  Stream<String> get events => _events.stream;
  void _notify(String message) {
    if (!_events.isClosed) _events.add(message);
  }

  DashboardProvider({required this.van, required this.prefsService}) {
    telemetry = TelemetryState();
    _parser = TelemetryParser(telemetry);
    // QUAN TRONG: TelemetryState la ChangeNotifier RIENG voi DashboardProvider.
    // Cac widget chi context.watch<DashboardProvider>() (khong watch truc
    // tiep TelemetryState), nen neu khong forward notifyListeners() cua
    // telemetry len day, du du lieu (telemetry.pos, .monTime, v.v.) van
    // duoc cap nhat dung sau moi tin nhan MQTT, UI se KHONG bao gio ve lai -
    // chi tinh co doi tab (Flutter build lai subtree luc do) moi thay du
    // lieu moi. Da xac nhan bang test that: PING nhan duoc (thay trong
    // Terminal) nhung man Giam Sat dung yen tai cho. Forward thang o day.
    telemetry.addListener(notifyListeners);
  }

  @override
  void dispose() {
    telemetry.removeListener(notifyListeners);
    _mqtt.disconnect();
    _noDataWatchdog?.cancel();
    _bleLinesSub?.cancel();
    _bleConnSub?.cancel();
    _ble?.dispose();
    _events.close();
    super.dispose();
  }

  MqttConnState connState = MqttConnState.disconnected;
  String? connError;
  String host = '103.143.207.89';
  int port = 9001;
  String mqttUser = 'thangpro1998';
  String mqttPass = 'thang123';

  // --- BLE (kenh du phong cuc bo - xem tryBleFallback()) ---
  BleService? _ble;
  StreamSubscription? _bleLinesSub;
  StreamSubscription? _bleConnSub;
  Timer? _noDataWatchdog;

  // MQTT "connected" chi nghia la da ket noi toi BROKER tren mang - van
  // (thiet bi thuc) co dang lang nghe tren do khong lai la chuyen khac (vd
  // van chua tung duoc cau hinh WiFi, hoac WiFi nha van dang mat trong khi
  // dien thoai van co Internet). _mqttProven chi thanh true khi THAT SU nhan
  // duoc >=1 message tu van qua MQTT - dung de uu tien dung BLE (da xac nhan
  // song) thay vi MQTT (chi xac nhan toi broker, chua chac toi duoc van).
  bool _mqttProven = false;

  ActiveTransport get activeTransport {
    if (connState == MqttConnState.connected && _mqttProven)
      return ActiveTransport.mqtt;
    if (_ble != null && _ble!.state == BleConnState.connected)
      return ActiveTransport.ble;
    if (connState == MqttConnState.connected) return ActiveTransport.mqtt;
    return ActiveTransport.none;
  }

  // Cac tinh nang can Internet THAT SU (upload/tai file .bin, nap OTA CH32 tu
  // xa) chi hoat dong qua MQTT - ble_manager.ino KHONG forward cac lenh
  // FILES?/FLASH:/DELETE:/DOWNLOAD: (xem dispatchDeviceCommand() ben firmware,
  // cac lenh nay chi duoc xu ly rieng trong mqttCallback(), khong qua duong
  // dung chung voi BLE). Dung o day de UI khoa nhom tinh nang nay lai khi
  // dang o che do cuc bo (BLE/mat ket noi) - tranh nguoi dung bam ma khong co
  // gi xay ra, khong ro tai sao.
  bool get isOfflineOnly => activeTransport != ActiveTransport.mqtt;

  // [NEW] "Da mat ket noi tu truoc" ma UI chua biet: activeTransport ==
  // mqtt CHI co nghia da ket noi toi BROKER, khong dam bao van thuc su con
  // song (xem comment _mqttProven o tren) - neu MQTT connect() nhung
  // KHONG BAO GIO nhan duoc phan hoi thuc tu van (vd van mat WiFi, khong
  // co BLE du phong de rot xuong), activeTransport se bao "mqtt" MAI MAI
  // (dong fallback cuoi cua getter tren) dù lenh gui di se roi vao khoang
  // khong. Dung gia tri nay CHAN lenh dieu khien (GOTO/NEXT) truoc khi
  // gui, thay vi gui roi bao "thanh cong" gia nhu truoc day.
  bool get isConnectionStale {
    if (activeTransport == ActiveTransport.ble) return false;
    if (activeTransport == ActiveTransport.none) return true;
    if (!_mqttProven) return true;
    final last = telemetry.lastUpdate;
    if (last == null) return true;
    return DateTime.now().difference(last) > const Duration(seconds: 60);
  }

  String get topicCmd => '${van.mqttPrefix}/cmd';

  Future<void> loadConfigAndConnect() async {
    final cfg = await prefsService.getMqttConfig();
    host = cfg['host'] as String;
    port = cfg['port'] as int;
    mqttUser = cfg['user'] as String;
    mqttPass = cfg['pass'] as String;
    await connect();
  }

  Future<void> saveConfig({
    required String host,
    required int port,
    required String user,
    required String pass,
  }) async {
    this.host = host;
    this.port = port;
    mqttUser = user;
    mqttPass = pass;
    await prefsService.setMqttConfig(
      host: host,
      port: port,
      user: user,
      pass: pass,
    );
  }

  Future<void> connect() async {
    connState = MqttConnState.connecting;
    connError = null;
    notifyListeners();

    final ok = await _mqtt.connect(
      host: host,
      port: port,
      username: mqttUser,
      password: mqttPass,
      topicPrefix: van.mqttPrefix,
      onMessage: _onMessage,
      onConnected: _onConnected,
      onDisconnected: _onDisconnected,
    );

    if (!ok) {
      connState = MqttConnState.error;
      connError = 'Không kết nối được tới MQTT Broker ($host:$port).';
      telemetry.mqttConnected = false;
      notifyListeners();
      tryBleFallback();
    }
  }

  void _onConnected() {
    connState = MqttConnState.connected;
    telemetry.mqttConnected = true;
    _mqttProven = false;
    telemetry.addLog(
      '[MQTT] Kết nối thành công tới $host:$port (broker) - chờ van phản hồi...',
    );
    notifyListeners();

    // [FIX] "Connected" ở đây chỉ là kết nối tới BROKER - nếu van CHƯA TỪNG
    // có WiFi (hoặc WiFi nhà van đang mất trong khi điện thoại vẫn có mạng),
    // broker sẽ không bao giờ nhận được gì từ van, và app sẽ đứng yên ở
    // "ONLINE" giả trong khi thực ra không điều khiển/giám sát được gì. Nếu
    // sau 8s vẫn chưa nhận được BẤT KỲ message nào từ van, coi như MQTT
    // không dùng được cho van này lúc này - chủ động thử BLE cục bộ.
    _noDataWatchdog?.cancel();
    _noDataWatchdog = Timer(const Duration(seconds: 8), () {
      if (!_mqttProven) {
        telemetry.addLog(
          '[MQTT] Không nhận được phản hồi từ van (van có thể chưa có WiFi) - thử Bluetooth...',
        );
        tryBleFallback();
      }
    });

    // Giong doan mqttClient.on('connect', ...) trong web: tu dong lam moi
    // toan bo trang thai ngay sau khi ket noi.
    Future.delayed(const Duration(milliseconds: 400), () {
      publish('PING');
      Future.delayed(const Duration(milliseconds: 200), () => publish('POS?'));
      Future.delayed(
        const Duration(milliseconds: 400),
        () => publish('FILES?'),
      );
      Future.delayed(
        const Duration(milliseconds: 600),
        () => publish('SETTINGS?'),
      );
      Future.delayed(
        const Duration(milliseconds: 800),
        () => publish('ESP_INFO?'),
      );
    });
  }

  void _onDisconnected() {
    connState = MqttConnState.disconnected;
    telemetry.mqttConnected = false;
    _mqttProven = false;
    _noDataWatchdog?.cancel();
    telemetry.addLog('[MQTT] Mất kết nối.');
    notifyListeners();
    tryBleFallback();
  }

  void _onMessage(String topic, String payload) {
    telemetry.lastUpdate = DateTime.now();
    telemetry.addLog('[MQTT RX] [$topic] $payload');

    // [FIX] App tu subscribe "${van.mqttPrefix}/#" - bao gom CA topicCmd
    // (chinh no vua publish() len). Broker MQTT chuan se ECHO LAI cho chinh
    // client da subscribe trung topic, KE CA khi van khong he online/khong
    // phan hoi gi ca. Neu dung "nhan duoc bat ky message nao" lam bang chung
    // MQTT song, _mqttProven se luon = true ngay sau lenh PING dau tien BAT
    // KE van co that su ket noi khong - day chinh la ly do "mac dinh luon
    // online" da xac nhan qua test that. CHI nhan la "bang chung" khi topic
    // KHONG PHAI topicCmd - vi van (khong phai app) chi publish len
    // topicStatus/topicTelemetry/topicLog, khong bao gio publish len topicCmd.
    if (!_mqttProven && topic != topicCmd) {
      // Tin nhan MQTT THAT SU dau tien tu van (khong chi ket noi broker) -
      // xac nhan duong nay dung, khong can BLE du phong nua (giam tranh chap
      // song radio WiFi/BLE dung chung 1 anten tren ESP32-C3).
      _mqttProven = true;
      _noDataWatchdog?.cancel();
      if (_ble != null && _ble!.state != BleConnState.disconnected) {
        telemetry.addLog(
          '[BLE] MQTT đã có dữ liệu thật từ van - ngắt kết nối Bluetooth dự phòng.',
        );
        _bleLinesSub?.cancel();
        _bleConnSub?.cancel();
        _ble!.disconnect();
        _notify('🟢 Đã khôi phục Internet - chuyển về chế độ Online (MQTT).');
      }
    }

    _parser.parse(payload);
  }

  void _onBleLine(String line) {
    telemetry.lastUpdate = DateTime.now();
    telemetry.addLog('[BLE RX] $line');
    _parser.parse(line);
  }

  /// Kênh dự phòng cục bộ khi mất MQTT/Internet: nếu van này đã từng được
  /// ghép nối qua BLE (xem BlePairScreen), thử kết nối lại bằng deviceId đã
  /// lưu - KHÔNG cần quét lại. Đường UART CH32<->ESP32 hoạt động độc lập với
  /// WiFi nên PING/GOTO/xem vị trí vẫn dùng được dù mất hoàn toàn Internet.
  Future<void> tryBleFallback() async {
    if (_ble != null &&
        (_ble!.state == BleConnState.connected ||
            _ble!.state == BleConnState.connecting)) {
      return;
    }
    final deviceId = await prefsService.getBleDeviceId(van.mqttPrefix);
    if (deviceId == null)
      return; // van nay chua tung ghep noi BLE - khong co gi de fallback

    telemetry.addLog('[BLE] Mất MQTT - thử kết nối dự phòng qua Bluetooth...');
    _ble ??= BleService();

    final connected = await _ble!.connectById(deviceId);
    if (!connected) {
      telemetry.addLog(
        '[BLE] Không kết nối được (van có thể ngoài tầm sóng Bluetooth).',
      );
      _notify('⚠️ Mất Internet và không tìm thấy van qua Bluetooth (ngoài tầm sóng hoặc đã tắt nguồn).');
      return;
    }

    final authed = await _ble!.authenticate();
    if (!authed) {
      telemetry.addLog('[BLE] Xác thực Bluetooth thất bại.');
      await _ble!.disconnect();
      _notify('⚠️ Kết nối Bluetooth thất bại (sai mã xác thực).');
      return;
    }

    telemetry.addLog(
      '[BLE] Đã kết nối dự phòng qua Bluetooth - dùng để điều khiển/giám sát cục bộ.',
    );
    _notify('🔵 Mất Internet - đã chuyển sang điều khiển/giám sát qua Bluetooth (cục bộ).');
    await _bleLinesSub?.cancel();
    _bleLinesSub = _ble!.lines.listen(_onBleLine);
    await _bleConnSub?.cancel();
    _bleConnSub = _ble!.connectionState.listen((s) {
      if (s == BleConnState.disconnected) {
        telemetry.addLog('[BLE] Mất kết nối Bluetooth dự phòng.');
      }
      notifyListeners();
    });

    notifyListeners();
    // [FIX] Tai tu dong toan bo trang thai ngay khi vao che do BLE - giong
    // het luong _onConnected() cua MQTT - de nguoi dung KHONG PHAI tu bam
    // "Tai Lai" o tung tab (Cai Dat Van, ESP32 & WiFi) moi thay du lieu. Bo
    // qua FILES? vi ble_manager.ino khong forward lenh nay (chi MQTT).
    publish('PING');
    Future.delayed(const Duration(milliseconds: 300), () => publish('POS?'));
    Future.delayed(const Duration(milliseconds: 600), () => publish('SETTINGS?'));
    Future.delayed(const Duration(milliseconds: 900), () => publish('ESP_INFO?'));
  }

  /// Tra ve true neu lenh THAT SU duoc gui di qua 1 duong truyen dang hoat
  /// dong (khong dam bao van se nhan/thuc thi dung - chi dam bao KHONG roi
  /// vao khoang khong nhu truoc day). Cac man hinh dieu khien (control_tab)
  /// PHAI kiem tra isConnectionStale TRUOC khi goi ham nay, khong chi dua
  /// vao gia tri tra ve - vi activeTransport=mqtt van co the "coi nhu gui
  /// duoc" du van khong thuc su con song (xem isConnectionStale).
  bool publish(String cmd) {
    if (cmd == 'PING')
      _parser.pingSentAtMs = DateTime.now().millisecondsSinceEpoch;
    switch (activeTransport) {
      case ActiveTransport.mqtt:
        _mqtt.publish(topicCmd, cmd);
        telemetry.addLog('[MQTT TX] [$topicCmd] -> $cmd');
        return true;
      case ActiveTransport.ble:
        _ble!.writeCommand(cmd);
        telemetry.addLog('[BLE TX] -> $cmd');
        return true;
      case ActiveTransport.none:
        telemetry.addLog(
          '[TX] Không có kết nối (MQTT/BLE) - lệnh "$cmd" không được gửi.',
        );
        return false;
    }
  }

  /// Tuong duong manualRefreshMqtt() - nut "Lam Moi" tren AppBar VA keo man
  /// hinh de lam moi (RefreshIndicator trong monitor_tab.dart).
  /// [FIX] TRUOC DAY chi publish() lai cac lenh PING/POS?/... - neu dang
  /// mat ket noi that su (isConnectionStale), publish() se khong lam gi ca
  /// (hoac gui vao khoang khong neu MQTT "connected" gia), khien nguoi
  /// dung keo lam moi ma KHONG THAY GI THAY DOI, tuong da on nhung thuc ra
  /// van dang mat ket noi. Gio: neu dang mat ket noi, CHU DONG ket noi lai
  /// tu dau (MQTT roi tu dong rot xuong BLE neu can - xem connect()) truoc
  /// khi thu publish, va cho Future nay hoan tat de RefreshIndicator biet
  /// khi nao nen tat vong xoay.
  Future<void> refreshAll() async {
    if (isConnectionStale) {
      telemetry.addLog('[REFRESH] Phat hien mat ket noi - dang thu ket noi lai...');
      if (connState != MqttConnState.connecting) {
        await connect();
      }
      // connect() that bai se tu goi tryBleFallback() ben trong - cho 1 chut
      // de kip ket noi BLE (neu co) truoc khi danh gia lai isConnectionStale.
      await Future.delayed(const Duration(seconds: 3));
      if (isConnectionStale) {
        telemetry.addLog('[REFRESH] Van chua ket noi lai duoc.');
        return;
      }
    }
    publish('PING');
    await Future.delayed(const Duration(milliseconds: 500));
    publish('POS?');
    publish('FILES?');
    publish('SETTINGS?');
    publish('ESP_INFO?');
  }
}
