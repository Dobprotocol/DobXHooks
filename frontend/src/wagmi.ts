import { http } from 'wagmi';
import { base, baseSepolia, localhost } from 'wagmi/chains';
import { getDefaultConfig } from '@rainbow-me/rainbowkit';

// Get WalletConnect project ID from environment variable
// Sign up at https://cloud.walletconnect.com to get your project ID
const projectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || '';

if (!projectId) {
  console.warn('⚠️ WalletConnect Project ID is not set. Rainbow wallet may not work properly on testnet/mainnet.');
  console.warn('Please set VITE_WALLETCONNECT_PROJECT_ID in your .env file.');
  console.warn('Get your project ID from https://cloud.walletconnect.com');
}

export const config = getDefaultConfig({
  appName: 'DOB Solar Farm 2035',
  projectId: projectId,
  chains: [localhost, baseSepolia, base],
  transports: {
    [localhost.id]: http('http://127.0.0.1:8545'),
    [baseSepolia.id]: http(),
    [base.id]: http(),
  },
});
