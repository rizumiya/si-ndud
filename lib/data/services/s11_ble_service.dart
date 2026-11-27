import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/s11_models.dart';
import '../protocol/s11_ble_protocol.dart';

/// Abstraksi operasi BLE tingkat rendah agar `S11BleService` dapat berjalan
/// di perangkat fisik menggunakan `FlutterBluePlus` sekaligus dapat diuji
/// secara deterministik pada unit/widget test.
abstract class S11BleAdapter {
  Future<void> scanAndConnect({
    required String targetName,
    required Duration timeout,
    String? savedDeviceId,
    bool forceScan = false,
    required void Function(String deviceId, String deviceName) onDeviceConnected,
    required void Function(List<int> data) onNotificationReceived,
    required void Function() onDisconnected,
  });

  Future<void> disconnect();

  Future<int?> readBatteryPercentage();

  Future<bool> writeCommand(Uint8List packet);
}

/// Implementasi nyata `S11BleAdapter` menggunakan `flutter_blue_plus`.
class FlutterBluePlusS11Adapter implements S11BleAdapter {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeCharacteristic;
  BluetoothCharacteristic? _notifyCharacteristic;
  BluetoothCharacteristic? _batteryCharacteristic;
  int _negotiatedMtu = 23;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<BluetoothBondState>? _bondSubscription;
  StreamSubscription<List<int>>? _notifySubscription;
  Future<void>? _ongoingDiscovery;

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
    await _cancelScanSubscription();

    final String normalizedTarget = targetName.trim().toUpperCase();
    final Set<String> triedIds = <String>{};

    // 0. Fast-path: Jika MAC Address tersimpan ada & bukan scan ulang, langsung sambungkan via fromId
    final String? cleanSavedId = savedDeviceId?.trim();
    if (!forceScan && cleanSavedId != null && cleanSavedId.isNotEmpty) {
      triedIds.add(cleanSavedId);
      try {
        final BluetoothDevice directDevice =
            BluetoothDevice.fromId(cleanSavedId);
        await _establishGattSession(
          device: directDevice,
          onDeviceConnected: onDeviceConnected,
          onNotificationReceived: onNotificationReceived,
          onDisconnected: onDisconnected,
        );
        return;
      } catch (_) {
        // Fallback ke systemDevices / bondedDevices / BLE scan jika direct connect gagal
      }
    }

    final List<BluetoothDevice> priorityCandidates = <BluetoothDevice>[];

    void addCandidateIfMatches(BluetoothDevice device) {
      final String id = device.remoteId.str;
      if (triedIds.contains(id) ||
          priorityCandidates.any((BluetoothDevice d) => d.remoteId.str == id)) {
        return;
      }
      if (_matchesTargetName(
        target: normalizedTarget,
        platformName: device.platformName,
        advName: device.advName,
      )) {
        priorityCandidates.add(device);
      }
    }

    // 1. Cek perangkat GATT yang sudah terhubung di OS Android (systemDevices),
    //    perangkat yang aktif di app (connectedDevices), dan perangkat bonded.
    if (!forceScan) {
      try {
        final List<BluetoothDevice> sysDevices =
            await FlutterBluePlus.systemDevices(
          <Guid>[S11BleService.primaryServiceUuid],
        );
        for (final BluetoothDevice device in sysDevices) {
          addCandidateIfMatches(device);
        }
      } catch (_) {
        // Abaikan jika platform tidak mendukung systemDevices
      }

      for (final BluetoothDevice device in FlutterBluePlus.connectedDevices) {
        addCandidateIfMatches(device);
      }

      try {
        final List<BluetoothDevice> bonded =
            await FlutterBluePlus.bondedDevices;
        for (final BluetoothDevice device in bonded) {
          addCandidateIfMatches(device);
        }
      } catch (_) {
        // Abaikan jika platform tidak mendukung bondedDevices (mis. iOS)
      }
    }

    // Coba setiap kandidat S11 yang sudah diketahui OS/bonded (lewati MAC Classic
    // seperti :D7:CD jika tidak memiliki Nordic UART Service 6e400001-...).
    Object? lastCandidateError;
    for (final BluetoothDevice candidate in priorityCandidates) {
      triedIds.add(candidate.remoteId.str);
      try {
        await _establishGattSession(
          device: candidate,
          onDeviceConnected: onDeviceConnected,
          onNotificationReceived: onNotificationReceived,
          onDisconnected: onDisconnected,
        );
        return;
      } catch (error) {
        lastCandidateError = error;
      }
    }

    // 2. Jika belum ada kandidat tersimpan/OS yang berhasil (atau forceScan = true), lakukan BLE scan.
    final Completer<BluetoothDevice> foundCompleter =
        Completer<BluetoothDevice>();

    _scanSubscription = FlutterBluePlus.onScanResults.listen(
      (List<ScanResult> results) {
        for (final ScanResult result in results) {
          final String id = result.device.remoteId.str;
          if (!forceScan && triedIds.contains(id)) continue;

          final bool matched = _matchesTargetName(
            target: normalizedTarget,
            platformName: result.device.platformName,
            advName: result.advertisementData.advName.isNotEmpty
                ? result.advertisementData.advName
                : result.device.advName,
          );
          if (matched && !foundCompleter.isCompleted) {
            foundCompleter.complete(result.device);
            break;
          }
        }
      },
      onError: (Object error) {
        if (!foundCompleter.isCompleted) {
          foundCompleter.completeError(error);
        }
      },
    );

    await FlutterBluePlus.startScan(timeout: timeout);

    BluetoothDevice targetDevice;
    try {
      targetDevice = await foundCompleter.future.timeout(timeout);
    } catch (scanError) {
      if (lastCandidateError != null) {
        throw StateError(
          'Kandidat S11 tersambung/bonded gagal dihubungi ($lastCandidateError) dan pemindaian BLE tidak menemukan iklan baru.',
        );
      }
      rethrow;
    } finally {
      await FlutterBluePlus.stopScan();
      await _cancelScanSubscription();
    }

    await _establishGattSession(
      device: targetDevice,
      onDeviceConnected: onDeviceConnected,
      onNotificationReceived: onNotificationReceived,
      onDisconnected: onDisconnected,
    );
  }

  bool _matchesTargetName({
    required String target,
    required String platformName,
    required String advName,
  }) {
    final String pName = platformName.trim().toUpperCase();
    final String aName = advName.trim().toUpperCase();
    return pName == target || aName == target;
  }

  Future<void> _establishGattSession({
    required BluetoothDevice device,
    required void Function(String deviceId, String deviceName) onDeviceConnected,
    required void Function(List<int> data) onNotificationReceived,
    required void Function() onDisconnected,
  }) async {
    await device.connect(
      license: License.nonprofit,
      autoConnect: false,
      mtu: null,
      timeout: const Duration(seconds: 20),
    );
    _connectedDevice = device;

    await _connectionSubscription?.cancel();
    _connectionSubscription = device.connectionState.listen(
      (BluetoothConnectionState state) {
        if (state == BluetoothConnectionState.disconnected) {
          _clearCharacteristics();
          onDisconnected();
        }
      },
    );

    bool initialDiscoveryDone = false;
    BluetoothBondState? previousBondState;
    bool bondChangedToBondedDuringProcess = false;

    await _bondSubscription?.cancel();
    _bondSubscription = null;
    if (!kIsWeb && Platform.isAndroid) {
      _bondSubscription = device.bondState.listen(
        (BluetoothBondState bondState) {
          final bool transitionedToBonded =
              previousBondState != null &&
              previousBondState != BluetoothBondState.bonded &&
              bondState == BluetoothBondState.bonded;
          previousBondState = bondState;

          if (transitionedToBonded) {
            if (initialDiscoveryDone) {
              unawaited(_discoverAndBindCharacteristics(device));
            } else {
              bondChangedToBondedDuringProcess = true;
            }
          }
        },
        onError: (_) {
          // Abaikan error stream bondState agar tidak memutus sesi GATT
        },
      );
    }

    // Beri jeda 250ms setelah connect() sebelum discoverServices()
    await Future<void>.delayed(const Duration(milliseconds: 250));

    try {
      await _discoverAndBindCharacteristics(device);
      initialDiscoveryDone = true;

      if (bondChangedToBondedDuringProcess) {
        bondChangedToBondedDuringProcess = false;
        await _discoverAndBindCharacteristics(device);
      }
    } catch (error) {
      await _bondSubscription?.cancel();
      _bondSubscription = null;
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
      _clearCharacteristics();
      await device.disconnect();
      rethrow;
    }

    // Negosiasi MTU 247 segera setelah discoverServices() agar paket notifikasi/panggilan bisa dikirim utuh
    _negotiatedMtu = 23;
    try {
      final int requestedMtu = await device.requestMtu(247);
      if (requestedMtu > 0) {
        _negotiatedMtu = requestedMtu;
      }
    } catch (_) {
      _negotiatedMtu = device.mtuNow > 0 ? device.mtuNow : 23;
    }

    if (_notifyCharacteristic != null) {
      try {
        await _notifyCharacteristic!.setNotifyValue(true);
        await _notifySubscription?.cancel();
        _notifySubscription =
            _notifyCharacteristic!.onValueReceived.listen(onNotificationReceived);
      } catch (_) {
        // Kegagalan mengaktifkan notify tidak boleh menggagalkan koneksi utama
      }
    }

    // Beri jeda 200ms setelah setNotifyValue sebelum menulis paket sinkronisasi waktu
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final String resolvedName = device.platformName.trim().isNotEmpty
        ? device.platformName.trim()
        : (device.advName.trim().isNotEmpty
            ? device.advName.trim()
            : S11BleService.targetDeviceName);

    onDeviceConnected(device.remoteId.str, resolvedName);
  }

  Future<void> _discoverAndBindCharacteristics(BluetoothDevice device) async {
    final Future<void>? inFlight = _ongoingDiscovery;
    if (inFlight != null) {
      await inFlight;
    }

    final Completer<void> completer = Completer<void>();
    _ongoingDiscovery = completer.future;

    try {
      List<BluetoothService> services = await device.discoverServices();
      if (services.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        services = await device.discoverServices();
      }

      BluetoothService? primaryService;
      BluetoothCharacteristic? batteryChar;
      for (final BluetoothService service in services) {
        if (service.uuid == S11BleService.primaryServiceUuid) {
          primaryService = service;
        }
        if (service.uuid == S11BleService.batteryServiceUuid ||
            service.uuid == Guid('180f')) {
          for (final BluetoothCharacteristic c in service.characteristics) {
            if (c.uuid == S11BleService.batteryCharacteristicUuid ||
                c.uuid == Guid('2a19')) {
              batteryChar = c;
            }
          }
        }
      }

      if (primaryService == null) {
        throw StateError(
          'Service utama ${S11BleService.primaryServiceUuid.str128} tidak ditemukan pada perangkat ${device.remoteId.str}.',
        );
      }

      BluetoothCharacteristic? writeChar;
      BluetoothCharacteristic? notifyChar;
      for (final BluetoothCharacteristic c in primaryService.characteristics) {
        if (c.uuid == S11BleService.writeCharacteristicUuid) {
          writeChar = c;
        } else if (c.uuid == S11BleService.notifyCharacteristicUuid) {
          notifyChar = c;
        }
      }

      if (writeChar == null) {
        throw StateError(
          'Write Characteristic ${S11BleService.writeCharacteristicUuid.str128} tidak ditemukan.',
        );
      }

      _batteryCharacteristic = batteryChar;
      _writeCharacteristic = writeChar;
      _notifyCharacteristic = notifyChar;
    } finally {
      _ongoingDiscovery = null;
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  @override
  Future<int?> readBatteryPercentage() async {
    final BluetoothCharacteristic? characteristic = _batteryCharacteristic;
    if (characteristic == null) return null;

    final List<int> data = await characteristic.read();
    if (data.isEmpty) return null;
    return (data[0] & 0xFF).clamp(0, 100);
  }

  @override
  Future<bool> writeCommand(Uint8List packet) async {
    final BluetoothCharacteristic? characteristic = _writeCharacteristic;
    if (characteristic == null || _connectedDevice == null) {
      return false;
    }

    try {
      await _writeInChunks(characteristic, packet);
      return true;
    } catch (error) {
      if (error.toString().contains('GATT_INVALID_HANDLE') &&
          _connectedDevice != null) {
        await _discoverAndBindCharacteristics(_connectedDevice!);
        final BluetoothCharacteristic? refreshed = _writeCharacteristic;
        if (refreshed != null) {
          await _writeInChunks(refreshed, packet);
          return true;
        }
      }
      rethrow;
    }
  }

  Future<void> _writeInChunks(
    BluetoothCharacteristic characteristic,
    Uint8List packet,
  ) async {
    final int deviceMtu = _connectedDevice?.mtuNow ?? _negotiatedMtu;
    final int effectiveMtu =
        deviceMtu > _negotiatedMtu ? deviceMtu : _negotiatedMtu;

    // Jika MTU perangkat >= panjang paket (dan >= panjang + 3 ATT header), kirim sekaligus
    if (effectiveMtu >= packet.length && (effectiveMtu - 3) >= packet.length) {
      await _writeBytesWithFallback(characteristic, packet);
      return;
    }

    // Jika masih harus dipecah per 20 byte, kirim berurutan dengan jeda 60ms antar-chunk
    final List<Uint8List> chunks = S11BleProtocol.splitIntoChunks(
      packet,
      chunkSize: S11BleProtocol.maxBleMtuChunkBytes,
    );
    for (int i = 0; i < chunks.length; i++) {
      await _writeBytesWithFallback(characteristic, chunks[i]);
      if (i < chunks.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
  }

  Future<void> _writeBytesWithFallback(
    BluetoothCharacteristic characteristic,
    Uint8List bytes,
  ) async {
    try {
      await characteristic.write(bytes, withoutResponse: false);
    } catch (_) {
      await characteristic.write(bytes, withoutResponse: true);
    }
  }

  @override
  Future<void> disconnect() async {
    await _cancelScanSubscription();
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    await _bondSubscription?.cancel();
    _bondSubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    final BluetoothDevice? device = _connectedDevice;
    _clearCharacteristics();
    if (device != null) {
      await device.disconnect();
    }
  }

  Future<void> _cancelScanSubscription() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  void _clearCharacteristics() {
    _connectedDevice = null;
    _writeCharacteristic = null;
    _notifyCharacteristic = null;
    _batteryCharacteristic = null;
    _negotiatedMtu = 23;
  }
}

/// Service utama untuk manajemen koneksi BLE Smartwatch S11:
/// - Scan perangkat bernama `"S11"`
/// - Koneksi otomatis ke Nordic UART Service `6e400001-b5a3-f393-e0a9-e50e24dcca9f`
/// - Membaca level baterai dari Battery Service `0x180F` (`0x2A19`)
/// - Otomatis menjalankan sinkronisasi waktu (`cmd = 2, key = 1`) segera saat terhubung
class S11BleService {
  S11BleService({
    S11BleAdapter? adapter,
    DateTime Function()? clock,
  })  : _adapter = adapter ?? FlutterBluePlusS11Adapter(),
        _clock = clock ?? DateTime.now;

  static const String targetDeviceName = 'S11';
  static const String _savedRemoteIdKey = 's11_saved_remote_id';

  /// Primary Communication Service (Nordic UART Service)
  static final Guid primaryServiceUuid =
      Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9f');

  /// Write Characteristic (HP -> Jam)
  static final Guid writeCharacteristicUuid =
      Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9f');

  /// Notify Characteristic (Jam -> HP)
  static final Guid notifyCharacteristicUuid =
      Guid('6e400003-b5a3-f393-e0a9-e50e24dcca9f');

  /// Battery Service (`0x180F`)
  static final Guid batteryServiceUuid =
      Guid('0000180f-0000-1000-8000-00805f9b34fb');

  /// Battery Level Characteristic (`0x2A19`)
  static final Guid batteryCharacteristicUuid =
      Guid('00002a19-0000-1000-8000-00805f9b34fb');

  final S11BleAdapter _adapter;
  final DateTime Function() _clock;

  S11ConnectionStatus _status = S11ConnectionStatus.disconnected;
  S11ConnectionStatus get status => _status;

  String? _savedDeviceId;
  String? get savedDeviceId => _savedDeviceId;

  String? _connectedDeviceId;
  String? get connectedDeviceId => _connectedDeviceId;

  String _connectedDeviceName = targetDeviceName;
  String get connectedDeviceName => _connectedDeviceName;

  int? _batteryLevel;
  int? get batteryLevel => _batteryLevel;

  DateTime? _lastTimeSync;
  DateTime? get lastTimeSync => _lastTimeSync;

  String? _statusMessage;
  String? get statusMessage => _statusMessage;

  String? _lastWriteError;

  S11SensorSnapshot _sensorSnapshot = const S11SensorSnapshot();
  S11SensorSnapshot get sensorSnapshot => _sensorSnapshot;

  final List<S11PacketLog> _packetLogs = <S11PacketLog>[];
  List<S11PacketLog> get packetLogs => List<S11PacketLog>.unmodifiable(_packetLogs);

  final StreamController<void> _stateChanges =
      StreamController<void>.broadcast();
  Stream<void> get onStateChanged => _stateChanges.stream;

  bool get isConnected => _status == S11ConnectionStatus.connected;

  /// Memuat MAC Address (`remoteId`) S11 yang tersimpan di `SharedPreferences`.
  Future<void> loadSavedDevice() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? stored = prefs.getString(_savedRemoteIdKey);
      if (stored != null && stored.trim().isNotEmpty) {
        _savedDeviceId = stored.trim();
        _notifyStateChanged();
      }
    } catch (_) {
      // Abaikan jika SharedPreferences belum tersedia (mis. environment test tertentu)
    }
  }

  Future<void> _persistSavedDeviceId(String deviceId) async {
    _savedDeviceId = deviceId;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_savedRemoteIdKey, deviceId);
    } catch (_) {
      // Abaikan error penyimpanan lokal agar tidak mengganggu sesi BLE
    }
  }

  /// Menghapus MAC Address tersimpan jika ingin mengganti perangkat secara penuh.
  Future<void> clearSavedDevice() async {
    _savedDeviceId = null;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_savedRemoteIdKey);
    } catch (_) {
      // Abaikan
    }
    _notifyStateChanged();
  }

  /// Menghubungkan ke S11 (langsung via MAC tersimpan jika ada dan [forceScan] false,
  /// atau memindai iklan BLE perangkat bernama `"S11"` jika belum tersimpan / [forceScan] true).
  Future<void> scanAndConnect({
    Duration timeout = const Duration(seconds: 12),
    bool forceScan = false,
  }) async {
    if (_status == S11ConnectionStatus.scanning ||
        _status == S11ConnectionStatus.connecting) {
      return;
    }

    if (!forceScan && _savedDeviceId == null) {
      await loadSavedDevice();
    }

    final bool hasSavedMac =
        !forceScan && _savedDeviceId != null && _savedDeviceId!.isNotEmpty;

    _status = hasSavedMac
        ? S11ConnectionStatus.connecting
        : S11ConnectionStatus.scanning;
    _statusMessage = hasSavedMac
        ? 'Menghubungkan langsung ke MAC tersimpan ($_savedDeviceId)...'
        : 'Mencari iklan BLE perangkat "$targetDeviceName"...';
    _notifyStateChanged();

    try {
      await _adapter.scanAndConnect(
        targetName: targetDeviceName,
        timeout: timeout,
        savedDeviceId: _savedDeviceId,
        forceScan: forceScan,
        onDeviceConnected: (String deviceId, String deviceName) {
          _connectedDeviceId = deviceId;
          _connectedDeviceName = deviceName;
          _status = S11ConnectionStatus.connected;
          _statusMessage =
              'Terhubung ke $deviceName ($deviceId). Menjalankan auto-sync waktu...';
          unawaited(_persistSavedDeviceId(deviceId));
          _notifyStateChanged();
        },
        onNotificationReceived: _handleIncomingNotification,
        onDisconnected: () {
          _status = S11ConnectionStatus.disconnected;
          _connectedDeviceId = null;
          _statusMessage = 'Koneksi BLE ke $targetDeviceName terputus.';
          _notifyStateChanged();
        },
      );

      // Segera setelah terhubung: jalankan sinkronisasi waktu otomatis (cmd = 2, key = 1).
      // Battery Service 0x180F tidak dibaca otomatis saat konek agar tidak memicu auto-bonding.
      await syncTime();

      _statusMessage =
          'Terhubung ke $_connectedDeviceName • Waktu tersinkron otomatis.';
      _notifyStateChanged();
    } catch (error) {
      _status = S11ConnectionStatus.error;
      _statusMessage =
          'Tidak dapat terhubung ke "$targetDeviceName": $error';
      _notifyStateChanged();
    }
  }

  /// Memutuskan koneksi BLE dari smartwatch S11.
  Future<void> disconnect() async {
    await _adapter.disconnect();
    _status = S11ConnectionStatus.disconnected;
    _connectedDeviceId = null;
    _statusMessage = 'Terputus dari perangkat S11.';
    _notifyStateChanged();
  }

  /// Membaca persentase baterai dari Service `0x180F` (`0x2A19` -> `data[0] & 0xFF`).
  Future<int?> readBatteryLevel() async {
    try {
      final int? level = await _adapter.readBatteryPercentage();
      if (level != null) {
        _batteryLevel = level;
        _notifyStateChanged();
      }
      return level;
    } catch (error) {
      _statusMessage = 'Gagal membaca baterai (0x180F): $error';
      _notifyStateChanged();
      return null;
    }
  }

  /// Mengirim paket Sinkronisasi Waktu (`cmd = 2, key = 1`).
  Future<Uint8List> syncTime({DateTime? dateTime}) async {
    final DateTime timestamp = dateTime ?? _clock();
    final Uint8List packet = S11BleProtocol.buildTimeSyncPacket(timestamp);
    final bool sent = await _sendPacket(
      title: 'Sync Waktu (cmd=2, key=1)',
      packet: packet,
    );
    _lastTimeSync = timestamp;
    _statusMessage = _buildTxStatusMessage(
      sent: sent,
      successMessage: 'Sinkronisasi waktu berhasil dikirim ke S11.',
      previewMessage:
          'Paket Sync Waktu dibuat (${S11BleProtocol.toHexString(packet)}) — hubungkan S11 untuk kirim via GATT.',
    );
    _notifyStateChanged();
    return packet;
  }

  /// Mengirim Push Notifikasi Telegram (`cmd = 2, key = 18`, byte tipe aplikasi = `4`).
  Future<Uint8List> sendTelegramTestNotification({
    String title = 'Telegram - Andi',
    String content = 'Halo, ini tes pesan S11',
  }) async {
    final Uint8List packet = S11BleProtocol.buildTelegramNotificationPacket(
      title: title,
      content: content,
    );
    final bool sent = await _sendPacket(
      title: 'Push Telegram (cmd=2, key=18, byte=4)',
      packet: packet,
    );
    _statusMessage = _buildTxStatusMessage(
      sent: sent,
      successMessage: 'Notifikasi Telegram (byte 4) terkirim ke S11.',
      previewMessage:
          'Paket Telegram (byte 4) siap (${packet.length} byte) — hubungkan S11 untuk kirim via GATT.',
    );
    _notifyStateChanged();
    return packet;
  }

  /// Mengirim Push Panggilan Masuk WhatsApp (`cmd = 2, key = 17`, status = `1` atau `0`).
  Future<Uint8List> sendWhatsAppCallTest({
    String callerName = 'WhatsApp - Budi Santoso',
    int status = S11BleProtocol.callStatusIncoming,
  }) async {
    final Uint8List packet = S11BleProtocol.buildIncomingCallPacket(
      callerName: callerName,
      status: status,
    );
    final String actionLabel =
        status == S11BleProtocol.callStatusIncoming ? 'Masuk' : 'Berakhir';
    final bool sent = await _sendPacket(
      title: 'Panggilan WhatsApp $actionLabel (cmd=2, key=17, status=$status)',
      packet: packet,
    );
    _statusMessage = _buildTxStatusMessage(
      sent: sent,
      successMessage:
          'Push Panggilan WhatsApp ($actionLabel, key 17) terkirim ke S11.',
      previewMessage:
          'Paket Panggilan WhatsApp ($actionLabel, key 17) siap (${packet.length} byte) — hubungkan S11 untuk kirim via GATT.',
    );
    _notifyStateChanged();
    return packet;
  }

  String _buildTxStatusMessage({
    required bool sent,
    required String successMessage,
    required String previewMessage,
  }) {
    if (sent) return successMessage;
    if (_lastWriteError != null) {
      return 'Gagal mengirim paket ke S11: $_lastWriteError';
    }
    return previewMessage;
  }

  Future<bool> _sendPacket({
    required String title,
    required Uint8List packet,
  }) async {
    bool sentOverBle = false;
    _lastWriteError = null;

    if (isConnected) {
      try {
        sentOverBle = await _adapter.writeCommand(packet);
      } catch (error) {
        _lastWriteError = error.toString();
      }
    }

    _appendLog(
      direction: 'TX',
      title: _lastWriteError == null ? title : '$title [GAGAL]',
      packet: packet,
      transmittedOverBle: sentOverBle,
    );
    return sentOverBle;
  }

  void _handleIncomingNotification(List<int> rawData) {
    if (rawData.isEmpty) return;

    final Uint8List bytes = Uint8List.fromList(rawData);
    final String hex = S11BleProtocol.toHexString(bytes);
    _appendLog(
      direction: 'RX',
      title: 'Notify 6e400003 (${bytes.length} byte)',
      packet: bytes,
      transmittedOverBle: true,
    );
    _statusMessage = 'RX 6e400003: $hex';

    final S11SensorSnapshot? parsed = S11BleProtocol.parseIncomingSensorPacket(
      bytes,
      current: _sensorSnapshot,
    );
    if (parsed != null) {
      _sensorSnapshot = parsed;
    }
    _notifyStateChanged();
  }

  void _appendLog({
    required String direction,
    required String title,
    required Uint8List packet,
    required bool transmittedOverBle,
  }) {
    _packetLogs.insert(
      0,
      S11PacketLog(
        timestamp: _clock(),
        direction: direction,
        title: title,
        packet: packet,
        hexString: S11BleProtocol.toHexString(packet),
        transmittedOverBle: transmittedOverBle,
      ),
    );
    if (_packetLogs.length > 25) {
      _packetLogs.removeLast();
    }
  }

  void clearLogs() {
    _packetLogs.clear();
    _notifyStateChanged();
  }

  void _notifyStateChanged() {
    if (!_stateChanges.isClosed) {
      _stateChanges.add(null);
    }
  }

  void dispose() {
    _stateChanges.close();
  }
}
