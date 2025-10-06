// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc
import { ERC20 } from "solady/tokens/ERC20.sol";
// Config
import { OrderRouterTestBase } from "@test/config/OrderRouterTestBase.t.sol";
// Types
import { AllowanceTargetType } from "@src/types/TOnitMarketOrderRouter.sol";
// Interfaces
import { IOnitMarketOrderRouter } from "@src/interfaces/IOnitMarketOrderRouter.sol";
// Contract to test
import { OnitMarketOrderRouter } from "@src/order-manager/OnitMarketOrderRouter.v2.sol";

contract OnitMarketOrderRouterInitializeOrderRouterForMarketTest is OrderRouterTestBase {
    address DUMMY_MARKET = makeAddr("DUMMY_MARKET");

    function setUp() public {
        // Setup initial token balances
        tokenA.mint(alice, 1000 ether);
        tokenA.mint(bob, 1000 ether);
    }

    // ----------------------------------------------------------------
    // Tests for permit-based initialization
    // ----------------------------------------------------------------

    function test_initializeOrderRouterForMarket_withPermit_successful() public {
        // Test the original permit-based flow
        initializeOrderRouterForTestMarket(DUMMY_MARKET);

        (address marketAdmin, address marketToken) = orderRouter.marketDetails(DUMMY_MARKET);
        assertEq(marketAdmin, someMarketsTokenAdmin);
        assertEq(marketToken, tokenAAddress);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), 1 ether);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), 2 ether);
        assertEq(tokenA.allowance(someMarketsTokenAdmin, orderRouterAddress), BASE_TOTAL_AMOUNT);
        assertEq(tokenA.balanceOf(someMarketsTokenAdmin), 1000 ether - INITIAL_BACKING);
        assertEq(tokenA.balanceOf(DUMMY_MARKET), INITIAL_BACKING);
    }

    function test_initializeOrderRouterForMarket_withPermit_zeroAllowances() public {
        // Test permit flow with no allowances being set
        bytes memory orderRouterInitData = encodeOrderRouterInitData(
            tokenAAddress,
            someMarketsTokenAdmin,
            orderRouterAddress,
            INITIAL_BACKING,
            block.timestamp + 1 days,
            someMarketsTokenAdminPk
        );

        vm.prank(DUMMY_MARKET);
        orderRouter.initializeOrderRouterForMarket(
            tokenAAddress, someMarketsTokenAdmin, INITIAL_BACKING, orderRouterInitData
        );

        (address marketAdmin, address marketToken) = orderRouter.marketDetails(DUMMY_MARKET);
        assertEq(marketAdmin, someMarketsTokenAdmin);
        assertEq(marketToken, tokenAAddress);
        assertEq(tokenA.allowance(someMarketsTokenAdmin, orderRouterAddress), 0);
        assertEq(tokenA.balanceOf(DUMMY_MARKET), INITIAL_BACKING);
    }

    // ----------------------------------------------------------------
    // Tests for non-permit initialization
    // ----------------------------------------------------------------

    function test_initializeOrderRouterForMarket_nonPermit_withReservedAllowance() public {
        uint256 reserveAmount = 10 ether;
        uint256 initialBacking = 1 ether;

        // someMarketsTokenAdmin approves tokens to order router
        vm.prank(someMarketsTokenAdmin);
        tokenA.approve(orderRouterAddress, reserveAmount);

        // someMarketsTokenAdmin reserves allowance for deployment
        vm.prank(someMarketsTokenAdmin);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, reserveAmount);

        // Create init data without permit signature (all zeros)
        bytes memory orderRouterInitData = abi.encode(
            uint256(0), // deadline - not used
            uint8(0), // v - not used
            bytes32(0), // r - not used
            bytes32(0), // s - not used
            SPENDERS, // set allowances for spenders
            AMOUNTS // allowance amounts
        );

        uint256 someMarketsTokenAdminBalanceBefore = tokenA.balanceOf(someMarketsTokenAdmin);
        uint256 marketBalanceBefore = tokenA.balanceOf(DUMMY_MARKET);

        // Initialize market without permit - should use reserved allowance
        vm.prank(DUMMY_MARKET);
        orderRouter.initializeOrderRouterForMarket(
            tokenAAddress, someMarketsTokenAdmin, initialBacking, orderRouterInitData
        );

        // Verify reserved allowance was cleared
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, orderRouterAddress, DUMMY_MARKET), 0);

        // Verify market details were set
        (address marketAdmin, address marketToken) = orderRouter.marketDetails(DUMMY_MARKET);
        assertEq(marketAdmin, someMarketsTokenAdmin);
        assertEq(marketToken, tokenAAddress);

        // Verify allowances were set for spenders
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), AMOUNTS[0]);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), AMOUNTS[1]);

        // Verify token transfer occurred
        assertEq(tokenA.balanceOf(someMarketsTokenAdmin), someMarketsTokenAdminBalanceBefore - initialBacking);
        assertEq(tokenA.balanceOf(DUMMY_MARKET), marketBalanceBefore + initialBacking);
    }

    function test_initializeOrderRouterForMarket_nonPermit_emitsEvent() public {
        uint256 reserveAmount = 5 ether;
        uint256 initialBacking = 1 ether;

        vm.prank(someMarketsTokenAdmin);
        tokenA.approve(orderRouterAddress, reserveAmount);

        vm.prank(someMarketsTokenAdmin);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, reserveAmount);

        bytes memory orderRouterInitData =
            abi.encode(uint256(0), uint8(0), bytes32(0), bytes32(0), new address[](0), new uint256[](0));

        // Expect the AllowanceUpdated event for clearing the reserved allowance
        vm.expectEmit(true, true, true, true);
        emit IOnitMarketOrderRouter.AllowanceUpdated(
            someMarketsTokenAdmin, orderRouterAddress, DUMMY_MARKET, AllowanceTargetType.MARKET, 0
        );

        vm.prank(DUMMY_MARKET);
        orderRouter.initializeOrderRouterForMarket(
            tokenAAddress, someMarketsTokenAdmin, initialBacking, orderRouterInitData
        );
    }

    function test_initializeOrderRouterForMarket_nonPermit_withSpenderAllowances() public {
        uint256 reserveAmount = 20 ether;
        uint256 initialBacking = 1 ether;

        vm.prank(someMarketsTokenAdmin);
        tokenA.approve(orderRouterAddress, reserveAmount);

        vm.prank(someMarketsTokenAdmin);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, reserveAmount);

        // Set allowances for multiple spenders
        address[] memory spenders = new address[](3);
        spenders[0] = alice;
        spenders[1] = bob;
        spenders[2] = carl;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 2 ether;
        amounts[1] = 3 ether;
        amounts[2] = 4 ether;

        bytes memory orderRouterInitData = abi.encode(uint256(0), uint8(0), bytes32(0), bytes32(0), spenders, amounts);

        vm.prank(DUMMY_MARKET);
        orderRouter.initializeOrderRouterForMarket(
            tokenAAddress, someMarketsTokenAdmin, initialBacking, orderRouterInitData
        );

        // Verify all spender allowances were set
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), amounts[0]);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), amounts[1]);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, carl, DUMMY_MARKET), amounts[2]);
    }

    // ----------------------------------------------------------------
    // Error cases for non-permit flow
    // ----------------------------------------------------------------

    function test_initializeOrderRouterForMarket_nonPermit_reverts_noReservedAllowance() public {
        // Try to initialize without reserving allowance first
        bytes memory orderRouterInitData =
            abi.encode(uint256(0), uint8(0), bytes32(0), bytes32(0), new address[](0), new uint256[](0));

        // Should revert to permit flow and fail because no valid signature
        vm.prank(DUMMY_MARKET);
        vm.expectRevert(ERC20.PermitExpired.selector);
        orderRouter.initializeOrderRouterForMarket(
            tokenAAddress, someMarketsTokenAdmin, INITIAL_BACKING, orderRouterInitData
        );
    }

    function test_initializeOrderRouterForMarket_nonPermit_reverts_insufficientAllowance() public {
        uint256 reserveAmount = 1 ether;
        uint256 initialBacking = 2 ether; // More than reserved

        vm.prank(someMarketsTokenAdmin);
        tokenA.approve(orderRouterAddress, reserveAmount);

        vm.prank(someMarketsTokenAdmin);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, reserveAmount);

        bytes memory orderRouterInitData =
            abi.encode(uint256(0), uint8(0), bytes32(0), bytes32(0), new address[](0), new uint256[](0));

        // Should revert because insufficient allowance for transfer
        vm.prank(DUMMY_MARKET);
        vm.expectRevert(); // Will revert on transferFrom due to insufficient allowance
        orderRouter.initializeOrderRouterForMarket(
            tokenAAddress, someMarketsTokenAdmin, initialBacking, orderRouterInitData
        );
    }

    function test_initializeOrderRouterForMarket_reverts_negativeAllowanceChange() public {
        // This test ensures the original validation still works
        // Create allowances that would result in negative change
        address[] memory spenders = new address[](1);
        spenders[0] = alice;

        // Set a very large amount that would cause overflow when cast to int256
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = uint256(type(int256).max) + 1;

        bytes memory orderRouterInitData =
            abi.encode(block.timestamp + 1 days, uint8(27), bytes32(0), bytes32(0), spenders, amounts);

        vm.prank(DUMMY_MARKET);
        vm.expectRevert(IOnitMarketOrderRouter.AmountTooLarge.selector);
        orderRouter.initializeOrderRouterForMarket(
            tokenAAddress, someMarketsTokenAdmin, INITIAL_BACKING, orderRouterInitData
        );
    }

    // ----------------------------------------------------------------
    // Edge cases and integration tests
    // ----------------------------------------------------------------

    function test_initializeOrderRouterForMarket_nonPermit_partialReservedAllowance() public {
        uint256 reserveAmount = 5 ether;
        uint256 initialBacking = 2 ether;
        uint256 spenderAllowance = 2 ether;

        // Total needed = initialBacking + spenderAllowance = 4 ether
        // Reserved = 5 ether (sufficient)

        vm.prank(someMarketsTokenAdmin);
        tokenA.approve(orderRouterAddress, reserveAmount);

        vm.prank(someMarketsTokenAdmin);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, reserveAmount);

        address[] memory spenders = new address[](1);
        spenders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = spenderAllowance;

        bytes memory orderRouterInitData = abi.encode(uint256(0), uint8(0), bytes32(0), bytes32(0), spenders, amounts);

        vm.prank(DUMMY_MARKET);
        orderRouter.initializeOrderRouterForMarket(
            tokenAAddress, someMarketsTokenAdmin, initialBacking, orderRouterInitData
        );

        // Should succeed and clear reserved allowance
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, orderRouterAddress, DUMMY_MARKET), 0);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), spenderAllowance);
    }

    function test_initializeOrderRouterForMarket_mixedFlow_permitWithExistingReserved() public {
        uint256 reserveAmount = 3 ether;
        uint256 initialBacking = 1 ether;

        // First reserve some allowance
        vm.prank(someMarketsTokenAdmin);
        tokenA.approve(orderRouterAddress, reserveAmount);

        vm.prank(someMarketsTokenAdmin);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, reserveAmount);

        // Then also provide a valid permit signature (should use reserved allowance instead)
        bytes memory orderRouterInitData = encodeOrderRouterInitData(
            tokenAAddress,
            someMarketsTokenAdmin,
            orderRouterAddress,
            SPENDERS,
            AMOUNTS,
            initialBacking,
            block.timestamp + 1 days,
            someMarketsTokenAdminPk
        );

        vm.prank(DUMMY_MARKET);
        orderRouter.initializeOrderRouterForMarket(
            tokenAAddress, someMarketsTokenAdmin, initialBacking, orderRouterInitData
        );

        // Should use non-permit flow and clear reserved allowance
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, orderRouterAddress, DUMMY_MARKET), 0);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), AMOUNTS[0]);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), AMOUNTS[1]);
    }

    function testFuzz_initializeOrderRouterForMarket_nonPermit(
        uint128 reserveAmount,
        uint64 initialBacking,
        uint32 spenderAllowance
    )
        public
    {
        // Bound inputs to reasonable values
        reserveAmount = uint128(bound(reserveAmount, 1 ether, 1000 ether));
        initialBacking = uint64(bound(initialBacking, 0.01 ether, 10 ether));
        spenderAllowance = uint32(bound(spenderAllowance, 0, 10 ether));

        // Ensure we have enough reserved for the operation
        uint256 totalNeeded = uint256(initialBacking) + uint256(spenderAllowance);
        vm.assume(reserveAmount >= totalNeeded);

        // Setup
        vm.prank(someMarketsTokenAdmin);
        tokenA.approve(orderRouterAddress, reserveAmount);

        vm.prank(someMarketsTokenAdmin);
        orderRouter.reserveAllowanceForDeployment(DUMMY_MARKET, reserveAmount);

        address[] memory spenders = new address[](1);
        spenders[0] = alice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = spenderAllowance;

        bytes memory orderRouterInitData = abi.encode(uint256(0), uint8(0), bytes32(0), bytes32(0), spenders, amounts);

        uint256 balanceBefore = tokenA.balanceOf(someMarketsTokenAdmin);

        vm.prank(DUMMY_MARKET);
        orderRouter.initializeOrderRouterForMarket(
            tokenAAddress, someMarketsTokenAdmin, initialBacking, orderRouterInitData
        );

        // Verify state
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, orderRouterAddress, DUMMY_MARKET), 0);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), spenderAllowance);
        assertEq(tokenA.balanceOf(someMarketsTokenAdmin), balanceBefore - initialBacking);
        assertEq(tokenA.balanceOf(DUMMY_MARKET), initialBacking);
    }
}
