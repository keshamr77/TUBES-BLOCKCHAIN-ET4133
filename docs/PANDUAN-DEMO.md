# Panduan Demo SAKSI

Skenario presentasi sekitar 12 menit. Semua langkah dijalankan di terminal **Ubuntu 24.04** dan browser Windows. Versi ini memakai kontrak Milestone 3: ketidakcocokan hash **dicatat** di blockchain (tidak lagi ditolak diam-diam), dan nomor perkara hanya disimpan sebagai hash.

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

Siapkan juga **jendela browser kedua** (profil lain atau jendela samaran) yang membuka alamat yang sama, untuk langkah 2.

> Jika ingin latihan tanpa Besu, ganti dua perintah pertama dengan `anvil` (di terminal terpisah) dan `scripts/deploy.sh anvil`.

## Skenario

### 1. Kontrol akses (± 1 menit)
1. Pilih peran **Tamu (tanpa peran)**.
2. Isi nomor perkara `LP/123/XI/2026`, deskripsi, pilih berkas contoh, klik **Daftarkan bukti**.
3. Log menampilkan: *Ditolak: akun ini tidak memiliki peran Penyidik yang dibutuhkan.* Tidak ada transaksi yang masuk blok.

**Poin:** hanya penyidik yang boleh mendaftarkan bukti, dan aturan ini ditegakkan oleh smart contract, bukan oleh aplikasi.

### 2. Pendaftaran bukti dan privasi data perkara (± 2 menit)
1. Pilih peran **Penyidik**. Saat mengetik nomor perkara, tunjukkan baris **Ref. perkara (keccak256)** yang berubah setiap ketikan.
2. Pilih berkas contoh. Hash SHA-256 muncul sebelum dikirim; berkasnya tidak dikirim ke mana pun.
3. Klik **Daftarkan bukti**. Log menyebut bahwa di blockchain hanya tercatat ref. perkara.
4. Di tabel, nomor perkara dan deskripsi tampil dengan label *tersimpan lokal di browser ini*.
5. Pindah ke **jendela browser kedua** dan muat ulang. Kolom yang sama hanya menampilkan **hash on-chain**.

**Poin:** nomor perkara dan deskripsi tidak pernah ditulis ke blockchain sebagai teks. Siapa pun yang membaca rantai hanya melihat hash.

### 3. Cocokkan nomor perkara (± 1 menit)
1. Klik **Riwayat** pada bukti #1.
2. Di **Cocokkan nomor perkara**, ketik `lp/123/xi/2026` (huruf kecil). Hasil: **COCOK**, karena nomor dinormalisasi (spasi di ujung dibuang, huruf besar).
3. Ketik `LP/124/XI/2026`. Hasil: **TIDAK COCOK**, beserta hash yang berbeda.

**Poin:** penyidik yang tahu nomor perkaranya bisa membuktikan keterkaitan bukti dengan perkara tanpa nomor itu disimpan terbuka.

### 4. Serah-terima normal (± 2 menit)
1. Sebagai **Penyidik**, klik **Serahkan** → penerima **Kustodian A**, catatan `Dikirim ke gudang bukti`.
2. Status menjadi **Dalam serah-terima**. Pemegang masih Penyidik, karena penerima belum mengonfirmasi.
3. Pilih peran **Kustodian A**, klik **Terima**, unggah **berkas contoh asli**.
4. Pemegang berubah menjadi **Kustodian A**.

**Poin:** serah-terima butuh persetujuan dua pihak, seperti berita acara yang ditandatangani kedua belah pihak.

### 5. Berkas diubah: tercatat, bukan ditolak diam-diam (± 2 menit), bagian utama
1. Sebagai **Kustodian A**, serahkan bukti ke **Kustodian B** (`Dikirim ke lab forensik`).
2. Pilih **Kustodian B**, klik **Terima**, unggah **berkas versi yang diubah**.
3. Muncul dialog **Hash berkas tidak cocok**. Jelaskan bahwa transaksi tetap akan dikirim agar upaya ini tercatat. Klik **Kirim & catat**.
4. Log menampilkan: *⚠ Hash tidak cocok, tercatat di blok N*, beserta hash terdaftar dan hash yang diserahkan.
5. Bukti tetap dipegang **Kustodian A**, status kembali **Disimpan**, dan muncul badge **⚠ 1× hash tidak cocok**.
6. Klik **Riwayat**: ada entri merah *Hash tidak cocok, tercatat* atas nama Kustodian B, berisi hash berkas yang ia serahkan.

**Poin:** di versi MVP, smart contract me-revert transaksi ini sehingga tidak ada jejak sama sekali. Sekarang upaya serah-terima dengan berkas yang diubah menjadi bagian permanen dari jejak audit, dan bukti diberi tanda yang tidak bisa dihapus.

### 6. Penyelesaian (± 1 menit)
1. Sebagai **Kustodian A**, serahkan lagi ke Kustodian B. Sebagai **Kustodian B**, terima dengan **berkas asli**. Pemegang berpindah; badge ketidakcocokan **tetap** ada.
2. (Opsional) Tunjukkan **Tolak**: serahkan sekali lagi lalu tolak dengan alasan `Berkas tidak sesuai`.
3. Klik **Tutup** dengan catatan `Analisis selesai`. Status menjadi **Ditutup** dan tidak ada lagi tombol aksi.

### 7. Jejak audit (± 1 menit)
1. Lini masa **Riwayat** menampilkan setiap aksi: siapa, kapan, dan catatannya, termasuk ketidakcocokan dan penolakan.
2. Pada **Periksa keutuhan berkas**, unggah berkas asli (**COCOK**), lalu versi yang diubah (**TIDAK COCOK**). Pemeriksaan ini hanya membaca, tidak mencatat apa pun.
3. Muat ulang halaman: **Log aktivitas** dibaca ulang dari event blockchain, termasuk entri ketidakcocokan berwarna kuning.

### 8. Jeda darurat (± 1 menit)
1. Sebagai **Penyidik**, klik **Jeda sistem**: ditolak, karena bukan admin.
2. Pilih **Admin**, klik **Jeda sistem**. Muncul label **SISTEM DIJEDA**.
3. Coba daftarkan bukti sebagai Penyidik: ditolak karena sistem dijeda.
4. Sebagai **Admin**, klik **Lanjutkan sistem**.

### 9. Ketahanan jaringan (opsional, ± 2 menit)
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
| Nomor perkara tampil sebagai hash di browser sendiri | Data lokal browser terhapus, atau bukti didaftarkan dari browser lain. Ini perilaku yang diharapkan; gunakan **Cocokkan nomor perkara**. |
