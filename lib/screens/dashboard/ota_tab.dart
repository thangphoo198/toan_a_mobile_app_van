import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/dashboard_provider.dart';
import '../../widgets/common.dart';

class OtaTab extends StatefulWidget {
  const OtaTab({super.key});

  @override
  State<OtaTab> createState() => _OtaTabState();
}

class _OtaTabState extends State<OtaTab> {
  final _urlCtrl = TextEditingController(
    text: 'http://103.143.207.89/app_ota_van4m3.bin',
  );

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<DashboardProvider>();
    final t = prov.telemetry;

    return OfflineLockNotice(
      locked: prov.isOfflineOnly,
      message: 'Nạp OTA / quản lý file cần kết nối Internet (MQTT) thật - hiện đang ở chế độ cục bộ (Bluetooth hoặc mất kết nối), tính năng này tạm khoá.',
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SectionCard(
            title: 'Tải & Nạp Firmware CH32 Từ Xa',
            icon: Icons.cloud_download,
            children: [
              const Text(
                'Gửi lệnh qua MQTT để ESP32 tự động tải file .bin từ URL, lưu vào LittleFS và nạp IAP vào CH32X035.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: 'URL file .bin',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => setState(
                      () => _urlCtrl.text =
                          'http://103.143.207.89/app_ota_van4m3.bin',
                    ),
                    child: const Text('Preset: app_ota_van4m3.bin'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(
                      () =>
                          _urlCtrl.text = 'http://103.143.207.89/apptest2.bin',
                    ),
                    child: const Text('Preset: apptest2.bin'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.rocket_launch),
                label: const Text('Gửi Lệnh Nạp OTA Qua MQTT'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: () async {
                  final url = _urlCtrl.text.trim();
                  if (url.isEmpty)
                    return showSnack(
                      context,
                      'Vui lòng nhập URL.',
                      isError: true,
                    );
                  final ok = await confirmDialog(
                    context,
                    title: 'Nạp OTA?',
                    message: 'Gửi lệnh OTA tải file từ:\n$url ?',
                  );
                  if (ok && context.mounted)
                    context.read<DashboardProvider>().publish('DOWNLOAD:$url');
                },
              ),
            ],
          ),
          SectionCard(
            title: 'File Firmware Trong ESP32 (LittleFS)',
            icon: Icons.folder,
            trailing: TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Quét'),
              onPressed: () =>
                  context.read<DashboardProvider>().publish('FILES?'),
            ),
            children: [
              if (t.usedBytes != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Flash: ${((t.usedBytes ?? 0) / 1024).toStringAsFixed(0)} / ${((t.totalBytes ?? 0) / 1024).toStringAsFixed(0)} KB',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              if (t.files.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Chưa có dữ liệu — bấm Quét để tải danh sách.'),
                )
              else
                ...t.files.map(
                  (f) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.insert_drive_file),
                      title: Text(f.name),
                      subtitle: Text(
                        f.formattedSize ??
                            '${(f.size / 1024).toStringAsFixed(1)} KB',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.bolt, color: Colors.green),
                            tooltip: 'Nạp CH32',
                            onPressed: () async {
                              final ok = await confirmDialog(
                                context,
                                title: 'Nạp firmware?',
                                message:
                                    'Nạp file "${f.path}" vào chip CH32X035 qua IAP?',
                              );
                              if (ok && context.mounted)
                                context.read<DashboardProvider>().publish(
                                  'FLASH:${f.path}',
                                );
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
                            tooltip: 'Xoá',
                            onPressed: () async {
                              final ok = await confirmDialog(
                                context,
                                title: 'Xoá file?',
                                message:
                                    'Xác nhận xoá file "${f.path}" khỏi Flash ESP32?',
                              );
                              if (ok && context.mounted)
                                context.read<DashboardProvider>().publish(
                                  'DELETE:${f.path}',
                                );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SectionCard(
            title: 'Tiến Trình Nạp IAP',
            icon: Icons.timeline,
            trailing: StatusPill(
              text: t.otaInProgress
                  ? 'ĐANG NẠP ${t.otaPercent ?? 0}%'
                  : (t.otaOk == true
                        ? 'THÀNH CÔNG'
                        : (t.otaOk == false ? 'THẤT BẠI' : 'SẴN SÀNG')),
              color: t.otaInProgress
                  ? Colors.orange
                  : (t.otaOk == true
                        ? Colors.green
                        : (t.otaOk == false ? Colors.red : Colors.blueGrey)),
            ),
            children: [
              LinearProgressIndicator(value: (t.otaPercent ?? 0) / 100),
              const SizedBox(height: 8),
              Text(
                t.otaStatusText,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
