import 'package:flutter/material.dart';

import '../../../../data/services/s11_ble_service.dart';
import '../../../../domain/models/s11_models.dart';
import '../../../core/app_theme.dart';
import '../view_models/s11_dashboard_view_model.dart';

class S11DashboardScreen extends StatelessWidget {
  const S11DashboardScreen({super.key, required this.viewModel});

  final S11DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (BuildContext context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.cyanAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.watch_rounded,
                    color: AppTheme.cyanAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'S11 Companion',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'HryFine BLE Protocol (0xAB) • Bebas Iklan',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: viewModel.status),
              ],
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _ConnectionAndBatteryCard(viewModel: viewModel),
              const SizedBox(height: 16),
              _TimeSyncCard(viewModel: viewModel),
              const SizedBox(height: 16),
              _NotificationAndCallTestCard(viewModel: viewModel),
              const SizedBox(height: 16),
              _PacketLogConsoleCard(viewModel: viewModel),
            ],
          ),
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final S11ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final Color color = switch (status) {
      S11ConnectionStatus.connected => AppTheme.limeAccent,
      S11ConnectionStatus.scanning ||
      S11ConnectionStatus.connecting =>
        AppTheme.amberAccent,
      S11ConnectionStatus.error => AppTheme.coralAccent,
      S11ConnectionStatus.disconnected => Colors.white54,
    };

    return Container(
      key: const Key('connection_status_badge'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionAndBatteryCard extends StatelessWidget {
  const _ConnectionAndBatteryCard({required this.viewModel});

  final S11DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final int? battery = viewModel.batteryLevel;
    final String batteryText = battery != null ? '$battery%' : '--%';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: [
            AppTheme.surfaceElevated,
            AppTheme.surfaceDark.withValues(alpha: 0.96),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: AppTheme.cyanAccent.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TARGET PERANGKAT BLE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: AppTheme.cyanAccent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      viewModel.deviceName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      viewModel.deviceId != null
                          ? 'ID / MAC: ${viewModel.deviceId}'
                          : (viewModel.savedDeviceId != null
                              ? 'MAC Tersimpan: ${viewModel.savedDeviceId}'
                              : 'UART Service: ${S11BleService.primaryServiceUuid.str128}'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundDark.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          battery != null && battery > 20
                              ? Icons.battery_charging_full_rounded
                              : Icons.battery_std_rounded,
                          size: 18,
                          color: AppTheme.limeAccent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          batteryText,
                          key: const Key('battery_percentage_text'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Baterai (0x180F)',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (viewModel.statusMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                viewModel.statusMessage!,
                key: const Key('status_message_text'),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (!viewModel.isConnected) ...[
                FilledButton.icon(
                  key: const Key('scan_connect_button'),
                  onPressed: viewModel.isBusy ? null : viewModel.scanAndConnect,
                  icon: Icon(
                    viewModel.isBusy
                        ? Icons.radar_rounded
                        : (viewModel.savedDeviceId != null
                            ? Icons.bolt_rounded
                            : Icons.bluetooth_searching_rounded),
                    size: 18,
                  ),
                  label: Text(
                    viewModel.isBusy
                        ? 'Menghubungkan...'
                        : (viewModel.savedDeviceId != null
                            ? 'Hubungkan Cepat "S11"'
                            : 'Scan & Hubungkan "S11"'),
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('rescan_button'),
                  onPressed: viewModel.isBusy ? null : viewModel.rescanDevices,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Scan Ulang'),
                ),
              ] else
                OutlinedButton.icon(
                  key: const Key('disconnect_button'),
                  onPressed: viewModel.disconnect,
                  icon: const Icon(Icons.bluetooth_disabled_rounded, size: 18),
                  label: const Text('Putuskan Koneksi'),
                ),
              OutlinedButton.icon(
                key: const Key('read_battery_button'),
                onPressed:
                    viewModel.isConnected ? viewModel.refreshBattery : null,
                icon: const Icon(Icons.battery_saver_rounded, size: 18),
                label: const Text('Baca Baterai 0x180F'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeSyncCard extends StatelessWidget {
  const _TimeSyncCard({required this.viewModel});

  final S11DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final DateTime? lastSync = viewModel.lastTimeSync;
    final String lastSyncLabel = lastSync != null
        ? '${lastSync.year}-${_twoDigits(lastSync.month)}-${_twoDigits(lastSync.day)} '
            '${_twoDigits(lastSync.hour)}:${_twoDigits(lastSync.minute)}:${_twoDigits(lastSync.second)}'
        : 'Belum disinkronkan';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.cyanAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.access_time_filled_rounded,
                    color: AppTheme.cyanAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sinkronisasi Waktu Smartwatch',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Otomatis saat terhubung • Bit-packing 4-byte (cmd=2, key=1)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Sinkron terakhir: $lastSyncLabel',
                    key: const Key('last_sync_time_text'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  key: const Key('manual_sync_time_button'),
                  onPressed: () async {
                    await viewModel.syncTimeManual();
                    if (context.mounted) {
                      _showActionSnackBar(
                        context,
                        viewModel.statusMessage ?? 'Sync Waktu dikirim.',
                      );
                    }
                  },
                  icon: const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('Sync Waktu Manual'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');
}

class _NotificationAndCallTestCard extends StatelessWidget {
  const _NotificationAndCallTestCard({required this.viewModel});

  final S11DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Uji Coba Push Notifikasi & Panggilan (Tahap 1)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Mengirim frame protokol 0xAB ke Characteristic 6e400002-b5a3-f393-e0a9-e50e24dcca9f',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('test_telegram_notification_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.cyanAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  await viewModel.testTelegramNotification();
                  if (context.mounted) {
                    _showActionSnackBar(
                      context,
                      viewModel.statusMessage ??
                          'Test Notifikasi Telegram (Byte 4) diproses.',
                    );
                  }
                },
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text(
                  'Test Notifikasi Telegram (Byte 4)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    key: const Key('test_whatsapp_call_button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.limeAccent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                    onPressed: () async {
                      await viewModel.testWhatsAppIncomingCall();
                      if (context.mounted) {
                        _showActionSnackBar(
                          context,
                          viewModel.statusMessage ??
                              'Test Panggilan WhatsApp (Key 17) diproses.',
                        );
                      }
                    },
                    icon: const Icon(Icons.ring_volume_rounded, size: 18),
                    label: const Text(
                      'Test Panggilan WhatsApp (Key 17)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    key: const Key('end_whatsapp_call_button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.coralAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 14,
                      ),
                    ),
                    onPressed: () async {
                      await viewModel.testWhatsAppEndCall();
                      if (context.mounted) {
                        _showActionSnackBar(
                          context,
                          viewModel.statusMessage ?? 'Perintah Stop Dering diproses.',
                        );
                      }
                    },
                    icon: const Icon(Icons.call_end_rounded, size: 16),
                    label: const Text(
                      'Stop Dering',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PacketLogConsoleCard extends StatelessWidget {
  const _PacketLogConsoleCard({required this.viewModel});

  final S11DashboardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final List<S11PacketLog> logs = viewModel.packetLogs;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Inspector Paket BLE (Header 0xAB)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (logs.isNotEmpty)
                  TextButton(
                    key: const Key('clear_logs_button'),
                    onPressed: viewModel.clearPacketLogs,
                    child: const Text('Bersihkan'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (logs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Belum ada paket dikirim. Tekan tombol Sync Waktu, Test Notifikasi Telegram, atau Test Panggilan WhatsApp untuk melihat frame heksadesimal.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              )
            else
              ...logs.take(6).map(
                    (S11PacketLog entry) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundDark.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  '[${entry.direction}] ${entry.title}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: entry.direction == 'RX'
                                        ? AppTheme.limeAccent
                                        : AppTheme.cyanAccent,
                                  ),
                                ),
                              ),
                              Text(
                                '${entry.packet.length}B • ${entry.direction == 'RX' ? "Notify RX" : (entry.transmittedOverBle ? "GATT TX" : "Preview")}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: entry.transmittedOverBle
                                      ? AppTheme.limeAccent
                                      : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            entry.hexString,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

void _showActionSnackBar(BuildContext context, String message) {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(milliseconds: 1200),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
