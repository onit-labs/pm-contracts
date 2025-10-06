// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Config
import { OrderRouterTestBase } from "@test/config/OrderRouterTestBase.t.sol";
// Types
import { AllowanceTargetType } from "@src/types/TOnitMarketOrderRouter.sol";
// Interfaces
import { IOnitMarketOrderRouter } from "@src/interfaces/IOnitMarketOrderRouter.sol";
// Contract to test
import { OnitMarketOrderRouter } from "@src/order-manager/OnitMarketOrderRouter.v2.sol";

contract OnitMarketOrderRouterReserveAllowanceForDeploymentTest is OrderRouterTestBase {
    address DUMMY_MARKET = makeAddr("DUMMY_MARKET");

    function setUp() public {
        // Setup initial token balances
        tokenA.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);
        tokenA.mint(someMarketsTokenAdmin, 1000 ether);
    }

    // ----------------------------------------------------------------
    // reserveAllowanceForDeployment tests
    // ----------------------------------------------------------------

    function test_reserveAllowanceForDeployment_successful() public {
        uint256 reserveAmount = 10 ether;

        // Initially no allowance reserved
        assertEq(orderRouter.allowances(alice, orderRouterAddress, DUMMY_MARKET), 0);

        // Alice reserves allowance for deployment
        vm.prank(alice);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, reserveAmount);

        // Verify allowance is reserved
        assertEq(orderRouter.allowances(alice, orderRouterAddress, DUMMY_MARKET), reserveAmount);
    }

    function test_reserveAllowanceForDeployment_emitsEvent() public {
        uint256 reserveAmount = 5 ether;

        // Expect the AllowanceUpdated event
        vm.expectEmit(true, true, true, true);
        emit IOnitMarketOrderRouter.AllowanceUpdated(
            alice, orderRouterAddress, DUMMY_MARKET, AllowanceTargetType.MARKET, reserveAmount
        );

        vm.prank(alice);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, reserveAmount);
    }

    function test_reserveAllowanceForDeployment_overwritesExisting() public {
        uint256 initialAmount = 5 ether;
        uint256 newAmount = 15 ether;

        // Reserve initial amount
        vm.prank(alice);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, initialAmount);
        assertEq(orderRouter.allowances(alice, orderRouterAddress, DUMMY_MARKET), initialAmount);

        // Overwrite with new amount
        vm.prank(alice);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, newAmount);
        assertEq(orderRouter.allowances(alice, orderRouterAddress, DUMMY_MARKET), newAmount);
    }

    function test_reserveAllowanceForDeployment_zeroAmount() public {
        uint256 initialAmount = 10 ether;

        // Reserve some amount first
        vm.prank(alice);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, initialAmount);
        assertEq(orderRouter.allowances(alice, orderRouterAddress, DUMMY_MARKET), initialAmount);

        // Set to zero
        vm.prank(alice);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, 0);
        assertEq(orderRouter.allowances(alice, orderRouterAddress, DUMMY_MARKET), 0);
    }

    function test_reserveAllowanceForDeployment_differentUsers() public {
        uint256 aliceAmount = 8 ether;
        uint256 bobAmount = 12 ether;

        // Alice reserves allowance
        vm.prank(alice);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, aliceAmount);

        // Bob reserves allowance for same market
        vm.prank(bob);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, bobAmount);

        // Both should have their respective allowances
        assertEq(orderRouter.allowances(alice, orderRouterAddress, DUMMY_MARKET), aliceAmount);
        assertEq(orderRouter.allowances(bob, orderRouterAddress, DUMMY_MARKET), bobAmount);
    }

    function test_reserveAllowanceForDeployment_differentMarkets() public {
        address MARKET_A = makeAddr("MARKET_A");
        address MARKET_B = makeAddr("MARKET_B");
        uint256 amountA = 6 ether;
        uint256 amountB = 9 ether;

        // Alice reserves for different markets
        vm.prank(alice);
        orderRouter.reserveAllowanceForDeployment(MARKET_A, amountA);

        vm.prank(alice);
        orderRouter.reserveAllowanceForDeployment(MARKET_B, amountB);

        // Both reservations should exist independently
        assertEq(orderRouter.allowances(alice, orderRouterAddress, MARKET_A), amountA);
        assertEq(orderRouter.allowances(alice, orderRouterAddress, MARKET_B), amountB);
    }

    function testFuzz_reserveAllowanceForDeployment(uint256 amount) public {
        // Bound the amount to reasonable values
        amount = bound(amount, 0, type(uint128).max);

        vm.prank(alice);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, amount);

        assertEq(orderRouter.allowances(alice, orderRouterAddress, DUMMY_MARKET), amount);
    }

    // ----------------------------------------------------------------
    // Integration test with market initialization
    // ----------------------------------------------------------------

    function test_reserveAllowanceForDeployment_integrationWithInit() public {
        uint256 reserveAmount = 20 ether;
        uint256 initialBacking = 1 ether;

        // Alice approves tokens to order router first
        vm.prank(alice);
        tokenA.approve(orderRouterAddress, reserveAmount);

        // Alice reserves allowance for deployment
        vm.prank(alice);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, reserveAmount);

        // Verify reserved allowance exists
        assertEq(orderRouter.allowances(alice, orderRouterAddress, DUMMY_MARKET), reserveAmount);

        // Create init data without permit signature (empty signature)
        bytes memory orderRouterInitData = abi.encode(
            uint256(0), // deadline - not used
            uint8(0), // v - not used
            bytes32(0), // r - not used
            bytes32(0), // s - not used
            new address[](0), // no spenders
            new uint256[](0) // no amounts
        );

        uint256 aliceBalanceBefore = tokenA.balanceOf(alice);
        uint256 marketBalanceBefore = tokenA.balanceOf(DUMMY_MARKET);

        // Initialize market without permit - should use reserved allowance
        vm.prank(DUMMY_MARKET);
        orderRouter.initializeOrderRouterForMarket(tokenAAddress, alice, initialBacking, orderRouterInitData);

        // Verify reserved allowance was cleared
        assertEq(orderRouter.allowances(alice, orderRouterAddress, DUMMY_MARKET), 0);

        // Verify market details were set
        (address marketAdmin, address marketToken) = orderRouter.marketDetails(DUMMY_MARKET);
        assertEq(marketAdmin, alice);
        assertEq(marketToken, tokenAAddress);

        // Verify token transfer occurred
        assertEq(tokenA.balanceOf(alice), aliceBalanceBefore - initialBacking);
        assertEq(tokenA.balanceOf(DUMMY_MARKET), marketBalanceBefore + initialBacking);
    }

    function test_reserveAllowanceForDeployment_reverts_InsufficientAllowance() public {
        uint256 reserveAmount = 1 ether;
        uint256 initialBacking = 2 ether; // More than reserved

        // Alice approves and reserves insufficient amount
        vm.prank(alice);
        tokenA.approve(orderRouterAddress, reserveAmount);

        vm.prank(alice);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, reserveAmount);

        // Create init data without permit signature
        bytes memory orderRouterInitData =
            abi.encode(uint256(0), uint8(0), bytes32(0), bytes32(0), new address[](0), new uint256[](0));

        // Should revert because insufficient allowance for transfer
        vm.prank(DUMMY_MARKET);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOnitMarketOrderRouter.InsufficientAllowance.selector, initialBacking - reserveAmount
            )
        );
        orderRouter.initializeOrderRouterForMarket(tokenAAddress, alice, initialBacking, orderRouterInitData);
    }
}
