import 'package:flutter_test/flutter_test.dart';
import 'package:van_test/models/telemetry_state.dart';
import 'package:van_test/services/telemetry_parser.dart';

void main() {
  late TelemetryState state;
  late TelemetryParser parser;

  setUp(() {
    state = TelemetryState();
    parser = TelemetryParser(state);
  });

  test('parses ##MCU## block (mau thuc te tu thiet bi van_E6EBAC)', () {
    parser.parse(
      '##MCU##{"fw":"v1.1.0-OTA","id":"0x03510671","uid":"81B0ABCDEB5EBDE1FFFFFFFF","clk":48,"ee":"ok","rtc":"ok","van":"5023"}##END##',
    );
    expect(state.mcuFw, 'v1.1.0-OTA');
    expect(state.mcuId, '0x03510671');
    expect(state.mcuClk, 48);
    expect(state.mcuEe, 'ok');
    expect(state.mcuRtc, 'ok');
    expect(state.mcuVan, '5023');
  });

  test('parses ##MON## block va dong bo sang pos/run/err dung chung', () {
    parser.parse(
      '##MON##{"heap":1744,"hmin":1744,"pos":1,"rem":43200,"van":"5023","mod":"NONE","t":"16:59:53","d":"03/09/26","mA":32,"mB":35,"scan":true,"run":false,"sh":16,"sm":56,"err":false,"f_speed":0.00,"f_set":25.00,"f_rem":25.00}##END##',
    );
    expect(state.heap, 1744);
    expect(state.monPos, 1);
    expect(state.monTime, '16:59:53');
    expect(state.monDate, '03/09/26');
    // mA:32/mB:35 la gia tri enum SetupMode NOI BO cua firmware (A_01=32,
    // B_02=35 - xem _normalizeModeAB() trong telemetry_parser.dart) - phai
    // duoc chuan hoa ve 1/2 (A-01, B-02), khong hien thi nguyen "A-32"/"B-35".
    expect(state.monModeA, 1);
    expect(state.monModeB, 2);
    expect(state.monSchedHour, 16);
    expect(state.monSchedMin, 56);
    expect(state.flowSet, 25.0);
    // Dong bo qua truong dung chung
    expect(state.pos, 1);
    expect(state.isRunning, false);
    expect(state.isError, false);
    expect(state.isScanDone, true);
  });

  test('parses dong plain POS=/MODEL=/RUN=/SCAN=/ERR=', () {
    parser.parse('POS=3 MODEL=3 RUN=1 SCAN=1 ERR=0');
    expect(state.pos, 3);
    expect(state.modelNum, 3);
    expect(state.isRunning, true);
    expect(state.isScanDone, true);
    expect(state.isError, false);
  });

  test('PONG tinh duoc do latency khi da ghi nhan pingSentAtMs', () {
    parser.pingSentAtMs = DateTime.now().millisecondsSinceEpoch - 42;
    parser.parse('PONG');
    expect(state.pingLatencyMs, isNotNull);
    expect(state.pingLatencyMs! >= 40, true);
  });

  test('parses ##CFG## (SETTINGS?)', () {
    parser.parse(
      '##CFG##{"wm":[10,20,5,15,8],"ql":[1,2,3,4,5],"qr":[9,8,7,6,5],"h10":12,"fxx":3,"y":25,"mo":9,"d":3,"h":16,"m":30,"ma":1,"mb":2}##END##',
    );
    expect(state.cfgWm, [10, 20, 5, 15, 8]);
    expect(state.cfgQl, [1, 2, 3, 4, 5]);
    expect(state.cfgH10, 12);
    expect(state.cfgFxx, 3);
    expect(state.cfgYear, 25);
    expect(state.cfgModeA, 1);
    expect(state.cfgModeB, 2);
  });

  test('parses ##FILES##', () {
    parser.parse(
      '##FILES##{"files":[{"name":"app_ota_van4m3.bin","path":"/app_ota_van4m3.bin","size":56650,"formattedSize":"55.32 KB"}],"usedBytes":188416,"totalBytes":1441792}##END##',
    );
    expect(state.files.length, 1);
    expect(state.files.first.name, 'app_ota_van4m3.bin');
    expect(state.usedBytes, 188416);
    expect(state.totalBytes, 1441792);
  });

  test('parses ##WIFI##', () {
    parser.parse(
      '##WIFI##{"apEnabled":true,"apIP":"192.168.4.1","staSavedSSID":"HomeWifi","staConnected":true,"staSSID":"HomeWifi","staIP":"192.168.1.50","staRSSI":-55}##END##',
    );
    expect(state.wifiApEnabled, true);
    expect(state.wifiApIP, '192.168.4.1');
    expect(state.wifiStaConnected, true);
    expect(state.wifiStaSSID, 'HomeWifi');
    expect(state.wifiStaRSSI, -55);
  });

  test('parses ##WIFISCAN##', () {
    parser.parse('##WIFISCAN##[{"ssid":"NetA","rssi":-40,"secure":true},{"ssid":"NetB","rssi":-70,"secure":false}]##END##');
    expect(state.wifiScanResults.length, 2);
    expect(state.wifiScanResults[0].ssid, 'NetA');
    expect(state.wifiScanResults[1].secure, false);
  });

  test('parses ##ESPINFO## va dong bo AP/STA', () {
    parser.parse(
      '##ESPINFO##{"fw":"v1.3.0-C3","mqttPrefix":"van_E6EBAC","chip":"ESP32-C3 Rev 3","cpuFreq":160,"flashSize":4,"freeHeap":123456,"minFreeHeap":100000,"uptime":3600,"apEnabled":false,"apIP":"0.0.0.0","staConnected":true,"staSSID":"HomeWifi","staIP":"192.168.1.50","staRSSI":-50}##END##',
    );
    expect(state.espFw, 'v1.3.0-C3');
    expect(state.espMqttPrefix, 'van_E6EBAC');
    expect(state.espCpuFreq, 160);
    expect(state.espUptime, 3600);
    expect(state.wifiApEnabled, false);
    expect(state.wifiStaConnected, true);
  });

  test('parses [IAP nn%] tien trinh nap CH32', () {
    parser.parse('[IAP 42%] Dang ghi trang 12/28...');
    expect(state.otaPercent, 42);
    expect(state.otaInProgress, true);
  });

  test('ota_ok/ota_err events cap nhat otaOk', () {
    parser.parse('{"event":"ota_ok"}');
    expect(state.otaOk, true);
    expect(state.otaInProgress, false);

    parser.parse('{"event":"ota_err"}');
    expect(state.otaOk, false);
  });
}
