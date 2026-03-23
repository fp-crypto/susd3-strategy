// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";

contract FuzzTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_fuzz_depositAndWithdraw(uint256 _amount) public {
        _amount = bound(_amount, minFuzzAmount, maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        skipLockPeriod();

        vm.prank(keeper);
        strategy.report();

        uint256 shares = strategy.balanceOf(user);
        vm.prank(user);
        strategy.redeem(shares, user, user);

        uint256 balanceAfter = asset.balanceOf(user);
        assertApproxEqAbs(balanceAfter, _amount, 2, "should get back ~amount");
    }

    function test_fuzz_profitableReport(uint256 _amount, uint256 _yield) public {
        _amount = bound(_amount, 100_000, maxFuzzAmount);
        _yield = bound(_yield, minFuzzAmount, _amount / 10);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 beforeAssets = strategy.totalAssets();

        skipLockPeriod();

        airdrop(asset, address(this), _yield);
        asset.approve(address(usd3), _yield);
        usd3.deposit(_yield, address(susd3));

        vm.prank(keeper);
        susd3.report();

        skip(profitMaxUnlockTime + 1);

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertGt(profit, 0, "should have profit");
        assertEq(loss, 0, "should have no loss");
        assertGt(strategy.totalAssets(), beforeAssets, "total assets should increase");
    }

    function test_fuzz_depositLimit(uint256 _limit, uint256 _amount) public {
        _limit = bound(_limit, minFuzzAmount, maxFuzzAmount);
        _amount = bound(_amount, minFuzzAmount, _limit);

        vm.prank(management);
        strategy.setDepositLimit(_limit);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        if (_amount == _limit) {
            assertEq(strategy.availableDepositLimit(user), 0);
        }

        uint256 remaining = strategy.availableDepositLimit(user);
        if (remaining == 0) {
            uint256 extra = 1e6;
            airdrop(asset, user, extra);
            vm.startPrank(user);
            asset.approve(address(strategy), extra);
            vm.expectRevert("ERC4626: deposit more than max");
            strategy.deposit(extra, user);
            vm.stopPrank();
        }
    }

    function test_fuzz_multipleDepositsAndWithdraws(uint256 _amount1, uint256 _amount2) public {
        _amount1 = bound(_amount1, minFuzzAmount, maxFuzzAmount / 2);
        _amount2 = bound(_amount2, minFuzzAmount, maxFuzzAmount / 2);

        address user2 = makeAddr("user2");
        vm.prank(management);
        strategy.setAllowed(user2, true);

        mintAndDepositIntoStrategy(strategy, user, _amount1);
        mintAndDepositIntoStrategy(strategy, user2, _amount2);

        uint256 totalDeposited = _amount1 + _amount2;
        assertApproxEqAbs(strategy.totalAssets(), totalDeposited, 2, "total assets should match deposits");

        skipLockPeriod();

        vm.prank(keeper);
        strategy.report();

        uint256 shares1 = strategy.balanceOf(user);
        vm.prank(user);
        strategy.redeem(shares1, user, user);

        uint256 shares2 = strategy.balanceOf(user2);
        vm.prank(user2);
        strategy.redeem(shares2, user2, user2);

        uint256 totalWithdrawn = asset.balanceOf(user) + asset.balanceOf(user2);
        assertApproxEqAbs(totalWithdrawn, totalDeposited, 2, "total withdrawn should match total deposited");
        assertEq(strategy.totalSupply(), 0, "no shares should remain");
    }
}
