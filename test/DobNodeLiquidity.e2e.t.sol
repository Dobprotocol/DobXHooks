// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {DobToken} from "../src/DobToken.sol";
import {DobOracle} from "../src/DobOracle.sol";
import {LiquidNodeExample} from "../src/LiquidNodeExample.sol";
import {IDobOracle} from "../src/interfaces/IDobOracle.sol";

/// @title Mock USDC for testing
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

/// @title DobNodeLiquidity End-to-End Test
/// @notice Demonstrates the complete workflow of the RWA liquidity system
/// @dev This test simulates the full investment lifecycle without requiring actual V4 pool
contract DobNodeLiquidityE2ETest is Test {
    // Contracts
    DobOracle public oracle;
    DobToken public dobToken;
    LiquidNodeExample public liquidNode;
    MockUSDC public usdc;

    // Test addresses
    address public operator = makeAddr("operator");
    address public hook = makeAddr("hook"); // Simulated hook address
    address public investor1 = makeAddr("investor1");
    address public investor2 = makeAddr("investor2");
    address public investor3 = makeAddr("investor3");

    // Constants matching the hook
    uint256 public constant OPERATOR_SHARE = 99; // 99% to operator on buys

    function setUp() public {
        // Deploy Oracle
        oracle = new DobOracle();
        console.log("Oracle deployed at:", address(oracle));

        // Deploy USDC mock
        usdc = new MockUSDC();
        console.log("USDC deployed at:", address(usdc));

        // Deploy DobToken with hook as minter
        dobToken = new DobToken(hook);
        console.log("DobToken deployed at:", address(dobToken));

        // Deploy Liquid Node
        liquidNode = new LiquidNodeExample(IDobOracle(address(oracle)));
        console.log("LiquidNode deployed at:", address(liquidNode));

        // Fund investors with USDC
        usdc.mint(investor1, 100_000e6);
        usdc.mint(investor2, 50_000e6);
        usdc.mint(investor3, 200_000e6);
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLETE WORKFLOW DEMONSTRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Main e2e test demonstrating the full investment lifecycle
    function test_E2E_CompleteWorkflow() public {
        console.log("\n");
        console.log("========================================");
        console.log("  DOB NODE LIQUIDITY - E2E WORKFLOW");
        console.log("========================================");

        // ============================================================
        // PHASE 1: PROJECT LAUNCH
        // ============================================================
        console.log("\n=== PHASE 1: PROJECT LAUNCH ===\n");

        console.log("Solar Farm 2035 project launches with:");
        console.log("- Initial NAV: 1.00 USDC per DOB token");
        console.log("- Default Risk: 10% (new project)");
        console.log("- Operator receives 99% of buy proceeds");

        assertEq(oracle.nav(), 1e18, "Initial NAV");
        assertEq(oracle.defaultRisk(), 1000, "Initial risk");

        // ============================================================
        // PHASE 2: FIRST INVESTORS ENTER
        // ============================================================
        console.log("\n=== PHASE 2: FIRST INVESTORS ENTER ===\n");

        // Investor 1 invests 10,000 USDC
        uint256 investment1 = 10_000e6;
        uint256 dobAmount1 = simulateBuy(investor1, investment1);

        console.log("Investor 1 buys in:");
        console.log("  USDC invested: ", investment1 / 1e6);
        console.log("  DOB received: ", dobAmount1 / 1e18);
        console.log("  To operator: ", (investment1 * OPERATOR_SHARE / 100) / 1e6, " USDC");

        // Investor 2 invests 5,000 USDC
        uint256 investment2 = 5_000e6;
        uint256 dobAmount2 = simulateBuy(investor2, investment2);

        console.log("\nInvestor 2 buys in:");
        console.log("  USDC invested: ", investment2 / 1e6);
        console.log("  DOB received: ", dobAmount2 / 1e18);

        console.log("\nTotal supply after initial investments: ", dobToken.totalSupply() / 1e18, " DOB");

        // ============================================================
        // PHASE 3: PROJECT GENERATES REVENUE
        // ============================================================
        console.log("\n=== PHASE 3: PROJECT GENERATES REVENUE ===\n");

        // Revenue event: NAV increases, risk decreases
        oracle.update(1.15e18, 700);

        console.log("Solar farm generates strong revenue!");
        console.log("  New NAV: 1.15 USDC (+15%)");
        console.log("  New Risk: 7% (improved outlook)");

        // Check investor positions
        (uint256 value1, uint256 penalty1) = calculateRedemption(dobAmount1);
        (uint256 value2, uint256 penalty2) = calculateRedemption(dobAmount2);

        console.log("\nPortfolio values:");
        console.log("  Investor 1:", value1 / 1e18, "USDC, penalty:", penalty1);
        console.log("  Investor 2:", value2 / 1e18, "USDC, penalty:", penalty2);

        // Verify gains
        assertGt(value1, investment1 * 1e12, "Investor 1 should have gains");

        // ============================================================
        // PHASE 4: NEW INVESTOR ENTERS AT HIGHER NAV
        // ============================================================
        console.log("\n=== PHASE 4: NEW INVESTOR AT HIGHER NAV ===\n");

        // Investor 3 enters at higher NAV
        uint256 investment3 = 20_000e6;
        uint256 dobAmount3 = simulateBuy(investor3, investment3);

        console.log("Investor 3 buys at NAV 1.15:");
        console.log("  USDC invested: ", investment3 / 1e6);
        console.log("  DOB received: ", dobAmount3 / 1e18);
        console.log("  (Fewer tokens due to higher NAV)");

        // Compare positions
        assertGt(dobAmount1 * investment3 / investment1, dobAmount3, "Early investors got more tokens per dollar");

        // ============================================================
        // PHASE 5: INVESTOR 1 TAKES PARTIAL PROFITS
        // ============================================================
        console.log("\n=== PHASE 5: INVESTOR 1 TAKES PROFITS ===\n");

        uint256 sellAmount1 = dobAmount1 / 2; // Sell half
        (uint256 exitValue1, uint256 exitPenalty1) = calculateRedemption(sellAmount1);

        console.log("Investor 1 sells 50% of position:");
        console.log("  DOB sold: ", sellAmount1 / 1e18);
        console.log("  USDC received: ", exitValue1 / 1e18);
        console.log("  Penalty paid:", exitPenalty1, "bps");

        // Simulate the burn
        vm.prank(hook);
        dobToken.burnFrom(investor1, sellAmount1);

        uint256 remaining1 = dobToken.balanceOf(investor1);
        console.log("  Remaining position:", remaining1 / 1e18, "DOB");

        // ============================================================
        // PHASE 6: ADVERSE EVENT - MARKET STRESS
        // ============================================================
        console.log("\n=== PHASE 6: ADVERSE EVENT ===\n");

        // Bad news: NAV drops, risk increases
        oracle.update(0.85e18, 3500);

        console.log("Equipment failure at solar farm!");
        console.log("  New NAV: 0.85 USDC (-26% from peak)");
        console.log("  New Risk: 35% (increased uncertainty)");

        // Check distressed values
        (uint256 distressed1, uint256 distressPenalty1) = calculateRedemption(remaining1);
        (uint256 distressed2, uint256 distressPenalty2) = calculateRedemption(dobAmount2);
        (uint256 distressed3, uint256 distressPenalty3) = calculateRedemption(dobAmount3);

        console.log("\nDistressed portfolio values:");
        console.log("  Investor 1:", distressed1 / 1e18, "USDC, penalty:", distressPenalty1);
        console.log("  Investor 2:", distressed2 / 1e18, "USDC, penalty:", distressPenalty2);
        console.log("  Investor 3:", distressed3 / 1e18, "USDC, penalty:", distressPenalty3);

        // ============================================================
        // PHASE 7: LIQUID NODE PROVIDES EMERGENCY EXIT
        // ============================================================
        console.log("\n=== PHASE 7: LIQUID NODE EMERGENCY EXIT ===\n");

        // Investor 2 wants immediate exit - check Liquid Node offer
        (uint256 nodeOffer, uint256 nodeFee) = liquidNode.quoteFromOracle(dobAmount2);

        console.log("Investor 2 considers emergency exit:");
        console.log("  Standard redemption: ", distressed2 / 1e18, " USDC");
        console.log("  Liquid Node offer: ", nodeOffer / 1e18, " USDC");
        console.log("  Liquid Node fee: ", nodeFee, " bps");

        if (nodeOffer > distressed2) {
            console.log("  => Liquid Node offers better rate!");
        } else {
            console.log("  => Standard redemption is better");
        }

        // Investor 2 exits via standard redemption
        vm.prank(hook);
        dobToken.burnFrom(investor2, dobAmount2);
        console.log("\nInvestor 2 exits position completely");

        // ============================================================
        // PHASE 8: PROJECT RECOVERS
        // ============================================================
        console.log("\n=== PHASE 8: PROJECT RECOVERS ===\n");

        // Project fixes issues and recovers
        oracle.update(1.30e18, 400);

        console.log("Solar farm repairs complete, strong Q4!");
        console.log("  New NAV: 1.30 USDC (+53% from distress)");
        console.log("  New Risk: 4% (very stable now)");

        // Check recovered values
        (uint256 recovered1, uint256 recoveryPenalty1) = calculateRedemption(remaining1);
        (uint256 recovered3, uint256 recoveryPenalty3) = calculateRedemption(dobAmount3);

        console.log("\nRecovered portfolio values:");
        console.log("  Investor 1:", recovered1 / 1e18, "USDC, penalty:", recoveryPenalty1);
        console.log("  Investor 3:", recovered3 / 1e18, "USDC, penalty:", recoveryPenalty3);

        // ============================================================
        // PHASE 9: FINAL EXITS
        // ============================================================
        console.log("\n=== PHASE 9: FINAL EXITS ===\n");

        // Investor 1 final exit
        vm.prank(hook);
        dobToken.burnFrom(investor1, remaining1);

        // Investor 3 final exit
        vm.prank(hook);
        dobToken.burnFrom(investor3, dobAmount3);

        console.log("All investors have exited");
        console.log("Final DOB supply: ", dobToken.totalSupply() / 1e18);

        assertEq(dobToken.totalSupply(), 0, "All tokens burned");

        // ============================================================
        // SUMMARY
        // ============================================================
        console.log("\n========================================");
        console.log("           INVESTMENT SUMMARY");
        console.log("========================================\n");

        console.log("Investor 1 (early, partial exit before crash):");
        console.log("  Initial: 10,000 USDC");
        console.log("  First exit: ", exitValue1 / 1e18, " USDC at NAV 1.15");
        console.log("  Final exit: ", recovered1 / 1e18, " USDC at NAV 1.30");
        uint256 total1 = (exitValue1 + recovered1) / 1e18;
        console.log("  Total received: ~", total1, " USDC");
        console.log("  Result: PROFIT (took profits before crash)");

        console.log("\nInvestor 2 (panic sold during crash):");
        console.log("  Initial: 5,000 USDC");
        console.log("  Exit: ", distressed2 / 1e18, " USDC at NAV 0.85");
        console.log("  Result: LOSS (sold at bottom)");

        console.log("\nInvestor 3 (bought high, held through crash):");
        console.log("  Initial: 20,000 USDC at NAV 1.15");
        console.log("  Exit: ", recovered3 / 1e18, " USDC at NAV 1.30");
        console.log("  Result: PROFIT (patient holding paid off)");

        console.log("\n========================================\n");
    }

    /// @notice Test demonstrating Liquid Node competitive dynamics
    function test_E2E_LiquidNodeDynamics() public {
        console.log("\n");
        console.log("========================================");
        console.log("  LIQUID NODE COMPETITIVE DYNAMICS");
        console.log("========================================");

        uint256 sellAmount = 50_000e18; // Large position

        console.log("\nLarge position exit: 50,000 DOB\n");

        // Test across different risk levels
        uint256[4] memory riskLevels = [uint256(500), 1500, 3000, 5000];
        string[4] memory riskLabels = ["Very Low (5%)", "Low (15%)", "Medium (30%)", "High (50%)"];

        for (uint256 i = 0; i < riskLevels.length; i++) {
            oracle.update(1e18, riskLevels[i]);

            (uint256 standardOut, uint256 standardPenalty) = calculateRedemption(sellAmount);
            (uint256 nodeOut, uint256 nodeFee) = liquidNode.quoteFromOracle(sellAmount);

            console.log("Risk Level:", riskLabels[i]);
            console.log("  Standard:", standardOut / 1e18, "USDC, penalty:", standardPenalty);
            console.log("  LiqNode:", nodeOut / 1e18, "USDC, fee:", nodeFee);

            if (nodeOut > standardOut) {
                console.log("  Winner: Liquid Node");
            } else {
                console.log("  Winner: Standard Redemption");
            }
            console.log("");
        }
    }

    /// @notice Test demonstrating penalty calculations across NAV levels
    function test_E2E_PenaltyMatrix() public {
        console.log("\n");
        console.log("========================================");
        console.log("    PENALTY MATRIX (1000 DOB sell)");
        console.log("========================================\n");

        uint256 sellAmount = 1000e18;

        uint256[5] memory navLevels = [uint256(0.5e18), 0.8e18, 1e18, 1.2e18, 2e18];
        uint256[5] memory riskLevels = [uint256(500), 1500, 3000, 4500, 6000];

        console.log("NAV (USDC) |  5%   |  15%  |  30%  |  45%  |  60%  |");
        console.log("-----------|-------|-------|-------|-------|-------|");

        for (uint256 i = 0; i < navLevels.length; i++) {
            string memory navStr;
            if (navLevels[i] == 0.5e18) navStr = "0.50";
            else if (navLevels[i] == 0.8e18) navStr = "0.80";
            else if (navLevels[i] == 1e18) navStr = "1.00";
            else if (navLevels[i] == 1.2e18) navStr = "1.20";
            else navStr = "2.00";

            console.log(navStr);

            for (uint256 j = 0; j < riskLevels.length; j++) {
                oracle.update(navLevels[i], riskLevels[j]);
                (uint256 output,) = calculateRedemption(sellAmount);
                // Just log the values - console.log doesn't support tables well
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Simulate a buy operation
    function simulateBuy(address investor, uint256 usdcAmount) internal returns (uint256 dobAmount) {
        // Calculate DOB to mint: 99% of USDC * 1e18 (convert to 18 decimals) / NAV
        uint256 effectiveUSDC = usdcAmount * OPERATOR_SHARE / 100;
        uint256 nav = oracle.nav();

        // Convert USDC (6 decimals) to DOB (18 decimals)
        dobAmount = (effectiveUSDC * 1e12 * 1e18) / nav;

        // Mint DOB tokens
        vm.prank(hook);
        dobToken.mint(investor, dobAmount);

        // In production, USDC would be transferred to operator
        return dobAmount;
    }

    /// @notice Calculate redemption value (matches hook logic)
    function calculateRedemption(uint256 rwaAmount) internal view returns (uint256 usdcOut, uint256 penaltyBps) {
        uint256 nav = oracle.nav();
        uint256 risk = oracle.defaultRisk();

        // Penalty = 300 + risk/10
        penaltyBps = 300 + risk / 10;
        if (penaltyBps > 5000) penaltyBps = 5000;

        // Output in 18 decimals (matching DOB)
        usdcOut = (rwaAmount * nav * (10000 - penaltyBps)) / (1e18 * 10000);
    }
}
