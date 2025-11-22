# Frontend Hook Integration Testing Guide

## Prerequisites

1. **Anvil must be running** on `localhost:8545`
2. **Contracts must be deployed** (run `DeploySimpleLocal.s.sol`)
3. **MetaMask** with Anvil test account

## Setup

### 1. Install Dependencies

```bash
cd frontend
npm install
```

### 2. Start Dev Server

```bash
npm run dev
```

Open http://localhost:5173

### 3. Configure MetaMask

**Add Localhost Network:**
- Network Name: Anvil Local
- RPC URL: http://127.0.0.1:8545
- Chain ID: 31337
- Currency: ETH

**Import Anvil Test Account:**
- Private Key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
- This account has ETH and is the deployer

## Testing the Hook Integration

### Step 1: Get USDC
1. Click "Get USDC" button
2. Confirm transaction in MetaMask
3. Wait for confirmation
4. You should see USDC balance update to 10,000

### Step 2: Approve Tokens
1. Enter an amount (e.g., 1000)
2. Click "Approve USDC" (for buying) or "Approve DOB" (for selling)
3. Confirm in MetaMask
4. Wait for confirmation

### Step 3: Execute Swap
1. Enter swap amount
2. Click "Swap USDC → DOB" or "Swap DOB → USDC"
3. Confirm in MetaMask
4. **This triggers the hook's afterSwap()!**

### Step 4: Watch the Magic Happen

**What you'll see:**
- **Pool Price** updates based on the swap
- **Deviation** shows how far from NAV
- **If deviation > 5%**:
  - Stabilization status shows "⚠️ BUY DOB" or "SELL DOB"
  - LiquidNode reserves change (it intervened!)
  - Fees Earned increases by 0.5% of intervention

### Step 5: Test Scenarios

Use the Demo Controls at the bottom to replicate the simulation scenarios:

**Scenario 1: Small Swap (No Stabilization)**
- Swap 1,000 USDC → DOB
- Deviation should be < 5%
- No stabilization triggered

**Scenario 2: Large Swap (Triggers Stabilization)**
- Swap 30,000 USDC → DOB (you need to mint more USDC first)
- Pool price will change significantly
- Hook detects deviation > 5%
- LiquidNode automatically intervenes!

**Scenario 3: Oracle NAV Change**
1. Click "Revenue" preset (NAV $1.15)
2. Click "Update Oracle"
3. Now do a small swap
4. Even small swap triggers stabilization because pool price is now far from new NAV!

**Scenario 4: Multiple Rapid Swaps**
- Do several swaps in succession
- Watch fees accumulate
- See LiquidNode reserves change with each intervention

## What's Happening Under the Hood

Every time you click "Swap":

```
1. Your transaction calls poolManager.swap(poolKey, params, "0x")
2. PoolManager executes the AMM logic (constant product)
3. PoolManager calls hook.afterSwap() ← THE KEY INTEGRATION!
4. Hook reads pool price from reserves
5. Hook reads oracle NAV
6. Hook calculates deviation
7. IF deviation > 5%:
   → Hook calls liquidNode.stabilizeLow() or stabilizeHigh()
   → LiquidNode executes a counter-swap
   → LiquidNode earns 0.5% fee
   → Pool price moves back toward NAV
```

## Troubleshooting

**"Approve" button doesn't appear**
- Make sure you've entered an amount
- Refresh the page to reload contract state

**"Transaction reverted"**
- Check you have enough tokens
- Make sure you approved first
- Check Anvil is still running

**Stats not updating**
- Refresh the page
- Check MetaMask is connected to Localhost (31337)
- Verify contracts are deployed

**No stabilization happening**
- Deviation must be > 5%
- Try larger swaps (20k-30k)
- Or update oracle NAV to create deviation

## Expected Results

After testing, you should see:

- ✅ Pool price changes with swaps
- ✅ Hook detects deviations
- ✅ LiquidNode intervenes when needed
- ✅ Fees accumulate (0.5% per intervention)
- ✅ Pool stays within ~5% of oracle NAV

## Manual Simulation Replication

To replicate the script simulation manually:

1. **Get 100k USDC** (click "Get USDC" 10 times)
2. **Small swap**: 1,000 USDC → Check deviation < 5%
3. **Large sale**: 30,000 DOB → Watch price drop & stabilization
4. **Large buy**: 30,000 USDC → Watch price rise & stabilization
5. **NAV increase**: Set NAV to $1.10 → Swap 1k → Stabilization triggers
6. **NAV decrease**: Set NAV to $0.90 → Swap 1k → Stabilization triggers
7. **Multiple swaps**: Do 3x 5,000 USDC swaps → Watch fees accumulate

Compare your results with the simulation output!
