// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Misc
import { Ownable } from "solady/auth/Ownable.sol";
// Interfaces
import { IOnitFactory } from "../interfaces/IOnitFactory.sol";
import { IOnitMarketResolver } from "../interfaces/IOnitMarketResolver.sol";

/**
 * @title Onit Market Resolver
 *
 * @author Onit Labs (https://github.com/onit-labs)
 *
 * @notice Contract storing resolution logic and admin addresses
 */
contract OnitMarketResolver is IOnitMarketResolver {
    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @inheritdoc IOnitMarketResolver
    address public onitFactory;

    /// @inheritdoc IOnitMarketResolver
    uint256 public withdrawlDelayPeriod;

    /// @inheritdoc IOnitMarketResolver
    uint256 public resolvedAtTimestamp;
    /// @inheritdoc IOnitMarketResolver
    int256 public resolvedOutcome;
    /// @inheritdoc IOnitMarketResolver
    int256 public resolvedBucketId;

    /// @inheritdoc IOnitMarketResolver
    bool public marketVoided;

    /// Array of addresses who can resolve the market
    address[] private resolvers;

    // ----------------------------------------------------------------
    // Initialization
    // ----------------------------------------------------------------

    function _initializeOnitMarketResolver(
        uint256 initWithdrawlDelayPeriod,
        address initOnitFactory,
        address[] memory initResolvers
    )
        internal
    {
        if (initOnitFactory == address(0)) revert OnitFactoryNotSet();
        if (initResolvers.length == 0 || initResolvers[0] == address(0)) revert ResolversNotSet();

        withdrawlDelayPeriod = initWithdrawlDelayPeriod;

        onitFactory = initOnitFactory;

        resolvers = initResolvers;
    }

    // ----------------------------------------------------------------
    // Modifiers
    // ----------------------------------------------------------------

    modifier onlyOnitFactoryOwner() {
        if (msg.sender != onitFactoryOwner()) revert OnlyOnitFactoryOwner();
        _;
    }

    modifier onlyResolver() {
        if (!isResolver(msg.sender)) revert OnlyResolver();
        _;
    }

    // ----------------------------------------------------------------
    // OnitFactoryOwner functions
    // ----------------------------------------------------------------

    function voidMarket() external onlyOnitFactoryOwner {
        marketVoided = true;

        emit MarketVoided(block.timestamp);
    }

    // ----------------------------------------------------------------
    // Getters
    // ----------------------------------------------------------------

    /// @inheritdoc IOnitMarketResolver
    function getResolvers() external view returns (address[] memory) {
        return resolvers;
    }

    /// @inheritdoc IOnitMarketResolver
    function isResolver(address _resolver) public view returns (bool) {
        /**
         * This is less efficient than a resolvers mapping, but:
         * - resolvers should never be a long array
         * - This function is rarely called
         * - Having the full resolvers address array in storage is good for other clients
         */
        for (uint256 i; i < resolvers.length; i++) {
            if (resolvers[i] == _resolver) return true;
        }
        return false;
    }

    /// @inheritdoc IOnitMarketResolver
    function onitFactoryOwner() public view returns (address) {
        return Ownable(onitFactory).owner();
    }

    // ----------------------------------------------------------------
    // Internal functions
    // ----------------------------------------------------------------

    function _setResolvedOutcome(int256 _resolvedOutcome, int256 _resolvedBucketId) internal {
        if (resolvedAtTimestamp != 0) revert MarketIsResolved();
        if (marketVoided) revert MarketIsVoided();

        resolvedAtTimestamp = block.timestamp;
        resolvedOutcome = _resolvedOutcome;
        resolvedBucketId = _resolvedBucketId;
    }

    function _updateResolvedOutcome(int256 _resolvedOutcome, int256 _resolvedBucketId) internal {
        if (resolvedAtTimestamp == 0) revert MarketIsOpen();
        if (block.timestamp > resolvedAtTimestamp + withdrawlDelayPeriod) revert DisputePeriodPassed();
        if (marketVoided) revert MarketIsVoided();

        resolvedOutcome = _resolvedOutcome;
        resolvedBucketId = _resolvedBucketId;

        emit MarketResolutionUpdated(_resolvedOutcome);
    }
}
