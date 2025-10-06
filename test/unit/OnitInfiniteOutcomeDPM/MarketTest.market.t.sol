// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Config
import { OnitIODPMTestBase } from "@test/config/OnitIODPMTestBase.t.sol";
// Types
import { BetStatus, MarketConfig, MarketInitData } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
import { TokenType } from "@src/types/TOnitIODPMOrderManager.sol";
// Interfaces
import { IOnitInfiniteOutcomeDPM } from "@src/interfaces/IOnitInfiniteOutcomeDPM.sol";
import { IOnitIODPMOrderManager } from "@src/interfaces/IOnitIODPMOrderManager.sol";
import { IOnitMarketResolver } from "@src/interfaces/IOnitMarketResolver.sol";
import { IOnitInfiniteOutcomeDPMMechanism } from "@src/interfaces/IOnitInfiniteOutcomeDPMMechanism.sol";
// Contract to test
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";
import { OnitMarketResolver } from "@src/resolvers/OnitMarketResolver.sol";
import {
    OnitInfiniteOutcomeDPMMechanism
} from "@src/mechanisms/infinite-outcome-DPM/OnitInfiniteOutcomeDPMMechanism.sol";
import { OnitIODPMOrderManager } from "@src/order-manager/OnitIODPMOrderManager.sol";

contract InfiniteOutcomeDPMTestMarket is OnitIODPMTestBase {
    function setUp() public {
        vm.deal(orderRouterAddress, 1000 ether);
    }

    function test_initialMarket_reverts_AlreadyInitialized() public {
        OnitInfiniteOutcomeDPM testMarket;
        testMarket = new OnitInfiniteOutcomeDPM();

        address[] memory resolvers = new address[](1);
        resolvers[0] = RESOLVER_1;

        vm.expectRevert(IOnitInfiniteOutcomeDPM.AlreadyInitialized.selector);
        testMarket.initialize(
            MarketInitData({
                onitFactory: address(this),
                initiator: alice,
                orderRouter: orderRouterAddress,
                initialBetSize: INITIAL_BET_VALUE,
                seededFunds: UNSEEDED_MARKET,
                config: MarketConfig({
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
                initialBucketIds: DUMMY_BUCKET_IDS,
                initialShares: DUMMY_SHARES,
                orderRouterInitData: ""
            })
        );
    }

    function test_initialMarket_reverts_BetValueOutOfBounds_belowMinBetSize() public {
        MarketInitData memory initData = defaultMarketConfig();
        initData.initialBetSize = MIN_BET_SIZE - 1;
        vm.expectRevert(IOnitIODPMOrderManager.BetValueOutOfBounds.selector);
        market = newMarket(initData);
    }

    function test_initialMarket_reverts_BetValueOutOfBounds_aboveMaxBetSize() public {
        MarketInitData memory initData = defaultMarketConfig();
        initData.initialBetSize = MAX_BET_SIZE + 1;
        vm.expectRevert(IOnitIODPMOrderManager.BetValueOutOfBounds.selector);
        market = newMarket(initData);
    }

    function test_initialMarket_reverts_BettingCutoffOutOfBounds_inThePast() public {
        MarketInitData memory initData = defaultMarketConfig();
        initData.config.bettingCutoff = block.timestamp - 1 days;
        vm.expectRevert(IOnitInfiniteOutcomeDPM.BettingCutoffOutOfBounds.selector);
        market = newMarket(initData);
    }

    function test_initialMarket_reverts_MarketCreatorCommissionBpOutOfBounds() public {
        MarketInitData memory initData = defaultMarketConfig();
        initData.config.marketCreatorCommissionBp = MAX_MARKET_CREATOR_COMMISSION_BPS + 1;
        vm.expectRevert(IOnitInfiniteOutcomeDPM.MarketCreatorCommissionBpOutOfBounds.selector);
        market = newMarket(initData);
    }

    function test_initialMarket_token_reverts_BucketIdsNotStrictlyIncreasing() public {
        Wrapper wrapper = new Wrapper();
        vm.deal(address(wrapper), 100 ether);

        int256[] memory bucketIds = new int256[](2);
        bucketIds[0] = 0;
        bucketIds[1] = 0;

        int256[] memory shares = new int256[](2);
        shares[0] = 1;
        shares[1] = 1;

        MarketInitData memory initData = defaultMarketConfig();
        initData.initialBucketIds = bucketIds;
        initData.initialShares = shares;

        try wrapper.externalCall(initData) {
            revert("Should have reverted");
        } catch (bytes memory reason) {
            assertEq(
                reason, abi.encodeWithSelector(IOnitInfiniteOutcomeDPMMechanism.BucketIdsNotStrictlyIncreasing.selector)
            );
        }
    }

    function test_initializeMarket(
        uint256 initialBetValue,
        uint256 bettingCutoff,
        uint256 withdrawalDelayPeriod,
        int256 outcomeUnit
    )
        external
    {
        // Bound initialBetValue between 0.1 ether and 100 ether
        initialBetValue = bound(initialBetValue, MIN_BET_SIZE, MAX_BET_SIZE);
        // Bound bettingCutoff between current time and 10k days. With 1/100 chance of being 0
        bettingCutoff = bettingCutoff % 100 == 0
            ? 0
            : bound(bettingCutoff, block.timestamp, block.timestamp + 10_000 days);
        // Bound withdrawalDelayPeriod between 1 hour and 7 days
        withdrawalDelayPeriod = bound(withdrawalDelayPeriod, 0, 7 days);
        // Bound outcomeUnit between 1 and 1000 (todo: improve this and the share generation fns)
        outcomeUnit = int256(bound(uint256(outcomeUnit), 1, 1000));

        // Generate predictions (initialBetValue is used as seed)
        OnitIODPMTestBase.TestPrediction[] memory predictions =
            generateNormalDistributionPredictionArray(getDefaultNormalTestConfig(), initialBetValue);

        int256[] memory bucketIds = predictions[0].bucketIds;
        int256[] memory shares = predictions[0].shares;

        assertEq(address(market), address(0), "market already exists");

        MarketInitData memory initData = defaultMarketConfig();
        initData.initialBetSize = initialBetValue;
        initData.config.bettingCutoff = bettingCutoff;
        initData.config.withdrawlDelayPeriod = withdrawalDelayPeriod;
        initData.config.marketCreatorCommissionBp = MARKET_CREATOR_COMMISSION_BPS;
        initData.config.outcomeUnit = outcomeUnit;
        initData.initialBucketIds = bucketIds;
        initData.initialShares = shares;
        market = newMarket(initData);

        // Market values
        assertEq(market.marketQuestion(), MARKET_QUESTION, "marketQuestion");
        assertEq(market.uri(0), MARKET_URI_0, "marketUri");
        assertEq(market.bettingCutoff(), bettingCutoff, "bettingCutoff");
        assertEq(market.withdrawlDelayPeriod(), withdrawalDelayPeriod, "withdrawlDelayPeriod");
        assertEq(market.marketCreatorFeeReceiver(), MARKET_CREATOR_FEE_RECEIVER);
        assertEq(market.marketCreatorCommissionBp(), MARKET_CREATOR_COMMISSION_BPS);
        assertEq(market.nextNftTokenId(), 1, "nextNftTokenId");
        assertEq(market.outcomeUnit(), outcomeUnit, "outcomeUnit");
        assertEq(market.kappa(), getKappaForInitialMarket(shares, int256(initialBetValue)), "kappa");
        assertEq(address(market).balance, initialBetValue, "market balance");
        assertEq(market.onitFactory(), address(factory), "onitFactory");
        assertEq(market.isResolver(RESOLVER_1), true, "resolver");

        // Initial traders values
        (uint256 totalStake, uint256 nftId, BetStatus status) = market.tradersStake(alice);
        assertEq(totalStake, initialBetValue, "tradersStake");
        assertEq(nftId, FIRST_PREDICTION_ID, "nftId");
        assertEq(market.balanceOf(alice, FIRST_PREDICTION_ID), 1, "alice ERC1155 balance");
        assertEq(uint8(status), uint8(BetStatus.OPEN), "alice status");

        // Outcome token values
        assertApproxEqRel(
            market.totalQSquared(),
            getTotalQSquaredForMarket(market.kappa(), int256(initialBetValue)),
            // TODO check the rounding for values less than this
            initialBetValue > 0.001 ether ? KAPPA_TOLERANCE : 0.0001 ether,
            "initial totalQSquared"
        );
        for (uint256 i; i < shares.length; i++) {
            uint256 aliceTokens = market.getBalanceOfShares(alice, bucketIds[i]);
            int256 totalOutstandingShares = market.getBucketOutstandingShares(bucketIds[i]);
            assertEq(aliceTokens, uint256(shares[i]), "aliceTokens");
            assertEq(totalOutstandingShares, shares[i], "totalOutstandingShares");
        }
    }

    function test_initializeMarket_noBettingCutoff() public {
        MarketInitData memory initData = defaultMarketConfig();
        initData.config.bettingCutoff = 0;
        market = newMarket(initData);

        assertEq(market.marketQuestion(), MARKET_QUESTION, "marketQuestion");
        assertEq(market.bettingCutoff(), 0, "bettingCutoff");
    }

    function test_updateBettingCutoff_reverts_NotOwner() public {
        market = newMarketWithDefaultConfig();

        // Try to update cutoff as non-owner
        vm.prank(alice);
        vm.expectRevert(IOnitMarketResolver.OnlyOnitFactoryOwner.selector);
        market.updateBettingCutoff(block.timestamp + 1 days);
    }

    function test_updateBettingCutoff() public {
        MarketInitData memory initData = defaultMarketConfig();
        initData.config.bettingCutoff = 0;
        market = newMarket(initData);

        // Set betting cutoff to past
        vm.prank(MARKET_OWNER);
        market.updateBettingCutoff(block.timestamp - 1);

        // Verify betting is closed by attempting to place a bet
        (int256 cost,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);

        vm.prank(orderRouterAddress);
        vm.expectRevert(IOnitInfiniteOutcomeDPM.BettingCutoffPassed.selector);
        market.buyShares{ value: uint256(cost) }(alice, uint256(cost), DUMMY_BUCKET_IDS, DUMMY_SHARES);

        // Update betting cutoff to future
        vm.prank(MARKET_OWNER);
        market.updateBettingCutoff(block.timestamp + 1 days);

        // Verify betting is open by placing a bet
        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(cost) }(alice, uint256(cost), DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_voidMarket_reverts_NotOwner() public {
        market = newMarketWithDefaultConfig();

        vm.prank(bob);
        vm.expectRevert(IOnitMarketResolver.OnlyOnitFactoryOwner.selector);
        market.voidMarket();
    }

    function test_voidMarket() public {
        market = newMarketWithDefaultConfig();

        market.voidMarket();
        assertEq(market.marketVoided(), true, "marketVoided");
    }

    function test_updateTokenUri_reverts_NotOwner() public {
        market = newMarketWithDefaultConfig();

        vm.prank(bob);
        vm.expectRevert(IOnitMarketResolver.OnlyOnitFactoryOwner.selector);
        market.setUri("newUri");
    }

    function test_updateTokenUri() public {
        market = newMarketWithDefaultConfig();

        string memory marketUri = market.uri(0);
        assertEq(marketUri, MARKET_URI_0, "marketUri");
        market.setUri("newUri/");
        marketUri = market.uri(0);
        assertEq(marketUri, "newUri/0", "newUri");
    }

    function test_cannotSendEthToContract() public {
        market = newMarketWithDefaultConfig();

        assertEq(address(market).balance, INITIAL_BET_VALUE, "contract balance");
        // Send some eth to the contract which is not allowed
        vm.prank(address(alice));
        vm.expectRevert(IOnitInfiniteOutcomeDPM.RejectFunds.selector);
        (bool success, bytes memory returnData) = address(market).call{ value: HALF_ETHER }("");
        success;
        returnData;
        assertEq(address(market).balance, INITIAL_BET_VALUE, "contract balance");
    }

    // ----------------------------------------------------------------
    // Utils
    // ----------------------------------------------------------------

    fallback() external payable { }
    receive() external payable { }
}

// Awkward work around to use try catch to catch a revert which is not the next call
contract Wrapper is OnitIODPMTestBase {
    function externalCall(MarketInitData memory initData) external {
        newMarket(initData);
    }
}
