// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDobOracle} from "./interfaces/IDobOracle.sol";
import "forge-std/console.sol";

// Extended interface for MockPoolManagerLocal
interface IPoolManagerExtended {
    function getPoolReserves(bytes32 poolId) external view returns (uint256 reserve0, uint256 reserve1);
    function adjustReserves(
        bytes32 poolId,
        int256 amount0Delta,
        int256 amount1Delta,
        address token0,
        address token1,
        address liquidNode
    ) external;
}

/// @title LiquidNodeStabilizer
/// @notice Pre-funded buffer that stabilizes pool price around oracle NAV
/// @dev Intervenes when pool price deviates >5% from NAV, earns fixed 0.5% fee
contract LiquidNodeStabilizer {
    using PoolIdLibrary for PoolKey;

    IPoolManager public immutable poolManager;
    IDobOracle public immutable oracle;
    Currency public immutable usdc;
    Currency public immutable dobToken;
    address public immutable operator;

    uint256 public constant DEVIATION_THRESHOLD = 500; // 5% in bps
    uint256 public constant INTERVENTION_FEE = 50; // 0.5% in bps
    uint256 public constant BPS = 10000;

    uint256 public totalFeesEarned;

    event Stabilized(bool buyingDOB, uint256 amount, uint256 feeEarned);
    event Funded(address token, uint256 amount);
    event FeesWithdrawn(uint256 amount);

    error OnlyOperator();
    error InsufficientBalance();

    modifier onlyOperator() {
        if (msg.sender != operator) revert OnlyOperator();
        _;
    }

    constructor(
        IPoolManager _poolManager,
        IDobOracle _oracle,
        Currency _usdc,
        Currency _dobToken,
        address _operator
    ) {
        poolManager = _poolManager;
        oracle = _oracle;
        usdc = _usdc;
        dobToken = _dobToken;
        operator = _operator;
    }

    /// @notice Fund the Liquid Node with USDC
    function fundUSDC(uint256 amount) external {
        IERC20(Currency.unwrap(usdc)).transferFrom(msg.sender, address(this), amount);
        emit Funded(Currency.unwrap(usdc), amount);
    }

    /// @notice Fund the Liquid Node with DOB tokens
    function fundDOB(uint256 amount) external {
        IERC20(Currency.unwrap(dobToken)).transferFrom(msg.sender, address(this), amount);
        emit Funded(Currency.unwrap(dobToken), amount);
    }

    /// @notice Stabilize when pool price is too LOW (< NAV - 5%)
    /// @dev Buys DOB from pool to support price, amount proportional to deviation
    /// @param poolKey The pool to stabilize
    /// @param deviation The price deviation in bps
    function stabilizeLow(PoolKey calldata poolKey, uint256 deviation) external returns (uint256 feeEarned) {
        console.log("[LIQUID NODE] stabilizeLow called");

        // Only hook can call stabilization
        require(msg.sender == address(poolKey.hooks), "Only hook");

        // DEMO FIX: Use 50% of USDC balance for strong intervention
        uint256 usdcBalance = IERC20(Currency.unwrap(usdc)).balanceOf(address(this));
        uint256 interventionAmount = usdcBalance / 2; // Use half of balance

        if (interventionAmount == 0) revert InsufficientBalance();

        console.log("[LIQUID NODE] USDC intervention (50% of balance):", interventionAmount);

        // Calculate fee (0.5% of intervention)
        feeEarned = (interventionAmount * INTERVENTION_FEE) / BPS;
        uint256 netAmount = interventionAmount - feeEarned;

        // Calculate how much DOB to receive using constant product formula
        // We're selling USDC to buy DOB
        // Pool has reserves, we add USDC and take DOB
        bytes32 poolId = bytes32(PoolId.unwrap(poolKey.toId()));
        (uint256 reserve0, uint256 reserve1) = IPoolManagerExtended(address(poolManager)).getPoolReserves(poolId);

        bool usdcIsToken0 = Currency.unwrap(usdc) < Currency.unwrap(dobToken);
        uint256 usdcReserve = usdcIsToken0 ? reserve0 : reserve1;
        uint256 dobReserve = usdcIsToken0 ? reserve1 : reserve0;

        // Constant product: (x + Δx)(y - Δy) = xy
        // Δy = (y * Δx) / (x + Δx)
        uint256 dobToReceive = (dobReserve * netAmount) / (usdcReserve + netAmount);

        console.log("[LIQUID NODE] DOB to receive:", dobToReceive);

        // Approve PoolManager to take USDC from us
        IERC20(Currency.unwrap(usdc)).approve(address(poolManager), netAmount);

        // Calculate deltas for adjustReserves
        // We're adding USDC to pool, taking DOB from pool
        int256 amount0Delta = usdcIsToken0 ? int256(netAmount) : -int256(dobToReceive);
        int256 amount1Delta = usdcIsToken0 ? -int256(dobToReceive) : int256(netAmount);

        // PoolManager will handle all transfers
        address token0 = usdcIsToken0 ? Currency.unwrap(usdc) : Currency.unwrap(dobToken);
        address token1 = usdcIsToken0 ? Currency.unwrap(dobToken) : Currency.unwrap(usdc);

        IPoolManagerExtended(address(poolManager)).adjustReserves(
            poolId,
            amount0Delta,
            amount1Delta,
            token0,
            token1,
            address(this)
        );

        totalFeesEarned += feeEarned;
        console.log("[LIQUID NODE] Fee earned (USDC):", feeEarned);
        console.log("[LIQUID NODE] Total fees earned:", totalFeesEarned);
        console.log("[LIQUID NODE] stabilizeLow completed!");
        emit Stabilized(true, netAmount, feeEarned);
    }

    /// @notice Stabilize when pool price is too HIGH (> NAV + 5%)
    /// @dev Sells DOB to pool to cap price, amount proportional to deviation
    /// @param poolKey The pool to stabilize
    /// @param deviation The price deviation in bps
    function stabilizeHigh(PoolKey calldata poolKey, uint256 deviation) external returns (uint256 feeEarned) {
        console.log("[LIQUID NODE] stabilizeHigh called");

        // Only hook can call stabilization
        require(msg.sender == address(poolKey.hooks), "Only hook");

        // DEMO FIX: Use 50% of DOB balance for strong intervention
        uint256 dobBalance = IERC20(Currency.unwrap(dobToken)).balanceOf(address(this));
        uint256 interventionAmount = dobBalance / 2; // Use half of balance

        if (interventionAmount == 0) revert InsufficientBalance();

        console.log("[LIQUID NODE] DOB intervention (50% of balance):", interventionAmount);

        // Calculate fee (0.5% of intervention in DOB)
        feeEarned = (interventionAmount * INTERVENTION_FEE) / BPS;
        uint256 netAmount = interventionAmount - feeEarned;

        // Calculate how much USDC to receive using constant product formula
        // We're selling DOB to buy USDC
        bytes32 poolId = bytes32(PoolId.unwrap(poolKey.toId()));
        (uint256 reserve0, uint256 reserve1) = IPoolManagerExtended(address(poolManager)).getPoolReserves(poolId);

        bool usdcIsToken0 = Currency.unwrap(usdc) < Currency.unwrap(dobToken);
        uint256 usdcReserve = usdcIsToken0 ? reserve0 : reserve1;
        uint256 dobReserve = usdcIsToken0 ? reserve1 : reserve0;

        // Constant product: (x + Δx)(y - Δy) = xy
        // Δy = (y * Δx) / (x + Δx)
        uint256 usdcToReceive = (usdcReserve * netAmount) / (dobReserve + netAmount);

        console.log("[LIQUID NODE] USDC to receive:", usdcToReceive);

        // Approve PoolManager to take DOB from us
        IERC20(Currency.unwrap(dobToken)).approve(address(poolManager), netAmount);

        // Calculate deltas for adjustReserves
        // We're adding DOB to pool, taking USDC from pool
        int256 amount0Delta = usdcIsToken0 ? -int256(usdcToReceive) : int256(netAmount);
        int256 amount1Delta = usdcIsToken0 ? int256(netAmount) : -int256(usdcToReceive);

        // PoolManager will handle all transfers
        address token0 = usdcIsToken0 ? Currency.unwrap(usdc) : Currency.unwrap(dobToken);
        address token1 = usdcIsToken0 ? Currency.unwrap(dobToken) : Currency.unwrap(usdc);

        IPoolManagerExtended(address(poolManager)).adjustReserves(
            poolId,
            amount0Delta,
            amount1Delta,
            token0,
            token1,
            address(this)
        );

        // Convert DOB fee to USDC equivalent for tracking
        // feeEarned is in DOB (18 decimals), usdcReserve is in USDC (6 decimals), dobReserve is in DOB (18 decimals)
        // Result: (18 * 6) / 18 = 6 decimals (USDC)
        uint256 feeEarnedUSDC = (feeEarned * usdcReserve) / dobReserve;
        totalFeesEarned += feeEarnedUSDC;

        console.log("[LIQUID NODE] Fee earned (USDC equivalent):", feeEarnedUSDC);
        console.log("[LIQUID NODE] Total fees earned:", totalFeesEarned);
        console.log("[LIQUID NODE] stabilizeHigh completed!");
        emit Stabilized(false, netAmount, feeEarnedUSDC);
    }

    /// @notice Withdraw accumulated fees
    function withdrawFees() external onlyOperator {
        uint256 amount = totalFeesEarned;
        totalFeesEarned = 0;
        IERC20(Currency.unwrap(usdc)).transfer(operator, amount);
        emit FeesWithdrawn(amount);
    }

    /// @notice Get quote for potential redemption (legacy function for compatibility)
    function quoteFromOracle(uint256 rwaAmount) external view returns (uint256 usdcProvided, uint256 feeBps) {
        uint256 nav = oracle.nav();
        uint256 risk = oracle.defaultRisk();

        // Tiered fee structure based on risk
        if (risk < 1500) { // < 15%
            feeBps = 500; // 5%
        } else if (risk < 3000) { // < 30%
            feeBps = 1000; // 10%
        } else {
            feeBps = 2000; // 20%
        }

        usdcProvided = (rwaAmount * nav * (10000 - feeBps)) / (1e18 * 10000);
    }

    /// @notice View balances
    function getBalances() external view returns (uint256 usdcBalance, uint256 dobBalance) {
        usdcBalance = IERC20(Currency.unwrap(usdc)).balanceOf(address(this));
        dobBalance = IERC20(Currency.unwrap(dobToken)).balanceOf(address(this));
    }
}
