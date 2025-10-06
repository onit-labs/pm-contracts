// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Config
import { OnitIODPMTestBase } from "@test/config/OnitIODPMTestBase.t.sol";
// Types
import { MarketInitData } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
// Interfaces
import { IOnitMarketResolver } from "@src/interfaces/IOnitMarketResolver.sol";
// Contract to test
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";
import { OnitMarketResolver } from "@src/resolvers/OnitMarketResolver.sol";

// Infinite Outcome DPM: updateResolution
contract IODPMTestUpdateResolution is OnitIODPMTestBase {
    function test_updateResolution_revert_MarketIsOpen() public {
        market = newMarketWithDefaultConfig();

        vm.expectRevert(IOnitMarketResolver.MarketIsOpen.selector);
        vm.prank(MARKET_OWNER);
        market.updateResolution(INITIAL_MEAN);
    }

    function test_updateResolution_revert_DisputePeriodPassed() public {
        MarketInitData memory config = defaultMarketConfig();
        config.config.withdrawlDelayPeriod = 1;
        market = newMarket(config);

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        vm.warp(block.timestamp + market.withdrawlDelayPeriod() + 1);
        vm.expectRevert(IOnitMarketResolver.DisputePeriodPassed.selector);
        vm.prank(MARKET_OWNER);
        market.updateResolution(INITIAL_MEAN);
    }

    function test_updateResolution_revert_MarketIsVoided() public {
        market = newMarketWithDefaultConfig();

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        vm.prank(MARKET_OWNER);
        market.voidMarket();

        vm.expectRevert(IOnitMarketResolver.MarketIsVoided.selector);
        vm.prank(MARKET_OWNER);
        market.updateResolution(INITIAL_MEAN);
    }

    function test_updateResolution_success() public {
        market = newMarketWithDefaultConfig();

        uint256 resolvedAtTimestamp = block.timestamp;
        vm.warp(resolvedAtTimestamp);
        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        assertEq(market.resolvedAtTimestamp(), resolvedAtTimestamp, "resolvedAtTimestamp");
        assertEq(market.resolvedOutcome(), INITIAL_MEAN, "resolvedOutcome");
        assertEq(market.resolvedBucketId(), INITIAL_MEAN / OUTCOME_UNIT, "resolvedBucketId");

        vm.prank(MARKET_OWNER);
        market.updateResolution(SECOND_MEAN);

        assertEq(market.resolvedAtTimestamp(), resolvedAtTimestamp, "resolvedAtTimestamp");
        assertEq(market.resolvedOutcome(), SECOND_MEAN, "resolvedOutcome");
        assertEq(market.resolvedBucketId(), SECOND_MEAN / OUTCOME_UNIT, "resolvedBucketId");
    }

    fallback() external payable { }
    receive() external payable { }
}
