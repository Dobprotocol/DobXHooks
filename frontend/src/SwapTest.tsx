import { useState, useEffect } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { formatUnits, parseUnits, keccak256, encodeAbiParameters } from 'viem';
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
              <div className="text-purple-300">If deviation {">"} 5%, LiquidNode will intervene automatically. Watch stats update!</div>
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
      <div className="text-xs text-gray-500 mb-3">Auto-updates every 2 seconds</div>

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
          <div className={`text-2xl font-bold ${deviation > 5 ? 'text-red-400' : 'text-green-400'}`}>
            {deviation.toFixed(2)}%
          </div>
        </div>
        <div>
          <div className="text-gray-400 text-sm">Stabilization</div>
          {shouldStabilize ? (
            <div className="text-xl font-bold text-yellow-400">
              ⚠️ {buyDOB ? 'BUY DOB' : 'SELL DOB'}
            </div>
          ) : (
            <div className="text-xl font-bold text-green-400">✓ Stable</div>
          )}
        </div>
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
  const { writeContract: mintUSDC, data: mintHash, isPending: isMintPending, error: mintError } = useWriteContract();

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

        {/* Quick Amount Buttons */}
        <div className="flex gap-2 mt-2">
          <button
            onClick={() => setAmount('1000')}
            className="flex-1 px-3 py-1 bg-gray-600 hover:bg-gray-500 rounded text-xs"
          >
            1K (Small - No Stabilization)
          </button>
          <button
            onClick={() => setAmount('6000')}
            className="flex-1 px-3 py-1 bg-yellow-600 hover:bg-yellow-500 rounded text-xs"
          >
            6K (Large - Triggers Stabilization!)
          </button>
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
      <div className="space-y-2">
        {needsApproval && (
          <button
            onClick={handleApprove}
            disabled={!address || isApprovePending || isApproveDOBPending || isApproving || amountValue <= 0}
            className="w-full bg-blue-600 hover:bg-blue-500 disabled:bg-gray-600 rounded py-3 font-semibold"
          >
            {isApprovePending || isApproveDOBPending ? 'Waiting for wallet...' : isApproving ? 'Confirming...' : `Approve ${isBuying ? 'USDC' : 'DOB'}`}
          </button>
        )}
        <button
          onClick={handleSwap}
          disabled={!address || isSwapPending || isSwapping || amountValue <= 0 || needsApproval}
          className="w-full bg-yellow-600 hover:bg-yellow-500 disabled:bg-gray-600 disabled:cursor-not-allowed rounded py-3 font-semibold"
        >
          {isSwapPending ? 'Waiting for wallet...' : isSwapping ? 'Confirming...' : needsApproval ? 'Approve First' : `Swap ${isBuying ? 'USDC → DOB' : 'DOB → USDC'}`}
        </button>
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
            The hook's afterSwap() was called and checked for stabilization
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

      <div className="mt-4 p-3 bg-gray-700 rounded text-sm text-gray-300">
        <div className="font-semibold mb-1">💡 What happens when you swap:</div>
        <ol className="list-decimal list-inside space-y-1 text-xs">
          <li>PoolManager executes the swap (constant product AMM)</li>
          <li>Hook's afterSwap() is automatically called</li>
          <li>Hook reads pool price from reserves</li>
          <li>Hook compares to oracle NAV</li>
          <li>If deviation {">"} 5%, LiquidNodeStabilizer intervenes</li>
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
