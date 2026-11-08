#!/usr/bin/env bash
# Deploy SaksiRegistry lalu tulis frontend/config.js untuk simulasi.
# Pemakaian: scripts/deploy.sh anvil   (anvil harus sudah berjalan di port 8545)
#            scripts/deploy.sh besu    (jaringan besu-network harus sudah berjalan)
#
# Semua kunci privat di bawah ini adalah kunci uji PUBLIK (anvil dan tutorial Besu).
# Jangan pernah dipakai di jaringan sungguhan.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"

NETWORK="${1:-}"
case "$NETWORK" in
  anvil)
    RPC_URL="http://127.0.0.1:8545"
    ADMIN_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
    INVESTIGATOR_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
    CUSTODIAN_A_KEY=0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
    CUSTODIAN_B_KEY=0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
    FUND_WEI=0
    ;;
  besu)
    . besu-network/ports.env 2>/dev/null || true
    RPC_URL="http://127.0.0.1:${RPC_BASE:-8545}"
    ADMIN_KEY=0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63
    INVESTIGATOR_KEY=0xc87509a1c067bbde78beb793e6fa76530b6382a4c0241e5e4a9ec0a0f44dc0d3
    CUSTODIAN_A_KEY=0xae6ae8e5ccbfb04590405997ee2d52d2b330726137b875053c36d94e974d162f
    CUSTODIAN_B_KEY=0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
    FUND_WEI=10000000000000000000   # 10 ETH untuk akun yang belum punya saldo
    ;;
  *)
    echo "Pemakaian: $0 anvil|besu" >&2; exit 1 ;;
esac

if ! CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL" 2>/dev/null); then
  echo "RPC $RPC_URL tidak bisa dihubungi. Jalankan dulu: $( [ "$NETWORK" = anvil ] && echo 'anvil' || echo 'besu-network/start.sh')" >&2
  exit 1
fi

ADMIN=$(cast wallet address "$ADMIN_KEY")
export ADMIN_PRIVATE_KEY="$ADMIN_KEY" FUND_WEI
export INVESTIGATOR=$(cast wallet address "$INVESTIGATOR_KEY")
export CUSTODIAN_A=$(cast wallet address "$CUSTODIAN_A_KEY")
export CUSTODIAN_B=$(cast wallet address "$CUSTODIAN_B_KEY")

echo "Deploy ke $NETWORK ($RPC_URL, chainId $CHAIN_ID)..."
forge script script/Deploy.s.sol:Deploy --rpc-url "$RPC_URL" --broadcast --slow -q

RUN="broadcast/Deploy.s.sol/$CHAIN_ID/run-latest.json"
ADDRESS=$(jq -r '[.transactions[] | select(.transactionType=="CREATE")][0].contractAddress' "$RUN")
DEPLOY_BLOCK=$(( $(jq -r '.receipts[0].blockNumber' "$RUN") ))
[ -n "$ADDRESS" ] && [ "$ADDRESS" != null ] || { echo "Alamat kontrak tidak ditemukan di $RUN" >&2; exit 1; }

ABI=$(jq -c '.abi' out/SaksiRegistry.sol/SaksiRegistry.json)
cat > frontend/config.js <<EOF
// Dibuat otomatis oleh scripts/deploy.sh $NETWORK pada $(date '+%Y-%m-%d %H:%M:%S').
// Berisi kunci uji PUBLIK untuk simulasi lokal saja. Jangan di-commit.
window.SAKSI_CONFIG = {
  network: "$NETWORK",
  rpcUrl: "$RPC_URL",
  chainId: $CHAIN_ID,
  contractAddress: "$ADDRESS",
  deployBlock: $DEPLOY_BLOCK,
  accounts: [
    { key: "admin", label: "Admin", role: "Admin", address: "$ADMIN", privateKey: "$ADMIN_KEY" },
    { key: "investigator", label: "Penyidik", role: "Penyidik", address: "$INVESTIGATOR", privateKey: "$INVESTIGATOR_KEY" },
    { key: "custodianA", label: "Kustodian A (Gudang Bukti)", role: "Kustodian", address: "$CUSTODIAN_A", privateKey: "$CUSTODIAN_A_KEY" },
    { key: "custodianB", label: "Kustodian B (Lab Forensik)", role: "Kustodian", address: "$CUSTODIAN_B", privateKey: "$CUSTODIAN_B_KEY" }
  ],
  abi: $ABI
};
EOF

echo "SaksiRegistry : $ADDRESS (blok $DEPLOY_BLOCK)"
echo "Penyidik      : $INVESTIGATOR"
echo "Kustodian A   : $CUSTODIAN_A"
echo "Kustodian B   : $CUSTODIAN_B"
echo "frontend/config.js diperbarui. Buka frontend dengan: scripts/serve-frontend.sh"
