// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Config
import { IODPMTestConstants } from "@test/config/IODPMTestConstants.sol";
import { IODPMTestData } from "@test/config/IODPMTestData.t.sol";
import { OrderRouterTestBase } from "@test/config/OrderRouterTestBase.t.sol";
import { IODPMUtils } from "@test/utils/IODPMUtils.sol";
// Types
import { TokenType } from "@src/types/TOnitIODPMOrderManager.sol";
import { MarketConfig, MarketInitData } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
// Interfaces
import { IOnitInfiniteOutcomeDPM } from "@src/interfaces/IOnitInfiniteOutcomeDPM.sol";
// Contracts to test
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";
import { OnitInfiniteOutcomeDPMProxyFactory } from "@src/OnitInfiniteOutcomeDPMProxyFactory.sol";
import { OnitIODPMOrderManager } from "@src/order-manager/OnitIODPMOrderManager.sol";

contract OnitIODPMTestBase is IODPMUtils, IODPMTestConstants, IODPMTestData, OrderRouterTestBase {
    address internal marketImplementation;
    OnitInfiniteOutcomeDPM internal market;
    address internal marketAddress;
    OnitInfiniteOutcomeDPMProxyFactory internal factory;
    address internal factoryAddress;

    /**
     * Test parameters
     */
    // kappa tolerance is 0.00000001%
    uint256 internal constant KAPPA_TOLERANCE = 0.000_000_01 ether;
    // Payout tolerance is 0.0001% of the market balance
    uint256 internal constant PAYOUT_TOLERANCE = 0.000_01 ether;

    constructor() {
        marketImplementation = address(new OnitInfiniteOutcomeDPM());
        factory = new OnitInfiniteOutcomeDPMProxyFactory(address(this), marketImplementation, orderRouterAddress);
        factoryAddress = address(factory);
    }

    function defaultMarketConfig() internal view returns (MarketInitData memory) {
        return MarketInitData({
            onitFactory: factoryAddress,
            orderRouter: orderRouterAddress,
            initiator: alice,
            seededFunds: UNSEEDED_MARKET,
            initialBetSize: INITIAL_BET_VALUE,
            initialBucketIds: DUMMY_BUCKET_IDS,
            initialShares: DUMMY_SHARES,
            config: MarketConfig({
                currencyType: TokenType.NATIVE,
                currency: address(0),
                marketCreatorFeeReceiver: MARKET_CREATOR_FEE_RECEIVER,
                marketCreatorCommissionBp: NO_MARKET_CREATOR_COMMISSION_BPS,
                bettingCutoff: NO_BETTING_CUTOFF,
                withdrawlDelayPeriod: NO_WITHDRAWAL_DELAY_PERIOD,
                minBetSize: MIN_BET_SIZE,
                maxBetSize: MAX_BET_SIZE,
                outcomeUnit: OUTCOME_UNIT,
                marketQuestion: MARKET_QUESTION,
                marketUri: MARKET_URI,
                resolvers: defaultResolvers()
            }),
            orderRouterInitData: abi.encode(uint256(0), uint8(0), bytes32(0), bytes32(0))
        });
    }

    function defaultMarketConfigWithToken() internal view returns (MarketInitData memory) {
        MarketInitData memory initData = defaultMarketConfig();
        initData.config.currencyType = TokenType.ERC20;
        initData.config.currency = tokenAAddress;
        return initData;
    }

    function newMarketWithDefaultConfig() internal returns (OnitInfiniteOutcomeDPM) {
        MarketInitData memory initData = defaultMarketConfig();
        return factory.createMarket{
            value: initData.initialBetSize + initData.seededFunds
        }(
            initData.initiator,
            CREATE_MARKET_SALT,
            initData.seededFunds,
            initData.initialBetSize,
            initData.config,
            initData.initialBucketIds,
            initData.initialShares,
            abi.encode(uint256(0), uint8(0), bytes32(0), bytes32(0))
        );
    }

    function newMarketWithDefaultConfigWithToken() internal returns (OnitInfiniteOutcomeDPM) {
        MarketInitData memory initData = defaultMarketConfigWithToken();
        return newMarket(initData);
    }

    function newMarket(MarketInitData memory initData) internal returns (OnitInfiniteOutcomeDPM) {
        uint256 value;
        bytes memory permitSeededFundsData;
        // If currency is set we need to permit the factory to transfer the tokens
        if (initData.config.currency != address(0)) {
            if (initData.config.currencyType == TokenType.ERC20) {
                (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
                    initData.config.currency,
                    initData.initiator,
                    orderRouterAddress,
                    initData.seededFunds + initData.initialBetSize,
                    block.timestamp + 1 days,
                    alicePk // pass pk
                );
                permitSeededFundsData =
                    abi.encode(block.timestamp + 1 days, v, r, s, new address[](0), new uint256[](0));
            }
        } else {
            value = initData.initialBetSize + initData.seededFunds;
        }

        return factory.createMarket{
            value: value
        }(
            initData.initiator,
            CREATE_MARKET_SALT,
            initData.seededFunds,
            initData.initialBetSize,
            initData.config,
            initData.initialBucketIds,
            initData.initialShares,
            permitSeededFundsData
        );
    }

    // ----------------------------------------------------------------
    // Utils
    // ----------------------------------------------------------------

    function defaultResolvers() internal view returns (address[] memory) {
        address[] memory resolvers = new address[](1);
        resolvers[0] = RESOLVER_1;
        return resolvers;
    }

    // Used to revert tests that are written but not fully constrained
    function unconstrainedTest() internal pure {
        revert("unconstrained test");
    }
}
