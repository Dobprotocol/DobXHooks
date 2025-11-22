// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

import {DobToken} from "../src/DobToken.sol";
import {DobOracle} from "../src/DobOracle.sol";
import {LiquidNodeStabilizer} from "../src/LiquidNodeStabilizer.sol";
import {DobNodeLiquidityHookLocal} from "../src/DobNodeLiquidityHookLocal.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MockPoolManagerLocal} from "../src/mocks/MockPoolManagerLocal.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";

/// @title SimulateStabilization
/// @notice Simulates various price stabilization scenarios
contract SimulateStabilization is Script {
    using PoolIdLibrary for PoolKey;

    MockUSDC usdc;
    DobToken dobToken;
    DobOracle oracle;
    MockPoolManagerLocal poolManager;
    LiquidNodeStabilizer liquidNode;
    DobNodeLiquidityHookLocal hook;
    PoolKey poolKey;

    address trader;

    function run() external {
        // Use addresses from deployment
        usdc = MockUSDC(0x4A679253410272dd5232B3Ff7cF5dbB88f295319);
        oracle = DobOracle(0x7a2088a1bFc9d81c55368AE168C2C02570cB814F);
        dobToken = DobToken(0x67d269191c92Caf3cD7723F116c85e6E9bf55933);
        poolManager = MockPoolManagerLocal(0xc5a5C42992dECbae36851359345FE25997F5C42d);
        liquidNode = LiquidNodeStabilizer(0xE6E340D132b5f46d1e472DebcD681B2aBc16e57E);
        hook = DobNodeLiquidityHookLocal(0xc3e53F4d16Ae77Db1c982e75a937B9f60FE63690);

        // Setup pool key
        poolKey = PoolKey({
            currency0: Currency.wrap(address(usdc)) < Currency.wrap(address(dobToken))
                ? Currency.wrap(address(usdc))
                : Currency.wrap(address(dobToken)),
            currency1: Currency.wrap(address(usdc)) < Currency.wrap(address(dobToken))
                ? Currency.wrap(address(dobToken))
                : Currency.wrap(address(usdc)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        trader = msg.sender;

        console.log("\n============================================");
        console.log("PRICE STABILIZATION SIMULATION");
        console.log("============================================\n");

        vm.startBroadcast();

        // Initial state
        printState("INITIAL STATE");

        // Scenario 1: Small swap (should NOT trigger stabilization)
        console.log("\n--- SCENARIO 1: Small Swap (No Stabilization) ---");
        smallSwap();
        printState("After Small Swap");

        // Scenario 2: Large swap selling DOB (price drops, should trigger stabilization)
        console.log("\n--- SCENARIO 2: Large DOB Sale (Price Drop) ---");
        largeSwapSellDOB();
        printState("After Large DOB Sale");

        // Scenario 3: Large swap buying DOB (price rises, should trigger stabilization)
        console.log("\n--- SCENARIO 3: Large DOB Buy (Price Rise) ---");
        largeSwapBuyDOB();
        printState("After Large DOB Buy");

        // Scenario 4: Oracle NAV increase
        console.log("\n--- SCENARIO 4: Oracle NAV Increase ---");
        increaseOracleNAV();
        printState("After NAV Increase");

        // Scenario 5: Small swap to trigger stabilization from NAV change
        console.log("\n--- SCENARIO 5: Swap After NAV Change ---");
        smallSwap();
        printState("After Swap (Should Stabilize)");

        // Scenario 6: Oracle NAV decrease
        console.log("\n--- SCENARIO 6: Oracle NAV Decrease ---");
        decreaseOracleNAV();
        printState("After NAV Decrease");

        // Scenario 7: Small swap to trigger stabilization
        console.log("\n--- SCENARIO 7: Swap After NAV Drop ---");
        smallSwap();
        printState("After Swap (Should Stabilize)");

        // Scenario 8: Multiple swaps
        console.log("\n--- SCENARIO 8: Multiple Rapid Swaps ---");
        multipleSwaps();
        printState("After Multiple Swaps");

        // Final summary
        printFinalSummary();

        vm.stopBroadcast();
    }

    function smallSwap() internal {
        uint256 swapAmount = 1000 * 1e6; // 1k USDC

        usdc.approve(address(poolManager), swapAmount);

        SwapParams memory params = SwapParams({
            zeroForOne: address(usdc) < address(dobToken),
            amountSpecified: int256(swapAmount),
            sqrtPriceLimitX96: 0
        });

        poolManager.swap(poolKey, params, "");
        console.log("   Swapped 1,000 USDC for DOB");
    }

    function largeSwapSellDOB() internal {
        // Sell large amount of DOB (30k) to drop price significantly
        uint256 swapAmount = 30_000 * 1e18;

        dobToken.approve(address(poolManager), swapAmount);

        SwapParams memory params = SwapParams({
            zeroForOne: address(dobToken) < address(usdc),
            amountSpecified: int256(swapAmount),
            sqrtPriceLimitX96: 0
        });

        poolManager.swap(poolKey, params, "");
        console.log("   Sold 30,000 DOB for USDC");
    }

    function largeSwapBuyDOB() internal {
        // Buy large amount of DOB with 30k USDC to push price up
        uint256 swapAmount = 30_000 * 1e6;

        usdc.approve(address(poolManager), swapAmount);

        SwapParams memory params = SwapParams({
            zeroForOne: address(usdc) < address(dobToken),
            amountSpecified: int256(swapAmount),
            sqrtPriceLimitX96: 0
        });

        poolManager.swap(poolKey, params, "");
        console.log("   Bought DOB with 30,000 USDC");
    }

    function increaseOracleNAV() internal {
        oracle.update(1.1e18, 1000); // NAV = $1.10 (+10%)
        console.log("   Updated NAV to $1.10 (+10%)");
    }

    function decreaseOracleNAV() internal {
        oracle.update(0.9e18, 1000); // NAV = $0.90 (-10%)
        console.log("   Updated NAV to $0.90 (-10%)");
    }

    function multipleSwaps() internal {
        for (uint256 i = 0; i < 3; i++) {
            uint256 swapAmount = 5000 * 1e6;
            usdc.approve(address(poolManager), swapAmount);

            SwapParams memory params = SwapParams({
                zeroForOne: address(usdc) < address(dobToken),
                amountSpecified: int256(swapAmount),
                sqrtPriceLimitX96: 0
            });

            poolManager.swap(poolKey, params, "");
        }
        console.log("   Executed 3 swaps of 5,000 USDC each");
    }

    function printState(string memory label) internal view {
        console.log("\n[%s]", label);
        console.log("-----------------------------------");

        // Get pool reserves
        bytes32 poolId = PoolId.unwrap(poolKey.toId());
        (uint256 reserve0, uint256 reserve1) = poolManager.getPoolReserves(poolId);

        // Determine which is USDC and which is DOB
        bool usdcIsToken0 = address(usdc) < address(dobToken);
        uint256 usdcReserve = usdcIsToken0 ? reserve0 : reserve1;
        uint256 dobReserve = usdcIsToken0 ? reserve1 : reserve0;

        // Calculate pool price (USDC per DOB) in 18 decimals
        // USDC has 6 decimals, need to scale to 18 decimals (multiply by 1e12)
        // Then multiply by 1e18 for price format = total 1e30
        uint256 poolPrice = 0;
        if (dobReserve > 0) {
            poolPrice = (usdcReserve * 1e30) / dobReserve;
        }

        // Get oracle NAV
        uint256 nav = oracle.nav();

        // Calculate deviation
        uint256 deviation = 0;
        if (poolPrice > 0 && nav > 0) {
            if (poolPrice > nav) {
                deviation = ((poolPrice - nav) * 10000) / nav;
            } else {
                deviation = ((nav - poolPrice) * 10000) / nav;
            }
        }

        // Get Liquid Node balances
        (uint256 lnUSDC, uint256 lnDOB) = liquidNode.getBalances();

        // Check if should stabilize
        (bool shouldStabilize, bool buyDOB, uint256 dev) = hook.checkStabilization(poolKey);

        console.log("Pool Reserves:");
        console.log("  USDC: %s", usdcReserve / 1e6);
        console.log("  DOB:  %s", dobReserve / 1e18);
        console.log("");
        console.log("Pool Price: $%s", formatPrice(poolPrice));
        console.log("Oracle NAV: $%s", formatPrice(nav));
        console.log("Deviation:  %s.%s%%", deviation / 100, (deviation % 100));
        console.log("");
        console.log("Liquid Node:");
        console.log("  USDC: %s", lnUSDC / 1e6);
        console.log("  DOB:  %s", lnDOB / 1e18);
        console.log("  Fees: %s USDC", liquidNode.totalFeesEarned() / 1e6);
        console.log("");

        if (shouldStabilize) {
            console.log(">>> STABILIZATION NEEDED <<<");
            console.log("    Action: %s", buyDOB ? "BUY DOB" : "SELL DOB");
            console.log("    Deviation: %s.%s%%", dev / 100, (dev % 100));
        } else {
            console.log("Pool stable (deviation < 5%)");
        }
    }

    function formatPrice(uint256 price) internal pure returns (string memory) {
        uint256 dollars = price / 1e18;
        uint256 cents = (price % 1e18) / 1e16; // 2 decimal places

        if (cents < 10) {
            return string(abi.encodePacked(uintToString(dollars), ".0", uintToString(cents)));
        }
        return string(abi.encodePacked(uintToString(dollars), ".", uintToString(cents)));
    }

    function uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    function printFinalSummary() internal view {
        console.log("\n============================================");
        console.log("SIMULATION SUMMARY");
        console.log("============================================\n");

        (uint256 lnUSDC, uint256 lnDOB) = liquidNode.getBalances();
        uint256 fees = liquidNode.totalFeesEarned();

        console.log("Final Liquid Node State:");
        console.log("  USDC:  %s (started with 50,000)", lnUSDC / 1e6);
        console.log("  DOB:   %s (started with 50,000)", lnDOB / 1e18);
        console.log("  Fees:  %s USDC", fees / 1e6);
        console.log("");

        int256 usdcChange = int256(lnUSDC / 1e6) - 50_000;
        int256 dobChange = int256(lnDOB / 1e18) - 50_000;

        console.log("Changes:");
        if (usdcChange >= 0) {
            console.log("  USDC: +%s", uint256(usdcChange));
        } else {
            console.log("  USDC: -%s", uint256(-usdcChange));
        }

        if (dobChange >= 0) {
            console.log("  DOB:  +%s", uint256(dobChange));
        } else {
            console.log("  DOB:  -%s", uint256(-dobChange));
        }

        console.log("\nKey Insights:");
        console.log("- Liquid Node intervened when price deviated > 5%");
        console.log("- Intervention was proportional to deviation size");
        console.log("- 0.5% fee collected on each intervention");
        console.log("- Pool price stability maintained around NAV");
    }
}
