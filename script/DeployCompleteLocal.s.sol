// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {DobToken} from "../src/DobToken.sol";
import {DobOracle} from "../src/DobOracle.sol";
import {LiquidNodeStabilizer} from "../src/LiquidNodeStabilizer.sol";
import {DobNodeLiquidityHookV2} from "../src/DobNodeLiquidityHookV2.sol";
import {IDobOracle} from "../src/interfaces/IDobOracle.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {MockPoolManagerLocal} from "../src/mocks/MockPoolManagerLocal.sol";

/// @title DeployCompleteLocal
/// @notice Complete deployment for local testnet with pool initialization and liquidity
contract DeployCompleteLocal is Script {
    function run() external {
        address deployer = msg.sender;

        console.log("\n=== Starting Complete Local Deployment ===\n");

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

        // Step 4: Deploy DOB Token (with placeholder hook)
        console.log("\n4. Deploying DobToken...");
        DobToken dobToken = new DobToken(address(0x1)); // Temporary
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

        // Step 6: Deploy Hook (no address validation on local)
        console.log("\n6. Deploying DobNodeLiquidityHookV2...");
        DobNodeLiquidityHookV2 hook = new DobNodeLiquidityHookV2(
            IPoolManager(address(poolManager)),
            liquidNode,
            IDobOracle(address(oracle)),
            Currency.wrap(address(usdc)),
            Currency.wrap(address(dobToken))
        );
        console.log("   Hook:", address(hook));

        // Step 7: Initialize Pool
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
            hooks: IHooks(address(hook))
        });

        // Initial price: 1 USDC = 1 DOB (sqrtPriceX96 for 1:1)
        // sqrtPrice = sqrt(1) = 1, sqrtPriceX96 = 1 * 2^96
        uint160 sqrtPriceX96 = 79228162514264337593543950336; // sqrt(1) * 2^96

        poolManager.initialize(poolKey, sqrtPriceX96, "");
        console.log("   Pool initialized at 1:1 price");

        // Step 8: Add Initial Liquidity
        console.log("\n8. Adding Initial Liquidity...");
        uint256 usdcLiquidity = 100_000 * 1e6; // 100k USDC
        uint256 dobLiquidity = 100_000 * 1e18; // 100k DOB

        // Mint tokens for liquidity
        usdc.mint(deployer, usdcLiquidity);
        dobToken.mint(deployer, dobLiquidity);

        // Approve pool manager
        usdc.approve(address(poolManager), usdcLiquidity);
        dobToken.approve(address(poolManager), dobLiquidity);

        // Add liquidity (simplified - determine token order)
        if (address(usdc) < address(dobToken)) {
            poolManager.addLiquidity(poolKey, usdcLiquidity, dobLiquidity);
        } else {
            poolManager.addLiquidity(poolKey, dobLiquidity, usdcLiquidity);
        }
        console.log("   Added: 100,000 USDC + 100,000 DOB");

        // Step 9: Fund Liquid Node
        console.log("\n9. Funding Liquid Node...");
        uint256 liquidNodeUSDC = 50_000 * 1e6; // 50k USDC
        uint256 liquidNodeDOB = 50_000 * 1e18; // 50k DOB

        usdc.mint(deployer, liquidNodeUSDC);
        dobToken.mint(deployer, liquidNodeDOB);

        usdc.approve(address(liquidNode), liquidNodeUSDC);
        dobToken.approve(address(liquidNode), liquidNodeDOB);

        liquidNode.fundUSDC(liquidNodeUSDC);
        liquidNode.fundDOB(liquidNodeDOB);
        console.log("   Funded: 50,000 USDC + 50,000 DOB");

        // Step 10: Give deployer test tokens
        console.log("\n10. Minting test tokens for deployer...");
        usdc.mint(deployer, 10_000 * 1e6);
        dobToken.mint(deployer, 10_000 * 1e18);
        console.log("   Minted: 10,000 USDC + 10,000 DOB");

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
        bytes32 poolId = keccak256(abi.encode(poolKey));
        console.log("Pool ID:         ", uint256(poolId));
        console.log("Initialized:      true");
        console.log("Liquidity:        100k USDC + 100k DOB");

        console.log("\nLiquid Node Reserves:");
        console.log("--------------------");
        console.log("USDC:             50,000");
        console.log("DOB:              50,000");

        console.log("\nConfiguration:");
        console.log("--------------");
        console.log("Deviation Threshold: 5%");
        console.log("Intervention Fee:    0.5%");
        console.log("Pool Fee:            0.3%");

        console.log("\nNext Steps:");
        console.log("-----------");
        console.log("1. Update frontend/src/contracts.ts with addresses above");
        console.log("2. Run: cd frontend && npm run dev");
        console.log("3. Connect wallet and test trading");
        console.log("4. Try updating oracle to trigger stabilization");
    }
}
