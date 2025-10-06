// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

// Misc
import { ERC20 } from "solady/tokens/ERC20.sol";
// Config
import { OrderRouterTestSetup } from "@test/config/OrderRouterTestSetup.t.sol";
// Types
import { AllowanceTargetType } from "@src/types/TOnitMarketOrderRouter.sol";
import { TokenType } from "@src/types/TOnitIODPMOrderManager.sol";

// Contracts
import { OnitMarketOrderRouter } from "@src/order-manager/OnitMarketOrderRouter.v2.sol";
import { OnitIODPMOrderManager } from "@src/order-manager/OnitIODPMOrderManager.sol";

contract OrderRouterTestBase is OrderRouterTestSetup {
    // ----------------------------------------------------------------
    // Order router initialization helpers
    // ----------------------------------------------------------------
    function initializeOrderRouterForTestMarket(address market) public {
        bytes memory orderRouterInitData = encodeOrderRouterInitData(
            tokenAAddress,
            someMarketsTokenAdmin,
            orderRouterAddress,
            SPENDERS,
            AMOUNTS,
            INITIAL_BACKING,
            block.timestamp + 1 days,
            someMarketsTokenAdminPk
        );

        vm.prank(market);
        orderRouter.initializeOrderRouterForMarket(
            tokenAAddress, someMarketsTokenAdmin, INITIAL_BACKING, orderRouterInitData
        );
    }

    function encodeOrderRouterInitData(
        address token,
        address tokenOwner,
        address orderRouterAddress,
        address[] memory spenders,
        uint256[] memory amounts,
        uint256 initialBacking,
        uint256 deadline,
        uint256 privateKey
    )
        public
        view
        returns (bytes memory)
    {
        uint256 totalAmount;
        for (uint256 i = 0; i < spenders.length; i++) {
            totalAmount += amounts[i];
        }
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            token, tokenOwner, orderRouterAddress, totalAmount + initialBacking, deadline, privateKey
        );
        return abi.encode(deadline, v, r, s, spenders, amounts);
    }

    // Override for simple case with no allowances
    function encodeOrderRouterInitData(
        address token,
        address tokenOwner,
        address orderRouterAddress,
        uint256 initialBacking,
        uint256 deadline,
        uint256 privateKey
    )
        public
        view
        returns (bytes memory)
    {
        address[] memory spenders = new address[](0);
        uint256[] memory amounts = new uint256[](0);
        return encodeOrderRouterInitData(
            token, tokenOwner, orderRouterAddress, spenders, amounts, initialBacking, deadline, privateKey
        );
    }

    function encodeOrderRouterPermitData(uint256 futureFunds, uint256 spendDeadline, uint8 v, bytes32 r, bytes32 s)
        public
        pure
        returns (bytes memory)
    {
        return abi.encode(futureFunds, spendDeadline, v, r, s);
    }

    // ----------------------------------------------------------------
    // Order router order helpers
    // ----------------------------------------------------------------

    function createEmptyOrderData() public pure returns (bytes memory) {
        address[] memory emptyAllowedAddresses = new address[](0);
        bytes memory emptyPermitData = new bytes(0);
        return abi.encode(emptyAllowedAddresses, emptyPermitData);
    }

    function createOrderData(
        address token,
        address owner,
        address,
        uint256 amount,
        uint256 deadline,
        uint256 privateKey
    )
        public
        view
        returns (bytes memory)
    {
        // address[] memory allowedAddresses = new address[](1);
        // allowedAddresses[0] = market;

        (uint8 v, bytes32 r, bytes32 s) =
            getPermitSignature(token, owner, orderRouterAddress, amount, deadline, privateKey);
        bytes memory permitData = abi.encode(0, deadline, v, r, s);

        return permitData;
    }

    function getPermitSignature(
        address tokenAddress,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint256 privateKey
    )
        public
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        ERC20 token = ERC20(tokenAddress);
        uint256 nonce = token.nonces(owner);
        bytes32 DOMAIN_SEPARATOR = token.DOMAIN_SEPARATOR();

        // Prepare the permit data
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        owner,
                        spender,
                        value,
                        nonce,
                        deadline
                    )
                )
            )
        );

        // Sign the permit hash
        (v, r, s) = vm.sign(privateKey, permitHash);
    }

    function encodeTypeAndAddressToUint256(TokenType tokenManagerType, address tokenAddress)
        public
        pure
        returns (uint256)
    {
        return uint256(tokenManagerType) << 160 | uint256(uint160(tokenAddress));
    }

    function decodeTypeAndAddressFromUint256(uint256 value) public pure returns (TokenType, address) {
        TokenType tokenType = TokenType(value >> 160);
        address tokenAddress = address(uint160(value & type(uint160).max));

        return (tokenType, tokenAddress);
    }
}

// ----------------------------------------------------------------
// Harness for OnitMarketOrderRouter
// ----------------------------------------------------------------

contract OnitMarketOrderRouterHarness is OnitMarketOrderRouter {
    constructor() OnitMarketOrderRouter() { }

    function setAllowances(
        AllowanceTargetType allowanceTargetType,
        address allower,
        address target,
        address[] memory spenders,
        uint256[] memory amounts
    )
        external
        returns (int256)
    {
        return _setAllowances(allowanceTargetType, allower, target, spenders, amounts);
    }

    function executeOrder(
        address market,
        address token,
        address buyer,
        uint256 betAmount,
        int256[] memory bucketIds,
        int256[] memory shares
    )
        external
    {
        // TODO add tests where buyer and payer are different
        _executeBuyOrder(market, token, buyer, buyer, betAmount, bucketIds, shares);
    }

    function handleTokenPermit(address buyer, address token, uint256 amount, bytes memory orderData) external {
        _handleTokenPermit(buyer, token, amount, orderData);
    }

    function permitErc20ForOrder(address permitter, address token, uint256 amount, bytes memory permitData) external {
        _permitErc20ForOrder(permitter, token, amount, permitData);
    }
}
