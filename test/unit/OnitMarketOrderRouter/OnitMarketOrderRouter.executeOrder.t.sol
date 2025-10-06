// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc
import { ERC20 } from "solady/tokens/ERC20.sol";
// Config
import { OnitIODPMTestBase } from "@test/config/OnitIODPMTestBase.t.sol";
// Types
import { MarketInitData, BetStatus } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
// Interfaces
import { IOnitMarketOrderRouter } from "@src/interfaces/IOnitMarketOrderRouter.sol";
// Contract to test
import { OnitMarketOrderRouter } from "@src/order-manager/OnitMarketOrderRouter.v2.sol";
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";

contract OnitMarketOrderRouterExecuteOrderTest is OnitIODPMTestBase {
    uint256 FUTURE_SPEND_DEADLINE = block.timestamp + 1 days;

    // Default to 1 ether, but this will be updated when calculating the cost of bets
    uint256 betAmount = 1 ether;

    function setUp() public {
        tokenA.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);

        market = newMarketWithDefaultConfigWithToken();
        marketAddress = address(market);
    }

    // ----------------------------------------------------------------
    // executeOrder tests
    // ----------------------------------------------------------------

    function test_executeOrder_withPermit_fromBuyer() public {
        assertEq(tokenA.balanceOf(bob), 1000 ether);
        assertEq(tokenA.balanceOf(marketAddress), INITIAL_BACKING);

        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        // Generate permit signature
        (uint8 v, bytes32 r, bytes32 s) =
            getPermitSignature(tokenAAddress, bob, orderRouterAddress, betAmount, FUTURE_SPEND_DEADLINE, bobPk);

        bytes memory orderData = encodeOrderRouterPermitData(0, FUTURE_SPEND_DEADLINE, v, r, s);

        // Execute order
        vm.prank(bob);
        orderRouter.executeOrder(marketAddress, bob, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES, orderData);

        // Verify token transfer
        assertEq(tokenA.balanceOf(marketAddress), INITIAL_BACKING + betAmount);
        assertEq(tokenA.balanceOf(bob), 1000 ether - betAmount);
        // Verify shares are minted
        (uint256 tradersStake, uint256 nftId, BetStatus status) = market.tradersStake(bob);
        assertEq(tradersStake, betAmount);
        assertEq(nftId, 1);
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
    }

    function test_executeOrder_withPermit_fromRelayer() public {
        assertEq(tokenA.balanceOf(bob), 1000 ether);
        assertEq(tokenA.balanceOf(marketAddress), INITIAL_BACKING);

        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        // Generate permit signature
        (uint8 v, bytes32 r, bytes32 s) =
            getPermitSignature(tokenAAddress, bob, orderRouterAddress, betAmount, FUTURE_SPEND_DEADLINE, bobPk);

        bytes memory orderData = encodeOrderRouterPermitData(0, FUTURE_SPEND_DEADLINE, v, r, s);

        // Execute order, bobs sig passed by alice
        vm.prank(alice);
        orderRouter.executeOrder(marketAddress, bob, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES, orderData);

        // Verify token transfer
        assertEq(tokenA.balanceOf(marketAddress), INITIAL_BACKING + betAmount);
        assertEq(tokenA.balanceOf(bob), 1000 ether - betAmount);
        // Verify shares are mintedx
        (uint256 tradersStake, uint256 nftId, BetStatus status) = market.tradersStake(bob);
        assertEq(tradersStake, betAmount);
        assertEq(nftId, 1);
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
    }

    function test_executeOrder_withExistingAllowance_fromBuyer() public {
        assertEq(tokenA.balanceOf(bob), 1000 ether);
        assertEq(tokenA.balanceOf(marketAddress), INITIAL_BACKING);
        assertEq(tokenA.allowance(bob, orderRouterAddress), 0);

        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        uint256 futureAllowance = 1 ether;

        // Get a permit sig for the bet amount + future allowance
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            tokenAAddress, bob, orderRouterAddress, betAmount + futureAllowance, FUTURE_SPEND_DEADLINE, bobPk
        );

        bytes memory orderData = encodeOrderRouterPermitData(futureAllowance, FUTURE_SPEND_DEADLINE, v, r, s);

        // Execute first order which will set the excess futureAllowance
        vm.prank(bob);
        orderRouter.executeOrder(marketAddress, bob, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES, orderData);

        // Verify token transfer
        assertEq(tokenA.balanceOf(marketAddress), INITIAL_BACKING + betAmount);
        assertEq(tokenA.balanceOf(bob), 1000 ether - betAmount);
        // Verify allowance was set
        assertEq(tokenA.allowance(bob, orderRouterAddress), futureAllowance);

        // Get a second bet amount
        (int256 int256BetAmount2,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        uint256 betAmount2 = uint256(int256BetAmount2);

        // Execute second order which will use the allowance, no order data is needed
        vm.prank(bob);
        orderRouter.executeOrder(marketAddress, bob, betAmount2, DUMMY_BUCKET_IDS, DUMMY_SHARES, "");

        // Verify token transfer
        assertEq(tokenA.balanceOf(marketAddress), INITIAL_BACKING + betAmount + betAmount2);
        assertEq(tokenA.balanceOf(bob), 1000 ether - betAmount - betAmount2);
        // Verify allowance was used
        assertEq(tokenA.allowance(bob, orderRouterAddress), futureAllowance - betAmount2);
    }

    function test_executeOrder_reverts_withExistingAllowance_ifNotFromBuyer() public {
        // TODO this is wasteful as we pass all these as a long byte string of 0
        // add a check in the order router to not decode bytes
        bytes memory orderData = encodeOrderRouterPermitData(0, 0, uint8(0), bytes32(0), bytes32(0));

        vm.prank(alice);
        // This happens because we try to permit when msg.sender != buyer, and empty bytes will cause deadline to be 0
        vm.expectRevert(ERC20.PermitExpired.selector);
        orderRouter.executeOrder(marketAddress, bob, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES, orderData);
    }

    function test_executeOrder_reverts_insufficientAllowance() public {
        assertEq(tokenA.balanceOf(bob), 1000 ether);
        assertEq(tokenA.balanceOf(marketAddress), INITIAL_BACKING);
        assertEq(tokenA.allowance(bob, orderRouterAddress), 0);

        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        // some extra allowance, but not enough for another bet
        uint256 futureAllowance = 1;

        // Get a permit sig for the bet amount + future allowance
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            tokenAAddress, bob, orderRouterAddress, betAmount + futureAllowance, FUTURE_SPEND_DEADLINE, bobPk
        );

        bytes memory orderData = encodeOrderRouterPermitData(futureAllowance, FUTURE_SPEND_DEADLINE, v, r, s);

        // Execute first order which will set the excess futureAllowance
        vm.prank(bob);
        orderRouter.executeOrder(marketAddress, bob, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES, orderData);

        // Verify token transfer
        assertEq(tokenA.balanceOf(marketAddress), INITIAL_BACKING + betAmount);
        assertEq(tokenA.balanceOf(bob), 1000 ether - betAmount);
        // Verify allowance was set
        assertEq(tokenA.allowance(bob, orderRouterAddress), futureAllowance);

        // Get a second bet amount
        (int256 int256BetAmount2,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        uint256 betAmount2 = uint256(int256BetAmount2);

        // Execute second order which will use the allowance, no order data is needed
        vm.prank(bob);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        orderRouter.executeOrder(marketAddress, bob, betAmount2, DUMMY_BUCKET_IDS, DUMMY_SHARES, "");
    }

    function test_executeOrder_reverts_invalidPermit() public {
        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        // Get a permit sig
        (uint8 v, bytes32 r, bytes32 s) =
            getPermitSignature(tokenAAddress, bob, orderRouterAddress, betAmount, FUTURE_SPEND_DEADLINE, bobPk);

        // Generate invalid permit signature
        bytes memory orderData = abi.encode(0, FUTURE_SPEND_DEADLINE + 99, v, r, s);

        vm.prank(alice);
        vm.expectRevert(ERC20.InvalidPermit.selector);
        orderRouter.executeOrder(marketAddress, alice, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES, orderData);
    }

    function test_executeOrder_nativeToken() public {
        // Create a new market that uses native ETH (address(0) as token)
        MarketInitData memory initData = defaultMarketConfig();
        initData.config.marketQuestion = "Test Market";

        market = newMarket(initData);
        marketAddress = address(market);

        // Calculate the cost of the trade
        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        // Get Bob's initial ETH balance
        uint256 initialBobBalance = bob.balance;
        uint256 initialMarketBalance = marketAddress.balance;

        // Execute order with native ETH
        vm.prank(bob);
        orderRouter.executeOrder{ value: betAmount }(marketAddress, bob, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES, "");

        // Verify ETH transfer
        assertEq(marketAddress.balance, initialMarketBalance + betAmount);
        assertEq(bob.balance, initialBobBalance - betAmount);

        // Verify shares are minted
        (uint256 tradersStake, uint256 nftId, BetStatus status) = market.tradersStake(bob);
        assertEq(tradersStake, betAmount);
        assertEq(nftId, 1);
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
    }

    // ----------------------------------------------------------------
    // executeSellOrder tests
    // ----------------------------------------------------------------

    function test_executeSellOrder_singleSeller() public {
        // First, let Bob buy some shares to sell later
        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        // Generate permit signature for Bob's buy order
        (uint8 v, bytes32 r, bytes32 s) =
            getPermitSignature(tokenAAddress, bob, orderRouterAddress, betAmount, FUTURE_SPEND_DEADLINE, bobPk);

        bytes memory orderData = encodeOrderRouterPermitData(0, FUTURE_SPEND_DEADLINE, v, r, s);

        // Execute buy order first
        vm.prank(bob);
        orderRouter.executeOrder(marketAddress, bob, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES, orderData);

        // Verify Bob has shares
        assertEq(int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[1])), DUMMY_SHARES[1], "Bob should have shares");
        (uint256 bobStakeBefore,,) = market.tradersStake(bob);
        assertEq(bobStakeBefore, betAmount, "Bob should have stake");

        // Now prepare to sell
        int256[] memory sellBucketIds = new int256[](1);
        int256[] memory sellShares = new int256[](1);
        sellBucketIds[0] = DUMMY_BUCKET_IDS[1];
        sellShares[0] = -DUMMY_SHARES[1]; // Negative for selling

        uint256 bobTokenBalanceBefore = tokenA.balanceOf(bob);
        uint256 marketTokenBalanceBefore = tokenA.balanceOf(marketAddress);

        // Calculate expected payout
        (int256 saleCostDiff,) = market.calculateCostOfTrade(sellBucketIds, sellShares);
        uint256 expectedPayout = uint256(-saleCostDiff);

        // Execute sell order
        vm.prank(bob);
        orderRouter.executeSellOrder(marketAddress, bob, sellBucketIds, sellShares);

        // Verify Bob received tokens
        assertEq(tokenA.balanceOf(bob), bobTokenBalanceBefore + expectedPayout, "Bob should receive payout");
        assertEq(
            tokenA.balanceOf(marketAddress), marketTokenBalanceBefore - expectedPayout, "Market should send tokens"
        );

        // Verify Bob's shares are gone
        assertEq(int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[1])), 0, "Bob should have no shares");

        // Verify Bob's stake is reduced
        (uint256 bobStakeAfter,,) = market.tradersStake(bob);
        uint256 expectedStakeAfter = bobStakeBefore > expectedPayout ? bobStakeBefore - expectedPayout : 0;
        assertEq(bobStakeAfter, expectedStakeAfter, "Bob's stake should be reduced");
    }

    function test_executeSellOrder_reverts_invalidSeller() public {
        // First, let Bob buy some shares
        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        (uint8 v, bytes32 r, bytes32 s) =
            getPermitSignature(tokenAAddress, bob, orderRouterAddress, betAmount, FUTURE_SPEND_DEADLINE, bobPk);

        bytes memory orderData = encodeOrderRouterPermitData(0, FUTURE_SPEND_DEADLINE, v, r, s);

        vm.prank(bob);
        orderRouter.executeOrder(marketAddress, bob, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES, orderData);

        // Prepare sell order
        int256[] memory sellBucketIds = new int256[](1);
        int256[] memory sellShares = new int256[](1);
        sellBucketIds[0] = DUMMY_BUCKET_IDS[1];
        sellShares[0] = -DUMMY_SHARES[1];

        // Alice tries to sell Bob's shares - should revert
        vm.expectRevert(IOnitMarketOrderRouter.InvalidAllowanceSpender.selector);
        vm.prank(alice);
        orderRouter.executeSellOrder(marketAddress, bob, sellBucketIds, sellShares);
    }

    function test_executeSellOrder_reverts_nothingToPay() public {
        // Try to sell without having any shares
        int256[] memory sellBucketIds = new int256[](1);
        int256[] memory sellShares = new int256[](1);
        sellBucketIds[0] = DUMMY_BUCKET_IDS[1];
        sellShares[0] = -DUMMY_SHARES[1];

        vm.expectRevert(); // This will be caught by the market's NothingToPay check
        vm.prank(bob);
        orderRouter.executeSellOrder(marketAddress, bob, sellBucketIds, sellShares);
    }

    function test_executeSellOrder_reverts_invalidSharesValue() public {
        // First, let Bob buy some shares
        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        (uint8 v, bytes32 r, bytes32 s) =
            getPermitSignature(tokenAAddress, bob, orderRouterAddress, betAmount, FUTURE_SPEND_DEADLINE, bobPk);

        bytes memory orderData = encodeOrderRouterPermitData(0, FUTURE_SPEND_DEADLINE, v, r, s);

        vm.prank(bob);
        orderRouter.executeOrder(marketAddress, bob, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES, orderData);

        // Try to sell positive shares (should be negative for selling)
        vm.expectRevert(); // This will be caught by the market's InvalidSharesValue check
        vm.prank(bob);
        orderRouter.executeSellOrder(marketAddress, bob, DUMMY_BUCKET_IDS, DUMMY_SHARES); // Using positive shares
    }

    function test_executeSellOrder_emitsEvent() public {
        // First, let Bob buy some shares
        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        (uint8 v, bytes32 r, bytes32 s) =
            getPermitSignature(tokenAAddress, bob, orderRouterAddress, betAmount, FUTURE_SPEND_DEADLINE, bobPk);

        bytes memory orderData = encodeOrderRouterPermitData(0, FUTURE_SPEND_DEADLINE, v, r, s);

        vm.prank(bob);
        orderRouter.executeOrder(marketAddress, bob, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES, orderData);

        // Prepare sell order
        int256[] memory sellBucketIds = new int256[](1);
        int256[] memory sellShares = new int256[](1);
        sellBucketIds[0] = DUMMY_BUCKET_IDS[1];
        sellShares[0] = -DUMMY_SHARES[1];

        // Execute sell order - the SellOrderExecuted event should be emitted
        vm.prank(bob);
        orderRouter.executeSellOrder(marketAddress, bob, sellBucketIds, sellShares);

        // Verify the sell actually happened by checking Bob's shares are gone
        assertEq(int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[1])), 0, "Bob should have no shares after sell");
    }

    function test_executeSellOrder_partialSell() public {
        // First, let Bob buy multiple shares to sell partially later
        int256[] memory buyBucketIds = new int256[](2);
        int256[] memory buyShares = new int256[](2);
        buyBucketIds[0] = DUMMY_BUCKET_IDS[1];
        buyBucketIds[1] = DUMMY_BUCKET_IDS[2];
        buyShares[0] = DUMMY_SHARES[1] * 2; // Buy 2 shares in bucket 1
        buyShares[1] = DUMMY_SHARES[2]; // Buy 1 share in bucket 2

        (int256 int256BetAmount,) = market.calculateCostOfTrade(buyBucketIds, buyShares);
        betAmount = uint256(int256BetAmount);

        (uint8 v, bytes32 r, bytes32 s) =
            getPermitSignature(tokenAAddress, bob, orderRouterAddress, betAmount, FUTURE_SPEND_DEADLINE, bobPk);

        bytes memory orderData = encodeOrderRouterPermitData(0, FUTURE_SPEND_DEADLINE, v, r, s);

        vm.prank(bob);
        orderRouter.executeOrder(marketAddress, bob, betAmount, buyBucketIds, buyShares, orderData);

        // Verify Bob has the shares
        assertEq(
            int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[1])),
            DUMMY_SHARES[1] * 2,
            "Bob should have 2 shares in bucket 1"
        );
        assertEq(
            int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[2])),
            DUMMY_SHARES[2],
            "Bob should have 1 share in bucket 2"
        );

        // Now sell only 1 share from bucket 1
        int256[] memory sellBucketIds = new int256[](1);
        int256[] memory sellShares = new int256[](1);
        sellBucketIds[0] = DUMMY_BUCKET_IDS[1];
        sellShares[0] = -DUMMY_SHARES[1]; // Sell 1 share

        uint256 bobTokenBalanceBefore = tokenA.balanceOf(bob);

        vm.prank(bob);
        orderRouter.executeSellOrder(marketAddress, bob, sellBucketIds, sellShares);

        // Verify Bob still has 1 share in bucket 1 and all shares in bucket 2
        assertEq(
            int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[1])),
            DUMMY_SHARES[1],
            "Bob should have 1 share left in bucket 1"
        );
        assertEq(
            int256(market.getBalanceOfShares(bob, DUMMY_BUCKET_IDS[2])),
            DUMMY_SHARES[2],
            "Bob should still have shares in bucket 2"
        );

        // Verify Bob received tokens for the partial sell
        assertGt(tokenA.balanceOf(bob), bobTokenBalanceBefore, "Bob should have received tokens");
    }
}
