// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc contracts used in tests
import { convert } from "prb-math/sd59x18/Conversions.sol";
import { LibClone } from "solady/utils/LibClone.sol";
import { Ownable } from "solady/auth/Ownable.sol";
// Config
import { IODPMTestConstants } from "@test/config/IODPMTestConstants.sol";
import { OrderRouterTestBase } from "@test/config/OrderRouterTestBase.t.sol";
import { IODPMUtils } from "@test/utils/IODPMUtils.sol";
// Types
import { BetStatus, MarketConfig } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
import { TokenType } from "@src/types/TOnitIODPMOrderManager.sol";
// Contract to test
import { OnitInfiniteOutcomeDPMProxyFactory } from "@src/OnitInfiniteOutcomeDPMProxyFactory.sol";
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";
import { OnitIODPMOrderManager } from "@src/order-manager/OnitIODPMOrderManager.sol";

contract InfiniteOutcomeDPMProxyFactoryTest is IODPMTestConstants, IODPMUtils, OrderRouterTestBase {
    address[] resolvers;

    OnitInfiniteOutcomeDPM testMarket;
    OnitInfiniteOutcomeDPMProxyFactory testFactory;

    address factoryOwner;

    function setUp() public {
        factoryOwner = makeAddr("factoryOwner");

        testMarket = new OnitInfiniteOutcomeDPM();
        testFactory = new OnitInfiniteOutcomeDPMProxyFactory(factoryOwner, address(testMarket), orderRouterAddress);

        resolvers = new address[](1);
        resolvers[0] = address(this);

        tokenA.mint(alice, 1000 ether);
    }

    function test_cannotSetImplementationIfNotOwner() public {
        assertEq(testFactory.owner(), factoryOwner);
        vm.prank(alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        testFactory.setImplementation(address(0xdead));
    }

    function test_setImplementation() public {
        assertEq(testFactory.implementation(), address(testMarket));
        vm.prank(factoryOwner);
        testFactory.setImplementation(address(0xdead));
        assertEq(testFactory.implementation(), address(0xdead));
    }

    function test_cannotSetOrderRouterIfNotOwner() public {
        assertEq(address(testFactory.orderRouter()), orderRouterAddress);
        vm.prank(alice);
        vm.expectRevert(Ownable.Unauthorized.selector);
        testFactory.setOrderRouter(address(0xdead));
    }

    function test_setOrderRouter() public {
        assertEq(address(testFactory.orderRouter()), orderRouterAddress);
        vm.prank(factoryOwner);
        testFactory.setOrderRouter(address(0xdead));
        assertEq(address(testFactory.orderRouter()), address(0xdead));
    }

    function test_createFailsIfBadImplementation() public {
        OnitInfiniteOutcomeDPMProxyFactory badFactory =
            new OnitInfiniteOutcomeDPMProxyFactory(factoryOwner, address(0xdead), orderRouterAddress);
        vm.expectRevert();
        badFactory.createMarket{
            value: INITIAL_BET_VALUE
        }(
            alice,
            CREATE_MARKET_SALT,
            UNSEEDED_MARKET,
            INITIAL_BET_VALUE,
            MarketConfig({
                currencyType: TokenType.NATIVE,
                currency: address(0),
                marketCreatorFeeReceiver: MARKET_CREATOR_FEE_RECEIVER,
                marketCreatorCommissionBp: MARKET_CREATOR_COMMISSION_BPS,
                bettingCutoff: BETTING_CUTOFF_ONE_DAY,
                withdrawlDelayPeriod: WITHDRAWAL_DELAY_PERIOD_ONE_DAY,
                minBetSize: MIN_BET_SIZE,
                maxBetSize: MAX_BET_SIZE,
                outcomeUnit: OUTCOME_UNIT,
                marketQuestion: MARKET_QUESTION,
                marketUri: MARKET_URI,
                resolvers: resolvers
            }),
            DUMMY_BUCKET_IDS,
            DUMMY_SHARES,
            ""
        );
    }

    function test_predictMarketAddress() public view {
        address marketAddress = testFactory.predictMarketAddress(1, BETTING_CUTOFF_ONE_DAY, MARKET_QUESTION);
        assertNotEq(marketAddress, address(0), "marketAddress");
    }

    function test_cannotDeployIfAlreadyDeployed() public {
        OnitInfiniteOutcomeDPM market1 = testFactory.createMarket{
            value: INITIAL_BET_VALUE
        }(
            alice,
            CREATE_MARKET_SALT,
            UNSEEDED_MARKET,
            INITIAL_BET_VALUE,
            MarketConfig({
                currencyType: TokenType.NATIVE,
                currency: address(0),
                marketCreatorFeeReceiver: MARKET_CREATOR_FEE_RECEIVER,
                marketCreatorCommissionBp: MARKET_CREATOR_COMMISSION_BPS,
                bettingCutoff: BETTING_CUTOFF_ONE_DAY,
                withdrawlDelayPeriod: WITHDRAWAL_DELAY_PERIOD_ONE_DAY,
                outcomeUnit: OUTCOME_UNIT,
                minBetSize: MIN_BET_SIZE,
                maxBetSize: MAX_BET_SIZE,
                marketQuestion: "question 1",
                marketUri: MARKET_URI,
                resolvers: resolvers
            }),
            DUMMY_BUCKET_IDS,
            DUMMY_SHARES,
            ""
        );

        vm.expectRevert(LibClone.DeploymentFailed.selector);
        testFactory.createMarket{
            value: INITIAL_BET_VALUE
        }(
            alice,
            CREATE_MARKET_SALT,
            UNSEEDED_MARKET,
            INITIAL_BET_VALUE,
            MarketConfig({
                currencyType: TokenType.NATIVE,
                currency: address(0),
                marketCreatorFeeReceiver: MARKET_CREATOR_FEE_RECEIVER,
                marketCreatorCommissionBp: MARKET_CREATOR_COMMISSION_BPS,
                bettingCutoff: BETTING_CUTOFF_ONE_DAY,
                withdrawlDelayPeriod: WITHDRAWAL_DELAY_PERIOD_ONE_DAY,
                outcomeUnit: OUTCOME_UNIT,
                minBetSize: MIN_BET_SIZE,
                maxBetSize: MAX_BET_SIZE,
                marketQuestion: "question 1",
                marketUri: MARKET_URI,
                resolvers: resolvers
            }),
            DUMMY_BUCKET_IDS,
            DUMMY_SHARES,
            ""
        );

        // Deploys if we change anything (in this case the question)
        OnitInfiniteOutcomeDPM market2 = testFactory.createMarket{
            value: INITIAL_BET_VALUE
        }(
            alice,
            CREATE_MARKET_SALT,
            UNSEEDED_MARKET,
            INITIAL_BET_VALUE,
            MarketConfig({
                currencyType: TokenType.NATIVE,
                currency: address(0),
                marketCreatorFeeReceiver: MARKET_CREATOR_FEE_RECEIVER,
                marketCreatorCommissionBp: MARKET_CREATOR_COMMISSION_BPS,
                bettingCutoff: BETTING_CUTOFF_ONE_DAY,
                withdrawlDelayPeriod: WITHDRAWAL_DELAY_PERIOD_ONE_DAY,
                outcomeUnit: OUTCOME_UNIT,
                minBetSize: MIN_BET_SIZE,
                maxBetSize: MAX_BET_SIZE,
                marketQuestion: "question 2",
                marketUri: MARKET_URI,
                resolvers: resolvers
            }),
            DUMMY_BUCKET_IDS,
            DUMMY_SHARES,
            ""
        );

        assertEq(market1.marketQuestion(), "question 1");
        assertEq(market2.marketQuestion(), "question 2");
    }

    function test_createMarket() public {
        OnitInfiniteOutcomeDPM market = testFactory.createMarket{
            value: INITIAL_BET_VALUE
        }(
            alice,
            CREATE_MARKET_SALT,
            UNSEEDED_MARKET,
            INITIAL_BET_VALUE,
            MarketConfig({
                currencyType: TokenType.NATIVE,
                currency: address(0),
                marketCreatorFeeReceiver: MARKET_CREATOR_FEE_RECEIVER,
                marketCreatorCommissionBp: MARKET_CREATOR_COMMISSION_BPS,
                bettingCutoff: BETTING_CUTOFF_ONE_DAY,
                withdrawlDelayPeriod: WITHDRAWAL_DELAY_PERIOD_ONE_DAY,
                minBetSize: MIN_BET_SIZE,
                maxBetSize: MAX_BET_SIZE,
                outcomeUnit: OUTCOME_UNIT,
                marketQuestion: MARKET_QUESTION,
                marketUri: MARKET_URI,
                resolvers: resolvers
            }),
            DUMMY_BUCKET_IDS,
            DUMMY_SHARES,
            ""
        );

        // Market values
        assertEq(market.onitFactory(), address(testFactory));
        assertEq(market.isResolver(address(this)), true);
        assertEq(market.bettingCutoff(), BETTING_CUTOFF_ONE_DAY);
        assertEq(market.outcomeUnit(), OUTCOME_UNIT);
        assertEq(market.kappa(), getKappaForInitialMarket(DUMMY_SHARES, int256(INITIAL_BET_VALUE)));
        assertEq(market.marketQuestion(), MARKET_QUESTION);
        assertEq(market.uri(0), MARKET_URI_0);
        assertEq(market.nextNftTokenId(), 1);
        assertEq(market.totalQSquared(), DUMMY_INITIAL_TOTAL_Q_SQUARED);

        // Bet values
        (uint256 aliceStake, uint256 aliceNftId, BetStatus status) = market.tradersStake(alice);
        assertEq(aliceStake, INITIAL_BET_VALUE);
        assertEq(aliceNftId, 0);
        assertEq(market.balanceOf(alice, 0), 1);
        assertEq(market.getBucketOutstandingShares(DUMMY_BUCKET_IDS[0]), DUMMY_SHARES[0]);
        assertEq(market.getBalanceOfShares(alice, DUMMY_BUCKET_IDS[0]), uint256(DUMMY_SHARES[0]));
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
    }

    function test_createMarketWithSeededFunds() public {
        uint256 initialBetValue = 1 ether;
        uint256 seededFunds = 2 ether;

        resolvers[0] = RESOLVER_1;

        MarketConfig memory config = MarketConfig({
            currencyType: TokenType.NATIVE,
            currency: address(0),
            marketCreatorFeeReceiver: MARKET_CREATOR_FEE_RECEIVER,
            marketCreatorCommissionBp: MARKET_CREATOR_COMMISSION_BPS,
            bettingCutoff: BETTING_CUTOFF_ONE_DAY,
            withdrawlDelayPeriod: WITHDRAWAL_DELAY_PERIOD_ONE_DAY,
            minBetSize: MIN_BET_SIZE,
            maxBetSize: MAX_BET_SIZE,
            outcomeUnit: OUTCOME_UNIT,
            marketQuestion: MARKET_QUESTION,
            marketUri: MARKET_URI,
            resolvers: resolvers
        });

        testMarket = testFactory.createMarket{
            value: initialBetValue + seededFunds
        }(alice, CREATE_MARKET_SALT, seededFunds, initialBetValue, config, DUMMY_BUCKET_IDS, DUMMY_SHARES, "");

        assertEq(address(testMarket).balance, initialBetValue + seededFunds);
        (uint256 aliceStake, uint256 aliceNftId, BetStatus status) = testMarket.tradersStake(alice);
        assertEq(aliceStake, initialBetValue);
        assertEq(aliceNftId, 0);
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
    }

    function test_createMarketWithERC20Token() public {
        // Create market config with ERC20 token
        MarketConfig memory config = MarketConfig({
            currencyType: TokenType.ERC20,
            currency: tokenAAddress,
            marketCreatorFeeReceiver: MARKET_CREATOR_FEE_RECEIVER,
            marketCreatorCommissionBp: MARKET_CREATOR_COMMISSION_BPS,
            bettingCutoff: BETTING_CUTOFF_ONE_DAY,
            withdrawlDelayPeriod: WITHDRAWAL_DELAY_PERIOD_ONE_DAY,
            outcomeUnit: OUTCOME_UNIT,
            minBetSize: MIN_BET_SIZE,
            maxBetSize: MAX_BET_SIZE,
            marketQuestion: MARKET_QUESTION,
            marketUri: MARKET_URI,
            resolvers: resolvers
        });

        // Create permit data for token approval
        bytes memory orderRouterInitData = encodeOrderRouterInitData(
            tokenAAddress, alice, orderRouterAddress, INITIAL_BET_VALUE, block.timestamp + 1 days, alicePk
        );

        // Create market with ERC20 token
        OnitInfiniteOutcomeDPM market = testFactory.createMarket(
            alice,
            CREATE_MARKET_SALT,
            UNSEEDED_MARKET,
            INITIAL_BET_VALUE,
            config,
            DUMMY_BUCKET_IDS,
            DUMMY_SHARES,
            orderRouterInitData
        );

        // Verify market values
        assertEq(market.onitFactory(), address(testFactory));
        assertEq(market.isResolver(address(this)), true);
        assertEq(market.bettingCutoff(), BETTING_CUTOFF_ONE_DAY);
        assertEq(market.outcomeUnit(), OUTCOME_UNIT);
        assertEq(market.kappa(), getKappaForInitialMarket(DUMMY_SHARES, int256(INITIAL_BET_VALUE)));
        assertEq(market.marketQuestion(), MARKET_QUESTION);
        assertEq(market.uri(0), MARKET_URI_0);
        assertEq(market.nextNftTokenId(), 1);
        assertEq(market.totalQSquared(), DUMMY_INITIAL_TOTAL_Q_SQUARED);

        // Verify token balances and allowances
        assertEq(tokenA.balanceOf(address(market)), INITIAL_BET_VALUE);
        assertEq(tokenA.allowance(alice, address(testFactory)), 0); // Allowance should be used up
    }

    function test_createMarketWithERC20TokenAndSeededFunds() public {
        uint256 initialBetValue = INITIAL_BET_VALUE;
        uint256 seededFunds = 2 ether;

        // Create market config with ERC20 token
        MarketConfig memory config = MarketConfig({
            currencyType: TokenType.ERC20,
            currency: tokenAAddress,
            marketCreatorFeeReceiver: MARKET_CREATOR_FEE_RECEIVER,
            marketCreatorCommissionBp: MARKET_CREATOR_COMMISSION_BPS,
            bettingCutoff: BETTING_CUTOFF_ONE_DAY,
            withdrawlDelayPeriod: WITHDRAWAL_DELAY_PERIOD_ONE_DAY,
            outcomeUnit: OUTCOME_UNIT,
            minBetSize: MIN_BET_SIZE,
            maxBetSize: MAX_BET_SIZE,
            marketQuestion: MARKET_QUESTION,
            marketUri: MARKET_URI,
            resolvers: resolvers
        });

        // Create permit data for token approval including seeded funds
        bytes memory orderRouterInitData = encodeOrderRouterInitData(
            tokenAAddress, alice, orderRouterAddress, initialBetValue + seededFunds, block.timestamp + 1 days, alicePk
        );

        // Create market with ERC20 token and seeded funds
        OnitInfiniteOutcomeDPM market = testFactory.createMarket(
            alice,
            CREATE_MARKET_SALT,
            seededFunds,
            initialBetValue,
            config,
            DUMMY_BUCKET_IDS,
            DUMMY_SHARES,
            orderRouterInitData
        );

        // Verify market values
        assertEq(tokenA.balanceOf(address(market)), initialBetValue + seededFunds);
        (uint256 aliceStake, uint256 aliceNftId, BetStatus status) = market.tradersStake(alice);
        assertEq(aliceStake, initialBetValue);
        assertEq(aliceNftId, 0);
        assertEq(uint8(status), uint8(BetStatus.OPEN), "status should be OPEN");
        assertEq(tokenA.allowance(alice, address(testFactory)), 0); // Allowance should be used up
    }

    function test_createMarketWithERC20Token_revert_InsufficientBalance() public {
        // Make sure alice has no balance of tokenA
        vm.prank(alice);
        tokenA.transfer(address(0), 1000 ether);

        // Create market config with ERC20 token
        MarketConfig memory config = MarketConfig({
            currencyType: TokenType.ERC20,
            currency: tokenAAddress,
            marketCreatorFeeReceiver: MARKET_CREATOR_FEE_RECEIVER,
            marketCreatorCommissionBp: MARKET_CREATOR_COMMISSION_BPS,
            bettingCutoff: BETTING_CUTOFF_ONE_DAY,
            withdrawlDelayPeriod: WITHDRAWAL_DELAY_PERIOD_ONE_DAY,
            outcomeUnit: OUTCOME_UNIT,
            minBetSize: MIN_BET_SIZE,
            maxBetSize: MAX_BET_SIZE,
            marketQuestion: MARKET_QUESTION,
            marketUri: MARKET_URI,
            resolvers: resolvers
        });

        // Create permit data
        bytes memory orderRouterInitData = encodeOrderRouterInitData(
            tokenAAddress, alice, orderRouterAddress, INITIAL_BET_VALUE, block.timestamp + 1 days, alicePk
        );

        // Attempt to create market with insufficient balance
        vm.expectRevert();
        testFactory.createMarket(
            alice,
            CREATE_MARKET_SALT,
            UNSEEDED_MARKET,
            INITIAL_BET_VALUE,
            config,
            DUMMY_BUCKET_IDS,
            DUMMY_SHARES,
            orderRouterInitData
        );
    }
}
