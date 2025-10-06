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

contract InfiniteOutcomeDPMTestSellSharesToken is OnitIODPMTestBase {
    uint256 FUTURE_SPEND_DEADLINE = block.timestamp + 1 days;

    function setUp() public {
        tokenA.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);
    }

    function test_sellShares_token_reverts_NotFromOrderRouter() public {
        market = newMarketWithDefaultConfigWithToken();

        int256[] memory sellBucketIds = new int256[](1);
        int256[] memory sellShares = new int256[](1);
        sellBucketIds[0] = DUMMY_BUCKET_IDS[1];
        sellShares[0] = -DUMMY_SHARES[1];

        vm.expectRevert(IOnitIODPMOrderManager.NotFromOrderRouter.selector);
        vm.prank(alice);
        market.sellShares(alice, sellBucketIds, sellShares);
    }

    function test_sellShares_token_reverts_NothingToPay() public {
        market = newMarketWithDefaultConfigWithToken();

        vm.expectRevert(IOnitIODPMOrderManager.NothingToPay.selector);
        vm.prank(address(orderRouter));
        market.sellShares(bob, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_sellShares_token_reverts_MarketIsResolved() public {
        market = newMarketWithDefaultConfigWithToken();

        vm.prank(RESOLVER_1);
        market.resolveMarket(1);

        vm.expectRevert(IOnitMarketResolver.MarketIsResolved.selector);
        vm.prank(address(orderRouter));
        market.sellShares(alice, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_sellShares_token_reverts_MarketIsVoided() public {
        market = newMarketWithDefaultConfigWithToken();

        market.voidMarket();

        vm.expectRevert(IOnitMarketResolver.MarketIsVoided.selector);
        vm.prank(address(orderRouter));
        market.sellShares(alice, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_sellShares_token_reverts_InsufficientShares() public {
        market = newMarketWithDefaultConfigWithToken();

        int256[] memory sellBucketIds = new int256[](1);
        int256[] memory sellShares = new int256[](1);
        sellBucketIds[0] = DUMMY_BUCKET_IDS[1];
        sellShares[0] = -2 * DUMMY_SHARES[1]; // sell 2x the users shares
        vm.expectRevert(OnitInfiniteOutcomeDPMOutcomeDomain.InsufficientShares.selector);
        vm.prank(address(orderRouter));
        market.sellShares(alice, sellBucketIds, sellShares);
    }

    function test_sellShares_token_reverts_InvalidSharesValue_cannotSellPositiveValues() public {
        market = newMarketWithDefaultConfigWithToken();

        vm.expectRevert(IOnitIODPMOrderManager.InvalidSharesValue.selector);
        vm.prank(address(orderRouter));
        market.sellShares(alice, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_sellShares_token_singleSeller() public {
        market = newMarketWithDefaultConfigWithToken();

        int256 bucketId = DUMMY_BUCKET_IDS[1];
        int256 midBucketOutstandingShares = market.getBucketOutstandingShares(bucketId);

        // Check market values
        assertEq(midBucketOutstandingShares, 1, "midBucketOutstandingShares 1");
        assertEq(market.totalQSquared(), DUMMY_INITIAL_TOTAL_Q_SQUARED, "totalQSquared 1");

        // Check alice's balance
        uint256 aliceTokenBalanceBefore = tokenA.balanceOf(alice);
        assertEq(int256(market.getBalanceOfShares(alice, bucketId)), DUMMY_SHARES[1], "balanceOfShares 1");
        assertEq(market.balanceOf(alice, uint256(FIRST_PREDICTION_ID)), 1, "balanceOfERC1155 1");
        (uint256 totalStake, uint256 nftId, BetStatus status) = market.tradersStake(alice);
        assertEq(totalStake, uint256(INITIAL_BET_VALUE), "totalStake 1");
        assertEq(nftId, 0, "nftId 1");

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

        // Check alice's token balance
        assertEq(tokenA.balanceOf(alice), aliceTokenBalanceBefore + uint256(-saleCostDiff), "alice's token balance 2");
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

    function test_sellShares_token_multipleSellers() public {
        market = newMarketWithDefaultConfigWithToken();

        // Get bob a bet using order router
        (int256 bobBetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        uint256 bobBetValue = uint256(bobBetAmount);

        // Generate permit signature for bob
        (uint8 v, bytes32 r, bytes32 s) =
            getPermitSignature(tokenAAddress, bob, orderRouterAddress, bobBetValue, FUTURE_SPEND_DEADLINE, bobPk);

        bytes memory orderData = encodeOrderRouterPermitData(0, FUTURE_SPEND_DEADLINE, v, r, s);

        vm.prank(bob);
        orderRouter.executeOrder(address(market), bob, bobBetValue, DUMMY_BUCKET_IDS, DUMMY_SHARES, orderData);

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
        vm.prank(alice);
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
        vm.prank(bob);
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

    // function test_sellSharesPartial_token_multipleTradersWithOverlappingBuckets() public {
    // market = newMarketWithDefaultConfigWithToken();

    // // Setup 3 traders with overlapping bets on the same buckets
    // // Alice already has a bet from market creation
    // // Bob will bet on buckets 1 and 2 (overlapping with Alice on bucket 1)
    // // Carl will bet on buckets 2 and 3 (overlapping with Bob on bucket 2)

    // // Bob's bet: buckets 1 and 2
    // int256[] memory bobBucketIds = new int256[](2);
    // int256[] memory bobShares = new int256[](2);
    // bobBucketIds[0] = DUMMY_BUCKET_IDS[1]; // bucket 1
    // bobBucketIds[1] = DUMMY_BUCKET_IDS[2]; // bucket 2
    // bobShares[0] = DUMMY_SHARES[1]; // 1 share
    // bobShares[1] = DUMMY_SHARES[2]; // 1 share

    // (int256 bobBetAmount,) = market.calculateCostOfTrade(bobBucketIds, bobShares);
    // uint256 bobBetValue = uint256(bobBetAmount);

    // // Generate permit signature for bob
    // (uint8 v, bytes32 r, bytes32 s) =
    // getPermitSignature(tokenAAddress, bob, orderRouterAddress, bobBetValue, FUTURE_SPEND_DEADLINE, bobPk);

    // bytes memory orderData = encodeOrderRouterPermitData(0, FUTURE_SPEND_DEADLINE, v, r, s);

    // vm.prank(bob);
    // orderRouter.executeOrder(address(market), bob, bobBetValue, bobBucketIds, bobShares, orderData);

    // // Carl's bet: buckets 2 and 3
    // int256[] memory carlBucketIds = new int256[](2);
    // int256[] memory carlShares = new int256[](2);
    // carlBucketIds[0] = DUMMY_BUCKET_IDS[2]; // bucket 2
    // carlBucketIds[1] = DUMMY_BUCKET_IDS[3]; // bucket 3
    // carlShares[0] = DUMMY_SHARES[2]; // 1 share
    // carlShares[1] = DUMMY_SHARES[3]; // 1 share

    // (int256 carlBetAmount,) = market.calculateCostOfTrade(carlBucketIds, carlShares);
    // uint256 carlBetValue = uint256(carlBetAmount);

    // // Generate permit signature for carl
    // (v, r, s) =
    // getPermitSignature(tokenAAddress, carl, orderRouterAddress, carlBetValue, FUTURE_SPEND_DEADLINE, carlPk);

    // orderData = encodeOrderRouterPermitData(0, FUTURE_SPEND_DEADLINE, v, r, s);

    // vm.prank(carl);
    // orderRouter.executeOrder(address(market), carl, carlBetValue, carlBucketIds, carlShares, orderData);

    // // Verify initial positions
    // assertEq(
    // int256(market.getBalanceOfShares(alice, DUMMY_BUCKET_IDS[1])), DUMMY_SHARES[1], "alice bucket 1 shares"
    //);
    // assertEq(int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[1])), DUMMY_SHARES[1], "bob bucket 1
    // shares");
    // assertEq(int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[2])), DUMMY_SHARES[2], "bob bucket 2
    // shares");
    // assertEq(int256(market.getBalanceOfShares(carl, DUMMY_BUCKET_IDS[2])), DUMMY_SHARES[2], "carl bucket 2
    // shares");
    // assertEq(int256(market.getBalanceOfShares(carl, DUMMY_BUCKET_IDS[3])), DUMMY_SHARES[3], "carl bucket 3
    // shares");

    // // Test partial selling: Alice sells half her position in bucket 1
    // int256[] memory alicePartialSellBucketIds = new int256[](1);
    // int256[] memory alicePartialSellShares = new int256[](1);
    // alicePartialSellBucketIds[0] = DUMMY_BUCKET_IDS[1];
    // alicePartialSellShares[0] = -DUMMY_SHARES[1] / 2; // sell half

    // uint256 aliceTokenBalanceBefore = tokenA.balanceOf(alice);
    // (uint256 aliceStakeBefore,) = market.tradersStake(alice);

    // vm.prank(alice);
    // market.sellSharesPartial(alicePartialSellBucketIds, alicePartialSellShares);

    // // Verify Alice's partial position remains
    // assertEq(
    // int256(market.getBalanceOfShares(alice, DUMMY_BUCKET_IDS[1])),
    // DUMMY_SHARES[1] / 2,
    // "alice bucket 1 shares after partial sell"
    //);
    // assertEq(market.balanceOf(alice, uint256(FIRST_PREDICTION_ID)), 1, "alice NFT should still exist");

    // // Verify Alice's stake was reduced but not zeroed
    // (uint256 aliceStakeAfter,) = market.tradersStake(alice);
    // assertGt(aliceStakeAfter, 0, "alice stake should be reduced but not zeroed");
    // assertLt(aliceStakeAfter, aliceStakeBefore, "alice stake should be reduced");

    // // Test full selling: Bob sells his entire position in bucket 1
    // int256[] memory bobFullSellBucketIds = new int256[](1);
    // int256[] memory bobFullSellShares = new int256[](1);
    // bobFullSellBucketIds[0] = DUMMY_BUCKET_IDS[1];
    // bobFullSellShares[0] = -DUMMY_SHARES[1]; // sell all

    // uint256 bobTokenBalanceBefore = tokenA.balanceOf(bob);
    // (uint256 bobStakeBefore,) = market.tradersStake(bob);

    // vm.prank(bob);
    // market.sellShares(bobFullSellBucketIds, bobFullSellShares);

    // // Verify Bob's position in bucket 1 is zeroed
    // assertEq(int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[1])), 0, "bob bucket 1 shares should be
    // zeroed");
    // // But Bob still has shares in bucket 2
    // assertEq(
    // int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[2])),
    // DUMMY_SHARES[2],
    // "bob bucket 2 shares should remain"
    //);

    // // Verify Bob's stake was reduced but not zeroed (still has bucket 2)
    // (uint256 bobStakeAfter,) = market.tradersStake(bob);
    // assertGt(bobStakeAfter, 0, "bob stake should be reduced but not zeroed");
    // assertLt(bobStakeAfter, bobStakeBefore, "bob stake should be reduced");

    // // Test partial selling: Carl sells half his position in bucket 2
    // int256[] memory carlPartialSellBucketIds = new int256[](1);
    // int256[] memory carlPartialSellShares = new int256[](1);
    // carlPartialSellBucketIds[0] = DUMMY_BUCKET_IDS[2];
    // carlPartialSellShares[0] = -DUMMY_SHARES[2] / 2; // sell half

    // uint256 carlTokenBalanceBefore = tokenA.balanceOf(carl);
    // (uint256 carlStakeBefore,) = market.tradersStake(carl);

    // vm.prank(carl);
    // market.sellSharesPartial(carlPartialSellBucketIds, carlPartialSellShares);

    // // Verify Carl's partial position remains
    // assertEq(
    // int256(market.getBalanceOfShares(carl, DUMMY_BUCKET_IDS[2])),
    // DUMMY_SHARES[2] / 2,
    // "carl bucket 2 shares after partial sell"
    //);
    // assertEq(
    // int256(market.getBalanceOfShares(carl, DUMMY_BUCKET_IDS[3])),
    // DUMMY_SHARES[3],
    // "carl bucket 3 shares should remain unchanged"
    //);

    // // Verify Carl's stake was reduced but not zeroed
    // (uint256 carlStakeAfter,) = market.tradersStake(carl);
    // assertGt(carlStakeAfter, 0, "carl stake should be reduced but not zeroed");
    // assertLt(carlStakeAfter, carlStakeBefore, "carl stake should be reduced");

    // // Verify market state is consistent
    // assertEq(
    // market.getBucketOutstandingShares(DUMMY_BUCKET_IDS[1]),
    // DUMMY_SHARES[1] / 2,
    // "bucket 1 total shares should be half"
    //);
    // assertEq(
    // market.getBucketOutstandingShares(DUMMY_BUCKET_IDS[2]),
    // DUMMY_SHARES[2] + DUMMY_SHARES[2] / 2,
    // "bucket 2 total shares should be bob's full + carl's half"
    //);
    // assertEq(
    // market.getBucketOutstandingShares(DUMMY_BUCKET_IDS[3]),
    // DUMMY_SHARES[3],
    // "bucket 3 total shares should remain unchanged"
    //);
    //}

    // function test_sellSharesPartial_multipleTradersWithOverlappingBuckets() public {
    // // Create a market with native ETH instead of tokens
    // market = newMarketWithDefaultConfig();

    // // Setup 3 traders with overlapping bets on the same buckets
    // // Alice already has a bet from market creation
    // // Bob will bet on buckets 1 and 2 (overlapping with Alice on bucket 1)
    // // Carl will bet on buckets 2 and 3 (overlapping with Bob on bucket 2)

    // // Bob's bet: buckets 1 and 2
    // int256[] memory bobBucketIds = new int256[](2);
    // int256[] memory bobShares = new int256[](2);
    // bobBucketIds[0] = DUMMY_BUCKET_IDS[1]; // bucket 1
    // bobBucketIds[1] = DUMMY_BUCKET_IDS[2]; // bucket 2
    // bobShares[0] = DUMMY_SHARES[1]; // 1 share
    // bobShares[1] = DUMMY_SHARES[2]; // 1 share

    // (int256 bobBetAmount,) = market.calculateCostOfTrade(bobBucketIds, bobShares);
    // uint256 bobBetValue = uint256(bobBetAmount);

    // // Bob places his bet directly with ETH
    // vm.deal(bob, bobBetValue);
    // vm.prank(bob);
    // market.buyShares{ value: bobBetValue }(bobBucketIds, bobShares);

    // // Carl's bet: buckets 2 and 3
    // int256[] memory carlBucketIds = new int256[](2);
    // int256[] memory carlShares = new int256[](2);
    // carlBucketIds[0] = DUMMY_BUCKET_IDS[2]; // bucket 2
    // carlBucketIds[1] = DUMMY_BUCKET_IDS[3]; // bucket 3
    // carlShares[0] = DUMMY_SHARES[2]; // 1 share
    // carlShares[1] = DUMMY_SHARES[3]; // 1 share

    // (int256 carlBetAmount,) = market.calculateCostOfTrade(carlBucketIds, carlShares);
    // uint256 carlBetValue = uint256(carlBetAmount);

    // // Carl places his bet directly with ETH
    // vm.deal(carl, carlBetValue);
    // vm.prank(carl);
    // market.buyShares{ value: carlBetValue }(carlBucketIds, carlShares);

    // // Verify initial positions
    // assertEq(
    // int256(market.getBalanceOfShares(alice, DUMMY_BUCKET_IDS[1])), DUMMY_SHARES[1], "alice bucket 1 shares"
    //);
    // assertEq(int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[1])), DUMMY_SHARES[1], "bob bucket 1
    // shares");
    // assertEq(int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[2])), DUMMY_SHARES[2], "bob bucket 2
    // shares");
    // assertEq(int256(market.getBalanceOfShares(carl, DUMMY_BUCKET_IDS[2])), DUMMY_SHARES[2], "carl bucket 2
    // shares");
    // assertEq(int256(market.getBalanceOfShares(carl, DUMMY_BUCKET_IDS[3])), DUMMY_SHARES[3], "carl bucket 3
    // shares");

    // // Test partial selling: Alice sells half her position in bucket 1
    // int256[] memory alicePartialSellBucketIds = new int256[](1);
    // int256[] memory alicePartialSellShares = new int256[](1);
    // alicePartialSellBucketIds[0] = DUMMY_BUCKET_IDS[1];
    // alicePartialSellShares[0] = -DUMMY_SHARES[1] / 2; // sell half

    // uint256 aliceEthBalanceBefore = alice.balance;
    // (uint256 aliceStakeBefore,) = market.tradersStake(alice);

    // vm.prank(alice);
    // market.sellSharesPartial(alicePartialSellBucketIds, alicePartialSellShares);

    // // Verify Alice's partial position remains
    // assertEq(
    // int256(market.getBalanceOfShares(alice, DUMMY_BUCKET_IDS[1])),
    // DUMMY_SHARES[1] / 2,
    // "alice bucket 1 shares after partial sell"
    //);
    // assertEq(market.balanceOf(alice, uint256(FIRST_PREDICTION_ID)), 1, "alice NFT should still exist");

    // // Verify Alice's stake was reduced but not zeroed
    // (uint256 aliceStakeAfter,) = market.tradersStake(alice);
    // assertGt(aliceStakeAfter, 0, "alice stake should be reduced but not zeroed");
    // assertLt(aliceStakeAfter, aliceStakeBefore, "alice stake should be reduced");

    // // Test full selling: Bob sells his entire position in bucket 1
    // int256[] memory bobFullSellBucketIds = new int256[](1);
    // int256[] memory bobFullSellShares = new int256[](1);
    // bobFullSellBucketIds[0] = DUMMY_BUCKET_IDS[1];
    // bobFullSellShares[0] = -DUMMY_SHARES[1]; // sell all

    // uint256 bobEthBalanceBefore = bob.balance;
    // (uint256 bobStakeBefore,) = market.tradersStake(bob);

    // vm.prank(bob);
    // market.sellShares(bobFullSellBucketIds, bobFullSellShares);

    // // Verify Bob's position in bucket 1 is zeroed
    // assertEq(int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[1])), 0, "bob bucket 1 shares should be
    // zeroed");
    // // But Bob still has shares in bucket 2
    // assertEq(
    // int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[2])),
    // DUMMY_SHARES[2],
    // "bob bucket 2 shares should remain"
    //);

    // // Verify Bob's stake was reduced but not zeroed (still has bucket 2)
    // (uint256 bobStakeAfter,) = market.tradersStake(bob);
    // assertGt(bobStakeAfter, 0, "bob stake should be reduced but not zeroed");
    // assertLt(bobStakeAfter, bobStakeBefore, "bob stake should be reduced");

    // // Test partial selling: Carl sells half his position in bucket 2
    // int256[] memory carlPartialSellBucketIds = new int256[](1);
    // int256[] memory carlPartialSellShares = new int256[](1);
    // carlPartialSellBucketIds[0] = DUMMY_BUCKET_IDS[2];
    // carlPartialSellShares[0] = -DUMMY_SHARES[2] / 2; // sell half

    // uint256 carlEthBalanceBefore = carl.balance;
    // (uint256 carlStakeBefore,) = market.tradersStake(carl);

    // vm.prank(carl);
    // market.sellSharesPartial(carlPartialSellBucketIds, carlPartialSellShares);

    // // Verify Carl's partial position remains
    // assertEq(
    // int256(market.getBalanceOfShares(carl, DUMMY_BUCKET_IDS[2])),
    // DUMMY_SHARES[2] / 2,
    // "carl bucket 2 shares after partial sell"
    //);
    // assertEq(
    // int256(market.getBalanceOfShares(carl, DUMMY_BUCKET_IDS[3])),
    // DUMMY_SHARES[3],
    // "carl bucket 3 shares should remain unchanged"
    //);

    // // Verify Carl's stake was reduced but not zeroed
    // (uint256 carlStakeAfter,) = market.tradersStake(carl);
    // assertGt(carlStakeAfter, 0, "carl stake should be reduced but not zeroed");
    // assertLt(carlStakeAfter, carlStakeBefore, "carl stake should be reduced");

    // // Verify market state is consistent
    // assertEq(
    // market.getBucketOutstandingShares(DUMMY_BUCKET_IDS[1]),
    // DUMMY_SHARES[1] / 2,
    // "bucket 1 total shares should be half"
    //);
    // assertEq(
    // market.getBucketOutstandingShares(DUMMY_BUCKET_IDS[2]),
    // DUMMY_SHARES[2] + DUMMY_SHARES[2] / 2,
    // "bucket 2 total shares should be bob's full + carl's half"
    //);
    // assertEq(
    // market.getBucketOutstandingShares(DUMMY_BUCKET_IDS[3]),
    // DUMMY_SHARES[3],
    // "bucket 3 total shares should remain unchanged"
    //);
    //}
}
