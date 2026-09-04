import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/van.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Boc REST API cua backend (FastAPI tai http://103.143.207.89/api).
/// Endpoint va contract khop 1:1 voi login.html/vans.html.
class ApiService {
  static const String baseUrl = 'http://103.143.207.89/api';

  String? _token;

  void setToken(String? token) => _token = token;

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<Map<String, dynamic>> _postJson(String path, Map<String, dynamic> body, {bool auth = false}) async {
    final res = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: auth ? _authHeaders : {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final data = _decode(res.body);
    if (res.statusCode >= 400) {
      throw ApiException(data['detail']?.toString() ?? 'Yêu cầu thất bại (${res.statusCode})');
    }
    return data;
  }

  Map<String, dynamic> _decode(String body) {
    if (body.isEmpty) return {};
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : {'value': v};
    } catch (_) {
      return {};
    }
  }

  Future<({String token, Map<String, dynamic> user})> login(String username, String password) async {
    final data = await _postJson('/auth/login', {'username': username, 'password': password});
    return (token: data['access_token'] as String, user: data['user'] as Map<String, dynamic>);
  }

  Future<void> register(String username, String password, String? email) async {
    await _postJson('/auth/register', {'username': username, 'password': password, 'email': email});
  }

  Future<Map<String, dynamic>> me() async {
    final res = await http.get(Uri.parse('$baseUrl/auth/me'), headers: _authHeaders);
    final data = _decode(res.body);
    if (res.statusCode >= 400) throw ApiException(data['detail']?.toString() ?? 'Phiên đăng nhập hết hạn');
    return data;
  }

  Future<void> logout() async {
    try {
      await http.post(Uri.parse('$baseUrl/auth/logout'), headers: _authHeaders);
    } catch (_) {
      // Bo qua loi mang - van xoa token cuc bo phia AuthProvider
    }
  }

  Future<List<Van>> listVans() async {
    final res = await http.get(Uri.parse('$baseUrl/vans'), headers: _authHeaders);
    if (res.statusCode >= 400) {
      throw ApiException(_decode(res.body)['detail']?.toString() ?? 'Không tải được danh sách van');
    }
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Van.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Van> addVan({required String code, required String mqttPrefix, String? model, String? name}) async {
    final data = await _postJson(
      '/vans',
      {'code': code, 'mqtt_prefix': mqttPrefix, 'model': model, 'name': name},
      auth: true,
    );
    return Van.fromJson(data);
  }

  Future<void> deleteVan(int id) async {
    final res = await http.delete(Uri.parse('$baseUrl/vans/$id'), headers: _authHeaders);
    if (res.statusCode >= 400) {
      throw ApiException(_decode(res.body)['detail']?.toString() ?? 'Không xoá được van');
    }
  }
}
