import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import 'mqtt_client_creator.dart';
import '../models/telemetry_state.dart';
import 'telemetry_parser.dart';

/// Ket qua theo doi 1 van - dung cho man hinh "Quan Ly Van" hien thi thong
/// tin nhanh (khong can mo dashboard) va xac dinh online/offline/dang chay.
class VanQuickStatus {
  bool online;
  int? pos; // vi tri hien tai (POS=/##MON##)
  int? wifiRssi; // cuong do song WiFi cua CHINH VAN toi router nha (dBm)
  bool? running; // dong co THUC SU dang quay (##MON##.mod=="RUN") - dung de khoa NEXT
  // Da quet xong chua (##MON##.scan, tuong ung is_scan_done ben CH32) - false
  // = dang quet/phuc hoi vi tri, vi tri (pos) THUC SU vo nghia luc nay.
  bool? scanDone;
  // [NEW] Model THAT SU dang chay tren van (##MCU##.van, vd "F041"/"S043") -
  // khac voi Van.model luu trong database app (nhap 1 lan luc them van, co
  // the LECH neu ai do doi model vat ly tren thiet bi sau do ma khong cap
  // nhat lai trong app - "Quan Ly Van" phai uu tien gia tri SONG nay).
  String? model;
  VanQuickStatus({this.online = false, this.pos, this.wifiRssi, this.running, this.scanDone, this.model});
}

/// Dich vu theo doi trang thai NHIEU van CUNG LUC cho tab "Quan Ly Van" -
/// giu MOT ket noi MQTT DUNG CHUNG, LIEN TUC trong suot thoi gian tab nay
/// dang duoc CHON (xem MainShell.onDestinationSelected() - dung khi chuyen
/// sang xem 1 van cu the, khoi dong lai khi quay ve tab danh sach). Khac voi
/// ban truoc day (mo/dong ket noi tam thoi moi lan bam lam moi): gio day co
/// 1 NGUON TRANG THAI DUY NHAT, cap nhat gan-nhu-realtime (poll moi 15s +
/// nhan telemetry chu dong tu van), giup biet CHINH XAC van nao dang chay
/// dong co de KHOA nut NEXT nhanh tren the, tranh nham lan trang thai giua
/// nhieu van khi danh sach dai.
class VanStatusChecker {
  MqttClient? _client;
  Timer? _pollTimer;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _sub;
  final Map<String, TelemetryState> _states = {};
  final Map<String, TelemetryParser> _parsers = {};

  /// Trang thai hien tai cua tung van (theo mqttPrefix) - VanListProvider
  /// doc truc tiep map nay sau moi lan [onUpdate] duoc goi.
  final Map<String, VanQuickStatus> results = {};

  /// Goi lai moi khi co du lieu moi tu bat ky van nao - dung de
  /// VanListProvider dong bo sang cac map cua no roi notifyListeners().
  void Function()? onUpdate;

  bool get isRunning => _client != null;

  /// Bat dau (hoac khoi dong lai tu dau neu dang chay - vd danh sach van vua
  /// doi) dich vu theo doi truc tiep cho dung [mqttPrefixes] da cho.
  Future<void> start(
    List<String> mqttPrefixes, {
    required String host,
    required int port,
    required String user,
    required String pass,
  }) async {
    await stop();
    if (mqttPrefixes.isEmpty) return;

    for (final p in mqttPrefixes) {
      results[p] = VanQuickStatus();
      _states[p] = TelemetryState();
      _parsers[p] = TelemetryParser(_states[p]!);
    }

    final clientId = 'VAN_MULTI_${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final client = createMqttClient(host, clientId, port);
    client.logging(on: false);
    client.setProtocolV311();
    client.keepAlivePeriod = 30;
    client.autoReconnect = true;
    client.connectTimeoutPeriod = 6000;
    client.connectionMessage = MqttConnectMessage().withClientIdentifier(clientId).startClean();

    try {
      await client.connect(user, pass).timeout(
        Duration(milliseconds: client.connectTimeoutPeriod + 2000),
        onTimeout: () => null,
      );
    } catch (_) {
      return;
    }
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      return;
    }
    _client = client;

    // [FIX] Topic gio nam duoi 1 namespace goc chung "van/" (xem chu thich
    // computeDeviceTopics() ben esp32c3_ota.ino) - ACL cua broker chi can 1
    // dong "van/#" duy nhat cho MOI van, khong phai sua tay moi khi them van
    // moi nhu truoc (tung van 1 dong ACL rieng theo prefix).
    for (final prefix in mqttPrefixes) {
      client.subscribe('van/$prefix/status', MqttQos.atMostOnce);
      client.subscribe('van/$prefix/telemetry', MqttQos.atMostOnce);
      client.subscribe('van/$prefix/log', MqttQos.atMostOnce);
    }

    _sub = client.updates?.listen((events) {
      bool changed = false;
      for (final e in events) {
        final topic = e.topic;
        // "van/<prefix>/<loai>" - bo qua segment goc "van/" roi moi lay prefix
        // (segment thu 2), khac voi truoc day prefix la segment DAU TIEN.
        if (!topic.startsWith('van/')) continue;
        final rest = topic.substring(4);
        final slash = rest.indexOf('/');
        if (slash <= 0) continue;
        final prefix = rest.substring(0, slash);
        final r = results[prefix];
        final parser = _parsers[prefix];
        if (r == null || parser == null) continue;
        r.online = true;
        final payload = MqttPublishPayload.bytesToStringAsString(
          (e.payload as MqttPublishMessage).payload.message,
        );
        parser.parse(payload);
        final t = _states[prefix]!;
        r.pos = t.pos ?? t.monPos ?? r.pos;
        r.wifiRssi = t.wifiStaRSSI ?? r.wifiRssi;
        r.model = t.mcuVan ?? t.monVan ?? r.model;
        // [FIX] KHONG dung t.isRunning/t.monRun (tu "RUN="/is_van_running ben
        // CH32) - nghia thuc su la "van dang o vi tri khac 1" (bus bi khoa),
        // TRUE VINH VIEN ca luc dong co dang DUNG YEN cho toi khi ve vi tri 1
        // (xem chu thich trong control_tab.dart). Dung t.monMod=='RUN' (tu
        // setupMode ben CH32, qua ##MON##) - CHI true trong luc dong co THUC
        // SU dang quay, giong het tieu chi khoa nut o tab Dieu Khien.
        if (t.monMod != null) r.running = t.monMod == 'RUN';
        if (t.isScanDone != null) r.scanDone = t.isScanDone;
        changed = true;
      }
      if (changed) onUpdate?.call();
    });

    pollNow();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => pollNow());
  }

  /// Gui ngay PING+WIFI_STATUS? toi TAT CA van dang theo doi - dung cho lan
  /// dau moi start() va cho "keo lam moi" thu cong tren man hinh danh sach.
  void pollNow() {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) return;
    for (final prefix in results.keys) {
      final b1 = MqttClientPayloadBuilder()..addString('PING');
      client.publishMessage('van/$prefix/cmd', MqttQos.atMostOnce, b1.payload!);
      final b2 = MqttClientPayloadBuilder()..addString('WIFI_STATUS?');
      client.publishMessage('van/$prefix/cmd', MqttQos.atMostOnce, b2.payload!);
    }
  }

  /// Gui 1 lenh dieu khien NHANH (vd "NEXT") toi 1 van CU THE - dung LAI ket
  /// noi dung chung dang mo (KHONG mo ket noi tam thoi rieng nhu truoc day)
  /// nen gui duoc ngay, khong ton them ~1-2s bat tay MQTT moi lan bam.
  bool sendCommand(String mqttPrefix, String cmd) {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) return false;
    final builder = MqttClientPayloadBuilder()..addString(cmd);
    client.publishMessage('van/$mqttPrefix/cmd', MqttQos.atMostOnce, builder.payload!);
    return true;
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _sub?.cancel();
    _sub = null;
    _client?.disconnect();
    _client = null;
    _states.clear();
    _parsers.clear();
    results.clear();
  }
}
