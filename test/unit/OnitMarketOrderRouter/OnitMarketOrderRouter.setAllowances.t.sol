// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc
import { ERC20 } from "solady/tokens/ERC20.sol";
// Config
import { OrderRouterTestBase, OnitMarketOrderRouterHarness } from "@test/config/OrderRouterTestBase.t.sol";
// Types
import { AllowanceTargetType } from "@src/types/TOnitMarketOrderRouter.sol";
// Interfaces
import { IOnitMarketOrderRouter } from "@src/interfaces/IOnitMarketOrderRouter.sol";
// Contract to test
import { OnitMarketOrderRouter } from "@src/order-manager/OnitMarketOrderRouter.v2.sol";

contract OnitMarketOrderRouterSetAllowancesTest is OrderRouterTestBase {
    // For testing internal functions
    OnitMarketOrderRouterHarness orderRouterHarness = new OnitMarketOrderRouterHarness();

    uint256 FUTURE_SPEND_DEADLINE = block.timestamp + 1 days;

    address DUMMY_MARKET = makeAddr("DUMMY_MARKET");

    AllowanceTargetType public constant MARKET_ALLOWANCE = AllowanceTargetType.MARKET;

    function test_initializeorderRouterForMarket() public {
        // Verify initial balances
        assertEq(tokenA.balanceOf(someMarketsTokenAdmin), 1000 ether, "Initial someMarketsTokenAdmin balance incorrect");
        assertEq(tokenA.balanceOf(DUMMY_MARKET), 0, "Initial test contract balance incorrect");

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

    // ----------------------------------------------------------------
    // setAllowances internal tests using harness
    // ----------------------------------------------------------------

    function test_setAllowances_internal_reverts_ArrayLengthMismatch() public {
        // Setup mismatched arrays
        address[] memory spendersWrong = new address[](2);
        spendersWrong[0] = alice;
        spendersWrong[1] = bob;

        uint256[] memory amountsWrong = new uint256[](1);
        amountsWrong[0] = 1 ether;

        // Expect revert due to array length mismatch
        vm.expectRevert(IOnitMarketOrderRouter.ArrayLengthMismatch.selector);
        orderRouterHarness.setAllowances({
            allowanceTargetType: MARKET_ALLOWANCE,
            allower: someMarketsTokenAdmin,
            target: DUMMY_MARKET,
            spenders: spendersWrong,
            amounts: amountsWrong
        });
    }

    function test_setAllowances_internal_reverts_AmountTooLarge() public {
        // Setup excessive amount
        uint256[] memory amountsExcessive = new uint256[](2);
        amountsExcessive[0] = type(uint256).max;
        amountsExcessive[1] = 1 ether;

        vm.expectRevert(IOnitMarketOrderRouter.AmountTooLarge.selector);
        orderRouterHarness.setAllowances({
            allowanceTargetType: MARKET_ALLOWANCE,
            allower: someMarketsTokenAdmin,
            target: DUMMY_MARKET,
            spenders: SPENDERS,
            amounts: amountsExcessive
        });
    }

    function test_setAllowances_internal() public {
        // Set allowances
        orderRouterHarness.setAllowances({
            allowanceTargetType: MARKET_ALLOWANCE,
            allower: someMarketsTokenAdmin,
            target: DUMMY_MARKET,
            spenders: SPENDERS,
            amounts: AMOUNTS
        });

        // Verify allowances are set correctly
        assertEq(orderRouterHarness.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), 1 ether);
        assertEq(orderRouterHarness.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), 2 ether);
    }

    function testFuzz_setAllowances_internal(uint8 numSpenders, uint64 amountBase) public {
        // Create arrays for SPENDERS and AMOUNTS
        address[] memory spendersFuzz = new address[](numSpenders);
        uint256[] memory amountsFuzz = new uint256[](numSpenders);

        // Setup the SPENDERS and AMOUNTS dynamically using a loop
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < numSpenders; i++) {
            // Create unique addresses for each spender
            spendersFuzz[i] = address(uint160(uint256(keccak256(abi.encode("spender", i)))));

            // Set AMOUNTS with some variability
            uint256 amount = uint256(amountBase) * (i + 1);
            amountsFuzz[i] = amount;
            totalAmount += amount;
        }

        // Set allowances
        orderRouterHarness.setAllowances({
            allowanceTargetType: MARKET_ALLOWANCE,
            allower: someMarketsTokenAdmin,
            target: DUMMY_MARKET,
            spenders: spendersFuzz,
            amounts: amountsFuzz
        });

        // Verify allowances are set correctly
        for (uint256 i = 0; i < numSpenders; i++) {
            assertEq(
                orderRouterHarness.allowances(someMarketsTokenAdmin, spendersFuzz[i], DUMMY_MARKET), amountsFuzz[i]
            );
        }
    }

    function test_setAllowances_internal_updatesExistingAllowances() public {
        test_initializeorderRouterForMarket();

        // Verify initial allowances are 0
        assertEq(orderRouterHarness.allowances(someMarketsTokenAdmin, SPENDERS[0], DUMMY_MARKET), 0);
        assertEq(orderRouterHarness.allowances(someMarketsTokenAdmin, SPENDERS[1], DUMMY_MARKET), 0);

        // Set allowances for first time
        int256 totalAmount = orderRouterHarness.setAllowances({
            allowanceTargetType: MARKET_ALLOWANCE,
            allower: someMarketsTokenAdmin,
            target: DUMMY_MARKET,
            spenders: SPENDERS,
            amounts: AMOUNTS
        });

        // Verify first allowances
        assertEq(orderRouterHarness.allowances(someMarketsTokenAdmin, SPENDERS[0], DUMMY_MARKET), AMOUNTS[0]);
        assertEq(orderRouterHarness.allowances(someMarketsTokenAdmin, SPENDERS[1], DUMMY_MARKET), AMOUNTS[1]);

        AMOUNTS[0] = 2 * AMOUNTS[0];
        AMOUNTS[1] = 2 * AMOUNTS[1];

        // Set allowances for second time
        int256 totalAmount2 = orderRouterHarness.setAllowances({
            allowanceTargetType: MARKET_ALLOWANCE,
            allower: someMarketsTokenAdmin,
            target: DUMMY_MARKET,
            spenders: SPENDERS,
            amounts: AMOUNTS
        });

        // Verify second allowances
        assertEq(orderRouterHarness.allowances(someMarketsTokenAdmin, SPENDERS[0], DUMMY_MARKET), AMOUNTS[0]);
        assertEq(orderRouterHarness.allowances(someMarketsTokenAdmin, SPENDERS[1], DUMMY_MARKET), AMOUNTS[1]);

        // Verify total amount is correct
        assertEq(uint256(totalAmount), BASE_TOTAL_AMOUNT);
        // Since we added the same amount twice, the total amount should be the same
        assertEq(uint256(totalAmount2), BASE_TOTAL_AMOUNT);
    }

    // ----------------------------------------------------------------
    // setAllowances tests
    // ----------------------------------------------------------------

    function test_setAllowances_reverts_notFromAdmin() public {
        initializeOrderRouterForTestMarket(DUMMY_MARKET);

        // Alice tried to add some allowances
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            tokenAAddress,
            alice,
            orderRouterAddress,
            BASE_TOTAL_AMOUNT,
            block.timestamp + 1 days,
            someMarketsTokenAdminPk
        );

        vm.expectRevert();
        orderRouter.setAllowances({
            allowanceTargetType: AllowanceTargetType.MARKET,
            market: DUMMY_MARKET,
            spendDeadline: block.timestamp + 1 days,
            v: v,
            r: r,
            s: s,
            spenders: SPENDERS,
            amounts: AMOUNTS
        });
    }

    function test_setAllowances_increaseAllowances() public {
        initializeOrderRouterForTestMarket(DUMMY_MARKET);

        // Initial state check
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), 1 ether);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), 2 ether);

        // New allowances to set
        address[] memory spenders = new address[](2);
        spenders[0] = alice;
        spenders[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 3 ether;
        amounts[1] = 4 ether;

        uint256 totalAmount = 7 ether; // 3 + 4
        uint256 deadline = block.timestamp + 1 days;

        // Generate signature
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature({
            tokenAddress: tokenAAddress,
            owner: someMarketsTokenAdmin,
            spender: orderRouterAddress,
            value: totalAmount,
            deadline: deadline,
            privateKey: someMarketsTokenAdminPk
        });

        // Call external setAllowances
        orderRouter.setAllowances({
            allowanceTargetType: AllowanceTargetType.MARKET,
            market: DUMMY_MARKET,
            spendDeadline: deadline,
            v: v,
            r: r,
            s: s,
            spenders: spenders,
            amounts: amounts
        });
        // Verify allowances are set correctly
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), 3 ether);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), 4 ether);

        // Verify token allowance is set correctly
        assertEq(tokenA.allowance(someMarketsTokenAdmin, orderRouterAddress), totalAmount);
    }

    function test_setAllowances_decreaseAllowances() public {
        initializeOrderRouterForTestMarket(DUMMY_MARKET);

        // Initial allowances from initialization
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), AMOUNTS[0]);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), AMOUNTS[1]);

        // Setup new amounts
        uint256[] memory newAmounts = new uint256[](2);
        newAmounts[0] = AMOUNTS[0] - 1 ether;
        newAmounts[1] = AMOUNTS[1] - 1 ether;

        uint256 totalDelta = 2 ether; // alice 1 -> 0, bob 2 -> 1
        uint256 expectedNewTotal = BASE_TOTAL_AMOUNT - totalDelta; // Original + new delta
        uint256 deadline = block.timestamp + 1 days;

        // Generate signature for the delta amount
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            tokenAAddress,
            someMarketsTokenAdmin,
            orderRouterAddress,
            expectedNewTotal,
            deadline,
            someMarketsTokenAdminPk
        );

        // Set new allowances
        orderRouter.setAllowances({
            allowanceTargetType: AllowanceTargetType.MARKET,
            market: DUMMY_MARKET,
            spendDeadline: deadline,
            v: v,
            r: r,
            s: s,
            spenders: SPENDERS,
            amounts: newAmounts
        });

        // Verify allowances are updated correctly
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), newAmounts[0]);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), newAmounts[1]);
        assertEq(tokenA.allowance(someMarketsTokenAdmin, orderRouterAddress), expectedNewTotal);
    }

    function test_setAllowances_increaseAndDecreaseAllowances() public {
        initializeOrderRouterForTestMarket(DUMMY_MARKET);

        // Initial allowances
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), AMOUNTS[0]);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), AMOUNTS[1]);

        // Mixed changes: increase one, decrease one, add a new one
        address[] memory spenders = new address[](3);
        spenders[0] = alice;
        spenders[1] = bob;
        spenders[2] = carl; // New spender

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = AMOUNTS[0] + 1 ether; // increase from 1 ether (+1)
        amounts[1] = AMOUNTS[1] - 1 ether; // decrease from 2 ether (-1)
        amounts[2] = 3 ether; // new allowance (+3)

        uint256 totalDelta = 3 ether; // +1 + -1 + 3 = +3 ether
        uint256 expectedNewTotal = BASE_TOTAL_AMOUNT + totalDelta;
        uint256 deadline = block.timestamp + 1 days;

        // Generate signature
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            tokenAAddress,
            someMarketsTokenAdmin,
            orderRouterAddress,
            expectedNewTotal,
            deadline,
            someMarketsTokenAdminPk
        );

        // Set mixed changed allowances
        vm.prank(someMarketsTokenAdmin);
        orderRouter.setAllowances({
            allowanceTargetType: AllowanceTargetType.MARKET,
            market: DUMMY_MARKET,
            spendDeadline: deadline,
            v: v,
            r: r,
            s: s,
            spenders: spenders,
            amounts: amounts
        });
        // Verify allowances are set correctly
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), AMOUNTS[0] + 1 ether);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), AMOUNTS[1] - 1 ether);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, carl, DUMMY_MARKET), 3 ether);

        // Token allowance should be updated
        assertEq(tokenA.allowance(someMarketsTokenAdmin, orderRouterAddress), expectedNewTotal);
    }

    function test_setAllowances_tokenSpecific() public {
        initializeOrderRouterForTestMarket(DUMMY_MARKET);

        // Setup spenders and amounts
        address[] memory spenders = new address[](2);
        spenders[0] = alice;
        spenders[1] = bob;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 3 ether;
        amounts[1] = 4 ether;

        uint256 totalAmount = 7 ether;
        uint256 deadline = block.timestamp + 1 days;

        // We need to approve the total amount the order router needs, that inclues any existing allowance the owner has
        uint256 approvalAmount = totalAmount + ERC20(tokenAAddress).allowance(someMarketsTokenAdmin, orderRouterAddress);

        // Generate signature
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature({
            tokenAddress: tokenAAddress,
            owner: someMarketsTokenAdmin,
            spender: orderRouterAddress,
            value: approvalAmount,
            deadline: deadline,
            privateKey: someMarketsTokenAdminPk
        });

        // Call setAllowances with TOKEN target type
        vm.prank(someMarketsTokenAdmin);
        orderRouter.setAllowances({
            allowanceTargetType: AllowanceTargetType.TOKEN,
            market: DUMMY_MARKET,
            spendDeadline: deadline,
            v: v,
            r: r,
            s: s,
            spenders: spenders,
            amounts: amounts
        });

        // Verify allowances are set correctly for token
        // And that the initial market specific allowances are not affected
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, tokenAAddress), 3 ether);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), AMOUNTS[0]);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, tokenAAddress), 4 ether);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), AMOUNTS[1]);

        // Verify token allowance is set correctly
        assertEq(tokenA.allowance(someMarketsTokenAdmin, orderRouterAddress), approvalAmount);
    }

    function test_setAllowances_withoutSignature() public {
        initializeOrderRouterForTestMarket(DUMMY_MARKET);

        // Initial allowances from initialization
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), AMOUNTS[0]);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), AMOUNTS[1]);

        // Setup new amounts
        uint256[] memory newAmounts = new uint256[](2);
        newAmounts[0] = 5 ether;
        newAmounts[1] = 6 ether;

        // Get initial token allowance to verify it doesn't change
        uint256 initialTokenAllowance = tokenA.allowance(someMarketsTokenAdmin, orderRouterAddress);

        // Call setAllowances without signature (pass zero values for signature params)
        vm.prank(someMarketsTokenAdmin); // Market admin calls
        orderRouter.setAllowances({
            allowanceTargetType: AllowanceTargetType.MARKET,
            market: DUMMY_MARKET,
            spendDeadline: 0, // Not used when no signature
            v: 0,
            r: bytes32(0), // This indicates no signature
            s: bytes32(0),
            spenders: SPENDERS,
            amounts: newAmounts
        });

        // Verify allowances are updated
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, alice, DUMMY_MARKET), newAmounts[0]);
        assertEq(orderRouter.allowances(someMarketsTokenAdmin, bob, DUMMY_MARKET), newAmounts[1]);

        // Verify token allowance remains unchanged (no permit was called)
        assertEq(tokenA.allowance(someMarketsTokenAdmin, orderRouterAddress), initialTokenAllowance);
    }

    function test_setAllowances_withoutSignature_reverts_InvalidAllowanceSpender() public {
        initializeOrderRouterForTestMarket(DUMMY_MARKET);

        // Setup new amounts
        uint256[] memory newAmounts = new uint256[](2);
        newAmounts[0] = 5 ether;
        newAmounts[1] = 6 ether;

        // Alice (not market admin) tries to call without signature
        vm.prank(alice);
        vm.expectRevert(IOnitMarketOrderRouter.InvalidAllowanceSpender.selector);
        orderRouter.setAllowances({
            allowanceTargetType: AllowanceTargetType.MARKET,
            market: DUMMY_MARKET,
            spendDeadline: 0,
            v: 0,
            r: bytes32(0), // No signature
            s: bytes32(0),
            spenders: SPENDERS,
            amounts: newAmounts
        });
    }

    // ----------------------------------------------------------------
    // Helper functions
    // ----------------------------------------------------------------
}
