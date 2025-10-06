// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc utils
import { stdMath } from "forge-std/StdMath.sol";
// Config
import { OnitIODPMTestBase } from "@test/config/OnitIODPMTestBase.t.sol";
// Types
import { MarketConfig, MarketInitData } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
import { TokenType } from "@src/types/TOnitIODPMOrderManager.sol";
// Interfaces
import { IOnitMarketResolver } from "@src/interfaces/IOnitMarketResolver.sol";
// Contract to test
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";
import { OnitMarketResolver } from "@src/resolvers/OnitMarketResolver.sol";
import { OnitIODPMOrderManager } from "@src/order-manager/OnitIODPMOrderManager.sol";

// Infinite Outcome DPM: resolveMarket
contract IODPMTestResolveMarket is OnitIODPMTestBase {
    event MarketResolved(address indexed resolver, int256 outcome, uint256 timestamp);

    function setUp() public {
        vm.deal(orderRouterAddress, 100 ether);
    }

    function test_resolveMarket_revert_OnlyResolver() public {
        market = newMarketWithDefaultConfig();

        vm.prank(bob);
        vm.expectRevert(IOnitMarketResolver.OnlyResolver.selector);
        market.resolveMarket(INITIAL_MEAN);
    }

    function test_resolveMarket_revert_MarketIsResolved() public {
        market = newMarketWithDefaultConfig();

        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);

        vm.prank(RESOLVER_1);
        vm.expectRevert(IOnitMarketResolver.MarketIsResolved.selector);
        market.resolveMarket(INITIAL_MEAN);
    }

    function test_resolveMarket_revert_MarketIsVoided() public {
        market = newMarketWithDefaultConfig();

        vm.prank(MARKET_OWNER);
        market.voidMarket();

        vm.expectRevert(IOnitMarketResolver.MarketIsVoided.selector);
        vm.prank(RESOLVER_1);
        market.resolveMarket(INITIAL_MEAN);
    }

    function testFuzz_resolveMarket(uint256 betValue, int256 resolvedOutcome, int256 outcomeUnit) public {
        resolvedOutcome = bound(resolvedOutcome, -1e40, 1e40);
        // Set some bounds on the fuzzed input
        betValue = bound(betValue, MIN_BET_SIZE, MAX_BET_SIZE);
        // Ensure outcome unit is positive and at most half of abs(resolvedOutcome) [v ugly fix this]
        outcomeUnit = resolvedOutcome == 0
            ? int256(1)
            : bound(
                outcomeUnit,
                1,
                int256(stdMath.abs(resolvedOutcome) / 2) == 0 ? int256(1) : int256(stdMath.abs(resolvedOutcome) / 2)
            );

        MarketInitData memory config = defaultMarketConfig();
        config.initialBetSize = betValue;
        config.config.resolvers = new address[](1);
        config.config.resolvers[0] = RESOLVER_1;
        config.config.outcomeUnit = outcomeUnit;
        market = newMarket(config);

        assertEq(market.resolvedOutcome(), 0, "resolvedOutcome");

        uint256 resolvedAtTimestamp = block.timestamp;
        vm.warp(resolvedAtTimestamp);
        vm.prank(RESOLVER_1);
        market.resolveMarket(resolvedOutcome);

        int256 resolvedBucketId = getBucketId(resolvedOutcome, outcomeUnit);

        // Outcome variables
        assertEq(market.resolvedOutcome(), resolvedOutcome, "resolvedOutcome");
        assertEq(market.resolvedAtTimestamp(), resolvedAtTimestamp, "resolvedAtTimestamp");
        assertEq(market.resolvedBucketId(), resolvedBucketId, "resolvedBucketId");

        // Market variables
        uint256 protocolFee = address(market).balance * market.PROTOCOL_COMMISSION_BP() / 10_000;
        uint256 marketCreatorFee = address(market).balance * market.marketCreatorCommissionBp() / 10_000;
        assertEq(market.protocolFee(), protocolFee, "protocolFee");
        assertEq(market.marketCreatorFee(), marketCreatorFee, "marketCreatorFee");
        assertEq(market.totalPayout(), address(market).balance - protocolFee - marketCreatorFee, "totalPayout");
        assertEq(
            market.winningBucketSharesAtClose(),
            market.getBucketOutstandingShares(resolvedBucketId),
            "winningBucketSharesAtClose"
        );
    }

    function test_resolveMarket_withSecondResolver() public {
        address[] memory resolvers = new address[](2);
        resolvers[0] = RESOLVER_1;
        resolvers[1] = RESOLVER_2;

        market = factory.createMarket{
            value: INITIAL_BET_VALUE
        }(
            alice,
            CREATE_MARKET_SALT,
            UNSEEDED_MARKET,
            INITIAL_BET_VALUE,
            MarketConfig({
                currencyType: TokenType.NATIVE,
                currency: address(0),
                marketCreatorFeeReceiver: MARKET_CREATOR_FEE_RECEIVER,
                marketCreatorCommissionBp: MARKET_CREATOR_COMMISSION_BPS,
                bettingCutoff: BETTING_CUTOFF_ONE_DAY,
                withdrawlDelayPeriod: WITHDRAWAL_DELAY_PERIOD_ONE_DAY,
                minBetSize: MIN_BET_SIZE,
                maxBetSize: MAX_BET_SIZE,
                outcomeUnit: OUTCOME_UNIT,
                marketQuestion: MARKET_QUESTION,
                marketUri: MARKET_URI,
                resolvers: resolvers
            }),
            DUMMY_BUCKET_IDS,
            DUMMY_SHARES,
            ""
        );

        vm.prank(RESOLVER_2);
        market.resolveMarket(INITIAL_MEAN);

        assertEq(market.resolvedOutcome(), INITIAL_MEAN, "resolvedOutcome");
    }

    fallback() external payable { }
    receive() external payable { }
}
