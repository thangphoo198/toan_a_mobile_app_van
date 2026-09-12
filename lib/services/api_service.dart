import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants.dart';
import '../models/van.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Boc REST API cua backend (FastAPI tai https://toana.cloud/api - domain +
/// HTTPS tu Let's Encrypt, xem app.py). [FIX] Truoc day dung IP tran qua HTTP
/// - Google Play/Apple deu coi day la rui ro bao mat (du lieu nhay cam nhu
/// mat khau/token dang truyen khong ma hoa), Apple con CHAN CUNG (ATS) neu
/// sau nay build iOS. Nginx tren server da chuyen HTTP->HTTPS (redirect), va
/// IP tran gio KHONG con dung duoc nua (tra 404) - PHAI dung domain nay.
/// Endpoint va contract khop 1:1 voi login.html/vans.html.
class ApiService {
  static const String baseUrl = 'https://toana.cloud/api';

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

  Future<void> register(String username, String password, String fullName, String phone, String? email) async {
    await _postJson('/auth/register', {
      'username': username,
      'password': password,
      'full_name': fullName,
      'phone': phone,
      'email': email,
    });
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

  /// Chia se 1 van (CHI chu so huu goi duoc) cho nguoi dung khac (ten dang
  /// nhap hoac so dien thoai). Goi lai voi cung nguoi se CAP NHAT quyen
  /// (upsert phia backend) thay vi bao loi "da chia se roi".
  Future<void> shareVan(int vanId, String usernameOrPhone, {bool canControl = true, bool canConfigure = false}) async {
    await _postJson(
      '/vans/$vanId/share',
      {'username_or_phone': usernameOrPhone, 'can_control': canControl, 'can_configure': canConfigure},
      auth: true,
    );
  }

  /// Danh sach nguoi dang duoc chia se 1 van (chi chu so huu xem duoc).
  Future<List<Map<String, dynamic>>> listVanShares(int vanId) async {
    final res = await http.get(Uri.parse('$baseUrl/vans/$vanId/shares'), headers: _authHeaders);
    if (res.statusCode >= 400) {
      throw ApiException(_decode(res.body)['detail']?.toString() ?? 'Không tải được danh sách chia sẻ');
    }
    return (jsonDecode(res.body) as List).cast<Map<String, dynamic>>();
  }

  /// Thu hoi 1 luot chia se - chu so huu goi voi userId cua nguoi bi thu hoi,
  /// hoac chinh nguoi duoc chia se tu goi voi userId = chinh minh de "roi van".
  Future<void> revokeVanShare(int vanId, int userId) async {
    final res = await http.delete(Uri.parse('$baseUrl/vans/$vanId/share/$userId'), headers: _authHeaders);
    if (res.statusCode >= 400) {
      throw ApiException(_decode(res.body)['detail']?.toString() ?? 'Không thực hiện được thao tác này');
    }
  }

  /// Firmware MOI NHAT da co trong kho (do admin quan ly qua trang web) cho
  /// 1 loai chip - dung de tu dong/thu cong kiem tra "co ban moi khong"
  /// (xem ota_tab.dart). Endpoint nay CONG KHAI (khong can Bearer token) -
  /// ban than file .bin da la URL cong khai san roi. Tra ve null neu chua co
  /// firmware nao cho loai chip do, hoac neu loi mang (khong nem loi, tab
  /// Cap Nhat chi don gian hien "chua kiem tra duoc" thay vi crash).
  Future<Map<String, dynamic>?> getLatestFirmware(String target) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/firmware/latest?target=$target'));
      if (res.statusCode >= 400) return null;
      final data = _decode(res.body);
      return data.isEmpty ? null : data;
    } catch (_) {
      return null;
    }
  }

  /// [NEW] Tai NGUYEN FILE nhi phan (.bin) tu URL kho firmware - dung MANG
  /// RIENG CUA DIEN THOAI (khong lien quan gi den ket noi cua van), phuc vu
  /// luong "nap qua Bluetooth khi van mat mang": dien thoai tu tai file nay
  /// roi day sang van qua BLE (xem DashboardProvider.sendFirmwareOverBle()).
  /// Tra ve null neu loi mang/HTTP - KHONG nem loi de UI tu hien thong bao.
  Future<List<int>?> downloadFirmwareBytes(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode >= 400) return null;
      return res.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// [NEW] Nap firmware ESP32 THANG qua mang LAN cuc bo cua chinh van - thay
  /// the cho duong truyen qua Bluetooth (da tat vi qua cham voi file .bin cỡ
  /// ~1-2MB, xem ble_manager.ino "[DISABLED - NGHIEN CUU]"). Dieu kien: dien
  /// thoai phai da CHUYEN WiFi sang AP cua van (SSID kApSsid/config.h AP_SSID
  /// - nguoi dung tu bat qua lenh AP_ON, tu chon mang trong Cai Dat WiFi cua
  /// dien thoai, xem ota_tab.dart) TRUOC khi goi ham nay. Dung endpoint
  /// /upload_esp_ota co san tren chinh ESP32 (web_server.ino) - multipart
  /// upload y het duong Web cuc bo da co tu truoc, chi khac la app tu lam
  /// thay vi nguoi dung mo trinh duyet. Nem ApiException neu that bai (vd
  /// dien thoai chua thuc su noi vao dung mang, hoac ESP32 tu choi ghi).
  Future<void> uploadEspOtaViaLocalAp(
    List<int> bytes, {
    String host = kApGatewayHost,
  }) async {
    final uri = Uri.parse('http://$host/upload_esp_ota');
    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(http.MultipartFile.fromBytes('firmware', bytes, filename: 'esp32_ota.bin'));
      final streamed = await request.send().timeout(const Duration(seconds: 90));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode >= 400) {
        throw ApiException('Nạp thất bại (mã lỗi ${res.statusCode}).');
      }
      final data = _decode(res.body);
      if (data['error'] == true) {
        throw ApiException(data['message']?.toString() ?? 'Cập nhật ESP32 thất bại.');
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        'Không kết nối được tới van qua WiFi ($host) - kiểm tra điện thoại đã kết nối đúng mạng WiFi của van chưa.',
      );
    }
  }
}
