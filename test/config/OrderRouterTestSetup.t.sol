// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Config
import { AddressTestConfig } from "@test/config/AddressTestConfig.t.sol";
import { MockErc20 } from "@test/mocks/MockErc20.sol";
// Contracts
import { OnitMarketOrderRouter } from "@src/order-manager/OnitMarketOrderRouter.v2.sol";

contract OrderRouterTestSetup is AddressTestConfig {
    OnitMarketOrderRouter internal orderRouter;
    address internal orderRouterAddress;

    MockErc20 tokenA;
    address tokenAAddress;

    address someMarketsTokenAdmin;
    uint256 someMarketsTokenAdminPk;

    address[] SPENDERS = [alice, bob];
    uint256[] AMOUNTS = [1 ether, 2 ether];
    uint256 BASE_TOTAL_AMOUNT = 3 ether;
    uint256 INITIAL_BACKING = 0.01 ether;

    constructor() {
        (someMarketsTokenAdmin, someMarketsTokenAdminPk) = makeAddrAndKey("someMarketsTokenAdmin");

        tokenA = new MockErc20("TokenA", "TKA", 18);
        tokenAAddress = address(tokenA);
        tokenA.mint(someMarketsTokenAdmin, 1000 ether);

        orderRouter = new OnitMarketOrderRouter();
        orderRouterAddress = address(orderRouter);
    }
}
