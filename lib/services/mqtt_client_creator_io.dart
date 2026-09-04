import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Tao MqttClient cho nen tang native (Android/Windows/iOS/macOS/Linux) -
/// dung MqttServerClient (dart:io WebSocket).
MqttClient createMqttClient(String host, String clientId, int port) {
  final client = MqttServerClient('ws://$host/mqtt', clientId);
  client.useWebSocket = true;
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  client.port = port;
  return client;
}
