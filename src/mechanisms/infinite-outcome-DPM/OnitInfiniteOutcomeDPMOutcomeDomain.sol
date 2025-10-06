// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title Onit Infinite Outcome Dynamic Parimutual Market Outcome Domain
 *
 * @author Onit Labs (https://github.com/onit-labs)
 *
 * @notice Outcome domain utilities for the DPM
 *
 * @dev Notes on the outcome domain:
 * - The continuous outcome domain is divided into buckets of fixed width
 * - Traders are exposed to a range of buckets based on their predictions on the outcome domain (real numbers)
 * - We use bit packing to encode multiple bucket balances into a single uint256 to save on storage costs
 *   @custom:warning This assumes token balances will not exceed 2^80 - 1 = 1.208925819614629174706175e24
 */
contract OnitInfiniteOutcomeDPMOutcomeDomain {
    /**
     * @notice BucketWordIndex is the word in which the packed shares can be found
     * @dev This is used to find the word in a mapping, which we then offset to extract the relevant shares
     */
    type BucketWordIndex is int256;
    /**
     * @notice BucketShares is the number of shares in a bucket
     */
    type BucketShares is uint80;
    /**
     * @notice PackedBucketShares is the packed shares for a bucket, comprised of 3 BucketShares
     */
    type PackedBucketShares is uint256;

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error BucketSharesOverflow();
    error InsufficientShares();

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /**
     * @notice The unit size for the outcome domain
     *
     * @dev This is essentially the resolution we measure the outcome domain to
     * eg.
     * - 1000 would mean we measure the outcome domain in 1000 unit increments
     * - Any guess from 0 to 999 would be bucketed into bucket 0 etc
     */
    int256 public outcomeUnit;

    /**
     * @notice Outcome tokens minted for each bucket
     * How many shares of each outcome are minted. Corresponds to q(x) in the calculates for a Dynamic Parimutual
     * Market
     *
     * @dev We use bit packing to store multiple bucket balances into a single uint256 to save on storage costs
     * - BucketWordIndex is a word in which the packed shares can be found
     * - PackedBucketShares is the packed shares for a bucket, comprised of 3 BucketShares
     * - Offset by the relevant amount to extract the correct shares
     * - Use getBucketOutstandingShares with the bucket ID to get the outstanding shares
     */
    mapping(BucketWordIndex bucket => PackedBucketShares outstandingShares) public bucketOutstandingPackedShares;
    /**
     * @notice Balance of shares for each trader for each bucket
     *
     * @dev We use bit packing to store multiple bucket balances into a single uint256 to save on storage costs
     * - BucketWordIndex is a word in which the packed shares can be found
     * - PackedBucketShares is the packed shares for a bucket, comprised of 3 BucketShares
     * - Offset by the relevant amount to extract the correct shares
     * - Use getBalanceOfShares with the trader address and bucket ID to get the balance
     */
    mapping(address holder => mapping(BucketWordIndex => PackedBucketShares)) public balanceOfPackedShares;

    /**
     * @notice Maximum value for a bucket's shares (2^80 - 1)
     * @dev This is used:
     * - to check for overflow when updating bucket shares
     * - as a bit mask to extract bucket shares from packed storage
     */
    uint256 public constant MAX_BUCKET_SHARES = type(uint80).max;

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    function _initializeOutcomeDomain(int256 _outcomeUnit) internal {
        outcomeUnit = _outcomeUnit;
    }

    // ----------------------------------------------------------------
    // Outcome domain functions
    // ----------------------------------------------------------------

    /**
     * @notice Get the bucket ID for an outcome
     *
     * @dev Determine the bucket that an outcome falls into based on the outcome unit
     *
     * @param outcome The outcome to get the bucket ID for
     *
     * @return bucketId The bucket ID for the outcome
     */
    function getBucketId(int256 outcome) public view returns (int256 bucketId) {
        /**
         * We get bucketId by dividing the outcome by the outcome unit
         * Solidity will round down (towards 0)
         * If the outcome is positive this works fine
         * If the outcome is negative, then bucketId 0 would be double the width of other buckets
         * We fix this by subtracting 1 from the result
         */
        if (outcome < 0) {
            bucketId = (outcome / outcomeUnit) - 1;
        } else {
            bucketId = outcome / outcomeUnit;
        }
    }

    // ----------------------------------------------------------------
    // Outcome token functions
    // ----------------------------------------------------------------

    /**
     * @notice Get the total outstanding shares for all buckets in a range
     *
     * @dev This is an external util to get the outstanding shares for a range of buckets
     *      A similar internal function _getOutstandingSharesInBuckets is usedin the OnitInfiniteOutcomeDPM
     *      It is preferred as bucketIds are not nescarily sequential
     * @param l The lower bucketId
     * @param u The upper bucketId
     *
     * @return shares The total outstanding shares for all buckets in the range (l, u)
     */
    function getOutstandingSharesInBucketRange(int256 l, int256 u) external view returns (int256[] memory) {
        if (l > u) {
            int256 correctedU = l;
            l = u;
            u = correctedU;
        }
        // Casting to uint256 is safe since the above (u - l + 1) >= 0
        uint256 bucketCount = uint256(u - l + 1);
        int256[] memory shares = new int256[](bucketCount);
        for (uint256 i; i < bucketCount; i++) {
            // Casting i to int256 is safe since i < bucketCount which should always be less than int256.max
            shares[i] = getBucketOutstandingShares(l + int256(i));
        }
        return shares;
    }

    /**
     * @notice Get the total outstanding shares for a bucket
     *
     * @dev Finds the word where the buckets outstanding shares are stored, then extracts the relevant bits
     *
     * @param bucketId The bucket ID to get the outstanding shares for
     *
     * @return outstandingShares The outstanding shares of the bucket
     */
    function getBucketOutstandingShares(int256 bucketId) public view returns (int256) {
        (BucketWordIndex packedWord, uint8 offset) = _bucketIdToPackedPosition(bucketId);

        /**
         * Extract the relevant shares from the packed word
         * - Convert to uint256 type for bit operations
         * - Shift right by the offset * 80 bits
         * - Mask with a bitmask of 80 bits
         */
        uint256 extracted =
            (PackedBucketShares.unwrap(bucketOutstandingPackedShares[packedWord]) >> (offset * 80)) & ((1 << 80) - 1);

        // Check extracted value is within bounds of BucketShares which is uint80
        if (extracted > type(uint80).max) revert BucketSharesOverflow();

        // Casting to int256 is safe since extracted is positive and less than uint80.max
        return int256(extracted);
    }

    /**
     * @notice Get the balance of a trader for a bucket
     *
     * @dev Finds the word where the traders balance is stored, then extracts the relevant bits
     *
     * @param trader The trader to get the balance for
     * @param bucketId The bucket ID to get the balance for
     *
     * @return balance The balance of the trader for the bucket
     */
    function getBalanceOfShares(address trader, int256 bucketId) public view returns (uint256) {
        (BucketWordIndex packedWord, uint8 offset) = _bucketIdToPackedPosition(bucketId);

        /**
         * Extract the relevant shares from the packed word
         * - Convert to uint256 type for bit operations
         * - Shift right by the offset * 80 bits
         * - Mask with a bitmask of 80 bits
         */
        uint256 extracted =
            (PackedBucketShares.unwrap(balanceOfPackedShares[trader][packedWord]) >> (offset * 80)) & ((1 << 80) - 1);

        // Check extracted value is within bounds of BucketShares which is uint80
        if (extracted > type(uint80).max) revert BucketSharesOverflow();

        return extracted;
    }

    /**
     * @notice Update both outstanding shares and trader balances in a single pass
     *
     * @dev Updates both bucketOutstandingPackedShares and balanceOfPackedShares mappings
     * @dev Pass bucketIds in ascending order, this lets us more efficiently batch write sequential buckets
     *
     * @param trader The address of the trader receiving the shares
     * @param bucketIds Array of bucket IDs to set
     * @param amounts Array of amounts to set
     */
    function _updateHoldings(address trader, int256[] memory bucketIds, int256[] memory amounts) internal {
        uint256 bucketCount = bucketIds.length;

        /**
         * @dev Process buckets in groups of 3 where possible
         * Since buckets are usually sequential we can usually update 3 at a time
         * WARNING: This assumes we pack 3 buckets into a single uint256 (ie. uint80 max balance)
         */
        for (uint256 i; i < bucketCount;) {
            // Get the packed word and offset for current bucket
            (BucketWordIndex packedWord, uint8 startOffset) = _bucketIdToPackedPosition(bucketIds[i]);

            uint256 batchSize = 1;
            // Determine if we can batch process 3 buckets
            if (startOffset == 0 && i + 3 <= bucketCount) {
                bool canBatch = true;

                // Check if 3 buckets are sequential and in same word
                for (uint256 j = 1; j < 3; j++) {
                    int256 nextBucket = bucketIds[i + j];

                    // Check if sequential (casting j to int256 is safe since j < 3)
                    if (nextBucket != bucketIds[i] + int256(j)) {
                        canBatch = false;
                        break;
                    }

                    // If first bucket is negative and next is non-negative, they're in different words
                    if (bucketIds[i] < 0 && nextBucket >= 0) {
                        canBatch = false;
                        break;
                    }
                }
                // Batch process if we can
                if (canBatch) batchSize = 3;
            }

            if (batchSize == 3) {
                // Process full word of 3 buckets
                int256 amount0 = amounts[i];
                int256 amount1 = amounts[i + 1];
                int256 amount2 = amounts[i + 2];

                // Get current values
                PackedBucketShares outstandingCurrent = bucketOutstandingPackedShares[packedWord];
                PackedBucketShares balanceCurrent = balanceOfPackedShares[trader][packedWord];

                // Extract current values
                uint256 outstanding0 = (PackedBucketShares.unwrap(outstandingCurrent) & MAX_BUCKET_SHARES);
                uint256 outstanding1 = ((PackedBucketShares.unwrap(outstandingCurrent) >> 80) & MAX_BUCKET_SHARES);
                uint256 outstanding2 = ((PackedBucketShares.unwrap(outstandingCurrent) >> 160) & MAX_BUCKET_SHARES);

                uint256 balance0 = uint256(PackedBucketShares.unwrap(balanceCurrent) & MAX_BUCKET_SHARES);
                uint256 balance1 = uint256((PackedBucketShares.unwrap(balanceCurrent) >> 80) & MAX_BUCKET_SHARES);
                uint256 balance2 = uint256((PackedBucketShares.unwrap(balanceCurrent) >> 160) & MAX_BUCKET_SHARES);

                // Check for overflow and insufficient balance
                if (amount0 > 0 && outstanding0 + uint256(amount0) > MAX_BUCKET_SHARES) revert BucketSharesOverflow();
                if (amount0 < 0 && uint256(-amount0) > balance0) revert InsufficientShares();

                if (amount1 > 0 && outstanding1 + uint256(amount1) > MAX_BUCKET_SHARES) revert BucketSharesOverflow();
                if (amount1 < 0 && uint256(-amount1) > balance1) revert InsufficientShares();

                if (amount2 > 0 && outstanding2 + uint256(amount2) > MAX_BUCKET_SHARES) revert BucketSharesOverflow();
                if (amount2 < 0 && uint256(-amount2) > balance2) revert InsufficientShares();

                // Calculate new values
                int256 newOutstanding0 = (int256(outstanding0) + amount0);
                int256 newOutstanding1 = (int256(outstanding1) + amount1);
                int256 newOutstanding2 = (int256(outstanding2) + amount2);

                uint256 newBalance0 = uint256(int256(balance0) + amount0);
                uint256 newBalance1 = uint256(int256(balance1) + amount1);
                uint256 newBalance2 = uint256(int256(balance2) + amount2);

                // Pack new values
                uint256 outstandingNew =
                    uint256(newOutstanding0) | (uint256(newOutstanding1) << 80) | (uint256(newOutstanding2) << 160);
                uint256 balanceNew = newBalance0 | (newBalance1 << 80) | (newBalance2 << 160);

                // Store updates
                bucketOutstandingPackedShares[packedWord] = PackedBucketShares.wrap(outstandingNew);
                balanceOfPackedShares[trader][packedWord] = PackedBucketShares.wrap(balanceNew);
            } else {
                // Process single bucket
                int256 amount = amounts[i];
                uint256 shift = startOffset * 80;

                // Get current values
                PackedBucketShares outstandingCurrent = bucketOutstandingPackedShares[packedWord];
                PackedBucketShares balanceCurrent = balanceOfPackedShares[trader][packedWord];

                // Extract current values
                uint256 outstanding =
                    uint256((PackedBucketShares.unwrap(outstandingCurrent) >> shift) & MAX_BUCKET_SHARES);
                uint256 balance = uint256((PackedBucketShares.unwrap(balanceCurrent) >> shift) & MAX_BUCKET_SHARES);

                // Check for overflow and insufficient balance
                if (amount < 0 && uint256(-amount) > balance) revert InsufficientShares();
                if (amount > 0 && outstanding + uint256(amount) > MAX_BUCKET_SHARES) revert BucketSharesOverflow();

                // Calculate new values
                uint256 newOutstanding = uint256(int256(outstanding) + amount);
                uint256 newBalance = uint256(int256(balance) + amount);

                // Create masks
                uint256 mask = ~(MAX_BUCKET_SHARES << shift);
                uint256 shiftedNewOutstanding = newOutstanding << shift;
                uint256 shiftedNewBalance = newBalance << shift;

                // Store updates
                bucketOutstandingPackedShares[packedWord] = PackedBucketShares.wrap(
                    (PackedBucketShares.unwrap(outstandingCurrent) & mask) | shiftedNewOutstanding
                );
                balanceOfPackedShares[trader][packedWord] =
                    PackedBucketShares.wrap((PackedBucketShares.unwrap(balanceCurrent) & mask) | shiftedNewBalance);
            }

            i += batchSize;
        }
    }

    /**
     * @notice Get the outstanding shares for a range of bucketIds
     *
     * @param bucketIds bucketIds to get shares in
     *
     * @return shares The outstanding shares for the bucketIds
     */
    function _getOutstandingSharesInBuckets(int256[] memory bucketIds) internal view returns (int256[] memory) {
        uint256 bucketCount = bucketIds.length;
        int256[] memory shares = new int256[](bucketCount);
        for (uint256 i; i < bucketCount; i++) {
            shares[i] = getBucketOutstandingShares(bucketIds[i]);
        }
        return shares;
    }

    /**
     * @notice Convert a bucket ID to a packed position (word and offset)
     *
     * @dev This is used to find the relevant bits in a storage location for a nucket ID
     *
     * @param bucketId The bucket ID to convert
     *
     * @return packedWord The word where the bucket's balance is stored
     * @return offset The offset within the word where the bucket's balance is stored
     */
    function _bucketIdToPackedPosition(int256 bucketId)
        internal
        pure
        returns (BucketWordIndex packedWord, uint8 offset)
    {
        // For negative numbers, we adjust the division to round towards negative infinity
        // Example: -1 should be in word -1 at offset 2, not word 0 at offset -1
        if (bucketId < 0) {
            // For negative numbers, we subtract 2 to ensure proper rounding
            // eg. (-1 - 2) = -3 / 3 -> -1
            // eg. (-4 - 2) = -6 / 3 -> -2
            packedWord = BucketWordIndex.wrap((bucketId - 2) / 3);

            // For negative numbers, we need to calculate the positive offset
            // eg. (-1 % 3 = -1) + 3 = 2 % 3 = 2
            // eg. (-3 % 3 = 0) + 3 = 3 % 3 = 0
            offset = uint8(uint256((bucketId % 3) + 3) % 3);
        } else {
            packedWord = BucketWordIndex.wrap(bucketId / 3);
            // Casting to uint256 then uint8 is safe since bucketId is positive and less than uint8.max
            offset = uint8(uint256(bucketId % 3));
        }
    }
}
