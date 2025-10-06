// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

/* solhint-disable max-line-length */

// Misc utils
import { stdStorage, StdStorage } from "forge-std/Test.sol";
// Config
import { OnitIODPMTestBase } from "@test/config/OnitIODPMTestBase.t.sol";
// Types
import { MarketInitData, BetStatus } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
// Interfaces
import { IOnitInfiniteOutcomeDPM } from "@src/interfaces/IOnitInfiniteOutcomeDPM.sol";
import { IOnitIODPMOrderManager } from "@src/interfaces/IOnitIODPMOrderManager.sol";
import { IOnitMarketResolver } from "@src/interfaces/IOnitMarketResolver.sol";
import { IOnitInfiniteOutcomeDPMMechanism } from "@src/interfaces/IOnitInfiniteOutcomeDPMMechanism.sol";
// Contract to test
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";
import {
    OnitInfiniteOutcomeDPMOutcomeDomain
} from "@src/mechanisms/infinite-outcome-DPM/OnitInfiniteOutcomeDPMOutcomeDomain.sol";
import {
    OnitInfiniteOutcomeDPMMechanism
} from "@src/mechanisms/infinite-outcome-DPM/OnitInfiniteOutcomeDPMMechanism.sol";
import { OnitMarketResolver } from "@src/resolvers/OnitMarketResolver.sol";
import { OnitIODPMOrderManager } from "@src/order-manager/OnitIODPMOrderManager.sol";

// Infinite Outcome DPM: buyShares
contract IODPMTestBuyShares is OnitIODPMTestBase {
    using stdStorage for StdStorage;

    function setUp() public {
        vm.deal(orderRouterAddress, 100 ether);
    }

    function test_buyShares_reverts_NotFromOrderRouter() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfig();
        vm.prank(bob);
        vm.expectRevert(IOnitIODPMOrderManager.NotFromOrderRouter.selector);
        market.buyShares(bob, INITIAL_BET_VALUE, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_reverts_BettingCutoffPassed() public {
        MarketInitData memory initData = defaultMarketConfig();
        initData.config.bettingCutoff = BETTING_CUTOFF_ONE_DAY;
        market = newMarket(initData);

        vm.warp(block.timestamp + 2 days);

        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitInfiniteOutcomeDPM.BettingCutoffPassed.selector);
        market.buyShares(bob, HALF_ETHER, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_reverts_MarketIsResolved() public {
        market = newMarketWithDefaultConfig();

        // Close the market
        vm.prank(RESOLVER_1);
        market.resolveMarket(1);

        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitMarketResolver.MarketIsResolved.selector);
        market.buyShares(bob, INITIAL_BET_VALUE, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_reverts_marketIsVoided() public {
        market = newMarketWithDefaultConfig();

        market.voidMarket();

        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitMarketResolver.MarketIsVoided.selector);
        market.buyShares(bob, HALF_ETHER, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_reverts_BetValueOutOfBounds_noValuePassedToNativeMarket() public {
        market = newMarketWithDefaultConfig();
        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitIODPMOrderManager.BetValueOutOfBounds.selector);
        market.buyShares(bob, INITIAL_BET_VALUE, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_reverts_BetValueOutOfBounds_belowMinBetSize() public {
        market = newMarketWithDefaultConfig();

        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitIODPMOrderManager.BetValueOutOfBounds.selector);
        market.buyShares{ value: MIN_BET_SIZE - 1 }(bob, MIN_BET_SIZE - 1, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_reverts_BetValueOutOfBounds_aboveMaxBetSize() public {
        market = newMarketWithDefaultConfig();

        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitIODPMOrderManager.BetValueOutOfBounds.selector);
        market.buyShares{ value: MAX_BET_SIZE + 1 }(bob, MAX_BET_SIZE + 1, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_reverts_IncorrectBetValue() public {
        market = newMarketWithDefaultConfig();

        // Expect the event IncorrectBetValue to be emitted with values (1, 0) representing (expected, actual)
        bytes memory errorData =
            abi.encodeWithSelector(IOnitIODPMOrderManager.IncorrectBetValue.selector, INITIAL_BET_VALUE, 0.99 ether);
        vm.prank(orderRouterAddress);
        vm.expectRevert(errorData);
        market.buyShares{ value: 0.99 ether }(bob, 0.99 ether, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_reverts_BetValueOutOfBounds_noValues() public {
        int256[] memory bucketIds = new int256[](1);
        int256[] memory shares = new int256[](1);
        bucketIds[0] = 0;
        shares[0] = 0;

        market = newMarketWithDefaultConfig();

        int256[] memory emptyBucketIds = new int256[](0);
        int256[] memory emptyShares = new int256[](0);

        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitIODPMOrderManager.BetValueOutOfBounds.selector);
        market.buyShares{ value: 0 }(bob, 0, emptyBucketIds, emptyShares);
    }

    function test_buyShares_reverts_BucketIdsNotStrictlyIncreasing() public {
        market = newMarketWithDefaultConfig();

        int256[] memory bucketIds = new int256[](2);
        bucketIds[0] = 0;
        bucketIds[1] = 0;
        int256[] memory shares = new int256[](2);
        shares[0] = 1;
        shares[1] = 2;

        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitInfiniteOutcomeDPMMechanism.BucketIdsNotStrictlyIncreasing.selector);
        market.buyShares{ value: INITIAL_BET_VALUE }(bob, INITIAL_BET_VALUE, bucketIds, shares);
    }

    function test_buyShares_reverts_IncorrectBetValue_negativeCostDiff() public {
        int256[] memory bucketIds = new int256[](2);
        bucketIds[0] = 0;
        bucketIds[1] = 1;
        int256[] memory shares = new int256[](2);
        shares[0] = 2;
        shares[1] = 2;

        MarketInitData memory initData = defaultMarketConfig();
        initData.initialBucketIds = bucketIds;
        initData.initialShares = shares;
        market = newMarket(initData);

        int256[] memory negativeShares = new int256[](2);
        negativeShares[0] = -1;
        negativeShares[1] = -1;

        (int256 cost2,) = market.calculateCostOfTrade(bucketIds, negativeShares);

        /**
         * The below is putting the -cost2 value into value since value can only be uint256
         * This will fail since the check on the contract will be expecting a negative value
         * Also, any attempt to pass another value will fail since any negative value cast to uint256 will be far too
         * large for the trader to afford
         */
        bytes memory errorData =
            abi.encodeWithSelector(IOnitIODPMOrderManager.IncorrectBetValue.selector, cost2, -cost2);
        vm.prank(orderRouterAddress);
        vm.expectRevert(errorData);
        market.buyShares{ value: uint256(-cost2) }(alice, uint256(-cost2), bucketIds, negativeShares);
    }

    function test_buyShares_singlePrediction() public {
        (int256[] memory bucketIds, int256[] memory shares) =
            gen.generateNormalDistribution(INITIAL_MEAN, INITIAL_STD_DEV, OUTCOME_UNIT);

        MarketInitData memory initData = defaultMarketConfig();
        initData.initialBucketIds = bucketIds;
        initData.initialShares = shares;
        market = newMarket(initData);

        uint256 aliceBalanceMean = market.getBalanceOfShares(alice, getBucketId(INITIAL_MEAN, OUTCOME_UNIT));
        assertGt(aliceBalanceMean, 0, "alice balance at mean");

        (int256[] memory bucketIds2, int256[] memory shares2) =
            gen.generateNormalDistribution(SECOND_MEAN, SECOND_STD_DEV, OUTCOME_UNIT);

        // Get cost of prediction for bob
        (int256 costBob, int256 predictedNewTotalQSquaredOfMarket) = market.calculateCostOfTrade(bucketIds2, shares2);
        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(costBob) }(bob, uint256(costBob), bucketIds2, shares2);

        // Check markets balance
        int256 expectedTotalMarketBalance = int256(INITIAL_BET_VALUE) + costBob;
        assertEq(address(market).balance, uint256(expectedTotalMarketBalance), "market balance");
        // Check markets shares
        int256 expectedTotalMarketShares = getTotalQSquaredForMarket(market.kappa(), expectedTotalMarketBalance);
        assertEq(market.totalQSquared(), predictedNewTotalQSquaredOfMarket, "predictedNewTotalQSquaredOfMarket");
        assertApproxEqRel(market.totalQSquared(), expectedTotalMarketShares, PAYOUT_TOLERANCE, "totalQSquared");
        // Check Bobs position
        (uint256 totalStake, uint256 nftId, BetStatus status) = market.tradersStake(bob);
        assertEq(nftId, SECOND_PREDICTION_ID, "nftId");
        assertEq(totalStake, uint256(costBob), "tradersTotalStake");
        assertEq(market.balanceOf(bob, SECOND_PREDICTION_ID), 1, "balanceOf ERC1155");
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
        // Check the balance of shares at the mean
        uint256 bobBalanceMean = market.getBalanceOfShares(bob, getBucketId(SECOND_MEAN, OUTCOME_UNIT));
        assertGt(bobBalanceMean, 0, "bob balance at mean");
    }

    function test_buyShares_sameTrader_multiplePredictions() public {
        (int256[] memory bucketIds, int256[] memory shares) =
            gen.generateNormalDistribution(INITIAL_MEAN, INITIAL_STD_DEV, OUTCOME_UNIT);

        MarketInitData memory initData = defaultMarketConfig();
        initData.initialBucketIds = bucketIds;
        initData.initialShares = shares;
        market = newMarket(initData);

        // Check alices balances
        assertEq(market.getBalanceOfShares(alice, bucketIds[0]), uint256(shares[0]), "alice balance 1");
        (uint256 totalStake, uint256 nftId, BetStatus status) = market.tradersStake(alice);
        assertEq(totalStake, uint256(INITIAL_BET_VALUE), "tradersTotalStake 1");
        assertEq(nftId, FIRST_PREDICTION_ID, "nftId 1");
        assertEq(market.balanceOf(alice, FIRST_PREDICTION_ID), 1, "alice ERC1155 balance 1");
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");

        (int256 cost,) = market.calculateCostOfTrade(bucketIds, shares);
        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(cost) }(alice, uint256(cost), bucketIds, shares);

        int256 costSoFar = int256(INITIAL_BET_VALUE) + cost;

        // Check alices balances
        assertEq(market.getBalanceOfShares(alice, bucketIds[0]), uint256(2 * shares[0]), "alice balance 2");
        (totalStake, nftId,) = market.tradersStake(alice);
        assertEq(totalStake, uint256(costSoFar), "tradersTotalStake 2");
        assertEq(nftId, FIRST_PREDICTION_ID, "nftId 2"); // Same NFT ID as the first prediction
        assertEq(market.balanceOf(alice, FIRST_PREDICTION_ID), 1, "alice ERC1155 balance 1"); // Same balance of NFT

        (cost,) = market.calculateCostOfTrade(bucketIds, shares);
        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(cost) }(alice, uint256(cost), bucketIds, shares);

        // Check alices balances
        assertEq(market.getBalanceOfShares(alice, bucketIds[0]), uint256(3 * shares[0]), "alice balance 3");
        (totalStake, nftId,) = market.tradersStake(alice);
        assertEq(totalStake, uint256(costSoFar + cost), "tradersTotalStake 3");
        assertEq(nftId, FIRST_PREDICTION_ID, "nftId 3"); // Same NFT ID as the first prediction
        assertEq(market.balanceOf(alice, FIRST_PREDICTION_ID), 1, "alice ERC1155 balance 3"); // Same balance of NFT
    }

    function testFuzz_buyShares(uint256 seed) public {
        OnitIODPMTestBase.NormalTestConfig memory initData = getDefaultNormalTestConfig();
        initData.base.numTests = 20;

        OnitIODPMTestBase.TestPrediction[] memory predictions =
            generateNormalDistributionPredictionArray(initData, seed);

        // Create a market
        MarketInitData memory marketConfig = defaultMarketConfig();
        marketConfig.initiator = predictions[0].predictor;
        marketConfig.initialBucketIds = predictions[0].bucketIds;
        marketConfig.initialShares = predictions[0].shares;
        market = newMarket(marketConfig);

        int256 marketKappa = market.kappa();

        int256 runningTotalValue = int256(INITIAL_BET_VALUE);
        int256 runningTotalQSquared = getTotalQSquaredForMarket(marketKappa, runningTotalValue);

        assertEq(address(market).balance, INITIAL_BET_VALUE, "market balance");
        assertApproxEqRel(market.totalQSquared(), runningTotalQSquared, KAPPA_TOLERANCE, "totalQSquared");
        assertEq(market.nextNftTokenId(), 1, "nextNftTokenId");

        for (uint256 i = 1; i < predictions.length; i++) {
            (int256 cost, int256 predictedNewTotalQSquaredOfMarket) =
                market.calculateCostOfTrade(predictions[i].bucketIds, predictions[i].shares);

            // Make a prediction
            vm.prank(orderRouterAddress);
            market.buyShares{
                value: uint256(cost)
            }(predictions[i].predictor, uint256(cost), predictions[i].bucketIds, predictions[i].shares);

            runningTotalValue += cost;
            runningTotalQSquared += getTotalQSquaredForMarket(marketKappa, runningTotalValue);

            // Market values
            assertEq(address(market).balance, uint256(runningTotalValue), "market balance");
            // assertEq(market.totalQSquared(), runningTotalQSquared, "totalQSquared");
            assertEq(market.totalQSquared(), predictedNewTotalQSquaredOfMarket, "predictedNewTotalQSquaredOfMarket");
            assertEq(market.nextNftTokenId(), i + 1, "nextNftTokenId");

            (uint256 totalStake, uint256 nftId, BetStatus status) = market.tradersStake(predictions[i].predictor);
            assertEq(nftId, i, "nftId");
            assertEq(totalStake, uint256(cost), "tradersTotalStake");
            assertEq(market.balanceOf(predictions[i].predictor, i), 1, "balanceOf ERC1155");
            assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");

            // Erc1155 values
            assertEq(market.balanceOf(predictions[i].predictor, i), 1, "balanceOf ERC1155");

            int256 midBucketId = predictions[i].bucketIds[predictions[i].bucketIds.length / 2];
            int256 midBucketShares = predictions[i].shares[predictions[i].shares.length / 2];
            assertEq(
                market.getBalanceOfShares(predictions[i].predictor, midBucketId),
                uint256(midBucketShares),
                "balanceOfShares"
            );
        }
    }

    function test_buyShares_revert_BucketSharesOverflow() public {
        // Init market
        MarketInitData memory initData = defaultMarketConfig();
        initData.config.maxBetSize = type(uint256).max; // set a huge bet size as we expect cost to be large
        market = newMarket(initData);

        // Get the storage slot of the bucket
        int256 bucketId = DUMMY_BUCKET_IDS[0];
        int256 bucketWordIndex = bucketId / 3;

        // Set the storage slot of the bucket to its max value
        uint256 bucketShares = type(uint80).max;
        stdstore.enable_packed_slots().target(address(market)).sig("bucketOutstandingPackedShares(int256)")
            .with_key(uint256(bucketWordIndex)).checked_write(bucketShares);

        (int256 cost,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        vm.deal(orderRouterAddress, uint256(cost));

        // The call to buyShares should revert
        vm.prank(orderRouterAddress);
        vm.expectRevert(OnitInfiniteOutcomeDPMOutcomeDomain.BucketSharesOverflow.selector);
        market.buyShares{ value: uint256(cost) }(bob, uint256(cost), DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    fallback() external payable { }
    receive() external payable { }
}
