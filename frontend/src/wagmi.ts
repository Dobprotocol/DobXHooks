import { http } from 'wagmi';
import { base, baseSepolia, localhost } from 'wagmi/chains';
import { getDefaultConfig } from '@rainbow-me/rainbowkit';

export const config = getDefaultConfig({
  appName: 'DOB Solar Farm 2035',
  projectId: 'YOUR_WALLETCONNECT_PROJECT_ID', // Get from cloud.walletconnect.com
  chains: [localhost, baseSepolia, base],
  transports: {
    [localhost.id]: http('http://127.0.0.1:8545'),
    [baseSepolia.id]: http(),
    [base.id]: http(),
  },
});
