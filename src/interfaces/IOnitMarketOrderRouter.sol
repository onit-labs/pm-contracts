// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { AllowanceTargetType, MarketDetails, Side } from "../types/TOnitMarketOrderRouter.sol";

interface IOnitMarketOrderRouter {
    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event AllowanceUpdated(
        address indexed allower,
        address indexed spender,
        address indexed target,
        AllowanceTargetType targetType,
        uint256 amount
    );

    event OrderExecuted(
        address indexed market,
        address indexed trader,
        Side indexed side,
        uint256 amount,
        int256[] bucketIds,
        int256[] shares
    );

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error InsufficientAllowance(uint256 remainingAmount);
    error InsufficientTokenAllowance(uint256 currentAllowance, int256 requestedChange);
    error InvalidAllowanceSpender();
    error ArrayLengthMismatch();
    error MulticallOrdersMustUseSameToken();
    error AmountTooLarge();
    error TransferFailed();

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    // function marketDetails(address market) external view returns (MarketDetails memory);
    // function allowances(address allower, address spender, address target) external view returns (uint256);

    // ----------------------------------------------------------------
    // Initialisation functions
    // ----------------------------------------------------------------

    function initializeOrderRouterForMarket(
        address marketToken,
        address initiator,
        uint256 initialBacking,
        bytes memory orderRouterInitData
    )
        external;

    // ----------------------------------------------------------------
    // Allowance functions
    // ----------------------------------------------------------------

    /**
     * @notice Set token allowances for spenders on a market
     *
     * @dev If an individual wants to set an allowance for the router, they just call the token contract directly
     *
     * @param market The market to set allowances for
     * @param spendDeadline The deadline for the permit
     * @param v The v part of the permit signature
     * @param r The r part of the permit signature
     * @param s The s part of the permit signature
     * @param spenders The spenders to set allowances for
     * @param amounts The amounts to set allowances for
     */
    function setAllowances(
        AllowanceTargetType allowanceTargetType,
        address market,
        uint256 spendDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address[] memory spenders,
        uint256[] memory amounts
    )
        external;

    /**
     * @notice Reserve allowance for deployment
     * @dev This is used to reserve allowance for a market deployment
     *      This is useful for cases where the market is deployed WITHOUT a permit signature
     *      The user calls approve directly on the token contract for the order router
     *      Then they call this function to reserve the allowance for the deployment
     *      This prevents the anyone from initialising a market with a users existing allowance on the order router
     *
     * @param market Market address
     * @param amount Amount to reserve
     */
    function reserveAllowanceForDeployment(address market, uint256 amount) external;

    // ----------------------------------------------------------------
    // Order execution functions
    // ----------------------------------------------------------------

    /**
     * @notice Execute order for a market
     *
     * @param market Market address
     * @param buyer Buyer address
     * @param betAmount Amount to spend
     * @param bucketIds Bucket IDs
     * @param shares Shares in each bucket
     * @param orderData Encoded data containing permit data and allowed addresses
     */
    function executeOrder(
        address market,
        address buyer,
        uint256 betAmount,
        int256[] memory bucketIds,
        int256[] memory shares,
        bytes memory orderData
    )
        external
        payable;

    /**
     * @notice Execute multiple orders
     *
     * @param buyer Buyer address
     * @param markets Markets to execute orders on
     * @param betAmounts Amounts to spend on each market
     * @param bucketIds Bucket IDs for each market
     * @param shares Shares for each market
     * @param orderData Encoded permit data for the batch (deadline, v, r, s)
     *
     * @custom:warning
     * Currently limited to only executing orders on markets which use the same token.
     * This is so that we can use a single permit sig for the batch if needed
     */
    function executeMultipleOrders(
        address buyer,
        address[] memory markets,
        uint256[] memory betAmounts,
        int256[][] memory bucketIds,
        int256[][] memory shares,
        bytes memory orderData
    )
        external
        payable;

    /**
     * @notice Execute order from allowance
     *
     * @param buyer Buyer address
     * @param market Market address
     * @param amount Amount to spend
     * @param bucketIds Bucket IDs
     * @param shares Shares in each bucket
     *
     * @dev Can be used by an authorised spender or the market admin to draw down an allowance
     * First we reduce the market specific allowance, then the token allowance if needed
     */
    function executeOrderFromAllowance(
        address buyer,
        address market,
        uint256 amount,
        int256[] memory bucketIds,
        int256[] memory shares
    )
        external;

    /**
     * @notice Execute sell order for a market
     *
     * @param market Market address
     * @param seller Seller address
     * @param bucketIds Bucket IDs
     * @param shares Shares in each bucket (should be negative for selling)
     */
    function executeSellOrder(address market, address seller, int256[] memory bucketIds, int256[] memory shares)
        external;
}
