// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc
import { MockErc20 } from "@test/mocks/MockErc20.sol";
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

contract OnitMarketOrderRouterExecuteMultipleOrdersTest is OnitIODPMTestBase {
    OnitInfiniteOutcomeDPM market2;
    address market2Address;

    uint256 FUTURE_SPEND_DEADLINE = block.timestamp + 1 days;

    function setUp() public {
        tokenA.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);

        market = newMarketWithDefaultConfigWithToken();
        MarketInitData memory initData2 = defaultMarketConfigWithToken();
        initData2.config.marketQuestion = "Market 2";
        market2 = newMarket(initData2);

        marketAddress = address(market);
        market2Address = address(market2);
    }

    // ----------------------------------------------------------------
    // executeMultipleOrders tests
    // ----------------------------------------------------------------

    function test_executeMultipleOrders_reverts_MulticallOrdersMustUseSameToken() public {
        // Create a second market with a different token
        address MARKET2 = makeAddr("MARKET2");
        MockErc20 tokenB = new MockErc20("TB", "TB", 18);
        tokenB.mint(someMarketsTokenAdmin, 1000 ether);

        // Initialize second market
        bytes memory orderRouterInitData = encodeOrderRouterInitData(
            address(tokenB),
            someMarketsTokenAdmin,
            orderRouterAddress,
            SPENDERS,
            AMOUNTS,
            INITIAL_BACKING,
            block.timestamp + 1 days,
            someMarketsTokenAdminPk
        );

        vm.prank(MARKET2);
        orderRouter.initializeOrderRouterForMarket(
            address(tokenB), someMarketsTokenAdmin, INITIAL_BACKING, orderRouterInitData
        );

        address[] memory markets = new address[](2);
        markets[0] = marketAddress;
        markets[1] = MARKET2;

        uint256[] memory betAmounts = new uint256[](2);
        betAmounts[0] = 1 ether;
        betAmounts[1] = 1 ether;

        int256[][] memory bucketIds = new int256[][](2);
        bucketIds[0] = DUMMY_BUCKET_IDS;
        bucketIds[1] = DUMMY_BUCKET_IDS;

        int256[][] memory shares = new int256[][](2);
        shares[0] = DUMMY_SHARES;
        shares[1] = DUMMY_SHARES;

        // Try to execute multiple orders with different tokens
        vm.prank(alice);
        vm.expectRevert(IOnitMarketOrderRouter.MulticallOrdersMustUseSameToken.selector);
        orderRouter.executeMultipleOrders(alice, markets, betAmounts, bucketIds, shares, "");
    }

    function test_executeMultipleOrders_withPermit_fromBuyer() public {
        address[] memory markets = new address[](2);
        markets[0] = marketAddress;
        markets[1] = market2Address;

        (int256 cost1,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        (int256 cost2,) = market2.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        uint256[] memory betAmounts = new uint256[](2);
        betAmounts[0] = uint256(cost1);
        betAmounts[1] = uint256(cost2);

        int256[][] memory bucketIds = new int256[][](2);
        bucketIds[0] = DUMMY_BUCKET_IDS;
        bucketIds[1] = DUMMY_BUCKET_IDS;

        int256[][] memory shares = new int256[][](2);
        shares[0] = DUMMY_SHARES;
        shares[1] = DUMMY_SHARES;

        uint256 totalAmount = uint256(cost1 + cost2);

        // Generate permit signature for total amount
        (uint8 v, bytes32 r, bytes32 s) =
            getPermitSignature(tokenAAddress, bob, orderRouterAddress, totalAmount, FUTURE_SPEND_DEADLINE, bobPk);

        bytes memory orderData = encodeOrderRouterPermitData(0, FUTURE_SPEND_DEADLINE, v, r, s);

        // Execute multiple orders
        vm.prank(bob);
        orderRouter.executeMultipleOrders(bob, markets, betAmounts, bucketIds, shares, orderData);

        // Verify token transfers
        assertEq(tokenA.balanceOf(marketAddress), INITIAL_BACKING + uint256(cost1));
        assertEq(tokenA.balanceOf(market2Address), INITIAL_BACKING + uint256(cost2));
        assertEq(tokenA.balanceOf(bob), 1000 ether - totalAmount);

        // Verify shares are minted for both orders
        (uint256 tradersStake1, uint256 nftId1, BetStatus status) = market.tradersStake(bob);
        assertEq(tradersStake1, uint256(cost1));
        assertEq(nftId1, 1);
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
        (uint256 tradersStake2, uint256 nftId2, BetStatus status2) = market2.tradersStake(bob);
        assertEq(tradersStake2, uint256(cost2));
        assertEq(nftId2, 1);
        assertEq(uint8(status2), uint8(BetStatus.OPEN), "status should be OPEN");
    }

    function test_executeMultipleOrders_withPermit_fromRelayer() public {
        address[] memory markets = new address[](2);
        markets[0] = marketAddress;
        markets[1] = market2Address;

        (int256 cost1,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        (int256 cost2,) = market2.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        uint256[] memory betAmounts = new uint256[](2);
        betAmounts[0] = uint256(cost1);
        betAmounts[1] = uint256(cost2);

        int256[][] memory bucketIds = new int256[][](2);
        bucketIds[0] = DUMMY_BUCKET_IDS;
        bucketIds[1] = DUMMY_BUCKET_IDS;

        int256[][] memory shares = new int256[][](2);
        shares[0] = DUMMY_SHARES;
        shares[1] = DUMMY_SHARES;

        uint256 totalAmount = uint256(cost1 + cost2);

        // Generate permit signature for total amount
        (uint8 v, bytes32 r, bytes32 s) =
            getPermitSignature(tokenAAddress, bob, orderRouterAddress, totalAmount, FUTURE_SPEND_DEADLINE, bobPk);

        bytes memory orderData = encodeOrderRouterPermitData(0, FUTURE_SPEND_DEADLINE, v, r, s);

        // Execute multiple orders from some other address
        vm.prank(alice);
        orderRouter.executeMultipleOrders(bob, markets, betAmounts, bucketIds, shares, orderData);

        // Verify token transfers
        assertEq(tokenA.balanceOf(marketAddress), INITIAL_BACKING + uint256(cost1));
        assertEq(tokenA.balanceOf(market2Address), INITIAL_BACKING + uint256(cost2));
        assertEq(tokenA.balanceOf(bob), 1000 ether - totalAmount);

        // Verify shares are minted for both orders
        (uint256 tradersStake1, uint256 nftId1, BetStatus status) = market.tradersStake(bob);
        assertEq(tradersStake1, uint256(cost1));
        assertEq(nftId1, 1);
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
        (uint256 tradersStake2, uint256 nftId2, BetStatus status2) = market2.tradersStake(bob);
        assertEq(tradersStake2, uint256(cost2));
        assertEq(nftId2, 1);
        assertEq(uint8(status2), uint8(BetStatus.OPEN), "status should be OPEN");
    }

    function test_executeMultipleOrders_withExistingAllowance() public {
        // bob permits 1000 ether on tokenA
        vm.prank(bob);
        tokenA.approve(orderRouterAddress, 1000 ether);

        address[] memory markets = new address[](2);
        markets[0] = marketAddress;
        markets[1] = market2Address;

        (int256 cost1,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        (int256 cost2,) = market2.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        uint256[] memory betAmounts = new uint256[](2);
        betAmounts[0] = uint256(cost1);
        betAmounts[1] = uint256(cost2);

        int256[][] memory bucketIds = new int256[][](2);
        bucketIds[0] = DUMMY_BUCKET_IDS;
        bucketIds[1] = DUMMY_BUCKET_IDS;

        int256[][] memory shares = new int256[][](2);
        shares[0] = DUMMY_SHARES;
        shares[1] = DUMMY_SHARES;

        uint256 totalAmount = uint256(cost1 + cost2);

        // No order data passed, so we execute from bobs existing allowance
        vm.prank(bob);
        orderRouter.executeMultipleOrders(bob, markets, betAmounts, bucketIds, shares, "");

        assertEq(tokenA.balanceOf(marketAddress), INITIAL_BACKING + uint256(cost1));
        assertEq(tokenA.balanceOf(market2Address), INITIAL_BACKING + uint256(cost2));
        assertEq(tokenA.balanceOf(bob), 1000 ether - totalAmount);
        assertEq(tokenA.allowance(bob, orderRouterAddress), 1000 ether - totalAmount);

        // Verify shares are minted for both orders
        (uint256 tradersStake1, uint256 nftId1, BetStatus status) = market.tradersStake(bob);
        assertEq(tradersStake1, uint256(cost1));
        assertEq(nftId1, 1);
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
        (uint256 tradersStake2, uint256 nftId2, BetStatus status2) = market2.tradersStake(bob);
        assertEq(tradersStake2, uint256(cost2));
        assertEq(nftId2, 1);
        assertEq(uint8(status2), uint8(BetStatus.OPEN), "status should be OPEN");
    }

    function test_executeMultipleOrders_reverts_TransferFailed_insufficientAllowance() public {
        address[] memory markets = new address[](2);
        markets[0] = marketAddress;
        markets[1] = marketAddress;

        uint256[] memory betAmounts = new uint256[](2);
        betAmounts[0] = 1 ether;
        betAmounts[1] = 1 ether;

        int256[][] memory bucketIds = new int256[][](2);
        bucketIds[0] = DUMMY_BUCKET_IDS;
        bucketIds[1] = DUMMY_BUCKET_IDS;

        int256[][] memory shares = new int256[][](2);
        shares[0] = DUMMY_SHARES;
        shares[1] = DUMMY_SHARES;

        // Try to execute multiple orders without permit or allowance
        vm.prank(alice);
        vm.expectRevert(ERC20.InsufficientAllowance.selector);
        orderRouter.executeMultipleOrders(alice, markets, betAmounts, bucketIds, shares, "");
    }

    function test_executeMultipleOrders_reverts_invalidPermit() public {
        address[] memory markets = new address[](2);
        markets[0] = marketAddress;
        markets[1] = marketAddress;

        uint256[] memory betAmounts = new uint256[](2);
        betAmounts[0] = 1 ether;
        betAmounts[1] = 1 ether;

        int256[][] memory bucketIds = new int256[][](2);
        bucketIds[0] = DUMMY_BUCKET_IDS;
        bucketIds[1] = DUMMY_BUCKET_IDS;

        int256[][] memory shares = new int256[][](2);
        shares[0] = DUMMY_SHARES;
        shares[1] = DUMMY_SHARES;

        // Generate invalid permit signature
        bytes memory orderData = abi.encode(0, FUTURE_SPEND_DEADLINE + 99, uint8(0), bytes32(0), bytes32(0));

        vm.prank(alice);
        vm.expectRevert(ERC20.InvalidPermit.selector);
        orderRouter.executeMultipleOrders(alice, markets, betAmounts, bucketIds, shares, orderData);
    }

    // function test_executeMultipleOrders_reverts_unauthorizedBuyer() public {
    // address[] memory markets = new address[](2);
    // markets[0] = marketAddress;
    // markets[1] = marketAddress;

    // uint256[] memory betAmounts = new uint256[](2);
    // betAmounts[0] = 1 ether;
    // betAmounts[1] = 1 ether;

    // int256[][] memory bucketIds = new int256[][](2);
    // bucketIds[0] = DUMMY_BUCKET_IDS;
    // bucketIds[1] = DUMMY_BUCKET_IDS;

    // int256[][] memory shares = new int256[][](2);
    // shares[0] = DUMMY_SHARES;
    // shares[1] = DUMMY_SHARES;

    // uint256 totalAmount = 2 ether;

    // // Generate permit signature for alice
    // (uint8 v, bytes32 r, bytes32 s) =
    // getPermitSignature(tokenAAddress, alice, orderRouterAddress, totalAmount, FUTURE_SPEND_DEADLINE,
    // alicePk);

    // bytes memory orderData = encodeOrderRouterPermitData(0, FUTURE_SPEND_DEADLINE, v, r, s);

    // // Try to execute multiple orders for alice as bob without a valid permit
    // vm.prank(bob);
    // vm.expectRevert("INVALID_SIGNER");
    // orderRouter.executeMultipleOrders(alice, markets, betAmounts, bucketIds, shares, orderData);
    //}

    function test_executeMultipleOrders_nativeToken() public {
        MarketInitData memory initData = defaultMarketConfig();
        initData.config.marketQuestion = "Test Market";
        market = newMarket(initData);
        marketAddress = address(market);

        MarketInitData memory initData2 = defaultMarketConfig();
        initData2.config.marketQuestion = "Test Market 2";
        market2 = newMarket(initData2);
        market2Address = address(market2);

        address[] memory markets = new address[](2);
        markets[0] = marketAddress;
        markets[1] = market2Address;

        int256[][] memory bucketIds = new int256[][](2);
        bucketIds[0] = DUMMY_BUCKET_IDS;
        bucketIds[1] = DUMMY_BUCKET_IDS;

        int256[][] memory shares = new int256[][](2);
        shares[0] = DUMMY_SHARES;
        shares[1] = DUMMY_SHARES;

        uint256[] memory betAmounts = new uint256[](2);

        // Calculate the cost of the trade
        (int256 int256BetAmount1,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        uint256 betAmount1 = uint256(int256BetAmount1);

        (int256 int256BetAmount2,) = market2.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        uint256 betAmount2 = uint256(int256BetAmount2);

        betAmounts[0] = betAmount1;
        betAmounts[1] = betAmount2;

        // Get Bob's initial ETH balance
        uint256 initialBobBalance = bob.balance;
        uint256 initialMarketBalance = marketAddress.balance;
        uint256 initialMarket2Balance = market2Address.balance;

        // Execute multiple orders with native ETH
        vm.prank(bob);
        orderRouter.executeMultipleOrders{
            value: betAmount1 + betAmount2
        }(bob, markets, betAmounts, bucketIds, shares, "");

        // Verify ETH transfer
        assertEq(marketAddress.balance, initialMarketBalance + betAmount1);
        assertEq(market2Address.balance, initialMarket2Balance + betAmount2);
        assertEq(bob.balance, initialBobBalance - betAmount1 - betAmount2);

        // Verify shares are minted for both orders
        (uint256 tradersStake1, uint256 nftId1, BetStatus status) = market.tradersStake(bob);
        assertEq(tradersStake1, betAmount1);
        assertEq(nftId1, 1);
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
        (uint256 tradersStake2, uint256 nftId2, BetStatus status2) = market2.tradersStake(bob);
        assertEq(tradersStake2, betAmount2);
        assertEq(nftId2, 1);
        assertEq(uint8(status2), uint8(BetStatus.OPEN), "status should be OPEN");
    }
}
