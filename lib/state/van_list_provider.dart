import 'dart:async';

import 'package:flutter/foundation.dart';
import '../models/van.dart';
import '../services/api_service.dart';
import '../services/prefs_service.dart';
import '../services/van_status_checker.dart';

/// Trang thai online/offline cua 1 van trong danh sach "Van Cua Toi".
/// checking = dang kiem tra (vua vao app/vua bam lam moi), chua co ket qua.
enum VanOnlineStatus { checking, online, offline }

class VanListProvider extends ChangeNotifier {
  final ApiService api;
  final PrefsService _prefsService = PrefsService();
  final VanStatusChecker _statusChecker = VanStatusChecker();
  VanListProvider({required this.api});

  List<Van> vans = [];
  bool loading = false;
  String? error;

  // Trang thai online/offline theo mqttPrefix - hien icon o van_list_screen.
  // Khong dung Map<int,...> (id) vi id chi co sau khi load() xong, trong khi
  // mqttPrefix la khoa tu nhien va on dinh cua van.
  final Map<String, VanOnlineStatus> onlineStatus = {};

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
    unawaited(checkOnlineStatus());
  }

  /// Kiem tra online/offline cho TOAN BO van trong danh sach - mo 1 ket noi
  /// MQTT tam thoi dung chung (xem VanStatusChecker), KHONG anh huong ket noi
  /// rieng cua bat ky DashboardProvider nao dang mo.
  Future<void> checkOnlineStatus() async {
    if (vans.isEmpty) return;
    for (final v in vans) {
      onlineStatus[v.mqttPrefix] = VanOnlineStatus.checking;
    }
    notifyListeners();

    final cfg = await _prefsService.getMqttConfig();
    final result = await _statusChecker.checkAll(
      vans.map((v) => v.mqttPrefix).toList(),
      host: cfg['host'] as String,
      port: cfg['port'] as int,
      user: cfg['user'] as String,
      pass: cfg['pass'] as String,
    );

    for (final entry in result.entries) {
      onlineStatus[entry.key] = entry.value ? VanOnlineStatus.online : VanOnlineStatus.offline;
    }
    notifyListeners();
  }

  Future<bool> addVan({required String code, required String mqttPrefix, String? model, String? name}) async {
    error = null;
    try {
      final v = await api.addVan(code: code, mqttPrefix: mqttPrefix, model: model, name: name);
      vans = [v, ...vans];
      notifyListeners();
      unawaited(checkOnlineStatus());
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
      return true;
    } on ApiException catch (e) {
      error = e.message;
      notifyListeners();
      return false;
    }
  }
}
