# Panduan Demo SAKSI

Skenario presentasi sekitar 10 menit. Semua langkah dijalankan di terminal **Ubuntu 24.04** dan browser Windows.

## Persiapan (sebelum presentasi)

```bash
cd ~/saksi-contracts
besu-network/start.sh          # tunggu ±20 detik
besu-network/status.sh         # pastikan 4 node, nomor blok bertambah
scripts/deploy.sh besu         # deploy kontrak baru dan siapkan peran
scripts/serve-frontend.sh      # biarkan terminal ini terbuka
```

Buka **http://localhost:5180** di browser. Pastikan di kanan atas muncul `Besu QBFT · chain 1337` berwarna hijau dan nomor blok terus naik.

Klik **Unduh berkas contoh**, lalu **Unduh versi yang diubah**. Kedua berkas tersimpan di folder Downloads. Isinya sama, kecuali nominal transfer (Rp 25.000.000 diubah menjadi Rp 95.000.000).

> Jika ingin latihan tanpa Besu, ganti dua perintah pertama dengan `anvil` (di terminal terpisah) dan `scripts/deploy.sh anvil`.

## Skenario

### 1. Kontrol akses (± 1 menit)
1. Pilih peran **Kustodian A**.
2. Isi nomor perkara `LP/123/XI/2026`, deskripsi, pilih berkas contoh, klik **Daftarkan bukti**.
3. Log menampilkan: *Ditolak: akun ini tidak memiliki peran Penyidik yang dibutuhkan.*

**Poin:** hanya penyidik yang boleh mendaftarkan bukti, dan aturan ini ditegakkan oleh smart contract, bukan oleh aplikasi.

### 2. Pendaftaran bukti (± 1 menit)
1. Pilih peran **Penyidik**, daftarkan berkas contoh yang sama.
2. Tunjukkan hash SHA-256 yang muncul sebelum dikirim. Berkas tidak dikirim ke mana pun, hanya hash-nya.
3. Bukti #1 muncul di tabel dengan status **Disimpan** dan pemegang **Penyidik**.

### 3. Serah-terima normal (± 2 menit)
1. Sebagai **Penyidik**, klik **Serahkan** → penerima **Kustodian A**, catatan `Dikirim ke gudang bukti`.
2. Status menjadi **Dalam serah-terima**. Pemegang masih Penyidik, karena penerima belum mengonfirmasi.
3. Pilih peran **Kustodian A**, klik **Terima**, unggah **berkas contoh asli**.
4. Pemegang berubah menjadi **Kustodian A**.

**Poin:** serah-terima butuh persetujuan dua pihak, seperti berita acara yang ditandatangani kedua belah pihak.

### 4. Deteksi perubahan berkas (± 2 menit) — bagian utama
1. Sebagai **Kustodian A**, serahkan bukti ke **Kustodian B** (`Dikirim ke lab forensik`).
2. Pilih **Kustodian B**, klik **Terima**, unggah **berkas versi yang diubah**.
3. Log menampilkan: *Hash berkas TIDAK COCOK … serah-terima ditolak oleh smart contract.*
4. Bukti tetap dipegang Kustodian A.

**Poin:** perubahan satu angka saja menghasilkan hash yang sama sekali berbeda, sehingga manipulasi bukti langsung ketahuan saat serah-terima.

### 5. Penolakan dan penyelesaian (± 1 menit)
1. Masih sebagai **Kustodian B**, klik **Tolak** dengan alasan `Berkas tidak sesuai`.
2. Sebagai **Kustodian A**, serahkan lagi ke Kustodian B. Sebagai **Kustodian B**, terima dengan **berkas asli**.
3. Klik **Tutup** dengan catatan `Analisis selesai`. Status menjadi **Ditutup** dan tidak ada lagi tombol aksi.

### 6. Jejak audit (± 1 menit)
1. Klik **Riwayat** pada bukti #1. Lini masa menampilkan setiap aksi: siapa, kapan, dan catatannya, termasuk penolakan.
2. Pada **Periksa keutuhan berkas**, unggah berkas asli (**COCOK**), lalu versi yang diubah (**TIDAK COCOK**).

### 7. Jeda darurat (± 1 menit)
1. Sebagai **Penyidik**, klik **Jeda sistem**: ditolak, karena bukan admin.
2. Pilih **Admin**, klik **Jeda sistem**. Muncul label **SISTEM DIJEDA**.
3. Coba daftarkan bukti sebagai Penyidik: ditolak karena sistem dijeda.
4. Sebagai **Admin**, klik **Lanjutkan sistem**.

### 8. Ketahanan jaringan (opsional, ± 2 menit)
Di terminal lain:
```bash
besu-network/stop.sh 4      # 3 dari 4 validator: blok tetap bertambah, frontend tetap bisa dipakai
besu-network/start.sh 4
```
Jangan mematikan dua node saat demo: jaringan akan berhenti dan butuh ±1 menit untuk pulih setelah node dinyalakan kembali.

## Setelah demo

```bash
# Ctrl+C di terminal serve-frontend
besu-network/stop.sh
besu-network/reset.sh       # opsional: mulai dari blok 0 lagi (deploy ulang setelahnya)
```

## Jika ada masalah

| Gejala | Solusi |
|---|---|
| Kotak merah "Tidak bisa terhubung" | Jaringan belum berjalan. Jalankan `besu-network/start.sh`, tunggu, lalu muat ulang halaman. |
| "Kontrak tidak ditemukan" | Jaringan di-reset. Jalankan `scripts/deploy.sh besu` lagi, lalu muat ulang halaman. |
| Halaman tidak terbuka | Port mungkin dipakai program Windows. Jalankan `scripts/serve-frontend.sh 8090` dan buka `http://localhost:8090`. |
| "Browser tidak mengizinkan perhitungan hash" | Buka lewat `http://localhost:…`, bukan alamat IP. |
| "Berkas ini sudah terdaftar" | Setiap berkas hanya boleh didaftarkan sekali. Klik **Unduh berkas contoh** lagi untuk berkas baru. |
