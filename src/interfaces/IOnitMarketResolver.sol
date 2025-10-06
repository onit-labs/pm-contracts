// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IOnitMarketResolver {
    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event MarketResolved(int256 actualOutcome, int256 totalSharesAtOutcome, uint256 totalPayout);
    event MarketResolutionUpdated(int256 newResolution);
    event MarketVoided(uint256 timestamp);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    /// Initialisation Errors
    error OnitFactoryNotSet();
    error ResolversNotSet();
    /// Admin Errors
    error OnlyOnitFactoryOwner();
    error OnlyResolver();
    /// Market State Errors
    error DisputePeriodPassed();
    error MarketIsOpen();
    error MarketIsResolved();
    error MarketIsVoided();

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// Address of the Onit factory where Onit owner address is stored
    function onitFactory() external view returns (address);

    /**
     * Withdrawal delay period after market is resolved
     * This serves multiple functions:
     * - Sets a dispute period within which the resolved outcome can be contested and changed
     * - Prevents traders from withdrawing their funds until the dispute period has passed
     * - Prevents the market creator from withdrawing funds before traders have had a chance to collect payouts
     *
     * @dev Measured in seconds (eg. 2 days = 172800)
     */
    function withdrawlDelayPeriod() external view returns (uint256);

    /// Timestamp when the market is resolved
    function resolvedAtTimestamp() external view returns (uint256);
    /// Final correct value resolved by the market owner
    function resolvedOutcome() external view returns (int256);
    /// The bucket ID the resolved outcome falls into (see OnitInfiniteOutcomeDPMOutcomeDomain for details about
    /// buckets)
    function resolvedBucketId() external view returns (int256);
    /// Flag that market is voided, allowing for traders to collect their funds
    function marketVoided() external view returns (bool);

    // ----------------------------------------------------------------
    // Functions
    // ----------------------------------------------------------------

    /**
     * @notice Void the market, allowing traders to collect their funds
     */
    function voidMarket() external;

    /**
     * @notice Get the resolvers
     * @return resolvers The resolvers
     */
    function getResolvers() external view returns (address[] memory);

    /**
     * @notice Check if an address is a resolver
     * @param _resolver The address to check
     * @return isResolver Whether the address is a resolver
     */
    function isResolver(address _resolver) external view returns (bool);

    /**
     * @notice Get the owner of the Onit factory
     * @return owner The owner of the Onit factory
     */
    function onitFactoryOwner() external view returns (address);
}
