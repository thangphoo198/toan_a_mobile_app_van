import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../constants.dart';
import '../../state/dashboard_provider.dart';
import '../../widgets/common.dart';

class ControlTab extends StatelessWidget {
  const ControlTab({super.key});

  void _sendGoto(BuildContext context, int pos, bool isRunning) {
    if (isRunning) {
      HapticFeedback.heavyImpact();
      showSnack(context, 'Van đang chạy — đợi xong mới chuyển được vị trí khác.', isError: true);
      return;
    }
    HapticFeedback.lightImpact();
    final mode = kWaterModes[pos]!;
    context.read<DashboardProvider>().publish('GOTO:$pos');
    showSnack(context, 'Đã gửi lệnh chuyển sang "${mode.name}" (vị trí $pos)...');
  }

  void _sendNext(BuildContext context, bool isRunning) {
    if (isRunning) {
      HapticFeedback.heavyImpact();
      showSnack(context, 'Van đang chạy — đợi xong mới chuyển được vị trí khác.', isError: true);
      return;
    }
    HapticFeedback.lightImpact();
    context.read<DashboardProvider>().publish('NEXT');
    showSnack(context, 'Đã gửi lệnh bước tới vị trí kế tiếp...');
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DashboardProvider>();
    final t = prov.telemetry;
    final currentPos = t.pos;
    // QUAN TRONG: KHONG dung t.isRunning (tu "RUN=" / is_van_running ben CH32)
    // o day - bien do thuc ra nghia la "van dang o vi tri khac 1" (bus bi
    // khoa), TRUE VINH VIEN cho toi khi ve vi tri 1, khong phai "dong co
    // dang quay" (xem chu thich trong uart1_rx.c). Dung t.monMod=='RUN' (tu
    // setupMode ben CH32) - CHI true trong luc dong co thuc su dang chay.
    final isRunning = t.monMod == 'RUN';

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (isRunning)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_clock, color: Colors.orange, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Van đang chạy — nút chuyển vị trí tạm khoá cho tới khi xong.',
                    style: TextStyle(color: Colors.orange.shade800, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        SectionCard(
          title: '5 Chế Độ Xử Lý Nước Tự Động',
          icon: Icons.grid_view,
          children: [
            const Text('Bấm chọn để chuyển nhanh tới vị trí tương ứng.', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
              children: kWaterModes.entries.map((e) {
                final selected = currentPos == e.key;
                final locked = isRunning && !selected;
                return Opacity(
                  opacity: locked ? 0.45 : 1.0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _sendGoto(context, e.key, isRunning),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selected ? e.value.color.withValues(alpha: 0.18) : Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: Border.all(color: selected ? e.value.color : Theme.of(context).colorScheme.outlineVariant, width: selected ? 2 : 1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${e.value.icon}  P${e.key}', style: const TextStyle(fontSize: 19)),
                              const SizedBox(height: 4),
                              Text(e.value.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                              Text(e.value.sub, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
                            ],
                          ),
                          if (selected && isRunning)
                            const Positioned(
                              top: 0,
                              right: 0,
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          if (locked)
                            const Positioned(top: 0, right: 0, child: Icon(Icons.lock, size: 16, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        SectionCard(
          title: 'Lệnh Nhanh',
          icon: Icons.bolt,
          children: [
            FilledButton.icon(
              onPressed: () => _sendNext(context, isRunning),
              icon: const Icon(Icons.skip_next),
              label: Text(isRunning ? 'Van Đang Chạy — Đợi Xong' : 'Bước Tới Vị Trí Kế Tiếp (NEXT)'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context.read<DashboardProvider>().publish('POS?');
                      showSnack(context, 'Đã gửi yêu cầu tra cứu vị trí...');
                    },
                    icon: const Icon(Icons.location_on_outlined),
                    label: const Text('Tra Cứu Vị Trí'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      context.read<DashboardProvider>().publish('PING');
                      showSnack(context, 'Đã gửi PING...');
                    },
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('PING'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, minimumSize: const Size.fromHeight(46)),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Khởi Động Lại CH32 (RESET)'),
              onPressed: () async {
                final dashboard = context.read<DashboardProvider>();
                final ok = await confirmDialog(context,
                    title: 'Khởi động lại CH32?', message: 'Van sẽ tạm dừng và khởi động lại. Tiếp tục?');
                if (!ok || !context.mounted) return;
                dashboard.publish('RESET');
                showSnack(context, 'Đã gửi lệnh khởi động lại...');
              },
            ),
          ],
        ),
      ],
    );
  }
}
