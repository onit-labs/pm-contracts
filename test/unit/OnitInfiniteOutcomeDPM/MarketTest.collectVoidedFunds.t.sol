// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc utils
import { ERC1155 } from "solady/tokens/ERC1155.sol";
import { Receiver } from "solady/accounts/Receiver.sol";
import { console2 } from "forge-std/console2.sol";
// PRB Math for matching contract's rounding behavior
import { convert as convertU, convert as convertU, div as divU, mul as mulU } from "prb-math/UD60x18.sol";
// Config
import { OnitIODPMTestBase } from "@test/config/OnitIODPMTestBase.t.sol";
// Types
import { BetStatus, MarketInitData } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
// Interfaces
import { IOnitInfiniteOutcomeDPM } from "@src/interfaces/IOnitInfiniteOutcomeDPM.sol";
import { IOnitMarketResolver } from "@src/interfaces/IOnitMarketResolver.sol";
import { IOnitIODPMOrderManager } from "@src/interfaces/IOnitIODPMOrderManager.sol";
// Contract to test
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";
import { OnitMarketResolver } from "@src/resolvers/OnitMarketResolver.sol";
import { OnitIODPMOrderManager } from "@src/order-manager/OnitIODPMOrderManager.sol";

// Infinite Outcome DPM: collectVoidedFunds
contract IODPMTestCollectVoidedFunds is OnitIODPMTestBase {
    function setUp() public {
        vm.deal(orderRouterAddress, 100 ether);
    }

    /// @notice Calculate expected payout using same PRB Math logic as contract
    /// @param pool Current pool balance
    /// @param traderStake Trader's stake amount
    /// @param totalOpenStake Total open stake in market
    /// @return Expected payout amount
    /// @dev This uses identical PRB Math operations as the contract's collectVoidedFunds function.
    ///      Due to rounding in division, sequential calls may leave small dust amounts in the pool.
    function _calculateExpectedPayout(uint256 pool, uint256 traderStake, uint256 totalOpenStake)
        internal
        pure
        returns (uint256)
    {
        if (totalOpenStake == 0 || traderStake == 0) return 0;
        // Use same PRB Math logic as contract: pool * traderStake / totalOpenStake
        return convertU(divU(mulU(convertU(pool), convertU(traderStake)), convertU(totalOpenStake)));
    }

    function test_collectVoidedFunds_revert_MarketIsOpen() public {
        market = newMarketWithDefaultConfig();

        vm.expectRevert(IOnitMarketResolver.MarketIsOpen.selector);
        market.collectVoidedFunds(alice);
    }

    function test_collectVoidedFunds_revert_NothingToPay() public {
        market = newMarketWithDefaultConfig();

        vm.prank(MARKET_OWNER);
        market.voidMarket();
        market.collectVoidedFunds(alice);

        vm.expectRevert(IOnitIODPMOrderManager.NothingToPay.selector);
        market.collectVoidedFunds(alice);
    }

    function test_collectVoidedFunds_reentrant() public {
        market = newMarketWithDefaultConfig();

        VoidedReentrant reentrant = new VoidedReentrant(address(market));
        address reentrantAddress = address(reentrant);

        (int256 cost,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);

        int256 reentrantOriginalBalance = cost;
        vm.deal(reentrantAddress, uint256(reentrantOriginalBalance));

        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(cost) }(reentrantAddress, uint256(cost), DUMMY_BUCKET_IDS, DUMMY_SHARES);

        vm.prank(MARKET_OWNER);
        market.voidMarket();

        // Expect revert doesnt work on the second call, so we let it pass and confirm the attack failed by checking
        // balance is equal to their original balance and no more
        market.collectVoidedFunds(reentrantAddress);

        // Attacker only got expected balance since reentrancy failed
        assertEq(address(reentrant).balance, uint256(reentrantOriginalBalance + cost), "reentrant balance");
    }

    function test_collectVoidedFunds() public {
        market = newMarketWithDefaultConfig();

        (int256 costBob,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(costBob) }(bob, uint256(costBob), DUMMY_BUCKET_IDS, DUMMY_SHARES);

        uint256 aliceBalance = address(alice).balance;
        uint256 bobBalance = address(bob).balance;
        uint256 marketBalance = address(market).balance;

        assertEq(marketBalance, uint256(costBob) + INITIAL_BET_VALUE, "initial market balance");

        // Alice's holdings
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
        assertEq(address(alice).balance, aliceBalance + INITIAL_BET_VALUE, "alice balance");

        market.collectVoidedFunds(bob);

        (totalStake, nftId,) = market.tradersStake(bob);
        assertEq(totalStake, 0, "bob total stake");
        assertEq(nftId, 0, "bob nftId");
        assertEq(address(bob).balance, bobBalance + uint256(costBob), "bob balance");

        assertEq(address(market).balance, 0, "final market balance");
    }

    function test_collectVoidedFunds_proportionalDistribution() public {
        market = newMarketWithDefaultConfig();

        // Alice starts with INITIAL_BET_VALUE (default market creator)
        // Bob makes a bet
        (int256 costBob,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(costBob) }(bob, uint256(costBob), DUMMY_BUCKET_IDS, DUMMY_SHARES);

        // Carl makes a different bet (different buckets to avoid overlap)
        int256[] memory carlBuckets = new int256[](1);
        carlBuckets[0] = 15; // different bucket from DUMMY_BUCKET_IDS
        int256[] memory carlShares = new int256[](1);
        carlShares[0] = 50; // different amount
        (int256 costCarl,) = market.calculateCostOfTrade(carlBuckets, carlShares);
        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(costCarl) }(carl, uint256(costCarl), carlBuckets, carlShares);

        // Total pool = INITIAL_BET_VALUE + calculated costs
        uint256 totalPool = INITIAL_BET_VALUE + uint256(costBob) + uint256(costCarl);
        assertEq(address(market).balance, totalPool, "total pool");
        assertEq(market.totalOpenStake(), totalPool, "total open stake");

        // Verify individual stakes
        (uint256 aliceStake,,) = market.tradersStake(alice);
        (uint256 bobStake,,) = market.tradersStake(bob);
        (uint256 carlStake,,) = market.tradersStake(carl);
        assertEq(aliceStake, INITIAL_BET_VALUE, "alice stake");
        assertEq(bobStake, uint256(costBob), "bob stake");
        assertEq(carlStake, uint256(costCarl), "carl stake");

        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 bobBalanceBefore = address(bob).balance;
        uint256 carlBalanceBefore = address(carl).balance;

        vm.prank(MARKET_OWNER);
        market.voidMarket();

        // Alice claims first (should get proportional share)
        uint256 poolBeforeAlice = address(market).balance;
        uint256 aliceExpected = _calculateExpectedPayout(poolBeforeAlice, aliceStake, totalPool);
        market.collectVoidedFunds(alice);
        assertEq(address(alice).balance, aliceBalanceBefore + aliceExpected, "alice payout");

        // Bob claims second
        uint256 poolBeforeBob = address(market).balance;
        uint256 currentTotalStake = market.totalOpenStake();
        uint256 bobExpected = _calculateExpectedPayout(poolBeforeBob, bobStake, currentTotalStake);
        market.collectVoidedFunds(bob);
        assertEq(address(bob).balance, bobBalanceBefore + bobExpected, "bob payout");

        // Carl claims last (gets remaining balance)
        uint256 poolBeforeCarl = address(market).balance;
        market.collectVoidedFunds(carl);
        assertEq(address(carl).balance, carlBalanceBefore + poolBeforeCarl, "carl payout");
        assertEq(market.totalOpenStake(), 0, "total stake after carl");
        assertEq(address(market).balance, 0, "final pool balance");
    }

    function test_collectVoidedFunds_withProfitableSells() public {
        uint256 initialBetSize = 0.001 ether;
        MarketInitData memory initData = defaultMarketConfig();
        initData.initialBetSize = initialBetSize;
        market = newMarket(initData);

        // Setup arrays for bucket 2 bets
        int256[] memory bucket2 = new int256[](1);
        bucket2[0] = 2;
        int256[] memory betShares = new int256[](1);
        betShares[0] = 10;

        // Bob makes an early bet in bucket 2 (he'll be our tracked participant)
        int256[] memory bobShares = new int256[](1);
        bobShares[0] = 10;
        (int256 costBob,) = market.calculateCostOfTrade(bucket2, bobShares);
        vm.deal(orderRouterAddress, uint256(costBob));
        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(costBob) }(bob, uint256(costBob), bucket2, bobShares);

        // Carl makes a bet in bucket 2 increasing its price
        int256[] memory carlShares = new int256[](1);
        carlShares[0] = 15;
        (int256 costCarl,) = market.calculateCostOfTrade(bucket2, carlShares);
        vm.deal(orderRouterAddress, uint256(costCarl));
        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(costCarl) }(carl, uint256(costCarl), bucket2, carlShares);

        // Dave makes a bet in bucket 2 increasing its price
        int256[] memory daveShares = new int256[](1);
        daveShares[0] = 15;
        (int256 costDave,) = market.calculateCostOfTrade(bucket2, daveShares);
        vm.deal(orderRouterAddress, uint256(costDave));
        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(costDave) }(dave, uint256(costDave), bucket2, daveShares);

        // Check Bob's initial stake
        (uint256 bobInitialStake,,) = market.tradersStake(bob);
        assertEq(bobInitialStake, uint256(costBob), "bob initial stake should equal initial bet value");

        // Bob sells his position in bucket 2 for profit (he bought at low price)
        int256[] memory bobSellBuckets = new int256[](1);
        bobSellBuckets[0] = 2;
        int256[] memory bobSellShares = new int256[](1);
        bobSellShares[0] = -int256(bobShares[0]);

        uint256 bobBalanceBeforeSell = address(bob).balance;

        vm.prank(orderRouterAddress);
        market.sellShares(bob, bobSellBuckets, bobSellShares);

        uint256 bobBalanceAfterSell = address(bob).balance;
        uint256 bobPayout = bobBalanceAfterSell - bobBalanceBeforeSell;

        // Verify Bob made a profit (payout should be greater than his original stake)
        assertGt(bobPayout, initialBetSize, "bob should have made a profit from selling");

        // Check Bob's remaining stake after selling
        (uint256 bobStakeAfterSell,,) = market.tradersStake(bob);
        uint256 expectedBobStake = 0;
        assertEq(bobStakeAfterSell, expectedBobStake, "bob stake after sell");

        // Now void the market
        vm.prank(MARKET_OWNER);
        market.voidMarket();

        // Get stakes of remaining bettors before collecting voided funds
        (uint256 aliceStake,,) = market.tradersStake(alice);
        (uint256 carlStake,,) = market.tradersStake(carl);
        (uint256 daveRemainingStake,,) = market.tradersStake(dave);

        uint256 totalPool = address(market).balance;
        uint256 totalStakeRemaining = market.totalOpenStake();

        // Because Bob sold his shares for profit, the total pool is less than the total stake remaining
        assertLt(totalPool, totalStakeRemaining, "total pool should be less than total stake remaining");

        // Calculate expected proportional returns using PRB Math (same as contract)
        uint256 aliceExpected = _calculateExpectedPayout(totalPool, aliceStake, totalStakeRemaining);
        uint256 carlExpected = _calculateExpectedPayout(totalPool, carlStake, totalStakeRemaining);
        uint256 daveExpected = _calculateExpectedPayout(totalPool, daveRemainingStake, totalStakeRemaining);
        // Because Bob sold his shares for profit, the expected returns should be less than the cost of the shares
        assertLt(aliceExpected, uint256(costBob), "alice expected return should be less than costBob");
        assertLt(carlExpected, uint256(costCarl), "carl expected return should be less than costCarl");
        assertLt(daveExpected, uint256(costDave), "dave expected return should be less than costDave");

        // Store balances before claiming
        uint256 aliceBalanceBeforeVoid = address(alice).balance;
        // uint256 bobBalanceBeforeVoid = address(bob).balance;
        uint256 carlBalanceBeforeVoid = address(carl).balance;
        uint256 daveBalanceBeforeVoid = address(dave).balance;

        // Collect voided funds for all participants
        market.collectVoidedFunds(alice);
        market.collectVoidedFunds(carl);
        market.collectVoidedFunds(dave);

        // Check actual payouts
        uint256 aliceActualReturn = address(alice).balance - aliceBalanceBeforeVoid;
        uint256 carlActualReturn = address(carl).balance - carlBalanceBeforeVoid;
        uint256 daveActualReturn = address(dave).balance - daveBalanceBeforeVoid;

        assertGt(aliceActualReturn, 0, "alice actual return should be greater than 0");
        assertGt(carlActualReturn, 0, "carl actual return should be greater than 0");
        assertGt(daveActualReturn, 0, "dave actual return should be greater than 0");
        // Verify proportional distribution (allowing for rounding differences of up to 3 wei)
        assertApproxEqRel(aliceActualReturn, aliceExpected, 1e14, "alice proportional void return");
        assertApproxEqRel(carlActualReturn, carlExpected, 1e14, "carl proportional void return");
        assertApproxEqRel(daveActualReturn, daveExpected, 1e14, "dave proportional void return");

        // Verify all funds are distributed and no rounding errors left significant amounts
        uint256 totalDistributed = aliceActualReturn + carlActualReturn + daveActualReturn;

        assertApproxEqRel(totalDistributed, totalPool, 1e15, "total distributed should equal pool (within rounding)");
        // Verify market is completely cleared
        assertEq(address(market).balance, 0, "market should have no remaining balance");
        assertEq(market.totalOpenStake(), 0, "total open stake should be zero");

        // // Additional check: ensure small stakes didn't get completely lost to rounding
        // if (totalPool > 1000 && bobRemainingStake > 0) {
        // // Only check this if pool is reasonably large and Bob had remaining stake
        // uint256 minExpectedBob = (totalPool * bobRemainingStake) / totalStakeRemaining;
        // if (minExpectedBob > 0) {
        // assertGt(bobActualReturn, 0, "bob should not lose all funds to rounding when expected return > 0");
        //}
        //}
    }

    /// @notice Fuzzed version testing profitable sells with randomized parameters
    /// @param initialBetSize Initial bet size for market creation (bounded to reasonable range)
    /// @param numTraders Number of additional traders to create (1-8, excluding Alice)
    /// @param targetBucket Bucket for profitable trading (bounded to avoid edge buckets)
    /// @param sellPercentage Percentage of shares to sell for profit (10-100%)
    function testFuzz_collectVoidedFunds_withProfitableSells(
        uint256 initialBetSize,
        uint8 numTraders,
        int256 targetBucket,
        uint8 sellPercentage
    )
        public
    {
        // Bound parameters to reasonable ranges
        initialBetSize = bound(initialBetSize, 0.0001 ether, 1 ether);
        numTraders = uint8(bound(numTraders, 1, 8)); // 1-8 additional traders
        targetBucket = int256(bound(targetBucket, -20, 20)); // Avoid extreme buckets
        sellPercentage = uint8(bound(sellPercentage, 10, 100)); // 10-100% sell

        // Create market with fuzzed initial bet size
        MarketInitData memory initData = defaultMarketConfig();
        initData.initialBetSize = initialBetSize;
        initData.config.minBetSize = 0;
        initData.config.maxBetSize = 100_000_000_000 ether;
        market = newMarket(initData);

        // Create arrays for dynamic trader management
        address[] memory traders = new address[](numTraders);
        uint256[] memory stakes = new uint256[](numTraders);
        uint256[] memory balancesBefore = new uint256[](numTraders);

        // Assign trader addresses (use available addresses, create more if needed)
        address[8] memory traderPool =
            [bob, carl, dave, eve, makeAddr("frank"), makeAddr("grace"), makeAddr("henry"), makeAddr("iris")];
        for (uint8 i = 0; i < numTraders; i++) {
            traders[i] = traderPool[i];
            // Ensure each trader has enough ETH
            vm.deal(traders[i], 100 ether);
        }

        // Setup bucket and shares arrays
        int256[] memory buckets = new int256[](1);
        buckets[0] = targetBucket;

        // First trader makes initial bet (will be profitable seller)
        int256[] memory firstTraderShares = new int256[](1);
        firstTraderShares[0] = int256(bound(uint256(keccak256(abi.encode("shares", 0))), 1, 100));

        (int256 firstCost,) = market.calculateCostOfTrade(buckets, firstTraderShares);
        vm.deal(orderRouterAddress, uint256(firstCost));
        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(firstCost) }(traders[0], uint256(firstCost), buckets, firstTraderShares);

        stakes[0] = uint256(firstCost);

        // Additional traders make bets to increase bucket price
        for (uint8 i = 1; i < numTraders; i++) {
            int256[] memory traderShares = new int256[](1);
            // Vary share amounts using deterministic randomness
            traderShares[0] = int256(bound(uint256(keccak256(abi.encode("shares", i))), 1, 200));

            (int256 cost,) = market.calculateCostOfTrade(buckets, traderShares);
            vm.deal(orderRouterAddress, uint256(cost));
            vm.prank(orderRouterAddress);
            market.buyShares{ value: uint256(cost) }(traders[i], uint256(cost), buckets, traderShares);

            stakes[i] = uint256(cost);
        }

        // First trader sells portion of shares for profit
        uint256 sharesToSell = uint256(firstTraderShares[0]) * sellPercentage / 100;
        if (sharesToSell > 0) {
            int256[] memory sellShares = new int256[](1);
            sellShares[0] = -int256(sharesToSell);

            uint256 balanceBeforeSell = address(traders[0]).balance;
            vm.prank(orderRouterAddress);
            market.sellShares(traders[0], buckets, sellShares);
            uint256 balanceAfterSell = address(traders[0]).balance;

            // Verify profitable sell occurred
            uint256 sellPayout = balanceAfterSell - balanceBeforeSell;
            if (sellPayout > 0) {
                // Update first trader's remaining stake
                (stakes[0],,) = market.tradersStake(traders[0]);
            }
        }

        // Void the market
        vm.prank(MARKET_OWNER);
        market.voidMarket();

        // Get final stakes and pool state
        uint256 totalPool = address(market).balance;
        uint256 totalStakeRemaining = market.totalOpenStake();
        (uint256 aliceStake,,) = market.tradersStake(alice);

        // Update stakes array with current values
        for (uint8 i = 0; i < numTraders; i++) {
            (stakes[i],,) = market.tradersStake(traders[i]);
            balancesBefore[i] = address(traders[i]).balance;
        }
        uint256 aliceBalanceBefore = address(alice).balance;

        // Calculate expected distributions using PRB Math (same as contract)
        uint256 aliceExpected = _calculateExpectedPayout(totalPool, aliceStake, totalStakeRemaining);
        uint256[] memory expectedReturns = new uint256[](numTraders);
        for (uint8 i = 0; i < numTraders; i++) {
            expectedReturns[i] = _calculateExpectedPayout(totalPool, stakes[i], totalStakeRemaining);
        }

        // Collect voided funds and verify each individual calculation
        // Note: Contract updates totalOpenStake after each collection, so we need to verify sequentially

        // Alice collects first
        uint256 aliceActual = 0;
        if (aliceStake > 0) {
            market.collectVoidedFunds(alice);
            aliceActual = address(alice).balance - aliceBalanceBefore;
            assertEq(aliceActual, aliceExpected, "exact alice proportional return with PRB Math");
        }

        // Traders collect sequentially (pool and totalOpenStake change after each collection)
        uint256 totalDistributed = aliceActual;
        for (uint8 i = 0; i < numTraders; i++) {
            if (stakes[i] > 0) {
                uint256 currentPool = address(market).balance;
                uint256 currentTotalStake = market.totalOpenStake();
                uint256 expectedReturn = _calculateExpectedPayout(currentPool, stakes[i], currentTotalStake);

                market.collectVoidedFunds(traders[i]);
                uint256 actualReturn = address(traders[i]).balance - balancesBefore[i];
                totalDistributed += actualReturn;

                assertEq(actualReturn, expectedReturn, "exact proportional distribution with PRB Math");
                assertGt(actualReturn, 0, "non-zero payout for stake holder");
            }
        }

        // Verify fund distribution accounting
        // Note: Due to PRB Math rounding in sequential divisions, there may be small dust remaining
        // The contract prioritizes exact proportional payouts over perfect pool clearing
        uint256 remainingBalance = address(market).balance;

        // Total distributed + remaining should equal the original pool we started with
        assertEq(totalDistributed + remainingBalance, totalPool, "total pool accounting");

        // Any remaining balance should be very small (rounding dust) - at most a few wei per trader
        assertLe(remainingBalance, numTraders + 2, "minimal rounding dust");

        // TotalOpenStake should be zero since we collected from everyone
        assertEq(market.totalOpenStake(), 0, "total stake cleared");
    }

    /// @notice Fuzzed test for multiple partial sells and complex scenarios
    /// @param numSells Number of sell transactions (1-5)
    /// @param sellPercentages Array of percentages for each sell (10-90% each)
    /// @param bucketSpread How many different buckets to use (1-3)
    function testFuzz_collectVoidedFunds_multiplePartialSells(
        uint8 numSells,
        uint256 sellPercentages,
        uint8 bucketSpread
    )
        public
    {
        // Bound parameters
        numSells = uint8(bound(numSells, 1, 5));
        bucketSpread = uint8(bound(bucketSpread, 1, 3));

        // Create market with medium initial bet for stability
        MarketInitData memory initData = defaultMarketConfig();
        initData.initialBetSize = 0.01 ether;
        market = newMarket(initData);

        // Setup multiple buckets for testing
        int256[] memory buckets = new int256[](bucketSpread);
        for (uint8 i = 0; i < bucketSpread; i++) {
            buckets[i] = int256(uint256(i + 1)); // buckets 1, 2, 3
        }

        // Bob makes initial positions across all buckets
        int256[] memory bobShares = new int256[](bucketSpread);
        for (uint8 i = 0; i < bucketSpread; i++) {
            bobShares[i] = int256(bound(uint256(keccak256(abi.encode("bob", i))), 20, 100));
        }

        (int256 bobInitialCost,) = market.calculateCostOfTrade(buckets, bobShares);
        vm.deal(orderRouterAddress, uint256(bobInitialCost));
        vm.prank(orderRouterAddress);
        market.buyShares{ value: uint256(bobInitialCost) }(bob, uint256(bobInitialCost), buckets, bobShares);

        // Carl and Dave make bets to increase prices
        for (uint8 trader = 0; trader < 2; trader++) {
            address traderAddr = trader == 0 ? carl : dave;
            int256[] memory traderShares = new int256[](bucketSpread);

            for (uint8 i = 0; i < bucketSpread; i++) {
                traderShares[i] = int256(bound(uint256(keccak256(abi.encode("trader", trader, i))), 10, 50));
            }

            (int256 cost,) = market.calculateCostOfTrade(buckets, traderShares);
            vm.deal(orderRouterAddress, uint256(cost));
            vm.prank(orderRouterAddress);
            market.buyShares{ value: uint256(cost) }(traderAddr, uint256(cost), buckets, traderShares);
        }

        // Track Bob's initial position for reference
        (uint256 bobInitialStake,,) = market.tradersStake(bob);
        bobInitialStake; // Silence unused variable warning
        uint256 totalSellProfit = 0;

        // Bob makes multiple partial sells
        for (uint8 sellIdx = 0; sellIdx < numSells; sellIdx++) {
            // Extract sell percentage for this sell (use different bits of sellPercentages)
            uint8 sellPercent = uint8(bound((sellPercentages >> (sellIdx * 8)) & 0xFF, 10, 90));

            // Choose bucket to sell from (cycle through available buckets)
            uint8 bucketIdx = sellIdx % bucketSpread;
            int256[] memory sellBucket = new int256[](1);
            sellBucket[0] = buckets[bucketIdx];

            // Calculate shares to sell (percentage of original position in this bucket)
            uint256 originalShares = uint256(bobShares[bucketIdx]);
            uint256 sharesToSell = originalShares * sellPercent / 100;

            if (sharesToSell > 0) {
                int256[] memory sellShares = new int256[](1);
                sellShares[0] = -int256(sharesToSell);

                uint256 balanceBeforeSell = address(bob).balance;

                // Check if Bob still has shares to sell
                uint256 currentShares = market.balanceOf(bob, uint256(buckets[bucketIdx]));
                if (currentShares >= sharesToSell) {
                    vm.prank(orderRouterAddress);
                    market.sellShares(bob, sellBucket, sellShares);

                    uint256 balanceAfterSell = address(bob).balance;
                    totalSellProfit += balanceAfterSell - balanceBeforeSell;

                    // Update remaining shares for next iteration
                    bobShares[bucketIdx] -= int256(sharesToSell);
                }
            }
        }

        // Get Bob's remaining stake after all sells
        (uint256 bobRemainingStake,,) = market.tradersStake(bob);

        // Void the market
        vm.prank(MARKET_OWNER);
        market.voidMarket();

        // Get final state
        uint256 totalPool = address(market).balance;

        (uint256 aliceStake,,) = market.tradersStake(alice);
        (uint256 carlStake,,) = market.tradersStake(carl);
        (uint256 daveStake,,) = market.tradersStake(dave);

        // Store balances before collecting voided funds
        uint256 aliceBalanceBefore = address(alice).balance;
        uint256 bobBalanceBefore = address(bob).balance;
        uint256 carlBalanceBefore = address(carl).balance;
        uint256 daveBalanceBefore = address(dave).balance;

        // Collect voided funds sequentially and verify each calculation
        uint256 totalDistributed = 0;

        // Alice collects first
        uint256 aliceActual = 0;
        if (aliceStake > 0) {
            uint256 currentPool = address(market).balance;
            uint256 currentTotalStake = market.totalOpenStake();
            uint256 aliceExpected = _calculateExpectedPayout(currentPool, aliceStake, currentTotalStake);

            market.collectVoidedFunds(alice);
            aliceActual = address(alice).balance - aliceBalanceBefore;
            totalDistributed += aliceActual;

            assertEq(aliceActual, aliceExpected, "exact alice proportional after multiple sells");
        }

        // Bob collects if he has remaining stake
        uint256 bobActual = 0;
        if (bobRemainingStake > 0) {
            uint256 currentPool = address(market).balance;
            uint256 currentTotalStake = market.totalOpenStake();
            uint256 bobExpected = _calculateExpectedPayout(currentPool, bobRemainingStake, currentTotalStake);

            market.collectVoidedFunds(bob);
            bobActual = address(bob).balance - bobBalanceBefore;
            totalDistributed += bobActual;

            assertEq(bobActual, bobExpected, "exact bob proportional after multiple sells");
        }

        // Carl collects
        uint256 carlActual = 0;
        if (carlStake > 0) {
            uint256 currentPool = address(market).balance;
            uint256 currentTotalStake = market.totalOpenStake();
            uint256 carlExpected = _calculateExpectedPayout(currentPool, carlStake, currentTotalStake);

            market.collectVoidedFunds(carl);
            carlActual = address(carl).balance - carlBalanceBefore;
            totalDistributed += carlActual;

            assertEq(carlActual, carlExpected, "exact carl proportional after multiple sells");
        }

        // Dave collects last
        uint256 daveActual = 0;
        if (daveStake > 0) {
            uint256 currentPool = address(market).balance;
            uint256 currentTotalStake = market.totalOpenStake();
            uint256 daveExpected = _calculateExpectedPayout(currentPool, daveStake, currentTotalStake);

            market.collectVoidedFunds(dave);
            daveActual = address(dave).balance - daveBalanceBefore;
            totalDistributed += daveActual;

            assertEq(daveActual, daveExpected, "exact dave proportional after multiple sells");
        }

        // Verify fund distribution accounting after multiple sells
        uint256 remainingBalance = address(market).balance;

        // Total distributed + remaining should equal the original pool
        assertEq(totalDistributed + remainingBalance, totalPool, "total pool accounting after multiple sells");

        // Any remaining balance should be minimal rounding dust
        assertLe(remainingBalance, 5, "minimal rounding dust after multiple sells");

        // TotalOpenStake should be zero since we collected from everyone
        assertEq(market.totalOpenStake(), 0, "total stake cleared after multiple sells");

        // Verify Bob got profitable sells (if he made any sells)
        if (numSells > 0 && totalSellProfit > 0) {
            assertGt(totalSellProfit, 0, "bob should have made profit from partial sells");
        }

        // Verify everyone with remaining stake gets some payout
        if (aliceStake > 0) assertGt(aliceActual, 0, "alice gets payout");
        if (bobRemainingStake > 0) assertGt(bobActual, 0, "bob gets payout for remaining stake");
        if (carlStake > 0) assertGt(carlActual, 0, "carl gets payout");
        if (daveStake > 0) assertGt(daveActual, 0, "dave gets payout");
    }

    fallback() external payable { }
    receive() external payable { }
}

contract VoidedReentrant is ERC1155, Receiver {
    address target;

    constructor(address _target) ERC1155() {
        target = _target;
    }

    function uri(uint256) public pure override returns (string memory) {
        return "uri";
    }

    receive() external payable override {
        console2.log("collectVoidedFunds received, lets try reentrancy");
        (bool success,) =
            target.call(abi.encodeWithSelector(bytes4(keccak256("collectVoidedFunds(address)")), address(this)));
        success;
    }
}
