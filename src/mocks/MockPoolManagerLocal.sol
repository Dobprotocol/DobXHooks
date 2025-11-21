// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title MockPoolManagerLocal
/// @notice Simplified PoolManager for local testing with basic AMM logic
/// @dev Implements constant product formula (x * y = k) for swaps
contract MockPoolManagerLocal {
    using PoolIdLibrary for PoolKey;

    struct Pool {
        uint256 reserve0;
        uint256 reserve1;
        uint160 sqrtPriceX96;
        bool initialized;
    }

    mapping(bytes32 => Pool) public pools;

    event PoolInitialized(bytes32 indexed poolId, uint160 sqrtPriceX96);
    event LiquidityAdded(bytes32 indexed poolId, uint256 amount0, uint256 amount1);
    event Swap(bytes32 indexed poolId, bool zeroForOne, uint256 amountIn, uint256 amountOut);

    /// @notice Initialize a new pool
    function initialize(PoolKey calldata key, uint160 sqrtPriceX96, bytes calldata hookData)
        external
        returns (int24)
    {
        bytes32 poolId = PoolId.unwrap(key.toId());
        require(!pools[poolId].initialized, "Pool already initialized");

        pools[poolId] = Pool({
            reserve0: 0,
            reserve1: 0,
            sqrtPriceX96: sqrtPriceX96,
            initialized: true
        });

        emit PoolInitialized(poolId, sqrtPriceX96);

        // Call hook if present (simplified - skip for local testing)
        // if (address(key.hooks) != address(0)) {
        //     try IHooks(address(key.hooks)).afterInitialize(...) {}
        //     catch {}
        // }

        return 0;
    }

    /// @notice Add liquidity to pool
    function addLiquidity(
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1
    ) external returns (uint256, uint256) {
        bytes32 poolId = PoolId.unwrap(key.toId());
        require(pools[poolId].initialized, "Pool not initialized");

        // Transfer tokens from sender
        IERC20(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), amount0);
        IERC20(Currency.unwrap(key.currency1)).transferFrom(msg.sender, address(this), amount1);

        // Update reserves
        pools[poolId].reserve0 += amount0;
        pools[poolId].reserve1 += amount1;

        emit LiquidityAdded(poolId, amount0, amount1);

        return (amount0, amount1);
    }

    /// @notice Execute a swap (simplified constant product AMM)
    function swap(PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        returns (BalanceDelta)
    {
        bytes32 poolId = PoolId.unwrap(key.toId());
        Pool storage pool = pools[poolId];
        require(pool.initialized, "Pool not initialized");

        uint256 amountIn;
        uint256 amountOut;
        int256 amount0Delta;
        int256 amount1Delta;

        // Simplified - skip beforeSwap for local testing
        // if (address(key.hooks) != address(0)) {
        //     try IHooks(address(key.hooks)).beforeSwap(...) {}
        //     catch {}
        // }

        // Determine swap direction and calculate output
        if (params.zeroForOne) {
            // Swapping token0 for token1
            amountIn = params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

            // Constant product: (x + Δx)(y - Δy) = k
            // Δy = (y * Δx) / (x + Δx)
            amountOut = (pool.reserve1 * amountIn) / (pool.reserve0 + amountIn);

            // Apply 0.3% fee
            amountOut = (amountOut * 997) / 1000;

            // Update reserves
            pool.reserve0 += amountIn;
            pool.reserve1 -= amountOut;

            amount0Delta = int256(amountIn);
            amount1Delta = -int256(amountOut);

            // Transfer tokens
            IERC20(Currency.unwrap(key.currency0)).transferFrom(msg.sender, address(this), amountIn);
            IERC20(Currency.unwrap(key.currency1)).transfer(msg.sender, amountOut);
        } else {
            // Swapping token1 for token0
            amountIn = params.amountSpecified < 0 ? uint256(-params.amountSpecified) : uint256(params.amountSpecified);

            amountOut = (pool.reserve0 * amountIn) / (pool.reserve1 + amountIn);
            amountOut = (amountOut * 997) / 1000;

            pool.reserve1 += amountIn;
            pool.reserve0 -= amountOut;

            amount0Delta = -int256(amountOut);
            amount1Delta = int256(amountIn);

            IERC20(Currency.unwrap(key.currency1)).transferFrom(msg.sender, address(this), amountIn);
            IERC20(Currency.unwrap(key.currency0)).transfer(msg.sender, amountOut);
        }

        emit Swap(poolId, params.zeroForOne, amountIn, amountOut);

        BalanceDelta delta = toBalanceDelta(int128(amount0Delta), int128(amount1Delta));

        // Call afterSwap hook to trigger price stabilization
        if (address(key.hooks) != address(0)) {
            try IHooks(address(key.hooks)).afterSwap(msg.sender, key, params, delta, hookData) {}
            catch {}
        }

        return delta;
    }

    /// @notice Get pool reserves
    function getPoolReserves(bytes32 poolId) external view returns (uint256 reserve0, uint256 reserve1) {
        Pool storage pool = pools[poolId];
        return (pool.reserve0, pool.reserve1);
    }

    /// @notice Get pool price
    function getPoolPrice(bytes32 poolId) external view returns (uint256) {
        Pool storage pool = pools[poolId];
        if (pool.reserve0 == 0) return 0;
        // Price = reserve1 / reserve0 (in token1 per token0)
        return (pool.reserve1 * 1e18) / pool.reserve0;
    }

    /// @notice Check if pool is initialized
    function isPoolInitialized(bytes32 poolId) external view returns (bool) {
        return pools[poolId].initialized;
    }
}
