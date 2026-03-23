// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Setup} from "./utils/Setup.sol";
import {StrategyHandler} from "./utils/StrategyHandler.sol";

contract InvariantTest is Setup {
    StrategyHandler public handler;
    address internal nonWhitelisted;

    function setUp() public override {
        super.setUp();

        handler = new StrategyHandler(strategy, asset, usd3, susd3, user, keeper, profitMaxUnlockTime);
        nonWhitelisted = makeAddr("invariantNonWhitelisted");

        targetContract(address(handler));
    }

    function invariant_depositLimitRespected() public view {
        uint256 limit = strategy.depositLimit();
        if (limit < type(uint256).max) {
            assertLe(strategy.totalAssets(), limit + 2, "totalAssets exceeds depositLimit");
        }
    }

    function invariant_whitelistEnforced() public view {
        assertEq(strategy.availableDepositLimit(nonWhitelisted), 0, "non-whitelisted should have 0 limit");
    }

    function invariant_noLooseUSD3AfterTend() public {
        vm.prank(keeper);
        try strategy.tend() {} catch {}

        assertEq(strategy.balanceOfVault(), 0, "should have no loose USD3 after tend");
    }

    function invariant_solvent() public view {
        if (strategy.totalSupply() > 0) {
            assertGt(strategy.totalAssets(), 0, "shares exist without assets");
        }
    }
}
