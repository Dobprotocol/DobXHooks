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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DobToken} from "./DobToken.sol";
import {IDobOracle} from "./interfaces/IDobOracle.sol";

/// @title DobNodeLiquidityHook
/// @notice Uniswap V4 hook for RWA tokenized revenue streams with programmatic buyback
/// @dev Acts as infinite primary market + protected secondary market
contract DobNodeLiquidityHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using SafeERC20 for IERC20;

    DobToken public immutable dobToken;
    Currency public immutable usdc;
    address public immutable operator;
    IDobOracle public immutable oracle;

    uint24 public constant BASE_FEE = 1000; // 0.1% (in hundredths of bps)
    uint256 public constant MAX_SLIPPAGE_BPS = 500; // 5%
    uint256 public constant LIQUID_NODE_THRESHOLD_BPS = 500; // trigger LN if sell >5% of pool TVL
    uint256 public constant OPERATOR_SHARE = 99; // 99% to operator on buys

    // Events
    event Buy(address indexed buyer, uint256 usdcIn, uint256 dobMinted);
    event Sell(address indexed seller, uint256 dobIn, uint256 usdcOut, uint256 penaltyBps);

    // Errors
    error InsufficientLiquidity();
    error SlippageTooHigh();

    constructor(
        IPoolManager _poolManager,
        DobToken _dobToken,
        Currency _usdc,
        address _operator,
        IDobOracle _oracle
    ) BaseHook(_poolManager) {
        dobToken = _dobToken;
        usdc = _usdc;
        operator = _operator;
        oracle = _oracle;
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
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Hook called before a swap
    /// @dev Calculates dynamic fee based on sell size and risk
    function _beforeSwap(
        address,
        PoolKey calldata,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Only apply dynamic fee for sells (DOB → USDC)
        // zeroForOne = true means token0 → token1
        // We need to determine which is DOB and which is USDC based on pool setup

        if (params.amountSpecified < 0) {
            // Exact input swap (selling)
            uint256 amountIn = uint256(-params.amountSpecified);
            (, uint256 penaltyBps) = _calculateRedemption(amountIn);

            // Dynamic fee: base fee + penalty (capped at 10%)
            uint24 dynamicFee = uint24(BASE_FEE + (penaltyBps * 100)); // convert bps to fee units
            if (dynamicFee > 100000) dynamicFee = 100000; // max 10%

            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, dynamicFee);
        }

        return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, BASE_FEE);
    }

    /// @notice Hook called after a swap
    /// @dev Handles minting for buys and burning for sells
    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // Determine if this is a buy or sell based on direction
        // For buys (USDC → DOB): mint DOB and send USDC to operator
        // For sells (DOB → USDC): burn DOB and apply penalty

        // This is simplified logic - in production you'd need to:
        // 1. Properly identify token directions
        // 2. Handle the actual token transfers via PoolManager
        // 3. Integrate with Liquid Nodes for large sells

        return (IHooks.afterSwap.selector, 0);
    }

    /// @notice Calculate redemption value with penalty
    /// @param rwaAmount Amount of RWA tokens being sold
    /// @return usdcOut Amount of USDC to receive
    /// @return penaltyBps Penalty in basis points
    function _calculateRedemption(uint256 rwaAmount) internal view returns (uint256 usdcOut, uint256 penaltyBps) {
        uint256 nav = oracle.nav();
        uint256 risk = oracle.defaultRisk(); // in bps

        // Base penalty 3% + risk factor (risk/10)
        // e.g., 10% default risk = 3% + 1% = 4% penalty
        penaltyBps = 300 + risk / 10;

        // Cap penalty at 50%
        if (penaltyBps > 5000) penaltyBps = 5000;

        // Calculate output: amount * nav * (1 - penalty)
        // nav is in 1e18, so we divide by 1e18
        // penalty is in bps (10000 = 100%)
        usdcOut = (rwaAmount * nav * (10000 - penaltyBps)) / (1e18 * 10000);
    }

    /// @notice Get current NAV from oracle
    function getCurrentNav() external view returns (uint256) {
        return oracle.nav();
    }

    /// @notice Get current default risk from oracle
    function getDefaultRisk() external view returns (uint256) {
        return oracle.defaultRisk();
    }

    /// @notice Calculate expected output for a given input
    /// @param amountIn Amount of tokens to sell
    /// @return amountOut Expected output after fees
    /// @return penaltyBps Applied penalty in bps
    function quoteRedemption(uint256 amountIn) external view returns (uint256 amountOut, uint256 penaltyBps) {
        return _calculateRedemption(amountIn);
    }
}

// Import IHooks for selector
import {IHooks} from "v4-core/interfaces/IHooks.sol";
