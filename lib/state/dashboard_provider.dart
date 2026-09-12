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

  // [NEW] Hoi nguoi dung TRUOC khi tu dong ket noi BLE khi mat MQTT - truoc
  // day tryBleFallback() tu ket noi ngam, nguoi dung khong biet dien thoai
  // dang tu chuyen sang phat/nhan qua Bluetooth. Gio chi PHAT 1 thong bao co
  // nut bam qua stream nay (xem main_shell.dart), THUC SU ket noi chi khi
  // nguoi dung tu bam xac nhan (confirmBleFallback()).
  final _bleFallbackPromptController = StreamController<String>.broadcast();
  Stream<String> get bleFallbackPrompts => _bleFallbackPromptController.stream;
  bool _blePromptActive = false;
  DateTime? _blePromptCooldownUntil;

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
    // [NEW] "Tu chua benh" cho BLE du phong - truoc day CHI thu ket noi BLE
    // theo phan ung voi 1 SU KIEN MQTT (connect that bai/mat ket noi), nen
    // neu chinh BLE roi (ra khoi tam song 1 chut, ESP32 tam khoi dong lai)
    // TRONG LUC MQTT van chua on, khong co gi tu dong thu ket noi lai - dung
    // yen o "MẤT KẾT NỐI" cho toi khi nguoi dung tu keo lam moi. Chu ky nay
    // la "luoi an toan" chay ngam, tu kiem tra va thu lai neu can.
    _bleRetryTimer = Timer.periodic(const Duration(seconds: 12), (_) => _maybeRetryBle());
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    telemetry.removeListener(notifyListeners);
    _mqtt.disconnect();
    _noDataWatchdog?.cancel();
    _bleRetryTimer?.cancel();
    _bleReconnectDelay?.cancel();
    _bleLinesSub?.cancel();
    _bleConnSub?.cancel();
    _ble?.dispose();
    _events.close();
    _bleFallbackPromptController.close();
    super.dispose();
  }

  MqttConnState connState = MqttConnState.disconnected;
  String? connError;
  String host = 'toana.cloud';
  int port = 443;
  String mqttUser = 'thangpro1998';
  String mqttPass = 'thang123';

  // --- BLE (kenh du phong cuc bo - xem tryBleFallback()) ---
  BleService? _ble;
  StreamSubscription? _bleLinesSub;
  StreamSubscription? _bleConnSub;
  Timer? _noDataWatchdog;
  Timer? _bleRetryTimer;
  Timer? _bleReconnectDelay;

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

  // [FIX] Topic gio nam duoi 1 namespace goc chung "van/" (xem chu thich
  // computeDeviceTopics() ben esp32c3_ota.ino) - ACL Mosquitto chi can 1
  // dong "van/#" cho MOI van thay vi phai sua tay them 1 dong rieng theo
  // tung mqttPrefix moi nhu truoc.
  String get _topicRoot => 'van/${van.mqttPrefix}';
  String get topicCmd => '$_topicRoot/cmd';

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
      topicPrefix: _topicRoot,
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
    // sau 4s vẫn chưa nhận được BẤT KỲ message nào từ van, coi như MQTT
    // không dùng được cho van này lúc này - chủ động thử BLE cục bộ. [FIX]
    // Rút từ 8s xuống 4s ("làm mượt" theo yêu cầu) - CH32 phản hồi PING/POS?
    // trong dưới 1s khi WiFi thực sự thông, 4s đã đủ dư để không "nhầy" báo
    // BLE khi mạng chỉ chậm nhẹ, mà không bắt người dùng chờ quá lâu khi
    // mạng THẬT SỰ mất.
    _noDataWatchdog?.cancel();
    _noDataWatchdog = Timer(const Duration(seconds: 4), () {
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
  /// ghép nối qua BLE (xem BlePairScreen), HỎI người dùng trước (KHÔNG tự
  /// động kết nối ngầm nữa - người dùng cần biết/đồng ý trước khi điện thoại
  /// chuyển sang phát/nhận qua Bluetooth). Chỉ PHÁT thông báo có nút bấm qua
  /// [bleFallbackPrompts] - việc kết nối THẬT SỰ nằm trong
  /// confirmBleFallback(), chỉ chạy khi người dùng tự bấm xác nhận.
  Future<void> tryBleFallback() async {
    if (_disposed) return;
    if (_mqttProven) return; // MQTT da xac nhan song - khong can BLE nua
    if (_ble != null &&
        (_ble!.state == BleConnState.connected ||
            _ble!.state == BleConnState.connecting)) {
      return;
    }
    if (_blePromptActive) return; // da hoi roi, dang cho nguoi dung tra loi
    if (_blePromptCooldownUntil != null &&
        DateTime.now().isBefore(_blePromptCooldownUntil!)) {
      return; // nguoi dung vua bo qua - khong hoi lai ngay lap tuc, tranh lam phien
    }
    final deviceId = await prefsService.getBleDeviceId(van.mqttPrefix);
    if (_disposed) return;
    if (deviceId == null)
      return; // van nay chua tung ghep noi BLE - khong co gi de fallback

    _blePromptActive = true;
    telemetry.addLog(
      '[BLE] Mất MQTT - hỏi người dùng có muốn chuyển sang Bluetooth...',
    );
    _bleFallbackPromptController.add(
      'Mất Internet - kết nối van "${van.displayName}" qua Bluetooth để tiếp tục điều khiển/giám sát cục bộ?',
    );
  }

  /// Người dùng bấm xác nhận trên thông báo từ tryBleFallback() - THỰC SỰ
  /// thực hiện kết nối BLE (toàn bộ logic trước đây nằm ngay trong
  /// tryBleFallback()).
  Future<void> confirmBleFallback() async {
    _blePromptActive = false;
    _blePromptCooldownUntil = null;
    if (_disposed) return;
    if (_mqttProven) return; // MQTT da tu khoi phuc trong luc cho tra loi
    final deviceId = await prefsService.getBleDeviceId(van.mqttPrefix);
    if (_disposed || deviceId == null) return;

    telemetry.addLog('[BLE] Người dùng đồng ý - thử kết nối dự phòng qua Bluetooth...');
    // [NEW] Bao ngay LUC BAT DAU do/ket noi - truoc day chi bao khi THANH
    // CONG hoac THAT BAI, nguoi dung khong biet app co dang lam gi khong
    // trong luc cho (co the vai giay). Dung ten van (khong chi "mất Internet"
    // chung chung) de ro rang dang tim DUNG van nao.
    _notify('🔍 Đang tìm van "${van.displayName}" qua Bluetooth...');
    _ble ??= BleService();

    final connected = await _ble!.connectById(deviceId);
    if (_disposed) return;
    if (!connected) {
      telemetry.addLog(
        '[BLE] Không kết nối được (van có thể ngoài tầm sóng Bluetooth).',
      );
      _notify('⚠️ Không tìm thấy van qua Bluetooth (ngoài tầm sóng hoặc đã tắt nguồn).');
      return;
    }

    final authed = await _ble!.authenticate();
    if (_disposed) return;
    if (!authed) {
      telemetry.addLog('[BLE] Xác thực Bluetooth thất bại.');
      await _ble!.disconnect();
      _notify('⚠️ Kết nối Bluetooth thất bại (sai mã xác thực).');
      return;
    }

    telemetry.addLog(
      '[BLE] Đã kết nối dự phòng qua Bluetooth - dùng để điều khiển/giám sát cục bộ.',
    );
    // [FIX] Neu ro TEN VAN da ket noi duoc (khong chi "đã chuyển sang
    // Bluetooth" chung chung) - quan trong khi nguoi dung dang mo nhieu van/
    // dung nhieu thiet bi gan nhau, can biet CHAC dang noi chuyen voi dung
    // van nao qua kenh du phong nay.
    _notify('🔵 Đã kết nối Bluetooth thành công tới van "${van.displayName}" - điều khiển/giám sát cục bộ.');
    await _bleLinesSub?.cancel();
    _bleLinesSub = _ble!.lines.listen(_onBleLine);
    await _bleConnSub?.cancel();
    _bleConnSub = _ble!.connectionState.listen((s) {
      if (s == BleConnState.disconnected) {
        telemetry.addLog('[BLE] Mất kết nối Bluetooth dự phòng.');
        // [NEW] "Làm mượt" - tự thử HỎI LẠI sau vài giây (không tự ý kết nối
        // thẳng) thay vì đứng yên chờ chu kỳ _bleRetryTimer (tới 12s) hoặc
        // người dùng tự kéo làm mới. Ca phổ biến nhất là rớt sóng thoáng qua
        // (đi ra xa 1 chút rồi quay lại, ESP32 khởi động lại).
        _bleReconnectDelay?.cancel();
        _bleReconnectDelay = Timer(const Duration(seconds: 4), () {
          if (!_disposed && !_mqttProven) tryBleFallback();
        });
      }
      notifyListeners();
    });

    notifyListeners();
    // [FIX] Tai tu dong toan bo trang thai ngay khi vao che do BLE - giong
    // het luong _onConnected() cua MQTT - de nguoi dung KHONG PHAI tu bam
    // "Tai Lai" o tung tab (Cai Dat Van, ESP32 & WiFi) moi thay du lieu.
    // FILES? gio DA dung duoc qua BLE (dispatchDeviceCommand() dung chung
    // MQTT+BLE, xem mqtt_manager.ino) - xin luon de danh sach file nap CH32
    // ngoai tuyen (ota_tab.dart) tu co san, khong bat nguoi dung tu bam lam moi.
    publish('PING');
    Future.delayed(const Duration(milliseconds: 300), () => publish('POS?'));
    Future.delayed(const Duration(milliseconds: 600), () => publish('SETTINGS?'));
    Future.delayed(const Duration(milliseconds: 900), () => publish('ESP_INFO?'));
    Future.delayed(const Duration(milliseconds: 1200), () => publish('FILES?'));
  }

  /// Người dùng bấm "Bỏ qua" (hoặc để thông báo tự tắt) - không kết nối BLE
  /// lần này, tạm ngừng hỏi lại vài phút để không làm phiền liên tục trong
  /// lúc van thực sự đang mất mạng lâu dài.
  void declineBleFallback() {
    _blePromptActive = false;
    _blePromptCooldownUntil = DateTime.now().add(const Duration(minutes: 2));
    telemetry.addLog('[BLE] Người dùng chọn không chuyển sang Bluetooth lúc này.');
  }

  /// "Luoi an toan" chay ngam moi 12s (xem constructor) - tu kiem tra va thu
  /// ket noi lai BLE neu can, thay vi chi phan ung voi 1 su kien MQTT. Ban
  /// than tryBleFallback() da tu bo qua neu MQTT dang on hoac BLE dang
  /// connected/connecting nen goi lai nhieu lan la an toan, khong lam gi neu
  /// khong can thiet.
  void _maybeRetryBle() => tryBleFallback();

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

  /// [NEW] Truyen 1 file firmware (CH32 hoac ESP32) qua Bluetooth - CHI dung
  /// duoc khi dang thuc su o che do BLE (xem ActiveTransport). Byte da duoc
  /// UI tu tai san (qua mang rieng cua dien thoai, khong lien quan van) hoac
  /// nguoi dung tu chon tu may - ham nay chi lo phan CHUYEN GIAO qua BLE, xem
  /// BleService.sendFirmwareOverBle() de biet chi tiet giao thuc.
  Future<bool> sendFirmwareOverBle({
    required String target,
    required List<int> bytes,
    void Function(String rawLine)? onStatus,
  }) async {
    if (activeTransport != ActiveTransport.ble || _ble == null) return false;
    telemetry.addLog('[BLE FLASH] Bắt đầu truyền firmware "$target" (${bytes.length} byte) qua Bluetooth...');
    final ok = await _ble!.sendFirmwareOverBle(target: target, bytes: bytes, onStatus: onStatus);
    telemetry.addLog(ok ? '[BLE FLASH] Hoàn tất.' : '[BLE FLASH] Thất bại/bị huỷ.');
    return ok;
  }

  /// Huy 1 phien truyen firmware qua BLE dang do dang.
  Future<void> abortBleFirmwareTransfer() async {
    if (_ble != null) await _ble!.abortFirmwareTransfer();
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
