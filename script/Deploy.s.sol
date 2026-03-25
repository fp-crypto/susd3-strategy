// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {Strategy} from "../src/Strategy.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";

interface ICreateX {
    struct Values {
        uint256 constructorAmount;
        uint256 initCallAmount;
    }

    function deployCreate2AndInit(
        bytes32 salt,
        bytes memory initCode,
        bytes memory data,
        Values memory values
    ) external payable returns (address);

    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) external view returns (address);
}

/// @notice Deploy Strategy via CreateX CREATE2.
/// @dev Salt format: bytes 0-19 = msg.sender, byte 20 = 0x00, bytes 21-31 = 0.
///
///  Usage:
///   forge script script/Deploy.s.sol --rpc-url $ETH_RPC_URL \
///     --account sms-signer-2024 --sender <YOUR_ADDRESS> --broadcast
contract DeployScript is Script {
    ICreateX constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    string constant NAME = "sUSD3 Compounder";

    function run() external {
        address deployer = msg.sender;

        // Permissioned salt: [deployer (20 bytes)] [0x00 (1 byte)] [zeros (11 bytes)]
        bytes32 salt = bytes32(uint256(uint160(deployer)) << 96);

        bytes memory initCode = abi.encodePacked(type(Strategy).creationCode, abi.encode(NAME));
        bytes memory initCall = abi.encodeWithSignature("setPendingManagement(address)", deployer);

        bytes32 initCodeHash = keccak256(initCode);
        address predicted = CREATEX.computeCreate2Address(salt, initCodeHash);
        console.log("Deploying to:", predicted);

        vm.startBroadcast();

        address strategy = CREATEX.deployCreate2AndInit(
            salt, initCode, initCall, ICreateX.Values(0, 0)
        );
        console.log("Strategy deployed at:", strategy);

        IStrategyInterface(strategy).acceptManagement();
        console.log("Management transferred to:", deployer);

        vm.stopBroadcast();
    }
}
