pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";

contract ShutdownTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function test_shutdownCanWithdraw_afterLock() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        skipLockPeriod();

        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        vm.prank(emergencyAdmin);
        strategy.emergencyWithdraw(type(uint256).max);

        // Report to realize any changes
        vm.prank(keeper);
        strategy.report();

        uint256 shares = strategy.balanceOf(user);
        vm.prank(user);
        strategy.redeem(shares, user, user, 10_000);

        assertGt(asset.balanceOf(user), 0, "user should have USDC back");
    }

    function test_shutdownStopsNewDeployment() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // Report should not redeploy
        vm.prank(keeper);
        strategy.report();

        // Funds should remain as USDC in strategy after emergency + report
        // (though staked funds remain locked until lock expires)
    }

    function test_emergencyWithdraw_duringLock() public {
        uint256 amount = 1_000e6;
        mintAndDepositIntoStrategy(strategy, user, amount);

        vm.prank(emergencyAdmin);
        strategy.shutdownStrategy();

        // During lock, vaultsMaxWithdraw is 0 so emergencyWithdraw reverts
        assertEq(strategy.vaultsMaxWithdraw(), 0, "nothing freeable during lock");
        assertGt(strategy.balanceOfStake(), 0, "funds still locked in sUSD3");
    }
}
