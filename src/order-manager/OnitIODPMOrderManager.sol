// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// Misc contracts
import { ERC20 } from "solady/tokens/ERC20.sol";

// Types
import { TokenType } from "@src/types/TOnitIODPMOrderManager.sol";

// Interfaces
import { IOnitIODPMOrderManager } from "@src/interfaces/IOnitIODPMOrderManager.sol";
import { IOnitMarketOrderRouter } from "@src/interfaces/IOnitMarketOrderRouter.sol";

// Onit contracts
import {
    OnitInfiniteOutcomeDPMMechanism
} from "@src/mechanisms/infinite-outcome-DPM/OnitInfiniteOutcomeDPMMechanism.sol";
import { OnitMarketOrderRouter } from "./OnitMarketOrderRouter.sol";

/**
 * @title Onit Infinite Outcome Dynamic Pari-Mutual Order Manager
 * @notice Manages orders for an Onit IODPM, interfacing with the order router for token bets
 */
contract OnitIODPMOrderManager is IOnitIODPMOrderManager, OnitInfiniteOutcomeDPMMechanism {
    // ----------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------

    /// @inheritdoc IOnitIODPMOrderManager
    TokenType public marketTokenType;
    /// @inheritdoc IOnitIODPMOrderManager
    address public marketToken;

    /// @inheritdoc IOnitIODPMOrderManager
    uint256 public minBetSize;
    /// @inheritdoc IOnitIODPMOrderManager
    uint256 public maxBetSize;

    /// @inheritdoc IOnitIODPMOrderManager
    IOnitMarketOrderRouter public onitMarketOrderRouter;

    // ----------------------------------------------------------------
    // Initializer
    // ----------------------------------------------------------------

    function _initializeOrderManager(
        address initiator,
        address initMarketOrderRouter,
        TokenType initCurrencyType,
        address initCurrency,
        uint256 initMinBetSize,
        uint256 initMaxBetSize,
        int256 initOutcomeUnit,
        uint256 initBetValue,
        uint256 seededFunds,
        int256[] memory initBucketIds,
        int256[] memory initShares,
        bytes memory orderRouterInitData
    )
        internal
    {
        onitMarketOrderRouter = IOnitMarketOrderRouter(initMarketOrderRouter);

        marketTokenType = initCurrencyType;
        marketToken = initCurrency;

        minBetSize = initMinBetSize;
        maxBetSize = initMaxBetSize;

        uint256 initialBacking = initBetValue + seededFunds;

        if (marketTokenType == TokenType.NATIVE) {
            if (address(this).balance != uint256(initialBacking)) {
                revert IncorrectInitialBacking(initialBacking, address(this).balance);
            }
        } else if (marketTokenType == TokenType.ERC20) {
            onitMarketOrderRouter.initializeOrderRouterForMarket(
                marketToken, initiator, initialBacking, orderRouterInitData
            );
        } else {
            revert InvalidManagerType();
        }

        _initializeInfiniteOutcomeDPM(initiator, initOutcomeUnit, int256(initBetValue), initBucketIds, initShares);
    }

    // ----------------------------------------------------------------
    // Order Functions
    // ----------------------------------------------------------------

    function _makeBuyOrder(address buyer, uint256 betAmount, int256[] memory bucketIds, int256[] memory shares)
        internal
    {
        if (betAmount < minBetSize || betAmount > maxBetSize) revert BetValueOutOfBounds();

        // Calculate shares for each bucket
        (int256 costDiff, int256 newTotalQSquared) = calculateCostOfTrade(bucketIds, shares);

        /**
         * costDiff may be negative, but we know that for a buy both it and betAmount should be positive
         * if it happened to be negative, casting it to uint256 would result in a number larger than they would ever
         * need to send, so the buy order would revert. This makes the casting here safe.
         */
        if (betAmount != uint256(costDiff)) {
            revert IncorrectBetValue(uint256(costDiff), betAmount);
        }

        // Track the latest totalQSquared so we don't need to recalculate it
        totalQSquared = newTotalQSquared;
        // Update the markets outcome token holdings
        _updateHoldings(buyer, bucketIds, shares);

        emit BoughtShares(buyer, costDiff, newTotalQSquared);
    }

    function _makeSellOrder(address seller, int256[] memory bucketIds, int256[] memory shares)
        internal
        returns (int256)
    {
        /**
         * We only allow negative share changes, so if any shares are positive, revert
         * This is because we don't want to allow traders to increase their position using this function
         * The function is not payable and we don't check they have provided enough funds to cover the cost of the
         * increase
         * TODO: move this to the calculateCostOfTrade function to avoid extra loop
         */
        for (uint256 i; i < shares.length; i++) {
            if (shares[i] > 0) revert InvalidSharesValue();
        }

        (int256 costDiff, int256 newTotalQSquared) = calculateCostOfTrade(bucketIds, shares);

        // If the cost difference is positive, revert
        // Otherwise this would mean they need to pay to sell their position
        if (costDiff > 0) revert NothingToPay();

        _updateHoldings(seller, bucketIds, shares);

        // Set new market values
        totalQSquared = newTotalQSquared;

        // Transfer the trader's payout
        // We use -costDiff as the payout is the difference in cost between the trader's prediction and the existing
        // cost. We know this is negative as we checked for that above, so negating it will give a positive value
        // which corrosponds to how much the market should pay the trader
        _sendFunds(seller, uint256(-costDiff));

        emit SoldShares(seller, costDiff, newTotalQSquared);

        return costDiff;
    }

    // ----------------------------------------------------------------
    // Fund Management Functions
    // ----------------------------------------------------------------

    function getBalance() public view returns (uint256) {
        if (marketTokenType == TokenType.NATIVE) {
            return address(this).balance;
        } else {
            return ERC20(marketToken).balanceOf(address(this));
        }
    }

    function _sendFunds(address receiver, uint256 amount) internal {
        if (marketTokenType == TokenType.NATIVE) {
            (bool success,) = receiver.call{ value: amount }("");
            if (!success) revert TransferFailed();
        } else {
            bool success = ERC20(marketToken).transfer(receiver, amount);
            if (!success) revert TransferFailed();
        }
    }

    function _withdrawRemainingFunds(address receiver) internal {
        if (marketTokenType == TokenType.NATIVE) {
            (bool success,) = receiver.call{ value: address(this).balance }("");
            if (!success) revert TransferFailed();
        } else {
            bool success = ERC20(marketToken).transfer(receiver, ERC20(marketToken).balanceOf(address(this)));
            if (!success) revert TransferFailed();
        }
    }
}
