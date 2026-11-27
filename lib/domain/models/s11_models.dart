import 'dart:typed_data';

enum S11ConnectionStatus {
  disconnected('Terputus'),
  scanning('Memindai "S11"...'),
  connecting('Menghubungkan...'),
  connected('Terhubung'),
  error('Gagal Terhubung');

  const S11ConnectionStatus(this.label);
  final String label;
}

class S11PacketLog {
  const S11PacketLog({
    required this.timestamp,
    required this.direction,
    required this.title,
    required this.packet,
    required this.hexString,
    required this.transmittedOverBle,
  });

  final DateTime timestamp;
  final String direction; // 'TX' or 'RX'
  final String title;
  final Uint8List packet;
  final String hexString;
  final bool transmittedOverBle;
}

class S11SensorSnapshot {
  const S11SensorSnapshot({
    this.heartRateBpm,
    this.steps,
    this.distanceMeters,
    this.calories,
  });

  final int? heartRateBpm;
  final int? steps;
  final int? distanceMeters;
  final int? calories;

  S11SensorSnapshot copyWith({
    int? heartRateBpm,
    int? steps,
    int? distanceMeters,
    int? calories,
  }) {
    return S11SensorSnapshot(
      heartRateBpm: heartRateBpm ?? this.heartRateBpm,
      steps: steps ?? this.steps,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      calories: calories ?? this.calories,
    );
  }
}
