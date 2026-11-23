# SAKSI Contracts

Smart contract untuk **SAKSI** (Sistem Audit Kustodi & Serah-Terima Integritas Bukti Digital), proyek kuliah yang mencatat serah-terima (*chain of custody*) bukti digital di blockchain *permissioned*. Setiap perpindahan bukti tercatat permanen, dan setiap upaya serah-terima dengan berkas yang sudah diubah **ikut tercatat** di blockchain.

> **Status:** Milestone 3: perbaikan gap UTS (ketidakcocokan hash dicatat on-chain, data perkara hanya berupa hash), demo, dan presentasi akhir.
>
> **Deployment publik:** <https://saksi.nafhanhs.my.id> (dikelola anggota kelompok, dipakai penguji).

## Quickstart

```bash
git clone --recurse-submodules https://github.com/keshamr77/TUBES-BLOCKCHAIN-ET4133.git saksi-contracts && cd saksi-contracts
forge test                     # 58 uji
besu-network/start.sh          # 4 validator QBFT (kunci validator dibuat dulu, lihat "Jaringan Besu QBFT")
scripts/deploy.sh besu         # deploy kontrak dan tulis frontend/config.js
scripts/serve-frontend.sh      # buka http://localhost:5180
```

## Cara kerja singkat

1. **Penyidik** mendaftarkan bukti. Yang disimpan di blockchain hanya **hash**: SHA-256 berkas, keccak256 nomor perkara (`caseRef`), dan keccak256 deskripsi (`metadataHash`). Berkas dan teks perkara tidak pernah dikirim ke blockchain.
2. Pemegang bukti **memulai serah-terima** ke personel lain.
3. Penerima **mengonfirmasi** dengan mengunggah berkas yang ia terima.
   - Hash **cocok**: bukti berpindah ke penerima.
   - Hash **tidak cocok**: transaksi tetap berhasil, tetapi bukti **tidak** berpindah. Ketidakcocokan dicatat di riwayat dan event `DiscrepancyRecorded`, serah-terima dibatalkan, dan `discrepancyCount` bukti bertambah sebagai tanda permanen.
4. Setiap aksi tercatat di **riwayat** yang tidak bisa diedit atau dihapus.

| Peran | Hak |
|---|---|
| Admin | Memberi/mencabut peran, menjeda dan melanjutkan sistem |
| Penyidik | Mendaftarkan bukti baru |
| Kustodian | Menerima, menyimpan, dan menyerahkan bukti |

Status bukti: `Disimpan → Dalam serah-terima → Disimpan … → Ditutup` (final). Ketidakcocokan hash tidak menambah status baru: bukti kembali ke `Disimpan` pada pengirim. Desain awal ada di [`docs/DESAIN-MILESTONE-2.md`](docs/DESAIN-MILESTONE-2.md), perubahannya di [`docs/PERUBAHAN-DARI-UTS.md`](docs/PERUBAHAN-DARI-UTS.md).

## Akun uji (jaringan Besu lokal)

Dibuat oleh `scripts/deploy.sh besu` dan bisa dipilih lewat menu peran di frontend. Semuanya **kunci uji publik**; jangan dipakai di jaringan sungguhan.

| Peran di frontend | Alamat | Peran on-chain |
|---|---|---|
| Admin | `0xFE3B557E8Fb62b89F4916B721be55cEb828dBd73` | `DEFAULT_ADMIN_ROLE` |
| Penyidik | `0x627306090abaB3A6e1400e9345bC60c78a8BEf57` | `INVESTIGATOR_ROLE` |
| Kustodian A (Gudang Bukti) | `0xf17f52151EbEF6C7334FAD080c5704D77216b732` | `CUSTODIAN_ROLE` |
| Kustodian B (Lab Forensik) | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | `CUSTODIAN_ROLE` |
| Tamu (tanpa peran) | `0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65` | tidak ada (hanya diberi saldo) |

Deployment publik bisa memakai kunci lain; lihat menu peran di halamannya.

## Skenario uji

| # | Skenario | Langkah singkat | Hasil yang diharapkan |
|---|---|---|---|
| 1 | Pendaftaran bukti | Penyidik mengisi nomor perkara, deskripsi, berkas | Bukti terdaftar. On-chain hanya `caseRef`/`metadataHash`; teks tampil dengan label "tersimpan lokal di browser ini" |
| 2 | Browser lain | Buka halaman di browser/profil lain | Kolom perkara dan deskripsi menampilkan hash, bukan teks |
| 3 | Cocokkan nomor perkara | Ketik nomor perkara di panel Riwayat | `COCOK` jika sama (huruf besar/kecil dan spasi di ujung diabaikan), `TIDAK COCOK` jika beda |
| 4 | Serah-terima dengan berkas diubah | Penyidik → Kustodian A, A menerima dengan berkas versi diubah, konfirmasi "Kirim & catat" | Transaksi sukses, log "Hash tidak cocok, tercatat di blok N", bukti tetap pada pengirim, badge "1× hash tidak cocok", entri merah di riwayat |
| 5 | Serah-terima dengan berkas asli | Pengirim menyerahkan ulang, penerima mengunggah berkas asli | Pemegang berpindah; badge ketidakcocokan tetap ada |
| 6 | Akun tanpa peran | Tamu mencoba mendaftarkan bukti | Ditolak ("tidak memiliki peran Penyidik"), tidak ada transaksi yang masuk blok |
| 7 | Bukan penerima | Akun selain calon penerima menekan Terima (uji unit) | Revert `NotPendingRecipient` |
| 8 | Jeda darurat | Admin menjeda, Penyidik mencoba mendaftar | Ditolak karena sistem dijeda |

Hasil uji end-to-end terakhir (Besu lokal, 23 Nov 2026) ada di [`docs/PERUBAHAN-DARI-UTS.md`](docs/PERUBAHAN-DARI-UTS.md#hasil-uji-end-to-end).

## Teknologi

| Komponen | Versi |
|---|---|
| Solidity | 0.8.28 (`evm_version = prague`) |
| [Foundry](https://book.getfoundry.sh/) | 1.9.0 |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) | v5.7.0 (AccessControl, Pausable, Strings) |
| [Slither](https://github.com/crytic/slither) | 0.11.6 (di `.venv`) |
| [Hyperledger Besu](https://github.com/besu-eth/besu) | 26.11.0, QBFT, 4 validator |
| Frontend | HTML + JavaScript + [ethers.js](https://docs.ethers.org/v6/) 6.17.0 (disertakan di `frontend/vendor`) |

## Struktur repositori

```
src/SaksiRegistry.sol               Kontrak utama
test/SaksiRegistry.t.sol            Uji unit dan fuzz (52 uji)
test/SaksiRegistry.invariant.t.sol  Uji invariant (5 invariant)
test/Setup.t.sol                    Uji asap toolchain (Milestone 1, 5 uji)
script/Deploy.s.sol                 Deploy + pemberian peran
scripts/deploy.sh                   Deploy ke anvil/Besu dan buat frontend/config.js
scripts/serve-frontend.sh           Server web lokal untuk frontend
frontend/                           Halaman simulasi
besu-network/                       Jaringan Besu QBFT 4 validator
docs/                               Desain, perubahan dari UTS, panduan demo
```

## Persiapan setelah clone

Kebutuhan: Linux atau WSL2 (diuji di Ubuntu 24.04), git, curl, jq, build-essential, python3-venv.

```bash
git clone --recurse-submodules <url-repo> saksi-contracts
cd saksi-contracts
git submodule update --init --recursive   # jika clone tanpa --recurse-submodules

curl -L https://foundry.paradigm.xyz | bash && foundryup
forge build
forge test
```

## Perintah harian

```bash
forge test                        # semua uji
forge test -vv --match-contract SaksiRegistryTest
FOUNDRY_PROFILE=ci forge test     # fuzz 10.000 run, invariant lebih dalam
forge coverage --no-match-coverage "test|script"
forge test --gas-report
source .venv/bin/activate && slither . --filter-paths "lib|test"
```

Hasil terakhir (23 Nov 2026): **58 uji lulus** (52 unit/fuzz, 1 suite berisi 5 invariant, 5 uji asap), **coverage `SaksiRegistry.sol` 100%** (baris, statement, cabang, fungsi), **Slither 0 temuan**.

## Menjalankan simulasi frontend

### Pilihan A: Anvil (cepat, untuk latihan)

```bash
anvil                         # terminal 1, biarkan berjalan
scripts/deploy.sh anvil       # terminal 2
scripts/serve-frontend.sh     # terminal 2
```

### Pilihan B: Besu QBFT (untuk demo)

```bash
besu-network/start.sh
scripts/deploy.sh besu
scripts/serve-frontend.sh
```

Lalu buka **http://localhost:5180** di browser Windows. Pakai `localhost`, bukan alamat IP, karena browser hanya mengizinkan perhitungan hash di alamat yang aman.

Panduan demo langkah demi langkah: [`docs/PANDUAN-DEMO.md`](docs/PANDUAN-DEMO.md).

Foto latar di bagian atas halaman tidak disertakan di repositori karena merupakan gambar pihak ketiga. Jika ingin memakainya, letakkan berkas gambar di `frontend/assets/hero-timbangan.webp`. Tanpa berkas itu, halaman tetap berjalan dengan latar gradien.

> ⚠️ Akun di frontend memakai **kunci uji publik** (anvil dan tutorial Besu). `frontend/config.js` dibuat otomatis dan tidak di-commit. Jangan pernah memakai kunci ini di jaringan sungguhan.

## Jaringan Besu QBFT

Script membutuhkan Java 25 di `~/.local/opt/jdk-25` dan Besu di `~/.local/opt/besu-26.11.0` (diatur di `besu-network/common.sh`).

Kunci validator **tidak** di-commit. Setelah clone, buat kunci baru dari folder `besu-network/`:

```bash
cd besu-network
JAVA_HOME=~/.local/opt/jdk-25 ~/.local/opt/besu-26.11.0/bin/besu operator generate-blockchain-config \
  --config-file=qbftConfigFile.json --to=networkFiles --private-key-file-name=key
cp networkFiles/genesis.json genesis.json
i=1; for d in networkFiles/keys/*/; do mkdir -p Node-$i; cp $d/key $d/key.pub Node-$i/; i=$((i+1)); done
rm -rf networkFiles
```

```bash
besu-network/start.sh     # jalankan 4 validator (atau: start.sh 3 4)
besu-network/status.sh    # nomor blok dan jumlah peer tiap node
besu-network/stop.sh      # hentikan semua (atau: stop.sh 2), berdasarkan PID
besu-network/reset.sh     # hapus data rantai saja; kunci dan genesis tetap
```

| Node | JSON-RPC | P2P |
|---|---|---|
| 1 (bootnode) | http://127.0.0.1:8545 | 30303 |
| 2 | http://127.0.0.1:8546 | 30304 |
| 3 | http://127.0.0.1:8547 | 30305 |
| 4 | http://127.0.0.1:8548 | 30306 |

### Catatan desain jaringan

- **Milestone Prague, bukan Osaka:** solc 0.8.28 hanya mendukung EVM sampai Prague, jadi genesis memakai `pragueTime: 0` dan `foundry.toml` memakai `evm_version = "prague"` agar compiler dan jaringan identik.
- **Gas limit** 100.000.000 agar kontrak besar bisa di-deploy (batas ukuran kode 24 KB dari EIP-170 tetap berlaku).
- **Toleransi gangguan:** dengan 4 validator, QBFT tahan 1 node mati. Teruji: blok tetap bertambah dengan 3/4 node, berhenti dengan 2/4, dan pulih setelah node kembali.
- Setiap node memakai `BESU_OPTS=-Xmx1g -Djava.net.preferIPv4Stack=true`. Opsi IPv4 diperlukan agar browser di Windows bisa menghubungi node di WSL.

## Known Issues

- **`caseRef` bisa ditebak.** keccak256 nomor perkara dihitung tanpa salt. Karena format nomor perkara terpola (mis. `LP/123/XI/2026`), penyerang bisa mencoba semua kombinasi dan menemukan nomor perkara dari hash-nya. Hash menyembunyikan teks dari pembaca biasa, tetapi bukan enkripsi.
- **Catatan serah-terima masih teks biasa.** Field `note` pada `initiateTransfer`, `rejectTransfer`, dan `closeEvidence` disimpan apa adanya di storage dan event. Jangan menulis data pribadi di catatan.
- **Teks perkara hanya ada di satu browser.** Nomor perkara dan deskripsi asli disimpan di `localStorage` browser yang mendaftarkan. Jika data browser dihapus, teks itu hilang; yang tersisa hanya hash di blockchain (bisa dicocokkan ulang lewat "Cocokkan nomor perkara").
- **Ketidakcocokan bisa dipicu penerima.** Calon penerima yang sengaja mengirim hash salah tetap menambah `discrepancyCount`. Penanda ini berarti "pernah ada upaya serah-terima dengan berkas berbeda", bukan bukti siapa yang mengubah berkas; penelusurannya tetap di luar rantai (riwayat mencatat akun penerima dan hash yang diserahkan).
- **Deployment publik perlu deploy ulang.** ABI dan alamat kontrak berubah. Sampai deployment publik diperbarui, <https://saksi.nafhanhs.my.id> masih menjalankan kontrak MVP (tag `mvp-16nov`), yang menolak berkas diubah dengan revert.
- **Kunci uji publik di frontend.** Simulasi menandatangani transaksi langsung di browser memakai kunci uji. Cocok untuk demo, tidak untuk produksi.

## Milestone

- [x] **Milestone 1**: Lingkungan pengembangan dan pengujian
- [x] **Milestone 2**: Kontrak SAKSI, pengujian, dan frontend simulasi (tag `mvp-16nov`)
- [ ] **Milestone 3**: Perbaikan gap UTS, demo, dan presentasi akhir (branch `fix/gap-uts`)
