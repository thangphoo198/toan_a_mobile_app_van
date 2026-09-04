// Chon MqttServerClient (native: Android/Windows/iOS/macOS/Linux, dung dart:io)
// hay MqttBrowserClient (Flutter Web, dung WebSocket cua trinh duyet) tuy nen
// tang bien dich - MqttServerClient KHONG chay duoc tren web (can dart:io).
export 'mqtt_client_creator_io.dart' if (dart.library.html) 'mqtt_client_creator_web.dart';
