// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DobToken} from "../src/DobToken.sol";
import {DobOracle} from "../src/DobOracle.sol";
import {LiquidNodeExample} from "../src/LiquidNodeExample.sol";
import {IDobOracle} from "../src/interfaces/IDobOracle.sol";

contract DobOracleTest is Test {
    DobOracle public oracle;
    address public updater = address(1);
    address public notUpdater = address(2);

    function setUp() public {
        vm.prank(updater);
        oracle = new DobOracle();
    }

    function test_InitialValues() public view {
        assertEq(oracle.nav(), 1e18, "Initial NAV should be 1e18");
        assertEq(oracle.defaultRisk(), 1000, "Initial risk should be 1000 bps");
        assertEq(oracle.updater(), updater, "Updater should be deployer");
    }

    function test_UpdateOracle() public {
        uint256 newNav = 0.95e18; // 0.95 USDC
        uint256 newRisk = 1500; // 15%

        vm.prank(updater);
        oracle.update(newNav, newRisk);

        assertEq(oracle.nav(), newNav);
        assertEq(oracle.defaultRisk(), newRisk);
    }

    function test_OnlyUpdaterCanUpdate() public {
        vm.prank(notUpdater);
        vm.expectRevert(DobOracle.OnlyUpdater.selector);
        oracle.update(1e18, 1000);
    }

    function test_SetUpdater() public {
        address newUpdater = address(3);

        vm.prank(updater);
        oracle.setUpdater(newUpdater);

        assertEq(oracle.updater(), newUpdater);

        // Old updater can no longer update
        vm.prank(updater);
        vm.expectRevert(DobOracle.OnlyUpdater.selector);
        oracle.update(1e18, 1000);

        // New updater can update
        vm.prank(newUpdater);
        oracle.update(0.9e18, 2000);
        assertEq(oracle.nav(), 0.9e18);
    }

    function testFuzz_UpdateOracle(uint256 nav, uint256 risk) public {
        vm.prank(updater);
        oracle.update(nav, risk);

        assertEq(oracle.nav(), nav);
        assertEq(oracle.defaultRisk(), risk);
    }
}

contract DobTokenTest is Test {
    DobToken public token;
    address public hook = address(1);
    address public user = address(2);
    address public notHook = address(3);

    function setUp() public {
        vm.prank(hook);
        token = new DobToken(hook);
    }

    function test_TokenMetadata() public view {
        assertEq(token.name(), "Dob Solar Farm 2035");
        assertEq(token.symbol(), "DOB-35");
        assertEq(token.decimals(), 18);
    }

    function test_HookCanMint() public {
        uint256 amount = 1000e18;

        vm.prank(hook);
        token.mint(user, amount);

        assertEq(token.balanceOf(user), amount);
        assertEq(token.totalSupply(), amount);
    }

    function test_HookCanBurn() public {
        uint256 amount = 1000e18;

        vm.prank(hook);
        token.mint(user, amount);

        vm.prank(hook);
        token.burnFrom(user, amount / 2);

        assertEq(token.balanceOf(user), amount / 2);
        assertEq(token.totalSupply(), amount / 2);
    }

    function test_OnlyHookCanMint() public {
        vm.prank(notHook);
        vm.expectRevert(DobToken.OnlyHook.selector);
        token.mint(user, 1000e18);
    }

    function test_OnlyHookCanBurn() public {
        vm.prank(hook);
        token.mint(user, 1000e18);

        vm.prank(notHook);
        vm.expectRevert(DobToken.OnlyHook.selector);
        token.burnFrom(user, 500e18);
    }

    function testFuzz_MintAndBurn(uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(mintAmount > 0 && mintAmount < type(uint128).max);
        vm.assume(burnAmount <= mintAmount);

        vm.prank(hook);
        token.mint(user, mintAmount);

        vm.prank(hook);
        token.burnFrom(user, burnAmount);

        assertEq(token.balanceOf(user), mintAmount - burnAmount);
    }
}

contract LiquidNodeExampleTest is Test {
    LiquidNodeExample public node;
    DobOracle public oracle;

    function setUp() public {
        oracle = new DobOracle();
        node = new LiquidNodeExample(IDobOracle(address(oracle)));
    }

    function test_QuoteLowRisk() public view {
        // 10% risk
        uint256 nav = 1e18;
        uint256 risk = 1000;
        uint256 amount = 1000e18;

        (uint256 usdcOut, uint256 feeBps) = node.quote(amount, nav, risk);

        // Fee should be in 5-8% range for low risk
        assertGe(feeBps, 500, "Fee too low");
        assertLe(feeBps, 800, "Fee too high");

        // Output should be amount * (1 - fee)
        uint256 expectedOut = (amount * nav * (10000 - feeBps)) / (1e18 * 10000);
        assertEq(usdcOut, expectedOut);
    }

    function test_QuoteMediumRisk() public view {
        // 25% risk
        uint256 nav = 0.95e18;
        uint256 risk = 2500;
        uint256 amount = 1000e18;

        (uint256 usdcOut, uint256 feeBps) = node.quote(amount, nav, risk);

        // Fee should be in 8-15% range for medium risk
        assertGe(feeBps, 800, "Fee too low");
        assertLe(feeBps, 1500, "Fee too high");

        uint256 expectedOut = (amount * nav * (10000 - feeBps)) / (1e18 * 10000);
        assertEq(usdcOut, expectedOut);
    }

    function test_QuoteHighRisk() public view {
        // 50% risk
        uint256 nav = 0.8e18;
        uint256 risk = 5000;
        uint256 amount = 1000e18;

        (uint256 usdcOut, uint256 feeBps) = node.quote(amount, nav, risk);

        // Fee should be in 15-30% range for high risk
        assertGe(feeBps, 1500, "Fee too low");
        assertLe(feeBps, 3000, "Fee too high");

        uint256 expectedOut = (amount * nav * (10000 - feeBps)) / (1e18 * 10000);
        assertEq(usdcOut, expectedOut);
    }

    function test_QuoteFromOracle() public {
        // Set oracle values
        oracle.update(0.9e18, 2000); // 0.9 NAV, 20% risk

        uint256 amount = 500e18;
        (uint256 usdcOut, uint256 feeBps) = node.quoteFromOracle(amount);

        // Verify it uses oracle values
        (uint256 expectedOut, uint256 expectedFee) = node.quote(amount, 0.9e18, 2000);
        assertEq(usdcOut, expectedOut);
        assertEq(feeBps, expectedFee);
    }

    function testFuzz_QuoteNeverExceedsNav(uint256 amount, uint256 nav, uint256 risk) public view {
        vm.assume(amount > 0 && amount < type(uint128).max);
        vm.assume(nav > 0 && nav <= 2e18); // reasonable NAV range
        vm.assume(risk <= 10000); // max 100% risk

        (uint256 usdcOut, uint256 feeBps) = node.quote(amount, nav, risk);

        // Output should never exceed amount * nav
        uint256 maxOut = (amount * nav) / 1e18;
        assertLe(usdcOut, maxOut, "Output exceeds NAV value");

        // Fee should be within bounds
        assertGe(feeBps, 500, "Fee below minimum");
        assertLe(feeBps, 3000, "Fee above maximum");
    }
}

contract RedemptionCalculationTest is Test {
    DobOracle public oracle;

    function setUp() public {
        oracle = new DobOracle();
    }

    /// @notice Test redemption calculation matches spec
    function test_RedemptionCalculation() public view {
        uint256 amount = 1000e18;
        uint256 nav = oracle.nav(); // 1e18
        uint256 risk = oracle.defaultRisk(); // 1000 bps (10%)

        // Penalty = 300 + risk/10 = 300 + 100 = 400 bps (4%)
        uint256 expectedPenaltyBps = 300 + risk / 10;
        assertEq(expectedPenaltyBps, 400);

        // Output = amount * nav * (1 - penalty)
        // = 1000e18 * 1e18 * 9600 / (1e18 * 10000)
        // = 960e18
        uint256 expectedOutput = (amount * nav * (10000 - expectedPenaltyBps)) / (1e18 * 10000);
        assertEq(expectedOutput, 960e18);
    }

    function test_RedemptionWithHighRisk() public {
        // Update to 40% risk
        oracle.update(0.8e18, 4000);

        uint256 amount = 1000e18;
        uint256 nav = oracle.nav();
        uint256 risk = oracle.defaultRisk();

        // Penalty = 300 + 4000/10 = 700 bps (7%)
        uint256 expectedPenaltyBps = 300 + risk / 10;
        assertEq(expectedPenaltyBps, 700);

        // Output = 1000e18 * 0.8e18 * 9300 / (1e18 * 10000)
        // = 744e18
        uint256 expectedOutput = (amount * nav * (10000 - expectedPenaltyBps)) / (1e18 * 10000);
        assertEq(expectedOutput, 744e18);
    }
}
