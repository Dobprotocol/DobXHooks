// Contract addresses - update these after deployment
export const CONTRACTS = {
  usdc: '0x0000000000000000000000000000000000000000' as `0x${string}`,
  oracle: '0x5FbDB2315678afecb367f032d93F642f64180aa3' as `0x${string}`,
  dobToken: '0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512' as `0x${string}`,
  liquidNode: '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0' as `0x${string}`,
} as const;

// ABIs
export const ORACLE_ABI = [
  {
    inputs: [],
    name: 'nav',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'defaultRisk',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: '_nav', type: 'uint256' },
      { name: '_defaultRisk', type: 'uint256' },
    ],
    name: 'update',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const;

export const DOB_TOKEN_ABI = [
  {
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'totalSupply',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'symbol',
    outputs: [{ type: 'string' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

export const LIQUID_NODE_ABI = [
  {
    inputs: [{ name: 'rwaAmount', type: 'uint256' }],
    name: 'quoteFromOracle',
    outputs: [
      { name: 'usdcProvided', type: 'uint256' },
      { name: 'feeBps', type: 'uint256' },
    ],
    stateMutability: 'view',
    type: 'function',
  },
] as const;

export const USDC_ABI = [
  {
    inputs: [{ name: 'account', type: 'address' }],
    name: 'balanceOf',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    name: 'approve',
    outputs: [{ type: 'bool' }],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    name: 'allowance',
    outputs: [{ type: 'uint256' }],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'faucet',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'decimals',
    outputs: [{ type: 'uint8' }],
    stateMutability: 'view',
    type: 'function',
  },
] as const;
