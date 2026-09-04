import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import 'mqtt_client_creator.dart';

/// Boc MqttClient qua WebSocket - tuong duong connectMqtt()/publishMqttCmd()
/// trong web_client_mqtt.html. Moi van dang mo dashboard co 1 instance rieng.
/// Client cu the (MqttServerClient tren native, MqttBrowserClient tren web)
/// duoc chon boi createMqttClient() - xem mqtt_client_creator.dart.
class MqttService {
  MqttClient? _client;
  StreamSubscription? _updatesSub;

  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<bool> connect({
    required String host,
    required int port,
    required String username,
    required String password,
    required String topicPrefix,
    required void Function(String topic, String payload) onMessage,
    required void Function() onConnected,
    required void Function() onDisconnected,
  }) async {
    await disconnect();

    final clientId = 'VAN_APP_${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final client = createMqttClient(host, clientId, port);
    client.logging(on: false);
    client.setProtocolV311();
    client.keepAlivePeriod = 30;
    client.autoReconnect = true;
    client.connectTimeoutPeriod = 8000;
    client.onDisconnected = onDisconnected;
    client.onConnected = onConnected;

    // KHONG goi .withWillQos() - khong dung Last Will/Testament trong app nay.
    // Goi no ma khong dat willTopic/willMessage se tao goi CONNECT vi pham
    // spec MQTT 3.1.1 (WillFlag=false nhung WillQos != 0), khien Mosquitto
    // dong ket noi ngay sau khi nhan duoc CONNECT ma khong tra CONNACK - da
    // xac minh bang client.logging(on: true): "websocket is closed" xuat
    // hien ngay sau "sending connect message" khi con dong nay.
    final connMess = MqttConnectMessage().withClientIdentifier(clientId).startClean();
    client.connectionMessage = connMess;

    _client = client;

    try {
      await client.connect(username, password).timeout(
        Duration(milliseconds: client.connectTimeoutPeriod + 2000),
        onTimeout: () => null,
      );
    } catch (_) {
      client.disconnect();
      _client = null;
      return false;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      _client = null;
      return false;
    }

    client.subscribe('$topicPrefix/#', MqttQos.atMostOnce);

    _updatesSub = client.updates?.listen((events) {
      for (final e in events) {
        final recMess = e.payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        onMessage(e.topic, payload);
      }
    });

    return true;
  }

  void publish(String topic, String message) {
    final client = _client;
    if (client == null || client.connectionStatus?.state != MqttConnectionState.connected) return;
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    client.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);
  }

  Future<void> disconnect() async {
    await _updatesSub?.cancel();
    _updatesSub = null;
    // Go callback truoc khi disconnect: day la lan ngat KET NOI CHU DONG (vd
    // DashboardProvider.dispose() khi dong man hinh) - khong can bao ai nua,
    // va callback co the fire SAU KHI provider phia tren da dispose() xong
    // (da gap that: "A DashboardProvider was used after being disposed" khi
    // Android kill process cu luc cai de APK moi), gay crash goi
    // notifyListeners() tren ChangeNotifier da disposed.
    _client?.onDisconnected = null;
    _client?.onConnected = null;
    _client?.disconnect();
    _client = null;
  }
}
