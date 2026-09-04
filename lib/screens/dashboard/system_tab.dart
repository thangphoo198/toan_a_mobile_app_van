import 'package:flutter/material.dart';
import 'esp_settings_tab.dart';
import 'ota_tab.dart';
import 'terminal_tab.dart';

/// Gom 3 khu vuc ky thuat/it dung hang ngay (Nap CH32, Cai Dat ESP32,
/// Terminal) vao 1 muc bottom-nav duy nhat "He Thong", dieu huong bang tab
/// con ben trong - giu bottom nav chinh o muc 5 muc theo chuan Material.
class SystemTab extends StatelessWidget {
  const SystemTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6))),
            ),
            child: TabBar(
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorColor: theme.colorScheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
              tabs: const [
                Tab(text: '⚡ Nạp CH32'),
                Tab(text: '📶 ESP32 & WiFi'),
                Tab(text: '📟 Terminal'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                OtaTab(),
                EspSettingsTab(),
                TerminalTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
