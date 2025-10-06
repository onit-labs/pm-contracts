// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Types
import { MarketConfig } from "@src/types/TOnitInfiniteOutcomeDPM.sol";

// Interfaces
import { IOnitMarketOrderRouter } from "@src/interfaces/IOnitMarketOrderRouter.sol";
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";

interface IOnitFactory {
    /// @notice Address of the implementation contract that will be cloned
    function implementation() external view returns (address);

    /// @notice The order router for ERC20 and ERC1155 transfers
    function orderRouter() external view returns (IOnitMarketOrderRouter);

    /**
     * @notice Create a new OnitInfiniteOutcomeDPM market
     *
     * @param initiator The address of the market creator
     * @param salt The salt for the market
     * @param seededFunds The amount of funds to seed the market with
     * @param initialBetSize The initial bet size
     * @param marketConfig The configuration for the market
     * @param initialBucketIds The initial bucket ids for the market
     * @param initialShares The initial shares for the market
     *
     * @return market The address of the newly created market
     */
    function createMarket(
        address initiator,
        uint256 salt,
        uint256 seededFunds,
        uint256 initialBetSize,
        MarketConfig memory marketConfig,
        int256[] memory initialBucketIds,
        int256[] memory initialShares,
        bytes memory orderRouterInitData
    )
        external
        payable
        returns (OnitInfiniteOutcomeDPM market);
}
