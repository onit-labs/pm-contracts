// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

/* solhint-disable max-line-length */

// Misc utils
import { stdStorage, StdStorage } from "forge-std/Test.sol";
// Config
import { MockErc20 } from "@test/mocks/MockErc20.sol";
import { OnitIODPMTestBase } from "@test/config/OnitIODPMTestBase.t.sol";
// Types
import { BetStatus, MarketInitData } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
// Interfaces
import { IOnitInfiniteOutcomeDPM } from "@src/interfaces/IOnitInfiniteOutcomeDPM.sol";
import { IOnitMarketResolver } from "@src/interfaces/IOnitMarketResolver.sol";
import { IOnitIODPMOrderManager } from "@src/interfaces/IOnitIODPMOrderManager.sol";
import { IOnitInfiniteOutcomeDPMMechanism } from "@src/interfaces/IOnitInfiniteOutcomeDPMMechanism.sol";
// Contract to test
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";
import {
    OnitInfiniteOutcomeDPMOutcomeDomain
} from "@src/mechanisms/infinite-outcome-DPM/OnitInfiniteOutcomeDPMOutcomeDomain.sol";
import { OnitIODPMOrderManager } from "@src/order-manager/OnitIODPMOrderManager.sol";
import { OnitMarketResolver } from "@src/resolvers/OnitMarketResolver.sol";
import {
    OnitInfiniteOutcomeDPMMechanism
} from "@src/mechanisms/infinite-outcome-DPM/OnitInfiniteOutcomeDPMMechanism.sol";

// Infinite Outcome DPM: buyShares
contract IODPMTestBuySharesToken is OnitIODPMTestBase {
    using stdStorage for StdStorage;

    MockErc20 tokenB;

    function setUp() public {
        tokenB = new MockErc20("B", "B", 18);

        tokenA.mint(alice, 1000 ether);
        tokenB.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);
        tokenB.mint(bob, 1000 ether);

        address[] memory resolvers = new address[](1);
        resolvers[0] = RESOLVER_1;
    }

    function test_buyShares_token_reverts_NotFromOrderRouter() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();
        vm.prank(bob);
        vm.expectRevert(IOnitIODPMOrderManager.NotFromOrderRouter.selector);
        market.buyShares(bob, INITIAL_BET_VALUE, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_token_reverts_BettingCutoffPassed() public {
        // Setup market with a betting cutoff
        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.config.bettingCutoff = BETTING_CUTOFF_ONE_DAY;

        OnitInfiniteOutcomeDPM market = newMarket(initData);

        // Warp past the betting cutoff
        vm.warp(block.timestamp + 2 days);

        // Expect revert when trying to buy shares
        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitInfiniteOutcomeDPM.BettingCutoffPassed.selector);
        market.buyShares(bob, INITIAL_BET_VALUE, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_token_reverts_MarketIsResolved() public {
        // Create market
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        // Resolve the market
        vm.prank(RESOLVER_1);
        market.resolveMarket(1);

        // Expect revert when trying to buy shares
        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitMarketResolver.MarketIsResolved.selector);
        market.buyShares(bob, INITIAL_BET_VALUE, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_token_reverts_MarketIsVoided() public {
        // Create market
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        // Void the market
        market.voidMarket();

        // Expect revert when trying to buy shares
        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitMarketResolver.MarketIsVoided.selector);
        market.buyShares(bob, INITIAL_BET_VALUE, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_token_reverts_BetValueOutOfBounds_belowMinBetSize() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();
        // Prepare for trade with very small amount
        int256 tooSmallAmount = 0.000_09 ether;

        // Expect revert when trying to buy shares with too small amount
        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitIODPMOrderManager.BetValueOutOfBounds.selector);
        market.buyShares(bob, uint256(tooSmallAmount), DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_token_reverts_BetValueOutOfBounds_aboveMaxBetSize() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        // Prepare for trade with very large amount
        int256 tooLargeAmount = 1.1 ether;

        // Expect revert when trying to buy shares with too large amount
        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitIODPMOrderManager.BetValueOutOfBounds.selector);
        market.buyShares(bob, uint256(tooLargeAmount), DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_token_reverts_IncorrectBetValue() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        // Calculate correct cost
        (int256 costDiff,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);

        // Attempt to use incorrect amount (slightly less)
        int256 incorrectAmount = costDiff - 10;

        // Expect revert when trying to buy shares with incorrect amount
        bytes memory errorData =
            abi.encodeWithSelector(IOnitIODPMOrderManager.IncorrectBetValue.selector, costDiff, incorrectAmount);

        vm.prank(orderRouterAddress);
        vm.expectRevert(errorData);
        market.buyShares(bob, uint256(incorrectAmount), DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_buyShares_token_reverts_BetValueOutOfBounds_noValues() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        int256[] memory emptyBucketIds = new int256[](0);
        int256[] memory emptyShares = new int256[](0);

        // This will be 0 so less than the min bet size
        (int256 costDiff,) = market.calculateCostOfTrade(emptyBucketIds, emptyShares);

        // Expect revert when trying to buy shares with empty arrays
        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitIODPMOrderManager.BetValueOutOfBounds.selector);
        market.buyShares(bob, uint256(costDiff), emptyBucketIds, emptyShares);
    }

    function test_buyShares_token_reverts_BucketIdsNotStrictlyIncreasing() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        // Create bucket IDs that aren't strictly increasing
        int256[] memory bucketIds = new int256[](2);
        bucketIds[0] = 0;
        bucketIds[1] = 0; // Same as bucketIds[0], not strictly increasing

        int256[] memory shares = new int256[](2);
        shares[0] = 1;
        shares[1] = 2;

        // Calculate cost (this will actually fail but we'll handle it)
        (int256 costDiff,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);

        // Expect revert when trying to buy shares with non-strictly increasing bucket IDs
        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitInfiniteOutcomeDPMMechanism.BucketIdsNotStrictlyIncreasing.selector);
        market.buyShares(bob, uint256(costDiff), bucketIds, shares);
    }

    function test_buyShares_token_reverts_IncorrectBetValue_negativeCostDiff() public {
        // Create a market with some initial positions
        int256[] memory bucketIds = new int256[](2);
        bucketIds[0] = 0;
        bucketIds[1] = 1;

        int256[] memory shares = new int256[](2);
        shares[0] = 2;
        shares[1] = 2;

        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.initialBucketIds = bucketIds;
        initData.initialShares = shares;

        OnitInfiniteOutcomeDPM market = newMarket(initData);

        // Create negative shares for the same buckets
        int256[] memory negativeShares = new int256[](2);
        negativeShares[0] = -1;
        negativeShares[1] = -1;

        // Calculate cost (will be negative)
        (int256 cost2,) = market.calculateCostOfTrade(bucketIds, negativeShares);

        // Expect revert when trying to buy shares with negative cost
        bytes memory errorData =
            abi.encodeWithSelector(IOnitIODPMOrderManager.IncorrectBetValue.selector, cost2, -cost2);

        vm.prank(orderRouterAddress);
        vm.expectRevert(errorData);
        market.buyShares(alice, uint256(-cost2), bucketIds, negativeShares);
    }

    function test_buyShares_single() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        (int256 cost,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);

        vm.prank(orderRouterAddress);
        market.buyShares(bob, uint256(cost), DUMMY_BUCKET_IDS, DUMMY_SHARES);

        (uint256 totalStake, uint256 nftId, BetStatus status) = market.tradersStake(bob);
        assertEq(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[0]), uint256(DUMMY_SHARES[0]), "balanceOfShares");
        assertEq(totalStake, uint256(cost), "tradersStake");
        assertEq(nftId, 1, "nftId");
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
        assertEq(market.balanceOf(bob, 1), 1, "balanceOf ERC1155");
    }

    function testFuzz_buyShares_token(uint256 seed) public {
        NormalTestConfig memory betConfig = getDefaultNormalTestConfig();
        betConfig.base.numTests = 20;

        TestPrediction[] memory predictions = generateNormalDistributionPredictionArray(betConfig, seed);

        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.initialBucketIds = predictions[0].bucketIds;
        initData.initialShares = predictions[0].shares;

        // Create a market with the first prediction
        OnitInfiniteOutcomeDPM market = newMarket(initData);

        int256 marketKappa = market.kappa();

        int256 runningTotalValue = int256(INITIAL_BET_VALUE);
        int256 runningTotalQSquared = getTotalQSquaredForMarket(marketKappa, runningTotalValue);

        assertApproxEqRel(market.totalQSquared(), runningTotalQSquared, KAPPA_TOLERANCE, "totalQSquared");
        assertEq(market.nextNftTokenId(), 1, "nextNftTokenId");

        // Make predictions in sequence
        for (uint256 i = 1; i < predictions.length; i++) {
            (int256 cost, int256 predictedNewTotalQSquaredOfMarket) =
                market.calculateCostOfTrade(predictions[i].bucketIds, predictions[i].shares);

            // Make a prediction
            vm.prank(orderRouterAddress);
            market.buyShares(predictions[i].predictor, uint256(cost), predictions[i].bucketIds, predictions[i].shares);

            runningTotalValue += cost;
            runningTotalQSquared = getTotalQSquaredForMarket(marketKappa, runningTotalValue);

            // Market values
            assertEq(market.totalQSquared(), predictedNewTotalQSquaredOfMarket, "predictedNewTotalQSquaredOfMarket");
            assertEq(market.nextNftTokenId(), i + 1, "nextNftTokenId");

            // Trader stake and NFT
            (uint256 totalStake, uint256 nftId, BetStatus status) = market.tradersStake(predictions[i].predictor);
            assertEq(nftId, i, "nftId");
            assertEq(totalStake, uint256(cost), "tradersTotalStake");
            assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
            assertEq(market.balanceOf(predictions[i].predictor, i), 1, "balanceOf ERC1155");

            // Check shares balance
            int256 midBucketId = predictions[i].bucketIds[predictions[i].bucketIds.length / 2];
            int256 midBucketShares = predictions[i].shares[predictions[i].shares.length / 2];
            assertEq(
                market.getBalanceOfShares(predictions[i].predictor, midBucketId),
                uint256(midBucketShares),
                "balanceOfShares"
            );
        }
    }

    function test_buyShares_token_sameTrader_multiplePredictions() public {
        // Get test data
        (int256[] memory bucketIds, int256[] memory shares) =
            gen.generateNormalDistribution(INITIAL_MEAN, INITIAL_STD_DEV, OUTCOME_UNIT);

        // get cost of initial bet
        int256 kappa = getKappaForInitialMarket(DUMMY_SHARES, int256(INITIAL_BET_VALUE));
        (int256 initialBetValue,) = getCostOfInitialBet(kappa, DUMMY_SHARES);

        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.initialBetSize = uint256(initialBetValue);
        initData.initialBucketIds = bucketIds;
        initData.initialShares = shares;

        // Setup market with initial shares
        OnitInfiniteOutcomeDPM market = newMarket(initData);

        // Check alice's initial balances
        assertEq(market.getBalanceOfShares(alice, bucketIds[0]), uint256(shares[0]), "alice balance 1");
        (uint256 totalStake, uint256 nftId, BetStatus status) = market.tradersStake(alice);
        assertEq(totalStake, uint256(INITIAL_BET_VALUE), "tradersTotalStake 1");
        assertEq(nftId, FIRST_PREDICTION_ID, "nftId 1");
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
        assertEq(market.balanceOf(alice, FIRST_PREDICTION_ID), 1, "alice ERC1155 balance 1");

        // Alice makes a second prediction
        (int256 cost,) = market.calculateCostOfTrade(bucketIds, shares);

        vm.prank(orderRouterAddress);
        market.buyShares(alice, uint256(cost), bucketIds, shares);

        int256 costSoFar = int256(INITIAL_BET_VALUE) + cost;

        // Check alice's balances after second prediction
        assertEq(market.getBalanceOfShares(alice, bucketIds[0]), uint256(2 * shares[0]), "alice balance 2");
        (totalStake, nftId,) = market.tradersStake(alice);
        assertEq(totalStake, uint256(costSoFar), "tradersTotalStake 2");
        assertEq(nftId, FIRST_PREDICTION_ID, "nftId 2"); // Same NFT ID as the first prediction
        assertEq(market.balanceOf(alice, FIRST_PREDICTION_ID), 1, "alice ERC1155 balance 2"); // Same balance of NFT

        // Alice makes a third prediction
        (cost,) = market.calculateCostOfTrade(bucketIds, shares);

        vm.prank(orderRouterAddress);
        market.buyShares(alice, uint256(cost), bucketIds, shares);

        // Check alice's balances after third prediction
        assertEq(market.getBalanceOfShares(alice, bucketIds[0]), uint256(3 * shares[0]), "alice balance 3");
        (totalStake, nftId,) = market.tradersStake(alice);
        assertEq(totalStake, uint256(costSoFar + cost), "tradersTotalStake 3");
        assertEq(nftId, FIRST_PREDICTION_ID, "nftId 3"); // Same NFT ID as the first prediction
        assertEq(market.balanceOf(alice, FIRST_PREDICTION_ID), 1, "alice ERC1155 balance 3"); // Same balance of NFT
    }

    function test_buyShares_token_revert_BucketSharesOverflow() public {
        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.config.maxBetSize = type(uint256).max; // set a huge bet size as we expect cost to be large
        market = newMarket(initData);

        // Get the storage slot of the bucket
        int256 bucketId = DUMMY_BUCKET_IDS[0];
        int256 bucketWordIndex = bucketId / 3;

        // Set the storage slot of the bucket to be at its max value
        uint256 bucketShares = type(uint80).max;
        stdstore.enable_packed_slots().target(address(market)).sig("bucketOutstandingPackedShares(int256)")
            .with_key(uint256(bucketWordIndex)).checked_write(bucketShares);

        (int256 cost,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);

        // The call to buyShares should revert
        vm.prank(orderRouterAddress);
        vm.expectRevert(OnitInfiniteOutcomeDPMOutcomeDomain.BucketSharesOverflow.selector);
        market.buyShares(bob, uint256(cost), DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    // -------------------------------------------------------------------------------------------------
    // Helper functions
    // -------------------------------------------------------------------------------------------------

    fallback() external payable { }
    receive() external payable { }
}

// Awkward work around to use try catch to catch a revert which is not the next call
contract Wrapper is OnitIODPMTestBase {
    function externalCall(MarketInitData memory initData) external {
        newMarket(initData);
    }
}
