# SAKSI Contracts

Smart contract untuk **SAKSI**, proyek kuliah yang mencatat serah-terima (*chain of custody*) bukti digital di blockchain *permissioned*. Setiap perpindahan bukti tercatat permanen, dan perubahan isi berkas bukti langsung terdeteksi.

> **Status:** Milestone 2 selesai — kontrak `SaksiRegistry`, pengujian lengkap, dan frontend simulasi.

## Cara kerja singkat

1. **Penyidik** mendaftarkan bukti. Yang disimpan di blockchain hanya **hash SHA-256** berkas, bukan berkasnya.
2. Pemegang bukti **memulai serah-terima** ke personel lain.
3. Penerima **mengonfirmasi** dengan mengunggah berkas yang ia terima. Jika hash-nya berbeda dari yang terdaftar, smart contract **menolak** serah-terima (berkas telah diubah).
4. Setiap aksi tercatat di **riwayat** yang tidak bisa diedit atau dihapus.

| Peran | Hak |
|---|---|
| Admin | Memberi/mencabut peran, menjeda dan melanjutkan sistem |
| Penyidik | Mendaftarkan bukti baru |
| Kustodian | Menerima, menyimpan, dan menyerahkan bukti |

Status bukti: `Disimpan → Dalam serah-terima → Disimpan … → Ditutup` (final). Desain lengkap ada di [`docs/DESAIN-MILESTONE-2.md`](docs/DESAIN-MILESTONE-2.md).

## Teknologi

| Komponen | Versi |
|---|---|
| Solidity | 0.8.28 (`evm_version = prague`) |
| [Foundry](https://book.getfoundry.sh/) | 1.9.0 |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) | v5.7.0 (AccessControl, Pausable) |
| [Slither](https://github.com/crytic/slither) | 0.11.6 (di `.venv`) |
| [Hyperledger Besu](https://github.com/besu-eth/besu) | 26.11.0, QBFT, 4 validator |
| Frontend | HTML + JavaScript + [ethers.js](https://docs.ethers.org/v6/) 6.17.0 (disertakan di `frontend/vendor`) |

## Struktur repositori

```
src/SaksiRegistry.sol               Kontrak utama
test/SaksiRegistry.t.sol            Uji unit dan fuzz (46 uji)
test/SaksiRegistry.invariant.t.sol  Uji invariant (4 invariant)
test/Setup.t.sol                    Uji asap toolchain (Milestone 1)
script/Deploy.s.sol                 Deploy + pemberian peran
scripts/deploy.sh                   Deploy ke anvil/Besu dan buat frontend/config.js
scripts/serve-frontend.sh           Server web lokal untuk frontend
frontend/                           Halaman simulasi
besu-network/                       Jaringan Besu QBFT 4 validator
docs/                               Desain, laporan milestone, panduan demo
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

Hasil terakhir: **52 uji lulus**, **coverage 100%** (baris, statement, cabang, fungsi), **Slither 0 temuan**.

## Menjalankan simulasi frontend

### Pilihan A — Anvil (cepat, untuk latihan)

```bash
anvil                         # terminal 1, biarkan berjalan
scripts/deploy.sh anvil       # terminal 2
scripts/serve-frontend.sh     # terminal 2
```

### Pilihan B — Besu QBFT (untuk demo)

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

## Milestone

- [x] **Milestone 1** — Lingkungan pengembangan dan pengujian
- [x] **Milestone 2** — Kontrak SAKSI, pengujian, dan frontend simulasi
- [ ] **Milestone 3** — Demo dan presentasi akhir
