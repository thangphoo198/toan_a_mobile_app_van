import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Tao MqttClient cho nen tang native (Android/Windows/iOS/macOS/Linux) -
/// dung MqttServerClient (dart:io WebSocket).
/// [FIX] wss:// (khong con ws:// cleartext) - ket noi qua proxy /mqtt cua
/// nginx tren domain toana.cloud (dung chung chung chi TLS voi REST API),
/// KHONG con ket noi thang toi IP:9001 cua Mosquitto nhu truoc. Bat buoc
/// phai the de bo duoc "android:usesCleartextTraffic" trong AndroidManifest
/// (yeu cau chinh sach du lieu nhay cam cua Google Play, va Apple ATS chan
/// cung cleartext tren iOS neu sau nay build).
MqttClient createMqttClient(String host, String clientId, int port) {
  final client = MqttServerClient('wss://$host/mqtt', clientId);
  client.useWebSocket = true;
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  client.port = port;
  return client;
}
