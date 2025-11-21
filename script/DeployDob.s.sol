// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

import {DobToken} from "../src/DobToken.sol";
import {DobOracle} from "../src/DobOracle.sol";
import {DobNodeLiquidityHook} from "../src/DobNodeLiquidityHook.sol";
import {LiquidNodeExample} from "../src/LiquidNodeExample.sol";
import {IDobOracle} from "../src/interfaces/IDobOracle.sol";
import {MockUSDC} from "../src/MockUSDC.sol";

/// @title DeployDob
/// @notice Deployment script for DobNodeLiquidity system
contract DeployDob is Script {
    // Base mainnet addresses
    address constant POOL_MANAGER_BASE = 0x498581fF718922c3f8e6A244956aF099B2652b2b;
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    // Deployment addresses (will be set during deployment)
    DobOracle public oracle;
    DobToken public dobToken;
    DobNodeLiquidityHook public hook;
    LiquidNodeExample public liquidNode;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer:", deployer);
        console.log("Pool Manager:", POOL_MANAGER_BASE);
        console.log("USDC:", USDC_BASE);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Oracle
        oracle = new DobOracle();
        console.log("Oracle deployed at:", address(oracle));

        // 2. Compute hook address with correct flags
        // Hook address must have specific bits set based on permissions
        // For beforeSwap + afterSwap: need bits for those flags
        bytes memory creationCode = type(DobNodeLiquidityHook).creationCode;
        bytes memory constructorArgs = abi.encode(
            IPoolManager(POOL_MANAGER_BASE),
            address(0), // placeholder for DobToken
            Currency.wrap(USDC_BASE),
            deployer,
            IDobOracle(address(oracle))
        );

        // For hackathon/testing, we'll deploy to a regular address
        // In production, you'd use CREATE2 to mine the correct hook address

        // 3. Deploy DobToken (placeholder hook address for now)
        address hookPlaceholder = address(0x1); // Will be updated
        dobToken = new DobToken(hookPlaceholder);
        console.log("DobToken deployed at:", address(dobToken));

        // Note: In production, you need to:
        // 1. Mine the correct hook address with CREATE2
        // 2. Deploy DobToken with correct hook address
        // 3. Deploy hook to the mined address

        // 4. Deploy Hook
        // This simplified version deploys to any address
        // Real deployment requires address mining
        /*
        hook = new DobNodeLiquidityHook(
            IPoolManager(POOL_MANAGER_BASE),
            dobToken,
            Currency.wrap(USDC_BASE),
            deployer,
            IDobOracle(address(oracle))
        );
        console.log("Hook deployed at:", address(hook));
        */

        // 5. Deploy LiquidNode
        liquidNode = new LiquidNodeExample(IDobOracle(address(oracle)));
        console.log("LiquidNode deployed at:", address(liquidNode));

        vm.stopBroadcast();

        // Log deployment summary
        console.log("\n=== Deployment Summary ===");
        console.log("Oracle:", address(oracle));
        console.log("DobToken:", address(dobToken));
        console.log("LiquidNode:", address(liquidNode));
        console.log("Note: Hook deployment requires address mining for correct permissions");
    }

    /// @notice Helper to create pool key
    function createPoolKey(address token0, address token1, address hookAddr)
        internal
        pure
        returns (PoolKey memory)
    {
        // Ensure token0 < token1
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }

        return PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000, // 0.3%
            tickSpacing: 60,
            hooks: IHooks(hookAddr)
        });
    }
}

/// @title DeployDobLocal
/// @notice Local/testnet deployment with mock addresses
contract DeployDobLocal is Script {
    function run() external {
        vm.startBroadcast();

        // Deploy Mock USDC
        MockUSDC usdc = new MockUSDC();
        console.log("MockUSDC:", address(usdc));

        // Deploy Oracle
        DobOracle oracle = new DobOracle();
        console.log("Oracle:", address(oracle));

        // For local testing, create mock token as hook placeholder
        address mockHook = address(0x1);
        DobToken dobToken = new DobToken(mockHook);
        console.log("DobToken:", address(dobToken));

        // Deploy LiquidNode
        LiquidNodeExample liquidNode = new LiquidNodeExample(IDobOracle(address(oracle)));
        console.log("LiquidNode:", address(liquidNode));

        console.log("\n=== Deployment Summary ===");
        console.log("MockUSDC:", address(usdc));
        console.log("Oracle:", address(oracle));
        console.log("DobToken:", address(dobToken));
        console.log("LiquidNode:", address(liquidNode));
        console.log("\nUpdate frontend/src/contracts.ts with these addresses");

        vm.stopBroadcast();
    }
}
