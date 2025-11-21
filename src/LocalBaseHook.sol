// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

/// @title LocalBaseHook
/// @notice Base hook for local testing - skips V4 address validation
/// @dev Use this instead of BaseHook for local/testnet deployments
abstract contract LocalBaseHook {
    error NotPoolManager();
    error NotSelf();
    error InvalidPool();
    error LockFailure();
    error HookNotImplemented();

    /// @notice The address of the pool manager
    IPoolManager public immutable poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
        // NOTE: Skipping validateHookAddress() for local testing
    }

    /// @dev Only the pool manager may call this function
    modifier poolManagerOnly() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    /// @dev Only this address may call this function
    modifier selfOnly() {
        if (msg.sender != address(this)) revert NotSelf();
        _;
    }

    function getHookPermissions() public pure virtual returns (Hooks.Permissions memory);
}
