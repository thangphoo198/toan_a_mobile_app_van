import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/auth_provider.dart';
import '../../state/dashboard_provider.dart';
import '../../state/theme_provider.dart';
import '../../widgets/common.dart';
import '../login_screen.dart';

class AccountTab extends StatelessWidget {
  const AccountTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final prov = context.watch<DashboardProvider>();
    final user = auth.user;
    final username = user?['username']?.toString() ?? '--';
    final email = user?['email']?.toString();
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    final connected = prov.connState == MqttConnState.connected;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // --- Banner mau chu dao + avatar (tuong tu cac app mobile chuan) ---
        Container(
          width: double.infinity,
          padding: const EdgeInsets.only(top: 28, bottom: 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.85)],
            ),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                child: Text(
                  initial,
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary),
                ),
              ),
              const SizedBox(height: 12),
              Text(username, style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold)),
              if (email != null && email.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(email, style: TextStyle(color: theme.colorScheme.onPrimary.withValues(alpha: 0.85))),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // --- Danh sach dong menu kieu list-tile co icon + chevron ---
        _MenuRow(
          icon: Icons.water_drop_outlined,
          title: 'Van Đang Mở',
          subtitle: '${prov.van.displayName} • ${prov.van.mqttPrefix}',
          onTap: () => Navigator.of(context).pop(),
        ),
        _MenuRow(
          icon: Icons.settings_ethernet,
          title: 'Kết Nối MQTT',
          subtitle: '${prov.host}:${prov.port} — ${connected ? "Đang online" : "Mất kết nối"}',
          subtitleColor: connected ? Colors.green : Colors.orange,
          onTap: null,
        ),

        const SizedBox(height: 20),
        SectionCard(
          title: 'Giao Diện',
          icon: Icons.palette_outlined,
          children: [
            Consumer<ThemeProvider>(
              builder: (context, themeProvider, _) => SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Sáng')),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Tối')),
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.smartphone_outlined), label: Text('Hệ thống')),
                ],
                selected: {themeProvider.mode},
                onSelectionChanged: (s) => themeProvider.setMode(s.first),
              ),
            ),
          ],
        ),
        SectionCard(
          title: 'Thông Tin App',
          icon: Icons.info_outline,
          children: const [
            ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text('Phiên bản'), trailing: Text('1.0.0')),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: Colors.red),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('Đăng Xuất'),
            onPressed: () async {
              final confirmed = await confirmDialog(context, title: 'Đăng xuất?', message: 'Bạn sẽ cần đăng nhập lại để tiếp tục sử dụng.');
              if (!confirmed || !context.mounted) return;
              await context.read<AuthProvider>().logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;
  final VoidCallback? onTap;

  const _MenuRow({required this.icon, required this.title, this.subtitle, this.subtitleColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle != null ? Text(subtitle!, style: TextStyle(color: subtitleColor)) : null,
        trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
      ),
    );
  }
}
