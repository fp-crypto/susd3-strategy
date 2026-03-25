// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@tokenized-strategy/BaseStrategy.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract ForkDeployedTest is Test {
    IStrategyInterface constant strategy = IStrategyInterface(0xb44EE7869b9D47cd605B05022c8Bd8612EBe53EE);
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;


    function setUp() public {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
    }

    function test_depositAndStake() public {
        uint256 amount = 1_000e6;
        address user = makeAddr("testUser");

        vm.prank(strategy.management());
        strategy.setAllowed(user, true);

        deal(USDC, user, amount);

        vm.startPrank(user);
        ERC20(USDC).approve(address(strategy), amount);
        strategy.deposit(amount, user);
        vm.stopPrank();

        assertGt(strategy.balanceOfStake(), 0, "should have staked position");
        assertEq(strategy.balanceOfVault(), 0, "no loose USD3 expected");
        assertEq(strategy.balanceOfAsset(), 0, "no loose USDC expected");
        assertGt(strategy.balanceOf(user), 0, "user should have shares");
    }
}
