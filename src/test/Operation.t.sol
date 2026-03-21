// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

contract OperationTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_setupStrategyOK() public view {
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(address(strategy.vault()), address(usd3));
        assertEq(address(strategy.staking()), address(susd3));
    }

    function test_depositAndStake() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        assertGt(strategy.balanceOfStake(), 0, "should have staked position");
        assertEq(strategy.balanceOfVault(), 0, "no loose USD3 expected");
        assertEq(strategy.balanceOfAsset(), 0, "no loose USDC expected");
    }

    function test_depositWhitelistEnforced() public {
        address nonWhitelisted = makeAddr("nonWhitelisted");
        uint256 amount = 1_000e6;
        airdrop(asset, nonWhitelisted, amount);

        assertEq(strategy.availableDepositLimit(nonWhitelisted), 0);

        vm.startPrank(nonWhitelisted);
        asset.approve(address(strategy), amount);
        vm.expectRevert("ERC4626: deposit more than max");
        strategy.deposit(amount, nonWhitelisted);
        vm.stopPrank();
    }

    function test_withdrawDuringLockReturnsZero() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        uint256 maxWithdraw = strategy.vaultsMaxWithdraw();
        assertEq(maxWithdraw, 0, "staked funds should be locked");
    }

    function test_withdrawAfterLockExpires() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        skipLockPeriod();

        uint256 maxWithdraw = strategy.vaultsMaxWithdraw();
        assertGt(maxWithdraw, 0, "should be able to withdraw after lock");

        vm.prank(keeper);
        strategy.report();

        uint256 shares = strategy.balanceOf(user);
        vm.prank(user);
        strategy.redeem(shares, user, user);

        assertGt(asset.balanceOf(user), 0, "user should have received USDC");
    }

    function test_profitableReport() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        uint256 beforeAssets = strategy.totalAssets();

        skipLockPeriod();

        // Simulate yield: airdrop USD3 tokens to sUSD3 (mimics performance fee flow)
        uint256 yieldAmount = 10e6; // 10 USDC worth of USD3
        airdrop(asset, address(this), yieldAmount);
        asset.approve(address(usd3), yieldAmount);
        usd3.deposit(yieldAmount, address(susd3));

        // Report on sUSD3 to realize the yield
        vm.prank(keeper);
        susd3.report();

        // Skip past profit unlock time so sUSD3 share price increases
        skip(profitMaxUnlockTime + 1);

        // Now our strategy should see increased value
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertGt(profit, 0, "should have profit");
        assertEq(loss, 0, "should have no loss");
        assertGt(strategy.totalAssets(), beforeAssets, "total assets should increase");
    }

    function test_tendStakesIdleUSD3() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        assertEq(strategy.balanceOfVault(), 0, "no loose USD3");
        assertGt(strategy.balanceOfStake(), 0, "should be staked");
    }

    function test_shutdownDoesNotUnlockFunds() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // During lock, vaultsMaxWithdraw is 0, so emergencyWithdraw
        // would revert with ZERO_ASSETS. Staked funds remain locked.
        assertEq(strategy.vaultsMaxWithdraw(), 0, "nothing freeable during lock");
        assertGt(strategy.balanceOfStake(), 0, "staked funds still locked");
    }

    function test_shutdownWithdrawAfterLock() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        skipLockPeriod();

        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        assertEq(strategy.balanceOfStake(), 0, "should have unstaked");
        assertGt(asset.balanceOf(address(strategy)), 0, "strategy should hold USDC");
    }

    function test_cooldownManagement() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        skipLockPeriod();

        uint256 stakingShares = ERC20(address(susd3)).balanceOf(address(strategy));

        vm.prank(management);
        strategy.startCooldown(stakingShares);

        vm.prank(management);
        strategy.cancelCooldown();

        vm.prank(user);
        vm.expectRevert("!management");
        strategy.startCooldown(stakingShares);
    }

    function test_setAuction() public {
        address fakeAuction = makeAddr("auction");

        // Non-management cannot set
        vm.prank(user);
        vm.expectRevert("!management");
        strategy.setAuction(fakeAuction);
    }

    function test_setMinAmountToSell() public {
        vm.prank(management);
        strategy.setMinAmountToSell(1e18);

        // Non-management cannot set
        vm.prank(user);
        vm.expectRevert("!management");
        strategy.setMinAmountToSell(0);
    }

    function test_reportWithoutAuction() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        skipLockPeriod();

        // Report should not revert even with no auction configured
        vm.prank(keeper);
        strategy.report();
    }

    function test_sweepRandomToken() public {
        ERC20 randomToken = ERC20(makeAddr("randomToken"));
        vm.etch(address(randomToken), address(asset).code);

        uint256 amount = 100e6;
        airdrop(randomToken, address(strategy), amount);

        address recipient = makeAddr("recipient");
        vm.prank(management);
        strategy.sweep(address(randomToken), amount, recipient);

        assertEq(randomToken.balanceOf(recipient), amount);
        assertEq(randomToken.balanceOf(address(strategy)), 0);
    }

    function test_sweepProtectedTokensReverts() public {
        vm.startPrank(management);

        vm.expectRevert("!asset");
        strategy.sweep(address(asset), 1, management);

        vm.expectRevert("!vault");
        strategy.sweep(address(usd3), 1, management);

        vm.expectRevert("!staking");
        strategy.sweep(address(susd3), 1, management);

        vm.stopPrank();
    }

    function test_sweepOnlyManagement() public {
        vm.prank(user);
        vm.expectRevert("!management");
        strategy.sweep(makeAddr("token"), 1, user);
    }

    function test_depositLimitDefault() public view {
        assertEq(strategy.depositLimit(), type(uint256).max);
    }

    function test_depositLimitCapsDeposits() public {
        uint256 limit = 1_000e6;
        vm.prank(management);
        strategy.setDepositLimit(limit);

        mintAndDepositIntoStrategy(strategy, user, limit);

        assertEq(strategy.availableDepositLimit(user), 0);

        uint256 extra = 1e6;
        airdrop(asset, user, extra);
        vm.startPrank(user);
        asset.approve(address(strategy), extra);
        vm.expectRevert("ERC4626: deposit more than max");
        strategy.deposit(extra, user);
        vm.stopPrank();
    }

    function test_setDepositLimitOnlyManagement() public {
        vm.prank(user);
        vm.expectRevert("!management");
        strategy.setDepositLimit(0);
    }

    function test_setDepositorWhitelist() public {
        address newDepositor = makeAddr("newDepositor");

        assertFalse(strategy.depositorWhitelist(newDepositor));

        vm.prank(management);
        strategy.setDepositorWhitelist(newDepositor, true);

        assertTrue(strategy.depositorWhitelist(newDepositor));

        vm.prank(user);
        vm.expectRevert("!management");
        strategy.setDepositorWhitelist(newDepositor, false);
    }
}
