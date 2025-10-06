// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @notice The target where an allowance is set
 *
 * @param TOKEN Allowance can be spent on any market with this token (more general)
 * @param MARKET Allowance can only be spent on this market (more specific)
 */
enum AllowanceTargetType {
    TOKEN,
    MARKET
}

enum Side {
    BUY,
    SELL
}

/**
 * @notice Details of a market
 * @dev marketAdmin is the address that can set allowances for the market
 * @dev marketToken is the address of the token that the market uses as its betting currency
 */
struct MarketDetails {
    address marketAdmin;
    address marketToken;
}
