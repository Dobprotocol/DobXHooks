import { useState, useEffect } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { formatUnits, parseUnits } from 'viem';
import {
  CONTRACTS,
  POOL_MANAGER_ABI,
  HOOK_ABI,
  LIQUID_NODE_STABILIZER_ABI,
  USDC_ABI,
  DOB_TOKEN_ABI,
  ORACLE_ABI,
} from './contracts';

export function SwapTestPanel() {
  return (
    <div className="space-y-6">
      {/* Demo Mode Banner */}
      <div className="bg-gradient-to-r from-yellow-600 to-orange-600 rounded-lg p-4 border-2 border-yellow-400 shadow-lg">
        <div className="flex items-center gap-3">
          <span className="text-3xl">🎯</span>
          <div>
            <h3 className="text-xl font-bold text-white">DEMO MODE - Enhanced Parameters</h3>
            <p className="text-yellow-100 text-sm mt-1">
              Automatic stabilization: <span className="font-bold">ENABLED</span> (max 1 nested call) •
              Stabilization Threshold: <span className="font-bold">5%</span> •
              Intervention Size: <span className="font-bold">50% of reserves</span> (production: calculated)
            </p>
            <p className="text-yellow-200 text-xs mt-1 font-semibold">
              ⚡ Large swaps (6K+ USDC) will automatically trigger stabilization
            </p>
          </div>
        </div>
      </div>

      {/* Step-by-step Instructions */}
      <div className="bg-gradient-to-r from-purple-900 to-blue-900 rounded-lg p-6 border-2 border-purple-500">
        <h2 className="text-2xl font-bold mb-4 text-purple-200">🧪 Hook Integration Testing Guide</h2>
        <div className="space-y-3 text-sm">
          <div className="flex items-start gap-3">
            <div className="bg-purple-600 rounded-full w-8 h-8 flex items-center justify-center font-bold flex-shrink-0">1</div>
            <div>
              <div className="font-semibold text-purple-200">Get USDC Tokens</div>
              <div className="text-purple-300">Click "Get USDC" button below to mint 10,000 USDC for testing</div>
            </div>
          </div>
          <div className="flex items-start gap-3">
            <div className="bg-purple-600 rounded-full w-8 h-8 flex items-center justify-center font-bold flex-shrink-0">2</div>
            <div>
              <div className="font-semibold text-purple-200">Approve Tokens</div>
              <div className="text-purple-300">Click "Approve USDC" or "Approve DOB" to allow the PoolManager to spend your tokens</div>
            </div>
          </div>
          <div className="flex items-start gap-3">
            <div className="bg-purple-600 rounded-full w-8 h-8 flex items-center justify-center font-bold flex-shrink-0">3</div>
            <div>
              <div className="font-semibold text-purple-200">Execute Swap</div>
              <div className="text-purple-300">Enter amount and click "Swap" - this calls poolManager.swap() which triggers hook.afterSwap()</div>
            </div>
          </div>
          <div className="flex items-start gap-3">
            <div className="bg-purple-600 rounded-full w-8 h-8 flex items-center justify-center font-bold flex-shrink-0">4</div>
            <div>
              <div className="font-semibold text-purple-200">Watch Stabilization</div>
              <div className="text-purple-300">If deviation {">"} 20%, LiquidNode will intervene automatically with 50% of reserves. Watch stats update!</div>
            </div>
          </div>
          <div className="flex items-start gap-3">
            <div className="bg-purple-600 rounded-full w-8 h-8 flex items-center justify-center font-bold flex-shrink-0">5</div>
            <div>
              <div className="font-semibold text-purple-200">Test Different Scenarios</div>
              <div className="text-purple-300">Use Demo Controls below to change NAV/Risk, then swap again to trigger stabilization</div>
            </div>
          </div>
        </div>
      </div>

      {/* Demo Tips */}
      <div className="bg-gradient-to-r from-green-900 to-teal-900 rounded-lg p-5 border-2 border-green-500">
        <h3 className="text-lg font-bold text-green-200 mb-3 flex items-center gap-2">
          💡 Demo Tips - What to Watch
        </h3>
        <div className="grid md:grid-cols-2 gap-3 text-sm text-green-100">
          <div className="bg-green-950 bg-opacity-50 p-3 rounded">
            <div className="font-semibold text-green-300 mb-1">🎯 Trigger Auto-Stabilization</div>
            <div className="text-xs">Swap 6K+ USDC to push deviation above 5% - stabilization triggers automatically!</div>
          </div>
          <div className="bg-green-950 bg-opacity-50 p-3 rounded">
            <div className="font-semibold text-green-300 mb-1">👀 Watch Reserves & Fees</div>
            <div className="text-xs">After swap, click 🔄 Refresh to see 50% intervention + 0.5% fees earned</div>
          </div>
          <div className="bg-green-950 bg-opacity-50 p-3 rounded">
            <div className="font-semibold text-green-300 mb-1">📊 Monitor Progress Bar</div>
            <div className="text-xs">Green = safe (&lt;3%), Yellow = warning (3-5%), Red = triggered (&gt;5%)</div>
          </div>
          <div className="bg-green-950 bg-opacity-50 p-3 rounded">
            <div className="font-semibold text-green-300 mb-1">⚡ Manual Override</div>
            <div className="text-xs">Use "Trigger Stabilization" button below to manually stabilize if needed</div>
          </div>
        </div>
      </div>

      <PoolStatsCard />
      <LiquidNodeStatsCard />
      <SwapCard />
    </div>
  );
}

// Pool Stats Card
function PoolStatsCard() {
  const poolKey = getPoolKey();

  const { data: poolPrice, refetch: refetchPrice } = useReadContract({
    address: CONTRACTS.hook,
    abi: HOOK_ABI,
    functionName: 'getPoolPrice',
    args: [poolKey],
    query: {
      refetchInterval: false, // Manual refresh only
    },
  });

  const { data: stabilization, refetch: refetchStabilization } = useReadContract({
    address: CONTRACTS.hook,
    abi: HOOK_ABI,
    functionName: 'checkStabilization',
    args: [poolKey],
    query: {
      refetchInterval: false, // Manual refresh only
    },
  });

  const { data: nav, refetch: refetchNav } = useReadContract({
    address: CONTRACTS.oracle,
    abi: ORACLE_ABI,
    functionName: 'nav',
    query: {
      refetchInterval: false, // Manual refresh only
    },
  });

  const poolPriceValue = poolPrice ? Number(formatUnits(poolPrice, 18)) : 0;
  const navValue = nav ? Number(formatUnits(nav, 18)) : 1;
  const shouldStabilize = stabilization?.[0] || false;
  const buyDOB = stabilization?.[1] || false;
  const deviation = stabilization?.[2] ? Number(stabilization[2]) / 100 : 0;

  const handleRefresh = () => {
    refetchPrice();
    refetchStabilization();
    refetchNav();
  };

  return (
    <div className="bg-gray-800 rounded-lg p-6 border border-blue-600">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-semibold text-blue-400">📊 Pool Status</h2>
        <button
          onClick={handleRefresh}
          className="px-3 py-1 bg-blue-600 hover:bg-blue-500 rounded text-sm font-semibold transition"
        >
          🔄 Refresh
        </button>
      </div>
      <div className="text-xs text-gray-500 mb-3">Click 🔄 Refresh to see latest pool state</div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <div className="text-gray-400 text-sm">Pool Price</div>
          <div className="text-2xl font-bold">${poolPriceValue.toFixed(4)}</div>
        </div>
        <div>
          <div className="text-gray-400 text-sm">Oracle NAV</div>
          <div className="text-2xl font-bold">${navValue.toFixed(4)}</div>
        </div>
        <div>
          <div className="text-gray-400 text-sm">Deviation</div>
          <div className={`text-2xl font-bold ${deviation > 20 ? 'text-red-400 animate-pulse' : deviation > 10 ? 'text-yellow-400' : 'text-green-400'}`}>
            {deviation.toFixed(2)}%
          </div>
          <div className="text-xs text-gray-500 mt-1">Threshold: 20%</div>
        </div>
        <div>
          <div className="text-gray-400 text-sm">Stabilization Status</div>
          {shouldStabilize ? (
            <div className="flex flex-col">
              <div className="text-xl font-bold text-red-400 animate-pulse">
                🚨 TRIGGERED
              </div>
              <div className="text-xs text-yellow-300 mt-1">
                Will {buyDOB ? 'BUY' : 'SELL'} with 50% reserves
              </div>
            </div>
          ) : (
            <div className="flex flex-col">
              <div className="text-xl font-bold text-green-400">✓ Stable</div>
              <div className="text-xs text-gray-500 mt-1">Within threshold</div>
            </div>
          )}
        </div>
      </div>

      {/* Visual Threshold Indicator */}
      <div className="mt-4 p-3 bg-gray-900 rounded">
        <div className="text-xs text-gray-400 mb-2">Deviation Threshold Monitor</div>
        <div className="relative h-6 bg-gray-700 rounded-full overflow-hidden">
          <div
            className={`h-full transition-all duration-500 ${
              deviation > 20 ? 'bg-red-500 animate-pulse' :
              deviation > 10 ? 'bg-yellow-500' :
              'bg-green-500'
            }`}
            style={{ width: `${Math.min((deviation / 20) * 100, 100)}%` }}
          />
          <div className="absolute inset-0 flex items-center justify-between px-2">
            <span className="text-xs font-bold text-white drop-shadow-lg">
              {deviation.toFixed(1)}%
            </span>
            <span className="text-xs font-bold text-white drop-shadow-lg">
              Trigger: 20%
            </span>
          </div>
        </div>
        {deviation > 20 && (
          <div className="mt-2 text-xs text-red-400 font-semibold animate-pulse">
            ⚠️ Above threshold! Stabilization will trigger on next swap
          </div>
        )}
      </div>
    </div>
  );
}

// Liquid Node Stats Card
function LiquidNodeStatsCard() {
  const [lastUpdate, setLastUpdate] = useState(new Date());

  const { data: balances, refetch: refetchBalances } = useReadContract({
    address: CONTRACTS.liquidNode,
    abi: LIQUID_NODE_STABILIZER_ABI,
    functionName: 'getBalances',
    query: {
      refetchInterval: false, // Manual refresh only
    },
  });

  const { data: fees, refetch: refetchFees } = useReadContract({
    address: CONTRACTS.liquidNode,
    abi: LIQUID_NODE_STABILIZER_ABI,
    functionName: 'totalFeesEarned',
    query: {
      refetchInterval: false, // Manual refresh only
    },
  });

  const usdcBalance = balances ? Number(formatUnits(balances[0], 6)) : 0;
  const dobBalance = balances ? Number(formatUnits(balances[1], 18)) : 0;
  const feesValue = fees ? Number(formatUnits(fees, 6)) : 0;

  // Update timestamp when data changes
  useEffect(() => {
    if (balances || fees) {
      setLastUpdate(new Date());
    }
  }, [balances, fees]);

  // Debug: Log when data changes
  console.log('[FRONTEND] Liquid Node Data:', {
    usdcBalance,
    dobBalance,
    feesValue,
    rawBalances: balances,
    rawFees: fees,
    timestamp: lastUpdate.toLocaleTimeString(),
  });

  const handleRefresh = () => {
    console.log('[FRONTEND] Manual refresh triggered');
    refetchBalances();
    refetchFees();
  };

  // Calculate changes from starting values
  const usdcChange = usdcBalance - 50000;
  const dobChange = dobBalance - 50000;
  const hasChanged = Math.abs(usdcChange) > 1 || Math.abs(dobChange) > 1 || feesValue > 1;

  return (
    <div className="bg-gray-800 rounded-lg p-6 border border-purple-600">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-semibold text-purple-400">💧 Liquid Node Stabilizer</h2>
        <button
          onClick={handleRefresh}
          className="px-3 py-1 bg-purple-600 hover:bg-purple-500 rounded text-sm font-semibold transition"
        >
          🔄 Refresh
        </button>
      </div>
      <div className="text-xs text-gray-500 mb-3 flex items-center justify-between">
        <span>Click 🔄 Refresh to see latest values • Last update: {lastUpdate.toLocaleTimeString()}</span>
        {hasChanged && <span className="text-green-400 font-semibold animate-pulse">● RESERVES CHANGED!</span>}
      </div>

      <div className="grid grid-cols-3 gap-4">
        <div className={hasChanged ? 'bg-green-900 bg-opacity-20 p-3 rounded' : ''}>
          <div className="text-gray-400 text-sm">USDC Reserve</div>
          <div className="text-xl font-bold">{usdcBalance.toLocaleString(undefined, {maximumFractionDigits: 0})}</div>
          <div className="text-xs text-gray-500">Started: 50,000</div>
          {Math.abs(usdcChange) > 1 && (
            <div className={`text-xs font-semibold mt-1 ${usdcChange > 0 ? 'text-green-400' : 'text-red-400'}`}>
              {usdcChange > 0 ? '↑' : '↓'} {Math.abs(usdcChange).toLocaleString(undefined, {maximumFractionDigits: 0})}
            </div>
          )}
        </div>
        <div className={hasChanged ? 'bg-green-900 bg-opacity-20 p-3 rounded' : ''}>
          <div className="text-gray-400 text-sm">DOB Reserve</div>
          <div className="text-xl font-bold">{dobBalance.toLocaleString(undefined, {maximumFractionDigits: 0})}</div>
          <div className="text-xs text-gray-500">Started: 50,000</div>
          {Math.abs(dobChange) > 1 && (
            <div className={`text-xs font-semibold mt-1 ${dobChange > 0 ? 'text-green-400' : 'text-red-400'}`}>
              {dobChange > 0 ? '↑' : '↓'} {Math.abs(dobChange).toLocaleString(undefined, {maximumFractionDigits: 0})}
            </div>
          )}
        </div>
        <div className={feesValue > 1 ? 'bg-green-900 bg-opacity-20 p-3 rounded' : ''}>
          <div className="text-gray-400 text-sm">Fees Earned</div>
          <div className="text-xl font-bold text-green-400">{feesValue.toLocaleString(undefined, {maximumFractionDigits: 0})} USDC</div>
          <div className="text-xs text-gray-500">0.5% per intervention</div>
        </div>
      </div>

      {/* Debug info */}
      <div className="mt-4 p-3 bg-gray-900 rounded text-xs font-mono">
        <div className="text-gray-500 mb-1">Debug (raw values):</div>
        <div className="text-gray-400">USDC: {balances ? balances[0].toString() : 'loading...'}</div>
        <div className="text-gray-400">DOB: {balances ? balances[1].toString() : 'loading...'}</div>
        <div className="text-gray-400">Fees: {fees ? fees.toString() : 'loading...'}</div>
      </div>
    </div>
  );
}

// Swap Card
function SwapCard() {
  const [amount, setAmount] = useState('');
  const [isBuying, setIsBuying] = useState(true);
  const [swapHistory, setSwapHistory] = useState<Array<{
    direction: string;
    amount: string;
    timestamp: number;
    txHash?: string;
  }>>(() => {
    // Load history from localStorage
    try {
      const saved = localStorage.getItem('swapHistory');
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  });
  const { address } = useAccount();

  const { data: usdcBalance } = useReadContract({
    address: CONTRACTS.usdc,
    abi: USDC_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      refetchInterval: false, // Manual refresh only
    },
  });

  const { data: dobBalance } = useReadContract({
    address: CONTRACTS.dobToken,
    abi: DOB_TOKEN_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      refetchInterval: false, // Manual refresh only
    },
  });

  const { data: usdcAllowance } = useReadContract({
    address: CONTRACTS.usdc,
    abi: USDC_ABI,
    functionName: 'allowance',
    args: address ? [address, CONTRACTS.poolManager] : undefined,
    query: {
      refetchInterval: false, // Manual refresh only
    },
  });

  const { data: dobAllowance } = useReadContract({
    address: CONTRACTS.dobToken,
    abi: DOB_TOKEN_ABI,
    functionName: 'allowance',
    args: address ? [address, CONTRACTS.poolManager] : undefined,
    query: {
      refetchInterval: false, // Manual refresh only
    },
  });

  const { writeContract: approveUSDC, data: approveUSDCHash, isPending: isApprovePending, error: approveError } = useWriteContract();
  const { writeContract: approveDOB, data: approveDOBHash, isPending: isApproveDOBPending, error: approveDOBError } = useWriteContract();
  const { writeContract: executeSwap, data: swapHash, isPending: isSwapPending, error: swapError } = useWriteContract();
  const { writeContract: mintUSDC, data: mintHash, error: mintError } = useWriteContract();
  const { writeContract: triggerStabilization, data: stabilizeHash, isPending: isStabilizePending, error: stabilizeError } = useWriteContract();

  const { isLoading: isApproving, isSuccess: approveSuccess, error: approveTxError } = useWaitForTransactionReceipt({
    hash: approveUSDCHash || approveDOBHash,
    confirmations: 1, // Only wait for 1 confirmation (Anvil mines instantly)
  });
  const { isLoading: isSwapping, isSuccess: swapSuccess, error: swapTxError } = useWaitForTransactionReceipt({
    hash: swapHash,
    confirmations: 1,
  });
  const { isLoading: isMinting, isSuccess: mintSuccess, error: mintTxError } = useWaitForTransactionReceipt({
    hash: mintHash,
    confirmations: 1,
  });
  const { isLoading: isStabilizing, isSuccess: stabilizeSuccess, error: stabilizeTxError } = useWaitForTransactionReceipt({
    hash: stabilizeHash,
    confirmations: 1,
  });

  // Save successful swaps to history
  useEffect(() => {
    if (swapSuccess && swapHash && amount) {
      const newSwap = {
        direction: isBuying ? 'Buy DOB' : 'Sell DOB',
        amount,
        timestamp: Date.now(),
        txHash: swapHash,
      };
      const updatedHistory = [newSwap, ...swapHistory].slice(0, 10); // Keep last 10
      setSwapHistory(updatedHistory);
      localStorage.setItem('swapHistory', JSON.stringify(updatedHistory));
    }
  }, [swapSuccess, swapHash]);

  const amountValue = parseFloat(amount) || 0;
  const usdcBalanceValue = usdcBalance ? Number(formatUnits(usdcBalance, 6)) : 0;
  const dobBalanceValue = dobBalance ? Number(formatUnits(dobBalance, 18)) : 0;

  // Check if approval is needed - compare bigints properly
  const needsApproval = isBuying
    ? !usdcAllowance || usdcAllowance < parseUnits(amount || '0', 6)
    : !dobAllowance || dobAllowance < parseUnits(amount || '0', 18);

  const handleApprove = () => {
    console.log(`🔓 Approving ${isBuying ? 'USDC' : 'DOB'} for PoolManager`);
    if (isBuying) {
      approveUSDC({
        address: CONTRACTS.usdc,
        abi: USDC_ABI,
        functionName: 'approve',
        args: [CONTRACTS.poolManager, parseUnits('1000000', 6)], // Approve 1M
      });
    } else {
      approveDOB({
        address: CONTRACTS.dobToken,
        abi: DOB_TOKEN_ABI,
        functionName: 'approve',
        args: [CONTRACTS.poolManager, parseUnits('1000000', 18)],
      });
    }
  };

  const handleSwap = () => {
    const poolKey = getPoolKey();
    const zeroForOne = isBuying
      ? CONTRACTS.usdc < CONTRACTS.dobToken
      : CONTRACTS.dobToken < CONTRACTS.usdc;

    // Parse amount as BigInt (keep precision!)
    const amountBigInt = isBuying
      ? parseUnits(amount, 6)
      : parseUnits(amount, 18);

    // IMPORTANT: Use NEGATIVE for exact input (Uniswap V4 convention)
    // Negative = "I'm giving exactly this much"
    // Positive = "I want to receive exactly this much"
    const amountSpecified = -amountBigInt;

    console.log('🔄 Executing swap:', {
      direction: isBuying ? 'Buy DOB' : 'Sell DOB',
      zeroForOne,
      amount: amount,
      amountSpecified: amountSpecified.toString(),
    });

    executeSwap({
      address: CONTRACTS.poolManager,
      abi: POOL_MANAGER_ABI,
      functionName: 'swap',
      args: [
        poolKey,
        {
          zeroForOne,
          amountSpecified, // Keep as BigInt, don't convert to Number!
          sqrtPriceLimitX96: BigInt(0),
        },
        '0x',
      ],
    });
  };

  const handleMintUSDC = () => {
    if (!address) return;
    console.log('💰 Minting 10,000 USDC for testing');
    mintUSDC({
      address: CONTRACTS.usdc,
      abi: USDC_ABI,
      functionName: 'mint',
      args: [address, parseUnits('10000', 6)],
    });
  };

  const handleManualStabilize = () => {
    const poolKey = getPoolKey();
    console.log('⚡ Manually triggering stabilization');
    triggerStabilization({
      address: CONTRACTS.hook,
      abi: HOOK_ABI,
      functionName: 'manualStabilize',
      args: [poolKey],
    });
  };

  const handleRedoSwap = (historyItem: { direction: string; amount: string }) => {
    const isBuySwap = historyItem.direction === 'Buy DOB';

    // Set the amount and direction in the UI for visibility
    setIsBuying(isBuySwap);
    setAmount(historyItem.amount);

    // Execute the swap directly with the history item's parameters
    const poolKey = getPoolKey();
    const zeroForOne = isBuySwap
      ? CONTRACTS.usdc < CONTRACTS.dobToken
      : CONTRACTS.dobToken < CONTRACTS.usdc;

    const amountBigInt = isBuySwap
      ? parseUnits(historyItem.amount, 6)
      : parseUnits(historyItem.amount, 18);

    const amountSpecified = -amountBigInt;

    console.log('🔄 Redoing swap from history:', {
      direction: historyItem.direction,
      zeroForOne,
      amount: historyItem.amount,
      amountSpecified: amountSpecified.toString(),
    });

    executeSwap({
      address: CONTRACTS.poolManager,
      abi: POOL_MANAGER_ABI,
      functionName: 'swap',
      args: [
        poolKey,
        {
          zeroForOne,
          amountSpecified,
          sqrtPriceLimitX96: BigInt(0),
        },
        '0x',
      ],
    });
  };

  const clearHistory = () => {
    setSwapHistory([]);
    localStorage.removeItem('swapHistory');
  };

  return (
    <div className="bg-gray-800 rounded-lg p-6">
      <h2 className="text-xl font-semibold mb-4 text-yellow-400">🔄 Swap (Tests Hook Integration)</h2>

      {/* Get USDC Button */}
      <div className="mb-4 p-3 bg-cyan-900 bg-opacity-30 rounded border border-cyan-600">
        <div className="flex justify-between items-center">
          <div>
            <div className="font-semibold text-cyan-400">Need USDC?</div>
            <div className="text-sm text-gray-400">Mint 10,000 USDC for testing</div>
          </div>
          <button
            onClick={handleMintUSDC}
            disabled={!address || isMinting}
            className="bg-cyan-600 hover:bg-cyan-500 disabled:bg-gray-600 px-4 py-2 rounded font-semibold"
          >
            {isMinting ? 'Minting...' : 'Get USDC'}
          </button>
        </div>
        {mintSuccess && <div className="text-green-400 text-sm mt-2">✓ Minted 10,000 USDC!</div>}
      </div>

      {/* Direction Toggle */}
      <div className="flex gap-2 mb-4">
        <button
          onClick={() => setIsBuying(true)}
          className={`flex-1 py-2 rounded font-semibold transition ${
            isBuying ? 'bg-green-600' : 'bg-gray-700 hover:bg-gray-600'
          }`}
        >
          Buy DOB
        </button>
        <button
          onClick={() => setIsBuying(false)}
          className={`flex-1 py-2 rounded font-semibold transition ${
            !isBuying ? 'bg-red-600' : 'bg-gray-700 hover:bg-gray-600'
          }`}
        >
          Sell DOB
        </button>
      </div>

      {/* Amount Input */}
      <div className="mb-4">
        <div className="flex justify-between mb-2">
          <label className="text-sm text-gray-400">
            {isBuying ? 'USDC Amount' : 'DOB Amount'}
          </label>
          <button
            onClick={() => setAmount(isBuying ? usdcBalanceValue.toString() : dobBalanceValue.toString())}
            className="text-sm text-blue-400 hover:text-blue-300"
          >
            Balance: {isBuying ? usdcBalanceValue.toFixed(2) : dobBalanceValue.toFixed(0)}
          </button>
        </div>
        <input
          type="number"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="0"
          className="w-full bg-gray-700 rounded px-4 py-3 text-lg focus:outline-none focus:ring-2 focus:ring-blue-400"
        />

        {/* Quick Test Buttons */}
        <div className="mt-3 p-3 bg-gradient-to-r from-blue-900 to-purple-900 rounded border border-blue-500">
          <div className="text-sm font-semibold text-blue-300 mb-2">⚡ Quick Demo Tests</div>
          <div className="grid grid-cols-2 gap-2">
            <button
              onClick={() => setAmount('2000')}
              className="px-3 py-2 bg-green-600 hover:bg-green-500 rounded text-xs font-semibold"
            >
              2K - Safe Zone<br/>
              <span className="text-[10px] opacity-80">(~3% deviation)</span>
            </button>
            <button
              onClick={() => setAmount('4000')}
              className="px-3 py-2 bg-yellow-600 hover:bg-yellow-500 rounded text-xs font-semibold"
            >
              4K - Warning<br/>
              <span className="text-[10px] opacity-80">(~4.5% deviation)</span>
            </button>
            <button
              onClick={() => setAmount('6000')}
              className="px-3 py-2 bg-orange-600 hover:bg-orange-500 rounded text-xs font-semibold animate-pulse"
            >
              🎯 6K - TRIGGER<br/>
              <span className="text-[10px] opacity-80">(~6% deviation)</span>
            </button>
            <button
              onClick={() => setAmount('8000')}
              className="px-3 py-2 bg-red-600 hover:bg-red-500 rounded text-xs font-semibold animate-pulse"
            >
              🚨 8K - BIG TRIGGER<br/>
              <span className="text-[10px] opacity-80">(~8% deviation)</span>
            </button>
          </div>
          <div className="text-[10px] text-blue-200 mt-2 text-center">
            💡 Use 6K+ to see stabilization in action!
          </div>
        </div>
      </div>

      {/* Status Messages */}
      {amountValue > 0 && (
        <div className="mb-3 p-2 bg-gray-700 rounded text-xs">
          <div className="flex justify-between">
            <span className="text-gray-400">Approval Status:</span>
            <span className={needsApproval ? 'text-yellow-400' : 'text-green-400'}>
              {needsApproval ? '⚠️ Need Approval' : '✓ Approved'}
            </span>
          </div>
          {needsApproval && (
            <div className="text-gray-400 mt-1">
              Current allowance: {isBuying
                ? (usdcAllowance ? formatUnits(usdcAllowance, 6) : '0')
                : (dobAllowance ? formatUnits(dobAllowance, 18) : '0')
              }
            </div>
          )}
        </div>
      )}

      {/* Action Buttons */}
      <div className="space-y-3 mt-4">
        {needsApproval && (
          <div className="bg-blue-900 bg-opacity-30 border-2 border-blue-500 rounded-lg p-3">
            <div className="text-sm text-blue-300 mb-2 font-semibold">⚠️ Step 1: Approve Token</div>
            <button
              onClick={handleApprove}
              disabled={!address || isApprovePending || isApproveDOBPending || isApproving || amountValue <= 0}
              className="w-full bg-blue-600 hover:bg-blue-500 disabled:bg-gray-600 rounded-lg py-3 font-bold text-lg transition transform hover:scale-105"
            >
              {isApprovePending || isApproveDOBPending ? '⏳ Waiting for wallet...' : isApproving ? '⏳ Confirming...' : `✓ Approve ${isBuying ? 'USDC' : 'DOB'}`}
            </button>
          </div>
        )}
        <div className={`rounded-lg p-3 ${needsApproval ? 'bg-gray-900 bg-opacity-50 border border-gray-700' : 'bg-yellow-900 bg-opacity-30 border-2 border-yellow-500'}`}>
          <div className={`text-sm mb-2 font-semibold ${needsApproval ? 'text-gray-500' : 'text-yellow-300'}`}>
            {needsApproval ? '⏸️ Step 2: Execute Swap (approve first)' : '🚀 Step 2: Execute Swap'}
          </div>
          <button
            onClick={handleSwap}
            disabled={!address || isSwapPending || isSwapping || amountValue <= 0 || needsApproval}
            className={`w-full rounded-lg py-4 font-bold text-lg transition transform ${
              needsApproval
                ? 'bg-gray-600 cursor-not-allowed'
                : 'bg-gradient-to-r from-yellow-600 to-orange-600 hover:from-yellow-500 hover:to-orange-500 hover:scale-105 animate-pulse'
            }`}
          >
            {isSwapPending ? '⏳ Waiting for wallet...' : isSwapping ? '⏳ Confirming...' : needsApproval ? '🔒 Approve First' : `🔄 Swap ${isBuying ? 'USDC → DOB' : 'DOB → USDC'}`}
          </button>
        </div>
      </div>

      {/* Success Messages */}
      {approveSuccess && (
        <div className="mt-4 p-3 bg-green-900 bg-opacity-30 border border-green-600 rounded">
          <div className="text-green-400 font-semibold">✓ Approval Successful!</div>
          <div className="text-sm text-gray-400 mt-1">
            You can now execute the swap
          </div>
          {(approveUSDCHash || approveDOBHash) && (
            <div className="text-xs text-gray-500 mt-1">
              Tx: {(approveUSDCHash || approveDOBHash)?.slice(0, 10)}...{(approveUSDCHash || approveDOBHash)?.slice(-8)}
            </div>
          )}
        </div>
      )}

      {swapSuccess && (
        <div className="mt-4 p-3 bg-green-900 bg-opacity-30 border border-green-600 rounded">
          <div className="text-green-400 font-semibold">✓ Swap Successful!</div>
          <div className="text-sm text-gray-400 mt-1">
            Hook checked for price deviation - stabilization triggered automatically if needed (deviation &gt; 5%)
          </div>
          {swapHash && (
            <div className="text-xs text-gray-500 mt-1">
              Tx: {swapHash.slice(0, 10)}...{swapHash.slice(-8)}
            </div>
          )}
        </div>
      )}

      {mintSuccess && (
        <div className="mt-4 p-3 bg-green-900 bg-opacity-30 border border-green-600 rounded">
          <div className="text-green-400 font-semibold">✓ USDC Minted Successfully!</div>
          <div className="text-sm text-gray-400 mt-1">
            10,000 USDC added to your wallet
          </div>
        </div>
      )}

      {stabilizeSuccess && (
        <div className="mt-4 p-3 bg-green-900 bg-opacity-30 border border-green-600 rounded">
          <div className="text-green-400 font-semibold">✓ Manual Stabilization Successful!</div>
          <div className="text-sm text-gray-400 mt-1">
            Liquid Node intervened with 50% of reserves
          </div>
          {stabilizeHash && (
            <div className="text-xs text-gray-500 mt-1">
              Tx: {stabilizeHash.slice(0, 10)}...{stabilizeHash.slice(-8)}
            </div>
          )}
        </div>
      )}

      {/* Manual Stabilization Button */}
      <div className="mt-4 p-4 bg-gradient-to-r from-purple-900 to-pink-900 rounded-lg border-2 border-purple-500">
        <h3 className="text-lg font-bold text-purple-200 mb-2">⚡ Manual Stabilization</h3>
        <div className="text-sm text-purple-300 mb-3">
          After large swaps, click below to manually trigger price stabilization
        </div>
        <button
          onClick={handleManualStabilize}
          disabled={!address || isStabilizePending || isStabilizing}
          className="w-full bg-gradient-to-r from-purple-600 to-pink-600 hover:from-purple-500 hover:to-pink-500 disabled:from-gray-600 disabled:to-gray-600 rounded-lg py-3 font-bold text-lg transition transform hover:scale-105"
        >
          {isStabilizePending ? '⏳ Waiting for wallet...' : isStabilizing ? '⏳ Stabilizing...' : '⚡ Trigger Stabilization'}
        </button>
        <div className="text-xs text-purple-400 mt-2 text-center">
          Will only stabilize if deviation &gt; 5%
        </div>
      </div>

      {/* Error Messages */}
      {(approveError || approveDOBError || approveTxError) && (
        <div className="mt-4 p-3 bg-red-900 bg-opacity-30 border border-red-600 rounded">
          <div className="text-red-400 font-semibold">✗ Approval Failed</div>
          <div className="text-sm text-gray-400 mt-1">
            {(approveError || approveDOBError || approveTxError)?.message || 'Transaction failed'}
          </div>
          <div className="text-xs text-gray-500 mt-2">
            Check browser console for details
          </div>
        </div>
      )}

      {(swapError || swapTxError) && (
        <div className="mt-4 p-3 bg-red-900 bg-opacity-30 border border-red-600 rounded">
          <div className="text-red-400 font-semibold">✗ Swap Failed</div>
          <div className="text-sm text-gray-400 mt-1">
            {(swapError || swapTxError)?.message || 'Transaction failed'}
          </div>
          <div className="text-xs text-gray-500 mt-2">
            Common issues: Insufficient balance, slippage too high, or pool price deviation
          </div>
        </div>
      )}

      {(mintError || mintTxError) && (
        <div className="mt-4 p-3 bg-red-900 bg-opacity-30 border border-red-600 rounded">
          <div className="text-red-400 font-semibold">✗ Mint Failed</div>
          <div className="text-sm text-gray-400 mt-1">
            {(mintError || mintTxError)?.message || 'Transaction failed'}
          </div>
        </div>
      )}

      {(stabilizeError || stabilizeTxError) && (
        <div className="mt-4 p-3 bg-red-900 bg-opacity-30 border border-red-600 rounded">
          <div className="text-red-400 font-semibold">✗ Stabilization Failed</div>
          <div className="text-sm text-gray-400 mt-1">
            {(stabilizeError || stabilizeTxError)?.message || 'Transaction failed'}
          </div>
        </div>
      )}

      {/* Swap History */}
      {swapHistory.length > 0 && (
        <div className="mt-4 p-4 bg-gray-700 rounded">
          <div className="flex items-center justify-between mb-3">
            <h3 className="font-semibold text-blue-400">📜 Recent Swaps</h3>
            <button
              onClick={clearHistory}
              className="text-xs text-gray-400 hover:text-gray-300"
            >
              Clear History
            </button>
          </div>
          <div className="space-y-2 max-h-64 overflow-y-auto">
            {swapHistory.map((swap, index) => (
              <div
                key={index}
                className="flex items-center justify-between p-2 bg-gray-800 rounded text-sm"
              >
                <div className="flex-1">
                  <div className="font-semibold">
                    {swap.direction === 'Buy DOB' ? '🟢' : '🔴'} {swap.direction}
                  </div>
                  <div className="text-xs text-gray-400">
                    {swap.amount} {swap.direction === 'Buy DOB' ? 'USDC' : 'DOB'}
                    {' • '}
                    {new Date(swap.timestamp).toLocaleTimeString()}
                  </div>
                  {swap.txHash && (
                    <div className="text-xs text-gray-500 font-mono">
                      {swap.txHash.slice(0, 10)}...{swap.txHash.slice(-8)}
                    </div>
                  )}
                </div>
                <button
                  onClick={() => handleRedoSwap(swap)}
                  disabled={!address || isSwapPending || isSwapping}
                  className="ml-3 px-3 py-1 bg-blue-600 hover:bg-blue-500 disabled:bg-gray-600 disabled:cursor-not-allowed rounded text-xs font-semibold"
                >
                  🔄 Redo
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="mt-4 p-3 bg-gray-700 rounded text-sm text-gray-300">
        <div className="font-semibold mb-1">💡 What happens when you swap:</div>
        <ol className="list-decimal list-inside space-y-1 text-xs">
          <li>PoolManager executes the swap (constant product AMM)</li>
          <li>Hook's afterSwap() is automatically called</li>
          <li>Hook reads pool price from reserves</li>
          <li>Hook compares to oracle NAV</li>
          <li>If deviation {">"} 20%, LiquidNodeStabilizer intervenes with 50% of reserves</li>
          <li>Watch the stats above update in real-time!</li>
        </ol>
      </div>
    </div>
  );
}

// Helper function to create pool key
function getPoolKey() {
  const currency0 = CONTRACTS.usdc < CONTRACTS.dobToken ? CONTRACTS.usdc : CONTRACTS.dobToken;
  const currency1 = CONTRACTS.usdc < CONTRACTS.dobToken ? CONTRACTS.dobToken : CONTRACTS.usdc;

  return {
    currency0,
    currency1,
    fee: 3000,
    tickSpacing: 60,
    hooks: CONTRACTS.hook,
  };
}
