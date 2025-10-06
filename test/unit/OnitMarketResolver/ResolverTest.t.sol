// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc
import { Test } from "forge-std/Test.sol";
// Interfaces
import { IOnitMarketResolver } from "@src/interfaces/IOnitMarketResolver.sol";
import { IOnitFactory } from "@src/interfaces/IOnitFactory.sol";
import { IOnitMarketOrderRouter } from "@src/interfaces/IOnitMarketOrderRouter.sol";
import { MarketConfig } from "@src/types/TOnitInfiniteOutcomeDPM.sol";
import { OnitInfiniteOutcomeDPM } from "@src/OnitInfiniteOutcomeDPM.sol";
// Contracts to test
import { OnitMarketResolver } from "@src/resolvers/OnitMarketResolver.sol";

contract MockOnitFactory is IOnitFactory {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function setOwner(address _owner) external {
        owner = _owner;
    }

    // Unused functions, needs implemented to keep interface
    function implementation() external view returns (address) {
        return address(0);
    }

    function orderRouter() external view returns (IOnitMarketOrderRouter) {
        return IOnitMarketOrderRouter(address(0));
    }

    function createMarket(
        address,
        uint256,
        uint256,
        uint256,
        MarketConfig memory,
        int256[] memory,
        int256[] memory,
        bytes memory
    )
        external
        payable
        returns (OnitInfiniteOutcomeDPM market)
    {
        return OnitInfiniteOutcomeDPM(payable(address(0)));
    }
}

contract TestResolver is OnitMarketResolver {
    function initialize(uint256 _withdrawlDelayPeriod, address _onitFactory, address[] memory _resolvers) external {
        _initializeOnitMarketResolver(_withdrawlDelayPeriod, _onitFactory, _resolvers);
    }

    function setResolvedOutcome(int256 _resolvedOutcome, int256 _resolvedBucketId) external onlyResolver {
        _setResolvedOutcome(_resolvedOutcome, _resolvedBucketId);
    }

    function updateResolvedOutcome(int256 _resolvedOutcome, int256 _resolvedBucketId) external onlyResolver {
        _updateResolvedOutcome(_resolvedOutcome, _resolvedBucketId);
    }
}

contract ResolverTest is Test {
    TestResolver public resolver;
    MockOnitFactory public factory;

    address public FACTORY_OWNER;
    address public RESOLVER_1;
    address public RESOLVER_2;
    address public NON_RESOLVER;

    uint256 public constant WITHDRAWAL_DELAY_PERIOD_ONE_DAY = 1 days;

    function setUp() public {
        FACTORY_OWNER = makeAddr("FACTORY_OWNER");
        RESOLVER_1 = makeAddr("RESOLVER_1");
        RESOLVER_2 = makeAddr("RESOLVER_2");
        NON_RESOLVER = makeAddr("NON_RESOLVER");

        factory = new MockOnitFactory(FACTORY_OWNER);
        resolver = new TestResolver();

        address[] memory resolvers = new address[](2);
        resolvers[0] = RESOLVER_1;
        resolvers[1] = RESOLVER_2;
        resolver.initialize(WITHDRAWAL_DELAY_PERIOD_ONE_DAY, address(factory), resolvers);
    }

    function test_initialization() public {
        assertEq(resolver.withdrawlDelayPeriod(), WITHDRAWAL_DELAY_PERIOD_ONE_DAY);
        assertEq(resolver.onitFactory(), address(factory));
        assertTrue(resolver.isResolver(RESOLVER_1));
        assertTrue(resolver.isResolver(RESOLVER_2));
        assertFalse(resolver.isResolver(NON_RESOLVER));
    }

    function test_cannotInitializeWithZeroFactory() public {
        TestResolver newResolver = new TestResolver();
        address[] memory resolvers = new address[](1);
        resolvers[0] = RESOLVER_1;

        vm.expectRevert(IOnitMarketResolver.OnitFactoryNotSet.selector);
        newResolver.initialize(WITHDRAWAL_DELAY_PERIOD_ONE_DAY, address(0), resolvers);
    }

    function test_cannotInitializeWithEmptyResolvers() public {
        TestResolver newResolver = new TestResolver();
        address[] memory resolvers = new address[](0);

        vm.expectRevert(IOnitMarketResolver.ResolversNotSet.selector);
        newResolver.initialize(WITHDRAWAL_DELAY_PERIOD_ONE_DAY, address(factory), resolvers);
    }

    function test_cannotInitializeWithZeroResolver() public {
        TestResolver newResolver = new TestResolver();
        address[] memory resolvers = new address[](1);
        resolvers[0] = address(0);

        vm.expectRevert(IOnitMarketResolver.ResolversNotSet.selector);
        newResolver.initialize(0, address(factory), resolvers);
    }

    function test_onlyResolverCanSetOutcome() public {
        vm.prank(NON_RESOLVER);
        vm.expectRevert(IOnitMarketResolver.OnlyResolver.selector);
        resolver.setResolvedOutcome(100, 1);

        vm.prank(RESOLVER_1);
        resolver.setResolvedOutcome(100, 1);

        assertEq(resolver.resolvedOutcome(), 100);
        assertEq(resolver.resolvedBucketId(), 1);
    }

    function test_cannotSetOutcomeTwice() public {
        vm.prank(RESOLVER_1);
        resolver.setResolvedOutcome(100, 1);

        vm.prank(RESOLVER_1);
        vm.expectRevert(IOnitMarketResolver.MarketIsResolved.selector);
        resolver.setResolvedOutcome(200, 2);
    }

    function test_canUpdateOutcomeWithinDisputePeriod() public {
        vm.prank(RESOLVER_1);
        resolver.setResolvedOutcome(100, 1);

        vm.prank(RESOLVER_2);
        resolver.updateResolvedOutcome(200, 2);

        assertEq(resolver.resolvedOutcome(), 200);
        assertEq(resolver.resolvedBucketId(), 2);
    }

    function test_cannotUpdateOutcomeAfterDisputePeriod() public {
        vm.prank(RESOLVER_1);
        resolver.setResolvedOutcome(100, 1);

        // Move time past dispute period
        vm.warp(block.timestamp + resolver.withdrawlDelayPeriod() + 1);

        vm.prank(RESOLVER_2);
        vm.expectRevert(IOnitMarketResolver.DisputePeriodPassed.selector);
        resolver.updateResolvedOutcome(200, 2);
    }

    function test_onlyFactoryOwnerCanVoidMarket() public {
        vm.prank(NON_RESOLVER);
        vm.expectRevert(IOnitMarketResolver.OnlyOnitFactoryOwner.selector);
        resolver.voidMarket();

        vm.prank(FACTORY_OWNER);
        resolver.voidMarket();
        assertTrue(resolver.marketVoided());
    }

    function test_cannotResolveVoidedMarket() public {
        vm.prank(FACTORY_OWNER);
        resolver.voidMarket();

        vm.prank(RESOLVER_1);
        vm.expectRevert(IOnitMarketResolver.MarketIsVoided.selector);
        resolver.setResolvedOutcome(100, 1);
    }

    function test_cannotUpdateUnresolvedMarket() public {
        vm.prank(RESOLVER_1);
        vm.expectRevert(IOnitMarketResolver.MarketIsOpen.selector);
        resolver.updateResolvedOutcome(100, 1);
    }
}
