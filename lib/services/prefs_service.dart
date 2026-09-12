import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Boc SharedPreferences - tuong duong localStorage cua web client.
class PrefsService {
  static const _kToken = 'van_auth_token';
  static const _kUser = 'van_auth_user';
  static const _kMqttHost = 'mqtt_host';
  static const _kMqttPort = 'mqtt_port';
  static const _kMqttUser = 'mqtt_user';
  static const _kMqttPass = 'mqtt_pass';
  static const _kThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'

  Future<String?> getToken() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kToken);
  }

  Future<void> setToken(String token) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
  }

  Future<void> clearToken() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kUser);
  }

  Future<Map<String, dynamic>?> getUser() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kUser);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> setUser(Map<String, dynamic> user) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUser, jsonEncode(user));
  }

  // --- Cau hinh MQTT broker (mac dinh khop voi web client) ---
  // [FIX] host/port mac dinh gio la domain HTTPS (toana.cloud:443, qua proxy
  // /mqtt cua nginx - dung wss:// khong con cleartext, xem
  // mqtt_client_creator_io/web.dart) thay vi IP:9001 truoc day. Neu thiet bi
  // da tung LUU (setMqttConfig()) gia tri IP cu tu ban cai truoc, "chua" lai
  // ve mac dinh moi - gia tri cu gio da hong (Mosquitto khong con TLS truc
  // tiep tren cong 9001).
  Future<Map<String, dynamic>> getMqttConfig() async {
    final p = await SharedPreferences.getInstance();
    var host = p.getString(_kMqttHost) ?? 'toana.cloud';
    var port = p.getInt(_kMqttPort) ?? 443;
    if (host == '103.143.207.89') {
      host = 'toana.cloud';
      port = 443;
    }
    return {
      'host': host,
      'port': port,
      'user': p.getString(_kMqttUser) ?? 'thangpro1998',
      'pass': p.getString(_kMqttPass) ?? 'thang123',
    };
  }

  Future<void> setMqttConfig({
    required String host,
    required int port,
    required String user,
    required String pass,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMqttHost, host);
    await p.setInt(_kMqttPort, port);
    await p.setString(_kMqttUser, user);
    await p.setString(_kMqttPass, pass);
  }

  // --- Giao dien sang/toi ---
  Future<String> getThemeMode() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kThemeMode) ?? 'system';
  }

  Future<void> setThemeMode(String mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kThemeMode, mode);
  }

  // --- Thiet bi BLE da ghep noi cho tung van (key theo mqttPrefix) - de lan
  // sau mo dashboard co the tu ket noi lai BLE lam kenh du phong khi mat MQTT,
  // khong can quet lai tu dau. Luu remoteId (MAC tren Android) cua thiet bi.
  Future<String?> getBleDeviceId(String mqttPrefix) async {
    final p = await SharedPreferences.getInstance();
    return p.getString('ble_device_$mqttPrefix');
  }

  Future<void> setBleDeviceId(String mqttPrefix, String deviceId) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ble_device_$mqttPrefix', deviceId);
  }
}
