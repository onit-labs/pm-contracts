// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc
import { console2 } from "forge-std/console2.sol";
import { stdStorage, StdStorage } from "forge-std/Test.sol";
// Config
import { AddressTestConfig } from "@test/config/AddressTestConfig.t.sol";
// Contracts to test
import {
    OnitInfiniteOutcomeDPMOutcomeDomain
} from "@src/mechanisms/infinite-outcome-DPM/OnitInfiniteOutcomeDPMOutcomeDomain.sol";

/**
 * @title OnitInfiniteOutcomeDPMOutcomeDomainHarness
 * @notice Test harness for OnitInfiniteOutcomeDPMOutcomeDomain
 */
contract OnitInfiniteOutcomeDPMOutcomeDomainHarness is OnitInfiniteOutcomeDPMOutcomeDomain {
    function initialize(int256 _outcomeUnit) external {
        _initializeOutcomeDomain(_outcomeUnit);
    }

    function bucketIdToPackedPosition(int256 bucketId)
        external
        pure
        returns (BucketWordIndex packedWord, uint8 offset)
    {
        return _bucketIdToPackedPosition(bucketId);
    }

    function updateHoldings(address trader, int256[] memory bucketIds, int256[] memory amounts) external {
        _updateHoldings(trader, bucketIds, amounts);
    }

    function initializeOutcomeDomain(int256 _outcomeUnit) external {
        _initializeOutcomeDomain(_outcomeUnit);
    }

    function getOutstandingSharesInBuckets(int256[] memory bucketIds) external view returns (int256[] memory) {
        return _getOutstandingSharesInBuckets(bucketIds);
    }
}

/**
 * @title OnitInfiniteOutcomeDPMOutcomeDomainTest
 * @notice Tests for OnitInfiniteOutcomeDPMOutcomeDomain
 */
contract OnitInfiniteOutcomeDPMOutcomeDomainTest is AddressTestConfig {
    using stdStorage for StdStorage;

    int256 constant OUTCOME_UNIT = 1000;

    OnitInfiniteOutcomeDPMOutcomeDomainHarness public harness;

    function setUp() public {
        harness = new OnitInfiniteOutcomeDPMOutcomeDomainHarness();
        harness.initialize(OUTCOME_UNIT);
    }

    // ----------------------------------------------------------------
    // Bucket ID Tests
    // ----------------------------------------------------------------

    function test_getBucketId_positive() public view {
        assertEq(harness.getBucketId(0), 0, "0 should be in bucket 0");
        assertEq(harness.getBucketId(999), 0, "999 should be in bucket 0");
        assertEq(harness.getBucketId(1000), 1, "1000 should be in bucket 1");
        assertEq(harness.getBucketId(1999), 1, "1999 should be in bucket 1");
        assertEq(harness.getBucketId(2000), 2, "2000 should be in bucket 2");
        assertEq(harness.getBucketId(2500), 2, "2500 should be in bucket 2");
        assertEq(harness.getBucketId(3000), 3, "3000 should be in bucket 3");
    }

    function test_getBucketId_negative() public view {
        assertEq(harness.getBucketId(-1), -1, "-1 should be in bucket -1");
        assertEq(harness.getBucketId(-999), -1, "-999 should be in bucket -1");
        assertEq(harness.getBucketId(-1000), -2, "-1000 should be in bucket -2");
        assertEq(harness.getBucketId(-1001), -2, "-1001 should be in bucket -2");
        assertEq(harness.getBucketId(-1999), -2, "-1999 should be in bucket -2");
        assertEq(harness.getBucketId(-2000), -3, "-2000 should be in bucket -3");
        assertEq(harness.getBucketId(-2001), -3, "-2001 should be in bucket -3");
    }

    function test_getBucketId_boundaries() public view {
        assertEq(harness.getBucketId(0), 0, "0 should be in bucket 0");
        assertEq(harness.getBucketId(-1), -1, "-1 should be in bucket -1");
        assertEq(harness.getBucketId(1), 0, "1 should be in bucket 0");
        assertEq(harness.getBucketId(-1000), -2, "-1000 should be in bucket -2");
        assertEq(harness.getBucketId(1000), 1, "1000 should be in bucket 1");
    }

    // ----------------------------------------------------------------
    // Packed Position Tests
    // ----------------------------------------------------------------

    function test_bucketIdToPackedPosition_positive() public view {
        (OnitInfiniteOutcomeDPMOutcomeDomain.BucketWordIndex word, uint8 offset) = harness.bucketIdToPackedPosition(0);
        assertEq(OnitInfiniteOutcomeDPMOutcomeDomain.BucketWordIndex.unwrap(word), 0);
        assertEq(offset, 0);

        (word, offset) = harness.bucketIdToPackedPosition(1);
        assertEq(OnitInfiniteOutcomeDPMOutcomeDomain.BucketWordIndex.unwrap(word), 0);
        assertEq(offset, 1);

        (word, offset) = harness.bucketIdToPackedPosition(2);
        assertEq(OnitInfiniteOutcomeDPMOutcomeDomain.BucketWordIndex.unwrap(word), 0);
        assertEq(offset, 2);

        (word, offset) = harness.bucketIdToPackedPosition(3);
        assertEq(OnitInfiniteOutcomeDPMOutcomeDomain.BucketWordIndex.unwrap(word), 1);
        assertEq(offset, 0);
    }

    function test_bucketIdToPackedPosition_negative() public view {
        (OnitInfiniteOutcomeDPMOutcomeDomain.BucketWordIndex word, uint8 offset) = harness.bucketIdToPackedPosition(-1);
        assertEq(OnitInfiniteOutcomeDPMOutcomeDomain.BucketWordIndex.unwrap(word), -1);
        assertEq(offset, 2);

        (word, offset) = harness.bucketIdToPackedPosition(-2);
        assertEq(OnitInfiniteOutcomeDPMOutcomeDomain.BucketWordIndex.unwrap(word), -1);
        assertEq(offset, 1);

        (word, offset) = harness.bucketIdToPackedPosition(-3);
        assertEq(OnitInfiniteOutcomeDPMOutcomeDomain.BucketWordIndex.unwrap(word), -1);
        assertEq(offset, 0);

        (word, offset) = harness.bucketIdToPackedPosition(-4);
        assertEq(OnitInfiniteOutcomeDPMOutcomeDomain.BucketWordIndex.unwrap(word), -2);
        assertEq(offset, 2);
    }

    // ----------------------------------------------------------------
    // Share Balance Tests
    // ----------------------------------------------------------------

    function test_getBalanceOfShares() public {
        int256[] memory bucketIds = new int256[](3);
        bucketIds[0] = 0;
        bucketIds[1] = 1;
        bucketIds[2] = 2;

        int256[] memory amounts = new int256[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        harness.updateHoldings(alice, bucketIds, amounts);

        // Test getting balances
        assertEq(harness.getBalanceOfShares(alice, 0), 100);
        assertEq(harness.getBalanceOfShares(alice, 1), 200);
        assertEq(harness.getBalanceOfShares(alice, 2), 300);

        // Add more shares
        harness.updateHoldings(alice, bucketIds, amounts);

        // Test getting balances
        assertEq(harness.getBalanceOfShares(alice, 0), 200);
        assertEq(harness.getBalanceOfShares(alice, 1), 400);
        assertEq(harness.getBalanceOfShares(alice, 2), 600);
    }

    function test_getBucketOutstandingShares() public {
        int256[] memory bucketIds = new int256[](3);
        bucketIds[0] = 0;
        bucketIds[1] = 1;
        bucketIds[2] = 2;

        int256[] memory amounts = new int256[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        harness.updateHoldings(alice, bucketIds, amounts);

        // Test getting outstanding shares
        assertEq(harness.getBucketOutstandingShares(0), 100);
        assertEq(harness.getBucketOutstandingShares(1), 200);
        assertEq(harness.getBucketOutstandingShares(2), 300);

        // Add more shares
        harness.updateHoldings(alice, bucketIds, amounts);

        // Test getting outstanding shares
        assertEq(harness.getBucketOutstandingShares(0), 200);
        assertEq(harness.getBucketOutstandingShares(1), 400);
        assertEq(harness.getBucketOutstandingShares(2), 600);
    }

    // ----------------------------------------------------------------
    // Batch Update Tests
    // ----------------------------------------------------------------

    function test_updateHoldings_sequential() public {
        // Test updating sequential buckets
        int256[] memory bucketIds = new int256[](3);
        bucketIds[0] = 0;
        bucketIds[1] = 1;
        bucketIds[2] = 2;

        int256[] memory amounts = new int256[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        harness.updateHoldings(alice, bucketIds, amounts);

        // Verify balances
        assertEq(harness.getBalanceOfShares(alice, 0), 100);
        assertEq(harness.getBalanceOfShares(alice, 1), 200);
        assertEq(harness.getBalanceOfShares(alice, 2), 300);

        // Verify outstanding shares
        assertEq(harness.getBucketOutstandingShares(0), 100);
        assertEq(harness.getBucketOutstandingShares(1), 200);
        assertEq(harness.getBucketOutstandingShares(2), 300);
    }

    function test_updateHoldings_nonSequential() public {
        // Test updating non-sequential buckets
        int256[] memory bucketIds = new int256[](3);
        bucketIds[0] = 0;
        bucketIds[1] = 2;
        bucketIds[2] = 4;

        int256[] memory amounts = new int256[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        harness.updateHoldings(alice, bucketIds, amounts);

        // Verify balances
        assertEq(harness.getBalanceOfShares(alice, 0), 100);
        assertEq(harness.getBalanceOfShares(alice, 2), 200);
        assertEq(harness.getBalanceOfShares(alice, 4), 300);

        // Verify outstanding shares
        assertEq(harness.getBucketOutstandingShares(0), 100);
        assertEq(harness.getBucketOutstandingShares(2), 200);
        assertEq(harness.getBucketOutstandingShares(4), 300);
    }

    function test_updateHoldings_reduce() public {
        // Test updating negative buckets
        int256[] memory bucketIds = new int256[](3);
        bucketIds[0] = 1;
        bucketIds[1] = 2;
        bucketIds[2] = 3;

        int256[] memory amounts = new int256[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        // initially setup some shares
        harness.updateHoldings(alice, bucketIds, amounts);

        // Verify balances
        assertEq(harness.getBalanceOfShares(alice, 1), 100);
        assertEq(harness.getBalanceOfShares(alice, 2), 200);
        assertEq(harness.getBalanceOfShares(alice, 3), 300);

        amounts[0] = -50;
        amounts[1] = -100;
        amounts[2] = -150;

        harness.updateHoldings(alice, bucketIds, amounts);

        // Verify outstanding shares
        assertEq(harness.getBucketOutstandingShares(1), 50);
        assertEq(harness.getBucketOutstandingShares(2), 100);
        assertEq(harness.getBucketOutstandingShares(3), 150);
    }

    // ----------------------------------------------------------------
    // Error Tests
    // ----------------------------------------------------------------

    function test_updateHoldings_revert_BucketSharesOverflow_nonConsecutive() public {
        // Set the storage slot of the bucket to be close to the max uint80
        uint256 bucketShares = type(uint80).max - 1;
        stdstore.enable_packed_slots().target(address(harness)).sig("bucketOutstandingPackedShares(int256)")
            .with_key(uint256(0)).checked_write(bucketShares);

        // Verify initial state
        int256 currentBucketShares = harness.getBucketOutstandingShares(0);
        assertEq(currentBucketShares, int256(bucketShares));

        // Setup bucket with max shares
        int256[] memory bucketIds = new int256[](1);
        bucketIds[0] = 0;

        int256[] memory amounts = new int256[](1);
        amounts[0] = int256(2);

        console2.logBytes10(OnitInfiniteOutcomeDPMOutcomeDomain.BucketSharesOverflow.selector);

        // This should revert with BucketSharesOverflow since we're trying to add 2 to max-1
        vm.expectRevert(OnitInfiniteOutcomeDPMOutcomeDomain.BucketSharesOverflow.selector);
        harness.updateHoldings(alice, bucketIds, amounts);
    }

    function test_updateHoldings_revert_BucketSharesOverflow_3Consecutive() public {
        // Set the storage slot of the bucket to be close to the max uint80
        uint256 bucketShares = type(uint80).max - 1;
        stdstore.enable_packed_slots().target(address(harness)).sig("bucketOutstandingPackedShares(int256)")
            .with_key(uint256(0)).checked_write(bucketShares);

        int256[] memory bucketIds = new int256[](3);
        bucketIds[0] = 0;
        bucketIds[1] = 1;
        bucketIds[2] = 2;

        int256[] memory amounts = new int256[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        vm.expectRevert(OnitInfiniteOutcomeDPMOutcomeDomain.BucketSharesOverflow.selector);
        harness.updateHoldings(alice, bucketIds, amounts);
    }

    function test_updateHoldings_revert_InsufficientShares_nonConsecutive() public {
        // Setup initial shares
        int256[] memory bucketIds = new int256[](1);
        bucketIds[0] = 0;

        int256[] memory amounts = new int256[](1);
        amounts[0] = 100;

        harness.updateHoldings(alice, bucketIds, amounts);

        // Try to remove more shares than available
        amounts[0] = -200;
        vm.expectRevert(OnitInfiniteOutcomeDPMOutcomeDomain.InsufficientShares.selector);
        harness.updateHoldings(alice, bucketIds, amounts);
    }

    function test_updateHoldings_revert_InsufficientShares_3Consecutive() public {
        // Setup initial shares
        int256[] memory bucketIds = new int256[](3);
        bucketIds[0] = 0;
        bucketIds[1] = 1;
        bucketIds[2] = 2;

        int256[] memory amounts = new int256[](3);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;

        harness.updateHoldings(alice, bucketIds, amounts);

        // Remove more than the available shares
        amounts[1] = -300;

        vm.expectRevert(OnitInfiniteOutcomeDPMOutcomeDomain.InsufficientShares.selector);
        harness.updateHoldings(alice, bucketIds, amounts);
    }

    // ----------------------------------------------------------------
    // Range Tests
    // ----------------------------------------------------------------

    function test_getOutstandingSharesInBucketRange() public {
        // Setup shares in multiple buckets
        int256[] memory bucketIds = new int256[](5);
        bucketIds[0] = 0;
        bucketIds[1] = 1;
        bucketIds[2] = 2;
        bucketIds[3] = 3;
        bucketIds[4] = 4;

        int256[] memory amounts = new int256[](5);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;
        amounts[3] = 400;
        amounts[4] = 500;

        harness.updateHoldings(alice, bucketIds, amounts);

        // Test getting shares in range
        int256[] memory shares = harness.getOutstandingSharesInBucketRange(1, 3);
        assertEq(shares.length, 3);
        assertEq(shares[0], 200);
        assertEq(shares[1], 300);
        assertEq(shares[2], 400);
    }

    function test_getOutstandingSharesInBucketRange_reversed() public {
        // Setup shares in multiple buckets
        int256[] memory bucketIds = new int256[](5);
        bucketIds[0] = 0;
        bucketIds[1] = 1;
        bucketIds[2] = 2;
        bucketIds[3] = 3;
        bucketIds[4] = 4;

        int256[] memory amounts = new int256[](5);
        amounts[0] = 100;
        amounts[1] = 200;
        amounts[2] = 300;
        amounts[3] = 400;
        amounts[4] = 500;

        harness.updateHoldings(alice, bucketIds, amounts);

        // Test getting shares in reversed range
        int256[] memory shares = harness.getOutstandingSharesInBucketRange(3, 1);
        assertEq(shares.length, 3);
        assertEq(shares[0], 200);
        assertEq(shares[1], 300);
        assertEq(shares[2], 400);
    }
}
