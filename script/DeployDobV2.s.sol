// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {DobToken} from "../src/DobToken.sol";
import {DobOracle} from "../src/DobOracle.sol";
import {LiquidNodeStabilizer} from "../src/LiquidNodeStabilizer.sol";
import {DobNodeLiquidityHookV2} from "../src/DobNodeLiquidityHookV2.sol";
import {IDobOracle} from "../src/interfaces/IDobOracle.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

/// @title DeployDobV2Local
/// @notice Deployment for stabilization-enabled system
contract DeployDobV2Local is Script {
    // Mock PoolManager address for local testing
    // In production, use real deployed PoolManager address
    address constant MOCK_POOL_MANAGER = address(0x1234567890123456789012345678901234567890);

    function run() external {
        address deployer = msg.sender;
        vm.startBroadcast();

        // 1. Deploy Mock USDC
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC:", address(usdc));

        // 2. Deploy Oracle
        DobOracle oracle = new DobOracle();
        console.log("Oracle:", address(oracle));

        // 3. Deploy DOB Token (with temporary hook address)
        DobToken dobToken = new DobToken(address(0x1));
        console.log("DobToken:", address(dobToken));

        // 4. Deploy Liquid Node Stabilizer
        LiquidNodeStabilizer liquidNode = new LiquidNodeStabilizer(
            IPoolManager(MOCK_POOL_MANAGER),
            IDobOracle(address(oracle)),
            Currency.wrap(address(usdc)),
            Currency.wrap(address(dobToken)),
            deployer // operator
        );
        console.log("LiquidNodeStabilizer:", address(liquidNode));

        // 5. Deploy Hook V2
        DobNodeLiquidityHookV2 hook = new DobNodeLiquidityHookV2(
            IPoolManager(MOCK_POOL_MANAGER),
            liquidNode,
            IDobOracle(address(oracle)),
            Currency.wrap(address(usdc)),
            Currency.wrap(address(dobToken))
        );
        console.log("HookV2:", address(hook));

        // 6. Fund Liquid Node with test tokens
        uint256 fundingUSDC = 100_000 * 1e6; // 100k USDC
        uint256 fundingDOB = 50_000 * 1e18; // 50k DOB

        // Mint USDC to deployer and fund Liquid Node
        usdc.mint(deployer, fundingUSDC);
        usdc.approve(address(liquidNode), fundingUSDC);
        liquidNode.fundUSDC(fundingUSDC);

        // Mint DOB to deployer and fund Liquid Node
        // Note: DobToken has hook-only mint, so we'd need to update it
        // For now, skip DOB funding in this script

        console.log("\n=== Deployment Summary ===");
        console.log("MockUSDC:", address(usdc));
        console.log("Oracle:", address(oracle));
        console.log("DobToken:", address(dobToken));
        console.log("LiquidNodeStabilizer:", address(liquidNode));
        console.log("HookV2:", address(hook));
        console.log("\nLiquid Node funded with:", fundingUSDC / 1e6, "USDC");

        console.log("\n=== Configuration ===");
        console.log("Deviation Threshold: 5%");
        console.log("Intervention Fee: 0.5%");
        console.log("Stabilization: Proportional to deviation");

        console.log("\n=== Next Steps ===");
        console.log("1. Update frontend/src/contracts.ts with these addresses");
        console.log("2. For production: Deploy to network with real Uniswap V4 PoolManager");
        console.log("3. Initialize pool with hook using PoolManager");
        console.log("4. Add initial liquidity to the pool");
        console.log("5. Fund Liquid Node with DOB tokens");

        vm.stopBroadcast();
    }
}
