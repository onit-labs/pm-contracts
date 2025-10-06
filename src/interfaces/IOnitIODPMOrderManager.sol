// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Types
import { TokenType } from "@src/types/TOnitIODPMOrderManager.sol";

// Interfaces
import { IOnitMarketOrderRouter } from "@src/interfaces/IOnitMarketOrderRouter.sol";

interface IOnitIODPMOrderManager {
    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event BoughtShares(address indexed predictor, int256 costDiff, int256 newTotalQSquared);
    event OrderProcessed(address buyer, uint256 amount);
    event SoldShares(address indexed predictor, int256 costDiff, int256 newTotalQSquared);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    /// Configuration Errors
    error IncorrectInitialBacking(uint256 expected, uint256 actual);
    error InvalidManagerType();
    /// Betting Errors
    error NotFromOrderRouter();
    error BetValueOutOfBounds();
    error IncorrectBetValue(uint256 expected, uint256 actual);
    error InvalidSharesValue();
    /// Withdrawal Errors
    error NothingToPay();
    error TransferFailed();

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @notice The currency of the market
    function marketTokenType() external view returns (TokenType);
    /// @notice The address of the token used to buy
    function marketToken() external view returns (address);

    /// @notice The minimum bet size
    function minBetSize() external view returns (uint256);
    /// @notice The maximum bet size
    function maxBetSize() external view returns (uint256);

    /**
     * @notice The order router for the market
     * @dev This is used to handle the token approvals and transfers
     */
    function onitMarketOrderRouter() external view returns (IOnitMarketOrderRouter);
}
