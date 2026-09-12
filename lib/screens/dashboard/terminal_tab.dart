import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../state/dashboard_provider.dart';

class TerminalTab extends StatefulWidget {
  const TerminalTab({super.key});

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<TerminalTab> {
  final _cmdCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  static const _quickCmds = [
    'PING', 'POS?', 'FILES?', 'SETTINGS?', 'ESP_INFO?', 'WIFI_STATUS?', 'WIFI_SCAN',
    'GOTO:1', 'GOTO:2', 'GOTO:3', 'GOTO:4', 'GOTO:5', 'NEXT', 'RESET', 'OTA',
  ];

  @override
  void dispose() {
    _cmdCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send(BuildContext context) {
    final cmd = _cmdCtrl.text.trim();
    if (cmd.isEmpty) return;
    context.read<DashboardProvider>().publish(cmd);
    _cmdCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DashboardProvider>();
    final log = prov.telemetry.logLines;

    // [NEW] Terminal cho phep gui LENH THO BAT KY (RESET, MODEL, SETxxx, OTA,
    // khong chi GOTO/dieu khien don thuan) - manh nhat trong toan bo app nen
    // chan bang quyen CAI DAT (nghiem ngat nhat), khong tach rieng duoc theo
    // tung lenh vi day la 1 o nhap tu do.
    if (!prov.van.canConfigure) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline_rounded, size: 56, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                'Bạn không có quyền Cài Đặt van này — Terminal (lệnh thô) bị khoá.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _quickCmds
                .map((c) => ActionChip(label: Text(c, style: const TextStyle(fontSize: 11)), onPressed: () => prov.publish(c)))
                .toList(),
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
            child: log.isEmpty
                ? const Center(child: Text('[MQTT] Chưa có log...', style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11)))
                : ListView.builder(
                    controller: _scrollCtrl,
                    itemCount: log.length,
                    itemBuilder: (ctx, i) => Text(
                      log[i],
                      style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cmdCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Nhập lệnh (PING, POS?, GOTO:x, ...)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _send(context),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(icon: const Icon(Icons.send), onPressed: () => _send(context)),
              IconButton(
                icon: const Icon(Icons.clear_all),
                tooltip: 'Xoá log',
                onPressed: () => prov.telemetry.clearLog(),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
