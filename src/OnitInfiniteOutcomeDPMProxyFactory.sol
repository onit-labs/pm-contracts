// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// Misc contracts
import { LibClone } from "solady/utils/LibClone.sol";
import { Ownable } from "solady/auth/Ownable.sol";

// Types
import { MarketConfig, MarketInitData } from "./types/TOnitInfiniteOutcomeDPM.sol";
import { TokenType } from "./types/TOnitIODPMOrderManager.sol";

// Interfaces
import { IOnitFactory } from "./interfaces/IOnitFactory.sol";
import { IOnitMarketOrderRouter } from "./interfaces/IOnitMarketOrderRouter.sol";

// Onit contracts
import { OnitInfiniteOutcomeDPM } from "./OnitInfiniteOutcomeDPM.sol";

/**
 * @title Onit Infinite Outcome Dynamic Parimutual Market Proxy Factory
 *
 * @author Onit Labs (https://github.com/onit-labs)
 *
 * @notice A factory contract for deploying OnitInfiniteOutcomeDPM markets.
 *
 * @dev Uses Solady's LibClone to clone the implementation to save deployment gas.
 */
contract OnitInfiniteOutcomeDPMProxyFactory is Ownable, IOnitFactory {
    // ----------------------------------------------------------------
    // Events
    // ----------------------------------------------------------------

    event ImplementationSet(address marketImplementation);
    event OrderRouterSet(address routerAddress);
    event MarketCreated(OnitInfiniteOutcomeDPM market);

    // ----------------------------------------------------------------
    // Errors
    // ----------------------------------------------------------------

    error FailedToDeployMarket();
    error FailedToInitializeMarket();
    error ZeroImplementationAddress();

    // ----------------------------------------------------------------
    // State
    // ----------------------------------------------------------------

    /// @inheritdoc IOnitFactory
    address public implementation;

    /// @inheritdoc IOnitFactory
    IOnitMarketOrderRouter public orderRouter;

    // ----------------------------------------------------------------
    // Constructor
    // ----------------------------------------------------------------

    /**
     * @notice Set the implementation address of the OnitInfiniteOutcomeDPM contract to deploy
     *
     * @param onitFactoryOwner The address of the Onit factory owner
     * @param marketImplementation The address of the OnitInfiniteOutcomeDPM implementation which new markets will
     * proxy to
     * @param _orderRouter The address of the order router for handling token transfers
     */
    constructor(address onitFactoryOwner, address marketImplementation, address _orderRouter) payable Ownable() {
        _initializeOwner(onitFactoryOwner);
        implementation = marketImplementation;
        orderRouter = IOnitMarketOrderRouter(_orderRouter);

        emit ImplementationSet(marketImplementation);
        emit OrderRouterSet(_orderRouter);
    }

    // ----------------------------------------------------------------
    // Owner functions
    // ----------------------------------------------------------------

    function setImplementation(address marketImplementation) external onlyOwner {
        implementation = marketImplementation;
        emit ImplementationSet(marketImplementation);
    }

    function setOrderRouter(address _orderRouter) external onlyOwner {
        orderRouter = IOnitMarketOrderRouter(_orderRouter);
        emit OrderRouterSet(_orderRouter);
    }

    // ----------------------------------------------------------------
    // Public functions
    // ----------------------------------------------------------------

    /// @inheritdoc IOnitFactory
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
        returns (OnitInfiniteOutcomeDPM market)
    {
        if (implementation == address(0)) revert ZeroImplementationAddress();

        // Create salt based on the market parameters
        bytes32 predictAddressSalt =
            keccak256(abi.encode(address(this), salt, marketConfig.bettingCutoff, marketConfig.marketQuestion));

        // Deploy the market using deterministic address
        market = OnitInfiniteOutcomeDPM(payable(LibClone.cloneDeterministic(implementation, predictAddressSalt)));

        // Handle token transfers based on the token type
        TokenType tokenType = marketConfig.currencyType;

        bool success;
        bytes memory returnData;

        // Initialize the market with value for native tokens, or 0 otherwise
        try market.initialize{
            value: tokenType == TokenType.NATIVE ? msg.value : 0
        }(
            MarketInitData({
                onitFactory: address(this),
                orderRouter: address(orderRouter),
                initiator: initiator,
                seededFunds: seededFunds,
                initialBetSize: initialBetSize,
                initialBucketIds: initialBucketIds,
                initialShares: initialShares,
                orderRouterInitData: orderRouterInitData,
                config: marketConfig
            })
        ) {
            success = true;
        } catch (bytes memory reason) {
            returnData = reason;
        }

        if (!success) {
            // If there's return data, forward the revert message
            if (returnData.length > 0) {
                assembly {
                    let returnDataSize := mload(returnData)
                    revert(add(32, returnData), returnDataSize)
                }
            }
            revert FailedToDeployMarket();
        }

        // Verify the market was initialized correctly
        address checkOnitFactory = market.onitFactory();
        if (checkOnitFactory != address(this)) revert FailedToInitializeMarket();

        emit MarketCreated(market);
    }

    /// @notice Predicts the address where a market will be deployed
    function predictMarketAddress(uint256 salt, uint256 marketBettingCutoff, string memory marketQuestion)
        external
        view
        returns (address)
    {
        if (implementation == address(0)) revert ZeroImplementationAddress();

        bytes32 predictAddressSalt = keccak256(abi.encode(address(this), salt, marketBettingCutoff, marketQuestion));
        return LibClone.predictDeterministicAddress(implementation, predictAddressSalt, address(this));
    }
}
