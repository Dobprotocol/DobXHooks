// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface ILiquidNode {
    function getBalances() external view returns (uint256, uint256);
    function totalFeesEarned() external view returns (uint256);
}

interface IHook {
    function getPoolPrice(PoolKey calldata key) external view returns (uint256);
}

contract TestReserveChanges is Script {
    // Contract addresses from frontend
    /*address constant USDC = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address constant DOB_TOKEN = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9;
    address constant POOL_MANAGER = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;
    address constant LIQUID_NODE = 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707;
    address constant HOOK = 0x0165878A594ca255338adfa4d48449f69242Eb8F;
export const CONTRACTS = {
  usdc: '0x8642584cf29245D7020D798484e94564D40dd3CE' as `0x${string}`,
  oracle: '0x125fD0A6474f03DE4e2D13d6CfA789Bc4FBB8b94' as `0x${string}`,
  dobToken: '0x52805E85b9C0FacDd97F085FdfE55eCa338EB893' as `0x${string}`,
  poolManager: '0x3296717bF2399E7d605a6d974b4917de7c663727' as `0x${string}`,
  liquidNode: '0x5e98ec31DE7d005146828D942C3306AE028c5f59' as `0x${string}`,
  hook: '0x24C6079Ba44f2484050CE3A6E51b16eBEF717419' as `0x${string}`,
} as const;


*/  
    address constant USDC = 0x8642584cf29245D7020D798484e94564D40dd3CE;
    address constant DOB_TOKEN = 0x52805E85b9C0FacDd97F085FdfE55eCa338EB893;
    address constant POOL_MANAGER = 0x3296717bF2399E7d605a6d974b4917de7c663727;
    address constant LIQUID_NODE = 0x5e98ec31DE7d005146828D942C3306AE028c5f59;
    address constant HOOK = 0x24C6079Ba44f2484050CE3A6E51b16eBEF717419;
    function run() external {
        uint256 deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n========================================");
        console.log("RESERVE CHANGE SIMULATION TEST");
        console.log("========================================\n");

        // Check initial state
        console.log("=== INITIAL STATE ===");
        logReserves();
        logPoolPrice();

        vm.startBroadcast(deployerPrivateKey);

        // Mint some USDC to deployer for testing
        console.log("\n=== MINTING TEST USDC ===");
        (bool success,) = USDC.call(abi.encodeWithSignature("mint(address,uint256)", deployer, 10000 * 1e6));
        require(success, "Mint failed");

        uint256 usdcBalance = IERC20(USDC).balanceOf(deployer);
        console.log("Deployer USDC Balance:", usdcBalance / 1e6);

        // Approve pool manager
        IERC20(USDC).approve(POOL_MANAGER, type(uint256).max);
        IERC20(DOB_TOKEN).approve(POOL_MANAGER, type(uint256).max);
        console.log("Approvals set");

        // Perform a LARGE swap to trigger stabilization (> 5% deviation)
        console.log("\n=== EXECUTING LARGE SWAP: 8000 USDC -> DOB ===");
        console.log("(This should cause > 5% deviation and trigger stabilization)");

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(USDC),
            currency1: Currency.wrap(DOB_TOKEN),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(HOOK)
        });

        bool zeroForOne = USDC < DOB_TOKEN;
        int256 amountSpecified = -8000 * 1e6; // Large swap: 8000 USDC

        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: 0
        });

        (bool swapSuccess,) = POOL_MANAGER.call(
            abi.encodeWithSignature(
                "swap((address,address,uint24,int24,address),(bool,int256,uint160),bytes)",
                poolKey,
                params,
                ""
            )
        );

        if (swapSuccess) {
            console.log("Swap executed successfully!");
        } else {
            console.log("Swap failed!");
        }

        vm.stopBroadcast();

        // Check state after swap
        console.log("\n=== STATE AFTER SWAP ===");
        logReserves();
        logPoolPrice();

        console.log("\n========================================");
        console.log("TEST COMPLETE");
        console.log("========================================\n");
    }

    function logReserves() internal view {
        (uint256 usdcBalance, uint256 dobBalance) = ILiquidNode(LIQUID_NODE).getBalances();
        uint256 fees = ILiquidNode(LIQUID_NODE).totalFeesEarned();

        console.log("Liquid Node Reserves:");
        console.log("  USDC:", usdcBalance / 1e6);
        console.log("  DOB:", dobBalance / 1e18);
        console.log("  Fees Earned:", fees / 1e6, "USDC");
    }

    function logPoolPrice() internal view {
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(USDC),
            currency1: Currency.wrap(DOB_TOKEN),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(HOOK)
        });

        try IHook(HOOK).getPoolPrice(poolKey) returns (uint256 price) {
            console.log("Pool Price (18 decimals):", price);
            console.log("Pool Price (human):", price / 1e18);
        } catch {
            console.log("Failed to get pool price");
        }
    }
}
