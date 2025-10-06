// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IOnitInfiniteOutcomeDPMMechanism {
    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    /// Initialization Errors
    error InvalidKappa();
    /// Trading Errors
    error BucketIdsNotStrictlyIncreasing();

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /**
     * @notice The sum of the squares of each outcome token
     *
     * @dev We use this in the cost function of the DPM.
     * Since it would be costly to calculate each time, we store it.
     */
    function totalQSquared() external view returns (int256);

    /**
     * @notice The kappa constant for the cost function: C(q) = κ * sqrt(Σq²)
     *
     * @dev κ is set to the initial market budget divided by the square root of the sum of initial totalQSquared
     */
    function kappa() external view returns (int256);

    // ----------------------------------------------------------------
    // Public market functions
    // ----------------------------------------------------------------

    /**
     * @notice Calculate the cost of a trader's prediction: C(q') - C(q)
     *
     * @dev Where q' is the new total q after the trader's prediction.
     *
     * @param bucketIds The bucket IDs for the trader's prediction
     * @param shares The shares for the trader's prediction
     *
     * @return costDiff The difference in cost between the trader's prediction and the existing cost
     */
    function calculateCostOfTrade(int256[] memory bucketIds, int256[] memory shares)
        external
        view
        returns (int256, int256);
}
