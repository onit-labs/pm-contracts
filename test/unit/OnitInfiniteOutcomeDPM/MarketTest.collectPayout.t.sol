// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc utils
import { ERC1155 } from "solady/tokens/ERC1155.sol";
import { Receiver } from "solady/accounts/Receiver.sol";
import { console2 } from "forge-std/console2.sol";
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

// Infinite Outcome DPM: collectPayout
contract IODPMTestCollectPayout is OnitIODPMTestBase {
    function setUp() public {
        vm.deal(orderRouterAddress, 100 ether);
    }

    function test_collectPayout_revert_MarketIsOpen() public {
        market = newMarketWithDefaultConfig();

        vm.expectRevert(IOnitMarketResolver.MarketIsOpen.selector);
        market.collectPayout(alice);
    }

    function test_collectPayout_revert_WithdrawalDelayPeriodNotPassed() public {
        MarketInitData memory initData = defaultMarketConfig();
        initData.config.withdrawlDelayPeriod = 1 days;
        market = newMarket(initData);

        vm.prank(RESOLVER_1);
        market.resolveMarket(1001);

        vm.expectRevert(IOnitInfiniteOutcomeDPM.WithdrawalDelayPeriodNotPassed.selector);
        market.collectPayout(alice);
    }

    function test_collectPayout_revert_MarketIsVoided() public {
        market = newMarketWithDefaultConfig();

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

    function test_collectPayout_revert_NothingToPay_alreadyPaid() public {
        market = newMarketWithDefaultConfig();

        vm.prank(RESOLVER_1);
        market.resolveMarket(1001); // in bucket 1
        market.collectPayout(alice);

        vm.expectRevert(IOnitIODPMOrderManager.NothingToPay.selector);
        market.collectPayout(alice);
    }

    function test_collectPayout_revert_NothingToPay_losingBet() public {
        market = newMarketWithDefaultConfig();

        vm.prank(RESOLVER_1);
        market.resolveMarket(2001); // not in bucket 1

        vm.expectRevert(IOnitIODPMOrderManager.NothingToPay.selector);
        market.collectPayout(bob);
    }

    function test_collectPayout_reentrant() public {
        market = newMarketWithDefaultConfig();

        PayoutReentrant reentrant = new PayoutReentrant(address(market));
        address reentrantAddress = address(reentrant);

        (int256 cost,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);

        int256 reentrantOriginalBalance = cost;
        vm.deal(reentrantAddress, uint256(reentrantOriginalBalance));

        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(cost) }(address(reentrant), uint256(cost), DUMMY_BUCKET_IDS, DUMMY_SHARES);

        vm.prank(RESOLVER_1);
        market.resolveMarket(1000);

        uint256 reentrantBalanceBeforePayout = address(reentrant).balance;
        uint256 expectedPayout = market.calculatePayout(reentrantAddress);

        // Expect revert doesnt work on the second call, so we let it pass and confirm the attack failed by checking
        // balance is equal to their original balance and no more
        market.collectPayout(reentrantAddress);

        uint256 reentrantBalanceAfterPayout = address(reentrant).balance;

        // Attacker only got expected balance since reentrancy failed
        assertEq(reentrantBalanceAfterPayout, reentrantBalanceBeforePayout + expectedPayout, "reentrant balance");
    }

    function test_collectPayout_multiplePayouts() public {
        (int256[] memory bucketIds, int256[] memory shares) =
            gen.generateNormalDistribution(INITIAL_MEAN, INITIAL_STD_DEV, OUTCOME_UNIT);

        MarketInitData memory initData = defaultMarketConfig();
        initData.initialBucketIds = bucketIds;
        initData.initialShares = shares;
        market = newMarket(initData);

        (int256[] memory bucketIds2, int256[] memory shares2) =
            gen.generateNormalDistribution(SECOND_MEAN, SECOND_STD_DEV, OUTCOME_UNIT);

        (int256 costBob,) = market.calculateCostOfTrade(bucketIds2, shares2);
        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(costBob) }(bob, uint256(costBob), bucketIds2, shares2);

        // Resolve the market
        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        uint256 totalPayout = market.totalPayout();
        uint256 aliceBalance = address(alice).balance;
        uint256 bobBalance = address(bob).balance;

        market.collectPayout(alice);
        market.collectPayout(bob);

        uint256 aliceBalanceChange = address(alice).balance - aliceBalance;
        uint256 bobBalanceChange = address(bob).balance - bobBalance;

        // Alice was right, so she should get more
        assertGt(aliceBalanceChange, bobBalanceChange, "payout sizes");
        assertApproxEqRel(aliceBalanceChange + bobBalanceChange, totalPayout, PAYOUT_TOLERANCE, "total payout");
    }

    function testFuzz_collectPayouts(uint256 seed) public {
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

        uint256 totalBetCost;
        int256[] memory betCosts = new int256[](runSize);

        betCosts[0] = int256(INITIAL_BET_VALUE);
        totalBetCost += uint256(INITIAL_BET_VALUE);
        MarketInitData memory marketConfig = defaultMarketConfig();
        marketConfig.initialBetSize = INITIAL_BET_VALUE;
        marketConfig.initiator = predictions[0].predictor;
        marketConfig.initialBucketIds = predictions[0].bucketIds;
        marketConfig.initialShares = predictions[0].shares;
        market = newMarket(marketConfig);

        for (uint256 i = 1; i < runSize; i++) {
            (int256 cost,) = market.calculateCostOfTrade(predictions[i].bucketIds, predictions[i].shares);
            betCosts[i] = cost;
            totalBetCost += uint256(cost);
            vm.prank(orderRouterAddress);
            market.buyShares{
                value: uint256(betCosts[i])
            }(predictions[i].predictor, uint256(betCosts[i]), predictions[i].bucketIds, predictions[i].shares);
        }

        // Resolve market at first predictor's mean
        vm.prank(RESOLVER_1);
        market.resolveMarket(predictions[0].mean);

        // Track actual payouts
        uint256[] memory payouts = new uint256[](predictions.length);
        uint256 totalPaidOut = 0;

        for (uint256 i = 0; i < predictions.length; i++) {
            uint256 preBalance = predictions[i].predictor.balance;

            uint256 expectedPayout = market.calculatePayout(predictions[i].predictor);
            uint256 payout;

            if (expectedPayout > 0) {
                market.collectPayout(predictions[i].predictor);
                payout = predictions[i].predictor.balance - preBalance;
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

    function test_collectPayout_sameBets() public {
        OnitIODPMTestBase.NormalTestConfig memory config = getDefaultNormalTestConfig();
        config.base.numTests = 1;
        config.base.minValue = 0.1 ether;
        config.base.maxValue = 0.1 ether;

        OnitIODPMTestBase.TestPrediction[] memory predictions = generateNormalDistributionPredictionArray(config, 1);

        uint256 runSize = 3;
        int256[] memory bucketIds = predictions[0].bucketIds;
        int256[] memory shares = predictions[0].shares;
        address[] memory predictors = new address[](runSize);
        int256[] memory betCosts = new int256[](runSize);
        uint256 totalBetCost;

        for (uint256 i = 0; i < runSize; i++) {
            predictors[i] = makeAddr(vm.toString(uint160(i)));
            vm.deal(predictors[i], 100 ether);
        }

        betCosts[0] = int256(INITIAL_BET_VALUE);
        totalBetCost += uint256(INITIAL_BET_VALUE);
        MarketInitData memory marketConfig = defaultMarketConfig();
        marketConfig.initialBetSize = INITIAL_BET_VALUE;
        marketConfig.initiator = predictors[0];
        marketConfig.config.bettingCutoff = 0;
        marketConfig.config.withdrawlDelayPeriod = 0;
        marketConfig.initialBucketIds = bucketIds;
        marketConfig.initialShares = shares;
        market = newMarket(marketConfig);

        for (uint256 i = 1; i < runSize; i++) {
            (int256 cost,) = market.calculateCostOfTrade(bucketIds, shares);
            betCosts[i] = cost;
            totalBetCost += uint256(cost);
            vm.prank(orderRouterAddress);
            market.buyShares{ value: uint256(cost) }(predictors[i], uint256(cost), bucketIds, shares);
        }

        // Resolve market to first bucket
        vm.prank(RESOLVER_1);
        market.resolveMarket(bucketIds[0] * OUTCOME_UNIT);

        uint256[] memory balancesBeforePayout = new uint256[](runSize);
        uint256[] memory payouts = new uint256[](runSize);
        uint256 totalPayout = market.totalPayout();

        for (uint256 i = 0; i < runSize; i++) {
            balancesBeforePayout[i] = predictors[i].balance;
            market.collectPayout(predictors[i]);
            payouts[i] = predictors[i].balance - balancesBeforePayout[i];
        }

        for (uint256 i = 0; i < runSize; i++) {
            // Each user should get 1/3 of the total payout
            assertApproxEqRel(
                payouts[i], totalPayout / runSize, PAYOUT_TOLERANCE, string.concat("payout", vm.toString(i))
            );
        }
    }

    // function test_collectPayout_withSeededFunds() public {
    // uint256 initialBetValue = 1 ether;
    // uint256 seededFunds = 2 ether;

    // address[] memory resolvers = new address[](1);
    // resolvers[0] = RESOLVER_1;

    // OnitInfiniteOutcomeDPM.MarketConfig memory config = OnitInfiniteOutcomeDPM.MarketConfig({
    // marketCreatorFeeReceiver: MARKET_CREATOR_FEE_RECEIVER,
    // marketCreatorCommissionBp: MARKET_CREATOR_COMMISSION_BPS,
    // bettingCutoff: BETTING_CUTOFF_ONE_DAY,
    // withdrawlDelayPeriod: WITHDRAWAL_DELAY_PERIOD_ONE_DAY,
    // outcomeUnit: OUTCOME_UNIT,
    // marketQuestion: MARKET_QUESTION,
    // marketUri: MARKET_URI,
    // resolvers: resolvers
    // });

    // market = newMarket(config);

    // (int256 cost,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);

    // vm.prank(orderRouterAddress);
    // market.buyShares{ value: uint256(cost) }(alice, uint256(cost), DUMMY_BUCKET_IDS, DUMMY_SHARES);

    // // resolve the market
    // vm.prank(RESOLVER_1);
    // market.resolveMarket(1001);
    // vm.warp(block.timestamp + market.withdrawlDelayPeriod());

    // uint256 totalPayout = market.totalPayout();
    // assertGt(totalPayout, initialBetValue + uint256(cost), "total payout"); // greater since we seeded the market

    // uint256 aliceBalanceBefore = alice.balance;
    // uint256 bobBalanceBefore = bob.balance;

    // market.collectPayout(alice);
    // market.collectPayout(bob);

    // uint256 aliceBalanceAfter = alice.balance;
    // uint256 bobBalanceAfter = bob.balance;

    // assertEq(aliceBalanceAfter, aliceBalanceBefore + totalPayout / 2);
    // assertEq(bobBalanceAfter, bobBalanceBefore + totalPayout / 2);
    //}

    fallback() external payable { }
    receive() external payable { }
}

contract PayoutReentrant is ERC1155, Receiver {
    address target;

    constructor(address _target) ERC1155() {
        target = _target;
    }

    function uri(uint256) public pure override returns (string memory) {
        return "uri";
    }

    receive() external payable override {
        console2.log("collectPayout received, lets try reentrancy");
        (bool success,) =
            target.call(abi.encodeWithSelector(bytes4(keccak256("collectPayout(address)")), address(this)));
        success;
    }
}
