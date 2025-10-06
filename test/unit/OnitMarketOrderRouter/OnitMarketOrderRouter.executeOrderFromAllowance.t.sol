// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Config
import { OnitIODPMTestBase } from "@test/config/OnitIODPMTestBase.t.sol";
// Types
import { BetStatus } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
import { AllowanceTargetType } from "@src/types/TOnitMarketOrderRouter.sol";
// Interfaces
import { IOnitMarketOrderRouter } from "@src/interfaces/IOnitMarketOrderRouter.sol";
// Contract to test
import { OnitMarketOrderRouter } from "@src/order-manager/OnitMarketOrderRouter.v2.sol";
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";

contract OnitMarketOrderRouterExecuteOrderFromAllowanceTest is OnitIODPMTestBase {
    uint256 FUTURE_SPEND_DEADLINE = block.timestamp + 1 days;
    uint256 betAmount = 1 ether;

    function setUp() public {
        tokenA.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);

        market = newMarketWithDefaultConfigWithToken();
        marketAddress = address(market);

        vm.prank(marketAddress);
        initializeOrderRouterForTestMarket(marketAddress);
    }

    // ----------------------------------------------------------------
    // executeOrderFromAllowance tests
    // ----------------------------------------------------------------

    function test_executeOrderFromAllowance_reverts_invalidSpender() public {
        vm.prank(address(0x123)); // Random address
        vm.expectRevert(IOnitMarketOrderRouter.InvalidAllowanceSpender.selector);
        orderRouter.executeOrderFromAllowance(bob, marketAddress, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_executeOrderFromAllowance_reverts_insufficientAllowance() public {
        // Try to execute with insufficient allowance
        vm.prank(carl);
        vm.expectRevert(abi.encodeWithSelector(IOnitMarketOrderRouter.InsufficientAllowance.selector, betAmount));
        orderRouter.executeOrderFromAllowance(carl, marketAddress, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES);
    }

    function test_executeOrderFromAllowance_usingMarketAllowance() public {
        // Check initial allowances (market allowances were set in setUp by initializeOrderRouterForTestMarket)
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, marketAddress), AMOUNTS[0]);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, tokenAAddress), 0);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, marketAddress), AMOUNTS[1]);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, tokenAAddress), 0);

        // Calculate actual bet amount
        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        // Record initial balances
        uint256 initialMarketBalance = tokenA.balanceOf(marketAddress);
        uint256 initialsomeMarketsTokenAdminBalance = tokenA.balanceOf(someMarketsTokenAdmin);
        uint256 initialBobBalance = tokenA.balanceOf(bob);
        uint256 initialMarketAllowance = orderRouter.allowances(someMarketsTokenAdmin, bob, marketAddress);

        // Execute order
        vm.prank(bob);
        orderRouter.executeOrderFromAllowance(bob, marketAddress, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES);

        // Verify balances
        assertEq(tokenA.balanceOf(marketAddress), initialMarketBalance + betAmount);
        assertEq(tokenA.balanceOf(someMarketsTokenAdmin), initialsomeMarketsTokenAdminBalance - betAmount);
        assertEq(tokenA.balanceOf(bob), initialBobBalance);
        // Verify allowance was reduced
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, marketAddress), initialMarketAllowance - betAmount);
        // Verify shares were minted
        (uint256 tradersStake, uint256 nftId, BetStatus status) = market.tradersStake(bob);
        assertEq(tradersStake, betAmount);
        assertEq(nftId, 1);
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
    }

    function test_executeOrderFromAllowance_usingTokenAllowance() public {
        // Set up a token allowance for carl from the project owner
        uint256 tokenAllowance = 2 ether;
        address[] memory spenders = new address[](1);
        spenders[0] = carl;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = tokenAllowance;

        uint256 totalAllowance = tokenAllowance + AMOUNTS[0] + AMOUNTS[1];

        // Generate permit signature for token approval
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            tokenAAddress,
            someMarketsTokenAdmin,
            orderRouterAddress,
            totalAllowance,
            FUTURE_SPEND_DEADLINE,
            someMarketsTokenAdminPk
        );

        // Set allowance for token
        orderRouter.setAllowances(
            AllowanceTargetType.TOKEN, marketAddress, FUTURE_SPEND_DEADLINE, v, r, s, spenders, amounts
        );

        // Calculate actual bet amount
        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        // Record initial balances
        uint256 initialMarketBalance = tokenA.balanceOf(marketAddress);
        uint256 initialcarlBalance = tokenA.balanceOf(carl);
        uint256 initialsomeMarketsTokenAdminBalance = tokenA.balanceOf(someMarketsTokenAdmin);
        uint256 initialTokenAllowance = orderRouter.allowances(someMarketsTokenAdmin, carl, tokenAAddress);
        uint256 initialMarketAllowance = orderRouter.allowances(someMarketsTokenAdmin, carl, marketAddress);

        assertEq(initialMarketAllowance, 0);
        assertEq(initialTokenAllowance, tokenAllowance);

        // Execute order
        vm.prank(carl);
        orderRouter.executeOrderFromAllowance(carl, marketAddress, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES);

        // Verify balances
        assertEq(tokenA.balanceOf(marketAddress), initialMarketBalance + betAmount);
        assertEq(tokenA.balanceOf(carl), initialcarlBalance);
        assertEq(tokenA.balanceOf(someMarketsTokenAdmin), initialsomeMarketsTokenAdminBalance - betAmount);
        // Verify allowance was reduced
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, carl, tokenAAddress), initialTokenAllowance - betAmount);
        // Verify shares were minted
        (uint256 tradersStake, uint256 nftId, BetStatus status) = market.tradersStake(carl);
        assertEq(tradersStake, betAmount);
        assertEq(nftId, 1);
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
    }

    function test_executeOrderFromAllowance_usingBothAllowances() public {
        // Calculate actual bet amount (we'll make a bet that is larger than the market allowance, so we need to use the
        // token allowance too)
        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        uint256 initialAllowance = AMOUNTS[0] + AMOUNTS[1];

        // Set up market allowance
        uint256 marketAllowance = betAmount / 2;
        address[] memory spenders = new address[](1);
        spenders[0] = carl;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = marketAllowance;

        // Generate permit signature for market allowance
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            tokenAAddress,
            someMarketsTokenAdmin,
            orderRouterAddress,
            marketAllowance + initialAllowance,
            FUTURE_SPEND_DEADLINE,
            someMarketsTokenAdminPk
        );
        // Set market allowance
        orderRouter.setAllowances(
            AllowanceTargetType.MARKET, marketAddress, FUTURE_SPEND_DEADLINE, v, r, s, spenders, amounts
        );

        uint256 afterMarketAllowance = initialAllowance + marketAllowance;

        uint256 tokenAllowance = betAmount / 2;
        // Generate permit signature for token allowance
        (v, r, s) = getPermitSignature(
            tokenAAddress,
            someMarketsTokenAdmin,
            orderRouterAddress,
            tokenAllowance + afterMarketAllowance,
            FUTURE_SPEND_DEADLINE,
            someMarketsTokenAdminPk
        );
        // Set token allowance
        orderRouter.setAllowances(
            AllowanceTargetType.TOKEN, marketAddress, FUTURE_SPEND_DEADLINE, v, r, s, spenders, amounts
        );

        // Record initial balances
        uint256 initialMarketBalance = tokenA.balanceOf(marketAddress);
        uint256 initialsomeMarketsTokenAdminBalance = tokenA.balanceOf(someMarketsTokenAdmin);
        uint256 initialcarlBalance = tokenA.balanceOf(carl);
        uint256 initialMarketAllowance = orderRouter.allowances(someMarketsTokenAdmin, carl, marketAddress);
        uint256 initialTokenAllowance = orderRouter.allowances(someMarketsTokenAdmin, carl, tokenAAddress);

        assertEq(initialMarketAllowance, marketAllowance);
        assertEq(initialTokenAllowance, tokenAllowance);

        // Execute order
        vm.prank(carl);
        orderRouter.executeOrderFromAllowance(carl, marketAddress, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES);

        // Verify balances
        assertEq(tokenA.balanceOf(marketAddress), initialMarketBalance + betAmount);
        assertEq(tokenA.balanceOf(carl), initialcarlBalance);
        assertEq(tokenA.balanceOf(someMarketsTokenAdmin), initialsomeMarketsTokenAdminBalance - betAmount);

        // Verify allowances were reduced correctly
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, carl, marketAddress), 0); // Market allowance should be
            // fully
            // used
        assertEq(
            orderRouter.allowances(someMarketsTokenAdmin, carl, tokenAAddress),
            initialTokenAllowance - (betAmount - marketAllowance)
        ); // Token allowance should be reduced by remaining amount

        // Verify shares were minted
        (uint256 tradersStake, uint256 nftId, BetStatus status) = market.tradersStake(carl);
        assertEq(tradersStake, betAmount);
        assertEq(nftId, 1);
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
    }

    function test_executeOrderFromAllowance_asMarketAdmin() public {
        // Calculate actual bet amount
        (int256 int256BetAmount,) = market.calculateCostOfTrade(DUMMY_BUCKET_IDS, DUMMY_SHARES);
        betAmount = uint256(int256BetAmount);

        // Record initial balances
        uint256 initialMarketBalance = tokenA.balanceOf(marketAddress);
        uint256 initialsomeMarketsTokenAdminBalance = tokenA.balanceOf(someMarketsTokenAdmin);
        uint256 initialBobBalance = tokenA.balanceOf(bob);
        uint256 initialMarketAllowance = orderRouter.allowances(someMarketsTokenAdmin, bob, marketAddress);

        // Execute order as market admin
        vm.prank(someMarketsTokenAdmin);
        orderRouter.executeOrderFromAllowance(bob, marketAddress, betAmount, DUMMY_BUCKET_IDS, DUMMY_SHARES);

        // Verify balances
        assertEq(tokenA.balanceOf(marketAddress), initialMarketBalance + betAmount);
        assertEq(tokenA.balanceOf(someMarketsTokenAdmin), initialsomeMarketsTokenAdminBalance - betAmount);
        assertEq(tokenA.balanceOf(bob), initialBobBalance);
        // Verify allowance was reduced
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, marketAddress), initialMarketAllowance - betAmount);
        // Verify shares were minted
        (uint256 tradersStake, uint256 nftId, BetStatus status) = market.tradersStake(bob);
        assertEq(tradersStake, betAmount);
        assertEq(nftId, 1);
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
    }
}
