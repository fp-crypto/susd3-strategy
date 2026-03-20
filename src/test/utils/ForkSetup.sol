// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {Strategy, ERC20} from "../../Strategy.sol";
import {StrategyFactory} from "../../StrategyFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";

contract ForkSetup is Test, IEvents {
    address internal constant USDC_ADDR = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USD3_ADDR = 0x056B269Eb1f75477a8666ae8C7fE01b64dD55eCc;
    address internal constant SUSD3_ADDR = 0xf689555121e529Ff0463e191F9Bd9d1E496164a7;

    uint256 internal constant FORK_BLOCK = 22089000;

    ERC20 public asset;
    IStrategyInterface public strategy;
    StrategyFactory public strategyFactory;

    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);

    address public factory;
    uint256 public decimals;
    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("FORK_RPC_URL"), FORK_BLOCK);

        asset = ERC20(USDC_ADDR);

        strategyFactory = new StrategyFactory(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin
        );

        strategy = IStrategyInterface(
            strategyFactory.newStrategy("sUSD3 Compounder")
        );

        vm.prank(management);
        strategy.acceptManagement();

        vm.prank(management);
        strategy.setDepositorWhitelist(user, true);

        factory = strategy.FACTORY();
        decimals = asset.decimals();

        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(USDC_ADDR, "USDC");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(USD3_ADDR, "USD3");
        vm.label(SUSD3_ADDR, "sUSD3");
    }

    function depositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(
        IStrategyInterface _strategy,
        address _user,
        uint256 _amount
    ) public {
        deal(USDC_ADDR, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    function skipLockPeriod() internal {
        skip(91 days);
    }
}
