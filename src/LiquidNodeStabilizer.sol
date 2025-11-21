// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDobOracle} from "./interfaces/IDobOracle.sol";

/// @title LiquidNodeStabilizer
/// @notice Pre-funded buffer that stabilizes pool price around oracle NAV
/// @dev Intervenes when pool price deviates >5% from NAV, earns fixed 0.5% fee
contract LiquidNodeStabilizer {
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
        // Only hook can call stabilization
        require(msg.sender == address(poolKey.hooks), "Only hook");

        // Calculate intervention amount proportional to deviation
        // More deviation = bigger intervention
        uint256 usdcBalance = IERC20(Currency.unwrap(usdc)).balanceOf(address(this));
        uint256 interventionAmount = (usdcBalance * deviation) / (BPS * 10); // Use up to 10% of balance per deviation point

        if (interventionAmount > usdcBalance) {
            interventionAmount = usdcBalance;
        }

        if (interventionAmount == 0) revert InsufficientBalance();

        // Calculate fee (0.5% of intervention)
        feeEarned = (interventionAmount * INTERVENTION_FEE) / BPS;
        uint256 swapAmount = interventionAmount - feeEarned;

        // Approve PoolManager to spend USDC
        IERC20(Currency.unwrap(usdc)).approve(address(poolManager), swapAmount);

        // Execute swap: USDC → DOB (buy DOB to support price)
        bool zeroForOne = Currency.unwrap(usdc) < Currency.unwrap(dobToken);

        poolManager.swap(
            poolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(swapAmount), // Exact input
                sqrtPriceLimitX96: zeroForOne ? 4295128739 : 1461446703485210103287273052203988822378723970342 // Min/max price
            }),
            ""
        );

        totalFeesEarned += feeEarned;
        emit Stabilized(true, swapAmount, feeEarned);
    }

    /// @notice Stabilize when pool price is too HIGH (> NAV + 5%)
    /// @dev Sells DOB to pool to cap price, amount proportional to deviation
    /// @param poolKey The pool to stabilize
    /// @param deviation The price deviation in bps
    function stabilizeHigh(PoolKey calldata poolKey, uint256 deviation) external returns (uint256 feeEarned) {
        // Only hook can call stabilization
        require(msg.sender == address(poolKey.hooks), "Only hook");

        // Calculate intervention amount proportional to deviation
        uint256 dobBalance = IERC20(Currency.unwrap(dobToken)).balanceOf(address(this));
        uint256 interventionAmount = (dobBalance * deviation) / (BPS * 10); // Use up to 10% of balance per deviation point

        if (interventionAmount > dobBalance) {
            interventionAmount = dobBalance;
        }

        if (interventionAmount == 0) revert InsufficientBalance();

        // Approve PoolManager to spend DOB
        IERC20(Currency.unwrap(dobToken)).approve(address(poolManager), interventionAmount);

        // Execute swap: DOB → USDC (sell DOB to cap price)
        bool zeroForOne = Currency.unwrap(dobToken) < Currency.unwrap(usdc);

        poolManager.swap(
            poolKey,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: -int256(interventionAmount), // Exact input
                sqrtPriceLimitX96: zeroForOne ? 4295128739 : 1461446703485210103287273052203988822378723970342 // Min/max price
            }),
            ""
        );

        // Fee is earned in USDC after selling
        uint256 usdcReceived = IERC20(Currency.unwrap(usdc)).balanceOf(address(this));
        feeEarned = (usdcReceived * INTERVENTION_FEE) / BPS;

        totalFeesEarned += feeEarned;
        emit Stabilized(false, interventionAmount, feeEarned);
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
