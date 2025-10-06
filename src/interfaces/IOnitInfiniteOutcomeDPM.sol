// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { TokenType } from "@src/types/TOnitIODPMOrderManager.sol";
import { BetStatus, MarketConfig, MarketInitData, TraderStake } from "@src/types/TOnitInfiniteOutcomeDPM.sol";

interface IOnitInfiniteOutcomeDPM {
    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    /// Configuration Errors
    error AlreadyInitialized();
    error BettingCutoffOutOfBounds();
    error MarketCreatorCommissionBpOutOfBounds();
    /// Trading Errors
    error BettingCutoffPassed();
    /// Payment/Withdrawal Errors
    error RejectFunds();
    error WithdrawalDelayPeriodNotPassed();

    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    /// Market Lifecycle Events
    event MarketInitialized(
        address indexed initiator, address indexed currency, TokenType currencyType, uint256 initialBacking
    );
    event BettingCutoffUpdated(uint256 bettingCutoff);
    /// Admin Events
    event CollectedProtocolFee(address indexed receiver, uint256 protocolFee);
    event CollectedMarketCreatorFee(address indexed receiver, uint256 marketCreatorFee);
    /// Trading Events
    event CollectedPayout(address indexed predictor, uint256 payout);
    event CollectedVoidedFunds(address indexed predictor, uint256 totalRepayment);

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// Total amount the trader has bet across all predictions and their NFT
    //function tradersStake(address trader) external view returns (TraderStake memory);

    /// Each predictor gets 1 NFT per market, we track the next tokenId to mint
    function nextNftTokenId() external view returns (uint256);
    /// Timestamp after which no more bets can be placed (0 = no cutoff)
    function bettingCutoff() external view returns (uint256);
    /// Total payout pool when the market is resolved
    function totalPayout() external view returns (uint256);
    /// Number of shares at the resolved outcome
    function winningBucketSharesAtClose() external view returns (int256);
    /// Total stake across all traders with an open position
    function totalOpenStake() external view returns (uint256);

    /// Protocol fee collected, set at market close
    function protocolFee() external view returns (uint256);
    /// The receiver of the market creator fees
    function marketCreatorFeeReceiver() external view returns (address);
    /// The (optional) market creator commission rate in basis points of 10000 (400 = 4%)
    function marketCreatorCommissionBp() external view returns (uint256);
    /// The market creator fee, set at market close
    function marketCreatorFee() external view returns (uint256);

    /// The name of the market
    function name() external view returns (string memory);
    /// The symbol of the market
    function symbol() external view returns (string memory);
    /// The question traders are predicting
    function marketQuestion() external view returns (string memory);

    /// Protocol commission rate in basis points of 10000 (400 = 4%)
    function PROTOCOL_COMMISSION_BP() external view returns (uint256);
    /// Maximum market creator commission rate (4%)
    function MAX_MARKET_CREATOR_COMMISSION_BP() external view returns (uint256);
    /// The version of the market
    function VERSION() external view returns (string memory);

    // ----------------------------------------------------------------
    // Initialization Functions
    // ----------------------------------------------------------------

    /**
     * @notice Initialize the market contract
     *
     * @dev This function can only be called once when the proxy is first deployed
     *
     * @param initData The market initialization data
     */
    function initialize(MarketInitData memory initData) external payable;

    // ----------------------------------------------------------------
    // Admin Functions
    // ----------------------------------------------------------------

    /**
     * @notice Set the resolved outcome, closing the market
     *
     * @param _resolvedOutcome The resolved value of the market
     */
    function resolveMarket(int256 _resolvedOutcome) external;

    /**
     * @notice Update the resolved outcome
     *
     * @param _resolvedOutcome The new resolved outcome
     *
     * @dev This is used to update the resolved outcome after the market has been resolved
     *      It is designed to real with disputes about the outcome.
     *      Can only be called:
     *      - By the owner
     *      - If the market is resolved
     *      - If the withdrawl delay period is open
     */
    function updateResolution(int256 _resolvedOutcome) external;

    /**
     * @notice Update the betting cutoff
     *
     * @param _bettingCutoff The new betting cutoff
     *
     * @dev Can only be called by the Onit factory owner
     * @dev This enables the owner to extend the betting period, or close betting early without resolving the market
     * - It allows for handling unexpected events that delay the market resolution criteria being confirmed
     * - This function should be made more robust in future versions
     */
    function updateBettingCutoff(uint256 _bettingCutoff) external;

    /**
     * @notice Withdraw protocol fees from the contract
     *
     * @param receiver The address to receive the fees
     */
    function withdrawProtocolFees(address receiver) external;
    /**
     * @notice Withdraw the market creator fees
     *
     * @dev Can only be called if the market is resolved and the withdrawal delay period has passed
     * @dev Not guarded since all parameters are pre-set, enabling automatic fee distribution to creators
     */
    function withdrawMarketCreatorFees() external;

    /**
     * @notice Withdraw all remaining funds from the contract
     *      - Can not be called if market is open
     *      - Can not be called if 2 x withdrawal delay period has not passed
     */
    function withdraw() external;

    /**
     * @notice Set the URI for the market ERC1155 token
     *
     * @param newUri The new URI
     */
    function setUri(string memory newUri) external;

    // ----------------------------------------------------------------
    // Public market functions
    // ----------------------------------------------------------------

    /**
     * @notice Buy shares in the market for a given outcome
     *
     * @dev Trader specifies the outcome outcome tokens they want exposure to, and if they provided a sufficent value we
     * mint them
     *
     * @param buyer The address of the buyer
     * @param betAmount The size of the bet
     * @param bucketIds The bucket IDs for the trader's prediction
     * @param shares The shares for the trader's prediction
     */
    function buyShares(address buyer, uint256 betAmount, int256[] memory bucketIds, int256[] memory shares)
        external
        payable;

    /**
     * @notice Sell a set of shares
     *
     * @dev Burn the trader's outcome tokens in the buckets they want to sell in exchange for their market value
     * This corresponds to the difference in the cost function between where the market is, and where it will be
     * after they burn their shares
     *
     * @param seller The address of the seller
     * @param bucketIds The bucket IDs for the trader's prediction
     * @param shares The shares for the trader's prediction
     */
    function sellShares(address seller, int256[] memory bucketIds, int256[] memory shares) external returns (uint256);

    /**
     * @notice Collect the payout for a trader
     *
     * @param trader The address of the trader
     */
    function collectPayout(address trader) external;

    /**
     * @notice Collect the voided funds for a trader
     *
     * @param trader The address of the trader
     */
    function collectVoidedFunds(address trader) external;

    /**
     * @notice Calculate the payout for a trader
     *
     * @param trader The address of the trader
     *
     * @return payout The payout amount
     */
    function calculatePayout(address trader) external view returns (uint256);
}
