// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Math
import { convert, convert } from "prb-math/sd59x18/Conversions.sol";
import { sd } from "prb-math/sd59x18.sol";
// PDF
import { PdfLib } from "pdf-lib/PdfLib.sol";
// Utils
import { IODPMUtils } from "./IODPMUtils.sol";

/**
 * @title GenerateTestShareDistributions
 *
 * @dev This contract is used to generate test share distributions for a given prediction
 * These distributions are used in OnitIODPMTestBase.t.sol to populate test arrays to be passed to the
 * market tests
 */
contract GenerateTestShareDistributions is IODPMUtils {
    int256 immutable OUTCOME_UNIT;
    int256 immutable BASE_SHARES;

    // Define market types to match the TypeScript MarketType enum
    enum MarketType {
        Normal,
        Uniform,
        Discrete
    }

    constructor(int256 _bucketWidth, int256 _baseShares) {
        OUTCOME_UNIT = _bucketWidth;
        BASE_SHARES = _baseShares;
    }

    // ----------------------------------------------------------------
    // Utils
    // ----------------------------------------------------------------

    /**
     * @notice Generate share distribution based on market type
     *
     * @param marketType The type of market distribution to generate
     * @param params The parameters for the distribution, encoded as needed for the market type
     *
     * @return bucketIds The array of bucket IDs
     * @return shares The array of share amounts to mint for each bucket
     */
    function generateShareDistributionForMarketType(MarketType marketType, bytes memory params)
        public
        view
        returns (int256[] memory bucketIds, int256[] memory shares)
    {
        if (marketType == MarketType.Normal) {
            (int256 mean, int256 stdDev) = abi.decode(params, (int256, int256));
            return generateNormalDistribution(mean, stdDev, OUTCOME_UNIT);
        } else if (marketType == MarketType.Uniform) {
            (int256 start, int256 end) = abi.decode(params, (int256, int256));
            return generateUniformDistribution(start, end, OUTCOME_UNIT);
        } else if (marketType == MarketType.Discrete) {
            (int256[] memory options, int256[] memory weights) = abi.decode(params, (int256[], int256[]));
            return generateDiscreteDistribution(options, weights);
        }

        // Fallback to normal distribution with default parameters
        return generateNormalDistribution(0, OUTCOME_UNIT * 10, OUTCOME_UNIT);
    }

    /**
     * @notice Calculate the shares for a normal distribution prediction
     *
     * @dev This distributes the BASE_SHARES across the buckets of the traders distribution
     *
     * @param mean The mean of the prediction
     * @param stdDev The standard deviation of the prediction
     *
     * @return bucketIds The array of bucket IDs
     * @return shares The array of share amounts to mint for each bucket
     */
    function generateNormalDistribution(int256 mean, int256 stdDev, int256 outcomeUnit)
        public
        view
        returns (int256[] memory bucketIds, int256[] memory shares)
    {
        bucketIds = _calculateBucketIdsSpanned(mean, stdDev, outcomeUnit);
        shares = new int256[](bucketIds.length);

        // Weight of shares we allocate to each bucket
        int256[] memory weights = new int256[](bucketIds.length);
        // Total weight of shares being minted across all buckets
        int256 totalWeight = 0;

        // Avoid stack too deep errors by limiting scope of pdf symetry variables
        {
            // The max height of the distribution at the mean, we SCALE other points relative to this
            int256 maxHeight = PdfLib.pdf(mean, mean, stdDev);
            /**
             * The pdf is symmetric across the midpoint, so we only need to calculate the first half
             */
            uint256 midIndex = bucketIds.length / 2;
            bool hasMiddleBucket = bucketIds.length % 2 == 1;
            uint256 calcLength = hasMiddleBucket ? midIndex + 1 : midIndex;

            /**
             * Calculate the weight of shares we allocate to each bucket
             * weight[i] = pdf(bucketMid) / (2 * maxHeight)
             *
             * We set both the weight and its mirror image in the same iteration
             */
            for (uint256 i; i < calcLength; i++) {
                int256 weight;
                int256 pdfValue = _calculateBucketMidpointPdf(bucketIds[i], (mean), (stdDev), (outcomeUnit));
                weight = sd(pdfValue).div(convert(2).mul(sd(maxHeight))).unwrap();
                weights[i] = weight;

                // If this isn't the middle bucket in an odd-length array, set the mirror weight
                if (!(hasMiddleBucket && i == midIndex)) {
                    weights[bucketIds.length - 1 - i] = weight;
                    totalWeight += 2 * weight;
                } else {
                    totalWeight += weight;
                }
            }
        }

        /**
         * Calculate shares across all buckets using the weights determined by the distribution
         * shares[i] = (NEW_POSITION_SHARES * weights[i]) / totalWeight
         */
        for (uint256 i; i < bucketIds.length; i++) {
            shares[i] = ((sd(BASE_SHARES).mul(sd(weights[i]))).div(sd(totalWeight))).unwrap();
        }
    }

    /**
     * @notice Calculate the shares for a uniform distribution prediction
     *
     * @dev This distributes the shares uniformly between start and end buckets
     *
     * @param start The starting bucket ID
     * @param end The ending bucket ID
     * @param outcomeUnit The width of each bucket
     *
     * @return bucketIds The array of bucket IDs
     * @return shares The array of share amounts to mint for each bucket
     */
    function generateUniformDistribution(int256 start, int256 end, int256 outcomeUnit)
        public
        view
        returns (int256[] memory bucketIds, int256[] memory shares)
    {
        // Calculate the range based on bucket IDs
        int256 startBucketId = getBucketId(start, outcomeUnit);
        int256 endBucketId = getBucketId(end, outcomeUnit);

        // Ensure startBucketId < endBucketId
        if (startBucketId > endBucketId) {
            (startBucketId, endBucketId) = (endBucketId, startBucketId);
        }

        // Calculate number of buckets in the range
        uint256 numBuckets = uint256(endBucketId - startBucketId + 1);

        // Create bucketIds and shares arrays
        bucketIds = new int256[](numBuckets);
        shares = new int256[](numBuckets);

        // Set each bucket and share value (uniform distribution means equal shares)
        int256 sharesPerBucket = BASE_SHARES / int256(numBuckets);

        for (uint256 i = 0; i < numBuckets; i++) {
            bucketIds[i] = startBucketId + int256(i);
            shares[i] = sharesPerBucket;
        }

        return (bucketIds, shares);
    }

    /**
     * @notice Calculate the shares for a discrete distribution prediction
     *
     * @dev This distributes shares across specific option points with given weights
     *
     * @param options The array of option values (not bucket IDs)
     * @param weights The weights for each option
     *
     * @return bucketIds The array of bucket IDs
     * @return shares The array of share amounts to mint for each bucket
     */
    function generateDiscreteDistribution(int256[] memory options, int256[] memory weights)
        public
        view
        returns (int256[] memory bucketIds, int256[] memory shares)
    {
        require(options.length == weights.length, "Options and weights arrays must have the same length");
        require(options.length > 0, "Options array cannot be empty");

        bucketIds = options;
        shares = new int256[](options.length);

        // Calculate total weight to normalize shares
        int256 totalWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalWeight += weights[i];
        }

        // Calculate shares based on weights
        for (uint256 i = 0; i < options.length; i++) {
            if (totalWeight > 0) {
                shares[i] = (sd(BASE_SHARES).mul(sd(weights[i])).div(sd(totalWeight))).unwrap();
            } else {
                // If total weight is zero, distribute evenly
                shares[i] = BASE_SHARES / int256(options.length);
            }
        }

        return (bucketIds, shares);
    }

    function _calculateBucketMidpointPdf(int256 bucketId, int256 mean, int256 stdDev, int256 outcomeUnit)
        internal
        pure
        returns (int256)
    {
        return PdfLib.pdf(_getBucketMidpoint(bucketId, outcomeUnit), mean, stdDev);
    }
}
