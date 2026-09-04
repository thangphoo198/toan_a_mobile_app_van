import 'package:flutter/material.dart';

/// Card bao ngoai 1 nhom noi dung - tuong duong .card trong web client.
class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget? trailing;
  final List<Widget> children;

  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Pill trang thai nho - tuong duong .pill trong web client.
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const StatusPill({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// O thong ke nho (nhan/gia tri/mo ta) - tuong duong .stat-box.
class StatBox extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;

  const StatBox({
    super.key,
    required this.label,
    required this.value,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 148),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(value, style: theme.textTheme.titleMedium),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

Widget statGrid(List<Widget> boxes) {
  return Wrap(spacing: 10, runSpacing: 10, children: boxes);
}

void showSnack(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red.shade700 : null,
      duration: const Duration(seconds: 3),
    ),
  );
}

/// Banner + khoá thao tác cho các nhóm tính năng BẮT BUỘC cần Internet thật
/// (vd nạp OTA, tải file qua MQTT) - không hoạt động được qua kênh BLE cục
/// bộ. Khi [locked], nội dung bị làm mờ và vô hiệu hoá chạm (AbsorbPointer),
/// kèm banner giải thích rõ lý do thay vì để nút bấm không phản hồi gì.
class OfflineLockNotice extends StatelessWidget {
  final bool locked;
  final String message;
  final Widget child;

  const OfflineLockNotice({
    super.key,
    required this.locked,
    required this.message,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!locked) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blueGrey.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock_outline, color: Colors.blueGrey, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.blueGrey, fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Opacity(opacity: 0.4, child: AbsorbPointer(child: child)),
        ),
      ],
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Huỷ'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Đồng ý'),
        ),
      ],
    ),
  );
  return result ?? false;
}
