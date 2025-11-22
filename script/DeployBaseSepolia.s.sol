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

/// @title DeployBaseSepolia
/// @notice Deployment script for Base Sepolia testnet
/// @dev Includes proper delays between transactions for testnet
contract DeployBaseSepolia is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n=== Base Sepolia Deployment ===");
        console.log("Deployer:", deployer);
        console.log("\n");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy Mock USDC (for testnet)
        console.log("1. Deploying MockUSDC...");
        MockUSDC usdc = new MockUSDC();
        console.log("   MockUSDC:", address(usdc));
        vm.sleep(2000); // Wait 2 seconds

        // Step 2: Deploy Oracle
        console.log("\n2. Deploying Oracle...");
        DobOracle oracle = new DobOracle();
        console.log("   Oracle:", address(oracle));
        vm.sleep(2000);

        // Initialize oracle
        console.log("   Initializing oracle...");
        oracle.update(1e18, 1000); // NAV = $1.00, Risk = 10%
        console.log("   Initial NAV: $1.00");
        console.log("   Initial Risk: 10%");
        vm.sleep(2000);

        // Step 3: Deploy Mock PoolManager (for testnet testing)
        console.log("\n3. Deploying MockPoolManagerLocal...");
        MockPoolManagerLocal poolManager = new MockPoolManagerLocal();
        console.log("   PoolManager:", address(poolManager));
        vm.sleep(2000);

        // Step 4: Deploy DOB Token
        console.log("\n4. Deploying DobToken...");
        DobToken dobToken = new DobToken(deployer);
        console.log("   DobToken:", address(dobToken));
        vm.sleep(2000);

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
        vm.sleep(2000);

        // Step 6: Deploy Hook
        console.log("\n6. Deploying DobNodeLiquidityHookLocal...");
        DobNodeLiquidityHookLocal hook = new DobNodeLiquidityHookLocal(
            IPoolManager(address(poolManager)),
            liquidNode,
            IDobOracle(address(oracle)),
            Currency.wrap(address(usdc)),
            Currency.wrap(address(dobToken))
        );
        console.log("   Hook:", address(hook));
        vm.sleep(2000);

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

        uint160 sqrtPriceX96 = 79228162514264337593543950336; // 1:1 price
        poolManager.initialize(poolKey, sqrtPriceX96, "");
        console.log("   Pool initialized at 1:1 price");
        vm.sleep(2000);

        // Step 8: Add Initial Liquidity
        console.log("\n8. Adding Initial Liquidity...");
        uint256 usdcLiquidity = 100_000 * 1e6;
        uint256 dobLiquidity = 100_000 * 1e18;

        console.log("   Minting tokens...");
        usdc.mint(deployer, usdcLiquidity);
        vm.sleep(2000);
        dobToken.mint(deployer, dobLiquidity);
        vm.sleep(2000);

        console.log("   Approving tokens...");
        usdc.approve(address(poolManager), usdcLiquidity);
        vm.sleep(2000);
        dobToken.approve(address(poolManager), dobLiquidity);
        vm.sleep(2000);

        console.log("   Adding liquidity...");
        if (address(usdc) < address(dobToken)) {
            poolManager.addLiquidity(poolKey, usdcLiquidity, dobLiquidity);
        } else {
            poolManager.addLiquidity(poolKey, dobLiquidity, usdcLiquidity);
        }
        console.log("   Added: 100,000 USDC + 100,000 DOB");
        vm.sleep(2000);

        // Step 9: Fund Liquid Node
        console.log("\n9. Funding Liquid Node...");
        uint256 liquidNodeUSDC = 50_000 * 1e6;
        uint256 liquidNodeDOB = 50_000 * 1e18;

        console.log("   Minting tokens...");
        usdc.mint(deployer, liquidNodeUSDC);
        vm.sleep(2000);
        dobToken.mint(deployer, liquidNodeDOB);
        vm.sleep(2000);

        console.log("   Approving tokens...");
        usdc.approve(address(liquidNode), liquidNodeUSDC);
        vm.sleep(2000);
        dobToken.approve(address(liquidNode), liquidNodeDOB);
        vm.sleep(2000);

        console.log("   Funding...");
        liquidNode.fundUSDC(liquidNodeUSDC);
        vm.sleep(2000);
        liquidNode.fundDOB(liquidNodeDOB);
        console.log("   Funded: 50,000 USDC + 50,000 DOB");
        vm.sleep(2000);

        // Step 10: Give deployer test tokens
        console.log("\n10. Minting test tokens for deployer...");
        usdc.mint(deployer, 100_000 * 1e6);
        vm.sleep(2000);
        dobToken.mint(deployer, 100_000 * 1e18);
        console.log("   Minted: 100,000 USDC + 100,000 DOB");

        vm.stopBroadcast();

        // Summary
        console.log("\n=== Deployment Complete ===\n");
        console.log("Network: Base Sepolia");
        console.log("Deployer:", deployer);
        console.log("\nContract Addresses:");
        console.log("-------------------");
        console.log("MockUSDC:        ", address(usdc));
        console.log("Oracle:          ", address(oracle));
        console.log("DobToken:        ", address(dobToken));
        console.log("PoolManager:     ", address(poolManager));
        console.log("LiquidNode:      ", address(liquidNode));
        console.log("Hook:            ", address(hook));

        console.log("\nUpdate these addresses in frontend/src/contracts.ts");

        console.log("\nBlockscout Explorer Links:");
        console.log("-------------------------");
        console.log("MockUSDC:         https://base-sepolia.blockscout.com/address/", address(usdc));
        console.log("Oracle:           https://base-sepolia.blockscout.com/address/", address(oracle));
        console.log("DobToken:         https://base-sepolia.blockscout.com/address/", address(dobToken));
        console.log("PoolManager:      https://base-sepolia.blockscout.com/address/", address(poolManager));
        console.log("LiquidNode:       https://base-sepolia.blockscout.com/address/", address(liquidNode));
        console.log("Hook:             https://base-sepolia.blockscout.com/address/", address(hook));

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

        console.log("\nFeatures:");
        console.log("---------");
        console.log("- Automatic stabilization when deviation > 5%");
        console.log("- 50% of reserves intervention");
        console.log("- 0.5% fee on interventions");
        console.log("- Max 1 nested call per transaction");
    }
}
