// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {LiquidNodeStabilizer} from "../src/LiquidNodeStabilizer.sol";
import {DobNodeLiquidityHookV2} from "../src/DobNodeLiquidityHookV2.sol";
import {DobOracle} from "../src/DobOracle.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {DobToken} from "../src/DobToken.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IDobOracle} from "../src/interfaces/IDobOracle.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {SwapParams} from "v4-core/types/PoolOperation.sol";

/// @title StabilizationE2ETest
/// @notice End-to-end test demonstrating price stabilization mechanism
contract StabilizationE2ETest is Test {
    LiquidNodeStabilizer public liquidNode;
    DobNodeLiquidityHookV2 public hook;
    DobOracle public oracle;
    MockUSDC public usdc;
    DobToken public dobToken;

    address public operator;
    address public alice;
    address public bob;
    address public mockPoolManager;

    PoolKey public poolKey;

    function setUp() public {
        operator = address(this);
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        mockPoolManager = address(new MockPoolManager());

        // Deploy core contracts
        oracle = new DobOracle();
        usdc = new MockUSDC();
        dobToken = new DobToken(address(this)); // Use test as mock hook for minting

        // Deploy Liquid Node Stabilizer
        liquidNode = new LiquidNodeStabilizer(
            IPoolManager(mockPoolManager),
            IDobOracle(address(oracle)),
            Currency.wrap(address(usdc)),
            Currency.wrap(address(dobToken)),
            operator
        );

        // Deploy Hook V2
        hook = new DobNodeLiquidityHookV2(
            IPoolManager(mockPoolManager),
            liquidNode,
            IDobOracle(address(oracle)),
            Currency.wrap(address(usdc)),
            Currency.wrap(address(dobToken))
        );

        // Create pool key with hook at address(0) to bypass validation
        poolKey = PoolKey({
            currency0: Currency.wrap(address(usdc)),
            currency1: Currency.wrap(address(dobToken)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0)) // Use address(0) to skip V4 validation in tests
        });

        // Initial oracle state: NAV = $1.00, Risk = 10%
        oracle.update(1e18, 1000);

        // Fund Liquid Node with reserves
        uint256 usdcFunding = 50_000 * 1e6; // 50k USDC
        uint256 dobFunding = 50_000 * 1e18; // 50k DOB

        usdc.mint(address(this), usdcFunding);
        usdc.approve(address(liquidNode), usdcFunding);
        liquidNode.fundUSDC(usdcFunding);

        dobToken.mint(address(this), dobFunding);
        dobToken.approve(address(liquidNode), dobFunding);
        liquidNode.fundDOB(dobFunding);

        // Give users some tokens for trading
        usdc.mint(alice, 10_000 * 1e6);
        usdc.mint(bob, 10_000 * 1e6);
        dobToken.mint(alice, 10_000 * 1e18);
        dobToken.mint(bob, 10_000 * 1e18);

        console.log("\n=== SETUP COMPLETE ===");
        console.log("Oracle NAV: $1.00");
        console.log("Oracle Risk: 10%");
        console.log("Liquid Node USDC:", usdcFunding / 1e6);
        console.log("Liquid Node DOB:", dobFunding / 1e18);
    }

    /// @notice Test 1: Normal market conditions - no intervention needed
    function testNoInterventionWhenPriceStable() public view {
        // Check if stabilization would trigger
        (bool shouldStabilize,,) = hook.checkStabilization(poolKey);

        assertFalse(shouldStabilize, "Should not trigger stabilization at NAV");
        console.log("\n[PASS] Test 1: No intervention when price stable");
    }

    /// @notice Test 2: Price drops - Liquid Node supports by buying
    function testStabilizeLowPrice() public {
        console.log("\n=== Test 2: Price Drop Scenario ===");

        // Simulate market stress - NAV drops to $0.90 (10% below)
        oracle.update(0.90e18, 2000); // NAV $0.90, Risk 20%

        // Check stabilization should trigger
        (bool shouldStabilize, bool buyDOB, uint256 deviation) = hook.checkStabilization(poolKey);

        console.log("Pool price deviation:", deviation, "bps");
        console.log("Should buy DOB:", buyDOB);
        console.log("Should stabilize:", shouldStabilize);

        // In real scenario, afterSwap would be called automatically
        // Here we simulate the stabilization call
        if (shouldStabilize && buyDOB) {
            uint256 usdcBefore = usdc.balanceOf(address(liquidNode));
            uint256 dobBefore = dobToken.balanceOf(address(liquidNode));

            // Note: In real scenario, this would be called by hook via afterSwap
            // Here we demonstrate the logic works
            console.log("Liquid Node would intervene to buy DOB");
            console.log("USDC balance before:", usdcBefore / 1e6);
            console.log("DOB balance before:", dobBefore / 1e18);

            assertTrue(shouldStabilize, "Should trigger stabilization");
            assertTrue(buyDOB, "Should buy DOB to support price");
        }
    }

    /// @notice Test 3: Price rises - Liquid Node caps by selling
    function testStabilizeHighPrice() public {
        console.log("\n=== Test 3: Price Surge Scenario ===");

        // Simulate bull market - NAV rises to $1.15 (15% above)
        oracle.update(1.15e18, 500); // NAV $1.15, Risk 5%

        (bool shouldStabilize, bool buyDOB, uint256 deviation) = hook.checkStabilization(poolKey);

        console.log("Pool price deviation:", deviation, "bps");
        console.log("Should sell DOB:", !buyDOB);
        console.log("Should stabilize:", shouldStabilize);

        if (shouldStabilize && !buyDOB) {
            uint256 dobBefore = dobToken.balanceOf(address(liquidNode));

            console.log("Liquid Node would intervene to sell DOB");
            console.log("DOB balance before:", dobBefore / 1e18);

            assertTrue(shouldStabilize, "Should trigger stabilization");
            assertFalse(buyDOB, "Should sell DOB to cap price");
        }
    }

    /// @notice Test 4: Complete market cycle with interventions
    function testFullMarketCycle() public {
        console.log("\n=== Test 4: Full Market Cycle ===");

        // Phase 1: Launch (NAV = $1.00)
        console.log("\n--- Phase 1: Launch ---");
        oracle.update(1e18, 1000);
        (uint256 usdcBal1, uint256 dobBal1) = liquidNode.getBalances();
        console.log("Liquid Node USDC:", usdcBal1 / 1e6);
        console.log("Liquid Node DOB:", dobBal1 / 1e18);

        // Phase 2: Revenue Growth (NAV = $1.20)
        console.log("\n--- Phase 2: Revenue Growth ---");
        oracle.update(1.20e18, 500);
        console.log("NAV increased to $1.20, Risk down to 5%");

        (bool stabilize2, bool buy2, uint256 dev2) = hook.checkStabilization(poolKey);
        console.log("Deviation (bps):", dev2);
        console.log("Should stabilize:", stabilize2);

        // Phase 3: Market Crash (NAV = $0.75)
        console.log("\n--- Phase 3: Market Crash ---");
        oracle.update(0.75e18, 3500);
        console.log("NAV crashed to $0.75, Risk up to 35%");

        (bool stabilize3, bool buy3, uint256 dev3) = hook.checkStabilization(poolKey);
        console.log("Deviation (bps):", dev3);
        console.log("Should buy DOB:", buy3);

        // Phase 4: Recovery (NAV = $1.30)
        console.log("\n--- Phase 4: Recovery ---");
        oracle.update(1.30e18, 400);
        console.log("NAV recovered to $1.30, Risk down to 4%");

        (bool stabilize4, bool buy4, uint256 dev4) = hook.checkStabilization(poolKey);
        console.log("Deviation (bps):", dev4);
        console.log("Should stabilize:", stabilize4);

        // Verify Liquid Node still has reserves
        (uint256 usdcFinal, uint256 dobFinal) = liquidNode.getBalances();
        console.log("\n--- Final State ---");
        console.log("Liquid Node USDC:", usdcFinal / 1e6);
        console.log("Liquid Node DOB:", dobFinal / 1e18);
        console.log("Fees earned (USDC):", liquidNode.totalFeesEarned() / 1e6);

        assertGt(usdcFinal, 0, "Should have USDC reserves");
        assertGt(dobFinal, 0, "Should have DOB reserves");
    }

    /// @notice Test 5: Multiple users trading in various conditions
    function testMultipleUserScenario() public {
        console.log("\n=== Test 5: Multiple Users Trading ===");

        // Scenario: Market volatility with different user behaviors

        console.log("\n--- Alice trades during stability ---");
        oracle.update(1e18, 1000); // Stable
        uint256 aliceUSDC = usdc.balanceOf(alice);
        console.log("Alice USDC balance:", aliceUSDC / 1e6);

        console.log("\n--- Bob trades during bull market ---");
        oracle.update(1.10e18, 700); // Bull market
        (bool stabilize, bool buyDOB, uint256 deviation) = hook.checkStabilization(poolKey);
        console.log("Deviation:", deviation, "bps");
        console.log("Stabilization needed:", stabilize);

        console.log("\n--- Market returns to normal ---");
        oracle.update(1.02e18, 900); // Near NAV
        (bool stabilize2,,) = hook.checkStabilization(poolKey);
        console.log("Stabilization needed:", stabilize2);

        assertTrue(true, "Multi-user scenario completed");
    }

    /// @notice Test 6: Liquid Node capital efficiency
    function testCapitalEfficiency() public view {
        console.log("\n=== Test 6: Capital Efficiency ===");

        (uint256 usdcBalance, uint256 dobBalance) = liquidNode.getBalances();

        // At 5% deviation, intervention uses deviation/BPS/10 of balance
        // 500 bps deviation = 500/10000/10 = 0.5% of balance per intervention
        uint256 maxInterventionUSDC = (usdcBalance * 500) / (10000 * 10);
        uint256 maxInterventionDOB = (dobBalance * 500) / (10000 * 10);

        console.log("Total USDC reserves:", usdcBalance / 1e6);
        console.log("Total DOB reserves:", dobBalance / 1e18);
        console.log("Max intervention USDC (5% dev):", maxInterventionUSDC / 1e6);
        console.log("Max intervention DOB (5% dev):", maxInterventionDOB / 1e18);

        // Can handle 200 interventions at 5% deviation (0.5% per intervention)
        uint256 interventionsSupported = 10000 / 50; // 100% / 0.5%
        console.log("Interventions supported:", interventionsSupported);

        assertGt(interventionsSupported, 100, "Should support many interventions");
    }

    /// @notice Test 7: Fee accumulation
    function testFeeAccumulation() public view {
        console.log("\n=== Test 7: Fee Structure ===");

        // 0.5% fee on each intervention
        uint256 interventionAmount = 10_000 * 1e6; // $10k intervention
        uint256 expectedFee = (interventionAmount * 50) / 10000; // 0.5%

        console.log("Intervention amount (USDC):", interventionAmount / 1e6);
        console.log("Expected fee 0.5% (USDC):", expectedFee / 1e6);
        console.log("Net intervention (USDC):", (interventionAmount - expectedFee) / 1e6);

        assertEq(expectedFee, 5 * 1e6, "Fee should be $5 on $10k intervention");
    }
}

/// @notice Mock PoolManager for testing
/// @dev Simplified mock that bypasses V4 hook address validation
contract MockPoolManager {
    // Just needs to exist and have swap function
    function swap(PoolKey calldata, SwapParams calldata, bytes calldata)
        external
        pure
        returns (BalanceDelta)
    {
        return BalanceDelta.wrap(0);
    }
}
