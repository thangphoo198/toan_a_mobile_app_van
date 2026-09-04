import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants.dart';
import '../../state/dashboard_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/flow_chart.dart';
import '../../widgets/position_gauge.dart';

class MonitorTab extends StatelessWidget {
  const MonitorTab({super.key});

  String _dateStr(String? d) {
    if (d == null) return '--';
    final parts = d.split('/');
    if (parts.length == 3) return '${parts[0]}/${parts[1]}/20${parts[2]}';
    return d;
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');

  /// Chip nho gon "icon + nhan + gia tri" - dung de hien thi nhanh cac
  /// thong so quan trong (con lai, che do A/B) ngay trong the "Trạng Thái
  /// Van" chinh, khong bat nguoi dung phai keo xuong the rieng ben duoi.
  Widget _miniStat(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text('$label: ', style: theme.textTheme.bodySmall),
          Text(value, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }

  String _freshnessText(DateTime? last) {
    if (last == null) return 'Chưa có dữ liệu';
    final secAgo = DateTime.now().difference(last).inSeconds;
    final timeStr = '${_pad2(last.hour)}:${_pad2(last.minute)}:${_pad2(last.second)}';
    if (secAgo < 3) return 'Cập nhật lúc $timeStr • vừa xong';
    if (secAgo < 60) return 'Cập nhật lúc $timeStr • $secAgo giây trước';
    return 'Cập nhật lúc $timeStr • ${secAgo ~/ 60} phút trước';
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DashboardProvider>();
    final t = prov.telemetry;
    final mode = t.pos != null ? kWaterModes[t.pos] : null;
    final isFlowValve = isFlowValveModel(t.mcuVan);
    final isMoving = t.monMod == 'RUN';

    return RefreshIndicator(
      onRefresh: () async {
        prov.refreshAll();
        await Future.delayed(const Duration(milliseconds: 900));
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Icon(Icons.access_time, size: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 5),
                Text(_freshnessText(t.lastUpdate), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          SectionCard(
            title: 'Trạng Thái Van',
            icon: Icons.water_drop,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (t.monMod != null)
                StatusPill(
                  // t.monMod=='RUN' phan anh dung "dong co dang thuc su quay"
                  // (setupMode ben CH32) - KHONG dung t.isRunning (RUN=), bien
                  // do thuc ra la "van dang o vi tri khac 1", khong phai dang
                  // quay, se hien "ĐANG CHẠY" sai suot thoi gian van dung yen
                  // o vi tri != 1.
                  text: isMoving ? '🟢 ĐANG CHẠY' : '⚪ DỪNG',
                  color: isMoving ? Colors.green : Colors.orange,
                ),
              const SizedBox(width: 6),
              if (t.isError != null)
                StatusPill(
                  text: t.isError! ? '🔴 CÓ LỖI' : '🟢 NO ERROR',
                  color: t.isError! ? Colors.red : Colors.green,
                ),
            ]),
            children: [
              Row(
                children: [
                  PositionGauge(position: t.pos, isMoving: isMoving, size: 126),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(mode != null ? '${mode.icon} ${mode.name}' : 'Vị trí ${t.pos ?? '--'}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        Text(mode?.sub ?? '', style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text('${_dateStr(t.monDate)} ${t.monTime ?? ''}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _miniStat(context, Icons.timer_outlined, 'Còn Lại', t.monRem != null ? '${t.monRem} phút' : '--'),
                  _miniStat(context, Icons.looks_one_outlined, 'Chế Độ A',
                      'A-${(t.monModeA ?? 0).toString().padLeft(2, '0')}'),
                  _miniStat(context, Icons.looks_two_outlined, 'Chế Độ B',
                      'B-${(t.monModeB ?? 0).toString().padLeft(2, '0')}'),
                ],
              ),
            ],
          ),
          if (isFlowValve)
            SectionCard(
              title: 'Đo Lưu Lượng Nước (Flowmeter)',
              icon: Icons.speed_rounded,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    t.flowSpeed?.toStringAsFixed(2) ?? '--',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 3),
                  Text('L/h', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              children: [
                FlowChart(samples: t.flowHistory),
                const SizedBox(height: 14),
                statGrid([
                  StatBox(label: 'Lưu Lượng Cài Đặt', value: '${t.flowSet?.toStringAsFixed(2) ?? '--'} m³'),
                  StatBox(label: 'Lưu Lượng Còn Lại', value: '${t.flowRem?.toStringAsFixed(2) ?? '--'} m³'),
                ]),
              ],
            ),
          // [FIX] Gop "Dinh Danh Chip & Ngoai Vi" vao chung the nay, va bo
          // Che Do A/B + Hen Gio (da hien thi o the "Trang Thai Van" phia
          // tren roi - de o day nua la trung lap khong can thiet).
          SectionCard(
            title: 'Thông Số Vận Hành & Phần Cứng CH32X035',
            icon: Icons.tune,
            trailing: FilledButton.tonal(
              onPressed: () => context.read<DashboardProvider>().publish('PING'),
              child: const Text('⚡ PING MCU'),
            ),
            children: [
              statGrid([
                StatBox(label: 'RAM Khả Dụng', value: '${t.heap ?? '--'} B', sub: 'Min Free: ${t.heapMin ?? '--'} B'),
                StatBox(label: 'Mã Van', value: t.mcuVan != null ? '#${t.mcuVan}' : '--', sub: t.mcuId != null ? 'Chip ID: ${t.mcuId}' : null),
                StatBox(label: 'Firmware CH32', value: t.mcuFw ?? '--', sub: t.mcuClk != null ? 'Clock: ${t.mcuClk} MHz' : null),
                StatBox(label: 'Ngoại Vi RTC', value: 'RTC: ${(t.mcuRtc ?? '--').toUpperCase()}'),
                StatBox(label: 'Ngoại Vi EEPROM', value: 'EEPROM: ${(t.mcuEe ?? '--').toUpperCase()}'),
              ]),
              if (t.mcuUid != null) ...[
                const SizedBox(height: 10),
                Text('Chip UID: ${t.mcuUid}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
