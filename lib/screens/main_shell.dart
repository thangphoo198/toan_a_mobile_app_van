import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/van.dart';
import '../services/prefs_service.dart';
import '../state/dashboard_provider.dart';
import '../state/van_list_provider.dart';
import 'dashboard/account_tab.dart';
import 'dashboard/monitor_tab.dart';
import 'dashboard/system_tab.dart';
import 'dashboard/van_settings_tab.dart';
import 'van_list_tab.dart';

/// Khung dieu huong GOC cua app (thay the cap VanListScreen -> push ->
/// DashboardScreen truoc day) - MOT thanh 5-tab-o-duoi DUY NHAT cho toan bo
/// app: Giam Sat/Cai Dat/He Thong (cua VAN DANG CHON) + Quan Ly Van (danh
/// sach toan bo van, chon van khac tu day thay vi phai "thoat ra" man hinh
/// rieng) + Tai Khoan (sau Quan Ly Van). Ly do gop lam 1: "Quan Ly Van" va
/// "Tai Khoan" deu phai la tab luon co san o thanh dieu huong - 1 tab KHONG
/// THE vua la noi dung nhung cung vua la 1 man hinh duoc PUSH rieng, nen
/// phai hop nhat thanh 1 shell duy nhat, "van dang chon" la 1 STATE cua
/// shell nay thay vi 1 THAM SO cua route.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  // Mac dinh mo vao tab Quan Ly Van (index 3) - nguoi dung tu chon 1 van tu
  // danh sach, sau do shell tu chuyen sang tab Giam Sat (index 0).
  int _navIndex = 3;
  DashboardProvider? _dashProvider;
  StreamSubscription<String>? _eventsSub;
  StreamSubscription<String>? _blePromptSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VanListProvider>().load();
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _blePromptSub?.cancel();
    _dashProvider?.dispose();
    super.dispose();
  }

  /// Nguoi dung chon 1 van tu tab "Quan Ly Van" - tao DashboardProvider MOI
  /// cho van do (huy provider cu neu co), roi chuyen sang tab Giam Sat. [FIX]
  /// Neu van DANG XEM hien dang giu 1 ket noi BLE that su (activeTransport ==
  /// ble) - PHAI hoi truoc khi chuyen, vi dispose() provider cu se ngat ket
  /// noi BLE do NGAY LAP TUC (dien thoai chi giu duoc 1 ket noi GATT tai 1
  /// thoi diem - xem BleService._activeGattConnections) - khong duoc ngat
  /// ngam mot ket noi dang dieu khien/giam sat cuc bo ma khong bao truoc.
  Future<void> _selectVan(Van v) async {
    final current = _dashProvider;
    if (current != null &&
        current.van.mqttPrefix != v.mqttPrefix &&
        current.activeTransport == ActiveTransport.ble) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ngắt kết nối Bluetooth?'),
          content: Text(
            'Đang điều khiển/giám sát van "${current.van.displayName}" qua Bluetooth. '
            'Để chuyển sang van "${v.displayName}", cần ngắt kết nối này trước. Tiếp tục?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ngắt & Chuyển Van'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    _eventsSub?.cancel();
    _blePromptSub?.cancel();
    _dashProvider?.dispose();
    final provider = DashboardProvider(van: v, prefsService: PrefsService());
    provider.loadConfigAndConnect();
    _eventsSub = provider.events.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
      );
    });
    // [NEW] Hoi truoc khi tu dong ket noi BLE khi mat MQTT (xem
    // DashboardProvider.tryBleFallback()/confirmBleFallback()) - SnackBar co
    // nut bam "KẾT NỐI", neu nguoi dung bo qua/de tu tat thi coi nhu tu choi
    // (declineBleFallback() tam ngung hoi lai vai phut).
    _blePromptSub = provider.bleFallbackPrompts.listen((msg) {
      if (!mounted) return;
      final controller = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'KẾT NỐI',
            onPressed: provider.confirmBleFallback,
          ),
        ),
      );
      controller.closed.then((reason) {
        if (reason != SnackBarClosedReason.action) {
          provider.declineBleFallback();
        }
      });
    });
    setState(() {
      _dashProvider = provider;
      _navIndex = 0;
    });
  }

  void _onDestinationSelected(int i) {
    final vanList = context.read<VanListProvider>();
    if (i == 3) {
      vanList.startLiveStatus();
    } else if (_navIndex == 3) {
      // [FIX] Roi khoi tab "Quan Ly Van" - dung dich vu theo doi TRUC TIEP
      // toan bo van (VanStatusChecker) de khong giu 2 ket noi MQTT song song
      // toi cung 1 van (rieng cua DashboardProvider dang xem + chung cua
      // danh sach) khi khong con hien thi gi tu no.
      vanList.stopLiveStatus();
    }
    setState(() => _navIndex = i);
    if (i == 1 && _dashProvider != null) _dashProvider!.publish('SETTINGS?');
  }

  Widget _buildStatusPill(DashboardProvider prov) {
    // [FIX] Phai xet activeTransport (co tinh den _mqttProven) VA
    // isConnectionStale, KHONG duoc chi xet connState tho - xem chu thich
    // day du (nguyen ban) trong dashboard_screen.dart truoc khi gop vao day.
    final transport = prov.activeTransport;
    final isStale = prov.isConnectionStale;
    final onMqtt = transport == ActiveTransport.mqtt && !isStale;
    final onBle = transport == ActiveTransport.ble;
    final connecting = prov.connState == MqttConnState.connecting;
    final dotColor = onMqtt
        ? const Color(0xFF4ADE80)
        : onBle
            ? const Color(0xFF60A5FA)
            : (connecting ? const Color(0xFFFBBF24) : const Color(0xFFF87171));
    final label = onMqtt
        ? 'ONLINE'
        : onBle
            ? 'BLUETOOTH'
            : (connecting ? 'ĐANG KẾT NỐI' : 'MẤT KẾT NỐI');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onBle)
              const Icon(Icons.bluetooth, size: 12, color: Colors.white)
            else
              Container(width: 7, height: 7, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  static const _noVanPlaceholder = Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Chưa chọn van nào.\nVào tab "Quản Lý Van" để chọn 1 van.',
        textAlign: TextAlign.center,
      ),
    ),
  );

  /// Key theo mqttPrefix cua van dang chon - bat buoc de Flutter HUY State cu
  /// va TAO MOI khi doi sang van KHAC (IndexedStack mac dinh giu nguyen State
  /// neu widget cung runtimeType, se lam MonitorTab/VanSettingsTab "dinh" du
  /// lieu/initState cua van CU khi chuyen van neu khong co key nay).
  Widget _dashboardTabOrPlaceholder(Widget Function(Key key) builder, String tabTag) {
    final prov = _dashProvider;
    if (prov == null) return _noVanPlaceholder;
    return builder(ValueKey('${tabTag}_${prov.van.mqttPrefix}'));
  }

  @override
  Widget build(BuildContext context) {
    final isVanListTab = _navIndex == 3;
    final isAccountTab = _navIndex == 4;
    final String title;
    if (isVanListTab) {
      title = 'Quản Lý Van';
    } else if (isAccountTab) {
      title = 'Tài Khoản';
    } else {
      title = _dashProvider?.van.displayName ?? 'Chưa chọn van';
    }
    final scaffold = Scaffold(
      appBar: AppBar(
        title: Text(title, overflow: TextOverflow.ellipsis),
        actions: [
          // [FIX] Bo nut icon "Tài khoản" tren AppBar - gio da la 1 tab rieng
          // luon co san o thanh dieu huong duoi (sau "Quan Ly Van"), khong
          // can 1 loi tat thu 2 trung lap nua.
          if (!isVanListTab && !isAccountTab && _dashProvider != null)
            Consumer<DashboardProvider>(builder: (ctx, prov, _) => _buildStatusPill(prov)),
        ],
      ),
      body: IndexedStack(
        index: _navIndex,
        children: [
          _dashboardTabOrPlaceholder((k) => MonitorTab(key: k), 'monitor'),
          _dashboardTabOrPlaceholder((k) => VanSettingsTab(key: k), 'settings'),
          _dashboardTabOrPlaceholder((k) => SystemTab(key: k), 'system'),
          VanListTab(onSelectVan: _selectVan),
          const AccountTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: _onDestinationSelected,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Giám Sát'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Cài Đặt'),
          NavigationDestination(icon: Icon(Icons.developer_board_outlined), selectedIcon: Icon(Icons.developer_board), label: 'Hệ Thống'),
          NavigationDestination(icon: Icon(Icons.water_drop_outlined), selectedIcon: Icon(Icons.water_drop), label: 'Quản Lý Van'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Tài Khoản'),
        ],
      ),
    );

    // [FIX] DashboardProvider phai bao TRUM CA AppBar (status pill) LAN body
    // (Giam Sat/Cai Dat/He Thong) - dat Provider chi quanh IndexedStack se
    // khien Consumer<DashboardProvider> trong AppBar.actions (1 nhanh KHAC,
    // khong phai con chau cua IndexedStack) khong tim thay Provider, nem
    // ProviderNotFoundException (da gap khi chay thu tren dien thoai).
    if (_dashProvider == null) return scaffold;
    return ChangeNotifierProvider<DashboardProvider>.value(value: _dashProvider!, child: scaffold);
  }
}
