import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import 'mqtt_client_creator.dart';

/// Kiem tra nhanh trang thai online/offline cua NHIEU van cung luc - dung
/// cho man hinh "Van Cua Toi" (tu dong check khi vao app, xem VanListProvider).
/// Mo 1 KET NOI MQTT TAM THOI DUNG CHUNG cho ca danh sach (khac voi
/// MqttService - moi dashboard rieng giu 1 ket noi LAU DAI), subscribe RIENG
/// topic status/telemetry/log theo TUNG prefix chinh xac (KHONG dung wildcard
/// cap 1 kieu "+/status" - broker nay dung CHUNG cho moi nguoi dung mac dinh
/// (hardcode 1 tai khoan MQTT trong ung dung), wildcard se nhan nham du lieu
/// van cua nguoi khac). Gui PING toi tung van roi cho phan hoi trong 1 khoang
/// thoi gian ngan - van nao khong tra loi gi trong thoi gian do coi la offline.
class VanStatusChecker {
  Future<Map<String, bool>> checkAll(
    List<String> mqttPrefixes, {
    required String host,
    required int port,
    required String user,
    required String pass,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final result = <String, bool>{for (final p in mqttPrefixes) p: false};
    if (mqttPrefixes.isEmpty) return result;

    final clientId = 'VAN_STATUS_${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final client = createMqttClient(host, clientId, port);
    client.logging(on: false);
    client.setProtocolV311();
    client.keepAlivePeriod = 30;
    client.autoReconnect = false;
    client.connectTimeoutPeriod = 6000;
    client.connectionMessage = MqttConnectMessage().withClientIdentifier(clientId).startClean();

    try {
      await client.connect(user, pass).timeout(
        Duration(milliseconds: client.connectTimeoutPeriod + 2000),
        onTimeout: () => null,
      );
    } catch (_) {
      client.disconnect();
      return result;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      return result;
    }

    for (final prefix in mqttPrefixes) {
      client.subscribe('$prefix/status', MqttQos.atMostOnce);
      client.subscribe('$prefix/telemetry', MqttQos.atMostOnce);
      client.subscribe('$prefix/log', MqttQos.atMostOnce);
    }

    // Hoan tat SOM neu MOI van deu da phan hoi - khong can cho het timeout.
    final completer = Completer<void>();
    final sub = client.updates?.listen((events) {
      for (final e in events) {
        final topic = e.topic;
        final slash = topic.indexOf('/');
        if (slash <= 0) continue;
        final prefix = topic.substring(0, slash);
        if (result.containsKey(prefix)) result[prefix] = true;
      }
      if (result.values.every((v) => v) && !completer.isCompleted) {
        completer.complete();
      }
    });

    for (final prefix in mqttPrefixes) {
      final builder = MqttClientPayloadBuilder();
      builder.addString('PING');
      client.publishMessage('$prefix/cmd', MqttQos.atMostOnce, builder.payload!);
    }

    await Future.any([completer.future, Future.delayed(timeout)]);

    await sub?.cancel();
    client.disconnect();
    return result;
  }
}
