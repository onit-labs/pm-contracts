// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc
import { MockErc20 } from "@test/mocks/MockErc20.sol";
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

// Infinite Outcome DPM: withdrawProtocolFees token
contract IODPMTestWithdrawProtocolFeesToken is OnitIODPMTestBase {
    MockErc20 tokenB;

    function setUp() public {
        tokenB = new MockErc20("B", "B", 18);

        tokenA.mint(alice, 1000 ether);
        tokenB.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);
        tokenB.mint(bob, 1000 ether);
    }

    function test_withdrawProtocolFees_revert_OnlyFactoryOwner() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        vm.prank(bob);
        vm.expectRevert(IOnitMarketResolver.OnlyOnitFactoryOwner.selector);
        market.withdrawProtocolFees(bob);
    }

    function test_withdrawProtocolFees_revert_MarketIsVoided() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        vm.prank(MARKET_OWNER);
        market.voidMarket();
        vm.expectRevert(IOnitMarketResolver.MarketIsVoided.selector);
        market.withdrawProtocolFees(bob);
    }

    function test_withdrawProtocolFees_revert_MarketIsOpen() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        vm.prank(MARKET_OWNER);
        vm.expectRevert(IOnitMarketResolver.MarketIsOpen.selector);
        market.withdrawProtocolFees(bob);
    }

    function test_withdrawProtocolFees_revert_WithdrawalDelayPeriodNotPassed() public {
        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.config.withdrawlDelayPeriod = 1 days;

        OnitInfiniteOutcomeDPM market = newMarket(initData);

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);
        vm.expectRevert(IOnitInfiniteOutcomeDPM.WithdrawalDelayPeriodNotPassed.selector);
        market.withdrawProtocolFees(address(this));
    }

    function test_withdrawProtocolFees_afterDelayPeriod() public {
        MarketInitData memory initData = defaultMarketConfigWithToken();
        initData.config.withdrawlDelayPeriod = 1 days;

        OnitInfiniteOutcomeDPM market = newMarket(initData);

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);
        vm.warp(block.timestamp + 1 days);
        market.withdrawProtocolFees(address(this));
    }

    function test_withdrawProtocolFees_success() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        // Owner has some balance, market has some balance
        uint256 ownerBalanceBeforeClaim = tokenA.balanceOf(address(this));
        uint256 marketBalanceBeforeClaim = tokenA.balanceOf(address(market));

        // Market holds some commission value for the owner
        uint256 marketCommission = market.PROTOCOL_COMMISSION_BP();
        uint256 marketCommissionValue = marketBalanceBeforeClaim * marketCommission / 10_000;

        // Resolve the market
        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        // Withdraw the fees
        vm.prank(MARKET_OWNER);
        market.withdrawProtocolFees(address(this));

        // Check the owner's balance, it should increase by the market commission value
        uint256 ownerBalanceDiff = tokenA.balanceOf(address(this)) - ownerBalanceBeforeClaim;
        // Check the market balance, it should decrease by the market commission value
        uint256 marketBalanceDiff = marketBalanceBeforeClaim - tokenA.balanceOf(address(market));

        assertEq(ownerBalanceDiff, marketCommissionValue, "ownerBalanceDiff");
        assertEq(marketBalanceDiff, marketCommissionValue, "marketBalanceDiff");
        assertEq(market.protocolFee(), 0, "protocolFee");
    }

    function test_withdrawProtocolFees_cannotWithdrawTwice() public {
        OnitInfiniteOutcomeDPM market = newMarketWithDefaultConfigWithToken();

        uint256 initialBalance = tokenA.balanceOf(address(this));

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        uint256 protocolFee = market.protocolFee();

        vm.prank(MARKET_OWNER);
        market.withdrawProtocolFees(address(this));

        uint256 balanceAfterFirstWithdrawal = tokenA.balanceOf(address(this));
        assertEq(balanceAfterFirstWithdrawal, initialBalance + protocolFee, "balanceAfterFirstWithdrawal");

        uint256 protocolFeeAfterFirstWithdrawal = market.protocolFee();
        assertEq(protocolFeeAfterFirstWithdrawal, 0, "protocolFeeAfterFirstWithdrawal");

        market.withdrawProtocolFees(address(this));

        uint256 balanceAfterSecondWithdrawal = tokenA.balanceOf(address(this));
        assertEq(balanceAfterSecondWithdrawal, balanceAfterFirstWithdrawal, "balanceAfterSecondWithdrawal");
    }

    fallback() external payable { }
    receive() external payable { }
}
