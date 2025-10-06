// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Test } from "forge-std/Test.sol";

/**
 * @title IODPMTestConstants
 * @dev Constants related to OnitInfiniteOutcomeDPM
 * -
 * - Market configuration
 * - Market initialization values
 * - Some specific market test values
 * - Dummy arrays for tests that don't need initial bucketIds / shares
 */
contract IODPMTestConstants is Test {
    uint256 internal constant MAX_UINT256 = type(uint256).max;
    uint256 internal constant ONE_ETHER = 1 ether;
    uint256 internal constant HALF_ETHER = 0.5 ether;

    int256 internal constant SCALE = 1e18;
    int256 internal constant BASE_SHARES = 1e7;
    uint256 internal constant CREATE_MARKET_SALT = 1;

    /**
     * Market Config
     */
    address internal MARKET_CREATOR_FEE_RECEIVER = makeAddr("marketCreatorFeeReceiver");
    uint256 internal constant NO_MARKET_CREATOR_COMMISSION_BPS = 0;
    uint256 internal constant MARKET_CREATOR_COMMISSION_BPS = 200;
    uint256 internal constant MAX_MARKET_CREATOR_COMMISSION_BPS = 400;

    uint256 internal constant NO_BETTING_CUTOFF = 0;
    uint256 internal BETTING_CUTOFF_ONE_DAY = block.timestamp + 1 days;
    uint256 internal constant NO_WITHDRAWAL_DELAY_PERIOD = 0;
    uint256 internal constant WITHDRAWAL_DELAY_PERIOD_ONE_DAY = 1 days;

    uint256 internal constant MIN_BET_SIZE = 0.0001 ether;
    uint256 internal constant MAX_BET_SIZE = 1 ether;

    int256 internal constant OUTCOME_UNIT = 1000;

    string internal constant MARKET_QUESTION = "Wen eth moon?";
    string internal constant MARKET_URI = "https://onit.fun/m/";
    string internal constant MARKET_URI_0 = "https://onit.fun/m/0";

    address internal MARKET_OWNER = address(this);
    address internal RESOLVER_1 = makeAddr("resolver1");
    address internal RESOLVER_2 = makeAddr("resolver2");
    // -------

    /**
     * Market Initialization Values
     */
    uint256 internal constant UNSEEDED_MARKET = 0;
    // --------

    /**
     * Some specific market test values
     */
    uint256 internal constant FIRST_PREDICTION_ID = 0;
    uint256 internal constant SECOND_PREDICTION_ID = 1;
    uint256 internal constant THIRD_PREDICTION_ID = 2;

    uint256 internal constant INITIAL_BET_VALUE = 0.01 ether;

    // dummy arrays for tests that don't need initial bucketIds / shares
    int256[] internal DUMMY_BUCKET_IDS = [int256(0), int256(1), int256(2), int256(3)];
    int256[] internal DUMMY_SHARES = [int256(1), int256(1), int256(1), int256(1)];
    int256 DUMMY_INITIAL_TOTAL_Q_SQUARED = 4;
}
