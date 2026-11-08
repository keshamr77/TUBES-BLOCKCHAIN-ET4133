# SAKSI Contracts

Smart contracts for **SAKSI** — a university project that records the chain of custody (serah-terima) of digital evidence on a permissioned blockchain, so every hand-over of an evidence item is traceable and tamper-evident.

> **Status:** Milestone 1 (environment setup) complete. The SAKSI contracts themselves are not written yet; `test/Setup.t.sol` contains only a toolchain smoke test.

## Tech stack

| Component | Version |
|---|---|
| Solidity | 0.8.28 (`evm_version = prague`) |
| [Foundry](https://book.getfoundry.sh/) (forge, cast, anvil) | 1.9.0 |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) | v5.7.0 |
| [Slither](https://github.com/crytic/slither) | 0.11.6 (in `.venv`) |
| [Hyperledger Besu](https://github.com/besu-eth/besu) | 26.11.0, QBFT, 4 validators |
| Java (for Besu) | Temurin 25 LTS |

## Repository layout

```
src/                 Solidity contracts (SAKSI contracts go here)
test/                Foundry tests (Setup.t.sol = toolchain smoke test)
script/              Foundry deployment scripts
lib/                 Dependencies as git submodules (forge-std, openzeppelin-contracts)
besu-network/        Local 4-validator Besu QBFT network
  qbftConfigFile.json  Input for key + genesis generation
  genesis.json         Network genesis (chainId 1337, Prague, gasLimit 100M)
  start.sh stop.sh reset.sh status.sh
foundry.toml         Compiler, optimizer, fuzz and invariant settings
remappings.txt       @openzeppelin/contracts/ and forge-std/ import paths
```

## Getting started

Requirements: Linux or WSL2 (Ubuntu 24.04 tested), git, curl, jq, build-essential, python3-venv.

```bash
git clone --recurse-submodules <repo-url> saksi-contracts
cd saksi-contracts
# if you cloned without --recurse-submodules:
git submodule update --init --recursive

# Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup
forge build
forge test -vv
```

### Slither

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install slither-analyzer
slither . --filter-paths "lib|test"
```

## Common commands

```bash
forge test -vv                    # run tests
FOUNDRY_PROFILE=ci forge test     # heavier fuzz (10k runs) and invariant runs
forge coverage                    # coverage report
forge test --gas-report           # gas usage per function
forge fmt                         # format Solidity code
```

## Local Besu QBFT network

The scripts expect Java 25 at `~/.local/opt/jdk-25` and Besu at `~/.local/opt/besu-26.11.0` (paths are set in `besu-network/common.sh`).

Validator keys are **not** committed. On a fresh clone, generate new ones from `besu-network/`:

```bash
cd besu-network
JAVA_HOME=~/.local/opt/jdk-25 ~/.local/opt/besu-26.11.0/bin/besu operator generate-blockchain-config \
  --config-file=qbftConfigFile.json --to=networkFiles --private-key-file-name=key
cp networkFiles/genesis.json genesis.json
i=1; for d in networkFiles/keys/*/; do mkdir -p Node-$i; cp $d/key $d/key.pub Node-$i/; i=$((i+1)); done
rm -rf networkFiles
```

Then:

```bash
besu-network/start.sh     # start all 4 validators (or: start.sh 3 4)
besu-network/status.sh    # block number and peer count per node
besu-network/stop.sh      # stop all (or: stop.sh 2) — by PID, never by name
besu-network/reset.sh     # delete chain data only; keys and genesis are kept
```

| Node | JSON-RPC | P2P |
|---|---|---|
| 1 (bootnode) | http://127.0.0.1:8545 | 30303 |
| 2 | http://127.0.0.1:8546 | 30304 |
| 3 | http://127.0.0.1:8547 | 30305 |
| 4 | http://127.0.0.1:8548 | 30306 |

Example deploy of the smoke contract:

```bash
forge create test/Setup.t.sol:SmokeRegistry --rpc-url http://127.0.0.1:8545 \
  --private-key 0x8f2a55949038a9610f50fb23b5883af3b4ecb3c3bb792cbcefbd1542c692be63 \
  --broadcast --constructor-args 0xfe3b557e8fb62b89f4916b721be55ceb828dbd73
```

> ⚠️ The funded accounts in `qbftConfigFile.json` / `genesis.json` use **publicly known test keys** from the Besu tutorial. Use them only on this local network.

### Design notes

- **Milestone Prague, not Osaka:** solc 0.8.28 supports EVM versions up to Prague, so the genesis uses `pragueTime: 0` and `foundry.toml` uses `evm_version = "prague"` to keep compiler and chain identical.
- **Gas limit** is 100,000,000 so large contracts can be deployed (the 24 KB EIP-170 code size limit still applies).
- **Fault tolerance:** with 4 validators QBFT tolerates 1 offline node. Tested: blocks continue with 3/4, halt with 2/4, and resume after the nodes return.
- With less than 16 GB RAM, each node runs with `BESU_OPTS=-Xmx1g`.

## Milestones

- [x] **Milestone 1** — Development and test environment (Foundry, OpenZeppelin, Slither, Besu QBFT)
- [ ] **Milestone 2** — SAKSI chain-of-custody contracts with unit, fuzz and invariant tests
- [ ] **Milestone 3** — Deployment and demonstration on the Besu QBFT network
