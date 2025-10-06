// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Math Utils
import { SD59x18, sd, convert, convert } from "prb-math/SD59x18.sol";

// Interfaces
import { IOnitInfiniteOutcomeDPMMechanism } from "@src/interfaces/IOnitInfiniteOutcomeDPMMechanism.sol";

// Onit contracts
import { OnitInfiniteOutcomeDPMOutcomeDomain } from "./OnitInfiniteOutcomeDPMOutcomeDomain.sol";

/**
 * @title Onit Infinite Outcome Dynamic Parimutual Market Mechanism
 *
 * @author Onit Labs (https://github.com/onit-labs)
 *
 * @notice State and logic for an infinite outcome DPM
 *
 * @dev Notes on the mechanism:
 * - The outcome domain is divided into buckets
 * - A traders prediction will expose them to a range of buckets
 * - The shares minted for each bucket can be proportional to the traders confidence in the outcome
 * - Determining the shares minted for each trade involves calculating the difference in the cost potential funciton:
 *   C(q') - C(q) = κ * sqrt(Σq'²) - κ * sqrt(Σq²)
 * - Where q is the number of shares outstanding at a point (x) on the outcome domain
 * - Traders with shares in the bucket which contains the resolved outcome will be paid out
 * - Payouts are proportional to the traders shares at the resolved outcome
 */
contract OnitInfiniteOutcomeDPMMechanism is IOnitInfiniteOutcomeDPMMechanism, OnitInfiniteOutcomeDPMOutcomeDomain {
    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @inheritdoc IOnitInfiniteOutcomeDPMMechanism
    int256 public totalQSquared;

    /// @inheritdoc IOnitInfiniteOutcomeDPMMechanism
    int256 public kappa;

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    function _initializeInfiniteOutcomeDPM(
        address initiator,
        int256 initOutcomeUnit,
        int256 initBetValue,
        int256[] memory initBucketIds,
        int256[] memory initShares
    )
        internal
    {
        // Initialize outcome domain parameters
        _initializeOutcomeDomain(initOutcomeUnit);

        /**
         * totalQSquared is the sum of the squares of the outcome tokens in each bucket
         * We store it as it is used in calculations for the DPM and it would be costly to calculate each time
         */
        int256 newTotalQSquared;
        for (uint256 i; i < initShares.length; i++) {
            /**
             * We enforce that bucketIds are strictly increasing.
             * Otherwise traders could pass the same bucketId multiple times with differen share amounts.
             * This is a problem as it would cause kappa to be larger than it should be for all following bets.
             */
            if (i > 0 && initBucketIds[i] <= initBucketIds[i - 1]) revert BucketIdsNotStrictlyIncreasing();
            newTotalQSquared += initShares[i] * initShares[i];
        }
        totalQSquared = newTotalQSquared;

        /**
         * kappa is the constant used in the cost function C(q) = κ * sqrt(Σq²)
         * It is set to the initial market budget divided by the square root of the sum of initial totalQSquared
         */
        kappa = convert(convert(initBetValue).div((convert(newTotalQSquared)).sqrt()));
        if (kappa <= 0) revert InvalidKappa();

        // Update the markets outcome token holdings for the initial prediction
        _updateHoldings(initiator, initBucketIds, initShares);
    }

    // ----------------------------------------------------------------
    // Public mechanism functions
    // ----------------------------------------------------------------

    /// @inheritdoc IOnitInfiniteOutcomeDPMMechanism
    function calculateCostOfTrade(int256[] memory bucketIds, int256[] memory shares)
        public
        view
        returns (int256, int256)
    {
        // Calculate cost: C(q) = κ * √(Σq_j²)
        SD59x18 existingCost = sd(_costPotential(totalQSquared));

        // Calculate new cost: C(q') = κ * √(Σq'²)
        (int256 newCost, int256 newTotalQSquared) = _costFunction(bucketIds, shares);

        // Difference in cost function is what the trader must pay
        SD59x18 costDiff = sd(newCost).sub(existingCost);

        return (costDiff.unwrap(), newTotalQSquared);
    }

    // ----------------------------------------------------------------
    // Internal functions
    // ----------------------------------------------------------------

    /**
     * @notice Calculate the cost potential of a position: C(q) = κ * √(Σq²)
     *
     * @param sumQSquared The sum of the squares of the outcome tokens in each bucket
     *
     * @return cost The cost of the position
     */
    function _costPotential(int256 sumQSquared) internal view returns (int256) {
        return convert(convert(kappa).mul((convert(sumQSquared)).sqrt()));
    }

    /**
     * @notice Calculate the cost function for an updated position: C(q') = κ * √(Σq'²)
     *
     * @dev Where q' is the number of outstanding outcome tokens in the sustem after the trade
     *
     * @param bucketIds The bucket IDs for the trader's prediction
     * @param shares The shares for the trader's prediction
     *
     * @return cost The cost of the position
     */
    function _costFunction(int256[] memory bucketIds, int256[] memory shares) internal view returns (int256, int256) {
        /**
         * C(q) = κ * √(Σq_j²)
         * C(q') = κ * √(Σ(q_j + Δq_j)²)
         *
         * It would be expensive to calculate the sum over all outcome buckets (j) every time we need it. So we keep
         * track of Σq_j² in totalQSquared
         *
         * This removes the need to calculate totalQSquared, and also lets us simplify the calculation of C(q')
         *
         * Let Q² = Σq_j²
         * Let Q'² = Σ(q_j + Δq_j)² = Σ(q_j² + 2 * q_j * Δq_j + (Δq_j)²)
         *
         * Q'² - Q² = Σ(2 * q_j * Δq_j + (Δq_j)²) = Σ(Δq_j * (2 * q_j + Δq_j)) [1] [2]
         *
         * [1] Combined in this way since we are summing both over j (total outcome buckets)
         * [2] Since Δq_j is 0 outside the traders prediction range, we can loop only over this range
         *
         * Q'² = Q² + Σ(Δq_j * (2 * q_j + Δq_j)) [3]
         *
         * [3] This sum is now not over all j, but just the traders prediction range
         *
         * C(q') = κ * √(Q² + Σ(Δq_j * (2 * q_j + Δq_j)))
         */
        // Get exisitng q for the buckets the trader will contribute to
        int256[] memory qInInterval = _getOutstandingSharesInBuckets(bucketIds);

        // Σ(Δq_j * (2 * q_j + Δq_j))
        int256 updateOverTradersInterval;
        for (uint256 i; i < shares.length; i++) {
            /**
             * We enforce that bucketIds are strictly increasing.
             * Otherwise traders could pass the same bucketId multiple times with differen share amounts.
             * This is a problem as the balance checks below are carried out on the current state of the outcome tokens.
             * Passing the same bucket could safely pass these checks, then cause over/underflow when writing the values
             * to storage later.
             * Rather than increasing gas by dealing with this in code, we revert.
             * There is no good reason not to pass bucketIds in increasing order.
             */
            if (i > 0 && bucketIds[i] <= bucketIds[i - 1]) revert BucketIdsNotStrictlyIncreasing();

            /**
             * We are comfortable doing this operation without prb math as we know even the worst case will not overflow
             * int256 since shares[i] and qInInterval[i] are restricted to type(uint80).max
             */
            updateOverTradersInterval += shares[i] * (2 * qInInterval[i] + shares[i]);
        }

        // Q'² = Q² + Σ(Δq_j * (2 * q_j + Δq_j))
        int256 newTotalQSquared = totalQSquared + updateOverTradersInterval;

        // Calculate cost: C(q') = κ * sqrt(Σq'²)
        int256 newCost = _costPotential(newTotalQSquared);

        return (newCost, newTotalQSquared);
    }
}
