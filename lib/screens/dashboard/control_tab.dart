import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../constants.dart';
import '../../state/dashboard_provider.dart';
import '../../widgets/common.dart';

class ControlTab extends StatelessWidget {
  const ControlTab({super.key});

  /// [FIX] Truoc day bam nut la publish() ngay va LUON hien snackbar "Đã gửi
  /// lệnh..." - kien ca khi thuc ra khong co ket noi nao con song (van da
  /// mat WiFi/Bluetooth tu truoc do ma app chua kip phat hien), khien nguoi
  /// dung tuong lenh da toi noi trong khi van khong he nhuc nhich. Kiem tra
  /// isConnectionStale TRUOC - neu dang mat ket noi, KHONG gui lenh, bao ro
  /// rang va chu dong thu ket noi lai (refreshAll()) thay vi gia vo thanh
  /// cong. Tra ve true neu lenh THAT SU duoc gui.
  bool _checkConnectionBeforeSend(BuildContext context, DashboardProvider prov) {
    if (!prov.isConnectionStale) return true;
    HapticFeedback.heavyImpact();
    showSnack(context, 'Mất kết nối với van — đang thử kết nối lại, vui lòng chờ rồi thử lại.', isError: true);
    prov.refreshAll();
    return false;
  }

  /// [NEW] Van duoc chia se CHI GIAM SAT (canControl=false, xem [[them tinh
  /// nang chia se]]/van_shares) - chan gui lenh dieu khien tu phia app TRUOC
  /// khi kiem tra ket noi/trang thai, vi day la gioi han QUYEN chu khong
  /// phai loi ket noi.
  bool _checkPermission(BuildContext context, DashboardProvider prov) {
    if (prov.van.canControl) return true;
    HapticFeedback.heavyImpact();
    showSnack(context, 'Bạn chỉ được chia sẻ quyền giám sát van này — không thể điều khiển. Liên hệ chủ van để được cấp thêm quyền.', isError: true);
    return false;
  }

  void _sendGoto(BuildContext context, int pos, bool isRunning, bool isScanning, String? modelCode) {
    final prov0 = context.read<DashboardProvider>();
    if (!_checkPermission(context, prov0)) return;
    // [NEW] Firmware TU CHOI GOTO trong luc dang quet ("ERR: chua quet" - xem
    // uart1_goto_run() trong uart1_rx.c) vi vi tri hien tai CHUA XAC DINH -
    // chan tu phia app truoc, khoi gui lenh chac chan bi tu choi.
    if (isScanning) {
      HapticFeedback.heavyImpact();
      showSnack(context, 'Van đang quét và phục hồi chế độ — vui lòng đợi xong rồi thử lại.', isError: true);
      return;
    }
    if (isRunning) {
      HapticFeedback.heavyImpact();
      showSnack(context, 'Van đang chạy — đợi xong mới chuyển được vị trí khác.', isError: true);
      return;
    }
    final prov = context.read<DashboardProvider>();
    if (!_checkConnectionBeforeSend(context, prov)) return;
    HapticFeedback.lightImpact();
    final mode = modeForPosition(modelCode, pos)!;
    prov.publish('GOTO:$pos');
    showSnack(context, 'Đã gửi lệnh chuyển sang "${mode.name}" (vị trí $pos)...');
  }

  void _sendNext(BuildContext context, bool isRunning, bool isScanning) {
    final prov0 = context.read<DashboardProvider>();
    if (!_checkPermission(context, prov0)) return;
    if (isScanning) {
      HapticFeedback.heavyImpact();
      showSnack(context, 'Van đang quét và phục hồi chế độ — vui lòng đợi xong rồi thử lại.', isError: true);
      return;
    }
    if (isRunning) {
      HapticFeedback.heavyImpact();
      showSnack(context, 'Van đang chạy — đợi xong mới chuyển được vị trí khác.', isError: true);
      return;
    }
    final prov = context.read<DashboardProvider>();
    if (!_checkConnectionBeforeSend(context, prov)) return;
    HapticFeedback.lightImpact();
    prov.publish('NEXT');
    showSnack(context, 'Đã gửi lệnh bước tới vị trí kế tiếp...');
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DashboardProvider>();
    final t = prov.telemetry;
    final currentPos = t.pos;
    // [FIX] Van 3 cua (F041/F043) chi co 3 vi tri THAT SU (motor3.c ben
    // firmware, xem GOTO trong uart1_rx.c gio da tu choi target>3 cho model
    // nay) - chi hien dung so o tuong ung, vi tri 3 dung nhan/mau "Rua Xuoi"
    // (giong vi tri 5 tren van 5 cua) thay vi "Hoan Nguyen" sai hoan toan.
    final maxPos = maxPositionsForModel(t.mcuVan);
    final visibleModes = [
      for (int p = 1; p <= maxPos; p++) MapEntry(p, modeForPosition(t.mcuVan, p)!),
    ];
    // QUAN TRONG: KHONG dung t.isRunning (tu "RUN=" / is_van_running ben CH32)
    // o day - bien do thuc ra nghia la "van dang o vi tri khac 1" (bus bi
    // khoa), TRUE VINH VIEN cho toi khi ve vi tri 1, khong phai "dong co
    // dang quay" (xem chu thich trong uart1_rx.c). Dung t.monMod=='RUN' (tu
    // setupMode ben CH32) - CHI true trong luc dong co thuc su dang chay.
    final isRunning = t.monMod == 'RUN';
    // [NEW] Dang quet/phuc hoi vi tri (detect_and_recover() ben CH32) - vi
    // tri CHUA XAC DINH, firmware TU CHOI moi lenh GOTO/NEXT luc nay ("ERR:
    // chua quet" - xem uart1_rx.c) nen phai khoa CA 2 nut tu phia app, tranh
    // gui lenh chac chan bi tu choi.
    final isScanning = t.isScanDone == false;
    // [NEW] Mat ket noi la canh bao QUAN TRONG HON "dang chay"/"dang quet" -
    // neu nhieu dieu kien cung dung, chi hien 1 banner theo do uu tien, vi
    // day la nguyen nhan goc khien bam nut vo nghia.
    final isStale = prov.isConnectionStale;
    // [NEW] Van duoc chia se chi de GIAM SAT - uu tien cao nhat trong cac
    // banner canh bao vi day la gioi han CHU DINH (khong phai su co tam
    // thoi nhu mat ket noi/dang chay), nguoi dung can hieu ro tai sao nut bi
    // khoa vinh vien tren van nay chu khong phai "cu doi la duoc".
    final noPermission = !prov.van.canControl;

    // [FIX] Truoc day la ListView rieng (trang dieu huong bottom-nav doc lap)
    // - gio duoc nhung vao chung ListView cua MonitorTab (gop "Dieu Khien"
    // vao chung man "Giam Sat") nen phai doi thanh Column (khong tu cuon)
    // de tranh loi "ListView long trong ListView" (2 truc cuon xung dot).
    return Column(
      children: [
        if (noPermission)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.visibility_rounded, color: Colors.grey, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Bạn chỉ có quyền GIÁM SÁT van này (chủ van chưa cấp quyền điều khiển).',
                    style: TextStyle(color: Colors.grey.shade800, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          )
        else if (isStale)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi_off_rounded, color: Colors.red, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Mất kết nối với van — kéo màn hình xuống để làm mới trước khi điều khiển.',
                    style: TextStyle(color: Colors.red.shade800, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          )
        else if (isScanning)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Van đang quét và phục hồi chế độ — nút điều khiển tạm khoá cho tới khi có vị trí mới.',
                    style: TextStyle(color: Colors.blueAccent.shade700, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          )
        else if (isRunning)
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
        // [UPDATE] Gop "5 Che Do" + nut NEXT vao 1 the duy nhat "Dieu Khien
        // Van" (bo the "Lenh Nhanh" rieng cung PING/Tra Cuu Vi Tri/RESET theo
        // yeu cau) - lam noi bat cac nut chinh (bo tron nhieu hon, do bong,
        // vien day hon) vi day la khu vuc thao tac CHINH cua tab nay.
        SectionCard(
          title: 'Điều Khiển Van',
          icon: Icons.videogame_asset_rounded,
          children: [
            const Text('Bấm chọn để chuyển nhanh tới vị trí tương ứng.', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.3,
              children: visibleModes.map((e) {
                final selected = currentPos == e.key;
                final locked = noPermission || isStale || isScanning || (isRunning && !selected);
                return Opacity(
                  opacity: locked ? 0.45 : 1.0,
                  child: Material(
                    color: selected ? e.value.color.withValues(alpha: 0.16) : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                    elevation: selected ? 3 : 0,
                    shadowColor: e.value.color.withValues(alpha: 0.4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _sendGoto(context, e.key, isRunning, isScanning, t.mcuVan),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: selected ? e.value.color : Theme.of(context).colorScheme.outlineVariant, width: selected ? 2.5 : 1),
                        ),
                        // [FIX] "BOTTOM OVERFLOWED" tren man hinh thap/font he
                        // thong lon: Column ben trong Stack KHONG duoc gioi
                        // han chieu cao boi Stack, chi bang dung noi dung -
                        // neu 3 dong text (icon+vi tri/ten/mo ta) vuot qua
                        // chieu cao o luoi (tinh tu childAspectRatio) se tran.
                        // Dung Column mainAxisSize.min + maxLines/overflow lam
                        // luoi an toan, khong phu thuoc kich thuoc man hinh.
                        child: Stack(
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${e.value.icon}  P${e.key}', style: const TextStyle(fontSize: 19)),
                                const SizedBox(height: 3),
                                Text(
                                  e.value.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                                ),
                                Text(
                                  e.value.sub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
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
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: noPermission ? null : () => _sendNext(context, isRunning, isScanning),
              icon: Icon(noPermission
                  ? Icons.visibility_rounded
                  : (isStale
                      ? Icons.wifi_off_rounded
                      : (isScanning ? Icons.travel_explore_rounded : Icons.skip_next_rounded))),
              label: Text(noPermission
                  ? 'Chỉ Xem — Không Có Quyền Điều Khiển'
                  : (isStale
                      ? 'Mất Kết Nối — Kéo Xuống Để Làm Mới'
                      : (isScanning
                          ? 'Đang Quét — Vui Lòng Đợi'
                          : (isRunning ? 'Van Đang Chạy — Đợi Xong' : 'Bước Tới Vị Trí Kế Tiếp (NEXT)')))),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
