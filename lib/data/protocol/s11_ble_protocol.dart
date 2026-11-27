import 'dart:convert';
import 'dart:typed_data';

import '../../domain/models/s11_models.dart';

/// Implementasi protokol biner HryFine untuk Smartwatch S11
/// sesuai spesifikasi `docs/S11_BLE_PROTOCOL.md`.
class S11BleProtocol {
  const S11BleProtocol._();

  /// Byte header tetap protokol HryFine (`0xAB`).
  static const int ackHeader = 0xAB;

  /// Versi protokol tetap (`0x01`).
  static const int protocolVersion = 0x01;

  /// Command group untuk pengaturan waktu, panggilan, dan push notifikasi (`cmd = 2`).
  static const int cmdSettingsAndNotification = 0x02;

  /// Command key sinkronisasi waktu (`key = 1`).
  static const int keyTimeSync = 0x01;

  /// Command key push panggilan masuk (`key = 17` / `0x11`).
  static const int keyIncomingCall = 17;

  /// Command key push notifikasi pesan (`key = 18` / `0x12`).
  static const int keyMessagePush = 18;

  /// Kode tipe aplikasi pada `payload[0]` untuk Push Notifikasi Pesan (`key = 18`).
  static const int appTypeSms = 1;
  static const int appTypeTelegram = 4; // Slot ikon Facebook yang dipetakan ke Telegram
  static const int appTypeWhatsApp = 8;

  /// Status panggilan pada `payload[0]` untuk Push Panggilan Masuk (`key = 17`).
  static const int callStatusIncoming = 1;
  static const int callStatusEnded = 0;

  /// Batas maksimal panjang karakter teks notifikasi/panggilan uji coba agar aman dari buffer firmware.
  static const int maxNotificationTextChars = 40;

  /// Batas maksimal panjang UTF-8 string `"$title:$content"` pada paket pesan.
  static const int maxMessageUtf8Bytes = 196;

  /// Batas aman payload GATT per penulisan (default BLE ATT MTU 23 - 3 byte header = 20 byte).
  static const int maxBleMtuChunkBytes = 20;

  /// Menghapus seluruh karakter non-ASCII / emoji (di luar rentang 0x20..0x7E).
  static String sanitizeAscii(String text) {
    return text.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
  }

  /// Membersihkan string ke ASCII lalu memotong maksimal [maxChars] karakter.
  static String sanitizeAndCapAscii(
    String text, {
    int maxChars = maxNotificationTextChars,
  }) {
    final String clean = sanitizeAscii(text);
    if (maxChars <= 0 || clean.isEmpty) return '';
    return clean.length <= maxChars ? clean : clean.substring(0, maxChars);
  }

  /// Membungkus `cmd`, `key`, dan `payload` dengan 8-byte header `0xAB` (`getSendByte`).
  ///
  /// Struktur Header (8 byte):
  /// - `[0]` : `0xAB` (`ACK_HEADER`)
  /// - `[1]` : `((payload.length + 5) >> 8) & 0xFF`
  /// - `[2]` : `(payload.length + 5) & 0xFF`
  /// - `[3]` : `cmd`
  /// - `[4]` : `0x01` (`PROTOCOL_VERSION`)
  /// - `[5]` : `key`
  /// - `[6]` : `(payload.length >> 8) & 0xFF`
  /// - `[7]` : `payload.length & 0xFF`
  /// - `[8..N]` : `payload`
  static Uint8List getSendByte({
    required int cmd,
    required int key,
    List<int> payload = const <int>[],
  }) {
    final int payloadLen = payload.length;
    final int frameLenAfterHeader = payloadLen + 5;
    final Uint8List packet = Uint8List(8 + payloadLen);

    packet[0] = ackHeader;
    packet[1] = (frameLenAfterHeader >> 8) & 0xFF;
    packet[2] = frameLenAfterHeader & 0xFF;
    packet[3] = cmd & 0xFF;
    packet[4] = protocolVersion;
    packet[5] = key & 0xFF;
    packet[6] = (payloadLen >> 8) & 0xFF;
    packet[7] = payloadLen & 0xFF;

    if (payloadLen > 0) {
      packet.setRange(8, 8 + payloadLen, payload);
    }
    return packet;
  }

  /// Menghasilkan 4-byte payload bit-packed untuk Sinkronisasi Waktu
  /// (Offset tahun = 2000, valid untuk 2000..2063).
  static Uint8List buildTimeSyncPayload(DateTime now) {
    final int y = (now.year - 2000).clamp(0, 63);
    final int m = now.month;
    final int d = now.day;
    final int h = now.hour;
    final int min = now.minute;
    final int s = now.second;

    return Uint8List.fromList(<int>[
      ((y << 2) | ((m & 0xFF) >> 2)) & 0xFF,
      (((m & 3) << 6) | (d << 1) | (h >> 4)) & 0xFF,
      (((h & 15) << 4) | (min >> 2)) & 0xFF,
      (((min & 3) << 6) | s) & 0xFF,
    ]);
  }

  /// Membentuk paket lengkap 12-byte Sinkronisasi Waktu (`cmd = 2`, `key = 1`).
  static Uint8List buildTimeSyncPacket([DateTime? dateTime]) {
    final Uint8List payload = buildTimeSyncPayload(dateTime ?? DateTime.now());
    return getSendByte(
      cmd: cmdSettingsAndNotification,
      key: keyTimeSync,
      payload: payload,
    );
  }

  /// Memotong string UTF-8 secara aman hingga maksimal [maxBytes] byte
  /// tanpa membelah karakter multibyte (emoji / karakter non-ASCII).
  static Uint8List truncateUtf8Safely(String text, int maxBytes) {
    if (maxBytes <= 0 || text.isEmpty) {
      return Uint8List(0);
    }

    final List<int> encoded = utf8.encode(text);
    if (encoded.length <= maxBytes) {
      return Uint8List.fromList(encoded);
    }

    int cutIndex = maxBytes;
    // Byte kelanjutan UTF-8 memiliki pola bit 10xxxxxx ((byte & 0xC0) == 0x80).
    // Mundur sampai menemukan awal karakter berikutnya agar tidak merusak karakter multibyte.
    while (cutIndex > 0 && (encoded[cutIndex] & 0xC0) == 0x80) {
      cutIndex--;
    }

    return Uint8List.fromList(encoded.sublist(0, cutIndex));
  }

  /// Membentuk paket Push Notifikasi Pesan (`cmd = 2`, `key = 18` / `0x12`).
  ///
  /// Struktur Payload:
  /// - `payload[0]`: Kode Tipe Aplikasi (`1` = SMS, `4` = Telegram/Facebook, `8` = WhatsApp)
  /// - `payload[1]`: `0x00` (Reserved)
  /// - `payload[2]`: `0x00` (Reserved)
  /// - `payload[3..]`: ASCII `"$title: $content"` (maksimal [maxChars] karakter, default 40)
  static Uint8List buildMessagePushPacket({
    required int appType,
    required String title,
    required String content,
    int maxChars = maxNotificationTextChars,
  }) {
    final String cleanTitle = sanitizeAscii(title);
    final String cleanContent = sanitizeAscii(content);
    final String combined = switch ((cleanTitle.isEmpty, cleanContent.isEmpty)) {
      (true, true) => '',
      (false, true) => cleanTitle,
      (true, false) => cleanContent,
      (false, false) => '$cleanTitle: $cleanContent',
    };
    final String capped = sanitizeAndCapAscii(combined, maxChars: maxChars);
    final Uint8List textBytes =
        truncateUtf8Safely(capped, maxMessageUtf8Bytes);

    final Uint8List payload = Uint8List(3 + textBytes.length);
    payload[0] = appType & 0xFF;
    payload[1] = 0x00;
    payload[2] = 0x00;
    payload.setRange(3, 3 + textBytes.length, textBytes);

    return getSendByte(
      cmd: cmdSettingsAndNotification,
      key: keyMessagePush,
      payload: payload,
    );
  }

  /// Helper khusus untuk Push Notifikasi Telegram (`appType = 4`, `cmd = 2`, `key = 18`).
  static Uint8List buildTelegramNotificationPacket({
    required String title,
    required String content,
    int maxChars = maxNotificationTextChars,
  }) {
    return buildMessagePushPacket(
      appType: appTypeTelegram,
      title: title,
      content: content,
      maxChars: maxChars,
    );
  }

  /// Helper khusus untuk Push Notifikasi Pesan WhatsApp (`appType = 8`, `cmd = 2`, `key = 18`).
  static Uint8List buildWhatsAppMessagePacket({
    required String title,
    required String content,
    int maxChars = maxNotificationTextChars,
  }) {
    return buildMessagePushPacket(
      appType: appTypeWhatsApp,
      title: title,
      content: content,
      maxChars: maxChars,
    );
  }

  /// Membentuk paket Push Panggilan Masuk (`cmd = 2`, `key = 17` / `0x11`).
  ///
  /// Struktur Payload:
  /// - `payload[0]`: Status panggilan (`1` = Panggilan masuk / berdering, `0` atau `2` = Berakhir)
  /// - `payload[1]`: `0x00` (Reserved)
  /// - `payload[2..]`: Nama kontak atau nomor penelepon dalam ASCII bersih (maksimal 40 karakter)
  static Uint8List buildIncomingCallPacket({
    required String callerName,
    int status = callStatusIncoming,
    int maxChars = maxNotificationTextChars,
  }) {
    final String cappedCaller =
        sanitizeAndCapAscii(callerName, maxChars: maxChars);
    final Uint8List callerBytes =
        truncateUtf8Safely(cappedCaller, maxMessageUtf8Bytes);

    final Uint8List payload = Uint8List(2 + callerBytes.length);
    payload[0] = status & 0xFF;
    payload[1] = 0x00;
    payload.setRange(2, 2 + callerBytes.length, callerBytes);

    return getSendByte(
      cmd: cmdSettingsAndNotification,
      key: keyIncomingCall,
      payload: payload,
    );
  }

  /// Memecah [packet] menjadi potongan maksimal [chunkSize] byte secara berurutan
  /// agar aman dikirim melalui karakteristik BLE dengan batas MTU 20 byte.
  static List<Uint8List> splitIntoChunks(
    Uint8List packet, {
    int chunkSize = maxBleMtuChunkBytes,
  }) {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize', 'Harus lebih besar dari 0');
    }
    if (packet.isEmpty) {
      return const <Uint8List>[];
    }
    if (packet.length <= chunkSize) {
      return <Uint8List>[packet];
    }

    final List<Uint8List> chunks = <Uint8List>[];
    for (int offset = 0; offset < packet.length; offset += chunkSize) {
      final int end =
          (offset + chunkSize < packet.length) ? offset + chunkSize : packet.length;
      chunks.add(Uint8List.sublistView(packet, offset, end));
    }
    return chunks;
  }

  /// Mem-parsing paket sensor kesehatan masuk dari `6e400003-b5a3-f393-e0a9-e50e24dcca9f`.
  static S11SensorSnapshot? parseIncomingSensorPacket(
    List<int> data, {
    S11SensorSnapshot? current,
  }) {
    if (data.length < 10 || (data[0] & 0xFF) != ackHeader) {
      return null;
    }

    final int dataType = data[6] & 0xFF;
    final List<int> sensorData = data.sublist(9);
    final S11SensorSnapshot base = current ?? const S11SensorSnapshot();

    switch (dataType) {
      case 4: // Riwayat Detak Jantung (Heart Rate)
        if (sensorData.length < 4) return null;
        final int count = sensorData[3] & 0xFF;
        int? latestValidBpm;
        for (int i = 0; i < count; i++) {
          final int offset = 4 + (i * 8);
          if (offset + 7 >= sensorData.length) break;
          final int bpm = sensorData[offset + 7] & 0xFF;
          if (bpm >= 40 && bpm <= 160) {
            latestValidBpm = bpm;
          }
        }
        if (latestValidBpm == null) return null;
        return base.copyWith(heartRateBpm: latestValidBpm);

      case 12: // Total Langkah, Jarak & Kalori Harian
        if (sensorData.length < 12) return null;
        final int steps = _readUint32BigEndian(sensorData, 0);
        final int distance = _readUint32BigEndian(sensorData, 4);
        final int calorie = _readUint32BigEndian(sensorData, 8);
        return base.copyWith(
          steps: steps <= 240000 ? steps : base.steps,
          distanceMeters: distance <= 192000 ? distance : base.distanceMeters,
          calories: calorie <= 4464000 ? calorie : base.calories,
        );

      default:
        return null;
    }
  }

  static int _readUint32BigEndian(List<int> bytes, int offset) {
    return ((bytes[offset] & 0xFF) << 24) |
        ((bytes[offset + 1] & 0xFF) << 16) |
        ((bytes[offset + 2] & 0xFF) << 8) |
        (bytes[offset + 3] & 0xFF);
  }

  /// Mengubah array byte menjadi representasi string Hex (`AB 00 09 ...`).
  static String toHexString(List<int> bytes) {
    return bytes
        .map((int b) => (b & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }
}
