// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Config
import { MockErc20 } from "@test/mocks/MockErc20.sol";
import { OnitIODPMTestBase } from "@test/config/OnitIODPMTestBase.t.sol";
// Types
import { MarketInitData } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
// Interfaces
import { IOnitInfiniteOutcomeDPM } from "@src/interfaces/IOnitInfiniteOutcomeDPM.sol";
import { IOnitMarketResolver } from "@src/interfaces/IOnitMarketResolver.sol";
// Contract to test
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";
import { OnitMarketResolver } from "@src/resolvers/OnitMarketResolver.sol";

// Infinite Outcome DPM: withdraw token
contract IODPMTestWithdrawToken is OnitIODPMTestBase {
    MockErc20 tokenB;

    function setUp() public {
        tokenB = new MockErc20("B", "B", 18);

        tokenA.mint(alice, 1000 ether);
        tokenB.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);
        tokenB.mint(bob, 1000 ether);
    }

    function test_withdraw_revert_MarketIsOpen() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        vm.prank(MARKET_OWNER);
        vm.expectRevert(IOnitMarketResolver.MarketIsOpen.selector);
        market.withdraw();
    }

    function test_withdraw_revert_WithdrawalDelayPeriodNotPassed() public {
        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.config.withdrawlDelayPeriod = 1 days;

        OnitInfiniteOutcomeDPM market = newMarket(initData);

        vm.warp(block.timestamp + 2 * market.withdrawlDelayPeriod() - 1);
        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);
        vm.expectRevert(IOnitInfiniteOutcomeDPM.WithdrawalDelayPeriodNotPassed.selector);
        vm.prank(MARKET_OWNER);
        market.withdraw();
    }

    function test_withdraw_revert_MarketIsVoided() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        vm.prank(MARKET_OWNER);
        market.voidMarket();

        vm.expectRevert(IOnitMarketResolver.MarketIsVoided.selector);
        vm.prank(MARKET_OWNER);
        market.withdraw();
    }

    function test_withdraw_success() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        assertEq(tokenA.balanceOf(address(market)), INITIAL_BET_VALUE, "market balance");

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);
        vm.prank(MARKET_OWNER);
        market.withdraw();

        assertEq(tokenA.balanceOf(address(market)), 0, "market balance");
    }

    fallback() external payable { }
    receive() external payable { }
}
