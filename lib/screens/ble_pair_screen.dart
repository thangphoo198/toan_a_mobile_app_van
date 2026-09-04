import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import '../models/telemetry_state.dart';
import '../models/van.dart';
import '../services/ble_service.dart';
import '../services/prefs_service.dart';
import '../services/telemetry_parser.dart';
import '../state/van_list_provider.dart';
import '../widgets/common.dart';

enum _Step { scanning, connecting, deviceInfo, wifiSetup, addVan }

/// Ghép nối van mới qua Bluetooth (BLE) - không cần biết trước mã
/// mqtt_prefix, không cần join AP thủ công để cấu hình WiFi. Xem
/// ble_manager.ino bên firmware esp32c3_ota cho giao thức tương ứng.
class BlePairScreen extends StatefulWidget {
  const BlePairScreen({super.key});

  @override
  State<BlePairScreen> createState() => _BlePairScreenState();
}

class _BlePairScreenState extends State<BlePairScreen> {
  _Step _step = _Step.scanning;
  StreamSubscription<ScanResult>? _scanSub;
  final Map<String, ScanResult> _found = {};

  final _ble = BleService();
  late final TelemetryState _info;
  late final TelemetryParser _infoParser;
  StreamSubscription? _bleLinesSub;

  String? _connectingName;
  String? _error;

  // WiFi setup
  bool _wifiScanning = false;
  String? _selectedSsid;
  final _wifiPassCtrl = TextEditingController();
  bool _wifiConnecting = false;
  String? _wifiError;

  // Add van form
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String? _model;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _info = TelemetryState();
    _infoParser = TelemetryParser(_info);
    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _bleLinesSub?.cancel();
    _ble.dispose();
    _wifiPassCtrl.dispose();
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _startScan() {
    _found.clear();
    setState(() => _step = _Step.scanning);
    _scanSub?.cancel();
    _scanSub = _ble.scan(timeout: const Duration(seconds: 10)).listen((r) {
      setState(() => _found[r.device.remoteId.str] = r);
    });
  }

  Future<void> _connectTo(ScanResult r) async {
    await _ble.stopScan();
    await _scanSub?.cancel();
    setState(() {
      _step = _Step.connecting;
      _connectingName = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
      _error = null;
    });

    final connected = await _ble.connectDevice(r.device);
    if (!connected) {
      setState(() {
        _error = 'Không kết nối được tới thiết bị. Thử lại?';
        _step = _Step.scanning;
      });
      return;
    }

    final authed = await _ble.authenticate();
    if (!authed) {
      await _ble.disconnect();
      setState(() {
        _error = 'Xác thực Bluetooth thất bại (sai mã PIN firmware?).';
        _step = _Step.scanning;
      });
      return;
    }

    _bleLinesSub = _ble.lines.listen((line) => _infoParser.parse(line));
    await _ble.writeCommand('ESP_INFO?');
    await _ble.writeCommand('PING'); // lay them ##MCU## de goi y model van
    await Future.delayed(const Duration(milliseconds: 1200));

    if (!mounted) return;
    _codeCtrl.text = _info.espMqttPrefix ?? '';
    if (_info.mcuVan != null && Van.modelLabels.containsKey(_info.mcuVan)) {
      _model = _info.mcuVan;
    }
    setState(() => _step = _Step.deviceInfo);
  }

  Future<void> _scanWifi() async {
    setState(() {
      _wifiScanning = true;
      _wifiError = null;
    });
    await _ble.writeCommand('WIFI_SCAN');
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    setState(() => _wifiScanning = false);
  }

  Future<void> _connectWifi() async {
    if (_selectedSsid == null || _selectedSsid!.isEmpty) return;
    setState(() {
      _wifiConnecting = true;
      _wifiError = null;
    });
    await _ble.writeCommand('WIFI_CONNECT:$_selectedSsid|${_wifiPassCtrl.text}');

    // Poll WIFI_STATUS? toi da ~15s cho staConnected=true (giong wifi_manager.ino
    // xu ly WIFI_CONNECT: khong dong bo, phai hoi lai de biet ket qua).
    bool ok = false;
    for (var i = 0; i < 8; i++) {
      await Future.delayed(const Duration(milliseconds: 2000));
      if (!mounted) return;
      await _ble.writeCommand('WIFI_STATUS?');
      await Future.delayed(const Duration(milliseconds: 400));
      if (_info.wifiStaConnected == true) {
        ok = true;
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _wifiConnecting = false;
      if (!ok) _wifiError = 'Van chưa lên được WiFi. Kiểm tra lại mật khẩu hoặc thử lại.';
    });
    if (ok) setState(() => _step = _Step.addVan);
  }

  Future<void> _saveVan() async {
    if (_codeCtrl.text.trim().isEmpty) {
      showSnack(context, 'Vui lòng nhập mã van.', isError: true);
      return;
    }
    setState(() => _saving = true);
    final provider = context.read<VanListProvider>();
    final ok = await provider.addVan(
      code: _codeCtrl.text.trim(),
      mqttPrefix: _codeCtrl.text.trim(),
      model: _model,
      name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      showSnack(context, provider.error ?? 'Không thêm được van.', isError: true);
      return;
    }
    final deviceId = _ble.connectedDeviceId;
    if (deviceId != null) {
      await PrefsService().setBleDeviceId(_codeCtrl.text.trim(), deviceId);
    }
    if (!mounted) return;
    final offlineOnly = _info.wifiStaConnected != true;
    showSnack(
      context,
      offlineOnly
          ? 'Đã thêm van (chế độ offline qua Bluetooth) - mở van để điều khiển/giám sát khi ở gần.'
          : 'Đã ghép nối và thêm van thành công!',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ghép Nối Qua Bluetooth')),
      body: switch (_step) {
        _Step.scanning => _buildScanning(),
        _Step.connecting => _buildConnecting(),
        _Step.deviceInfo => _buildDeviceInfo(),
        _Step.wifiSetup => _buildWifiSetup(),
        _Step.addVan => _buildAddVan(),
      },
    );
  }

  Widget _buildScanning() {
    final devices = _found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    return RefreshIndicator(
      onRefresh: () async => _startScan(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null) ...[
            SectionCard(
              title: 'Lỗi',
              icon: Icons.error_outline,
              children: [Text(_error!, style: const TextStyle(color: Colors.red))],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Text('Đang quét van gần đây qua Bluetooth...', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 16),
          if (devices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('Chưa tìm thấy van nào. Đảm bảo van đã bật nguồn và ở gần điện thoại.')),
            )
          else
            ...devices.map((r) {
              final name = r.advertisementData.advName.isNotEmpty ? r.advertisementData.advName : r.device.platformName;
              return Card(
                child: ListTile(
                  leading: Icon(_rssiIcon(r.rssi), color: Theme.of(context).colorScheme.primary),
                  title: Text(name.isEmpty ? '(Không tên)' : name),
                  subtitle: Text('Tín hiệu: ${r.rssi} dBm'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _connectTo(r),
                ),
              );
            }),
        ],
      ),
    );
  }

  IconData _rssiIcon(int rssi) {
    if (rssi >= -60) return Icons.signal_cellular_alt;
    if (rssi >= -75) return Icons.signal_cellular_alt_2_bar;
    return Icons.signal_cellular_alt_1_bar;
  }

  Widget _buildConnecting() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Đang kết nối tới ${_connectingName ?? "van"}...'),
        ],
      ),
    );
  }

  Widget _buildDeviceInfo() {
    final hasWifi = _info.wifiStaConnected == true;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: 'Thông Tin Van',
          icon: Icons.water_drop,
          children: [
            statGrid([
              StatBox(label: 'Mã / Prefix MQTT', value: _info.espMqttPrefix ?? '--'),
              StatBox(label: 'Firmware ESP32', value: _info.espFw ?? '--'),
              StatBox(label: 'Model Van', value: _model != null ? (Van.modelLabels[_model!] ?? _model!) : 'Chưa xác định'),
            ]),
          ],
        ),
        const SizedBox(height: 12),
        SectionCard(
          title: 'Trạng Thái WiFi',
          icon: Icons.wifi,
          trailing: StatusPill(
            text: hasWifi ? '🟢 ĐÃ CÓ WIFI' : '⚪ CHƯA CÓ WIFI',
            color: hasWifi ? Colors.green : Colors.orange,
          ),
          children: [
            if (hasWifi) Text('Đang kết nối: ${_info.wifiStaSSID ?? "--"}') else const Text('Van chưa được cấu hình WiFi. Bấm "Cài Đặt WiFi" để tiếp tục.'),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () {
            if (hasWifi) {
              setState(() => _step = _Step.addVan);
            } else {
              setState(() => _step = _Step.wifiSetup);
              _scanWifi();
            }
          },
          icon: Icon(hasWifi ? Icons.arrow_forward : Icons.wifi),
          label: Text(hasWifi ? 'Tiếp Tục Thêm Van' : 'Cài Đặt WiFi'),
        ),
        if (!hasWifi) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _step = _Step.addVan),
            icon: const Icon(Icons.bluetooth),
            label: const Text('Bỏ qua, chỉ dùng offline qua Bluetooth'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Không cần Internet - điều khiển/giám sát được khi điện thoại ở gần van qua Bluetooth. Có thể cài WiFi sau trong tab Cài Đặt ESP32.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWifiSetup() {
    final networks = _info.wifiScanResults;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: Text('Chọn mạng WiFi cho van', style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
              icon: _wifiScanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
              onPressed: _wifiScanning ? null : _scanWifi,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (networks.isEmpty && !_wifiScanning) const Text('Chưa có kết quả quét. Bấm nút làm mới.'),
        ...networks.map((n) => Card(
              child: RadioListTile<String>(
                value: n.ssid,
                groupValue: _selectedSsid,
                onChanged: (v) => setState(() => _selectedSsid = v),
                title: Text(n.ssid),
                secondary: Icon(n.secure ? Icons.lock_outline : Icons.lock_open, size: 18),
                subtitle: Text('${n.rssi} dBm'),
              ),
            )),
        const SizedBox(height: 16),
        TextField(
          controller: _wifiPassCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Mật khẩu WiFi', prefixIcon: Icon(Icons.password)),
        ),
        const SizedBox(height: 16),
        if (_wifiError != null) ...[
          Text(_wifiError!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
        ],
        FilledButton.icon(
          onPressed: (_selectedSsid == null || _wifiConnecting) ? null : _connectWifi,
          icon: _wifiConnecting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.wifi),
          label: Text(_wifiConnecting ? 'Đang kết nối...' : 'Kết Nối WiFi Cho Van'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _wifiConnecting ? null : () => setState(() => _step = _Step.addVan),
          icon: const Icon(Icons.bluetooth),
          label: const Text('Bỏ qua, chỉ dùng offline qua Bluetooth'),
        ),
      ],
    );
  }

  Widget _buildAddVan() {
    final offlineOnly = _info.wifiStaConnected != true;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Xác nhận thêm van', style: Theme.of(context).textTheme.titleMedium),
        if (offlineOnly) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.bluetooth, color: Colors.orange),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Van chưa có WiFi - chỉ điều khiển/giám sát được khi điện thoại ở gần qua Bluetooth. Có thể cài WiFi sau.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(controller: _codeCtrl, decoration: const InputDecoration(labelText: 'Mã van / MQTT Prefix')),
        const SizedBox(height: 10),
        TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Tên hiển thị (tuỳ chọn)')),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _model,
          decoration: const InputDecoration(labelText: 'Model van (tuỳ chọn)'),
          items: Van.modelLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) => setState(() => _model = v),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _saveVan,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check),
          label: Text(_saving ? 'Đang lưu...' : 'Thêm Van Vào Tài Khoản'),
        ),
      ],
    );
  }
}
