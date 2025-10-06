// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

/* solhint-disable max-line-length */

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

// Infinite Outcome DPM: withdrawMarketCreatorFees
contract IODPMTestWithdrawMarketCreatorFees is OnitIODPMTestBase {
    function test_withdrawMarketCreatorFees_revert_MarketIsVoided() public {
        market = newMarketWithDefaultConfig();

        vm.prank(MARKET_OWNER);
        market.voidMarket();
        vm.expectRevert(IOnitMarketResolver.MarketIsVoided.selector);
        market.withdrawMarketCreatorFees();
    }

    function test_withdrawMarketCreatorFees_revert_MarketIsOpen() public {
        market = newMarketWithDefaultConfig();

        vm.expectRevert(IOnitMarketResolver.MarketIsOpen.selector);
        market.withdrawMarketCreatorFees();
    }

    function test_withdrawMarketCreatorFees_revert_WithdrawalDelayPeriodNotPassed() public {
        MarketInitData memory initData = defaultMarketConfig();
        initData.config.withdrawlDelayPeriod = 1 days;
        market = newMarket(initData);

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        vm.expectRevert(IOnitInfiniteOutcomeDPM.WithdrawalDelayPeriodNotPassed.selector);
        market.withdrawMarketCreatorFees();
    }

    function test_withdrawMarketCreatorFees_afterWithdrawalDelayPeriod() public {
        MarketInitData memory initData = defaultMarketConfig();
        initData.config.withdrawlDelayPeriod = 1 days;
        market = newMarket(initData);
        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);
        vm.warp(block.timestamp + 1 days);
        market.withdrawMarketCreatorFees();
    }

    function test_withdrawMarketCreatorFees() public {
        // Set market creator commission to 2%
        uint256 creatorCommissionBp = 200;

        MarketInitData memory initData = defaultMarketConfig();
        initData.config.marketCreatorCommissionBp = creatorCommissionBp;
        market = newMarket(initData);

        // Resolve market and wait delay period
        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        uint256 marketCreatorBalanceBefore = MARKET_CREATOR_FEE_RECEIVER.balance;
        uint256 expectedCreatorFee = INITIAL_BET_VALUE * creatorCommissionBp / 10_000;
        uint256 creatorFee = market.marketCreatorFee();

        assertEq(creatorFee, expectedCreatorFee, "creatorFee");

        // Withdraw fees
        market.withdrawMarketCreatorFees();

        // Check alice received correct fee amount
        assertEq(
            MARKET_CREATOR_FEE_RECEIVER.balance - marketCreatorBalanceBefore,
            expectedCreatorFee,
            "Market creator should receive correct fee amount"
        );
        assertEq(market.marketCreatorFee(), 0, "marketCreatorFee");
    }

    function test_cannotWithdrawMarketCreatorFeesTwice() public {
        market = newMarketWithDefaultConfig();

        uint256 initialBalance = MARKET_CREATOR_FEE_RECEIVER.balance;

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        uint256 creatorFee = market.marketCreatorFee();

        market.withdrawMarketCreatorFees();

        uint256 balanceAfterFirstWithdrawal = MARKET_CREATOR_FEE_RECEIVER.balance;
        assertEq(balanceAfterFirstWithdrawal, initialBalance + creatorFee, "balanceAfterFirstWithdrawal");
        assertEq(market.marketCreatorFee(), 0, "creatorFeeAfterFirstWithdrawal");

        market.withdrawMarketCreatorFees();

        uint256 balanceAfterSecondWithdrawal = MARKET_CREATOR_FEE_RECEIVER.balance;
        assertEq(balanceAfterSecondWithdrawal, balanceAfterFirstWithdrawal, "balanceAfterSecondWithdrawal");
    }

    fallback() external payable { }
    receive() external payable { }
}
