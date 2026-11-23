# Perubahan dari UTS

Dokumen ini mencatat perbedaan antara MVP yang diuji saat UTS (tag `mvp-16nov`, commit `75e4a64`) dan versi Milestone 3 di branch `fix/gap-uts`. Ada dua gap dari desain UTS yang ditutup.

## Ringkasan

| | MVP (`mvp-16nov`) | Milestone 3 (`fix/gap-uts`) |
|---|---|---|
| Hash berkas tidak cocok saat serah-terima | `revert HashMismatch`; transaksi gagal, **tidak ada jejak** | Transaksi berhasil, event `DiscrepancyRecorded`, entri riwayat, `discrepancyCount` +1, serah-terima dibatalkan |
| Nilai kembali `acceptTransfer` | tidak ada | `bool accepted` |
| Nomor perkara on-chain | `string caseNumber` (teks biasa, di storage dan event) | `bytes32 caseRef` = keccak256(trim + huruf besar), `indexed` di event |
| Deskripsi on-chain | `string description` (teks biasa) | `bytes32 metadataHash` = keccak256(deskripsi), atau `0x0` jika kosong |
| Teks perkara | di blockchain | hanya di `localStorage` browser pendaftar |
| Jumlah uji | 52 | 58 |

## Gap 1: ketidakcocokan hash harus tercatat on-chain

**Masalah.** `acceptTransfer` dulu me-revert dengan `HashMismatch` jika hash berkas yang diserahkan penerima berbeda dari yang terdaftar. Revert membatalkan seluruh efek transaksi, termasuk event, sehingga upaya serah-terima dengan berkas yang sudah diubah tidak meninggalkan jejak apa pun di blockchain. Padahal desain UTS menuntut ketidakcocokan itu tercatat.

**Perubahan di kontrak.**
- `Action.DiscrepancyRecorded` ditambahkan di akhir enum (nilai 6), sehingga nilai aksi lama tidak bergeser.
- `event DiscrepancyRecorded(uint256 indexed id, address indexed by, bytes32 expected, bytes32 provided)`.
- `Evidence.discrepancyCount` (uint256): hanya bisa bertambah, tidak pernah dikurangi.
- `acceptTransfer(id, fileHash) returns (bool accepted)`:
  - Pemeriksaan yang tetap **revert**: `whenNotPaused`, bukti ada dan berstatus `InTransfer`, pemanggil adalah `pendingRecipient`.
  - Hash cocok: pemegang berpindah, `TransferAccepted`, kembali `true`.
  - Hash tidak cocok: `pendingRecipient = 0`, status kembali `Stored`, pemegang **tetap pengirim**, `discrepancyCount` +1, entri riwayat `DiscrepancyRecorded` (actor = penerima, counterparty = pengirim, note = hash yang diserahkan dalam hex), event `DiscrepancyRecorded`, kembali `false`.
- Error `HashMismatch` dihapus karena tidak dipakai lagi.

**Kenapa tidak menambah status baru.** Status `Disputed`/`Quarantined` sempat dipertimbangkan, tetapi akan mengubah state machine dan semua invariant yang bergantung padanya. Dengan mengembalikan bukti ke `Stored` pada pengirim, invariant lama tetap berlaku, pengirim bisa langsung menyerahkan ulang (ke penerima yang sama atau lain), dan tanda permanennya cukup dibawa oleh `discrepancyCount` serta riwayat.

**Uji baru/diubah.** Mismatch tercatat (event, riwayat, counter), pemegang tidak berpindah, pengirim bisa menyerahkan ulang dan tanda tetap ada, pengirim bisa menyerahkan ke kustodian lain, penerima tidak bisa menerima lagi tanpa serah-terima baru, bukan-penerima tetap revert `NotPendingRecipient`, fuzz semua hash salah tercatat. Invariant baru: `discrepancyCount` selalu sama dengan jumlah entri `DiscrepancyRecorded` di riwayat, dan ketidakcocokan tidak pernah memindahkan pemegang.

## Gap 2: data perkara tidak boleh teks biasa on-chain

**Masalah.** `caseNumber` dan `description` disimpan sebagai string di storage dan di event `EvidenceRegistered`. Siapa pun yang punya akses baca ke node bisa melihat nomor perkara dan deskripsi bukti.

**Perubahan di kontrak.**
- `registerEvidence(bytes32 caseRef, bytes32 metadataHash, bytes32 fileHash)`.
- `event EvidenceRegistered(uint256 indexed id, address indexed holder, bytes32 indexed caseRef, bytes32 fileHash, bytes32 metadataHash)`. `caseRef` di-index agar bukti bisa difilter per perkara; `fileHash` tidak lagi di-index karena batas tiga topik (pencarian per hash berkas tetap tersedia lewat `evidenceIdByHash`).
- Validasi: `caseRef` dan `fileHash` tidak boleh `bytes32(0)` (`EmptyField`). `metadataHash` **boleh** nol, karena deskripsi bersifat opsional sejak MVP; nol berarti "tanpa deskripsi".
- `MAX_CASE_NUMBER_LENGTH` dihapus. `MAX_TEXT_LENGTH` (256 byte) tetap dipakai untuk `note`.

**Perubahan di frontend.**
- Nomor perkara dinormalisasi (`trim()` lalu huruf besar) dan di-hash dengan keccak256 di browser; deskripsi di-hash apa adanya setelah `trim()`.
- Teks asli disimpan di `localStorage` (kunci per chainId + alamat kontrak, dibungkus try/catch) dan hanya ditampilkan jika hash-nya sama dengan yang on-chain, dengan label *tersimpan lokal di browser ini*. Browser lain melihat hash.
- Fitur **Cocokkan nomor perkara** di panel Riwayat.

## Perubahan frontend lain
- Terima serah-terima: pre-check `verifyIntegrity` hanya untuk memberi peringatan. Jika hash beda, pengguna diminta konfirmasi **Kirim & catat**; transaksi tetap dikirim. Event `DiscrepancyRecorded` dibaca dari receipt dan ditampilkan sebagai *Hash tidak cocok, tercatat di blok N*. Jika pengguna membatalkan di dialog, log menyatakan tidak ada yang tercatat.
- Badge **⚠ n× hash tidak cocok** di tabel dan detail, entri merah di riwayat, entri kuning di log aktivitas (memakai pagination `eth_getLogs` yang sudah ada).
- Akun **Tamu (tanpa peran)** ditambahkan (`OUTSIDER` di `Deploy.s.sol`, hanya diberi saldo) untuk mendemokan penolakan akses. Akun ini tidak muncul sebagai pilihan penerima.
- Log transaksi sukses kini menyertakan tx hash.

## Verifikasi (23 Nov 2026)

| Pemeriksaan | Hasil |
|---|---|
| `forge build` | sukses (solc 0.8.28) |
| `forge test` | **58/58 lulus** (sebelumnya 52/52 di `mvp-16nov`) |
| `forge coverage` | `src/SaksiRegistry.sol`: 100% baris (93/93), statement (98/98), cabang (12/12), fungsi (20/20) |
| `slither . --filter-paths "lib\|test"` | **0 temuan** (13 kontrak, 102 detektor). Tanpa filter ada 45 temuan, semuanya di `lib/openzeppelin-contracts` (antara lain `Strings`/`Bytes`/`Math` yang kini ikut ter-import) |

### Hasil uji end-to-end

Besu QBFT lokal (4 validator, chainId 1337), kontrak `0x3484b20600854091c166c062facad700123f5f71` (deploy di blok 5305, tx `0x5b3a522c54d798b0de9ce0ca513422260a99fa545bf5c2ce4e4bb9f95dc71322`), lewat frontend di `http://localhost:5180`.

| # | Skenario | Hasil | Blok | Tx hash |
|---|---|---|---|---|
| 1 | Penyidik mendaftarkan bukti #1 (` lp/123/xi/2026 `, dinormalisasi jadi `LP/123/XI/2026`) | ✅ On-chain hanya `caseRef 0x26ea…9e02`; teks tampil dengan label lokal | 5330 | `0xa342b9ec5a7c6ae78cd86fdebfac4cdf510df6689b38e9597eeed483d673d9c7` |
| 2 | Penyidik → Kustodian A | ✅ Status Dalam serah-terima | 5342 | `0xdb872074789e29be28339939be7c05295f22e59f09a954abdae6a81922659fe7` |
| 3 | Kustodian A menerima dengan **berkas diubah** | ✅ Dialog konfirmasi → transaksi sukses, *Hash tidak cocok, tercatat di blok 5356*; pemegang tetap Penyidik; badge 1× | 5356 | `0x8ac2a87213983eefaf4b6c3eace4fa14154b0e4e8cfc192de60b9f93a38038f7` |
| 4 | Penyidik menyerahkan ulang ke Kustodian A | ✅ | 5367 | `0x194eff3f0ca707c89dc28028ad6230026179d79e057136fe4450a7bd4a4ceef2` |
| 5 | Kustodian A menerima dengan **berkas asli** | ✅ Pemegang Kustodian A; `discrepancyCount` tetap 1 | 5373 | `0x72803b7a5ee3d408fc68c42c38488d5d47afa84e96032e88b7db998fdb147d5e` |
| 6 | Tamu (tanpa peran) mendaftarkan bukti | ✅ Ditolak *tidak memiliki peran Penyidik*; nonce akun tetap 0 | – | – (tidak ada transaksi) |
| 7 | Cocokkan nomor perkara `lp/123/xi/2026 ` / `LP/124/XI/2026` | ✅ COCOK / TIDAK COCOK | – | – (hanya baca) |
| 8 | Browser tanpa data lokal (localStorage dikosongkan, muat ulang) | ✅ Perkara dan deskripsi tampil sebagai hash; log aktivitas dari event memuat entri ketidakcocokan | – | – |
| 9 | Tampilan 375px | ✅ Tanpa scroll horizontal | – | – |

Status akhir bukti #1 dari `getEvidence(1)`: pemegang Kustodian A, status Disimpan, `pendingRecipient` nol, `discrepancyCount = 1`.

## Keterbatasan yang tersisa

- **`caseRef` tanpa salt bisa ditebak.** Format nomor perkara terpola, jadi ruang kemungkinannya kecil dan hash bisa dibalik dengan mencoba semua kombinasi. Perbaikan yang mungkin: salt/HMAC per perkara yang disimpan di luar rantai, dengan konsekuensi pencocokan butuh salt tersebut.
- **`note` masih teks biasa** di storage dan event (serah-terima, penolakan, penutupan).
- **Teks asli hanya di satu browser** (`localStorage`); hilang jika data browser dihapus. Belum ada penyimpanan off-chain bersama.
- **Ketidakcocokan bisa dipicu sengaja** oleh calon penerima. `discrepancyCount` menandai adanya upaya dengan berkas berbeda, bukan menentukan siapa yang mengubah berkas.
- **Tidak kompatibel dengan deployment lama.** ABI berubah (`registerEvidence`, `getEvidence`, event), sehingga kontrak harus di-deploy ulang dan data uji lama tidak ikut pindah.
