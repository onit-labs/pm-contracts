// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc utils
import { MockErc20 } from "@test/mocks/MockErc20.sol";
// Config
import { OnitIODPMTestBase } from "@test/config/OnitIODPMTestBase.t.sol";
// Types
import { MarketInitData } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
// Interfaces
import { IOnitInfiniteOutcomeDPM } from "@src/interfaces/IOnitInfiniteOutcomeDPM.sol";
import { IOnitMarketResolver } from "@src/interfaces/IOnitMarketResolver.sol";
import { IOnitIODPMOrderManager } from "@src/interfaces/IOnitIODPMOrderManager.sol";
// Contract to test
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";
import { OnitMarketResolver } from "@src/resolvers/OnitMarketResolver.sol";
import { OnitIODPMOrderManager } from "@src/order-manager/OnitIODPMOrderManager.sol";

// Infinite Outcome DPM: collectPayout token
contract IODPMTestCollectPayoutToken is OnitIODPMTestBase {
    MockErc20 tokenB;

    function setUp() public {
        tokenB = new MockErc20("B", "B", 18);

        tokenA.mint(alice, 1000 ether);
        tokenB.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);
        tokenB.mint(bob, 1000 ether);
    }

    function test_collectPayout_revert_MarketIsOpen_token() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        vm.expectRevert(IOnitMarketResolver.MarketIsOpen.selector);
        market.collectPayout(alice);
    }

    function test_collectPayout_revert_WithdrawalDelayPeriodNotPassed_token() public {
        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.config.withdrawlDelayPeriod = 1 days;

        OnitInfiniteOutcomeDPM market = newMarket(initData);

        vm.prank(RESOLVER_1);
        market.resolveMarket(1001);

        vm.expectRevert(IOnitInfiniteOutcomeDPM.WithdrawalDelayPeriodNotPassed.selector);
        market.collectPayout(alice);
    }

    function test_collectPayout_revert_MarketIsVoided_token() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        // The check for the market not being resolved occurs before the check if the market is voided in
        // collectPayout
        // So this test is only relevant if the market is resolved, then somehow voided
        vm.prank(RESOLVER_1);
        market.resolveMarket(1001);

        vm.prank(MARKET_OWNER);
        market.voidMarket();

        vm.expectRevert(IOnitMarketResolver.MarketIsVoided.selector);
        market.collectPayout(alice);
    }

    function test_collectPayout_revert_NothingToPay_alreadyPaid_token() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        vm.prank(RESOLVER_1);
        market.resolveMarket(1001); // in bucket 1

        market.collectPayout(alice);

        vm.expectRevert(IOnitIODPMOrderManager.NothingToPay.selector);
        market.collectPayout(alice);
    }

    function test_collectPayout_revert_NothingToPay_losingBet_token() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        vm.prank(RESOLVER_1);
        market.resolveMarket(2001); // not in bucket 1

        vm.expectRevert(IOnitIODPMOrderManager.NothingToPay.selector);
        market.collectPayout(bob);
    }

    function test_collectPayout_multiplePayouts_token() public {
        (int256[] memory bucketIds, int256[] memory shares) =
            gen.generateNormalDistribution(INITIAL_MEAN, INITIAL_STD_DEV, OUTCOME_UNIT);

        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.initialBucketIds = bucketIds;
        initData.initialShares = shares;
        OnitInfiniteOutcomeDPM market = newMarket(initData);

        (int256[] memory bucketIds2, int256[] memory shares2) =
            gen.generateNormalDistribution(SECOND_MEAN, SECOND_STD_DEV, OUTCOME_UNIT);

        (int256 costBob,) = market.calculateCostOfTrade(bucketIds2, shares2);

        vm.prank(orderRouterAddress);
        market.buyShares(bob, uint256(costBob), bucketIds2, shares2);

        // Resolve the market
        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        // Wait for withdrawal delay period
        vm.warp(block.timestamp + market.withdrawlDelayPeriod());

        uint256 totalPayout = market.totalPayout();
        uint256 aliceBalance = tokenA.balanceOf(alice);
        uint256 bobBalance = tokenA.balanceOf(bob);

        market.collectPayout(alice);
        market.collectPayout(bob);

        uint256 aliceBalanceChange = tokenA.balanceOf(alice) - aliceBalance;
        uint256 bobBalanceChange = tokenA.balanceOf(bob) - bobBalance;

        // Alice was right, so she should get more
        assertGt(aliceBalanceChange, bobBalanceChange, "payout sizes");
        assertApproxEqRel(aliceBalanceChange + bobBalanceChange, totalPayout, PAYOUT_TOLERANCE, "total payout");
    }

    function testFuzz_collectPayouts_token(uint256 seed) public {
        uint256 runSize = 50;

        OnitIODPMTestBase.NormalTestConfig memory config = getDefaultNormalTestConfig();
        config.base.numTests = runSize;
        config.base.minValue = 0.1 ether;
        config.base.maxValue = 0.1 ether;

        // 10% deviation on test values
        OnitIODPMTestBase.TestArrayDistributionConfig memory distributionConfig =
            getDefaultTestArrayDistributionConfig();
        distributionConfig.meanDev = 0.1 ether;
        distributionConfig.stdDevDev = 0.1 ether;

        OnitIODPMTestBase.TestPrediction[] memory predictions =
            generateNormalDistributionPredictionArray(config, distributionConfig, seed);

        // first predictor is alice so we can use the existing newMarket function for testing
        predictions[0].predictor = alice;
        predictions[0].predictorPk = alicePk;

        int256 kappa = getKappaForInitialMarket(predictions[0].shares, int256(INITIAL_BET_VALUE));

        (int256 initalCost,) = getCostOfInitialBet(kappa, predictions[0].shares);

        uint256 totalBetCost;
        int256[] memory betCosts = new int256[](runSize);

        betCosts[0] = (initalCost);
        totalBetCost += uint256(initalCost);

        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.initiator = predictions[0].predictor;
        initData.initialBucketIds = predictions[0].bucketIds;
        initData.initialShares = predictions[0].shares;
        OnitInfiniteOutcomeDPM market = newMarket(initData);

        // Mint tokens for all predictors
        for (uint256 i = 0; i < runSize; i++) {
            tokenA.mint(predictions[i].predictor, 100 ether);
        }

        for (uint256 i = 1; i < runSize; i++) {
            (int256 cost,) = market.calculateCostOfTrade(predictions[i].bucketIds, predictions[i].shares);

            betCosts[i] = cost;
            totalBetCost += uint256(cost);

            // Create order data with permit for token approval
            bytes memory orderData = createOrderData(
                address(tokenA),
                predictions[i].predictor,
                address(market),
                uint256(cost),
                block.timestamp + 1 days,
                predictions[i].predictorPk
            );

            vm.prank(predictions[i].predictor);
            orderRouter.executeOrder(
                address(market),
                predictions[i].predictor,
                uint256(cost),
                predictions[i].bucketIds,
                predictions[i].shares,
                orderData
            );
        }

        // Resolve market at first predictor's mean
        vm.prank(RESOLVER_1);
        market.resolveMarket(predictions[0].mean);

        // Wait for withdrawal delay
        vm.warp(block.timestamp + market.withdrawlDelayPeriod());

        // Track actual payouts
        uint256[] memory payouts = new uint256[](predictions.length);
        uint256 totalPaidOut = 0;

        for (uint256 i = 0; i < predictions.length; i++) {
            uint256 preBalance = tokenA.balanceOf(predictions[i].predictor);

            uint256 expectedPayout = market.calculatePayout(predictions[i].predictor);
            uint256 payout;

            if (expectedPayout > 0) {
                market.collectPayout(predictions[i].predictor);
                payout = tokenA.balanceOf(predictions[i].predictor) - preBalance;
            } else {
                payout = 0;
            }

            payouts[i] = payout;
            totalPaidOut += payout;
        }

        uint256 payoutAfterMarketCommission = totalBetCost - market.PROTOCOL_COMMISSION_BP() * totalBetCost / 10_000;

        // Verify total payout equals total value
        assertApproxEqRel(
            totalPaidOut, payoutAfterMarketCommission, 0.001 ether, "Total payout should equal total value"
        );
    }

    function test_collectPayout_sameBets_token() public {
        OnitIODPMTestBase.NormalTestConfig memory config = getDefaultNormalTestConfig();
        config.base.numTests = 1;
        config.base.minValue = 0.1 ether;
        config.base.maxValue = 0.1 ether;

        OnitIODPMTestBase.TestPrediction[] memory predictions = generateNormalDistributionPredictionArray(config, 1);

        uint256 runSize = 10;
        int256[] memory bucketIds = predictions[0].bucketIds;
        int256[] memory shares = predictions[0].shares;
        address[] memory predictors = new address[](runSize);
        uint256[] memory predictorPks = new uint256[](runSize);
        int256[] memory betCosts = new int256[](runSize);
        uint256 totalBetCost;

        for (uint256 i = 0; i < runSize; i++) {
            if (i == 0) {
                // setting first predictor to alice lets us use the existing newMarket function for testing
                predictors[i] = alice;
            } else {
                (predictors[i], predictorPks[i]) = makeAddrAndKey(vm.toString(uint160(i)));
            }
            vm.deal(predictors[i], 100 ether);
            tokenA.mint(predictors[i], 100 ether);
        }

        betCosts[0] = int256(INITIAL_BET_VALUE);
        totalBetCost += uint256(INITIAL_BET_VALUE);

        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.initiator = predictors[0];
        initData.config.bettingCutoff = 0;
        initData.config.withdrawlDelayPeriod = 0;
        initData.initialBucketIds = bucketIds;
        initData.initialShares = shares;
        OnitInfiniteOutcomeDPM market = newMarket(initData);

        for (uint256 i = 1; i < runSize; i++) {
            (int256 cost,) = market.calculateCostOfTrade(bucketIds, shares);

            // Set up token approval
            bytes memory orderData = createOrderData(
                address(tokenA),
                predictors[i],
                address(market),
                uint256(cost),
                block.timestamp + 100 days,
                predictorPks[i]
            );

            betCosts[i] = cost;
            totalBetCost += uint256(cost);
            vm.prank(predictors[i]);
            orderRouter.executeOrder(address(market), predictors[i], uint256(cost), bucketIds, shares, orderData);
        }

        // Resolve market to first bucket
        vm.prank(RESOLVER_1);
        market.resolveMarket(bucketIds[0] * OUTCOME_UNIT);

        uint256[] memory balancesBeforePayout = new uint256[](runSize);
        uint256[] memory payouts = new uint256[](runSize);
        uint256 totalPayout = market.totalPayout();

        for (uint256 i = 0; i < runSize; i++) {
            balancesBeforePayout[i] = tokenA.balanceOf(predictors[i]);
            market.collectPayout(predictors[i]);
            payouts[i] = tokenA.balanceOf(predictors[i]) - balancesBeforePayout[i];
        }

        for (uint256 i = 0; i < runSize; i++) {
            // Each user should get 1/3 of the total payout
            assertApproxEqRel(
                payouts[i], totalPayout / runSize, PAYOUT_TOLERANCE, string.concat("payout", vm.toString(i))
            );
        }
    }

    function test_collectPayout_withSeededFunds_token() public {
        uint256 initialBetValue = 1 ether;
        uint256 seededFunds = 2 ether;

        tokenA.mint(bob, 10 ether);

        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.seededFunds = seededFunds;
        initData.initialBetSize = initialBetValue;

        // Approve tokens for the creation
        tokenA.approve(orderRouterAddress, initialBetValue + seededFunds);

        OnitInfiniteOutcomeDPM testMarket = newMarket(initData);

        // Check balance of market
        assertEq(tokenA.balanceOf(address(testMarket)), initialBetValue + seededFunds);

        // Make a token bet as bob
        (int256 cost,) = testMarket.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);

        vm.prank(orderRouterAddress);
        testMarket.buyShares(bob, uint256(cost), DUMMY_BUCKET_IDS, DUMMY_SHARES);

        // resolve the market
        vm.prank(RESOLVER_1);
        testMarket.resolveMarket(1001);
        vm.warp(block.timestamp + testMarket.withdrawlDelayPeriod());

        uint256 totalPayout = testMarket.totalPayout();
        assertGt(totalPayout, initialBetValue + uint256(cost), "total payout"); // greater since we seeded the market

        uint256 aliceBalanceBefore = tokenA.balanceOf(alice);
        uint256 bobBalanceBefore = tokenA.balanceOf(bob);

        testMarket.collectPayout(alice);
        testMarket.collectPayout(bob);

        uint256 aliceBalanceAfter = tokenA.balanceOf(alice);
        uint256 bobBalanceAfter = tokenA.balanceOf(bob);

        assertEq(aliceBalanceAfter, aliceBalanceBefore + totalPayout / 2);
        assertEq(bobBalanceAfter, bobBalanceBefore + totalPayout / 2);
    }

    fallback() external payable { }
    receive() external payable { }
}
