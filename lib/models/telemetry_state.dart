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
  int? mcuClk;
  String? mcuEe; // "ok"/khac
  String? mcuRtc; // "ok"/khac
  String? mcuVan; // ma van vd "S043"
  // [NEW] Chan doan boot CH32: so lan reset (dem tang dan, luu EEPROM tren
  // CH32 - song sot qua moi lan reset), nguyen nhan reset gan nhat
  // ("power"/"pin"/"software"/"iwdg"/"wwdg"/"lowpower"), va uptime (giay)
  // ke tu lan boot nay.
  int? mcuResetCount;
  String? mcuResetCause;
  int? mcuUptimeSec;

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
  // Cxx: canh bao het vat lieu - monCxx = gia tri cai dat (so chu ky giua 2
  // lan canh bao), monCcur = so chu ky con lai. monCxx == null hoac == 0
  // nghia la chua cau hinh/tat tinh nang nay tren van.
  int? monCxx;
  int? monCcur;

  // Lich su f_speed gan day - dung de ve bieu do bien thien luu luong (xem
  // FlowChart trong widgets/flow_chart.dart). Gioi han so diem de khong phinh
  // bo nho khi app mo lau - chi can du de thay xu huong gan day. [FIX] Tang
  // 60->120: cal_flow_sensor() ben firmware gui ##MON## moi ~1-5s khi co
  // luu luong (xem main.c: goi khi pulse_count>5 HOAC moi 5s) - 60 mau chi
  // giu duoc 1-5 PHUT lich su, qua ngan de thay xu huong troi qua 1 chu ky
  // xu ly (thuong vai chuc phut). 120 mau van nhe (FlowSample chi la
  // DateTime+double), doi lay cua so xem dai hon ro rang.
  static const int maxFlowSamples = 120;
  final List<FlowSample> flowHistory = [];

  // --- ##CFG## (SETTINGS?) ---
  // [NEW] Thoi diem NHAN duoc ##CFG## gan nhat - dung de van_settings_tab
  // biet chinh xac khi nao co 1 ban ##CFG## MOI ve (sau khi bam Luu, hoac
  // sau khi chu dong xin lai luc vao tab) de dong bo lai cac o nhap, thay
  // vi chi dong bo 1 LAN DUY NHAT luc mo dashboard nhu truoc day.
  DateTime? cfgUpdatedAt;
  List<int>? cfgWm; // gio/phut moi vi tri (van hen gio)
  List<int>? cfgQl; // luu luong trai moi vi tri (van flow)
  List<int>? cfgQr; // luu luong phai moi vi tri
  int? cfgH10;
  int? cfgFxx;
  int? cfgCxx; // Cxx: so chu ky giua 2 lan canh bao het vat lieu (0 = tat)
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
  // [NEW] Dia chi MAC (co dinh, khong doi theo trang thai ket noi) va so lan
  // STA bi mat ket noi tinh tu luc khoi dong - phuc vu giao dien quan ly
  // mang chi tiet hon trong esp_settings_tab.dart.
  String? wifiStaMac;
  int? wifiStaDisconnectCount;

  // --- ##WIFISCAN## ---
  List<WifiNetwork> wifiScanResults = [];
  // [NEW] Thoi diem NHAN duoc ##WIFISCAN## gan nhat - dung de esp_settings_tab
  // biet chinh xac 1 lan quet MOI da xong (so sanh voi thoi diem gui lenh
  // WIFI_SCAN), khac voi chi kiem tra wifiScanResults.isNotEmpty (co the la
  // ket qua CU con sot lai tu lan quet truoc, chua chac da quet xong lan nay).
  DateTime? wifiScanUpdatedAt;

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
    mcuFw = mcuId = mcuEe = mcuRtc = mcuVan = mcuResetCause = null;
    mcuResetCount = mcuUptimeSec = null;
    mcuClk = null;
    monPos = monRem = monModeA = monModeB = monSchedHour = monSchedMin = heap = heapMin = null;
    monCxx = monCcur = null;
    monVan = monMod = monTime = monDate = null;
    monScan = monRun = monErr = null;
    flowSpeed = flowSet = flowRem = null;
    flowHistory.clear();
    cfgWm = cfgQl = cfgQr = null;
    cfgH10 = cfgFxx = cfgCxx = cfgYear = cfgMonth = cfgDay = cfgHour = cfgMinute = cfgModeA = cfgModeB = null;
    cfgUpdatedAt = null;
    files = [];
    usedBytes = totalBytes = null;
    wifiApEnabled = wifiStaConnected = null;
    wifiApIP = wifiStaSavedSSID = wifiStaSSID = wifiStaIP = null;
    wifiStaRSSI = null;
    wifiStaMac = null;
    wifiStaDisconnectCount = null;
    wifiScanResults = [];
    wifiScanUpdatedAt = null;
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
