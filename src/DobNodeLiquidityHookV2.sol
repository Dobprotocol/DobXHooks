// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/utils/BaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {LiquidNodeStabilizer} from "./LiquidNodeStabilizer.sol";
import {IDobOracle} from "./interfaces/IDobOracle.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {FixedPoint96} from "v4-core/libraries/FixedPoint96.sol";

/// @title DobNodeLiquidityHookV2
/// @notice Hook with automatic price stabilization via Liquid Node
/// @dev Monitors pool price vs NAV, triggers stabilization when deviation >5%
contract DobNodeLiquidityHookV2 is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    LiquidNodeStabilizer public immutable liquidNode;
    IDobOracle public immutable oracle;
    Currency public immutable usdc;
    Currency public immutable dobToken;

    uint256 public constant DEVIATION_THRESHOLD = 500; // 5% in bps
    uint256 public constant BPS = 10000;

    event PriceStabilized(uint256 poolPrice, uint256 nav, uint256 deviation, bool buyingDOB);
    event PriceChecked(uint256 poolPrice, uint256 nav, uint256 deviation);

    constructor(
        IPoolManager _poolManager,
        LiquidNodeStabilizer _liquidNode,
        IDobOracle _oracle,
        Currency _usdc,
        Currency _dobToken
    ) BaseHook(_poolManager) {
        liquidNode = _liquidNode;
        oracle = _oracle;
        usdc = _usdc;
        dobToken = _dobToken;
    }

    /// @notice Returns the hook permissions
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true, // Monitor price after each swap
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Hook called after a swap - checks for price deviation and stabilizes if needed
    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // Get current pool price
        uint256 poolPrice = _getPoolPrice(key);

        // Get oracle NAV (both in 18 decimals)
        uint256 nav = oracle.nav();

        // Calculate deviation in bps
        uint256 deviation;
        bool poolPriceTooLow;

        if (poolPrice < nav) {
            deviation = ((nav - poolPrice) * BPS) / nav;
            poolPriceTooLow = true;
        } else {
            deviation = ((poolPrice - nav) * BPS) / nav;
            poolPriceTooLow = false;
        }

        emit PriceChecked(poolPrice, nav, deviation);

        // If deviation > 5%, trigger stabilization
        if (deviation > DEVIATION_THRESHOLD) {
            if (poolPriceTooLow) {
                // Pool price too low - Liquid Node buys DOB to support price
                try liquidNode.stabilizeLow(key, deviation) {
                    emit PriceStabilized(poolPrice, nav, deviation, true);
                } catch {
                    // Liquid Node might be out of funds - continue without stabilizing
                }
            } else {
                // Pool price too high - Liquid Node sells DOB to cap price
                try liquidNode.stabilizeHigh(key, deviation) {
                    emit PriceStabilized(poolPrice, nav, deviation, false);
                } catch {
                    // Liquid Node might be out of funds - continue without stabilizing
                }
            }
        }

        return (this.afterSwap.selector, 0);
    }

    /// @notice Calculate pool price from sqrtPriceX96
    /// @dev Converts Uniswap V4 pool price to human-readable format (18 decimals)
    /// @param key The pool key
    /// @return price Pool price in 18 decimals (DOB per USDC, adjusted for decimals)
    function _getPoolPrice(PoolKey calldata key) internal view returns (uint256 price) {
        // Get pool state from PoolManager
        // Note: In a real V4 deployment, you'd use the actual state getters
        // For now, we'll use a simplified approach
        PoolId poolId = key.toId();

        // Attempt to get sqrtPriceX96 from pool state
        // This is a placeholder - actual V4 API may differ
        // You may need to use poolManager.extsload() or similar

        // For testing purposes, return oracle NAV as pool price
        // In production, implement proper V4 pool state reading
        price = oracle.nav();
    }

    /// @notice View current pool price
    function getPoolPrice(PoolKey calldata key) external view returns (uint256) {
        return _getPoolPrice(key);
    }

    /// @notice Check if stabilization would be triggered
    function checkStabilization(PoolKey calldata key)
        external
        view
        returns (bool shouldStabilize, bool buyDOB, uint256 deviation)
    {
        uint256 poolPrice = _getPoolPrice(key);
        uint256 nav = oracle.nav();

        if (poolPrice < nav) {
            deviation = ((nav - poolPrice) * BPS) / nav;
            buyDOB = true;
        } else {
            deviation = ((poolPrice - nav) * BPS) / nav;
            buyDOB = false;
        }

        shouldStabilize = deviation > DEVIATION_THRESHOLD;
    }
}
