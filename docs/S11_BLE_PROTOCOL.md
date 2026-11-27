# Spesifikasi Protokol BLE & Arsitektur Pendamping Smartwatch S11 (HryFine)

Dokumen ini merupakan hasil *reverse engineering* dari `HryFine_3.8.26.apk` (`com.lianhezhuli.hyfit`) dan verifikasi GATT langsung menggunakan nRF Connect pada perangkat keras smartwatch **S11**.

---

## 1. Spesifikasi Bluetooth Low Energy (BLE)

* **Tipe Koneksi:** Bondless BLE (tanpa *system pairing* Bluetooth Android; terhubung langsung ke GATT server).
* **Target Perangkat:** Nama iklan BLE `S11` (contoh MAC: `41:42:1A:84:D7:98`).
* **Primary Communication Service (Nordic UART Service):**
  * **Service UUID:** `6e400001-b5a3-f393-e0a9-e50e24dcca9f`
  * **Write Characteristic (HP $\rightarrow$ Jam):** `6e400002-b5a3-f393-e0a9-e50e24dcca9f` (*Properties: `WRITE`, `WRITE NO RESPONSE`*)
  * **Notify Characteristic (Jam $\rightarrow$ HP):** `6e400003-b5a3-f393-e0a9-e50e24dcca9f` (*Properties: `NOTIFY`, `READ`*, Descriptor: `0x2902`)
* **Battery Service (Standar BLE):**
  * **Service UUID:** `0000180f-0000-1000-8000-00805f9b34fb` (`0x180F`)
  * **Battery Level Characteristic:** `00002a19-0000-1000-8000-00805f9b34fb` (`0x2A19`) — Byte pertama (`data[0] & 0xFF`) bernilai `0` sampai `100` (persentase baterai).

---

## 2. Format Pembungkus Paket Perintah (`getSendByte`)

Setiap perintah yang dikirim dari HP ke `6e400002-b5a3-f393-e0a9-e50e24dcca9f` wajib dibungkus dengan **8-byte header** berikut (tanpa *checksum* di akhir paket):

| Indeks Byte | Nilai / Rumus | Keterangan |
| :--- | :--- | :--- |
| `0` | `0xAB` | `ACK_HEADER` (Header tetap protokol HryFine) |
| `1` | `((payload.length + 5) >> 8) & 0xFF` | Panjang frame setelah header (High Byte) |
| `2` | `(payload.length + 5) & 0xFF` | Panjang frame setelah header (Low Byte) |
| `3` | `cmd` | Command Group (contoh: `2` untuk pengaturan & notifikasi) |
| `4` | `0x01` | `PROTOCOL_VERSION` |
| `5` | `key` | Command ID spesifik (contoh: `1` = Waktu, `17` = Panggilan, `18` = Pesan) |
| `6` | `(payload.length >> 8) & 0xFF` | Panjang `payload` murni (High Byte) |
| `7` | `payload.length & 0xFF` | Panjang `payload` murni (Low Byte) |
| `8 .. N` | `payload` | Isi data perintah dalam byte |

*(Catatan: Untuk perintah tanpa payload (`payload.length == 0`), array 8 byte yang dikirim adalah `[0xAB, 0x00, 0x05, cmd, 0x01, key, 0x00, 0x00]`).*

---

## 3. Daftar Perintah Keluar (HP $\rightarrow$ Smartwatch)

### A. Sinkronisasi Waktu (`cmd = 2`, `key = 1`)
* **Total Panjang Payload:** `4 byte` (dikirim otomatis setiap kali koneksi BLE berhasil tersambung).
* **Rumus Bit-Packing (Offset Tahun = 2000, valid 2000–2063):**
```dart
  final int y = now.year - 2000;
  final int m = now.month;
  final int d = now.day;
  final int h = now.hour;
  final int min = now.minute;
  final int s = now.second;

  final Uint8List payload = Uint8List.fromList([
    ((y << 2) | ((m & 0xFF) >> 2)) & 0xFF,
    (((m & 3) << 6) | (d << 1) | (h >> 4)) & 0xFF,
    (((h & 15) << 4) | (min >> 2)) & 0xFF,
    (((min & 3) << 6) | s) & 0xFF,
  ]);

```

### B. Push Notifikasi Pesan (`cmd = 2`, `key = 18` / `0x12`)

* **Struktur Payload:**
* `payload[0]`: **Kode Tipe Aplikasi/Ikon**
* `1` = SMS
* `4` = Facebook *(Dipetakan ulang di aplikasi ini untuk **Telegram** / `org.telegram.messenger`)*
* `8` = WhatsApp (`com.whatsapp`)


* `payload[1]`: `0x00` (Reserved)
* `payload[2]`: `0x00` (Reserved)
* `payload[3..]`: String UTF-8 berformat `"$title:$content"`, dipotong maksimal **196 byte** (potong aman pada batas karakter UTF-8 agar tidak merusak karakter multibyte).



### C. Push Panggilan Masuk (`cmd = 2`, `key = 17` / `0x11`)

Digunakan untuk meneruskan panggilan masuk **WhatsApp** (`com.whatsapp` dengan kategori/aksi panggilan) maupun panggilan telepon reguler ke smartwatch agar bergetar dan menampilkan nama penelepon.

* **Struktur Payload:**
* `payload[0]`: Status panggilan (`1` = Panggilan masuk / berdering, `0` atau `2` = Panggilan diangkat / berakhir)
* `payload[1]`: `0x00` (Reserved)
* `payload[2..]`: Nama kontak atau nomor penelepon dalam encoding **UTF-8**.


---

## 4. Parser Data Kesehatan Masuk (Smartwatch $\rightarrow$ HP)

Data diterima melalui listener pada Characteristic `6e400003-b5a3-f393-e0a9-e50e24dcca9f`.

1. **Validasi Header & Ekstraksi Payload Sensor (`bArr2`):**
* Periksa `data[0] == 0xAB` dan panjang minimal `10 byte`.
* Panjang isi sensor: `int contentLen = ((data[1] & 0xFF) << 8 | (data[2] & 0xFF)) - 5` *(little-endian/big-endian disesuaikan dengan urutan `HexUtil.byte2IntLR(data[1], data[2])`: `(data[1] & 0xFF) + ((data[2] & 0xFF) << 8)` jika little-endian, atau big-endian sesuai header `getSendByte`; verifikasi log hex mentah saat testing)*.
* Jenis data ditentukan oleh `int dataType = data[6] & 0xFF`.
* Potong array sensor `sensorData` mulai dari indeks ke-`9` (`data.sublist(9)`).


2. **Jenis Data Berdasarkan `data[6] & 0xFF`:**
* **`case 4` — Riwayat Detak Jantung (Heart Rate):**
* `int count = sensorData[3] & 0xFF;` (jumlah rekaman).
* Setiap rekaman berukuran **8 byte**, dimulai dari indeks `4` (`offset = 4 + (i * 8)`).
* Nilai BPM berada pada byte ke-7 dari masing-masing blok (`int bpm = sensorData[offset + 7] & 0xFF`).
* Filter validitas firmware: `40 <= bpm <= 160`.


* **`case 12` — Total Langkah, Jarak & Kalori Harian:**
* Terdiri dari 3 nilai integer 32-bit berturut-turut pada `sensorData[0..11]`:
* `steps` (indeks `0..3`) — valid jika `<= 240000`
* `distance` dalam meter (indeks `4..7`) — valid jika `<= 192000`
* `calorie` (indeks `8..11`) — valid jika `<= 4464000`


---

## 5. Arsitektur Android Native Bridge (`NotificationListenerService`)

Karena Android membatasi pembacaan notifikasi aplikasi lain dari proses latar belakang, sisi Android (`android/app/src/main/kotlin/...`) wajib mengimplementasikan:

1. **`S11NotificationListenerService extends NotificationListenerService`:**
* Mendaftarkan izin `android.permission.BIND_NOTIFICATION_LISTENER_SERVICE` di `AndroidManifest.xml`.
* Mengimplementasikan `onListenerDisconnected()` dengan memanggil `requestRebind(ComponentName)` serta Foreground Service ringan agar tidak dimatikan sistem saat aplikasi ditutup dari *recent apps*.
* **Filter Paket Target:**
* **`org.telegram.messenger`:** Ambil `android.title` dan `android.text`, kirim ke Flutter/BLE dengan tipe byte **`4`**.
* **`com.whatsapp`:**
* Deteksi apakah notifikasi merupakan panggilan masuk (cek `Notification.CATEGORY_CALL`, `extras.getBoolean("android.isGroupConversation") == false` dengan tag/channel panggilan, atau keberadaan `Notification.Action` terima/tolak panggilan). Jika panggilan masuk $\rightarrow$ panggil protokol **Panggilan Masuk (`cmd = 2, key = 17`)** dengan nama penelepon. Jika pesan chat biasa $\rightarrow$ kirim sebagai pesan dengan tipe byte **`8`**.


* **Panggilan Telepon Biasa (Opsional / Nonaktif by Default):** Dapat dimatikan melalui pengaturan UI Flutter sesuai preferensi pengguna.


2. **Komunikasi ke Flutter:** Menggunakan `MethodChannel` / `EventChannel` (atau langsung mengantrekan paket byte ke service BLE Android native agar notifikasi tetap terkirim ke jam meskipun UI Flutter sedang tertutup).
