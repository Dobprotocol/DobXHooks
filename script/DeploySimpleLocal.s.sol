// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {DobToken} from "../src/DobToken.sol";
import {DobOracle} from "../src/DobOracle.sol";
import {LiquidNodeStabilizer} from "../src/LiquidNodeStabilizer.sol";
import {DobNodeLiquidityHookLocal} from "../src/DobNodeLiquidityHookLocal.sol";
import {IDobOracle} from "../src/interfaces/IDobOracle.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MockPoolManagerLocal} from "../src/mocks/MockPoolManagerLocal.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

/// @title DeploySimpleLocal
/// @notice Complete local deployment WITH hook using LocalBaseHook
contract DeploySimpleLocal is Script {
    function run() external {
        address deployer = msg.sender;

        console.log("\n=== Complete Local Deployment (With Hook) ===\n");

        vm.startBroadcast();

        // Step 1: Deploy Mock USDC
        console.log("1. Deploying MockUSDC...");
        MockUSDC usdc = new MockUSDC();
        console.log("   MockUSDC:", address(usdc));

        // Step 2: Deploy Oracle
        console.log("\n2. Deploying Oracle...");
        DobOracle oracle = new DobOracle();
        oracle.update(1e18, 1000); // NAV = $1.00, Risk = 10%
        console.log("   Oracle:", address(oracle));
        console.log("   Initial NAV: $1.00");
        console.log("   Initial Risk: 10%");

        // Step 3: Deploy Mock PoolManager
        console.log("\n3. Deploying MockPoolManagerLocal...");
        MockPoolManagerLocal poolManager = new MockPoolManagerLocal();
        console.log("   PoolManager:", address(poolManager));

        // Step 4: Deploy DOB Token
        console.log("\n4. Deploying DobToken...");
        DobToken dobToken = new DobToken(deployer); // Deployer can mint for testing
        console.log("   DobToken:", address(dobToken));

        // Step 5: Deploy Liquid Node Stabilizer
        console.log("\n5. Deploying LiquidNodeStabilizer...");
        LiquidNodeStabilizer liquidNode = new LiquidNodeStabilizer(
            IPoolManager(address(poolManager)),
            IDobOracle(address(oracle)),
            Currency.wrap(address(usdc)),
            Currency.wrap(address(dobToken)),
            deployer
        );
        console.log("   LiquidNode:", address(liquidNode));

        // Step 6: Deploy Hook (using LocalBaseHook - no address validation!)
        console.log("\n6. Deploying DobNodeLiquidityHookLocal...");
        DobNodeLiquidityHookLocal hook = new DobNodeLiquidityHookLocal(
            IPoolManager(address(poolManager)),
            liquidNode,
            IDobOracle(address(oracle)),
            Currency.wrap(address(usdc)),
            Currency.wrap(address(dobToken))
        );
        console.log("   Hook:", address(hook));

        // Step 7: Initialize Pool (WITH hook)
        console.log("\n7. Initializing Pool...");
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(usdc)) < Currency.wrap(address(dobToken))
                ? Currency.wrap(address(usdc))
                : Currency.wrap(address(dobToken)),
            currency1: Currency.wrap(address(usdc)) < Currency.wrap(address(dobToken))
                ? Currency.wrap(address(dobToken))
                : Currency.wrap(address(usdc)),
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: IHooks(address(hook)) // Use our hook!
        });

        uint160 sqrtPriceX96 = 79228162514264337593543950336; // 1:1 price
        poolManager.initialize(poolKey, sqrtPriceX96, "");
        console.log("   Pool initialized at 1:1 price");

        // Step 8: Add Initial Liquidity
        console.log("\n8. Adding Initial Liquidity...");
        uint256 usdcLiquidity = 100_000 * 1e6;
        uint256 dobLiquidity = 100_000 * 1e18;

        usdc.mint(deployer, usdcLiquidity);
        dobToken.mint(deployer, dobLiquidity);

        usdc.approve(address(poolManager), usdcLiquidity);
        dobToken.approve(address(poolManager), dobLiquidity);

        if (address(usdc) < address(dobToken)) {
            poolManager.addLiquidity(poolKey, usdcLiquidity, dobLiquidity);
        } else {
            poolManager.addLiquidity(poolKey, dobLiquidity, usdcLiquidity);
        }
        console.log("   Added: 100,000 USDC + 100,000 DOB");

        // Step 9: Fund Liquid Node
        console.log("\n9. Funding Liquid Node...");
        uint256 liquidNodeUSDC = 50_000 * 1e6;
        uint256 liquidNodeDOB = 50_000 * 1e18;

        usdc.mint(deployer, liquidNodeUSDC);
        dobToken.mint(deployer, liquidNodeDOB);

        usdc.approve(address(liquidNode), liquidNodeUSDC);
        dobToken.approve(address(liquidNode), liquidNodeDOB);

        liquidNode.fundUSDC(liquidNodeUSDC);
        liquidNode.fundDOB(liquidNodeDOB);
        console.log("   Funded: 50,000 USDC + 50,000 DOB");

        // Step 10: Give deployer test tokens
        console.log("\n10. Minting test tokens for deployer...");
        usdc.mint(deployer, 100_000 * 1e6); // Extra for testing
        dobToken.mint(deployer, 100_000 * 1e18);
        console.log("   Minted: 100,000 USDC + 100,000 DOB");

        vm.stopBroadcast();

        // Summary
        console.log("\n=== Deployment Complete ===\n");
        console.log("Contract Addresses:");
        console.log("-------------------");
        console.log("MockUSDC:        ", address(usdc));
        console.log("Oracle:          ", address(oracle));
        console.log("DobToken:        ", address(dobToken));
        console.log("PoolManager:     ", address(poolManager));
        console.log("LiquidNode:      ", address(liquidNode));
        console.log("Hook:            ", address(hook));

        console.log("\nPool Status:");
        console.log("------------");
        console.log("Initialized:      true");
        console.log("Initial Price:    1:1 (USDC/DOB)");
        console.log("Liquidity:        100k USDC + 100k DOB");

        console.log("\nLiquid Node:");
        console.log("------------");
        (uint256 usdcBal, uint256 dobBal) = liquidNode.getBalances();
        console.log("USDC:            ", usdcBal / 1e6);
        console.log("DOB:             ", dobBal / 1e18);

        console.log("\nYour Test Tokens:");
        console.log("-----------------");
        console.log("USDC:             100,000");
        console.log("DOB:              100,000");

        console.log("\nFeatures:");
        console.log("---------");
        console.log("- Pool with automatic stabilization hook");
        console.log("- Monitors price deviation from NAV");
        console.log("- Triggers Liquid Node when deviation > 5%");
        console.log("- 0.5% intervention fee");

        console.log("\nNext Steps:");
        console.log("-----------");
        console.log("1. Update frontend/src/contracts.ts with addresses above");
        console.log("2. Try swapping - hook monitors after each swap");
        console.log("3. Update oracle NAV to test stabilization");
        console.log("4. Check Liquid Node balances and fees earned");
    }
}
