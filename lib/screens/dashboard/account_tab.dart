import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/auth_provider.dart';
import '../../state/theme_provider.dart';
import '../../widgets/common.dart';
import '../login_screen.dart';

/// Tab "Tài Khoản" - 1 trong 5 tab cua MainShell (sau "Quan Ly Van"). [FIX]
/// Truoc day co 1 section "Van Dang Quan Ly" (ten/mqttPrefix cua van dang
/// mo) vi luc do "doi van" chi lam duoc tu day - nay "Quan Ly Van" da la 1
/// tab rieng luon co san o thanh dieu huong, section do thanh du thua/gay
/// nham lan (van dang chon la trang thai CUA MAN HINH KHAC, khong phai cua
/// tai khoan nguoi dung) nen bo hoan toan, khong con phu thuoc DashboardProvider.
class AccountTab extends StatelessWidget {
  const AccountTab({super.key});

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
      padding: EdgeInsets.zero,
      children: [
        // [FIX] Lam "chuyen nghiep" hon: bo goc duoi bo tron (thay vi cat
        // thang, cam giac "banner web" cu) + avatar co vien trang noi bat +
        // do bong nhe, giong pattern man hinh ho so quen thuoc cua cac app
        // lon (Zalo, Google...).
        ClipRRect(
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 36, bottom: 32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.78)],
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: theme.colorScheme.onPrimary.withValues(alpha: 0.55), width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: CircleAvatar(
                    radius: 42,
                    backgroundColor: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                    child: Text(
                      initial,
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  displayName,
                  style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold),
                ),
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
        ),
        const SizedBox(height: 12),

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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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
