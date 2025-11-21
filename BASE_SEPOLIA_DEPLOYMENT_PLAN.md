# Base Sepolia Testnet Deployment Plan

> **Configuration Choices:**
> - Pool Manager: **Real Uniswap V4** (Production-ready)
> - USDC: **MockUSDC** (Custom deployment)
> - Testing Scope: **All Phases (1-6)**
> - Frontend: **Local Testing**
> - Timeline: **Full deployment & testing**

---

## Phase 1: Preparation & Setup

### 1.1 Get Testnet Assets
- [ ] Get Base Sepolia ETH from faucet: https://www.alchemy.com/faucets/base-sepolia
- [ ] Alternative faucets:
  - https://docs.base.org/tools/network-faucets/
  - https://www.coinbase.com/faucets/base-ethereum-sepolia-faucet
- [ ] Fund deployer wallet with ~**0.5 ETH** for deployments
- [ ] Verify balance: `cast balance <YOUR_ADDRESS> --rpc-url https://sepolia.base.org`

### 1.2 Environment Setup
Create `.env` file in project root:

```bash
# Deployer Wallet
PRIVATE_KEY=your_private_key_here

# RPC URLs
BASE_SEPOLIA_RPC=https://sepolia.base.org

# Optional: For contract verification
ETHERSCAN_API_KEY=your_basescan_api_key

# Base Sepolia Chain ID: 84532
```

### 1.3 Verify Uniswap V4 Deployment on Base Sepolia
- [ ] Check PoolManager address: `0x05e73354cfdd6745c338b50bcfdfa3aa6fa03408`
- [ ] Verify deployment: https://sepolia.basescan.org/address/0x05e73354cfdd6745c338b50bcfdfa3aa6fa03408
- [ ] Confirm it's the official V4 PoolManager

### 1.4 Install Dependencies
```bash
forge install
cd frontend
npm install
cd ..
```

---

## Phase 2: Hook Address Mining (CREATE2)

> **Why This is Required:**
> Uniswap V4 hooks must be deployed to specific addresses with flag bits matching their permissions.
> For `beforeSwap + afterSwap`, specific bits in the address must be set.

### 2.1 Calculate Required Hook Flags
Our hook needs:
- `beforeSwap = true` (bit 7)
- `afterSwap = true` (bit 8)
- All others = false

This requires the hook address to have specific bits set.

### 2.2 Mine Hook Address
**Option A: Use HookMiner (Recommended)**
```bash
# Clone hook miner tool
git clone https://github.com/uniswapfoundation/v4-template
cd v4-template
forge install

# Mine address with correct flags
# This may take several minutes
forge script script/MineAddress.s.sol --sig "run(uint160)" 0x4000
```

**Option B: Use CREATE2 Factory**
- Deploy using CREATE2 factory with salt mining
- Iterate salts until address matches required flags
- Document the salt used

### 2.3 Record Mined Address
- [ ] Save hook address: `0x____________________`
- [ ] Save CREATE2 salt: `0x____________________`
- [ ] Verify address flags match requirements

---

## Phase 3: Smart Contract Deployment

### 3.1 Create Deployment Script

Create `script/DeployBaseTestnet.s.sol`:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {DobToken} from "../src/DobToken.sol";
import {DobOracle} from "../src/DobOracle.sol";
import {DobNodeLiquidityHook} from "../src/DobNodeLiquidityHook.sol";
import {LiquidNodeStabilizer} from "../src/LiquidNodeStabilizer.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {IDobOracle} from "../src/interfaces/IDobOracle.sol";

contract DeployBaseTestnet is Script {
    // Base Sepolia PoolManager (official V4 deployment)
    address constant POOL_MANAGER = 0x05e73354cfdd6745c338b50bcfdfa3aa6fa03408;

    // Mined hook address (from Phase 2)
    address constant HOOK_ADDRESS = 0x____________________; // TODO: Fill from mining
    bytes32 constant HOOK_SALT = 0x____________________; // TODO: Fill from mining

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Base Sepolia Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID: 84532");
        console.log("PoolManager:", POOL_MANAGER);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy MockUSDC
        MockUSDC usdc = new MockUSDC();
        console.log("1. MockUSDC:", address(usdc));

        // 2. Deploy Oracle
        DobOracle oracle = new DobOracle();
        oracle.update(1e18, 1000); // NAV $1.00, Risk 10%
        console.log("2. Oracle:", address(oracle));

        // 3. Deploy DobToken (with mined hook address)
        DobToken dobToken = new DobToken(HOOK_ADDRESS);
        console.log("3. DobToken:", address(dobToken));

        // 4. Deploy LiquidNodeStabilizer
        LiquidNodeStabilizer liquidNode = new LiquidNodeStabilizer(
            IPoolManager(POOL_MANAGER),
            IDobOracle(address(oracle)),
            Currency.wrap(address(usdc)),
            Currency.wrap(address(dobToken)),
            deployer
        );
        console.log("4. LiquidNodeStabilizer:", address(liquidNode));

        // 5. Deploy Hook using CREATE2 to mined address
        DobNodeLiquidityHook hook = new DobNodeLiquidityHook{salt: HOOK_SALT}(
            IPoolManager(POOL_MANAGER),
            dobToken,
            Currency.wrap(address(usdc)),
            deployer,
            IDobOracle(address(oracle))
        );
        require(address(hook) == HOOK_ADDRESS, "Hook address mismatch");
        console.log("5. Hook:", address(hook));

        // 6. Setup: Fund deployer with test tokens
        uint256 fundingUSDC = 200_000 * 1e6; // 200k USDC
        usdc.mint(deployer, fundingUSDC);

        // 7. Fund Liquid Node
        uint256 lnFundingUSDC = 100_000 * 1e6; // 100k USDC
        usdc.approve(address(liquidNode), lnFundingUSDC);
        liquidNode.fundUSDC(lnFundingUSDC);

        console.log("\n=== Deployment Complete ===");
        console.log("USDC:", address(usdc));
        console.log("Oracle:", address(oracle));
        console.log("DobToken:", address(dobToken));
        console.log("LiquidNode:", address(liquidNode));
        console.log("Hook:", address(hook));
        console.log("\n=== Next Steps ===");
        console.log("1. Initialize pool via PoolManager.initialize()");
        console.log("2. Add initial liquidity");
        console.log("3. Update frontend/src/contracts.ts");
        console.log("4. Verify contracts on BaseScan");

        vm.stopBroadcast();
    }
}
```

### 3.2 Deploy to Base Sepolia

```bash
# Deploy contracts
forge script script/DeployBaseTestnet.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY

# Save output
forge script script/DeployBaseTestnet.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  | tee deployment_output.txt
```

### 3.3 Record Deployed Addresses

Create `TESTNET_ADDRESSES.md`:

```markdown
# Base Sepolia Testnet Deployment

**Chain ID:** 84532
**Deployment Date:** [DATE]
**Deployer:** 0x...

## Contract Addresses

| Contract | Address | BaseScan |
|----------|---------|----------|
| MockUSDC | 0x... | [Link](https://sepolia.basescan.org/address/0x...) |
| DobOracle | 0x... | [Link](https://sepolia.basescan.org/address/0x...) |
| DobToken | 0x... | [Link](https://sepolia.basescan.org/address/0x...) |
| LiquidNodeStabilizer | 0x... | [Link](https://sepolia.basescan.org/address/0x...) |
| DobNodeLiquidityHook | 0x... | [Link](https://sepolia.basescan.org/address/0x...) |
| PoolManager (V4) | 0x05e73354cfdd6745c338b50bcfdfa3aa6fa03408 | [Link](https://sepolia.basescan.org/address/0x05e73354cfdd6745c338b50bcfdfa3aa6fa03408) |

## Configuration

- **Initial NAV:** $1.00 (1e18)
- **Initial Risk:** 10% (1000 bps)
- **Liquid Node Funding:** 100,000 USDC
- **Pool Fee:** 0.3% (3000)
- **Tick Spacing:** 60
```

### 3.4 Verify Contracts
```bash
# Verify each contract manually if auto-verification fails
forge verify-contract \
  --chain-id 84532 \
  --constructor-args $(cast abi-encode "constructor(address)" <HOOK_ADDRESS>) \
  <DOBTOKEN_ADDRESS> \
  src/DobToken.sol:DobToken \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

---

## Phase 4: Pool Initialization & Liquidity

### 4.1 Initialize Pool

Create `script/InitializePool.s.sol`:

```solidity
// Initialize the DOB/USDC pool with 1:1 price
// Add initial liquidity (100k USDC + 100k DOB)
```

### 4.2 Execute Pool Setup
```bash
forge script script/InitializePool.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### 4.3 Verify Pool State
```bash
# Check pool liquidity
cast call <POOL_MANAGER> "getLiquidity(bytes32)" <POOL_ID> \
  --rpc-url $BASE_SEPOLIA_RPC

# Check pool price
cast call <POOL_MANAGER> "getSlot0(bytes32)" <POOL_ID> \
  --rpc-url $BASE_SEPOLIA_RPC
```

---

## Phase 5: On-Chain Testing

### 5.1 Basic Functionality Tests

#### Test 1: Oracle Reading
```bash
# Read NAV
cast call <ORACLE_ADDRESS> "nav()" --rpc-url $BASE_SEPOLIA_RPC

# Read Risk
cast call <ORACLE_ADDRESS> "defaultRisk()" --rpc-url $BASE_SEPOLIA_RPC
```

#### Test 2: Token Balances
```bash
# Check deployer USDC balance
cast call <USDC_ADDRESS> "balanceOf(address)" <DEPLOYER> \
  --rpc-url $BASE_SEPOLIA_RPC

# Check Liquid Node USDC balance
cast call <USDC_ADDRESS> "balanceOf(address)" <LIQUIDNODE_ADDRESS> \
  --rpc-url $BASE_SEPOLIA_RPC
```

#### Test 3: Small Swap (No Stabilization)
```bash
# Approve USDC
cast send <USDC_ADDRESS> "approve(address,uint256)" <POOL_MANAGER> 1000000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC

# Execute swap: 1000 USDC → DOB
# (Use PoolManager.swap() with proper params)
```

**Expected Result:**
- ✅ Swap executes successfully
- ✅ DOB tokens received
- ✅ No stabilization triggered (< 5% deviation)
- ✅ Transaction on BaseScan

### 5.2 Price Stabilization Tests

#### Test 4: Large Sell (Triggers Stabilization - Buy)
```bash
# Execute large swap: 30,000 DOB → USDC
# Should drop price below -5% threshold
# Liquid Node should buy DOB
```

**Expected Result:**
- ✅ Price drops significantly
- ✅ Stabilization triggered
- ✅ Liquid Node DOB balance increases
- ✅ Fees accumulated in Liquid Node

#### Test 5: Large Buy (Triggers Stabilization - Sell)
```bash
# Execute large swap: 30,000 USDC → DOB
# Should raise price above +5% threshold
# Liquid Node should sell DOB
```

**Expected Result:**
- ✅ Price rises significantly
- ✅ Stabilization triggered
- ✅ Liquid Node DOB balance decreases
- ✅ Fees accumulated in Liquid Node

### 5.3 Oracle Integration Tests

#### Test 6: NAV Increase
```bash
# Update oracle NAV to $1.10
cast send <ORACLE_ADDRESS> "update(uint256,uint256)" 1100000000000000000 700 \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC

# Execute small swap
# Should trigger stabilization (pool price now < NAV)
```

#### Test 7: NAV Decrease
```bash
# Update oracle NAV to $0.90
cast send <ORACLE_ADDRESS> "update(uint256,uint256)" 900000000000000000 3500 \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC

# Execute small swap
# Should trigger stabilization (pool price now > NAV)
```

### 5.4 Run Full Simulation Script

Create `script/TestnetSimulation.s.sol` (adapted from SimulateStabilization.s.sol):

```bash
forge script script/TestnetSimulation.s.sol \
  --rpc-url $BASE_SEPOLIA_RPC \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --gas-limit 30000000
```

**Scenarios to Test:**
1. ✅ Small swap (no stabilization)
2. ✅ Large DOB sale (price drop, LN buys)
3. ✅ Large DOB buy (price rise, LN sells)
4. ✅ Oracle NAV increase to $1.10
5. ✅ Swap after NAV change
6. ✅ Oracle NAV decrease to $0.90
7. ✅ Swap after NAV drop
8. ✅ Multiple rapid swaps

**Expected Outcome:**
- Liquid Node fees accumulate to ~21,000 USDC
- All stabilizations trigger correctly
- Pool price stays within 5% of NAV

---

## Phase 6: Frontend Integration

### 6.1 Update Frontend Configuration

Edit `frontend/src/contracts.ts`:

```typescript
export const CONTRACTS = {
  usdc: '0x...', // From deployment
  oracle: '0x...', // From deployment
  dobToken: '0x...', // From deployment
  poolManager: '0x05e73354cfdd6745c338b50bcfdfa3aa6fa03408', // V4 PoolManager
  liquidNode: '0x...', // From deployment
  hook: '0x...', // From deployment
} as const;

export const CHAIN_CONFIG = {
  chainId: 84532,
  name: 'Base Sepolia',
  rpcUrl: 'https://sepolia.base.org',
  blockExplorer: 'https://sepolia.basescan.org',
} as const;
```

Verify `frontend/src/wagmi.ts` includes Base Sepolia:

```typescript
import { baseSepolia } from 'wagmi/chains';

export const config = getDefaultConfig({
  appName: 'DOB Solar Farm 2035',
  projectId: 'YOUR_WALLETCONNECT_PROJECT_ID',
  chains: [baseSepolia], // Base Sepolia enabled
  transports: {
    [baseSepolia.id]: http(),
  },
});
```

### 6.2 Start Frontend Locally

```bash
cd frontend
npm run dev
```

Open http://localhost:5173

### 6.3 Frontend Testing Checklist

#### Connect Wallet
- [ ] Connect MetaMask to Base Sepolia
- [ ] Verify network: Chain ID 84532
- [ ] Import deployer account (or create test account)
- [ ] Fund test account with Base Sepolia ETH

#### Stats Display
- [ ] NAV displays: $1.00
- [ ] Risk displays: 10%
- [ ] Balance shows: 0 DOB
- [ ] All values update correctly

#### Get Test USDC
- [ ] Click "Get Test USDC" button (if implemented)
- [ ] Or manually call: `usdc.mint(YOUR_ADDRESS, 10000 * 1e6)`
- [ ] Verify USDC balance updates

#### Small Swap Test
- [ ] Input: 1000 USDC
- [ ] Preview shows: ~1000 DOB (minus fees)
- [ ] Execute swap
- [ ] Verify transaction on BaseScan
- [ ] Verify DOB balance updates
- [ ] Verify NO stabilization occurred

#### Large Swap Test (Stabilization)
- [ ] Input: 30,000 USDC → DOB
- [ ] Execute swap
- [ ] Observe price change
- [ ] Verify stabilization event on BaseScan
- [ ] Check Liquid Node balance changed
- [ ] Verify fees accumulated

#### Oracle Update Test
- [ ] Use demo panel "Revenue" preset (NAV $1.15, Risk 7%)
- [ ] Execute small swap
- [ ] Verify stabilization triggered
- [ ] Check updated NAV in UI

#### Sell Test
- [ ] Input: 5,000 DOB
- [ ] Preview shows USDC output (with penalty)
- [ ] Execute swap
- [ ] Verify penalty applied correctly
- [ ] Check transaction on BaseScan

---

## Phase 7: Edge Cases & Stress Testing

### 7.1 Edge Case Tests

#### Test A: Zero Liquidity Behavior
```bash
# Remove all liquidity from pool
# Attempt swap
# Expected: Graceful failure with clear error
```

#### Test B: Oracle NAV = 0
```bash
# Update oracle NAV to 0
cast send <ORACLE_ADDRESS> "update(uint256,uint256)" 0 5000 \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC

# Attempt swap
# Expected: Should handle safely or revert cleanly
```

#### Test C: Maximum Deviation (99% drop)
```bash
# Update oracle NAV to $0.01
# Execute swap
# Expected: Stabilization with max intervention
```

#### Test D: Liquid Node Depleted
```bash
# Drain Liquid Node funds
# Trigger large swap requiring stabilization
# Expected: Graceful degradation (stabilization skipped or partial)
```

#### Test E: Multiple Rapid Swaps
```bash
# Execute 5 swaps in quick succession
# Expected: All process correctly, stabilization triggers as needed
```

### 7.2 Gas Cost Analysis

Measure gas for each operation:

```bash
# Normal swap (no stabilization)
# Expected: ~100-150k gas

# Swap with stabilization
# Expected: ~300-400k gas

# Oracle update
# Expected: ~50k gas

# Add liquidity
# Expected: ~200k gas
```

Create `GAS_COSTS.md`:

| Operation | Gas Used | Cost (at 1 gwei) |
|-----------|----------|------------------|
| Small swap (no stab) | ~100k | ~0.0001 ETH |
| Large swap (with stab) | ~350k | ~0.00035 ETH |
| Oracle update | ~50k | ~0.00005 ETH |
| Add liquidity | ~200k | ~0.0002 ETH |

### 7.3 Multi-User Scenario

```bash
# Create 3 test accounts
# Account A: Deployer
# Account B: User 1 (gets USDC from deployer)
# Account C: User 2 (gets USDC from deployer)

# Transfer USDC to B and C
cast send <USDC_ADDRESS> "transfer(address,uint256)" <USER_B> 50000000000 \
  --private-key $PRIVATE_KEY \
  --rpc-url $BASE_SEPOLIA_RPC

# User B swaps and triggers stabilization
# User C swaps during high deviation
# Verify all interactions work correctly
```

---

## Phase 8: Documentation & Reporting

### 8.1 Create Test Results Document

Create `TESTNET_RESULTS.md`:

```markdown
# Base Sepolia Testnet Results

## Deployment Summary
- **Date:** [DATE]
- **Chain:** Base Sepolia (84532)
- **Total Gas Used:** ~X ETH
- **Contracts Deployed:** 5
- **Tests Executed:** 12

## Test Results

### ✅ Passed Tests
1. Oracle reading and updates
2. Small swap (no stabilization)
3. Large swap triggering stabilization
4. NAV increase scenario
5. NAV decrease scenario
6. Multi-user interactions
7. Frontend integration
8. Gas cost analysis

### ⚠️ Issues Encountered
- [Document any issues]
- [Workarounds applied]

### 📊 Performance Metrics
- Average swap gas: ~X
- Stabilization gas: ~X
- Success rate: 100%

## Key Transactions
- Initial deployment: [BaseScan link]
- First swap: [BaseScan link]
- First stabilization: [BaseScan link]
- Oracle update: [BaseScan link]

## Screenshots
- [Include screenshots of BaseScan transactions]
- [Frontend UI screenshots]
```

### 8.2 Create Video Demo (Optional)

**Recording Checklist:**
- [ ] Frontend connected to Base Sepolia
- [ ] Execute swap with voiceover
- [ ] Show stabilization event
- [ ] Open BaseScan to show transaction
- [ ] Display Liquid Node balance changes
- [ ] Show oracle update and effect

**Tools:**
- OBS Studio (screen recording)
- Loom (quick web recording)

### 8.3 Final Checklist

#### Contracts
- [ ] All contracts deployed to Base Sepolia
- [ ] All contracts verified on BaseScan
- [ ] All addresses documented in TESTNET_ADDRESSES.md

#### Testing
- [ ] Basic functionality tested (5 tests)
- [ ] Stabilization tested (3 scenarios)
- [ ] Oracle integration tested (2 scenarios)
- [ ] Full simulation executed
- [ ] Edge cases tested (5 scenarios)
- [ ] Gas costs measured
- [ ] Multi-user scenarios tested

#### Frontend
- [ ] Configuration updated
- [ ] Local testing completed
- [ ] All UI components work
- [ ] Wallet connection works
- [ ] Transactions execute successfully

#### Documentation
- [ ] TESTNET_ADDRESSES.md created
- [ ] TESTNET_RESULTS.md created
- [ ] GAS_COSTS.md created
- [ ] Screenshots collected
- [ ] Issues documented

---

## Phase 9: Next Steps (Production Preparation)

### 9.1 Security Audit Preparation
- [ ] Run Slither static analysis
- [ ] Run Mythril symbolic execution
- [ ] Document known issues
- [ ] Prepare audit scope document

### 9.2 Mainnet Deployment Checklist
- [ ] Use real USDC (0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
- [ ] Use Base mainnet PoolManager
- [ ] Mine new hook address for mainnet
- [ ] Multi-sig for oracle updater
- [ ] Time-locks for critical functions
- [ ] Emergency pause mechanism
- [ ] Insurance fund for Liquid Node

### 9.3 Monitoring & Operations
- [ ] Set up Tenderly monitoring
- [ ] Configure alerts for:
  - Large swaps
  - High deviation events
  - Liquid Node balance low
  - Oracle update failures
- [ ] Create operator runbook

---

## Troubleshooting

### Common Issues

#### Issue: Hook address validation fails
**Solution:** Ensure CREATE2 salt produces address with correct flag bits

#### Issue: Pool initialization fails
**Solution:** Check token ordering (token0 < token1), fee tier, and tick spacing

#### Issue: Stabilization doesn't trigger
**Solution:** Verify deviation threshold, check Liquid Node has funds

#### Issue: Frontend can't connect
**Solution:** Verify Base Sepolia in MetaMask, check RPC URL, confirm chain ID 84532

#### Issue: Transaction reverts
**Solution:** Check gas limit, verify token approvals, review revert reason on BaseScan

---

## Resources

### Base Sepolia
- Faucet: https://www.alchemy.com/faucets/base-sepolia
- Block Explorer: https://sepolia.basescan.org
- Chain ID: 84532
- RPC: https://sepolia.base.org

### Uniswap V4
- Docs: https://docs.uniswap.org/contracts/v4/overview
- PoolManager: 0x05e73354cfdd6745c338b50bcfdfa3aa6fa03408
- Hook Mining: https://github.com/uniswapfoundation/v4-template

### Tools
- Foundry: https://book.getfoundry.sh/
- Cast CLI: https://book.getfoundry.sh/cast/
- Tenderly: https://tenderly.co/
- Rainbow Kit: https://www.rainbowkit.com/

---

## Timeline Estimate

| Phase | Estimated Time | Notes |
|-------|----------------|-------|
| Phase 1: Setup | 30 min | Faucet, env config |
| Phase 2: Hook Mining | 1-2 hours | Depends on luck |
| Phase 3: Deployment | 30 min | Contract deployment |
| Phase 4: Pool Setup | 30 min | Initialize & add liquidity |
| Phase 5: On-Chain Tests | 1 hour | 8 test scenarios |
| Phase 6: Frontend | 1 hour | Integration & testing |
| Phase 7: Edge Cases | 1 hour | Stress testing |
| Phase 8: Documentation | 30 min | Write results |
| **Total** | **~6-7 hours** | Full comprehensive testing |

---

**Ready to start? Let's begin with Phase 1! 🚀**
