// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Script, console2 } from "forge-std/Script.sol";

import { OnitInfiniteOutcomeDPM } from "../src/OnitInfiniteOutcomeDPM.sol";
import { OnitInfiniteOutcomeDPMProxyFactory } from "../src/OnitInfiniteOutcomeDPMProxyFactory.sol";
import { OnitMarketOrderRouter } from "../src/order-manager/OnitMarketOrderRouter.sol";

contract OnitInfiniteOutcomeDPMFactoryDeployer is Script {
    // TODO better linking of this to previous deployments and deploy.js script
    address public EXISTING_IMPLEMENTATION_ADDRESS = address(0);

    bytes32 public IMPLEMENTATION_SALT = bytes32(keccak256("implementation v0.0.3"));
    bytes32 public FACTORY_SALT = bytes32(keccak256("factory v0.0.3"));
    bytes32 public ORDER_ROUTER_SALT = bytes32(keccak256("order_router v0.0.1"));

    error FailedToDeploy();

    // Just log instead of revert for already deployed contracts, this makes the script more useful in local tests
    event AlreadyDeployed(address contractAddress);
    event ImplementationDeployed(address implementation, bytes32 salt);
    event FactoryDeployed(address factory, bytes32 salt);
    event OrderRouterDeployed(address orderRouter, bytes32 salt);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address owner = vm.envAddress("ONIT_OWNER_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Get the implementation address, or deploy it if needed
        address implementation = getImplementationAddress(IMPLEMENTATION_SALT);

        // Deploy the order router
        bytes memory orderRouterInitCode = type(OnitMarketOrderRouter).creationCode;
        address orderRouter = deployCreate2(ORDER_ROUTER_SALT, orderRouterInitCode);
        emit OrderRouterDeployed(orderRouter, ORDER_ROUTER_SALT);

        console2.log("Owner address:", owner);
        console2.log("Implementation address:", implementation);
        console2.log("Order Router address:", orderRouter);
        console2.log("Deploying on chain ID", block.chainid);

        // Deploy factory with CREATE2
        bytes memory factoryInitCode = abi.encodePacked(
            type(OnitInfiniteOutcomeDPMProxyFactory).creationCode, abi.encode(owner, implementation, orderRouter)
        );
        address factoryAddress = deployCreate2(FACTORY_SALT, factoryInitCode);
        console2.log("Factory address:", factoryAddress);
        emit FactoryDeployed(factoryAddress, FACTORY_SALT);

        vm.stopBroadcast();
    }

    function getImplementationAddress(bytes32 salt) public returns (address) {
        if (EXISTING_IMPLEMENTATION_ADDRESS != address(0)) {
            return EXISTING_IMPLEMENTATION_ADDRESS;
        }

        bytes memory implementationInitCode = type(OnitInfiniteOutcomeDPM).creationCode;
        address implementation = deployCreate2(salt, implementationInitCode);
        emit ImplementationDeployed(implementation, salt);
        return implementation;
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
