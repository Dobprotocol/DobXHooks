# Base Sepolia Deployment Setup Guide

## 1. Get Alchemy API Key

1. Go to [Alchemy](https://www.alchemy.com/)
2. Sign up / Log in
3. Click "Create New App"
4. Select:
   - Chain: **Base**
   - Network: **Base Sepolia (Testnet)**
5. Copy your API key

Your RPC URL will be:
```
https://base-sepolia.g.alchemy.com/v2/YOUR-API-KEY
```

## 2. Get Etherscan API Key (for verification)

**IMPORTANT:** Use **Etherscan.io** (not BaseScan) - the V2 API works across all chains!

1. Go to [Etherscan.io](https://etherscan.io/)
2. Sign up / Log in
3. Go to [API Keys](https://etherscan.io/myapikey) section
4. Create a new API key
5. Copy it

This single Etherscan API key works for all chains including Base Sepolia.

## 3. Create .env File

Copy the example and fill in your keys:

```bash
cp .env.example .env
```

Then edit `.env` and add:
- Your Alchemy API key in `BASE_SEPOLIA_RPC_URL`
- Your **Etherscan** API key (V2) in `BASESCAN_API_KEY`
- Your deployment private key in `PRIVATE_KEY`

**Example .env:**
```bash
BASE_SEPOLIA_RPC_URL=https://base-sepolia.g.alchemy.com/v2/abc123def456
BASESCAN_API_KEY=XYZ789ABC123
PRIVATE_KEY=your-private-key-without-0x-prefix
```

**Note:** Despite the variable name, use your Etherscan.io API key (not BaseScan) due to the V2 API migration.

## 4. Get Test ETH

You need Base Sepolia ETH for gas fees:

1. Go to [Base Sepolia Faucet](https://www.alchemy.com/faucets/base-sepolia)
2. Enter your wallet address
3. Request testnet ETH

Or use the [Coinbase Faucet](https://portal.cdp.coinbase.com/products/faucet)

## 5. Load Environment Variables

```bash
source .env
```

Or for automatic loading with every command:
```bash
# Add to your shell profile (~/.bashrc or ~/.zshrc)
export $(grep -v '^#' .env | xargs)
```

## 6. Test Connection

```bash
cast block-number --rpc-url $BASE_SEPOLIA_RPC_URL
```

Should return the latest Base Sepolia block number.

## 7. Check Your Balance

```bash
cast balance YOUR_ADDRESS --rpc-url $BASE_SEPOLIA_RPC_URL
```

## 8. Deploy

Use your deployment script:

```bash
forge script script/DeployBaseSepolia.s.sol:DeployBaseSepolia \
  --rpc-url base_sepolia \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

Or if you have the script already:
```bash
./redeploy_and_test.sh
```

## 9. Verify Manually (if needed)

If auto-verification fails:

```bash
forge verify-contract \
  CONTRACT_ADDRESS \
  src/YourContract.sol:YourContract \
  --chain base-sepolia \
  --etherscan-api-key $BASESCAN_API_KEY
```

## Security Notes

⚠️ **NEVER commit `.env` to git!** (Already added to `.gitignore`)

⚠️ **Use a separate wallet for testnet deployments** - don't use your main wallet

⚠️ **Keep your private keys secure** - don't share them or paste them in public channels

## Useful Links

- [Base Sepolia Explorer](https://sepolia.basescan.org/)
- [Alchemy Dashboard](https://dashboard.alchemy.com/)
- [Base Docs](https://docs.base.org/)
- [Foundry Book](https://book.getfoundry.sh/)
