// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc
import { MockErc20 } from "@test/mocks/MockErc20.sol";
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
import { OnitIODPMOrderManager } from "@src/order-manager/OnitIODPMOrderManager.sol";

// Infinite Outcome DPM: collectVoidedFunds token
contract IODPMTestCollectVoidedFundsToken is OnitIODPMTestBase {
    MockErc20 tokenB;

    function setUp() public {
        tokenB = new MockErc20("B", "B", 18);

        tokenA.mint(alice, 1000 ether);
        tokenB.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);
        tokenB.mint(bob, 1000 ether);
    }

    function test_collectVoidedFunds_revert_MarketIsOpen() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        vm.expectRevert(IOnitMarketResolver.MarketIsOpen.selector);
        market.collectVoidedFunds(alice);
    }

    function test_collectVoidedFunds_revert_NothingToPay() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        vm.prank(MARKET_OWNER);
        market.voidMarket();
        market.collectVoidedFunds(alice);

        vm.expectRevert(IOnitIODPMOrderManager.NothingToPay.selector);
        market.collectVoidedFunds(alice);
    }

    function test_collectVoidedFunds_success() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        (int256 costBob,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);

        // Set up token approval
        bytes memory orderData = createOrderData(
            address(tokenA), bob, orderRouterAddress, uint256(costBob), block.timestamp + 100 days, bobPk
        );

        vm.prank(bob);
        orderRouter.executeOrder(address(market), bob, uint256(costBob), DUMMY_BUCKET_IDS, DUMMY_SHARES, orderData);

        uint256 aliceBalance = tokenA.balanceOf(alice);
        uint256 bobBalance = tokenA.balanceOf(bob);
        uint256 marketBalance = tokenA.balanceOf(address(market));

        assertEq(marketBalance, uint256(costBob) + INITIAL_BET_VALUE, "initial market balance");
        // Alices holdings
        assertEq(market.balanceOf(alice, FIRST_PREDICTION_ID), 1, "alice nft balance");
        (uint256 totalStake, uint256 nftId, BetStatus status) = market.tradersStake(alice);
        assertEq(totalStake, INITIAL_BET_VALUE, "alice total stake");
        assertEq(nftId, FIRST_PREDICTION_ID, "alice nftId");
        assertEq(uint8(status), uint8(BetStatus.OPEN), "alice status");

        // Bob's holdings
        assertEq(market.balanceOf(bob, SECOND_PREDICTION_ID), 1, "bob nft balance");
        (uint256 totalStakeBob, uint256 nftIdBob, BetStatus statusBob) = market.tradersStake(bob);
        assertEq(totalStakeBob, uint256(costBob), "bob total stake");
        assertEq(nftIdBob, SECOND_PREDICTION_ID, "bob nftId");
        assertEq(uint8(statusBob), uint8(BetStatus.OPEN), "bob status");

        vm.prank(MARKET_OWNER);
        market.voidMarket();

        market.collectVoidedFunds(alice);

        (totalStake, nftId,) = market.tradersStake(alice);
        assertEq(totalStake, 0, "alice total stake");
        assertEq(nftId, 0, "alice nftId");
        assertEq(tokenA.balanceOf(alice), aliceBalance + INITIAL_BET_VALUE, "alice balance");

        market.collectVoidedFunds(bob);

        (totalStake, nftId,) = market.tradersStake(bob);
        assertEq(totalStake, 0, "bob total stake");
        assertEq(nftId, 0, "bob nftId");
        assertEq(tokenA.balanceOf(bob), bobBalance + uint256(costBob), "bob balance");

        assertEq(tokenA.balanceOf(address(market)), 0, "final market balance");
    }

    fallback() external payable { }
    receive() external payable { }
}
