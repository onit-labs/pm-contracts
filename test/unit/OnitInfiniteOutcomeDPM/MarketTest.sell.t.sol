// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Config
import { OnitIODPMTestBase } from "@test/config/OnitIODPMTestBase.t.sol";
// Types
import { BetStatus } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
// Interfaces
import { IOnitMarketResolver } from "@src/interfaces/IOnitMarketResolver.sol";
import { IOnitIODPMOrderManager } from "@src/interfaces/IOnitIODPMOrderManager.sol";
// Contract to test
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";
import { OnitMarketResolver } from "@src/resolvers/OnitMarketResolver.sol";
import {
    OnitInfiniteOutcomeDPMOutcomeDomain
} from "@src/mechanisms/infinite-outcome-DPM/OnitInfiniteOutcomeDPMOutcomeDomain.sol";
import { OnitIODPMOrderManager } from "@src/order-manager/OnitIODPMOrderManager.sol";

contract InfiniteOutcomeDPMTestSellShares is OnitIODPMTestBase {
    function test_sellShares_reverts_NotFromOrderRouter() public {
        market = newMarketWithDefaultConfig();

        int256[] memory sellBucketIds = new int256[](1);
        int256[] memory sellShares = new int256[](1);
        sellBucketIds[0] = DUMMY_BUCKET_IDS[1];
        sellShares[0] = -DUMMY_SHARES[1];

        vm.expectRevert(IOnitIODPMOrderManager.NotFromOrderRouter.selector);
        vm.prank(alice);
        market.sellShares(alice, sellBucketIds, sellShares);
    }

    function test_sellShares_reverts_NothingToPay() public {
        market = newMarketWithDefaultConfig();

        vm.expectRevert(IOnitIODPMOrderManager.NothingToPay.selector);
        vm.prank(address(orderRouter));
        market.sellShares(bob, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_sellShares_reverts_MarketIsResolved() public {
        market = newMarketWithDefaultConfig();

        vm.prank(RESOLVER_1);
        market.resolveMarket(1);

        vm.expectRevert(IOnitMarketResolver.MarketIsResolved.selector);
        vm.prank(address(orderRouter));
        market.sellShares(alice, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_sellShares_reverts_MarketIsVoided() public {
        market = newMarketWithDefaultConfig();

        market.voidMarket();

        vm.expectRevert(IOnitMarketResolver.MarketIsVoided.selector);
        vm.prank(address(orderRouter));
        market.sellShares(alice, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_sellShares_reverts_InsufficientShares() public {
        market = newMarketWithDefaultConfig();

        int256[] memory sellBucketIds = new int256[](1);
        int256[] memory sellShares = new int256[](1);
        sellBucketIds[0] = DUMMY_BUCKET_IDS[1];
        sellShares[0] = -2 * DUMMY_SHARES[1]; // sell 2x the users shares
        vm.expectRevert(OnitInfiniteOutcomeDPMOutcomeDomain.InsufficientShares.selector);
        vm.prank(address(orderRouter));
        market.sellShares(alice, sellBucketIds, sellShares);
    }

    function test_sellShares_reverts_InvalidSharesValue_cannotSellPositiveValues() public {
        market = newMarketWithDefaultConfig();

        vm.expectRevert(IOnitIODPMOrderManager.InvalidSharesValue.selector);
        vm.prank(address(orderRouter));
        market.sellShares(alice, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_sellShares_singleSeller() public {
        market = newMarketWithDefaultConfig();

        int256 bucketId = DUMMY_BUCKET_IDS[1];
        int256 midBucketOutstandingShares = market.getBucketOutstandingShares(bucketId);

        // Check market values
        assertEq(midBucketOutstandingShares, 1, "midBucketOutstandingShares 1");
        assertEq(market.totalQSquared(), DUMMY_INITIAL_TOTAL_Q_SQUARED, "totalQSquared 1");

        // Check alice's balance
        uint256 aliceBalanceBefore = alice.balance; // used to check payout later
        assertEq(int256(market.getBalanceOfShares(alice, bucketId)), DUMMY_SHARES[1], "balanceOfShares 1");
        assertEq(market.balanceOf(alice, uint256(FIRST_PREDICTION_ID)), 1, "balanceOfERC1155 1");
        (uint256 totalStake, uint256 nftId, BetStatus status) = market.tradersStake(alice);
        assertEq(totalStake, uint256(INITIAL_BET_VALUE), "totalStake 1");
        assertEq(nftId, 0, "nftId 1");
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");

        // Setup the sale of 1 share
        int256[] memory sellBucketIds = new int256[](1);
        int256[] memory sellShares = new int256[](1);
        sellBucketIds[0] = bucketId;
        sellShares[0] = -DUMMY_SHARES[1];

        // Get the expected cost diff of the trade (the amount alice will receive)
        vm.prank(alice);
        (int256 saleCostDiff,) = market.calculateCostOfTrade(sellBucketIds, sellShares);

        vm.prank(address(orderRouter));
        market.sellShares(alice, sellBucketIds, sellShares);

        midBucketOutstandingShares = market.getBucketOutstandingShares(bucketId);

        // Check market values
        assertEq(midBucketOutstandingShares, int256(0), "midBucketOutstandingShares 2");
        assertEq(
            market.totalQSquared(), DUMMY_INITIAL_TOTAL_Q_SQUARED - DUMMY_SHARES[1] * DUMMY_SHARES[1], "totalQSquared2"
        );

        // Check alice's balance
        assertEq(alice.balance, aliceBalanceBefore + uint256(-saleCostDiff), "alice's balance 2");
        assertEq(int256(market.getBalanceOfShares(alice, bucketId)), int256(0), "balanceOfShares 2");
        assertEq(market.balanceOf(alice, uint256(FIRST_PREDICTION_ID)), 1, "balanceOfERC1155 2");

        (totalStake, nftId, status) = market.tradersStake(alice);
        uint256 expectedStakeAfter =
            uint256(INITIAL_BET_VALUE) > uint256(-saleCostDiff)
            ? uint256(INITIAL_BET_VALUE) - uint256(-saleCostDiff)
            : 0;
        assertEq(totalStake, expectedStakeAfter, "totalStake 2");
        assertEq(nftId, 0, "nftId remains unchanged until payout/void");
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
    }

    function test_sellShares_multipleSellers() public {
        market = newMarketWithDefaultConfig();

        // Get bob a bet using order router
        (int256 bobBetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        uint256 bobBetValue = uint256(bobBetAmount);

        vm.prank(bob);
        orderRouter.executeOrder{
            value: bobBetValue
        }(address(market), bob, bobBetValue, DUMMY_BUCKET_IDS, DUMMY_SHARES, "");

        // Verify bob has a stake and NFT
        (uint256 bobStake, uint256 bobNftId,) = market.tradersStake(bob);
        assertEq(bobStake, bobBetValue, "bob should have stake");
        assertEq(bobNftId, 1, "bob should have NFT ID 1");

        // Alice sells her shares
        int256[] memory aliceSellBucketIds = new int256[](1);
        int256[] memory aliceSellShares = new int256[](1);
        aliceSellBucketIds[0] = DUMMY_BUCKET_IDS[1];
        aliceSellShares[0] = -DUMMY_SHARES[1];

        // compute expected according to payout from sell (recalculate for this specific trade)
        int256[] memory aliceSellBucketIds2 = new int256[](1);
        int256[] memory aliceSellShares2 = new int256[](1);
        aliceSellBucketIds2[0] = DUMMY_BUCKET_IDS[1];
        aliceSellShares2[0] = -DUMMY_SHARES[1];

        (int256 aliceSaleCostDiff,) = market.calculateCostOfTrade(aliceSellBucketIds2, aliceSellShares2);
        uint256 expectedAliceStakeAfter = uint256(INITIAL_BET_VALUE) > uint256(-aliceSaleCostDiff)
            ? uint256(INITIAL_BET_VALUE) - uint256(-aliceSaleCostDiff)
            : 0;

        vm.prank(address(orderRouter));
        market.sellShares(alice, aliceSellBucketIds, aliceSellShares);

        // Verify alice's stake is zeroed and NFT is burned
        (uint256 aliceStake, uint256 aliceNftId,) = market.tradersStake(alice);
        assertEq(aliceStake, expectedAliceStakeAfter, "alice stake after sell");
        assertEq(aliceNftId, 0, "alice NFT ID remains until payout/void");
        assertEq(market.balanceOf(alice, 0), 1, "alice NFT should remain");

        // Bob sells his shares
        int256[] memory bobSellBucketIds = new int256[](1);
        int256[] memory bobSellShares = new int256[](1);
        bobSellBucketIds[0] = DUMMY_BUCKET_IDS[1];
        bobSellShares[0] = -DUMMY_SHARES[1];

        // compute expected according to payout from sell
        int256[] memory bobSellBucketIds2 = new int256[](1);
        int256[] memory bobSellShares2 = new int256[](1);
        bobSellBucketIds2[0] = DUMMY_BUCKET_IDS[1];
        bobSellShares2[0] = -DUMMY_SHARES[1];

        (int256 bobSaleCostDiff,) = market.calculateCostOfTrade(bobSellBucketIds2, bobSellShares2);
        uint256 expectedBobStakeAfter =
            bobBetValue > uint256(-bobSaleCostDiff) ? bobBetValue - uint256(-bobSaleCostDiff) : 0;

        vm.prank(address(orderRouter));
        market.sellShares(bob, bobSellBucketIds, bobSellShares);

        // Verify bob's stake is zeroed and NFT is burned
        (uint256 bobStakeAfter, uint256 bobNftIdAfter,) = market.tradersStake(bob);
        assertEq(bobStakeAfter, expectedBobStakeAfter, "bob stake after sell");
        assertEq(bobNftIdAfter, 1, "bob NFT ID remains until payout/void");
        assertEq(market.balanceOf(bob, 1), 1, "bob NFT should remain");
    }
}
