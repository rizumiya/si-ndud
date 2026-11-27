import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartwatch_app/data/protocol/s11_ble_protocol.dart';
import 'package:smartwatch_app/data/services/s11_ble_service.dart';
import 'package:smartwatch_app/main.dart';
import 'package:smartwatch_app/ui/features/dashboard/view_models/s11_dashboard_view_model.dart';

class FakeS11BleAdapter implements S11BleAdapter {
  FakeS11BleAdapter({this.simulatedBatteryLevel = 87});

  final int simulatedBatteryLevel;
  final List<Uint8List> writtenPackets = <Uint8List>[];
  String? lastSavedDeviceIdReceived;
  bool? lastForceScanReceived;
  void Function(List<int> data)? _onNotificationReceived;
  void Function()? _onDisconnected;

  @override
  Future<void> scanAndConnect({
    required String targetName,
    required Duration timeout,
    String? savedDeviceId,
    bool forceScan = false,
    required void Function(String deviceId, String deviceName) onDeviceConnected,
    required void Function(List<int> data) onNotificationReceived,
    required void Function() onDisconnected,
  }) async {
    lastSavedDeviceIdReceived = savedDeviceId;
    lastForceScanReceived = forceScan;
    _onNotificationReceived = onNotificationReceived;
    _onDisconnected = onDisconnected;
    onDeviceConnected(savedDeviceId ?? '41:42:1A:84:D7:98', targetName);
  }

  void emitIncomingNotification(List<int> rawData) {
    _onNotificationReceived?.call(rawData);
  }

  @override
  Future<int?> readBatteryPercentage() async => simulatedBatteryLevel;

  @override
  Future<bool> writeCommand(Uint8List packet) async {
    writtenPackets.add(packet);
    return true;
  }

  @override
  Future<void> disconnect() async {
    _onDisconnected?.call();
  }
}

void main() {
  group('S11BleProtocol Specification Tests', () {
    test('getSendByte wraps empty payload with 8-byte 0xAB header', () {
      final Uint8List packet = S11BleProtocol.getSendByte(cmd: 2, key: 1);
      expect(
        packet,
        equals(Uint8List.fromList(<int>[0xAB, 0x00, 0x05, 0x02, 0x01, 0x01, 0x00, 0x00])),
      );
    });

    test('buildTimeSyncPacket bit-packs year, month, day, hour, minute, second', () {
      final DateTime sampleTime = DateTime(2026, 11, 27, 22, 30, 44);
      final Uint8List packet = S11BleProtocol.buildTimeSyncPacket(sampleTime);

      expect(packet.length, equals(12));
      expect(packet[0], equals(0xAB));
      expect(packet[1], equals(0x00));
      expect(packet[2], equals(0x09)); // payload(4) + 5
      expect(packet[3], equals(0x02)); // cmd = 2
      expect(packet[4], equals(0x01)); // version = 1
      expect(packet[5], equals(0x01)); // key = 1
      expect(packet[6], equals(0x00));
      expect(packet[7], equals(0x04)); // payload length = 4

      // Verify exact formula from docs/S11_BLE_PROTOCOL.md
      const int y = 26;
      const int m = 11;
      const int d = 27;
      const int h = 22;
      const int min = 30;
      const int s = 44;
      expect(packet[8], equals(((y << 2) | ((m & 0xFF) >> 2)) & 0xFF));
      expect(packet[9], equals((((m & 3) << 6) | (d << 1) | (h >> 4)) & 0xFF));
      expect(packet[10], equals((((h & 15) << 4) | (min >> 2)) & 0xFF));
      expect(packet[11], equals((((min & 3) << 6) | s) & 0xFF));
    });

    test('buildTelegramNotificationPacket strips non-ASCII, caps at 40 chars, uses cmd=2, key=18, appType=4', () {
      final Uint8List packet = S11BleProtocol.buildTelegramNotificationPacket(
        title: 'Telegram • Andi 🔥',
        content: 'Halo, ini tes pesan S11 yang sangat panjang sekali',
      );

      expect(packet[0], equals(0xAB));
      expect(packet[3], equals(2)); // cmd = 2
      expect(packet[5], equals(18)); // key = 18 (0x12)
      expect(packet[8], equals(4)); // payload[0] = 4 (Telegram/Facebook slot)
      expect(packet[9], equals(0x00));
      expect(packet[10], equals(0x00));

      final String decoded = ascii.decode(packet.sublist(11));
      expect(decoded.length, lessThanOrEqualTo(40));
      expect(decoded, equals('Telegram  Andi: Halo, ini tes pesan S11 '));
    });

    test('default Telegram test text fits exact 40 ASCII chars', () {
      final Uint8List packet = S11BleProtocol.buildTelegramNotificationPacket(
        title: 'Telegram - Andi',
        content: 'Halo, ini tes pesan S11',
      );
      final String decoded = ascii.decode(packet.sublist(11));
      expect(decoded, equals('Telegram - Andi: Halo, ini tes pesan S11'));
      expect(decoded.length, equals(40));
    });

    test('truncateUtf8Safely caps at 196 bytes without corrupting multi-byte UTF-8', () {
      final String longMultibyte = 'Halo 🔥' * 50;
      final Uint8List truncated = S11BleProtocol.truncateUtf8Safely(
        longMultibyte,
        S11BleProtocol.maxMessageUtf8Bytes,
      );

      expect(truncated.length, lessThanOrEqualTo(196));
      expect(() => utf8.decode(truncated), returnsNormally);
    });

    test('buildIncomingCallPacket uses cmd=2, key=17, status=1 and UTF-8 caller name', () {
      final Uint8List packet = S11BleProtocol.buildIncomingCallPacket(
        callerName: 'Budi WhatsApp',
        status: S11BleProtocol.callStatusIncoming,
      );

      expect(packet[0], equals(0xAB));
      expect(packet[3], equals(2)); // cmd = 2
      expect(packet[5], equals(17)); // key = 17 (0x11)
      expect(packet[8], equals(1)); // payload[0] = 1 (incoming ringing)
      expect(packet[9], equals(0x00));
      expect(utf8.decode(packet.sublist(10)), equals('Budi WhatsApp'));
    });

    test('splitIntoChunks splits packets > 20 bytes into <= 20-byte chunks sequentially', () {
      final Uint8List largePacket = S11BleProtocol.buildTelegramNotificationPacket(
        title: 'Telegram • Andi',
        content: 'Halo! Ini pesan uji coba ke Smartwatch S11.',
      );
      expect(largePacket.length, greaterThan(20));

      final List<Uint8List> chunks = S11BleProtocol.splitIntoChunks(largePacket);
      expect(chunks.length, greaterThan(1));
      for (int i = 0; i < chunks.length; i++) {
        expect(chunks[i].length, lessThanOrEqualTo(20));
        if (i < chunks.length - 1) {
          expect(chunks[i].length, equals(20));
        }
      }

      final List<int> reassembled = chunks.expand((Uint8List c) => c).toList();
      expect(reassembled, equals(largePacket));
    });
  });

  group('S11 Dashboard & BLE Service Integration Tests', () {
    testWidgets(
      'Persists MAC, fast-connects with saved MAC, logs [TX]/[RX], and triggers SnackBars',
      (WidgetTester tester) async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final FakeS11BleAdapter fakeAdapter =
            FakeS11BleAdapter(simulatedBatteryLevel: 92);
        final S11BleService bleService = S11BleService(
          adapter: fakeAdapter,
          clock: () => DateTime(2026, 11, 27, 22, 30, 0),
        );
        final S11DashboardViewModel viewModel =
            S11DashboardViewModel(bleService: bleService);

        await tester.pumpWidget(S11CompanionApp(viewModel: viewModel));
        await tester.pumpAndSettle();

        // 1. Initial disconnected state with Scan Ulang button visible
        expect(find.text('Terputus'), findsOneWidget);
        expect(find.text('--%'), findsOneWidget);
        expect(find.byKey(const Key('rescan_button')), findsOneWidget);

        // 2. Tap Scan & Hubungkan "S11" -> auto-connects & auto-syncs time (battery NOT auto-read)
        await tester.tap(find.byKey(const Key('scan_connect_button')));
        await tester.pumpAndSettle();

        expect(find.text('Terhubung'), findsOneWidget);
        expect(find.text('--%'), findsOneWidget);
        expect(bleService.savedDeviceId, equals('41:42:1A:84:D7:98'));
        // First written packet on connect must be Time Sync (cmd=2, key=1)
        expect(fakeAdapter.writtenPackets.length, equals(1));
        expect(fakeAdapter.writtenPackets.first[5], equals(1));

        // 2b. Tap Baca Baterai 0x180F manually -> reads 92%
        await tester.tap(find.byKey(const Key('read_battery_button')));
        await tester.pumpAndSettle();
        expect(find.text('92%'), findsOneWidget);

        // 2c. Simulate incoming [RX] notification from 6e400003-...
        fakeAdapter.emitIncomingNotification(<int>[0xAB, 0x00, 0x05, 0x02, 0x01, 0x01, 0x00, 0x00]);
        await tester.pumpAndSettle();

        // 3. Tap Sync Waktu Manual button -> SnackBar & TX
        await tester.tap(find.byKey(const Key('manual_sync_time_button')));
        await tester.pumpAndSettle();
        expect(fakeAdapter.writtenPackets.length, equals(2));
        expect(fakeAdapter.writtenPackets.last[5], equals(1));

        // 4. Tap Test Notifikasi Telegram (Byte 4) -> ASCII sanitized & capped
        final Finder telegramBtn =
            find.byKey(const Key('test_telegram_notification_button'));
        await tester.ensureVisible(telegramBtn);
        await tester.pumpAndSettle();
        await tester.tap(telegramBtn);
        await tester.pumpAndSettle();
        expect(fakeAdapter.writtenPackets.length, equals(3));
        expect(fakeAdapter.writtenPackets.last[5], equals(18)); // key = 18
        expect(fakeAdapter.writtenPackets.last[8], equals(4)); // appType = 4
        expect(
          ascii.decode(fakeAdapter.writtenPackets.last.sublist(11)),
          equals('Telegram - Andi: Halo, ini tes pesan S11'),
        );

        // 5. Tap Test Panggilan WhatsApp (Key 17)
        final Finder whatsappCallBtn =
            find.byKey(const Key('test_whatsapp_call_button'));
        await tester.ensureVisible(whatsappCallBtn);
        await tester.pumpAndSettle();
        await tester.tap(whatsappCallBtn);
        await tester.pumpAndSettle();
        expect(fakeAdapter.writtenPackets.length, equals(4));
        expect(fakeAdapter.writtenPackets.last[5], equals(17)); // key = 17
        expect(fakeAdapter.writtenPackets.last[8], equals(1)); // status = 1
        expect(
          ascii.decode(fakeAdapter.writtenPackets.last.sublist(10)),
          equals('WhatsApp - Budi Santoso'),
        );

        // 6. Tap Stop Dering (Key 17, status = 0)
        final Finder endCallBtn =
            find.byKey(const Key('end_whatsapp_call_button'));
        await tester.ensureVisible(endCallBtn);
        await tester.pumpAndSettle();
        await tester.tap(endCallBtn);
        await tester.pumpAndSettle();
        expect(fakeAdapter.writtenPackets.length, equals(5));
        expect(fakeAdapter.writtenPackets.last[5], equals(17)); // key = 17
        expect(fakeAdapter.writtenPackets.last[8], equals(0)); // status = 0

        // 7. Verify [TX] & [RX] logs appear in Inspector Paket BLE
        final Finder rxLogFinder =
            find.textContaining('[RX] Notify 6e400003 (8 byte)');
        await tester.scrollUntilVisible(
          rxLogFinder,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(rxLogFinder, findsOneWidget);
        expect(
          find.textContaining('[TX] Push Telegram (cmd=2, key=18, byte=4)'),
          findsOneWidget,
        );
        expect(
          find.textContaining('[TX] Panggilan WhatsApp Masuk (cmd=2, key=17, status=1)'),
          findsOneWidget,
        );
        expect(
          find.textContaining('[TX] Panggilan WhatsApp Berakhir (cmd=2, key=17, status=0)'),
          findsOneWidget,
        );

        // 8. Scroll back to top, disconnect, and test fast-path saved MAC + Scan Ulang button
        await tester.drag(find.byType(ListView), const Offset(0, 600));
        await tester.pumpAndSettle();
        final Finder disconnectBtn = find.byKey(const Key('disconnect_button'));
        await tester.ensureVisible(disconnectBtn);
        await tester.pumpAndSettle();
        await tester.tap(disconnectBtn);
        await tester.pumpAndSettle();
        expect(find.textContaining('MAC Tersimpan: 41:42:1A:84:D7:98'), findsOneWidget);

        await tester.tap(find.byKey(const Key('rescan_button')));
        await tester.pumpAndSettle();
        expect(fakeAdapter.lastForceScanReceived, isTrue);
      },
    );
  });
}
