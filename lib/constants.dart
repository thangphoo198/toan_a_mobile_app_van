import 'package:flutter/material.dart';

class WaterMode {
  final String name;
  final String sub;
  final String icon;
  final Color color;
  const WaterMode(this.name, this.sub, this.icon, this.color);
}

/// 5 che do xu ly nuoc - khop WATER_MODES trong web_client_mqtt.html.
const Map<int, WaterMode> kWaterModes = {
  1: WaterMode('Chế Độ Lọc', 'Filter Service Mode', '⏳', Color(0xFF29B6F6)),
  2: WaterMode('Rửa Ngược', 'Backwash Mode', '🔄', Color(0xFFFBBF24)),
  3: WaterMode('Hoàn Nguyên', 'Regeneration Mode', '🧪', Color(0xFFC084FC)),
  4: WaterMode('Bù Muối', 'Brine Refill Mode', '🧂', Color(0xFFF472B6)),
  5: WaterMode('Rửa Xuôi', 'Fast Rinse Mode', '🌊', Color(0xFF4ADE80)),
};

/// Van luu luong (co do flow) la F023/5023 (modelNum 1/3, 0-based tu MODEL=).
bool isFlowValveModel(String? modelCode) => modelCode == 'F023' || modelCode == '5023';

/// --- BLE (khop CHINH XAC voi config.h ben firmware esp32c3_ota) ---
/// UUID 128-bit co dinh cua service/characteristic GATT - xem ble_manager.ino.
const String kBleServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String kBleCmdCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // App -> ESP32 (Write)
const String kBleTxCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // ESP32 -> App (Notify)
/// Ma PIN dung chung xac thuc BLE - PHAI khop BLE_AUTH_PIN trong config.h.
const String kBleAuthPin = '246813';
/// Ten quang ba BLE cua van luon bat dau bang tien to nay (= devicePrefix ben
/// firmware, vd "van_e6ebac") - dung de loc ket qua scan.
const String kBleNamePrefix = 'van_';
