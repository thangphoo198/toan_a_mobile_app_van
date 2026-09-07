import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants.dart';
import '../../state/dashboard_provider.dart';
import '../../widgets/common.dart';
import '../../widgets/flow_chart.dart';
import '../../widgets/position_gauge.dart';
import '../../widgets/water_tank.dart';
import 'control_tab.dart';

class MonitorTab extends StatefulWidget {
  const MonitorTab({super.key});

  @override
  State<MonitorTab> createState() => _MonitorTabState();
}

/// [FIX] Truoc day la StatelessWidget - dong chu "Cập nhật lúc..." (freshness
/// text) chi tinh lai moi khi TelemetryState.notifyListeners() (tin moi ve),
/// nen khi mat ket noi THAT SU (khong con tin nao ve nua), dong chu nay
/// DUNG YEN MAI o gia tri cu (vd "vừa xong") thay vi tang dan "... phút
/// trước" - khien nguoi dung khong nhan ra du lieu dang cu di. Chuyen sang
/// StatefulWidget + Timer.periodic de tu lam moi hien thi (khong can du lieu
/// moi) - dong bo voi isConnectionStale o dashboard_provider.dart.
class _MonitorTabState extends State<MonitorTab> {
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _tickTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

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
  Widget _miniStat(BuildContext context, IconData icon, String label, String value, {Color? accentColor}) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor != null ? accent.withValues(alpha: 0.14) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: accentColor != null ? Border.all(color: accent.withValues(alpha: 0.4)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accent),
          const SizedBox(width: 6),
          Text('$label: ', style: theme.textTheme.bodySmall),
          Text(value, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: accentColor ?? theme.colorScheme.onSurface)),
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

  /// [NEW] "Chua he nhan duoc du lieu nao tu van" - vua mo dashboard, dang
  /// ket noi/cho phan hoi dau tien. Khac voi isConnectionStale (da TUNG co
  /// du lieu roi nhung gio nghi ngo da cu/mat) - truong hop nay CHUA CO GI
  /// ca de hien thi, nen thay vi ve card voi toan "--"/rong, hien man hinh
  /// cho ro rang. Dung lai khi da that bai han (connState == error) de
  /// khong bi "ket dinh" mai o trang thai cho neu that su mat ket noi -
  /// luc do nhuong lai cho banner "Mat Ket Noi" trong ControlTab xu ly.
  bool _isInitializing(DashboardProvider prov) {
    return prov.telemetry.lastUpdate == null && prov.connState != MqttConnState.error;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DashboardProvider>();
    final t = prov.telemetry;
    final mode = t.pos != null ? kWaterModes[t.pos] : null;
    final isFlowValve = isFlowValveModel(t.mcuVan);
    final isMoving = t.monMod == 'RUN';
    final isInitializing = _isInitializing(prov);

    return RefreshIndicator(
      // [FIX] Truoc day khong await ket qua refreshAll() (chi delay co dinh
      // 900ms) - keo lam moi khi dang mat ket noi se ket thuc "qua nhanh"
      // truoc khi refreshAll() kip thu ket noi lai (co the mat vai giay),
      // khien nguoi dung tuong da lam moi xong nhung thuc ra chua ket noi
      // lai duoc gi ca. Await dung Future de vong xoay hien thi suot qua
      // trinh thu ket noi lai.
      onRefresh: () => prov.refreshAll(),
      child: isInitializing
          ? ListView(
              // Van la ListView (khong phai Center don thuan) de nguoi dung
              // van keo-de-lam-moi duoc ngay ca trong luc dang cho, phong
              // khi ket noi bi "treo" lau hon binh thuong.
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.65,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Đang tải trạng thái van...',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          prov.activeTransport == ActiveTransport.ble
                              ? 'Đang kết nối qua Bluetooth cục bộ...'
                              : 'Đang kết nối MQTT và chờ van phản hồi...',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : ListView(
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
                  // [NEW] Canh bao het vat lieu (Cxx) - chi hien khi van THAT
                  // SU da duoc cau hinh tinh nang nay (monCxx > 0), tranh
                  // hien "0/0" gay nham lan cho cac van chua dung tinh nang.
                  if ((t.monCxx ?? 0) > 0)
                    _miniStat(
                      context,
                      (t.monCcur ?? 0) == 0 ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
                      (t.monCcur ?? 0) == 0 ? 'Hết Vật Liệu' : 'Chu Kỳ Còn Lại',
                      (t.monCcur ?? 0) == 0 ? 'Cần thay ngay!' : '${t.monCcur}/${t.monCxx}',
                      accentColor: (t.monCcur ?? 0) == 0 ? Colors.red : null,
                    ),
                ],
              ),
            ],
          ),
          // [FIX] Gop giao dien Dieu Khien vao chung man Giam Sat (bo muc
          // bottom-nav "Dieu Khien" rieng) - nguoi dung thay trang thai van
          // VA cac nut dieu khien cung luc, khong phai chuyen tab qua lai.
          const ControlTab(),
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
                const SizedBox(height: 18),
                WaterTank(setValue: t.flowSet, remainValue: t.flowRem),
              ],
            ),
        ],
      ),
    );
  }
}
