import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../state/dashboard_provider.dart';
import '../../widgets/common.dart';

class EspSettingsTab extends StatefulWidget {
  const EspSettingsTab({super.key});

  @override
  State<EspSettingsTab> createState() => _EspSettingsTabState();
}

class _EspSettingsTabState extends State<EspSettingsTab> {
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  @override
  void dispose() {
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// [FIX] Truoc day moi nut trong tab nay (Quet WiFi, Ket Noi, Ngat Ket
  /// Noi, AP_ON/OFF, Doc Lai ESP_INFO) goi thang prov.publish() - khong
  /// kiem tra ket noi, khong co phan hoi truc quan nao (khong SnackBar, khong
  /// rung) - bam ma mat ket noi thi hoan toan im lang, tuong app dung/lag.
  /// Dung chung 1 ham nhu van_settings_tab.dart de bao ve VA phan hoi dong
  /// nhat cho tat ca cac nut trong tab nay.
  void _publish(BuildContext context, String cmd, [String? confirmMsg]) {
    final prov = context.read<DashboardProvider>();
    if (prov.isConnectionStale) {
      HapticFeedback.heavyImpact();
      showSnack(context, 'Mất kết nối với van — đang thử kết nối lại, vui lòng chờ rồi thử lại.', isError: true);
      prov.refreshAll();
      return;
    }
    HapticFeedback.lightImpact();
    prov.publish(cmd);
    if (confirmMsg != null) showSnack(context, confirmMsg);
  }

  String _uptimeStr(int? sec) {
    if (sec == null) return '--';
    final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
    return '${h}h ${m}m ${s}s';
  }

  IconData _rssiIcon(int rssi) {
    if (rssi >= -60) return Icons.wifi_rounded;
    if (rssi >= -75) return Icons.wifi_2_bar_rounded;
    return Icons.wifi_1_bar_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DashboardProvider>();
    final t = prov.telemetry;
    final theme = Theme.of(context);
    final staConnected = t.wifiStaConnected == true;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // === WIFI - muc chinh, dua len dau vi day la thao tac thuong xuyen
        // nhat trong tab nay (cau hinh/sua WiFi cho van), khac voi thong tin
        // phan cung chi de tham khao/chan doan, it can toi hon. ===
        SectionCard(
          title: 'Kết Nối WiFi',
          icon: Icons.wifi_rounded,
          trailing: StatusPill(
            text: staConnected ? 'ĐÃ KẾT NỐI' : 'CHƯA KẾT NỐI',
            color: staConnected ? Colors.green : Colors.grey,
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: (staConnected ? Colors.green : theme.colorScheme.outline).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: (staConnected ? Colors.green : theme.colorScheme.outline).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(
                    staConnected ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: staConnected ? Colors.green : theme.colorScheme.outline,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          staConnected ? (t.wifiStaSSID ?? '--') : (t.wifiStaSavedSSID != null ? 'Chưa kết nối' : 'Chưa cấu hình mạng nào'),
                          style: theme.textTheme.titleSmall,
                        ),
                        if (staConnected)
                          Text('Tín hiệu ${t.wifiStaRSSI ?? '--'} dBm', style: theme.textTheme.bodySmall)
                        else if (t.wifiStaSavedSSID != null)
                          Text('Đã lưu: ${t.wifiStaSavedSSID}', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ssidCtrl,
                    decoration: const InputDecoration(labelText: 'Tên WiFi (SSID)', isDense: true, prefixIcon: Icon(Icons.router_rounded)),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _publish(context, 'WIFI_SCAN', 'Đang quét WiFi...'),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Quét'),
                ),
              ],
            ),
            if (t.wifiScanResults.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: t.wifiScanResults.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: theme.colorScheme.outlineVariant),
                  itemBuilder: (ctx, i) {
                    final n = t.wifiScanResults[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(_rssiIcon(n.rssi), size: 20, color: theme.colorScheme.primary),
                      title: Text(n.ssid, style: const TextStyle(fontSize: 13.5)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (n.secure) Icon(Icons.lock_rounded, size: 14, color: theme.colorScheme.outline),
                          const SizedBox(width: 4),
                          Text('${n.rssi} dBm', style: theme.textTheme.bodySmall),
                        ],
                      ),
                      onTap: () => setState(() => _ssidCtrl.text = n.ssid),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mật khẩu WiFi', isDense: true, prefixIcon: Icon(Icons.lock_outline_rounded)),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.wifi_rounded, size: 18),
                    onPressed: () {
                      final ssid = _ssidCtrl.text.trim();
                      if (ssid.isEmpty) return showSnack(context, 'Vui lòng nhập tên WiFi!', isError: true);
                      if (ssid.contains('|')) return showSnack(context, 'Tên WiFi không được chứa ký tự "|"!', isError: true);
                      _publish(context, 'WIFI_CONNECT:$ssid|${_passCtrl.text}', 'Đã gửi lệnh kết nối WiFi "$ssid".');
                    },
                    label: const Text('Kết Nối & Lưu'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.link_off_rounded, size: 18),
                    onPressed: () async {
                      final ok = await confirmDialog(context, title: 'Ngắt kết nối?', message: 'Ngắt kết nối và xoá cấu hình WiFi nhà đã lưu trên ESP32?');
                      if (ok && context.mounted) _publish(context, 'WIFI_DISCONNECT', 'Đã gửi lệnh ngắt kết nối WiFi.');
                    },
                    label: const Text('Ngắt Kết Nối'),
                  ),
                ),
              ],
            ),
          ],
        ),
        SectionCard(
          title: 'Điểm Phát WiFi (AP)',
          icon: Icons.wifi_tethering_rounded,
          trailing: Switch(
            value: t.wifiApEnabled ?? true,
            onChanged: (enable) async {
              if (!enable) {
                final ok = await confirmDialog(context,
                    title: 'Tắt AP?', message: 'ESP32 sẽ TỰ CHỐI nếu WiFi nhà chưa kết nối ổn định (để tránh khoá thiết bị). Tiếp tục?');
                if (!ok || !context.mounted) return;
              }
              _publish(context, enable ? 'AP_ON' : 'AP_OFF', enable ? 'Đã gửi lệnh bật AP.' : 'Đã gửi lệnh tắt AP.');
            },
          ),
          children: [
            Text(
              t.wifiApEnabled == true ? 'Đang phát tại ${t.wifiApIP ?? '--'}' : 'Đang tắt',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Chỉ tắt khi ESP32 đang kết nối WiFi nhà ổn định — tắt lúc chưa có mạng nhà sẽ khoá hoàn toàn thiết bị.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
            ),
          ],
        ),
        // === THONG TIN PHAN CUNG - day xuong duoi, chi de tham khao/chan
        // doan, khong phai thao tac chinh cua tab nay. ===
        SectionCard(
          title: 'Thông Tin Phần Cứng',
          icon: Icons.memory_rounded,
          trailing: IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Đọc lại',
            onPressed: () => _publish(context, 'ESP_INFO?', 'Đang tải lại thông tin phần cứng...'),
          ),
          children: [
            statGrid([
              StatBox(label: 'Firmware ESP32', value: t.espFw ?? '--', sub: t.espMqttPrefix != null ? 'Prefix: ${t.espMqttPrefix}' : null),
              StatBox(label: 'Chip', value: t.espChip ?? '--', sub: t.espCpuFreq != null ? '${t.espCpuFreq} MHz' : null),
              StatBox(label: 'Flash', value: t.espFlashSize != null ? '${t.espFlashSize} MB' : '--', sub: 'Uptime: ${_uptimeStr(t.espUptime)}'),
              StatBox(
                label: 'RAM Khả Dụng',
                value: t.espFreeHeap != null ? '${(t.espFreeHeap! / 1024).toStringAsFixed(1)} KB' : '--',
                sub: t.espMinFreeHeap != null ? 'Min Free: ${(t.espMinFreeHeap! / 1024).toStringAsFixed(1)} KB' : null,
              ),
            ]),
          ],
        ),
      ],
    );
  }
}
