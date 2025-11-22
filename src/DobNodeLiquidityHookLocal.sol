// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LocalBaseHook} from "./LocalBaseHook.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {Currency, CurrencyLibrary} from "v4-core/types/Currency.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/types/PoolOperation.sol";
import {LiquidNodeStabilizer} from "./LiquidNodeStabilizer.sol";
import {IDobOracle} from "./interfaces/IDobOracle.sol";
import {console} from "forge-std/console.sol";
import {MockPoolManagerLocal} from "./mocks/MockPoolManagerLocal.sol";

/// @title DobNodeLiquidityHookLocal
/// @notice Local testing version of hook with automatic price stabilization
/// @dev Uses LocalBaseHook to bypass V4 address validation
contract DobNodeLiquidityHookLocal is LocalBaseHook, IHooks {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    LiquidNodeStabilizer public immutable liquidNode;
    IDobOracle public immutable oracle;
    Currency public immutable usdc;
    Currency public immutable dobToken;

    uint256 public constant DEVIATION_THRESHOLD = 500; // 5% in bps
    uint256 public constant BPS = 10000;
    uint256 public constant MIN_STABILIZATION_INTERVAL = 5; // seconds between stabilizations

    // Flag to prevent recursive stabilization (demo purposes)
    bool private isStabilizing;
    uint256 private lastStabilizationTime;

    event PriceStabilized(uint256 poolPrice, uint256 nav, uint256 deviation, bool buyingDOB);
    event PriceChecked(uint256 poolPrice, uint256 nav, uint256 deviation);

    constructor(
        IPoolManager _poolManager,
        LiquidNodeStabilizer _liquidNode,
        IDobOracle _oracle,
        Currency _usdc,
        Currency _dobToken
    ) LocalBaseHook(_poolManager) {
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

    // Stub implementations for unused hooks
    function beforeInitialize(address, PoolKey calldata, uint160) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterInitialize(address, PoolKey calldata, uint160, int24) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function beforeAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        bytes calldata
    ) external pure override returns (bytes4) {
        revert HookNotImplemented();
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external pure override returns (bytes4, BalanceDelta) {
        revert HookNotImplemented();
    }

    function beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        revert HookNotImplemented();
    }

    function beforeDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    function afterDonate(address, PoolKey calldata, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        revert HookNotImplemented();
    }

    /// @notice Hook called after a swap - checks for price deviation and stabilizes if needed
    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override poolManagerOnly returns (bytes4, int128) {
        return _afterSwap(sender, key, params, delta, hookData);
    }

    /// @notice Internal afterSwap implementation
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata,
        BalanceDelta,
        bytes calldata
    ) internal returns (bytes4, int128) {
        // DEMO FIX: Skip if already stabilizing to prevent nested recursion
        // This ensures at most 1 level of nesting per transaction
        if (isStabilizing) {
            console.log("[HOOK] Skipping - already stabilizing (prevents nesting)");
            return (this.afterSwap.selector, 0);
        }

        // Get current pool price
        uint256 poolPrice = _getPoolPrice(key);

        // Get oracle NAV (both in 18 decimals)
        uint256 nav = oracle.nav();

        // DEBUG: Log price and NAV
        console.log("[HOOK DEBUG] Pool Price (18 decimals):", poolPrice);
        console.log("[HOOK DEBUG] Oracle NAV (18 decimals):", nav);

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

        console.log("[HOOK DEBUG] Deviation (bps):", deviation);
        console.log("[HOOK DEBUG] Threshold (bps):", DEVIATION_THRESHOLD);
        if (deviation > DEVIATION_THRESHOLD) {
            console.log("[HOOK DEBUG] STABILIZATION TRIGGERED");
        }

        emit PriceChecked(poolPrice, nav, deviation);

        // If deviation > 5%, trigger stabilization
        if (deviation > DEVIATION_THRESHOLD) {
            // DEMO FIX: Set flag and timestamp before stabilization
            isStabilizing = true;
            lastStabilizationTime = block.timestamp;

            if (poolPriceTooLow) {
                // Pool price too low - Liquid Node buys DOB to support price
                console.log("[HOOK] Calling stabilizeLow...");
                try liquidNode.stabilizeLow(key, deviation) {
                    console.log("[HOOK] stabilizeLow SUCCESS");
                    emit PriceStabilized(poolPrice, nav, deviation, true);
                } catch Error(string memory reason) {
                    console.log("[HOOK] stabilizeLow FAILED:", reason);
                } catch (bytes memory lowLevelData) {
                    console.log("[HOOK] stabilizeLow FAILED with low-level error");
                    console.logBytes(lowLevelData);
                }
            } else {
                // Pool price too high - Liquid Node sells DOB to cap price
                console.log("[HOOK] Calling stabilizeHigh...");
                try liquidNode.stabilizeHigh(key, deviation) {
                    console.log("[HOOK] stabilizeHigh SUCCESS");
                    emit PriceStabilized(poolPrice, nav, deviation, false);
                } catch Error(string memory reason) {
                    console.log("[HOOK] stabilizeHigh FAILED:", reason);
                } catch (bytes memory lowLevelData) {
                    console.log("[HOOK] stabilizeHigh FAILED with low-level error");
                    console.logBytes(lowLevelData);
                }
            }

            // DEMO FIX: Clear flag after stabilization completes
            isStabilizing = false;
        }

        return (this.afterSwap.selector, 0);
    }

    /// @notice Calculate pool price from reserves
    /// @dev Gets actual price from MockPoolManagerLocal reserves
    /// @param key The pool key
    /// @return price Pool price in 18 decimals (USDC per DOB)
    function _getPoolPrice(PoolKey calldata key) internal view returns (uint256 price) {
        bytes32 poolId = bytes32(PoolId.unwrap(key.toId()));

        // Get reserves from MockPoolManagerLocal
        (uint256 reserve0, uint256 reserve1) = MockPoolManagerLocal(address(poolManager)).getPoolReserves(poolId);

        // DEBUG: Log raw reserves
        console.log("[PRICE DEBUG] Reserve0:", reserve0);
        console.log("[PRICE DEBUG] Reserve1:", reserve1);

        // Determine which is USDC and which is DOB
        bool usdcIsToken0 = Currency.unwrap(usdc) < Currency.unwrap(dobToken);
        uint256 usdcReserve = usdcIsToken0 ? reserve0 : reserve1;
        uint256 dobReserve = usdcIsToken0 ? reserve1 : reserve0;

        console.log("[PRICE DEBUG] USDC Reserve (6 decimals):", usdcReserve);
        console.log("[PRICE DEBUG] DOB Reserve (18 decimals):", dobReserve);

        // Calculate price (USDC per DOB) in 18 decimals
        // USDC has 6 decimals, DOB has 18 decimals
        if (dobReserve == 0) {
            console.log("[PRICE DEBUG] ERROR: DOB Reserve is ZERO");
            return 0;
        }

        // price = (usdcReserve * 1e18) / dobReserve, adjust for USDC decimals
        // Formula: (usdcReserve * 1e12 * 1e18) / dobReserve = (usdcReserve * 1e30) / dobReserve
        price = (usdcReserve * 1e30) / dobReserve;

        console.log("[PRICE DEBUG] Calculated Price (18 decimals):", price);
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

    /// @notice Manually trigger stabilization (for demo purposes)
    function manualStabilize(PoolKey calldata key) external {
        console.log("[HOOK] Manual stabilization called");

        // Get current pool price
        uint256 poolPrice = _getPoolPrice(key);
        uint256 nav = oracle.nav();

        // Calculate deviation
        uint256 deviation;
        bool poolPriceTooLow;

        if (poolPrice < nav) {
            deviation = ((nav - poolPrice) * BPS) / nav;
            poolPriceTooLow = true;
        } else {
            deviation = ((poolPrice - nav) * BPS) / nav;
            poolPriceTooLow = false;
        }

        console.log("[HOOK] Manual stabilization - Deviation:", deviation);
        console.log("[HOOK] Manual stabilization - Threshold:", DEVIATION_THRESHOLD);

        if (deviation > DEVIATION_THRESHOLD) {
            if (poolPriceTooLow) {
                console.log("[HOOK] Manual stabilizeLow...");
                try liquidNode.stabilizeLow(key, deviation) {
                    console.log("[HOOK] Manual stabilizeLow SUCCESS");
                    emit PriceStabilized(poolPrice, nav, deviation, true);
                } catch Error(string memory reason) {
                    console.log("[HOOK] Manual stabilizeLow FAILED:", reason);
                } catch (bytes memory lowLevelData) {
                    console.log("[HOOK] Manual stabilizeLow FAILED with low-level error");
                    console.logBytes(lowLevelData);
                }
            } else {
                console.log("[HOOK] Manual stabilizeHigh...");
                try liquidNode.stabilizeHigh(key, deviation) {
                    console.log("[HOOK] Manual stabilizeHigh SUCCESS");
                    emit PriceStabilized(poolPrice, nav, deviation, false);
                } catch Error(string memory reason) {
                    console.log("[HOOK] Manual stabilizeHigh FAILED:", reason);
                } catch (bytes memory lowLevelData) {
                    console.log("[HOOK] Manual stabilizeHigh FAILED with low-level error");
                    console.logBytes(lowLevelData);
                }
            }
        } else {
            console.log("[HOOK] Manual stabilization skipped - deviation below threshold");
        }
    }
}
