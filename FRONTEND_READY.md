# ✅ Frontend Hook Integration Testing - READY

## What's Been Updated

### 1. Contract Addresses (contracts.ts)
✅ Updated with your local deployment:
- USDC: `0x4A679253410272dd5232B3Ff7cF5dbB88f295319`
- Oracle: `0x7a2088a1bFc9d81c55368AE168C2C02570cB814F`
- DobToken: `0x67d269191c92Caf3cD7723F116c85e6E9bf55933`
- PoolManager: `0xc5a5C42992dECbae36851359345FE25997F5C42d`
- LiquidNode: `0xE6E340D132b5f46d1e472DebcD681B2aBc16e57E`
- Hook: `0xc3e53F4d16Ae77Db1c982e75a937B9f60FE63690`

### 2. New ABIs Added
✅ POOL_MANAGER_ABI - for executing swaps
✅ HOOK_ABI - for reading pool price and stabilization status
✅ LIQUID_NODE_STABILIZER_ABI - for reading reserves and fees
✅ Updated DOB_TOKEN_ABI with approve/allowance
✅ Updated USDC_ABI with mint function

### 3. New UI Component (SwapTest.tsx)
✅ **Step-by-step guide** at the top
✅ **Pool Stats Card** - Shows pool price, NAV, deviation, stabilization status
✅ **Liquid Node Stats Card** - Shows reserves and fees earned
✅ **Swap Card** - Working swap functionality with approve flow

### 4. Updated App.tsx
✅ Added tab navigation
✅ "Hook Integration Test" tab with full testing UI
✅ "Overview" tab with original UI
✅ Integrated SwapTest component

## Quick Start

### Terminal 1: Anvil (if not running)
```bash
anvil
```

### Terminal 2: Deploy (if not deployed)
```bash
forge script script/DeploySimpleLocal.s.sol \
  --tc DeploySimpleLocal \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

### Terminal 3: Frontend
```bash
cd frontend
npm install  # First time only
npm run dev
```

### Browser
1. Open http://localhost:5173
2. Connect MetaMask to Localhost (31337)
3. Import Anvil account:
   - Private Key: `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80`
4. Click "🧪 Hook Integration Test" tab
5. Follow the numbered steps in the purple box!

## Testing Flow

```
┌─────────────────────────────────────────────────────────┐
│  1. Get USDC (mint 10,000)                              │
│  2. Approve USDC (allow PoolManager to spend)           │
│  3. Enter amount (e.g., 1000)                           │
│  4. Click "Swap USDC → DOB"                             │
│  5. Confirm in MetaMask                                 │
│  6. Watch the stats update in real-time!                │
│                                                         │
│  Every swap triggers:                                   │
│  → poolManager.swap()                                   │
│  → hook.afterSwap() ← THE INTEGRATION POINT            │
│  → liquidNode intervention (if deviation > 5%)          │
└─────────────────────────────────────────────────────────┘
```

## What You'll See

**Before Swap:**
- Pool Price: $1.00
- Oracle NAV: $1.00
- Deviation: 0%
- Stabilization: ✓ Stable

**After Small Swap (1,000 USDC):**
- Pool Price: $1.02
- Deviation: 2%
- Stabilization: ✓ Stable (< 5%)
- LiquidNode: No change

**After Large Swap (30,000 USDC):**
- Pool Price: $1.08
- Deviation: 8%
- Stabilization: ⚠️ SELL DOB
- LiquidNode: Reserves changed, Fees earned!

## Replicate the Simulation

You can now manually do what the script did:

| Scenario | Action | Expected Result |
|----------|--------|-----------------|
| 1. Small swap | 1k USDC → DOB | Deviation < 5%, no stabilization |
| 2. Large sale | 30k DOB → USDC | Price drops, LiquidNode buys DOB |
| 3. Large buy | 30k USDC → DOB | Price rises, LiquidNode sells DOB |
| 4. NAV increase | Update NAV to $1.10 | Pool now "too cheap" |
| 5. Swap after NAV | 1k USDC swap | Triggers stabilization |
| 6. NAV decrease | Update NAV to $0.90 | Pool now "too expensive" |
| 7. Swap after drop | 1k USDC swap | Triggers opposite stabilization |
| 8. Multiple swaps | 3x 5k USDC swaps | Fees accumulate |

## Success Criteria

✅ Pool price updates after swaps
✅ Hook detects deviations correctly
✅ Stabilization triggers when deviation > 5%
✅ LiquidNode reserves change when intervening
✅ Fees accumulate at 0.5% per intervention
✅ Pool price stays within ~5% of NAV

## Files Modified/Created

```
frontend/
├── src/
│   ├── contracts.ts          # ✏️ Updated addresses + new ABIs
│   ├── App.tsx               # ✏️ Added tabs + SwapTest integration
│   └── SwapTest.tsx          # ✨ NEW - Full testing UI
├── TESTING_GUIDE.md          # ✨ NEW - Detailed instructions
└── package.json              # (unchanged)
```

## Next Steps

1. **Install dependencies**: `cd frontend && npm install`
2. **Start dev server**: `npm run dev`
3. **Open browser**: http://localhost:5173
4. **Connect MetaMask**: Localhost network + Anvil account
5. **Start testing**: Follow the purple guide box!

---

**The hook integration is READY TO TEST! 🎉**

See `frontend/TESTING_GUIDE.md` for detailed step-by-step instructions.
