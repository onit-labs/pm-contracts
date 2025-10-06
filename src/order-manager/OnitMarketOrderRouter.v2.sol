// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Misc contracts
import { ERC20 } from "solady/tokens/ERC20.sol";

// Types
import { AllowanceTargetType, MarketDetails, Side } from "@src/types/TOnitMarketOrderRouter.sol";

// Interfaces
import { IOnitMarketOrderRouter } from "@src/interfaces/IOnitMarketOrderRouter.sol";

// Onit contracts
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";

/**
 * @title OnitMarketOrderRouter
 *
 * @author Onit Labs (https://github.com/onit-labs)
 *
 * @notice Central registry for handling token approvals across multiple markets
 */
contract OnitMarketOrderRouter is IOnitMarketOrderRouter {
    // ----------------------------------------------------------------
    // Storage
    // ----------------------------------------------------------------

    /**
     * @notice Mapping of all initialised markets to their details
     * @dev marketDetails[market] = MarketDetails({ marketAdmin: initiator, marketToken: marketToken })
     */
    mapping(address market => MarketDetails details) public marketDetails;

    /**
     * Allowers can set allowances for a spender to spend on a market (more specific) or token (more general)
     * @dev allowances[allower][spender][market/token] = amount
     */
    mapping(address allower => mapping(address spender => mapping(address target => uint256 amount))) public allowances;

    // ----------------------------------------------------------------
    // Initialisation functions
    // ----------------------------------------------------------------

    function initializeOrderRouterForMarket(
        address marketToken,
        address initiator,
        uint256 initialBacking,
        bytes memory orderRouterInitData
    )
        external
    {
        marketDetails[msg.sender] = MarketDetails({ marketAdmin: initiator, marketToken: marketToken });

        (uint256 deadline, uint8 v, bytes32 r, bytes32 s, address[] memory spenders, uint256[] memory amounts) =
            abi.decode(orderRouterInitData, (uint256, uint8, bytes32, bytes32, address[], uint256[]));

        // If allowances are set in the initiator, they are always market specific - ie msg.sender of the init call
        int256 allowanceChange = _setAllowances(AllowanceTargetType.MARKET, initiator, msg.sender, spenders, amounts);

        // For initialization, we expect the allowance change to be positive (setting new allowances)
        if (allowanceChange < 0) {
            revert InsufficientTokenAllowance(0, allowanceChange);
        }

        uint256 reservedAllowance = allowances[initiator][address(this)][msg.sender];

        /*
         * If the reserved allowance is 0:
         * - then we require a permit signature
         * - we allow the initiator to set the allowances for other spenders
         * Else (the reserved allowance is not 0):
        * - we don't require a permit signature, we check the initiator has reserved an allowance for the deployment
         * - we clear the reserved allowance
         */
        if (reservedAllowance == 0) {
            // Casting to uint256 is safe as we know the allowance change is positive from `allowanceChange < 0` check
            uint256 totalAmount = initialBacking + uint256(allowanceChange);

            /**
             * If the token owner has already permitted this order router to spend an amount, we need to add this to the
             * total amount so we don't overwrite it
             */
            uint256 currentTokenAllowance = ERC20(marketToken).allowance(initiator, address(this));

            /**
             * Permit order router to spend the total amount of tokens needed on behalf of the initiator
             * This is used to:
             * - make the initial bet, and optionally seed the market with some extra funds (combined as initialBacking)
             * - let the allowed spenders use their allowance to bet on the initialised market
             */
            ERC20(marketToken).permit(initiator, address(this), totalAmount + currentTokenAllowance, deadline, v, r, s);
        } else {
            // We enforce that the user reserved the exact amount of allowance they want to use for the deployment
            // This prevents using any existing allowance against their will
            if (initialBacking > reservedAllowance) {
                revert InsufficientAllowance(initialBacking - reservedAllowance);
            }

            allowances[initiator][address(this)][msg.sender] = 0;

            emit AllowanceUpdated(initiator, address(this), msg.sender, AllowanceTargetType.MARKET, 0);
        }

        // Transfer initial backing from initiator to market
        bool success = ERC20(marketToken).transferFrom(initiator, address(msg.sender), initialBacking);
        if (!success) {
            revert TransferFailed();
        }
    }

    // ----------------------------------------------------------------
    // Allowance functions
    // ----------------------------------------------------------------

    /// @inheritdoc IOnitMarketOrderRouter
    function setAllowances(
        AllowanceTargetType allowanceTargetType,
        address market,
        uint256 spendDeadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address[] calldata spenders,
        uint256[] calldata amounts
    )
        external
    {
        MarketDetails memory _marketDetails = marketDetails[market];
        address marketAdmin = _marketDetails.marketAdmin;
        address token = _marketDetails.marketToken;

        address target = allowanceTargetType == AllowanceTargetType.TOKEN ? token : market;

        int256 changeToTokenAllowance = _setAllowances(allowanceTargetType, marketAdmin, target, spenders, amounts);

        /**
         * If a signature is passed, then we should set the token allowance by calling permit within this function call
         * If no signature is passed, then we don't call permit on the token, we just update the allowances on the
         * router
         * This ensures the marketAdmin can remove allowances without risking the permit signature failing due to to a
         * change in the total remaining allowance they have set for the router
         */
        if (r != bytes32(0)) {
            uint256 currentTokenAllowance = ERC20(token).allowance(marketAdmin, address(this));

            // Safely calculate the new token allowance, preventing underflow
            uint256 newTokenAllowance;
            if (changeToTokenAllowance >= 0) {
                // Positive change: safe to add
                newTokenAllowance = currentTokenAllowance + uint256(changeToTokenAllowance);
            } else {
                // Negative change: check for underflow
                uint256 changeMagnitude = uint256(-changeToTokenAllowance);
                if (currentTokenAllowance < changeMagnitude) {
                    revert InsufficientTokenAllowance(currentTokenAllowance, changeToTokenAllowance);
                }
                newTokenAllowance = currentTokenAllowance - changeMagnitude;
            }

            // Permit this address to spend the total amount of tokens
            ERC20(token).permit(marketAdmin, address(this), newTokenAllowance, spendDeadline, v, r, s);
        } else {
            /**
             * In the case where no signature is passed, we make sure the marketAdmin made the call
             */
            if (msg.sender != marketAdmin) {
                revert InvalidAllowanceSpender();
            }
        }
    }

    /// @inheritdoc IOnitMarketOrderRouter
    function reserveAllowanceForDeployment(address market, uint256 amount) external {
        allowances[msg.sender][address(this)][market] = amount;

        emit AllowanceUpdated(msg.sender, address(this), market, AllowanceTargetType.MARKET, amount);
    }

    // ----------------------------------------------------------------
    // Order execution functions
    // ----------------------------------------------------------------

    /// @inheritdoc IOnitMarketOrderRouter
    function executeOrder(
        address market,
        address buyer,
        uint256 betAmount,
        int256[] memory bucketIds,
        int256[] memory shares,
        bytes memory orderData
    )
        external
        payable
    {
        MarketDetails memory _marketDetails = marketDetails[market];
        address token = _marketDetails.marketToken;

        _handleTokenPermit(buyer, token, betAmount, orderData);
        _executeBuyOrder(market, token, buyer, buyer, betAmount, bucketIds, shares);

        // TODO update order details (referrer etc when we start tracking that)
    }

    /// @inheritdoc IOnitMarketOrderRouter
    function executeMultipleOrders(
        address buyer,
        address[] memory markets,
        uint256[] memory betAmounts,
        int256[][] memory bucketIds,
        int256[][] memory shares,
        bytes memory orderData
    )
        external
        payable
    {
        // We currently only execute batches of orders which use the same token
        MarketDetails memory _marketDetails = marketDetails[markets[0]];
        address token = _marketDetails.marketToken;

        uint256 totalAmountForBatch;

        if (token != address(0)) {
            for (uint256 i = 0; i < markets.length; i++) {
                /**
                 * Ensure all orders use the same token
                 * This means we have a single permit amount for the batch
                 */
                if (marketDetails[markets[i]].marketToken != token) {
                    revert MulticallOrdersMustUseSameToken();
                }
                totalAmountForBatch += betAmounts[i];
            }
        }

        _handleTokenPermit(buyer, token, totalAmountForBatch, orderData);

        for (uint256 i = 0; i < markets.length; i++) {
            _executeBuyOrder(markets[i], token, buyer, buyer, betAmounts[i], bucketIds[i], shares[i]);
        }

        // TODO update order details (referrer etc when we start tracking that)
    }

    /// @inheritdoc IOnitMarketOrderRouter
    function executeOrderFromAllowance(
        address buyer,
        address market,
        uint256 amount,
        int256[] memory bucketIds,
        int256[] memory shares
    )
        external
    {
        MarketDetails memory _marketDetails = marketDetails[market];
        address token = _marketDetails.marketToken;
        address marketAdmin = _marketDetails.marketAdmin;

        if (msg.sender != buyer && msg.sender != marketAdmin) {
            revert InvalidAllowanceSpender();
        }

        _spendAllowance(marketAdmin, buyer, market, token, amount);

        _executeBuyOrder(market, token, marketAdmin, buyer, amount, bucketIds, shares);
    }

    /// @inheritdoc IOnitMarketOrderRouter
    function executeSellOrder(address market, address seller, int256[] memory bucketIds, int256[] memory shares)
        external
    {
        // Validate that the caller is authorized to sell on behalf of the seller
        if (msg.sender != seller) {
            revert InvalidAllowanceSpender();
        }

        _executeSellOrder(market, seller, bucketIds, shares);
    }

    // ----------------------------------------------------------------
    // View functions
    // ----------------------------------------------------------------

    function getErc20Allowance(address token, address owner) public view returns (uint256) {
        return ERC20(token).allowance(owner, address(this));
    }

    // ----------------------------------------------------------------
    // Internal functions
    // ----------------------------------------------------------------

    /**
     * @notice Spend allowance from market-specific and token allowances
     * @param marketAdmin The market admin who set the allowances
     * @param buyer The buyer whose allowance is being spent
     * @param market The market address for market-specific allowance
     * @param token The token address for token allowance
     * @param amount The total amount to spend
     */
    function _spendAllowance(address marketAdmin, address buyer, address market, address token, uint256 amount)
        internal
    {
        // First use any market specific allowance
        uint256 marketAllowance = allowances[marketAdmin][buyer][market];
        uint256 remainingAmount = amount;

        if (marketAllowance > 0) {
            uint256 amountFromMarket = marketAllowance >= amount ? amount : marketAllowance;
            allowances[marketAdmin][buyer][market] -= amountFromMarket;
            remainingAmount -= amountFromMarket;

            emit AllowanceUpdated(
                marketAdmin, buyer, market, AllowanceTargetType.MARKET, allowances[marketAdmin][buyer][market]
            );
        }

        // If we still need more, use token allowance
        if (remainingAmount > 0) {
            uint256 tokenAllowance = allowances[marketAdmin][buyer][token];
            if (tokenAllowance < remainingAmount) {
                revert InsufficientAllowance(remainingAmount);
            }
            allowances[marketAdmin][buyer][token] -= remainingAmount;

            emit AllowanceUpdated(
                marketAdmin, buyer, token, AllowanceTargetType.TOKEN, allowances[marketAdmin][buyer][token]
            );
        }
    }

    function _executeBuyOrder(
        address market,
        address token,
        address spender,
        address buyer,
        uint256 betAmount,
        int256[] memory bucketIds,
        int256[] memory shares
    )
        internal
    {
        uint256 ethValue = 0;

        if (token != address(0)) {
            bool success = ERC20(token).transferFrom(spender, market, betAmount);
            if (!success) {
                revert TransferFailed();
            }
        } else {
            // If a native token market, we pass a value to the buyShares call
            ethValue = betAmount;
        }

        OnitInfiniteOutcomeDPM(payable(market)).buyShares{ value: ethValue }(buyer, betAmount, bucketIds, shares);

        emit OrderExecuted(market, buyer, Side.BUY, betAmount, bucketIds, shares);
    }

    function _executeSellOrder(address market, address seller, int256[] memory bucketIds, int256[] memory shares)
        internal
    {
        uint256 payout = OnitInfiniteOutcomeDPM(payable(market)).sellShares(seller, bucketIds, shares);

        emit OrderExecuted(market, seller, Side.SELL, payout, bucketIds, shares);
    }

    /**
     * @notice Handle token permit and validation for an order
     *
     * @param buyer Buyer address
     * @param token Token address
     * @param amount Amount to permit
     * @param orderData Encoded permit data
     */
    function _handleTokenPermit(address buyer, address token, uint256 amount, bytes memory orderData) internal {
        if (token != address(0)) {
            /**
             * - If the buyer is msg.sender, and they don't pass orderData, they are using an existing allowance so we
             * don't do a permit
             * - If the buyer is msg.sender, and they pass orderData, we use that to permit the order router for the
             * updated amount
             * - If the buyer is not msg.sender, we need to permit the order router for the amount
             * -- NOTE: Amount will be the new allowance for this order router to spend on behalf of permitter, so if
             *          they have an existing allowance this needs to be taken into account
             */
            if (buyer != msg.sender || orderData.length > 0) {
                _permitErc20ForOrder(buyer, token, amount, orderData);
            }
        }
    }

    /**
     * @notice Permit this order router to spend on behalf of a user
     *
     * @param permitter The address of the user to permit
     * @param token The token to permit
     * @param amount The amount to permit
     * @param permitData Encoded permit data (deadline, v, r, s)
     *
     * @dev This function should be used to permit this order router to spend on behalf of a user. The amount can be
     * some value that will cover the user for a number of bets
     *
     * @custom:warning
     * The amount passed to permit will be the new allowance for this order router to spend on behalf of permitter
     * This mean that any existing allowance will be overwritten
     */
    function _permitErc20ForOrder(address permitter, address token, uint256 amount, bytes memory permitData) internal {
        // futureAllowance is an optional extra amount the permitter can set for the order router
        (uint256 futureAllowance, uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            abi.decode(permitData, (uint256, uint256, uint8, bytes32, bytes32));

        ERC20(token).permit(permitter, address(this), amount + futureAllowance, deadline, v, r, s);
    }

    function _setAllowances(
        AllowanceTargetType allowanceTargetType,
        address allower,
        address target,
        address[] memory spenders,
        uint256[] memory amounts
    )
        internal
        returns (int256 totalAmount)
    {
        if (spenders.length != amounts.length) {
            revert ArrayLengthMismatch();
        }

        /**
         * The amount of a token this contract needs permission to spend on behalf of a token owner is the sum of all
         * the allowances set by that owner.
         * If the amount to set for a spender is greater than their current allowance, this will increase
         * If it less than their current allowance, this will decrease
         * We return this total change and use it to permit on the token
         */
        for (uint256 i = 0; i < spenders.length; i++) {
            if (amounts[i] > uint256(type(int256).max)) {
                revert AmountTooLarge();
            }
            // Track the difference between the new allowance and the current allowance
            totalAmount += int256(amounts[i]) - int256(allowances[allower][spenders[i]][target]);

            // Update the allowance
            allowances[allower][spenders[i]][target] = amounts[i];

            emit AllowanceUpdated(allower, spenders[i], target, allowanceTargetType, amounts[i]);
        }
    }
}
