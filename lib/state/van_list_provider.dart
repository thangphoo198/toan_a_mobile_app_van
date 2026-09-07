import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/van.dart';
import '../services/api_service.dart';
import '../services/ble_service.dart';
import '../services/prefs_service.dart';
import '../services/van_status_checker.dart';

/// Trang thai online/offline cua 1 van trong danh sach "Quan Ly Van".
/// checking = dang kiem tra (vua vao app/vua bam lam moi), chua co ket qua.
enum VanOnlineStatus { checking, online, offline }

class VanListProvider extends ChangeNotifier {
  final ApiService api;
  final PrefsService _prefsService = PrefsService();
  final VanStatusChecker _statusChecker = VanStatusChecker();
  final BleService _bleScanner = BleService();

  List<Van> vans = [];
  bool loading = false;
  String? error;

  // Trang thai/thong tin nhanh theo mqttPrefix - hien truc tiep tren the cua
  // tung van trong "Quan Ly Van" (khong can mo dashboard). Khong dung
  // Map<int,...> (id) vi id chi co sau khi load() xong, trong khi mqttPrefix
  // la khoa tu nhien va on dinh cua van.
  final Map<String, VanOnlineStatus> onlineStatus = {};
  final Map<String, int?> posByPrefix = {}; // vi tri hien tai (1-5)
  final Map<String, int?> wifiRssiByPrefix = {}; // cuong do song WiFi cua CHINH VAN (dBm, qua MQTT)
  final Map<String, int?> bleRssiByPrefix = {}; // cuong do song BLE (dBm, qua quet truc tiep)
  final Map<String, bool> runningByPrefix = {}; // dong co dang chay - dung de khoa nut NEXT nhanh
  // Dang quet/phuc hoi vi tri (vi tri THUC SU vo nghia luc nay) - dong bo
  // cung 1 tieu chi voi Giam Sat/Dieu Khien (t.isScanDone==false), xem
  // VanStatusChecker. Dung de hien "Đang quét" thay vi/che do tren the va
  // khoa nut NEXT nhanh, tranh gui lenh chac chan bi firmware tu choi.
  final Map<String, bool> scanningByPrefix = {};

  VanListProvider({required this.api}) {
    _statusChecker.onUpdate = _onStatusUpdate;
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      vans = await api.listVans();
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'Không tải được danh sách van.';
    } finally {
      loading = false;
      notifyListeners();
    }
    // [FIX] Tu dong kiem tra online/offline ngay khi danh sach van tai xong
    // (vao app/keo lam moi) - khong doi nguoi dung tu mo tung van moi biet.
    unawaited(startLiveStatus());
  }

  /// Bat dau (hoac khoi dong lai tu dau neu danh sach van thay doi) dich vu
  /// theo doi TRUC TIEP toan bo van trong danh sach - giu 1 ket noi MQTT
  /// DUNG CHUNG, LIEN TUC (xem VanStatusChecker) trong khi tab "Quan Ly Van"
  /// dang duoc CHON (goi tu MainShell.onDestinationSelected()). Khac ban cu
  /// (mo/dong ket noi tam thoi moi lan lam moi): gio la 1 NGUON TRANG THAI
  /// DUY NHAT, cap nhat gan-nhu-realtime, biet CHINH XAC van nao dang chay
  /// dong co de khoa nut NEXT nhanh, tranh nham lan trang thai giua nhieu
  /// van. BLE scan van chay SONG SONG (radio khac, khong xung dot).
  Future<void> startLiveStatus() async {
    if (vans.isEmpty) return;
    for (final v in vans) {
      onlineStatus[v.mqttPrefix] = VanOnlineStatus.checking;
    }
    notifyListeners();

    final cfg = await _prefsService.getMqttConfig();
    await _statusChecker.start(
      vans.map((v) => v.mqttPrefix).toList(),
      host: cfg['host'] as String,
      port: cfg['port'] as int,
      user: cfg['user'] as String,
      pass: cfg['pass'] as String,
    );
    unawaited(_scanBleRssi());
    _onStatusUpdate();
  }

  /// Dung dich vu theo doi truc tiep - goi khi roi khoi man hinh danh sach
  /// (mo dashboard 1 van cu the) de khong giu 2 ket noi MQTT song song toi
  /// cung 1 van (rieng cua dashboard + chung cua danh sach) khong can thiet.
  void stopLiveStatus() {
    _statusChecker.stop();
  }

  void _onStatusUpdate() {
    for (final entry in _statusChecker.results.entries) {
      onlineStatus[entry.key] = entry.value.online ? VanOnlineStatus.online : VanOnlineStatus.offline;
      posByPrefix[entry.key] = entry.value.pos;
      wifiRssiByPrefix[entry.key] = entry.value.wifiRssi;
      if (entry.value.running != null) runningByPrefix[entry.key] = entry.value.running!;
      if (entry.value.scanDone != null) scanningByPrefix[entry.key] = !entry.value.scanDone!;
    }
    notifyListeners();
  }

  /// Lam moi thu cong (keo-de-lam-moi tren man hinh danh sach) - neu dich vu
  /// truc tiep dang chay chi can gui lai PING/WIFI_STATUS? ngay (khong can
  /// doi chu ky 15s), neu chua chay (vd vua quay lai man hinh) thi khoi
  /// dong lai tu dau.
  Future<void> checkOnlineStatus() async {
    if (vans.isEmpty) return;
    if (!_statusChecker.isRunning) {
      await startLiveStatus();
    } else {
      _statusChecker.pollNow();
      unawaited(_scanBleRssi());
    }
  }

  /// Quet BLE 1 lan (~5s) de lay cuong do song CUA TUNG VAN dang phat quang
  /// ba gan do - khop ten quang ba BLE (chinh la mqttPrefix, xem
  /// computeDeviceTopics() ben firmware) voi tung van trong danh sach.
  Future<void> _scanBleRssi() async {
    bleRssiByPrefix.clear();
    try {
      final sub = _bleScanner.scan(timeout: const Duration(seconds: 5)).listen((r) {
        final name = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
        bleRssiByPrefix[name] = r.rssi;
      });
      await Future.delayed(const Duration(seconds: 5));
      await sub.cancel();
    } catch (_) {
      // Chua co quyen Bluetooth hoac thiet bi khong ho tro - bo qua, van
      // khong hien cuong do song BLE nhung khong lam hong phan MQTT.
    }
  }

  /// Gui lenh dieu khien NHANH (vd "NEXT") toi 1 van CU THE ngay tu danh
  /// sach - KHONG can mo dashboard day du. Dung LAI ket noi dung chung dang
  /// mo (xem VanStatusChecker.sendCommand()) - CHI gui duoc khi dich vu theo
  /// doi truc tiep dang chay (man hinh danh sach dang hien).
  Future<bool> sendQuickCommand(Van van, String cmd) async {
    return _statusChecker.sendCommand(van.mqttPrefix, cmd);
  }

  Future<bool> addVan({required String code, required String mqttPrefix, String? model, String? name}) async {
    error = null;
    try {
      final v = await api.addVan(code: code, mqttPrefix: mqttPrefix, model: model, name: name);
      vans = [v, ...vans];
      notifyListeners();
      // Khoi dong lai (khong chi poll) de dich vu theo doi TRUC TIEP subscribe
      // ca prefix moi vua them - checkOnlineStatus() cu se bo qua van nay vi
      // dich vu dang chay chi poll cac prefix DA subscribe tu truoc.
      unawaited(startLiveStatus());
      return true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      error = 'Không thêm được van.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteVan(int id) async {
    try {
      await api.deleteVan(id);
      vans = vans.where((v) => v.id != id).toList();
      notifyListeners();
      unawaited(startLiveStatus());
      return true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _statusChecker.stop();
    super.dispose();
  }
}
