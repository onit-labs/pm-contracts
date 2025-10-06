// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { TokenType } from "@src/types/TOnitIODPMOrderManager.sol";

enum BetStatus {
    NONE,
    OPEN,
    CLOSED
}

/**
 * TraderStake is the amount they have put into the market, and the NFT they were minted in return
 * Traders can:
 * - Sell their position and leave the market (which makes sense if the traders position is worth more than their
 * stake)
 * - Redeem their position when the market closes
 * - Reclaim their stake if the market is void
 * - Lose their stake if their prediction generates no return
 */
struct TraderStake {
    uint256 totalStake;
    uint256 nftId;
    BetStatus betStatus;
}

/// Market configuration params passed to initialize the market
struct MarketConfig {
    /// The currency type (NATIVE, ERC20, CUSTOM)
    TokenType currencyType;
    /// The address of the currency used to make bets (address(0) for native)
    address currency;
    address marketCreatorFeeReceiver;
    uint256 marketCreatorCommissionBp;
    uint256 bettingCutoff;
    uint256 withdrawlDelayPeriod;
    uint256 minBetSize;
    uint256 maxBetSize;
    int256 outcomeUnit;
    string marketQuestion;
    string marketUri;
    address[] resolvers;
}

/// Market initialization data
struct MarketInitData {
    /// Onit factory contract with the Onit admin address
    address onitFactory;
    /// Onit market order router contract (used for token transfers)
    address orderRouter;
    /// Address that gets the initial prediction
    address initiator;
    /// Seeded funds to initialize the market pot
    uint256 seededFunds;
    /// Initial bet size
    uint256 initialBetSize;
    /// Bucket ids for the initial prediction
    int256[] initialBucketIds;
    /// Shares for the initial prediction
    int256[] initialShares;
    /// order router initialization data
    bytes orderRouterInitData;
    /// Market configuration
    MarketConfig config;
}

