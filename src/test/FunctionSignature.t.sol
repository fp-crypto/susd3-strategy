// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";

contract FunctionSignatureTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_viewFunctions() public view {
        strategy.asset();
        strategy.vault();
        strategy.staking();
        strategy.balanceOfAsset();
        strategy.balanceOfVault();
        strategy.balanceOfStake();
        strategy.valueOfVault();
        strategy.vaultsMaxWithdraw();
        strategy.totalAssets();
        strategy.availableDepositLimit(user);
        strategy.availableWithdrawLimit(user);
        strategy.open();
        strategy.allowed(user);
    }
}
