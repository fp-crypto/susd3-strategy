// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {sUSD3} from "@3jane/usd3/sUSD3.sol";
import {USD3} from "@3jane/usd3/USD3.sol";

contract StrategyHandler is Test {
    IStrategyInterface public strategy;
    ERC20 public asset;
    USD3 public usd3;
    sUSD3 public susd3;

    address public user;
    address public keeper;
    uint256 public profitMaxUnlockTime;

    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;

    uint256 internal constant MIN_AMOUNT = 10_000;
    uint256 internal constant MAX_AMOUNT = 1_000_000e6;

    constructor(
        IStrategyInterface _strategy,
        ERC20 _asset,
        USD3 _usd3,
        sUSD3 _susd3,
        address _user,
        address _keeper,
        uint256 _profitMaxUnlockTime
    ) {
        strategy = _strategy;
        asset = _asset;
        usd3 = _usd3;
        susd3 = _susd3;
        user = _user;
        keeper = _keeper;
        profitMaxUnlockTime = _profitMaxUnlockTime;
    }

    function deposit(uint256 _amount) external {
        _amount = bound(_amount, MIN_AMOUNT, MAX_AMOUNT);

        uint256 balanceBefore = asset.balanceOf(user);
        deal(address(asset), user, balanceBefore + _amount);

        vm.startPrank(user);
        asset.approve(address(strategy), _amount);
        try strategy.deposit(_amount, user) {
            ghost_totalDeposited += _amount;
        } catch {}
        vm.stopPrank();
    }

    function withdraw(uint256 _shares) external {
        uint256 userShares = strategy.balanceOf(user);
        if (userShares == 0) return;

        _shares = bound(_shares, 1, userShares);

        vm.prank(user);
        try strategy.redeem(_shares, user, user) returns (uint256 assets) {
            ghost_totalWithdrawn += assets;
        } catch {}
    }

    function report() external {
        vm.prank(keeper);
        try strategy.report() {} catch {}
    }

    function tend() external {
        vm.prank(keeper);
        try strategy.tend() {} catch {}
    }

    function simulateYield(uint256 _yield) external {
        _yield = bound(_yield, MIN_AMOUNT, MAX_AMOUNT / 10);

        uint256 balanceBefore = asset.balanceOf(address(this));
        deal(address(asset), address(this), balanceBefore + _yield);

        asset.approve(address(usd3), _yield);
        try usd3.deposit(_yield, address(susd3)) {} catch {
            return;
        }

        vm.prank(keeper);
        try susd3.report() {} catch {}

        skip(profitMaxUnlockTime + 1);

        vm.prank(keeper);
        try strategy.report() {} catch {}
    }

    function skipTime(uint256 _seconds) external {
        _seconds = bound(_seconds, 1, 100 days);
        skip(_seconds);
    }
}
