// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {IStrategyInterface} from "../src/interfaces/IStrategyInterface.sol";

interface ICommonTrigger {
    function setCustomStrategyTrigger(address _strategy, address _trigger) external;
}

/// @notice Configure the deployed sUSD3 strategy to match yvUSD standards.
contract ConfigureScript is Script {
    address constant STRATEGY = 0xb44EE7869b9D47cd605B05022c8Bd8612EBe53EE;
    address constant ACCOUNTANT = 0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69;
    address constant KEEPER = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;
    address constant MANAGEMENT = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
    address constant COMMON_TRIGGER = 0xA045D4dAeA28BA7Bfe234c96eAa03daFae85A147;
    address constant REPORT_TRIGGER = 0xb9F57B62Cbe9463da16E5b75e3B809321a0eA871;
    address constant DEPOSITOR = 0x696d02Db93291651ED510704c9b286841d506987;

    function run() external {
        IStrategyInterface strategy = IStrategyInterface(STRATEGY);

        vm.startBroadcast();

        strategy.setPerformanceFee(0);
        strategy.setProfitMaxUnlockTime(0);
        strategy.setPerformanceFeeRecipient(ACCOUNTANT);
        strategy.setKeeper(KEEPER);
        strategy.setAllowed(DEPOSITOR, true);
        strategy.setAllowed(msg.sender, true);

        ICommonTrigger(COMMON_TRIGGER).setCustomStrategyTrigger(STRATEGY, REPORT_TRIGGER);

        // Last: pending management transfer (new mgmt must call acceptManagement)
        strategy.setPendingManagement(MANAGEMENT);

        vm.stopBroadcast();

        console.log("Strategy configured:", STRATEGY);
    }
}
