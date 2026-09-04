import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/prefs_service.dart';

enum AuthStatus { unknown, loggedOut, loggedIn }

class AuthProvider extends ChangeNotifier {
  final ApiService api;
  final PrefsService prefs;

  AuthProvider({required this.api, required this.prefs});

  AuthStatus status = AuthStatus.unknown;
  Map<String, dynamic>? user;
  String? error;
  bool busy = false;

  /// Goi luc app khoi dong - giong checkExistingSession() trong login.html:
  /// neu con token hop le trong SharedPreferences thi bo qua man dang nhap.
  Future<void> tryRestoreSession() async {
    final token = await prefs.getToken();
    if (token == null) {
      status = AuthStatus.loggedOut;
      notifyListeners();
      return;
    }
    api.setToken(token);
    try {
      final me = await api.me();
      user = me;
      status = AuthStatus.loggedIn;
    } catch (_) {
      await prefs.clearToken();
      api.setToken(null);
      status = AuthStatus.loggedOut;
    }
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await api.login(username, password);
      api.setToken(result.token);
      await prefs.setToken(result.token);
      await prefs.setUser(result.user);
      user = result.user;
      status = AuthStatus.loggedIn;
      return true;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } catch (_) {
      error = 'Không kết nối được tới máy chủ. Thử lại sau.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> register(String username, String password, String? email) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await api.register(username, password, email);
      return await login(username, password);
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } catch (_) {
      error = 'Không kết nối được tới máy chủ. Thử lại sau.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await api.logout();
    await prefs.clearToken();
    api.setToken(null);
    user = null;
    status = AuthStatus.loggedOut;
    notifyListeners();
  }
}
