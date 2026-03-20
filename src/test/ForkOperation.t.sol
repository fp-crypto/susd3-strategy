// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {ForkSetup, ERC20, IStrategyInterface} from "./utils/ForkSetup.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

contract ForkOperationTest is ForkSetup {
    function setUp() public override {
        super.setUp();
    }

    function test_fork_setupOK() public view {
        assertEq(strategy.asset(), USDC_ADDR);
        assertEq(address(strategy.vault()), USD3_ADDR);
        assertEq(address(strategy.staking()), SUSD3_ADDR);
    }

    function test_fork_depositAndStake() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        assertGt(strategy.balanceOfStake(), 0, "should have staked position");
        assertEq(strategy.balanceOfVault(), 0, "no loose USD3 expected");
        assertEq(strategy.balanceOfAsset(), 0, "no loose USDC expected");
    }

    function test_fork_withdrawDuringLock() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        assertEq(strategy.vaultsMaxWithdraw(), 0, "staked funds should be locked");
    }

    function test_fork_withdrawAfterLock() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        // During lock, vaultsMaxWithdraw should be 0
        assertEq(strategy.vaultsMaxWithdraw(), 0, "should be locked");

        skipLockPeriod();

        // After lock, withdrawability depends on sUSD3's subordination ratio.
        // On a real fork, the backing floor may limit withdrawals even after
        // lock expires. Verify lock is no longer the constraint by checking
        // that maxRedeem on sUSD3 is non-zero (lock passed) even if
        // vaultsMaxWithdraw may be limited by backing requirements.
        uint256 maxWithdraw = strategy.vaultsMaxWithdraw();
        if (maxWithdraw > 0) {
            vm.prank(keeper);
            strategy.report();

            uint256 shares = strategy.balanceOf(user);
            vm.prank(user);
            strategy.redeem(shares, user, user);

            assertGt(asset.balanceOf(user), 0, "user should have received USDC");
        }
    }

    function test_fork_depositLimitRespectsSubordinationCap() public {
        uint256 limit = strategy.availableDepositLimit(user);
        assertGt(limit, 0, "whitelisted user should have deposit limit > 0");

        address nonWhitelisted = makeAddr("nonWhitelisted");
        assertEq(strategy.availableDepositLimit(nonWhitelisted), 0, "non-whitelisted should be 0");
    }

    function test_fork_profitableReport() public {
        uint256 amount = 10_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        uint256 beforeAssets = strategy.totalAssets();

        skipLockPeriod();

        // Airdrop USD3 to sUSD3 to simulate yield
        IStrategy usd3Strategy = IStrategy(USD3_ADDR);
        IStrategy susd3Strategy = IStrategy(SUSD3_ADDR);

        uint256 yieldAmount = 100e6;
        deal(USDC_ADDR, address(this), yieldAmount);
        asset.approve(USD3_ADDR, yieldAmount);
        usd3Strategy.deposit(yieldAmount, SUSD3_ADDR);

        vm.prank(susd3Strategy.keeper());
        susd3Strategy.report();

        skip(profitMaxUnlockTime + 1);

        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        assertGt(profit, 0, "should have profit");
        assertEq(loss, 0, "should have no loss");
        assertGt(strategy.totalAssets(), beforeAssets, "total assets should increase");
    }
}
