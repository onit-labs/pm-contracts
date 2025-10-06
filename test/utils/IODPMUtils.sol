// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { convert } from "prb-math/sd59x18/Conversions.sol";

contract IODPMUtils {
    function costFunction(int256 kappa, int256 totalQSquared) internal pure returns (int256) {
        return convert(convert(kappa).mul(convert(int256(totalQSquared)).sqrt()));
    }

    function getCostOfInitialBet(int256 kappa, int256[] memory shares) internal pure returns (int256, int256) {
        int256 totalQSquared;
        for (uint256 i; i < shares.length; i++) {
            totalQSquared += shares[i] * shares[i];
        }
        return (convert(convert(kappa).mul(convert(int256(totalQSquared)).sqrt())), totalQSquared);
    }

    function getKappaForInitialMarket(int256[] memory shares, int256 initialMarketBudget) public pure returns (int256) {
        int256 sumOfSharesSquared = 0;

        for (uint256 i = 0; i < shares.length; i++) {
            sumOfSharesSquared += shares[i] * shares[i];
        }

        int256 kappa = convert(convert(initialMarketBudget).div(convert(sumOfSharesSquared).sqrt()));

        return kappa;
    }

    function getTotalQSquaredForMarket(int256 kappa, int256 cost) internal pure returns (int256) {
        return (convert((convert(int256(cost)).div(convert(kappa))).pow(convert(int256(2)))));
    }

    function getBucketId(int256 outcome, int256 outcomeUnit) internal pure returns (int256 bucketId) {
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

    function _calculateBucketIdsSpanned(int256 mean, int256 stdDev, int256 outcomeUnit)
        internal
        pure
        returns (int256[] memory)
    {
        (int256 lowerBucket, int256 bucketRange) = _calculateBucketsSpanned(mean, stdDev, outcomeUnit);
        int256[] memory bucketIds = new int256[](uint256(bucketRange));
        for (int256 i = 0; i < bucketRange; i++) {
            bucketIds[uint256(i)] = lowerBucket + i;
        }

        return bucketIds;
    }

    function _calculateBucketsSpanned(int256 mean, int256 stdDev, int256 outcomeUnit)
        internal
        pure
        returns (int256, int256)
    {
        int256 lowerBound = mean - stdDev;
        int256 upperBound = mean + stdDev;

        int256 lowerBucket = getBucketId(lowerBound, outcomeUnit);
        int256 upperBucket = getBucketId(upperBound, outcomeUnit);

        int256 bucketRange = upperBucket - lowerBucket;

        return (lowerBucket, bucketRange);
    }

    function _getBucketMidpoint(int256 bucketId, int256 outcomeUnit) internal pure returns (int256) {
        (int256 start, int256 end) = _getBucketEndpoints(bucketId, outcomeUnit);
        return (start + end) / 2;
    }

    function _getBucketEndpoints(int256 bucketId, int256 outcomeUnit) internal pure returns (int256 start, int256 end) {
        start = bucketId * outcomeUnit;
        end = start + outcomeUnit;
    }
}
