import { useState } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { formatUnits, parseUnits } from 'viem';
import { CONTRACTS, ORACLE_ABI, DOB_TOKEN_ABI, USDC_ABI } from './contracts';
import { SwapTestPanel } from './SwapTest';

function App() {
  const [tab, setTab] = useState<'overview' | 'test'>('test');

  return (
    <div className="min-h-screen bg-gray-900 p-4 md:p-8">
      <div className="max-w-4xl mx-auto">
        {/* Header */}
        <header className="flex justify-between items-center mb-8">
          <h1 className="text-2xl font-bold text-yellow-400">
            ☀️ DOB Solar Farm 2035
          </h1>
          <ConnectButton />
        </header>

        {/* Tab Navigation */}
        <div className="flex gap-2 mb-6">
          <button
            onClick={() => setTab('test')}
            className={`px-6 py-2 rounded font-semibold transition ${
              tab === 'test' ? 'bg-blue-600' : 'bg-gray-800 hover:bg-gray-700'
            }`}
          >
            🧪 Hook Integration Test
          </button>
          <button
            onClick={() => setTab('overview')}
            className={`px-6 py-2 rounded font-semibold transition ${
              tab === 'overview' ? 'bg-blue-600' : 'bg-gray-800 hover:bg-gray-700'
            }`}
          >
            📊 Overview
          </button>
        </div>

        {tab === 'test' ? (
          <>
            <SwapTestPanel />
            <DemoPanel />
          </>
        ) : (
          <>
            {/* Stats Bar */}
            <StatsBar />

            {/* USDC Faucet */}
            <USDCFaucet />

            {/* Main Actions */}
            <div className="grid md:grid-cols-2 gap-6 mt-6">
              <BuyCard />
              <SellCard />
            </div>

            {/* Demo Panel */}
            <DemoPanel />
          </>
        )}
      </div>
    </div>
  );
}

// Stats Bar Component
function StatsBar() {
  const { address } = useAccount();

  const { data: nav } = useReadContract({
    address: CONTRACTS.oracle,
    abi: ORACLE_ABI,
    functionName: 'nav',
    query: {
      refetchInterval: false, // Manual refresh only
    },
  });

  const { data: risk } = useReadContract({
    address: CONTRACTS.oracle,
    abi: ORACLE_ABI,
    functionName: 'defaultRisk',
    query: {
      refetchInterval: false, // Manual refresh only
    },
  });

  const { data: balance } = useReadContract({
    address: CONTRACTS.dobToken,
    abi: DOB_TOKEN_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      refetchInterval: false, // Manual refresh only
    },
  });

  const { data: usdcBalance } = useReadContract({
    address: CONTRACTS.usdc,
    abi: USDC_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: {
      refetchInterval: false, // Manual refresh only
    },
  });

  const navValue = nav ? Number(formatUnits(nav, 18)) : 1;
  const riskValue = risk ? Number(risk) / 100 : 10;
  const balanceValue = balance ? Number(formatUnits(balance, 18)) : 0;
  const portfolioValue = balanceValue * navValue;
  const usdcValue = usdcBalance ? Number(formatUnits(usdcBalance, 6)) : 0;

  return (
    <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
      <StatCard
        label="NAV"
        value={`$${navValue.toFixed(2)}`}
        subtext={navValue >= 1 ? `↑ +${((navValue - 1) * 100).toFixed(0)}%` : `↓ ${((1 - navValue) * 100).toFixed(0)}%`}
        color={navValue >= 1 ? 'text-green-400' : 'text-red-400'}
      />
      <StatCard
        label="Risk"
        value={`${riskValue.toFixed(1)}%`}
        subtext={riskValue < 15 ? 'Low' : riskValue < 30 ? 'Medium' : 'High'}
        color={riskValue < 15 ? 'text-green-400' : riskValue < 30 ? 'text-yellow-400' : 'text-red-400'}
      />
      <StatCard
        label="USDC Balance"
        value={`${usdcValue.toFixed(2)}`}
        subtext="Available to invest"
        color="text-cyan-400"
      />
      <StatCard
        label="DOB Balance"
        value={`${balanceValue.toFixed(0)} DOB`}
        subtext={`≈ $${portfolioValue.toFixed(0)}`}
        color="text-blue-400"
      />
    </div>
  );
}

function StatCard({ label, value, subtext, color }: { label: string; value: string; subtext: string; color: string }) {
  return (
    <div className="bg-gray-800 rounded-lg p-4 text-center">
      <div className="text-gray-400 text-sm">{label}</div>
      <div className="text-2xl font-bold mt-1">{value}</div>
      <div className={`text-sm mt-1 ${color}`}>{subtext}</div>
    </div>
  );
}

// USDC Faucet Component
function USDCFaucet() {
  const { address } = useAccount();
  const { writeContract, data: hash, isPending, error: writeError } = useWriteContract();
  const { isLoading: isConfirming, isSuccess, error: txError } = useWaitForTransactionReceipt({ hash });

  const handleFaucet = () => {
    if (!address) return;
    console.log('🚀 Requesting USDC faucet for address:', address);
    writeContract({
      address: CONTRACTS.usdc,
      abi: USDC_ABI,
      functionName: 'mint',
      args: [address, parseUnits('10000', 6)],
    });
  };

  const isLoading = isPending || isConfirming;
  const error = writeError || txError;

  return (
    <div className="mt-6 bg-cyan-900 bg-opacity-30 border border-cyan-600 rounded-lg p-4">
      <div className="flex items-center justify-between">
        <div>
          <h3 className="font-semibold text-cyan-400">Test USDC Faucet</h3>
          <p className="text-sm text-gray-400 mt-1">Get 10,000 USDC for testing</p>
        </div>
        <button
          onClick={handleFaucet}
          disabled={!address || isLoading}
          className="bg-cyan-600 hover:bg-cyan-500 disabled:bg-gray-600 disabled:cursor-not-allowed px-6 py-2 rounded font-semibold transition"
        >
          {isPending ? 'Waiting for wallet...' : isConfirming ? 'Confirming...' : 'Get USDC'}
        </button>
      </div>
      {isSuccess && (
        <p className="text-green-400 text-sm mt-2">✓ 10,000 USDC claimed successfully!</p>
      )}
      {error && (
        <p className="text-red-400 text-sm mt-2">
          ✗ Error: {error.message || 'Transaction failed'}
        </p>
      )}
      {hash && (
        <p className="text-gray-400 text-xs mt-1">
          Tx: {hash.slice(0, 10)}...{hash.slice(-8)}
        </p>
      )}
    </div>
  );
}

// Buy Card Component
function BuyCard() {
  const [amount, setAmount] = useState('');
  const { address } = useAccount();

  const { data: nav } = useReadContract({
    address: CONTRACTS.oracle,
    abi: ORACLE_ABI,
    functionName: 'nav',
  });

  const navValue = nav ? Number(formatUnits(nav, 18)) : 1;
  const usdcAmount = parseFloat(amount) || 0;
  const toOperator = usdcAmount * 0.99;
  const dobReceived = toOperator / navValue;

  return (
    <div className="bg-gray-800 rounded-lg p-6">
      <h2 className="text-xl font-semibold mb-4 text-green-400">Buy DOB</h2>

      <div className="mb-4">
        <label className="block text-sm text-gray-400 mb-2">USDC Amount</label>
        <input
          type="number"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="0"
          className="w-full bg-gray-700 rounded px-4 py-3 text-lg focus:outline-none focus:ring-2 focus:ring-green-400"
        />
      </div>

      {usdcAmount > 0 && (
        <div className="space-y-2 mb-4 text-sm">
          <div className="flex justify-between">
            <span className="text-gray-400">You receive:</span>
            <span className="font-semibold">{dobReceived.toFixed(2)} DOB</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-400">To operator:</span>
            <span>${toOperator.toFixed(2)}</span>
          </div>
        </div>
      )}

      <button
        disabled={!address || usdcAmount <= 0}
        className="w-full bg-green-600 hover:bg-green-500 disabled:bg-gray-600 disabled:cursor-not-allowed rounded py-3 font-semibold transition"
      >
        {!address ? 'Connect Wallet' : 'Buy DOB'}
      </button>
    </div>
  );
}

// Sell Card Component
function SellCard() {
  const [amount, setAmount] = useState('');
  const { address } = useAccount();

  const { data: nav } = useReadContract({
    address: CONTRACTS.oracle,
    abi: ORACLE_ABI,
    functionName: 'nav',
  });

  const { data: risk } = useReadContract({
    address: CONTRACTS.oracle,
    abi: ORACLE_ABI,
    functionName: 'defaultRisk',
  });

  const { data: balance } = useReadContract({
    address: CONTRACTS.dobToken,
    abi: DOB_TOKEN_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
  });

  const navValue = nav ? Number(formatUnits(nav, 18)) : 1;
  const riskValue = risk ? Number(risk) : 1000;
  const balanceValue = balance ? Number(formatUnits(balance, 18)) : 0;

  const dobAmount = parseFloat(amount) || 0;
  const penaltyBps = Math.min(300 + riskValue / 10, 5000);
  const penaltyPercent = penaltyBps / 100;
  const usdcReceived = dobAmount * navValue * (1 - penaltyBps / 10000);

  return (
    <div className="bg-gray-800 rounded-lg p-6">
      <h2 className="text-xl font-semibold mb-4 text-red-400">Sell DOB</h2>

      <div className="mb-4">
        <label className="block text-sm text-gray-400 mb-2">
          DOB Amount
          <button
            onClick={() => setAmount(balanceValue.toString())}
            className="float-right text-blue-400 hover:text-blue-300"
          >
            Max: {balanceValue.toFixed(0)}
          </button>
        </label>
        <input
          type="number"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="0"
          className="w-full bg-gray-700 rounded px-4 py-3 text-lg focus:outline-none focus:ring-2 focus:ring-red-400"
        />
      </div>

      {dobAmount > 0 && (
        <div className="space-y-2 mb-4 text-sm">
          <div className="flex justify-between">
            <span className="text-gray-400">You receive:</span>
            <span className="font-semibold">${usdcReceived.toFixed(2)}</span>
          </div>
          <div className="flex justify-between">
            <span className="text-gray-400">Penalty:</span>
            <span className={penaltyPercent > 5 ? 'text-red-400' : 'text-yellow-400'}>
              {penaltyPercent.toFixed(1)}%
            </span>
          </div>
        </div>
      )}

      <button
        disabled={!address || dobAmount <= 0 || dobAmount > balanceValue}
        className="w-full bg-red-600 hover:bg-red-500 disabled:bg-gray-600 disabled:cursor-not-allowed rounded py-3 font-semibold transition"
      >
        {!address ? 'Connect Wallet' : 'Sell DOB'}
      </button>
    </div>
  );
}

// Demo Panel Component
function DemoPanel() {
  const [navInput, setNavInput] = useState('1.00');
  const [riskInput, setRiskInput] = useState('10');
  const { address } = useAccount();

  const { writeContract, data: hash } = useWriteContract();
  const { isLoading, isSuccess } = useWaitForTransactionReceipt({ hash });

  // Oracle updater address
  const ORACLE_UPDATER = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266' as `0x${string}`;
  const isUpdater = address?.toLowerCase() === ORACLE_UPDATER.toLowerCase();

  const handleUpdate = () => {
    const navWei = parseUnits(navInput, 18);
    const riskBps = BigInt(parseFloat(riskInput) * 100);

    writeContract({
      address: CONTRACTS.oracle,
      abi: ORACLE_ABI,
      functionName: 'update',
      args: [navWei, riskBps],
    });
  };

  // Preset scenarios for quick demo
  const presets = [
    { name: 'Launch', nav: '1.00', risk: '10' },
    { name: 'Revenue', nav: '1.15', risk: '7' },
    { name: 'Stress', nav: '0.85', risk: '35' },
    { name: 'Recovery', nav: '1.30', risk: '4' },
  ];

  return (
    <div className="mt-8 bg-gray-800 rounded-lg p-6 border border-yellow-600">
      <h2 className="text-lg font-semibold mb-4 text-yellow-400">
        ⚡ Demo Controls (Oracle Update)
      </h2>

      {/* Warning if not updater */}
      {address && !isUpdater && (
        <div className="mb-4 p-3 bg-red-900 bg-opacity-30 border border-red-600 rounded">
          <div className="text-red-400 font-semibold">⚠️ Wrong Account</div>
          <div className="text-sm text-red-300 mt-1">
            You must use the oracle updater account:
          </div>
          <div className="text-xs font-mono text-red-200 mt-1 break-all">
            {ORACLE_UPDATER}
          </div>
          <div className="text-xs text-red-300 mt-2">
            This is Anvil's first test account (Account #0)
          </div>
        </div>
      )}

      <div className="grid grid-cols-2 gap-4 mb-4">
        <div>
          <label className="block text-sm text-gray-400 mb-1">NAV (USDC)</label>
          <input
            type="number"
            step="0.01"
            value={navInput}
            onChange={(e) => setNavInput(e.target.value)}
            className="w-full bg-gray-700 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-yellow-400"
          />
        </div>
        <div>
          <label className="block text-sm text-gray-400 mb-1">Risk (%)</label>
          <input
            type="number"
            value={riskInput}
            onChange={(e) => setRiskInput(e.target.value)}
            className="w-full bg-gray-700 rounded px-3 py-2 focus:outline-none focus:ring-2 focus:ring-yellow-400"
          />
        </div>
      </div>

      <div className="flex gap-2 mb-4">
        {presets.map((preset) => (
          <button
            key={preset.name}
            onClick={() => {
              setNavInput(preset.nav);
              setRiskInput(preset.risk);
            }}
            className="px-3 py-1 bg-gray-700 hover:bg-gray-600 rounded text-sm transition"
          >
            {preset.name}
          </button>
        ))}
      </div>

      <button
        onClick={handleUpdate}
        disabled={isLoading || !isUpdater}
        className="w-full bg-yellow-600 hover:bg-yellow-500 disabled:bg-gray-600 disabled:cursor-not-allowed rounded py-2 font-semibold transition"
      >
        {isLoading ? 'Updating...' : !isUpdater ? 'Wrong Account (Need Updater)' : 'Update Oracle'}
      </button>

      {isSuccess && (
        <p className="text-green-400 text-sm mt-2">✓ Oracle updated successfully!</p>
      )}
    </div>
  );
}

export default App;
