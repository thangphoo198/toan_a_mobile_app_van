import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/van.dart';
import '../../state/auth_provider.dart';
import '../../state/theme_provider.dart';
import '../../widgets/common.dart';
import '../login_screen.dart';

/// [FIX] Truoc day doc "van dang mo" qua `context.watch<DashboardProvider>()`
/// vi AccountTab la 1 trong 4 tab BEN TRONG dashboard cua 1 van cu the (luon
/// co san DashboardProvider trong cay widget). Gio "Quan Ly Van" da la 1 tab
/// rieng ngang hang (xem MainShell), AccountTab duoc mo nhu 1 MAN HINH PUSH
/// TU BEN NGOAI IndexedStack - khong con nam trong pham vi Provider do nua -
/// nen nhan truc tiep [van] (co the null neu nguoi dung chua chon van nao).
class AccountTab extends StatelessWidget {
  final Van? van;
  const AccountTab({super.key, this.van});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final username = user?['username']?.toString() ?? '--';
    final fullName = user?['full_name']?.toString();
    final phone = user?['phone']?.toString();
    final email = user?['email']?.toString();
    // Tai khoan cu (tao truoc khi co full_name/phone) se co 2 truong nay =
    // null - fallback ve username de khong hien "null" ngoai giao dien.
    final displayName = (fullName != null && fullName.isNotEmpty) ? fullName : username;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
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
              Text(displayName, style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold)),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('@$username', style: TextStyle(color: theme.colorScheme.onPrimary.withValues(alpha: 0.85))),
              ),
              if (email != null && email.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(email, style: TextStyle(color: theme.colorScheme.onPrimary.withValues(alpha: 0.85), fontSize: 12.5)),
                ),
            ],
          ),
        ),

        // [FIX] Gop cac dong roi (_MenuRow) vao chung SectionCard, dong nhat
        // voi ngon ngu thiet ke cua toan bo app (Giam Sat/Dieu Khien/Cai Dat
        // deu dung SectionCard) - truoc day "Van Dang Mo"/"So Dien Thoai" la
        // 2 hop roi noi thanh 1 hang muc rieng, khong ro nhom, thieu chuyen
        // nghiep. Bo hoan toan "Ket Noi MQTT" - da co pill trang thai o
        // AppBar roi, dat lai o day vua trung lap vua chi phan anh 1 trong 2
        // kenh (MQTT), gay hieu nham khi dang dung BLE du phong.
        SectionCard(
          title: 'Thông Tin Cá Nhân',
          icon: Icons.badge_outlined,
          children: [
            _InfoRow(
              icon: Icons.phone_outlined,
              label: 'Số điện thoại',
              value: (phone != null && phone.isNotEmpty) ? phone : 'Chưa cập nhật',
            ),
          ],
        ),
        // [FIX] Bo nut "Đổi Van" - "Quản Lý Van" gio la 1 tab rieng luon co
        // san o thanh dieu huong duoi cung (xem MainShell), khong can 1 loi
        // tat rieng tu day nua. Card nay chi con hien khi CO van dang chon.
        if (van != null)
          SectionCard(
            title: 'Van Đang Quản Lý',
            icon: Icons.water_drop_outlined,
            children: [
              _InfoRow(icon: Icons.label_outline, label: 'Tên hiển thị', value: van!.displayName),
              _InfoRow(icon: Icons.settings_ethernet, label: 'MQTT Prefix', value: van!.mqttPrefix),
            ],
          ),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
      ],
    );
  }
}

/// Hang thong tin gon trong 1 SectionCard - icon + nhan + gia tri, dung chung
/// cho cac muc chi de xem (khong bam duoc), thay the _MenuRow roi truoc day.
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
