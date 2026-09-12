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

/// [FIX] Doi ma model theo dong "van 4 met khoi" (van4m3): F021->F041,
/// F023->F043, 5021->S041, 5023->S043 - F021/F023/5021/5023 la ten CU, khong
/// con dung (xem CH32 firmware main.c/monitor.c - noi PHAT SINH chuoi nay,
/// app chi hien thi lai dung gia tri CH32 tra ve).
/// Van luu luong (co do flow) la F043/S043 (modelNum 1/3, 0-based tu MODEL=).
bool isFlowValveModel(String? modelCode) => modelCode == 'F043' || modelCode == 'S043';

/// Van 3 cua (F041/F043) - KHONG co buoc Hoan Nguyen/Bu Muoi rieng (chi danh
/// cho van 5 cua co binh muoi). Khop CHINH XAC firmware: motor3.c cycles
/// cus_pos CHI trong 1/2/3 (xem MAX_MODE3 trong control_motor.h), khac han
/// van 5 cua (motor5.c, cus_pos 1..5).
bool isThreePortModel(String? modelCode) => modelCode == 'F041' || modelCode == 'F043';

/// So vi tri (buoc) THAT SU co cua 1 model - dung de gioi han luoi GOTO/vong
/// tron vi tri o app, khop dung max_pos ben firmware (control_motor.c:
/// check_material_cycle(), van_set.c: max_allowed_pos, uart1_rx.c: GOTO).
int maxPositionsForModel(String? modelCode) => isThreePortModel(modelCode) ? 3 : 5;

/// Tra ve WaterMode DUNG cho 1 vi tri, co xet model. Van 3 cua chi co 3 buoc
/// xu ly: 1=Loc, 2=Rua Nguoc, 3=Rua Xuoi (buoc CUOI CUNG truoc khi ve Loc) -
/// KHONG co Hoan Nguyen(3)/Bu Muoi(4) nhu van 5 cua, vi khong co binh muoi de
/// hoan nguyen/bu muoi. Vi vay vi tri 3 tren van 3 cua mang Y NGHIA giong
/// vi tri 5 tren van 5 cua (buoc rua xuoi cuoi) - dung nhan/icon/mau cua
/// kWaterModes[5] cho no thay vi kWaterModes[3] ("Hoan Nguyen" sai hoan
/// toan trong ngu canh nay). Vi tri (GOTO target) VAN LA 3, chi nhan hien
/// thi doi - khop dung firmware (motor3.c KHONG BAO GIO gui pos=4/5).
WaterMode? modeForPosition(String? modelCode, int? pos) {
  if (pos == null) return null;
  if (isThreePortModel(modelCode) && pos == 3) return kWaterModes[5];
  return kWaterModes[pos];
}

/// --- BLE (khop CHINH XAC voi config.h ben firmware esp32c3_ota) ---
/// UUID 128-bit co dinh cua service/characteristic GATT - xem ble_manager.ino.
const String kBleServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
const String kBleCmdCharUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // App -> ESP32 (Write)
const String kBleTxCharUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // ESP32 -> App (Notify)
/// [NEW] Characteristic RIENG nhan du lieu NHI PHAN (goi firmware .bin) khi
/// truyen firmware qua Bluetooth (BLEFLASH:/BLEFLASH_END tren kenh lenh text
/// - xem BleService.sendFirmwareOverBle()).
const String kBleFileCharUuid = '6e400004-b5a3-f393-e0a9-e50e24dcca9e'; // App -> ESP32 (Write co response)
/// Ma PIN dung chung xac thuc BLE - PHAI khop BLE_AUTH_PIN trong config.h.
const String kBleAuthPin = '246813';
/// Ten quang ba BLE cua van luon bat dau bang tien to nay (= devicePrefix ben
/// firmware, vd "van_e6ebac") - dung de loc ket qua scan.
const String kBleNamePrefix = 'van_';

/// --- AP cuc bo cua ESP32 (khop CHINH XAC esp32c3_ota.ino) ---
/// [NEW] Dung cho luong "Nap ESP32 qua AP" (ota_tab.dart) - nap qua BLE qua
/// cham de dung duoc thuc te (da tat, xem ble_manager.ino "[DISABLED - NGHIEN
/// CUU]"), thay bang huong dan nguoi dung tu chuyen WiFi dien thoai sang AP
/// nay de nap qua mang LAN cuc bo (nhanh hon nhieu).
/// [FIX] KHONG con ten/mat khau CO DINH dung chung nua - AP gio dung TRUC
/// TIEP devicePrefix (= van.mqttPrefix ben app, vd "van_e6ebac") lam ten, VA
/// la mang MO (khong mat khau) - xem van.mqttPrefix truc tiep tai noi hien
/// huong dan (ota_tab.dart) thay vi hang so ten co dinh o day.
/// Dia chi gateway mac dinh cua ESP32 softAP (ESP32 Arduino core khong doi
/// tuy chinh dia chi nay o dau trong code) - noi endpoint /upload_esp_ota
/// (web_server.ino) lang nghe khi dien thoai da ket noi vao AP tren.
const String kApGatewayHost = '192.168.4.1';
