// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {LiquidNodeStabilizer} from "../src/LiquidNodeStabilizer.sol";
import {DobOracle} from "../src/DobOracle.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {DobToken} from "../src/DobToken.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IDobOracle} from "../src/interfaces/IDobOracle.sol";

contract LiquidNodeStabilizerTest is Test {
    LiquidNodeStabilizer public liquidNode;
    DobOracle public oracle;
    MockUSDC public usdc;
    DobToken public dobToken;

    address public operator = address(this);
    address public mockPoolManager = address(0x1234);

    function setUp() public {
        // Deploy contracts
        oracle = new DobOracle();
        usdc = new MockUSDC();
        dobToken = new DobToken(address(this)); // Use test contract as mock hook

        // Deploy Liquid Node
        liquidNode = new LiquidNodeStabilizer(
            IPoolManager(mockPoolManager),
            IDobOracle(address(oracle)),
            Currency.wrap(address(usdc)),
            Currency.wrap(address(dobToken)),
            operator
        );

        // Fund Liquid Node
        uint256 usdcAmount = 100_000 * 1e6; // 100k USDC
        uint256 dobAmount = 50_000 * 1e18; // 50k DOB

        usdc.mint(address(this), usdcAmount);
        usdc.approve(address(liquidNode), usdcAmount);
        liquidNode.fundUSDC(usdcAmount);

        dobToken.mint(address(this), dobAmount);
        dobToken.approve(address(liquidNode), dobAmount);
        liquidNode.fundDOB(dobAmount);
    }

    function testFunding() public view {
        (uint256 usdcBalance, uint256 dobBalance) = liquidNode.getBalances();
        assertEq(usdcBalance, 100_000 * 1e6, "USDC balance incorrect");
        assertEq(dobBalance, 50_000 * 1e18, "DOB balance incorrect");
    }

    function testDeviationThreshold() public view {
        assertEq(liquidNode.DEVIATION_THRESHOLD(), 500, "Threshold should be 5%");
    }

    function testInterventionFee() public view {
        assertEq(liquidNode.INTERVENTION_FEE(), 50, "Fee should be 0.5%");
    }

    function testQuoteFromOracle() public {
        // Set oracle state
        oracle.update(1e18, 1000); // NAV = $1, Risk = 10%

        uint256 dobAmount = 1000 * 1e18;
        (uint256 usdcProvided, uint256 feeBps) = liquidNode.quoteFromOracle(dobAmount);

        // At 10% risk, fee should be 5%
        assertEq(feeBps, 500, "Fee should be 5% at 10% risk");

        // Expected USDC: 1000 DOB * $1 * (1 - 0.05) = $950
        // Note: quoteFromOracle returns amount without decimal adjustment
        uint256 expected = 950 * 1e18; // Result is in 18 decimals
        assertEq(usdcProvided, expected, "Quote incorrect");
    }

    function testQuoteHighRisk() public {
        // Set high risk
        oracle.update(1e18, 3500); // NAV = $1, Risk = 35%

        uint256 dobAmount = 1000 * 1e18;
        (uint256 usdcProvided, uint256 feeBps) = liquidNode.quoteFromOracle(dobAmount);

        // At 35% risk, fee should be 20%
        assertEq(feeBps, 2000, "Fee should be 20% at high risk");

        // Expected USDC: 1000 DOB * $1 * (1 - 0.20) = $800
        // Note: quoteFromOracle returns amount without decimal adjustment
        uint256 expected = 800 * 1e18; // Result is in 18 decimals
        assertEq(usdcProvided, expected, "Quote incorrect for high risk");
    }

    function testOnlyOperatorCanWithdraw() public {
        vm.prank(address(0xdead));
        vm.expectRevert(LiquidNodeStabilizer.OnlyOperator.selector);
        liquidNode.withdrawFees();
    }

    function testConstants() public view {
        assertEq(liquidNode.BPS(), 10000, "BPS should be 10000");
        assertEq(liquidNode.DEVIATION_THRESHOLD(), 500, "Deviation threshold should be 500 bps");
        assertEq(liquidNode.INTERVENTION_FEE(), 50, "Intervention fee should be 50 bps");
    }
}
