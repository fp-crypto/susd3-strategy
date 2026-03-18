// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";

import {Strategy, ERC20} from "../../Strategy.sol";
import {StrategyFactory} from "../../StrategyFactory.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";
import {TokenizedStrategy} from "@tokenized-strategy/TokenizedStrategy.sol";

import {USD3} from "@3jane/usd3/USD3.sol";
import {sUSD3} from "@3jane/usd3/sUSD3.sol";
import {MorphoCredit} from "@3jane/MorphoCredit.sol";
import {IMorpho, MarketParams, Id} from "@3jane/interfaces/IMorpho.sol";
import {MarketParamsLib} from "@3jane/libraries/MarketParamsLib.sol";
import {IrmMock} from "@3jane/mocks/IrmMock.sol";
import {HelperMock} from "@3jane/mocks/HelperMock.sol";
import {CreditLineMock} from "@3jane/mocks/CreditLineMock.sol";
import {ProtocolConfigLib} from "@3jane/libraries/ProtocolConfigLib.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {MockProtocolConfig} from "./MockProtocolConfig.sol";
import {MockERC20} from "./MockERC20.sol";
import {MockWaUSDC} from "./MockWaUSDC.sol";
import {MockStrategyFactory} from "./MockStrategyFactory.sol";

interface IFactory {
    function governance() external view returns (address);
    function set_protocol_fee_bps(uint16) external;
    function set_protocol_fee_recipient(address) external;
}

contract Setup is Test, IEvents {
    ERC20 public asset; // USDC
    IStrategyInterface public strategy;
    StrategyFactory public strategyFactory;

    USD3 public usd3;
    sUSD3 public susd3;
    MockWaUSDC public waUSDC;
    MockProtocolConfig public protocolConfig;
    HelperMock public helper;

    address public user = address(10);
    address public keeper = address(4);
    address public management = address(1);
    address public performanceFeeRecipient = address(3);
    address public emergencyAdmin = address(5);

    address public factory;
    uint256 public decimals;
    uint256 public MAX_BPS = 10_000;

    uint256 public maxFuzzAmount = 1_000_000e6;
    uint256 public minFuzzAmount = 10_000; // 0.01 USDC

    uint256 public profitMaxUnlockTime = 10 days;

    function setUp() public virtual {
        _deployMockTokens();
        _deployTokenizedStrategy();
        _deployUSD3AndSUSD3();

        strategyFactory = new StrategyFactory(
            management,
            performanceFeeRecipient,
            keeper,
            emergencyAdmin,
            address(usd3),
            address(susd3)
        );

        strategy = IStrategyInterface(
            strategyFactory.newStrategy(address(asset), "sUSD3 Compounder")
        );

        vm.prank(management);
        strategy.acceptManagement();

        // Whitelist the user for deposits
        vm.prank(management);
        strategy.setDepositorWhitelist(user, true);

        factory = strategy.FACTORY();
        decimals = asset.decimals();

        vm.label(keeper, "keeper");
        vm.label(factory, "factory");
        vm.label(address(asset), "USDC");
        vm.label(management, "management");
        vm.label(address(strategy), "strategy");
        vm.label(address(usd3), "USD3");
        vm.label(address(susd3), "sUSD3");
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function _deployMockTokens() internal {
        // Deploy and etch USDC at mainnet address
        address usdcAddr = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        MockERC20 mockUsdc = new MockERC20("USD Coin", "USDC", 6);
        vm.etch(usdcAddr, address(mockUsdc).code);
        vm.store(usdcAddr, bytes32(uint256(5)), bytes32(uint256(6)));
        asset = ERC20(usdcAddr);

        // Deploy and etch waUSDC at mainnet address
        address waUSDCAddr = 0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E;
        MockWaUSDC mockWaUSDC = new MockWaUSDC(usdcAddr);
        vm.etch(waUSDCAddr, address(mockWaUSDC).code);
        vm.store(waUSDCAddr, bytes32(uint256(5)), bytes32(uint256(uint160(usdcAddr))));
        vm.store(waUSDCAddr, bytes32(uint256(6)), bytes32(uint256(1e6)));
        waUSDC = MockWaUSDC(waUSDCAddr);
        vm.label(waUSDCAddr, "waUSDC");
    }

    function _deployTokenizedStrategy() internal {
        MockStrategyFactory mockFactory = new MockStrategyFactory();
        TokenizedStrategy tokenizedStrategyImpl = new TokenizedStrategy(address(mockFactory));
        address expectedAddress = 0xD377919FA87120584B21279a491F82D5265A139c;
        vm.etch(expectedAddress, address(tokenizedStrategyImpl).code);
        vm.label(expectedAddress, "TokenizedStrategy");
    }

    function _deployUSD3AndSUSD3() internal {
        protocolConfig = new MockProtocolConfig();
        protocolConfig.setConfig(ProtocolConfigLib.DEBT_CAP, 100_000_000e6);

        // Deploy MorphoCredit
        address morphoOwner = makeAddr("MorphoOwner");
        address proxyAdminOwner = makeAddr("ProxyAdminOwner");

        MorphoCredit morphoImpl = new MorphoCredit(address(protocolConfig));
        ProxyAdmin morphoProxyAdmin = new ProxyAdmin();
        bytes memory morphoInitData = abi.encodeWithSelector(MorphoCredit.initialize.selector, morphoOwner);
        TransparentUpgradeableProxy morphoProxy =
            new TransparentUpgradeableProxy(address(morphoImpl), address(morphoProxyAdmin), morphoInitData);
        IMorpho morpho = IMorpho(address(morphoProxy));

        // Create market
        IrmMock irm = new IrmMock();
        CreditLineMock creditLine = new CreditLineMock(address(morpho));
        MarketParams memory marketParams = MarketParams({
            loanToken: address(waUSDC),
            collateralToken: address(asset),
            oracle: address(0),
            irm: address(irm),
            lltv: 0,
            creditLine: address(creditLine)
        });

        vm.startPrank(morphoOwner);
        morpho.enableIrm(address(irm));
        morpho.enableLltv(0);
        morpho.createMarket(marketParams);
        vm.stopPrank();

        // Deploy USD3
        USD3 usd3Impl = new USD3();
        ProxyAdmin usd3ProxyAdmin = new ProxyAdmin();
        bytes memory usd3InitData = abi.encodeWithSelector(
            USD3.initialize.selector,
            address(morpho),
            MarketParamsLib.id(marketParams),
            management,
            keeper
        );
        TransparentUpgradeableProxy usd3Proxy =
            new TransparentUpgradeableProxy(address(usd3Impl), address(usd3ProxyAdmin), usd3InitData);
        USD3(address(usd3Proxy)).reinitialize();
        usd3 = USD3(address(usd3Proxy));

        vm.prank(morphoOwner);
        MorphoCredit(address(morpho)).setUsd3(address(usd3));

        helper = new HelperMock(address(morpho));
        vm.prank(morphoOwner);
        MorphoCredit(address(morpho)).setHelper(address(helper));

        // Deploy sUSD3
        sUSD3 susd3Impl = new sUSD3();
        ProxyAdmin susd3ProxyAdmin = new ProxyAdmin();
        bytes memory susd3InitData = abi.encodeWithSelector(
            sUSD3.initialize.selector,
            address(usd3),
            management,
            keeper
        );
        TransparentUpgradeableProxy susd3Proxy =
            new TransparentUpgradeableProxy(address(susd3Impl), address(susd3ProxyAdmin), susd3InitData);
        susd3 = sUSD3(address(susd3Proxy));

        // Link USD3 and sUSD3
        vm.prank(management);
        usd3.setSUSD3(address(susd3));
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
        airdrop(asset, _user, _amount);
        depositIntoStrategy(_strategy, _user, _amount);
    }

    function checkStrategyTotals(
        IStrategyInterface _strategy,
        uint256 _totalAssets,
        uint256 _totalDebt,
        uint256 _totalIdle
    ) public view {
        uint256 _assets = _strategy.totalAssets();
        uint256 _balance = ERC20(_strategy.asset()).balanceOf(address(_strategy));
        uint256 _idle = _balance > _assets ? _assets : _balance;
        uint256 _debt = _assets - _idle;
        assertEq(_assets, _totalAssets, "!totalAssets");
        assertEq(_debt, _totalDebt, "!totalDebt");
        assertEq(_idle, _totalIdle, "!totalIdle");
        assertEq(_totalAssets, _totalDebt + _totalIdle, "!Added");
    }

    function airdrop(ERC20 _asset, address _to, uint256 _amount) public {
        uint256 balanceBefore = _asset.balanceOf(_to);
        deal(address(_asset), _to, balanceBefore + _amount);
    }

    function setFees(uint16 _protocolFee, uint16 _performanceFee) public {
        address gov = IFactory(factory).governance();

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_recipient(gov);

        vm.prank(gov);
        IFactory(factory).set_protocol_fee_bps(_protocolFee);

        vm.prank(management);
        strategy.setPerformanceFee(_performanceFee);
    }

    function skipLockPeriod() internal {
        skip(91 days);
    }
}
