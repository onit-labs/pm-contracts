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

// Infinite Outcome DPM: withdrawMarketCreatorFees token
contract IODPMTestWithdrawMarketCreatorFeesToken is OnitIODPMTestBase {
    MockErc20 tokenB;

    function setUp() public {
        tokenB = new MockErc20("B", "B", 18);

        tokenA.mint(alice, 1000 ether);
        tokenB.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);
        tokenB.mint(bob, 1000 ether);
    }

    function test_withdrawMarketCreatorFees_revert_MarketIsVoided() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        vm.prank(MARKET_OWNER);
        market.voidMarket();
        vm.expectRevert(IOnitMarketResolver.MarketIsVoided.selector);
        market.withdrawMarketCreatorFees();
    }

    function test_withdrawMarketCreatorFees_revert_MarketIsOpen() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        vm.expectRevert(IOnitMarketResolver.MarketIsOpen.selector);
        market.withdrawMarketCreatorFees();
    }

    function test_withdrawMarketCreatorFees_revert_WithdrawalDelayPeriodNotPassed() public {
        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.config.withdrawlDelayPeriod = 1 days;

        OnitInfiniteOutcomeDPM market = newMarket(initData);

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        vm.expectRevert(IOnitInfiniteOutcomeDPM.WithdrawalDelayPeriodNotPassed.selector);
        market.withdrawMarketCreatorFees();
    }

    function test_withdrawMarketCreatorFees_afterDelayPeriod() public {
        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.config.withdrawlDelayPeriod = 1 days;

        OnitInfiniteOutcomeDPM market = newMarket(initData);

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);
        vm.warp(block.timestamp + 1 days);
        market.withdrawMarketCreatorFees();
    }

    function test_withdrawMarketCreatorFees_success() public {
        // Set market creator commission to 2%
        uint256 creatorCommissionBp = 200;

        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.config.marketCreatorCommissionBp = creatorCommissionBp;

        OnitInfiniteOutcomeDPM market = newMarket(initData);

        // Resolve market and wait delay period
        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        uint256 marketCreatorBalanceBefore = tokenA.balanceOf(MARKET_CREATOR_FEE_RECEIVER);
        uint256 expectedCreatorFee = INITIAL_BET_VALUE * creatorCommissionBp / 10_000;
        uint256 creatorFee = market.marketCreatorFee();

        assertEq(creatorFee, expectedCreatorFee, "creatorFee");

        // Withdraw fees
        market.withdrawMarketCreatorFees();

        // Check alice received correct fee amount
        assertEq(
            tokenA.balanceOf(MARKET_CREATOR_FEE_RECEIVER) - marketCreatorBalanceBefore,
            expectedCreatorFee,
            "Market creator should receive correct fee amount"
        );
        assertEq(market.marketCreatorFee(), 0, "marketCreatorFee");
    }

    function test_withdrawMarketCreatorFees_cannotWithdrawTwice() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        uint256 initialBalance = tokenA.balanceOf(MARKET_CREATOR_FEE_RECEIVER);

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        uint256 creatorFee = market.marketCreatorFee();

        market.withdrawMarketCreatorFees();

        uint256 balanceAfterFirstWithdrawal = tokenA.balanceOf(MARKET_CREATOR_FEE_RECEIVER);
        assertEq(balanceAfterFirstWithdrawal, initialBalance + creatorFee, "balanceAfterFirstWithdrawal");
        assertEq(market.marketCreatorFee(), 0, "creatorFeeAfterFirstWithdrawal");

        market.withdrawMarketCreatorFees();

        uint256 balanceAfterSecondWithdrawal = tokenA.balanceOf(MARKET_CREATOR_FEE_RECEIVER);
        assertEq(balanceAfterSecondWithdrawal, balanceAfterFirstWithdrawal, "balanceAfterSecondWithdrawal");
    }

    fallback() external payable { }
    receive() external payable { }
}
