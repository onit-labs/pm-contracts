// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Config
import { OnitIODPMTestBase } from "@test/config/OnitIODPMTestBase.t.sol";
// Types
import { MarketInitData } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
// Interfaces
import { IOnitInfiniteOutcomeDPM } from "@src/interfaces/IOnitInfiniteOutcomeDPM.sol";
import { IOnitMarketResolver } from "@src/interfaces/IOnitMarketResolver.sol";
// Contract to test
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";
import { OnitMarketResolver } from "@src/resolvers/OnitMarketResolver.sol";

// Infinite Outcome DPM: withdraw
contract IODPMTestWithdraw is OnitIODPMTestBase {
    function test_withdraw_revert_MarketIsOpen() public {
        market = newMarketWithDefaultConfig();

        vm.prank(MARKET_OWNER);
        vm.expectRevert(IOnitMarketResolver.MarketIsOpen.selector);
        market.withdraw();
    }

    function test_withdraw_revert_WithdrawalDelayPeriodNotPassed() public {
        MarketInitData memory config = defaultMarketConfig();
        config.config.withdrawlDelayPeriod = 1 days;
        market = newMarket(config);

        vm.warp(block.timestamp + 2 * market.withdrawlDelayPeriod() - 1);
        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);
        vm.expectRevert(IOnitInfiniteOutcomeDPM.WithdrawalDelayPeriodNotPassed.selector);
        vm.prank(MARKET_OWNER);
        market.withdraw();
    }

    function test_withdraw_revert_MarketIsVoided() public {
        market = newMarketWithDefaultConfig();

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        vm.prank(MARKET_OWNER);
        market.voidMarket();

        vm.expectRevert(IOnitMarketResolver.MarketIsVoided.selector);
        vm.prank(MARKET_OWNER);
        market.withdraw();
    }

    function test_withdraw_success() public {
        market = newMarketWithDefaultConfig();

        assertEq(address(market).balance, INITIAL_BET_VALUE, "market balance");

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);
        vm.prank(MARKET_OWNER);
        market.withdraw();

        assertEq(address(market).balance, 0, "market balance");
    }

    // ----------------------------------------------------------------
    // Helpers
    // ----------------------------------------------------------------

    receive() external payable { }
}
