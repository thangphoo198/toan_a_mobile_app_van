import 'package:flutter/foundation.dart';
import '../models/van.dart';
import '../services/api_service.dart';

class VanListProvider extends ChangeNotifier {
  final ApiService api;
  VanListProvider({required this.api});

  List<Van> vans = [];
  bool loading = false;
  String? error;

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
  }

  Future<bool> addVan({required String code, required String mqttPrefix, String? model, String? name}) async {
    error = null;
    try {
      final v = await api.addVan(code: code, mqttPrefix: mqttPrefix, model: model, name: name);
      vans = [v, ...vans];
      notifyListeners();
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
