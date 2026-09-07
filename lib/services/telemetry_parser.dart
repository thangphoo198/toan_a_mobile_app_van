import 'dart:convert';
import '../models/telemetry_state.dart';

/// Port 1:1 cua parseTelemetry() trong web_client_mqtt.html - nhan 1 dong
/// message MQTT tho (bat ke topic cmd/status/telemetry/log) va cap nhat
/// TelemetryState tuong ung. Goi tu DashboardProvider moi khi co message den.
class TelemetryParser {
  final TelemetryState state;
  int? pingSentAtMs;

  TelemetryParser(this.state);

  void parse(String raw) {
    if (raw.isEmpty) return;
    bool changed = false;

    // PONG - do latency
    if (raw.contains('PONG') && pingSentAtMs != null) {
      state.pingLatencyMs = DateTime.now().millisecondsSinceEpoch - pingSentAtMs!;
      pingSentAtMs = null;
      changed = true;
    }

    // [IAP nn%] tien trinh nap CH32
    if (raw.contains('[IAP')) {
      final m = RegExp(r'\[IAP\s+(\d+)%\]').firstMatch(raw);
      if (m != null) {
        state.otaPercent = int.tryParse(m.group(1)!);
        state.otaInProgress = true;
      }
      state.otaStatusText = raw;
      changed = true;
    }
    if (raw.contains('ota_ok')) {
      state.otaOk = true;
      state.otaInProgress = false;
      state.otaPercent = 100;
      changed = true;
    } else if (raw.contains('ota_err')) {
      state.otaOk = false;
      state.otaInProgress = false;
      changed = true;
    }

    // POS=<n> MODEL=<n> RUN=<0|1> SCAN=<0|1> ERR=<0|1>
    final posM = RegExp(r'POS=(\d+)').firstMatch(raw);
    if (posM != null) {
      state.pos = int.tryParse(posM.group(1)!);
      changed = true;
    }
    final modelM = RegExp(r'MODEL=(\d+)').firstMatch(raw);
    if (modelM != null) {
      state.modelNum = int.tryParse(modelM.group(1)!);
      changed = true;
    }
    final runM = RegExp(r'RUN=(\d+)').firstMatch(raw);
    if (runM != null) {
      state.isRunning = runM.group(1) == '1';
      changed = true;
    }
    final scanM = RegExp(r'SCAN=(\d+)').firstMatch(raw);
    if (scanM != null) {
      state.isScanDone = scanM.group(1) == '1';
      changed = true;
    }
    final errM = RegExp(r'ERR=(\d+)').firstMatch(raw);
    if (errM != null) {
      state.isError = errM.group(1) == '1';
      changed = true;
    }

    changed |= _parseBlock(raw, 'MCU', _applyMcu);
    changed |= _parseBlock(raw, 'MON', _applyMon);
    changed |= _parseBlock(raw, 'CFG', _applyCfg);
    changed |= _parseBlock(raw, 'FILES', _applyFiles);
    changed |= _parseBlock(raw, 'WIFI', _applyWifi);
    changed |= _parseBlock(raw, 'WIFISCAN', _applyWifiScan);
    changed |= _parseBlock(raw, 'ESPINFO', _applyEspInfo);

    if (changed) state.notifyChanges();
  }

  bool _parseBlock(String raw, String marker, void Function(dynamic) apply) {
    final m = RegExp('##$marker##([\\s\\S]*?)##END##').firstMatch(raw);
    if (m == null || m.group(1) == null) return false;
    try {
      final decoded = jsonDecode(m.group(1)!);
      apply(decoded);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _applyMcu(dynamic m) {
    state.mcuFw = m['fw']?.toString();
    state.mcuId = m['id']?.toString();
    state.mcuUid = m['uid']?.toString();
    if (m['clk'] != null) state.mcuClk = (m['clk'] as num).toInt();
    state.mcuEe = m['ee']?.toString();
    state.mcuRtc = m['rtc']?.toString();
    state.mcuVan = m['van']?.toString();
  }

  /// [FIX] "mA"/"mB" trong ##MON## (send_monitor_json() bên firmware
  /// monitor.c) từng gửi NGUYÊN giá trị enum SetupMode nội bộ của CH32
  /// (A_01=32, A_02=33, B_01=34, B_02=35 - do modeOptionA/B dùng CHUNG 1
  /// enum lớn với hàng chục hằng số khác, không phải enum riêng bắt đầu từ
  /// 0/1) thay vì chuẩn hoá về 1/2 như ##CFG## (send_settings_json()) đã
  /// làm đúng từ trước - gây hiển thị vô nghĩa "A-32"/"B-35" thay vì
  /// "A-01"/"B-02". Đã sửa firmware để gửi đúng 1/2 (khớp CFG), hàm này chỉ
  /// là lớp bảo vệ ở app: giá trị 1/2 giữ nguyên; giá trị lạ (firmware cũ
  /// chưa nạp lại) được suy ra qua tính chẵn/lẻ - khớp chính xác với thứ tự
  /// enum thực tế (A_01=32 chẵn, A_02=33 lẻ, B_01=34 chẵn, B_02=35 lẻ).
  int _normalizeModeAB(int raw) {
    if (raw == 1 || raw == 2) return raw;
    return (raw % 2 == 0) ? 1 : 2;
  }

  void _applyMon(dynamic d) {
    if (d['pos'] != null) state.monPos = (d['pos'] as num).toInt();
    if (d['rem'] != null) state.monRem = (d['rem'] as num).toInt();
    state.monVan = d['van']?.toString();
    state.monMod = d['mod']?.toString();
    state.monTime = d['t']?.toString();
    state.monDate = d['d']?.toString();
    if (d['mA'] != null) state.monModeA = _normalizeModeAB((d['mA'] as num).toInt());
    if (d['mB'] != null) state.monModeB = _normalizeModeAB((d['mB'] as num).toInt());
    if (d['scan'] != null) state.monScan = d['scan'] == true;
    if (d['run'] != null) state.monRun = d['run'] == true;
    if (d['sh'] != null) state.monSchedHour = (d['sh'] as num).toInt();
    if (d['sm'] != null) state.monSchedMin = (d['sm'] as num).toInt();
    if (d['err'] != null) state.monErr = d['err'] == true;
    if (d['f_speed'] != null) {
      state.flowSpeed = (d['f_speed'] as num).toDouble();
      state.flowHistory.add(FlowSample(DateTime.now(), state.flowSpeed!));
      if (state.flowHistory.length > TelemetryState.maxFlowSamples) {
        state.flowHistory.removeAt(0);
      }
    }
    if (d['f_set'] != null) state.flowSet = (d['f_set'] as num).toDouble();
    if (d['f_rem'] != null) state.flowRem = (d['f_rem'] as num).toDouble();
    if (d['heap'] != null) state.heap = (d['heap'] as num).toInt();
    if (d['hmin'] != null) state.heapMin = (d['hmin'] as num).toInt();
    if (d['cxx'] != null) state.monCxx = (d['cxx'] as num).toInt();
    if (d['ccur'] != null) state.monCcur = (d['ccur'] as num).toInt();

    // MON cung mang pos/run/err "tuoi" hon POS= line - dong bo luon truong
    // dung chung o Giam Sat/Dieu Khien de khong lech giua 2 nguon.
    if (d['pos'] != null) state.pos = (d['pos'] as num).toInt();
    if (d['run'] != null) state.isRunning = d['run'] == true;
    if (d['err'] != null) state.isError = d['err'] == true;
    if (d['scan'] != null) state.isScanDone = d['scan'] == true;
  }

  void _applyCfg(dynamic c) {
    if (c['wm'] is List) state.cfgWm = (c['wm'] as List).map((e) => (e as num).toInt()).toList();
    if (c['ql'] is List) state.cfgQl = (c['ql'] as List).map((e) => (e as num).toInt()).toList();
    if (c['qr'] is List) state.cfgQr = (c['qr'] as List).map((e) => (e as num).toInt()).toList();
    if (c['h10'] != null) state.cfgH10 = (c['h10'] as num).toInt();
    if (c['fxx'] != null) state.cfgFxx = (c['fxx'] as num).toInt();
    if (c['cxx'] != null) state.cfgCxx = (c['cxx'] as num).toInt();
    if (c['y'] != null) state.cfgYear = (c['y'] as num).toInt();
    if (c['mo'] != null) state.cfgMonth = (c['mo'] as num).toInt();
    if (c['d'] != null) state.cfgDay = (c['d'] as num).toInt();
    if (c['h'] != null) state.cfgHour = (c['h'] as num).toInt();
    if (c['m'] != null) state.cfgMinute = (c['m'] as num).toInt();
    if (c['ma'] != null) state.cfgModeA = (c['ma'] as num).toInt();
    if (c['mb'] != null) state.cfgModeB = (c['mb'] as num).toInt();
  }

  void _applyFiles(dynamic f) {
    if (f['files'] is List) {
      state.files = (f['files'] as List)
          .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      state.files = [];
    }
    if (f['usedBytes'] != null) state.usedBytes = (f['usedBytes'] as num).toInt();
    if (f['totalBytes'] != null) state.totalBytes = (f['totalBytes'] as num).toInt();
  }

  void _applyWifi(dynamic w) {
    if (w['apEnabled'] != null) state.wifiApEnabled = w['apEnabled'] == true;
    state.wifiApIP = w['apIP']?.toString();
    state.wifiStaSavedSSID = w['staSavedSSID']?.toString();
    if (w['staConnected'] != null) state.wifiStaConnected = w['staConnected'] == true;
    state.wifiStaSSID = w['staSSID']?.toString();
    state.wifiStaIP = w['staIP']?.toString();
    if (w['staRSSI'] != null) state.wifiStaRSSI = (w['staRSSI'] as num).toInt();
  }

  void _applyWifiScan(dynamic list) {
    if (list is List) {
      state.wifiScanResults =
          list.map((e) => WifiNetwork.fromJson(e as Map<String, dynamic>)).toList();
    }
  }

  void _applyEspInfo(dynamic e) {
    state.espFw = e['fw']?.toString();
    state.espMqttPrefix = e['mqttPrefix']?.toString();
    state.espChip = e['chip']?.toString();
    if (e['cpuFreq'] != null) state.espCpuFreq = (e['cpuFreq'] as num).toInt();
    if (e['flashSize'] != null) state.espFlashSize = (e['flashSize'] as num).toInt();
    if (e['freeHeap'] != null) state.espFreeHeap = (e['freeHeap'] as num).toInt();
    if (e['minFreeHeap'] != null) state.espMinFreeHeap = (e['minFreeHeap'] as num).toInt();
    if (e['uptime'] != null) state.espUptime = (e['uptime'] as num).toInt();

    // ##ESPINFO## cung mang theo AP/STA - dong bo qua card WiFi luon.
    if (e['apEnabled'] != null) state.wifiApEnabled = e['apEnabled'] == true;
    if (e['apIP'] != null) state.wifiApIP = e['apIP']?.toString();
    if (e['staConnected'] != null) state.wifiStaConnected = e['staConnected'] == true;
    if (e['staSSID'] != null) state.wifiStaSSID = e['staSSID']?.toString();
    if (e['staIP'] != null) state.wifiStaIP = e['staIP']?.toString();
    if (e['staRSSI'] != null) state.wifiStaRSSI = (e['staRSSI'] as num).toInt();
  }
}
