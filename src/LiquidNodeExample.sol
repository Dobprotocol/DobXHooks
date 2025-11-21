// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDobOracle} from "./interfaces/IDobOracle.sol";

/// @title LiquidNodeExample
/// @notice Permissionless competitive instant redemption liquidity provider
/// @dev Anyone can deploy these and register them to provide instant liquidity for large sells
contract LiquidNodeExample {
    address public owner;
    IDobOracle public oracle;

    // Minimum and maximum fee in basis points
    uint256 public constant MIN_FEE_BPS = 500;   // 5%
    uint256 public constant MAX_FEE_BPS = 3000;  // 30%

    // Risk thresholds for fee tiers
    uint256 public constant LOW_RISK_THRESHOLD = 1500;   // 15%
    uint256 public constant MED_RISK_THRESHOLD = 3000;   // 30%

    event QuoteProvided(uint256 rwaAmount, uint256 usdcProvided, uint256 feeBps);

    constructor(IDobOracle _oracle) {
        owner = msg.sender;
        oracle = _oracle;
    }

    /// @notice Get a quote for providing instant liquidity
    /// @param rwaAmount Amount of RWA tokens to redeem
    /// @param nav Current NAV (can be passed or fetched from oracle)
    /// @param defaultRisk Current default risk in bps
    /// @return usdcProvided Amount of USDC the node will provide
    /// @return feeBps Fee charged by the node in bps
    function quote(
        uint256 rwaAmount,
        uint256 nav,
        uint256 defaultRisk
    ) external pure returns (uint256 usdcProvided, uint256 feeBps) {
        // Fee based on risk level
        // Low risk (<15%): 5-8%
        // Med risk (15-30%): 8-15%
        // High risk (>30%): 15-30%
        if (defaultRisk <= LOW_RISK_THRESHOLD) {
            feeBps = MIN_FEE_BPS + (defaultRisk * 200 / LOW_RISK_THRESHOLD);
        } else if (defaultRisk <= MED_RISK_THRESHOLD) {
            feeBps = 800 + ((defaultRisk - LOW_RISK_THRESHOLD) * 700 / (MED_RISK_THRESHOLD - LOW_RISK_THRESHOLD));
        } else {
            feeBps = 1500 + ((defaultRisk - MED_RISK_THRESHOLD) * 1500 / (10000 - MED_RISK_THRESHOLD));
            if (feeBps > MAX_FEE_BPS) feeBps = MAX_FEE_BPS;
        }

        // Calculate USDC provided: amount * NAV * (1 - fee)
        usdcProvided = (rwaAmount * nav * (10000 - feeBps)) / (1e18 * 10000);
    }

    /// @notice Get a quote using current oracle values
    /// @param rwaAmount Amount of RWA tokens to redeem
    /// @return usdcProvided Amount of USDC the node will provide
    /// @return feeBps Fee charged by the node in bps
    function quoteFromOracle(uint256 rwaAmount) external view returns (uint256 usdcProvided, uint256 feeBps) {
        uint256 nav = oracle.nav();
        uint256 risk = oracle.defaultRisk();
        return this.quote(rwaAmount, nav, risk);
    }

    /// @notice Execute instant redemption (placeholder for full implementation)
    /// @dev In production, this would:
    /// 1. Verify the quote is still valid
    /// 2. Take RWA tokens from seller
    /// 3. Provide USDC to seller
    /// 4. Register the redemption for later settlement
    function executeRedemption(uint256 rwaAmount) external pure returns (bool) {
        // Placeholder - full implementation would handle actual token transfers
        rwaAmount; // silence unused variable warning
        return true;
    }
}
