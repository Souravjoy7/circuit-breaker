# Circuit Breaker — Decentralized Exploit Detection

**Real-time anomaly detection + auto-pause for smart contracts. $600B MEV problem, no decentralized solution existed — until now.**

## On-Chain Proof (Deployed & Verified)

### Base Sepolia (OP Stack)

| Contract | Address |
|----------|---------|
| **CircuitBreaker** | [`0x81734Aa0...1b65f`](https://sepolia.basescan.org/address/0x81734Aa078eB6b410Db4418Ce6edccACA0F1b65f) |
| AnomalyDetector | [`0xBf10e41A...3351`](https://sepolia.basescan.org/address/0xBf10e41A3e12cB173eaeb445B6b31EF8674F3351) |
| ProtocolRegistry | [`0x67a66c92...f76B`](https://sepolia.basescan.org/address/0x67a66c92fAC0194bb62Dc90f5a7b4cF83623f76B) |

### Linea Sepolia (ZK-Rollup)

| Contract | Address |
|----------|---------|
| **CircuitBreaker** | [`0x301045eA...97d51`](https://sepolia.lineascan.build/address/0x301045eAa0EF1c200178DC3f9a70580060397d51) |
| AnomalyDetector | [`0xBbf988EF...7354`](https://sepolia.lineascan.build/address/0xBbf988EFe8897a0183E390e7f5AA14F6a7A97354) |
| ProtocolRegistry | [`0x13Db0D79...67a6A`](https://sepolia.lineascan.build/address/0x13Db0D79479A1C7401EDA702B6029b1A96667a6A) |

**Deployer**: [`0x7F75bfAfeD5c96584774c7F2Bc33F3bF887BC739`](https://sepolia.basescan.org/address/0x7F75bfAfeD5c96584774c7F2Bc33F3bF887BC739)

## How It Works

```
    Transaction ──▶ AnomalyDetector ──▶ CircuitBreaker
         │               │                    │
         │          Score 0-1000         Auto-pause?
         │               │                    │
         │          ┌────┴────┐          ┌────┴────┐
         │          │ Gas     │          │ PAUSE   │
         │          │ Value   │    YES   │ Protocol│
         │          │ Freq    │─────────▶│ OFF     │
         │          │ Reentry │          │         │
         │          └─────────┘          └─────────┘
         │
    ProtocolRegistry ◀── Register protocols to monitor
```

## Detection Strategies

| Anomaly Type | Detection | Weight |
|-------------|-----------|--------|
| **High Gas** | Tx gas > protocol max | 30% |
| **Large Value** | Tx value > protocol max | 35% |
| **High Frequency** | Txs per block > max | 20% |
| **Reentrancy** | Same sender, rapid calls | 15% |

**Threshold**: Total score >= 500/1000 triggers auto-pause.

## Smart Contracts

### `CircuitBreaker.sol` — Main Controller
- Auto-pause on anomaly detection
- Governance manual pause
- Emergency multi-sig pause (2-of-3)
- 30-minute timelock for unpause

### `AnomalyDetector.sol` — Scoring Engine
- Multi-factor anomaly scoring (0-1000)
- Weighted combination of 4 detection strategies
- On-chain transaction history recording

### `ProtocolRegistry.sol` — Protocol Registration
- Register protocols with custom thresholds
- Per-protocol monitoring parameters
- TVL tracking

## Setup

```bash
git clone https://github.com/Souravjoy7/circuit-breaker.git
cd circuit-breaker
npm install
```

## Usage

```bash
npx hardhat compile
npx hardhat run scripts/demo.js
npx hardhat run scripts/deploy.js --network base_sepolia
npx hardhat run scripts/deploy.js --network linea_sepolia
```

## License

MIT
