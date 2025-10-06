// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console2 } from "forge-std/Script.sol";

import { OnitMarketOrderRouter } from "../src/order-manager/OnitMarketOrderRouter.v2.sol";

contract OnitOrderRouterDeployer is Script {
    bytes32 public ORDER_ROUTER_SALT = bytes32(keccak256("order_router v0.0.2"));

    error FailedToDeploy();

    // Just log instead of revert for already deployed contracts, this makes the script more useful in local tests
    event AlreadyDeployed(address contractAddress);
    event OrderRouterDeployed(address orderRouter, bytes32 salt);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the order router
        bytes memory orderRouterInitCode = type(OnitMarketOrderRouter).creationCode;
        address orderRouter = deployCreate2(ORDER_ROUTER_SALT, orderRouterInitCode);
        emit OrderRouterDeployed(orderRouter, ORDER_ROUTER_SALT);

        console2.log("Order Router address:", orderRouter);
        console2.log("Deploying on chain ID", block.chainid);

        vm.stopBroadcast();
    }

    function deployCreate2(bytes32 salt, bytes memory initCode) internal returns (address deployedAddress) {
        // Check if contract is already deployed at the target address
        address predictedAddress = vm.computeCreate2Address(salt, keccak256(initCode));
        uint256 size = predictedAddress.code.length;
        if (size > 0) {
            emit AlreadyDeployed(predictedAddress);
            return predictedAddress;
        }

        assembly {
            deployedAddress := create2(0, add(initCode, 0x20), mload(initCode), salt)
        }
        if (deployedAddress == address(0)) {
            revert FailedToDeploy();
        }

        return deployedAddress;
    }
}
