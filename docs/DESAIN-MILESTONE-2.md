# Desain Milestone 2 — Kontrak SAKSI

Dokumen ini menjelaskan desain kontrak `SaksiRegistry` untuk pencatatan serah-terima (chain of custody) bukti digital. Sesuai arahan dosen, desain dibuat **sederhana**: satu kontrak, tiga peran, dan satu alur serah-terima dua langkah.

## 1. Prinsip desain

1. **Hanya hash yang disimpan di blockchain.** Berkas bukti (citra disk, foto, dokumen) tetap di luar rantai. Yang dicatat adalah hash SHA-256 berkas tersebut. Data pribadi tidak pernah ditulis ke blockchain karena data di blockchain bersifat permanen dan bisa dibaca semua node.
2. **Serah-terima harus disetujui dua pihak.** Pengirim memulai, penerima mengonfirmasi. Ini meniru berita acara serah-terima yang ditandatangani kedua belah pihak.
3. **Penerima memverifikasi keutuhan berkas.** Saat menerima, penerima mengirim hash berkas yang ia hitung sendiri. Jika tidak sama dengan hash yang terdaftar, transaksi ditolak, sehingga perubahan berkas langsung terdeteksi.
4. **Jejak audit tidak bisa diubah.** Setiap aksi dicatat dalam riwayat on-chain dan event. Tidak ada fungsi untuk mengedit atau menghapus riwayat, dan kontrak tidak bisa di-upgrade.

## 2. Peran

| Peran | Konstanta | Contoh di dunia nyata | Hak |
|---|---|---|---|
| Admin | `DEFAULT_ADMIN_ROLE` | Kepala unit / laboratorium | Memberi dan mencabut peran, menjeda dan melanjutkan sistem |
| Penyidik | `INVESTIGATOR_ROLE` | Penyidik lapangan | Mendaftarkan bukti baru (otomatis menjadi pemegang pertama) |
| Kustodian | `CUSTODIAN_ROLE` | Petugas gudang bukti, pemeriksa forensik | Menerima, menyimpan, dan menyerahkan bukti |

Penyidik dan kustodian disebut **personel**. Hanya personel yang boleh memegang, menyerahkan, atau menerima bukti. Admin sengaja tidak otomatis menjadi personel (pemisahan tugas).

## 3. Data bukti

| Field | Tipe | Keterangan |
|---|---|---|
| `caseNumber` | string (≤ 64 byte) | Nomor perkara, misalnya `LP/123/XI/2026` |
| `description` | string (≤ 256 byte) | Deskripsi singkat bukti |
| `fileHash` | bytes32 | Hash SHA-256 berkas bukti, tidak pernah berubah |
| `holder` | address | Pemegang bukti saat ini |
| `pendingRecipient` | address | Calon penerima saat serah-terima berlangsung |
| `status` | enum | `Stored`, `InTransfer`, `Closed` |
| `registeredAt` | uint64 | Waktu pendaftaran (timestamp blok) |

Satu hash hanya boleh didaftarkan sekali, agar satu berkas tidak tercatat sebagai dua bukti berbeda.

## 4. Diagram status

```
                 registerEvidence
                        │
                        ▼
              ┌──────────────────┐   initiateTransfer   ┌──────────────────┐
              │      Stored      │ ───────────────────► │    InTransfer    │
              │ (disimpan oleh   │ ◄─────────────────── │ (menunggu        │
              │  pemegang)       │  acceptTransfer      │  konfirmasi)     │
              └──────────────────┘  rejectTransfer      └──────────────────┘
                        │           cancelTransfer
                        │ closeEvidence
                        ▼
              ┌──────────────────┐
              │      Closed      │  status akhir, tidak bisa diubah lagi
              └──────────────────┘
```

- `acceptTransfer`: pemegang berganti ke penerima.
- `rejectTransfer` (oleh penerima) dan `cancelTransfer` (oleh pengirim): pemegang tetap pengirim.

## 5. Fungsi

| Fungsi | Siapa | Syarat utama | Efek |
|---|---|---|---|
| `registerEvidence(caseNumber, description, fileHash)` | Penyidik | hash ≠ 0, belum pernah terdaftar | Bukti baru, status `Stored`, pemegang = pemanggil |
| `initiateTransfer(id, to, note)` | Pemegang | status `Stored`, `to` adalah personel lain | Status `InTransfer` |
| `acceptTransfer(id, fileHash)` | Calon penerima | status `InTransfer`, hash cocok | Pemegang = penerima, status `Stored` |
| `rejectTransfer(id, note)` | Calon penerima | status `InTransfer` | Status kembali `Stored` |
| `cancelTransfer(id)` | Pemegang | status `InTransfer` | Status kembali `Stored` |
| `closeEvidence(id, note)` | Pemegang | status `Stored` | Status `Closed` (akhir) |
| `pause()` / `unpause()` | Admin | — | Menghentikan / melanjutkan semua perubahan data |
| `getEvidence(id)` | Siapa saja | — | Data bukti |
| `getHistory(id)` | Siapa saja | — | Seluruh riwayat serah-terima |
| `verifyIntegrity(id, fileHash)` | Siapa saja | — | `true` jika hash cocok |

## 6. Riwayat dan event

Setiap aksi menambah satu catatan ke riwayat bukti: jenis aksi, pelaku, pihak lawan, waktu, dan catatan. Aksi yang sama juga dipancarkan sebagai event (`EvidenceRegistered`, `TransferInitiated`, `TransferAccepted`, `TransferRejected`, `TransferCancelled`, `EvidenceClosed`) sehingga aplikasi bisa memantau perubahan.

## 7. Error

Kontrak memakai *custom error* agar pesan penolakan jelas dan hemat gas, misalnya `NotHolder`, `NotPendingRecipient`, `InvalidStatus`, `HashMismatch`, `DuplicateEvidence`, `InvalidRecipient`, `EvidenceNotFound`, `EmptyField`, dan `FieldTooLong`.

## 8. Yang sengaja tidak dibuat

Agar tetap sederhana: objek perkara terpisah, bukti multi-berkas (Merkle), bukti turunan, peran analis/auditor terpisah, dan kemampuan upgrade.

## 9. Rencana pengujian

- **Uji unit:** setiap fungsi, baik jalur berhasil maupun setiap jenis penolakan.
- **Uji fuzz:** pendaftaran dengan data acak, dan penolakan untuk hash apa pun yang salah.
- **Uji invariant:**
  1. Hash bukti tidak pernah berubah.
  2. Status `InTransfer` jika dan hanya jika ada calon penerima.
  3. Pemegang selalu terisi.
  4. Riwayat hanya bertambah, dan bukti `Closed` tidak pernah berubah lagi.
  5. Jumlah bukti sama dengan jumlah pendaftaran yang berhasil.
- **Slither** tanpa temuan penting, **coverage** ≥ 90%.

## 10. Simulasi frontend

Halaman web sederhana di `frontend/` untuk demo:

- Pilih peran (Admin, Penyidik, Kustodian A, Kustodian B) memakai akun uji lokal, tanpa MetaMask.
- Unggah berkas: browser menghitung SHA-256, berkas tidak dikirim ke mana pun.
- Daftarkan bukti, serahkan, terima (dengan unggah ulang berkas), tolak, batalkan, tutup.
- Demo deteksi perubahan: unggah berkas yang sudah diubah saat menerima, transaksi ditolak.
- Lini masa riwayat serah-terima setiap bukti.
- Bisa terhubung ke anvil (pengembangan) maupun jaringan Besu (demo).
