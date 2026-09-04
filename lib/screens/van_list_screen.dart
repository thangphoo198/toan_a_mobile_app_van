import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/van.dart';
import '../state/auth_provider.dart';
import '../state/van_list_provider.dart';
import '../widgets/common.dart';
import 'ble_pair_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'login_screen.dart';

class VanListScreen extends StatefulWidget {
  const VanListScreen({super.key});

  @override
  State<VanListScreen> createState() => _VanListScreenState();
}

class _VanListScreenState extends State<VanListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VanListProvider>().load();
    });
  }

  Future<void> _openAddDialog() async {
    final codeCtrl = TextEditingController();
    final prefixCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    String? model;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm Van Mới'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'Mã van (vd: VAN-01)')),
              const SizedBox(height: 10),
              TextField(
                controller: prefixCtrl,
                decoration: const InputDecoration(labelText: 'MQTT Topic Prefix (vd: van_E6EBAC)'),
              ),
              const SizedBox(height: 10),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên hiển thị (tuỳ chọn)')),
              const SizedBox(height: 10),
              StatefulBuilder(
                builder: (ctx, setSt) => DropdownButtonFormField<String>(
                  initialValue: model,
                  decoration: const InputDecoration(labelText: 'Model van (tuỳ chọn)'),
                  items: Van.modelLabels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setSt(() => model = v),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Thêm')),
        ],
      ),
    );

    if (ok != true) return;
    if (codeCtrl.text.trim().isEmpty || prefixCtrl.text.trim().isEmpty) {
      if (mounted) showSnack(context, 'Vui lòng nhập đủ mã van và MQTT prefix.', isError: true);
      return;
    }
    if (!mounted) return;
    final provider = context.read<VanListProvider>();
    final success = await provider.addVan(
      code: codeCtrl.text.trim(),
      mqttPrefix: prefixCtrl.text.trim(),
      model: model,
      name: nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
    );
    if (!mounted) return;
    if (!success) {
      showSnack(context, provider.error ?? 'Không thêm được van.', isError: true);
    }
  }

  Future<void> _openAddMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(alignment: Alignment.centerLeft, child: Text('Thêm Van Mới', style: TextStyle(fontWeight: FontWeight.w700))),
            ),
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: const Text('Ghép nối qua Bluetooth'),
              subtitle: const Text('Tự nhận mã van, cài WiFi trực tiếp từ điện thoại - không cần biết trước mã van'),
              onTap: () => Navigator.pop(ctx, 'ble'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Nhập mã van thủ công'),
              subtitle: const Text('Dùng khi đã biết mã van và MQTT prefix'),
              onTap: () => Navigator.pop(ctx, 'manual'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'ble') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlePairScreen()));
    } else if (choice == 'manual') {
      _openAddDialog();
    }
  }

  Future<void> _deleteVan(Van v) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Xoá van?',
      message: 'Xoá "${v.displayName}" khỏi tài khoản của bạn?',
    );
    if (!confirmed || !mounted) return;
    final provider = context.read<VanListProvider>();
    final ok = await provider.deleteVan(v.id);
    if (!ok && mounted) {
      showSnack(context, provider.error ?? 'Không xoá được van.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final vanList = context.watch<VanListProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Van Của Tôi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Đăng xuất',
            onPressed: () async {
              await context.read<AuthProvider>().logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => vanList.load(),
        child: vanList.loading
            ? const Center(child: CircularProgressIndicator())
            : vanList.vans.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 100),
                      Center(
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.water_drop_outlined, size: 44, color: Theme.of(context).colorScheme.onPrimaryContainer),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: Text(
                          auth.user != null ? 'Chào ${auth.user!['username']}!' : 'Chưa có van nào',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: Text(
                          'Bấm nút + để thêm van đầu tiên của bạn.',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 88, top: 8),
                    itemCount: vanList.vans.length,
                    itemBuilder: (ctx, i) {
                      final v = vanList.vans[i];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          leading: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.water_drop, color: Theme.of(context).colorScheme.onPrimaryContainer),
                          ),
                          title: Text(v.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('Mã: ${v.code} • Prefix: ${v.mqttPrefix}${v.model != null ? ' • ${v.modelLabel}' : ''}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _deleteVan(v),
                          ),
                          onTap: () {
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => DashboardScreen(van: v)));
                          },
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddMenu,
        icon: const Icon(Icons.add),
        label: const Text('Thêm Van'),
      ),
    );
  }
}
