// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Misc Utils
import { convert as convertToUD, convert as convertBack, div, mul } from "prb-math/UD60x18.sol";
import { ERC1155 } from "solady/tokens/ERC1155.sol";
import { LibString } from "./utils/LibString.sol";

// Types
import { TokenType } from "@src/types/TOnitIODPMOrderManager.sol";
import { BetStatus, MarketInitData, TraderStake } from "@src/types/TOnitInfiniteOutcomeDPM.sol";

// Interfaces
import { IOnitInfiniteOutcomeDPM } from "@src/interfaces/IOnitInfiniteOutcomeDPM.sol";

// Onit contracts
import { OnitIODPMOrderManager } from "./order-manager/OnitIODPMOrderManager.sol";
import { OnitMarketResolver } from "./resolvers/OnitMarketResolver.sol";

/**
 * @title Onit Infinite Outcome Dynamic Parimutual Market
 *
 * @author Onit Labs (https://github.com/onit-labs)
 *
 * @notice Decentralized prediction market suitable for binary, numerical, multiple choice, and more questions.
 *
 * @dev Notes on the market:
 * - See OnitInfiniteOutcomeDPMMechanism for explanation of the mechanism
 * - See OnitInfiniteOutcomeDPMOutcomeDomain for explanation of the outcome domain and token tracking
 */
contract OnitInfiniteOutcomeDPM is IOnitInfiniteOutcomeDPM, OnitIODPMOrderManager, OnitMarketResolver, ERC1155 {
    /// Total amount the trader has bet across all predictions and their NFT
    mapping(address trader => TraderStake stake) public tradersStake;

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    uint256 public nextNftTokenId;
    /// @inheritdoc IOnitInfiniteOutcomeDPM
    uint256 public bettingCutoff;
    /// @inheritdoc IOnitInfiniteOutcomeDPM
    uint256 public totalPayout;
    /// @inheritdoc IOnitInfiniteOutcomeDPM
    int256 public winningBucketSharesAtClose;
    /// @inheritdoc IOnitInfiniteOutcomeDPM
    uint256 public totalOpenStake;

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    uint256 public protocolFee;
    /// @inheritdoc IOnitInfiniteOutcomeDPM
    address public marketCreatorFeeReceiver;
    /// @inheritdoc IOnitInfiniteOutcomeDPM
    uint256 public marketCreatorCommissionBp;
    /// @inheritdoc IOnitInfiniteOutcomeDPM
    uint256 public marketCreatorFee;

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    string public name = "Onit Prediction Market";
    /// @inheritdoc IOnitInfiniteOutcomeDPM
    string public symbol = "ONIT";
    /// @inheritdoc IOnitInfiniteOutcomeDPM
    string public marketQuestion;
    /// ERC1155 token uri
    string private _uri = "https://onit.fun/";

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    uint256 public constant PROTOCOL_COMMISSION_BP = 400;
    /// @inheritdoc IOnitInfiniteOutcomeDPM
    uint256 public constant MAX_MARKET_CREATOR_COMMISSION_BP = 400;
    /// @inheritdoc IOnitInfiniteOutcomeDPM
    string public constant VERSION = "0.0.4";

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    /**
     * @notice Construct the implementation of the market
     *
     * @dev Initialize owner to a dummy address to prevent implementation from being initialized
     */
    constructor() {
        // Used as flag to prevent implementation from being initialized, and to prevent bets
        marketVoided = true;
    }

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    function initialize(MarketInitData memory initData) external payable {
        uint256 initialBetValue = initData.initialBetSize;

        // Prevents the implementation from being initialized
        if (marketVoided) revert AlreadyInitialized();
        if (initialBetValue < initData.config.minBetSize || initialBetValue > initData.config.maxBetSize) {
            revert BetValueOutOfBounds();
        }
        // If cutoff is set, it must be greater than now
        if (initData.config.bettingCutoff != 0 && initData.config.bettingCutoff <= block.timestamp) {
            revert BettingCutoffOutOfBounds();
        }
        if (initData.config.marketCreatorCommissionBp > MAX_MARKET_CREATOR_COMMISSION_BP) {
            revert MarketCreatorCommissionBpOutOfBounds();
        }

        _initializeOrderManager(
            initData.initiator,
            initData.orderRouter,
            initData.config.currencyType,
            initData.config.currency,
            initData.config.minBetSize,
            initData.config.maxBetSize,
            initData.config.outcomeUnit,
            initialBetValue,
            initData.seededFunds,
            initData.initialBucketIds,
            initData.initialShares,
            initData.orderRouterInitData
        );

        _initializeOnitMarketResolver(
            initData.config.withdrawlDelayPeriod, initData.onitFactory, initData.config.resolvers
        );

        // Set market description
        marketQuestion = initData.config.marketQuestion;
        // Set ERC1155 token uri
        _uri = initData.config.marketUri;
        // Set time limit for betting
        bettingCutoff = initData.config.bettingCutoff;
        // Set market creator
        marketCreatorFeeReceiver = initData.config.marketCreatorFeeReceiver;
        // Set market creator commission rate
        marketCreatorCommissionBp = initData.config.marketCreatorCommissionBp;

        // Mint the trader a prediction NFT
        _mint(initData.initiator, nextNftTokenId, 1, "");
        // Update the traders stake
        tradersStake[initData.initiator] =
            TraderStake({ totalStake: initialBetValue, nftId: nextNftTokenId, betStatus: BetStatus.OPEN });

        // Track initial total open stake
        totalOpenStake = initialBetValue;

        // Update the prediction count for the next trader
        nextNftTokenId++;

        emit MarketInitialized(
            initData.initiator,
            initData.config.currency,
            initData.config.currencyType,
            initialBetValue + initData.seededFunds
        );
    }

    // ----------------------------------------------------------------
    // Admin functions
    // ----------------------------------------------------------------

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    function resolveMarket(int256 _resolvedOutcome) external onlyResolver {
        _setResolvedOutcome(_resolvedOutcome, getBucketId(_resolvedOutcome));

        uint256 finalBalance = getBalance();

        // Calculate market maker fee
        uint256 _protocolFee = finalBalance * PROTOCOL_COMMISSION_BP / 10_000;
        protocolFee = _protocolFee;

        uint256 _marketCreatorFee = finalBalance * marketCreatorCommissionBp / 10_000;
        marketCreatorFee = _marketCreatorFee;

        // Calculate total payout pool
        totalPayout = finalBalance - protocolFee - marketCreatorFee;

        /**
         * Set the total shares at the resolved outcome, traders payouts are:
         * totalPayout * tradersSharesAtOutcome/totalSharesAtOutcome
         */
        winningBucketSharesAtClose = getBucketOutstandingShares(resolvedBucketId);

        emit MarketResolved(_resolvedOutcome, winningBucketSharesAtClose, totalPayout);
    }

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    function updateResolution(int256 _resolvedOutcome) external onlyOnitFactoryOwner {
        _updateResolvedOutcome(_resolvedOutcome, getBucketId(_resolvedOutcome));
    }

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    function updateBettingCutoff(uint256 _bettingCutoff) external onlyOnitFactoryOwner {
        bettingCutoff = _bettingCutoff;

        emit BettingCutoffUpdated(_bettingCutoff);
    }

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    function withdrawProtocolFees(address receiver) external onlyOnitFactoryOwner {
        if (marketVoided) revert MarketIsVoided();
        if (resolvedAtTimestamp == 0) revert MarketIsOpen();
        if (block.timestamp < resolvedAtTimestamp + withdrawlDelayPeriod) revert WithdrawalDelayPeriodNotPassed();

        uint256 _protocolFee = protocolFee;
        protocolFee = 0;

        _sendFunds(receiver, _protocolFee);

        emit CollectedProtocolFee(receiver, _protocolFee);
    }

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    function withdrawMarketCreatorFees() external {
        if (marketVoided) revert MarketIsVoided();
        if (resolvedAtTimestamp == 0) revert MarketIsOpen();
        if (block.timestamp < resolvedAtTimestamp + withdrawlDelayPeriod) revert WithdrawalDelayPeriodNotPassed();

        uint256 _marketCreatorFee = marketCreatorFee;
        marketCreatorFee = 0;

        _sendFunds(marketCreatorFeeReceiver, _marketCreatorFee);

        emit CollectedMarketCreatorFee(marketCreatorFeeReceiver, _marketCreatorFee);
    }

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    function withdraw() external onlyOnitFactoryOwner {
        if (resolvedAtTimestamp == 0) revert MarketIsOpen();
        if (block.timestamp < resolvedAtTimestamp + 2 * withdrawlDelayPeriod) {
            revert WithdrawalDelayPeriodNotPassed();
        }
        if (marketVoided) revert MarketIsVoided();

        _withdrawRemainingFunds(onitFactoryOwner());
    }

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    function setUri(string memory newUri) external onlyOnitFactoryOwner {
        _uri = newUri;

        emit URI(newUri, 0);
    }

    // ----------------------------------------------------------------
    // Public market functions
    // ----------------------------------------------------------------

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    function buyShares(address buyer, uint256 betAmount, int256[] memory bucketIds, int256[] memory shares)
        external
        payable
    {
        if (msg.sender != address(onitMarketOrderRouter)) revert NotFromOrderRouter();
        if (bettingCutoff != 0 && block.timestamp > bettingCutoff) revert BettingCutoffPassed();
        if (resolvedAtTimestamp != 0) revert MarketIsResolved();
        if (marketVoided) revert MarketIsVoided();

        // If the token is native, ensure betAmount is msg.value
        betAmount = marketTokenType == TokenType.NATIVE ? msg.value : betAmount;

        _makeBuyOrder(buyer, betAmount, bucketIds, shares);

        // If the trader does not already have an NFT, mint one
        if (tradersStake[buyer].betStatus == BetStatus.NONE) {
            _mint(buyer, nextNftTokenId, 1, "");
            tradersStake[buyer].nftId = nextNftTokenId++;
        }
        // Update the traders total stake and status
        tradersStake[buyer].totalStake += betAmount;
        tradersStake[buyer].betStatus = BetStatus.OPEN;
        totalOpenStake += betAmount;
    }

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    function sellShares(address seller, int256[] memory bucketIds, int256[] memory shares) external returns (uint256) {
        if (msg.sender != address(onitMarketOrderRouter)) revert NotFromOrderRouter();
        if (tradersStake[seller].betStatus != BetStatus.OPEN) revert NothingToPay();
        if (resolvedAtTimestamp != 0) revert MarketIsResolved();
        if (marketVoided) revert MarketIsVoided();

        int256 costDiff = _makeSellOrder(seller, bucketIds, shares);

        // Update the traders total stake, subtract the payout and cap at 0
        // Casting to uint256 is safe since costDiff > 0 reverts in _makeSellOrder
        uint256 payout = uint256(-costDiff);
        uint256 currentStake = tradersStake[seller].totalStake;
        uint256 stakeReduction = payout >= currentStake ? currentStake : payout;

        tradersStake[seller].totalStake = currentStake - stakeReduction;
        totalOpenStake -= stakeReduction;

        return payout;
    }

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    function collectPayout(address trader) external {
        if (resolvedAtTimestamp == 0) revert MarketIsOpen();
        if (block.timestamp < resolvedAtTimestamp + withdrawlDelayPeriod) revert WithdrawalDelayPeriodNotPassed();
        if (marketVoided) revert MarketIsVoided();

        // Calculate payout
        uint256 payout = _calculatePayout(trader);

        // If caller has already closed position, or there is nothing to pay, revert
        if (tradersStake[trader].betStatus != BetStatus.OPEN || payout == 0) revert NothingToPay();

        // Close position and prevent multiple payouts
        totalOpenStake -= tradersStake[trader].totalStake;
        tradersStake[trader].totalStake = 0;
        tradersStake[trader].betStatus = BetStatus.CLOSED;

        _sendFunds(trader, payout);

        emit CollectedPayout(trader, payout);
    }

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    function collectVoidedFunds(address trader) external {
        if (!marketVoided) revert MarketIsOpen();

        // If caller has already closed position, revert
        if (tradersStake[trader].betStatus != BetStatus.OPEN) revert NothingToPay();
        uint256 traderStake = tradersStake[trader].totalStake;
        if (traderStake == 0 || totalOpenStake == 0) revert NothingToPay();

        // Calculate proportional payout based on current pool and remaining open stake
        uint256 pool = getBalance();
        uint256 repayment =
            convertBack(div(mul(convertToUD(pool), convertToUD(traderStake)), convertToUD(totalOpenStake)));

        // Close position and prevent multiple repayments
        tradersStake[trader].totalStake = 0;
        tradersStake[trader].betStatus = BetStatus.CLOSED;

        // Reduce remaining open stake
        totalOpenStake -= traderStake;

        // Burn the trader's NFT and remove it from stake
        _burn(trader, tradersStake[trader].nftId, 1);
        tradersStake[trader].nftId = 0;

        _sendFunds(trader, repayment);

        emit CollectedVoidedFunds(trader, repayment);
    }

    /// @inheritdoc IOnitInfiniteOutcomeDPM
    function calculatePayout(address trader) external view returns (uint256) {
        return _calculatePayout(trader);
    }

    // ----------------------------------------------------------------
    // Internal functions
    // ----------------------------------------------------------------

    /**
     * @notice Calculate the payout for a prediction
     *
     * @param trader The address of the trader
     *
     * @return payout The payout amount
     */
    function _calculatePayout(address trader) internal view returns (uint256) {
        // Get total shares in winning bucket
        int256 totalBucketShares = getBucketOutstandingShares(resolvedBucketId);
        if (totalBucketShares == 0) return 0;

        // Get traders balance of the winning bucket
        uint256 traderShares = getBalanceOfShares(trader, resolvedBucketId);

        // Calculate payout based on share of winning bucket
        return convertBack(
            // Casting totalBucketShares to uint256 is safe as totalBucketShares is positive and less than uint80.max
            convertToUD(traderShares).mul(convertToUD(totalPayout)).div(convertToUD(uint256(totalBucketShares)))
        );
    }

    // ----------------------------------------------------------------
    // ERC1155 functions
    // ----------------------------------------------------------------

    function uri(uint256 id) public view virtual override returns (string memory) {
        return LibString.concat(_uri, LibString.toString(id));
    }

    // ----------------------------------------------------------------
    // Fallback functions
    // ----------------------------------------------------------------

    /**
     * @dev Reject any funds sent to the contract
     * - We dont't want funds not accounted for in the market to effect the expected outcome for traders
     */
    fallback() external payable {
        revert RejectFunds();
    }

    /**
     * @dev Reject any funds sent to the contract
     * - We dont't want funds not accounted for in the market to effect the expected outcome for traders
     */
    receive() external payable {
        revert RejectFunds();
    }
}
