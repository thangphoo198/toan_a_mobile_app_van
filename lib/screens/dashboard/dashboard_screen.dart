import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/van.dart';
import '../../services/prefs_service.dart';
import '../../state/dashboard_provider.dart';
import 'account_tab.dart';
import 'monitor_tab.dart';
import 'system_tab.dart';
import 'van_settings_tab.dart';

class DashboardScreen extends StatefulWidget {
  final Van van;
  const DashboardScreen({super.key, required this.van});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardProvider _provider;
  StreamSubscription<String>? _eventsSub;
  int _navIndex = 0;

  // [FIX] Gop "Dieu Khien" vao chung trang "Giam Sat" (xem ControlTab duoc
  // nhung vao MonitorTab) - con lai 4 muc bottom-nav thay vi 5.
  static const _pages = [
    MonitorTab(),
    VanSettingsTab(),
    SystemTab(),
    AccountTab(),
  ];

  @override
  void initState() {
    super.initState();
    _provider = DashboardProvider(van: widget.van, prefsService: PrefsService());
    _provider.loadConfigAndConnect();
    // Thong bao chuyen doi transport (mat Internet -> Bluetooth, khoi phuc
    // Internet, khong tim thay van qua Bluetooth...) - phat tu provider qua
    // Stream (xem DashboardProvider._notify()), hien SnackBar noi bat o day
    // vi Provider (ChangeNotifier thuan) khong co BuildContext.
    _eventsSub = _provider.events.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
      );
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DashboardProvider>.value(
      value: _provider,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.van.displayName, overflow: TextOverflow.ellipsis),
          actions: [
            Consumer<DashboardProvider>(
              builder: (ctx, prov, _) {
                // [FIX] Phai xet activeTransport (co tinh den _mqttProven),
                // KHONG duoc chi xet connState tho - connState=connected chi
                // co nghia da ket noi toi BROKER, van co the chua tung phan
                // hoi gi (vd chua co WiFi) trong khi BLE moi la kenh THAT SU
                // dang dung. Xet rieng connState se hien "ONLINE" gia trong
                // luc thuc ra dang dieu khien/giam sat qua Bluetooth.
                final transport = prov.activeTransport;
                final onMqtt = transport == ActiveTransport.mqtt;
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
                        // [FIX] Kenh Bluetooth dung icon Bluetooth chuan (Icons.bluetooth)
                        // thay vi emoji "🔵" trong chuoi text - cac kenh khac van dung
                        // dau cham mau nhu cu.
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
              },
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Làm Mới',
              // [FIX] KHONG dung context.read<DashboardProvider>() o day: "context"
              // trong build() nay la context CUA CHINH DashboardScreen (ancestor
              // cua ChangeNotifierProvider ma ta dang tao ben duoi trong cung ham
              // build), khong phai descendant - Provider se KHONG BAO GIO tim thay
              // no, nem "Could not find the correct Provider<DashboardProvider>
              // above this DashboardScreen Widget" moi lan bam nut (da xac nhan
              // qua log that tren may). Dung thang field _provider da co san.
              onPressed: () => _provider.refreshAll(),
            ),
          ],
        ),
        body: IndexedStack(index: _navIndex, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _navIndex,
          onDestinationSelected: (i) => setState(() => _navIndex = i),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Giám Sát'),
            NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'Cài Đặt'),
            NavigationDestination(icon: Icon(Icons.developer_board_outlined), selectedIcon: Icon(Icons.developer_board), label: 'Hệ Thống'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Tài Khoản'),
          ],
        ),
      ),
    );
  }
}
