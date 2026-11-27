import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../data/protocol/s11_ble_protocol.dart';
import '../../../../data/services/s11_ble_service.dart';
import '../../../../domain/models/s11_models.dart';

class S11DashboardViewModel extends ChangeNotifier {
  S11DashboardViewModel({S11BleService? bleService})
      : _bleService = bleService ?? S11BleService() {
    _subscription = _bleService.onStateChanged.listen((_) {
      notifyListeners();
    });
    unawaited(_bleService.loadSavedDevice());
  }

  final S11BleService _bleService;
  StreamSubscription<void>? _subscription;

  S11ConnectionStatus get status => _bleService.status;
  bool get isConnected => _bleService.isConnected;
  bool get isBusy =>
      status == S11ConnectionStatus.scanning ||
      status == S11ConnectionStatus.connecting;

  String get deviceName => _bleService.connectedDeviceName;
  String? get deviceId => _bleService.connectedDeviceId;
  String? get savedDeviceId => _bleService.savedDeviceId;
  int? get batteryLevel => _bleService.batteryLevel;
  DateTime? get lastTimeSync => _bleService.lastTimeSync;
  String? get statusMessage => _bleService.statusMessage;
  S11SensorSnapshot get sensorSnapshot => _bleService.sensorSnapshot;
  List<S11PacketLog> get packetLogs => _bleService.packetLogs;

  Future<void> scanAndConnect() => _bleService.scanAndConnect();

  Future<void> rescanDevices() => _bleService.scanAndConnect(forceScan: true);

  Future<void> disconnect() => _bleService.disconnect();

  Future<void> refreshBattery() => _bleService.readBatteryLevel();

  Future<void> syncTimeManual() => _bleService.syncTime();

  Future<void> testTelegramNotification() =>
      _bleService.sendTelegramTestNotification();

  Future<void> testWhatsAppIncomingCall() =>
      _bleService.sendWhatsAppCallTest(
        status: S11BleProtocol.callStatusIncoming,
      );

  Future<void> testWhatsAppEndCall() => _bleService.sendWhatsAppCallTest(
        status: S11BleProtocol.callStatusEnded,
      );

  void clearPacketLogs() => _bleService.clearLogs();

  @override
  void dispose() {
    _subscription?.cancel();
    _bleService.dispose();
    super.dispose();
  }
}
