import 'package:flutter/foundation.dart';

class FileEntry {
  final String name;
  final String path;
  final int size;
  final String? formattedSize;

  FileEntry({required this.name, required this.path, required this.size, this.formattedSize});

  factory FileEntry.fromJson(Map<String, dynamic> j) => FileEntry(
        name: j['name']?.toString() ?? '',
        path: j['path']?.toString() ?? '',
        size: (j['size'] is num) ? (j['size'] as num).toInt() : 0,
        formattedSize: j['formattedSize']?.toString(),
      );
}

/// 1 diem du lieu luu luong tuc thoi (f_speed) tai 1 thoi diem - dung de ve
/// bieu do bien thien flow theo thoi gian trong monitor_tab.dart.
class FlowSample {
  final DateTime time;
  final double speed;
  FlowSample(this.time, this.speed);
}

class WifiNetwork {
  final String ssid;
  final int rssi;
  final bool secure;

  WifiNetwork({required this.ssid, required this.rssi, required this.secure});

  factory WifiNetwork.fromJson(Map<String, dynamic> j) => WifiNetwork(
        ssid: j['ssid']?.toString() ?? '',
        rssi: (j['rssi'] is num) ? (j['rssi'] as num).toInt() : 0,
        secure: j['secure'] == true,
      );
}

/// Toan bo trang thai da parse tu MQTT cua 1 van dang mo - mirror parseTelemetry()
/// trong web_client_mqtt.html. Moi tab dashboard doc tu day qua Provider.
class TelemetryState extends ChangeNotifier {
  // --- Trang thai ket noi ---
  bool mqttConnected = false;
  int? pingLatencyMs;
  DateTime? lastUpdate; // lan cuoi nhan duoc bat ky message nao tu van

  // --- POS=/MODEL=/RUN=/SCAN=/ERR= (plain, tu PING/POS?/NEXT/GOTO) ---
  int? pos;
  int? modelNum; // 0-3 noi bo (MODEL=), UI hien 1-4
  bool? isRunning;
  bool? isScanDone;
  bool? isError;

  // --- ##MCU## ---
  String? mcuFw;
  String? mcuId;
  String? mcuUid;
  int? mcuClk;
  String? mcuEe; // "ok"/khac
  String? mcuRtc; // "ok"/khac
  String? mcuVan; // ma van vd "5023"

  // --- ##MON## ---
  int? monPos;
  int? monRem;
  String? monVan;
  String? monMod;
  String? monTime; // "HH:MM:SS"
  String? monDate; // "DD/MM/YY"
  int? monModeA;
  int? monModeB;
  bool? monScan;
  bool? monRun;
  int? monSchedHour;
  int? monSchedMin;
  bool? monErr;
  double? flowSpeed; // f_speed
  double? flowSet; // f_set
  double? flowRem; // f_rem
  int? heap;
  int? heapMin;

  // Lich su f_speed gan day - dung de ve bieu do bien thien luu luong (xem
  // FlowChart trong widgets/flow_chart.dart). Gioi han so diem de khong phinh
  // bo nho khi app mo lau - chi can du de thay xu huong gan day.
  static const int maxFlowSamples = 60;
  final List<FlowSample> flowHistory = [];

  // --- ##CFG## (SETTINGS?) ---
  List<int>? cfgWm; // gio/phut moi vi tri (van hen gio)
  List<int>? cfgQl; // luu luong trai moi vi tri (van flow)
  List<int>? cfgQr; // luu luong phai moi vi tri
  int? cfgH10;
  int? cfgFxx;
  int? cfgYear; // 2 chu so (25 = 2025)
  int? cfgMonth;
  int? cfgDay;
  int? cfgHour;
  int? cfgMinute;
  int? cfgModeA;
  int? cfgModeB;

  // --- ##FILES## ---
  List<FileEntry> files = [];
  int? usedBytes;
  int? totalBytes;

  // --- ##WIFI## ---
  bool? wifiApEnabled;
  String? wifiApIP;
  String? wifiStaSavedSSID;
  bool? wifiStaConnected;
  String? wifiStaSSID;
  String? wifiStaIP;
  int? wifiStaRSSI;

  // --- ##WIFISCAN## ---
  List<WifiNetwork> wifiScanResults = [];

  // --- ##ESPINFO## ---
  String? espFw;
  String? espMqttPrefix;
  String? espChip;
  int? espCpuFreq;
  int? espFlashSize;
  int? espFreeHeap;
  int? espMinFreeHeap;
  int? espUptime;

  // --- OTA / IAP progress ---
  int? otaPercent;
  String otaStatusText = 'Chờ lệnh nạp...';
  bool otaInProgress = false;
  bool? otaOk;

  // --- Log / terminal ---
  final List<String> logLines = [];

  void addLog(String line) {
    logLines.add(line);
    if (logLines.length > 500) {
      logLines.removeRange(0, logLines.length - 500);
    }
    // Goi rieng, khong dua vao parse() cua TelemetryParser: 1 dong log co
    // the la text ma khong khop bat ky pattern nao (parser se khong goi
    // notifyChanges()) - Terminal tab van phai thay dong do ngay lap tuc.
    notifyListeners();
  }

  void clearLog() {
    logLines.clear();
    notifyListeners();
  }

  /// Wrapper cong khai cho notifyListeners() (protected) - de TelemetryParser
  /// (khong phai ChangeNotifier) co the bao UI cap nhat sau khi parse xong.
  void notifyChanges() => notifyListeners();

  void reset() {
    mqttConnected = false;
    pingLatencyMs = null;
    lastUpdate = null;
    pos = modelNum = null;
    isRunning = isScanDone = isError = null;
    mcuFw = mcuId = mcuUid = mcuEe = mcuRtc = mcuVan = null;
    mcuClk = null;
    monPos = monRem = monModeA = monModeB = monSchedHour = monSchedMin = heap = heapMin = null;
    monVan = monMod = monTime = monDate = null;
    monScan = monRun = monErr = null;
    flowSpeed = flowSet = flowRem = null;
    flowHistory.clear();
    cfgWm = cfgQl = cfgQr = null;
    cfgH10 = cfgFxx = cfgYear = cfgMonth = cfgDay = cfgHour = cfgMinute = cfgModeA = cfgModeB = null;
    files = [];
    usedBytes = totalBytes = null;
    wifiApEnabled = wifiStaConnected = null;
    wifiApIP = wifiStaSavedSSID = wifiStaSSID = wifiStaIP = null;
    wifiStaRSSI = null;
    wifiScanResults = [];
    espFw = espMqttPrefix = espChip = null;
    espCpuFreq = espFlashSize = espFreeHeap = espMinFreeHeap = espUptime = null;
    otaPercent = null;
    otaStatusText = 'Chờ lệnh nạp...';
    otaInProgress = false;
    otaOk = null;
    logLines.clear();
    notifyListeners();
  }
}
