# DobNodeLiquidity

A Uniswap V4 hook system for tokenized Real World Assets (RWA) that creates an infinite primary market with protected secondary market liquidity.

## Overview

DobNodeLiquidity enables tokenization of revenue-generating assets (e.g., solar farms) with:

- **Primary Market**: Mint tokens at oracle NAV (99% to operator, 1% fee)
- **Secondary Market**: Redeem tokens at NAV minus dynamic penalty based on default risk
- **Liquid Nodes**: Permissionless liquidity providers offering instant redemption at competitive rates
- **Price Stabilization**: Automatic intervention when pool price deviates >5% from oracle NAV

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   DobOracle │◄────│   V4 Hook   │────►│  DobToken   │
│  (NAV/Risk) │     │  (Primary)  │     │   (ERC20)   │
└─────────────┘     └──────┬──────┘     └─────────────┘
                          │
                          ▼
                   ┌─────────────┐
                   │ LiquidNode  │
                   │ (Secondary) │
                   └─────────────┘
```

## How It Works

### Buying DOB Tokens (Primary Market)

1. User sends USDC to the hook
2. Hook reads current NAV from oracle
3. 99% goes to operator, 1% fee
4. DOB tokens minted to user at NAV rate

```
DOB received = (USDC × 0.99) / NAV
```

### Selling DOB Tokens (Secondary Market)

1. User sends DOB tokens to redeem
2. Hook calculates dynamic penalty based on default risk:
   - Base penalty: 3%
   - Risk adjustment: +risk/1000
   - Maximum: 50%
3. USDC returned minus penalty

```
Penalty BPS = min(300 + defaultRisk/10, 5000)
USDC received = DOB × NAV × (1 - penalty)
```

### Liquid Nodes (Instant Liquidity)

For large redemptions, Liquid Nodes compete to provide instant liquidity:

1. LiquidNode queries oracle for current conditions
2. Calculates fee based on risk tier:
   - Low risk (<15%): 5% fee
   - Medium risk (<30%): 10% fee
   - High risk (≥30%): 20% fee
3. User can choose best offer from competing nodes

### Price Stabilization System

The system includes automatic price stabilization to maintain DOB pool prices close to oracle NAV:

**How It Works:**
1. After every swap, the hook compares pool price to oracle NAV
2. If deviation exceeds 5%, the Liquid Node Stabilizer intervenes
3. **Price too low** → Liquid Node buys DOB to support price
4. **Price too high** → Liquid Node sells DOB to cap price
5. Intervention amount is proportional to deviation size
6. 0.5% fee collected on each intervention

**Benefits:**
- Prevents excessive price manipulation
- Protects users from large deviations
- Generates revenue for the Liquid Node
- Maintains market confidence

## Smart Contracts

| Contract | Description |
|----------|-------------|
| `DobOracle.sol` | Push oracle storing NAV and default risk |
| `DobToken.sol` | ERC20 with hook-only mint/burn |
| `DobNodeLiquidityHook.sol` | Uniswap V4 hook for primary market |
| `DobNodeLiquidityHookLocal.sol` | Local testing version (bypasses V4 address validation) |
| `LiquidNodeStabilizer.sol` | Automatic price stabilization mechanism |
| `LiquidNodeExample.sol` | Permissionless liquidity provider |
| `MockPoolManagerLocal.sol` | Simplified pool manager for local testing |

### Key Functions

**DobOracle**
```solidity
function nav() external view returns (uint256);           // Current NAV (18 decimals)
function defaultRisk() external view returns (uint256);   // Risk in basis points
function update(uint256 _nav, uint256 _risk) external;    // Update values
```

**DobToken**
```solidity
function mint(address to, uint256 amount) external;       // Hook only
function burnFrom(address from, uint256 amount) external; // Hook only
```

**LiquidNodeExample**
```solidity
function quoteFromOracle(uint256 rwaAmount) external view
    returns (uint256 usdcProvided, uint256 feeBps);
```

## Prerequisites

- [Foundry](https://getfoundry.sh/)
- [Node.js](https://nodejs.org/) (v18+)
- [Anvil](https://book.getfoundry.sh/anvil/) (comes with Foundry)

## Installation

```bash
# Clone and enter project
cd dob-node-liquidity

# Install Foundry dependencies
forge install

# Install frontend dependencies
cd frontend
npm install
cd ..
```

## Running Tests

```bash
# Unit tests
forge test

# With verbosity
forge test -vvv

# Specific test
forge test --match-test testBuyCalculation -vvv
```

### Test Coverage

- **18 unit tests**: Oracle, Token, LiquidNode, Redemption calculations
- **3 E2E tests**: Complete investment lifecycle with multiple investors
- **7 stabilization tests**: Price stabilization mechanism verification

## Running Price Stabilization Simulation

The simulation demonstrates the automatic price stabilization system through 8 scenarios:

### 1. Start Anvil (if not already running)

```bash
# Terminal 1
anvil
```

### 2. Deploy the System

```bash
# Terminal 2
forge script script/DeploySimpleLocal.s.sol \
  --tc DeploySimpleLocal \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

### 3. Run the Simulation

```bash
forge script script/SimulateStabilization.s.sol \
  --tc SimulateStabilization \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast \
  --gas-limit 30000000
```

**What the simulation shows:**

1. **Small Swap** - No stabilization (deviation < 5%)
2. **Large DOB Sale** - Price drops, Liquid Node buys DOB
3. **Large DOB Buy** - Price rises, Liquid Node sells DOB
4. **Oracle NAV Increase** - NAV changes to $1.10
5. **Swap After NAV Change** - Triggers stabilization
6. **Oracle NAV Decrease** - NAV drops to $0.90
7. **Swap After NAV Drop** - Stabilization intervention
8. **Multiple Rapid Swaps** - Multiple interventions with fee accumulation

**Expected output:**
- Pool reserves and prices after each scenario
- Liquid Node balance changes
- Fees collected (starts at 0, accumulates to ~21,000 USDC)
- Stabilization triggers when deviation > 5%

## Cleaning Build Artifacts

To clean all build artifacts and start fresh:

```bash
# Clean Foundry artifacts
forge clean

# Clean frontend build
cd frontend
rm -rf node_modules dist
npm install
cd ..

# Clean all (nuclear option)
rm -rf out cache broadcast frontend/node_modules frontend/dist
forge install
cd frontend && npm install && cd ..
```

## Local Development

### 1. Start Local Blockchain

```bash
# Terminal 1
anvil
```

### 2. Deploy Contracts

```bash
# Terminal 2
forge script script/DeployDob.s.sol \
  --tc DeployDobLocal \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

Save the deployed addresses from the output.

### 3. Update Frontend Config

Edit `frontend/src/contracts.ts` with deployed addresses:

```typescript
export const CONTRACTS = {
  oracle: '0x...deployed_oracle_address...',
  dobToken: '0x...deployed_token_address...',
  liquidNode: '0x...deployed_liquidnode_address...',
} as const;
```

### 4. Start Frontend

```bash
cd frontend
npm run dev
```

Open http://localhost:5173 in your browser.

### 5. Connect Wallet

Import an Anvil test account into MetaMask:

- Private Key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
- Network: Localhost 8545 (Chain ID: 31337)

## Frontend Features

### Stats Bar
- **NAV**: Current Net Asset Value with % change
- **Risk**: Default risk percentage with severity indicator
- **Balance**: Your DOB holdings and USD value

### Buy Card
- Input USDC amount
- Shows DOB tokens to receive
- Displays operator allocation

### Sell Card
- Input DOB amount (with Max button)
- Shows USDC to receive
- Displays current penalty rate

### Demo Panel
Oracle controls with preset scenarios:
- **Launch**: NAV $1.00, Risk 10%
- **Revenue**: NAV $1.15, Risk 7%
- **Stress**: NAV $0.85, Risk 35%
- **Recovery**: NAV $1.30, Risk 4%

## Project Structure

```
dob-node-liquidity/
├── src/
│   ├── interfaces/
│   │   └── IDobOracle.sol
│   ├── mocks/
│   │   └── MockPoolManagerLocal.sol
│   ├── DobOracle.sol
│   ├── DobToken.sol
│   ├── MockUSDC.sol
│   ├── DobNodeLiquidityHook.sol
│   ├── DobNodeLiquidityHookLocal.sol     # Local testing hook
│   ├── LocalBaseHook.sol                 # Base for local hooks
│   ├── LiquidNodeStabilizer.sol          # Price stabilization
│   └── LiquidNodeExample.sol
├── test/
│   ├── DobNodeLiquidity.t.sol            # Unit tests
│   ├── DobNodeLiquidity.e2e.t.sol        # E2E tests
│   ├── LiquidNodeStabilizer.t.sol        # Stabilizer tests
│   └── StabilizationE2E.t.sol            # Stabilization E2E
├── script/
│   ├── DeployDob.s.sol                   # Production deploy
│   ├── DeploySimpleLocal.s.sol           # Local deploy with stabilization
│   └── SimulateStabilization.s.sol       # Simulation script
├── frontend/
│   ├── src/
│   │   ├── App.tsx
│   │   ├── main.tsx
│   │   ├── wagmi.ts
│   │   ├── contracts.ts
│   │   └── index.css
│   ├── package.json
│   └── vite.config.ts
├── foundry.toml
└── README.md
```

## Configuration

### foundry.toml

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.26"
evm_version = "cancun"
via_ir = true
optimizer = true
optimizer_runs = 200
```

### Wagmi Config

The frontend supports:
- Localhost (Anvil)
- Base Sepolia (testnet)
- Base (mainnet)

Update `frontend/src/wagmi.ts` with your WalletConnect project ID for production.

## Investment Lifecycle Example

The E2E test demonstrates a complete scenario:

1. **Launch** - NAV $1.00, Risk 10%
2. **Initial Investment** - Alice invests $10,000 → receives 9,900 DOB
3. **Revenue Period** - NAV rises to $1.15, risk drops to 7%
4. **New Investor** - Bob invests $5,000
5. **Profit Taking** - Alice sells 2,000 DOB at profit
6. **Market Crash** - NAV drops to $0.85, risk spikes to 35%
7. **Emergency Exit** - Bob panic sells at high penalty
8. **Recovery** - NAV recovers to $1.30, risk drops to 4%
9. **Final Exits** - Remaining holders exit with gains

## Production Deployment

For mainnet deployment:

1. Set `PRIVATE_KEY` environment variable
2. Use `DeployDob` contract (not `DeployDobLocal`)
3. Mine correct hook address with CREATE2 for V4 permissions
4. Update oracle updater address
5. Configure real USDC and PoolManager addresses

```bash
export PRIVATE_KEY=your_private_key
forge script script/DeployDob.s.sol \
  --tc DeployDob \
  --rpc-url https://mainnet.base.org \
  --broadcast \
  --verify
```

## Stabilization System Configuration

The price stabilization system uses these parameters:

| Parameter | Value | Description |
|-----------|-------|-------------|
| Deviation Threshold | 5% (500 bps) | Triggers stabilization when exceeded |
| Intervention Fee | 0.5% (50 bps) | Fee collected by Liquid Node on interventions |
| Intervention Size | Proportional | `(balance × deviation) / (BPS × 10)` |
| Pool Fee | 0.3% (30 bps) | Standard Uniswap V4 pool fee |
| Direction | Bidirectional | Both buying and selling DOB |

**Example Stabilization:**
- Pool price: $0.92, NAV: $1.00 (8% deviation)
- Liquid Node has 50,000 USDC
- Intervention: `(50,000 × 800) / (10,000 × 10)` = 400 USDC
- Fee: `400 × 0.005` = 2 USDC
- Net intervention: 398 USDC used to buy DOB

## Security Considerations

- Oracle updater is trusted (single point of control)
- Hook has exclusive mint/burn permissions
- Penalty caps at 50% to prevent total loss
- LiquidNodes are permissionless but competitive
- Stabilization mechanism can be drained if NAV diverges significantly from market
- LocalBaseHook bypasses V4 address validation (for local testing only)

## License

MIT
