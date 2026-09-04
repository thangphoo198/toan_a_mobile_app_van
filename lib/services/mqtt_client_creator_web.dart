import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

/// Tao MqttClient cho Flutter Web - dung MqttBrowserClient (WebSocket cua
/// trinh duyet, khong can dart:io). Chi ho tro WebSocket (dung nhu broker
/// dang dung), khong can bat useWebSocket rieng nhu MqttServerClient.
MqttClient createMqttClient(String host, String clientId, int port) {
  final client = MqttBrowserClient('ws://$host/mqtt', clientId);
  client.port = port;
  // QUAN TRONG: mac dinh MqttBrowserClient chao nhieu WS sub-protocol
  // (protocolsMultipleDefault) - Mosquitto chi chap nhan dung 1 gia tri
  // "mqtt" duy nhat, neu khong se dong socket ngay sau khi nhan goi
  // CONNECT (khong bao gio tra ve CONNACK). Da xac minh bang cach bat
  // client.logging(on: true) va thay "websocket is closed" xuat hien
  // ngay sau "sending connect message" khi chua sua dong nay.
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  return client;
}
