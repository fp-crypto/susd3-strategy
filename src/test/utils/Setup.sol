// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";

import {Strategy, ERC20} from "../../Strategy.sol";
import {IStrategyInterface} from "../../interfaces/IStrategyInterface.sol";
import {IEvents} from "@tokenized-strategy/interfaces/IEvents.sol";
import {TokenizedStrategy} from "@tokenized-strategy/TokenizedStrategy.sol";

import {USD3} from "@3jane/usd3/USD3.sol";
import {sUSD3} from "@3jane/usd3/sUSD3.sol";
import {MorphoCredit} from "@3jane/MorphoCredit.sol";
import {IMorpho, MarketParams} from "@3jane/interfaces/IMorpho.sol";
import {MarketParamsLib} from "@3jane/libraries/MarketParamsLib.sol";
import {IrmMock} from "@3jane/mocks/IrmMock.sol";
import {HelperMock} from "@3jane/mocks/HelperMock.sol";
import {CreditLineMock} from "@3jane/mocks/CreditLineMock.sol";
import {ProtocolConfigLib} from "@3jane/libraries/ProtocolConfigLib.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
// ProxyAdmin + TransparentUpgradeableProxy still needed for MorphoCredit deployment

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
    // Hardcoded addresses matching Strategy constants
    address internal constant USDC_ADDR = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USD3_ADDR = 0x056B269Eb1f75477a8666ae8C7fE01b64dD55eCc;
    address internal constant SUSD3_ADDR = 0xf689555121e529Ff0463e191F9Bd9d1E496164a7;
    address internal constant WAUSDC_ADDR = 0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E;
    address internal constant TOKENIZED_STRATEGY_ADDR = 0xD377919FA87120584B21279a491F82D5265A139c;
    address internal constant JANE_ADDR = 0x333333330522F64EE8d0b3039c460b41670e3404;
    address internal constant REWARDS_DISTRIBUTOR = 0xaC6985D4dBcd89CCAD71DB9bf0309eaF57F064e8;

    // OZ v5 ERC-7201 Initializable storage slot
    bytes32 internal constant _INITIALIZABLE_SLOT = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;
    // Yearn TokenizedStrategy base storage slot (holds StrategyData.asset at offset 0)
    bytes32 internal constant _TOKENIZED_STRATEGY_SLOT = bytes32(uint256(keccak256("yearn.base.strategy.storage")) - 1);

    ERC20 public asset; // USDC
    IStrategyInterface public strategy;
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

        strategy = IStrategyInterface(address(new Strategy("sUSD3 Compounder")));
        strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        strategy.setKeeper(keeper);
        strategy.setPendingManagement(management);
        strategy.setEmergencyAdmin(emergencyAdmin);

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
        vm.label(performanceFeeRecipient, "performanceFeeRecipient");
    }

    function _deployMockTokens() internal {
        MockERC20 mockUsdc = new MockERC20("USD Coin", "USDC", 6);
        vm.etch(USDC_ADDR, address(mockUsdc).code);
        vm.store(USDC_ADDR, bytes32(uint256(5)), bytes32(uint256(6)));
        asset = ERC20(USDC_ADDR);

        MockERC20 mockJane = new MockERC20("Jane Token", "JANE", 18);
        vm.etch(JANE_ADDR, address(mockJane).code);

        MockWaUSDC mockWaUSDC = new MockWaUSDC(USDC_ADDR);
        vm.etch(WAUSDC_ADDR, address(mockWaUSDC).code);
        vm.store(WAUSDC_ADDR, bytes32(uint256(5)), bytes32(uint256(uint160(USDC_ADDR))));
        vm.store(WAUSDC_ADDR, bytes32(uint256(6)), bytes32(uint256(1e6)));
        waUSDC = MockWaUSDC(WAUSDC_ADDR);
    }

    function _deployTokenizedStrategy() internal {
        MockStrategyFactory mockFactory = new MockStrategyFactory();
        TokenizedStrategy tokenizedStrategyImpl = new TokenizedStrategy(address(mockFactory));
        vm.etch(TOKENIZED_STRATEGY_ADDR, address(tokenizedStrategyImpl).code);
    }

    function _deployUSD3AndSUSD3() internal {
        protocolConfig = new MockProtocolConfig();
        protocolConfig.setConfig(ProtocolConfigLib.DEBT_CAP, 100_000_000e6);

        address morphoOwner = makeAddr("MorphoOwner");

        MorphoCredit morphoImpl = new MorphoCredit(address(protocolConfig));
        ProxyAdmin morphoProxyAdmin = new ProxyAdmin();
        bytes memory morphoInitData = abi.encodeWithSelector(MorphoCredit.initialize.selector, morphoOwner);
        TransparentUpgradeableProxy morphoProxy =
            new TransparentUpgradeableProxy(address(morphoImpl), address(morphoProxyAdmin), morphoInitData);
        IMorpho morpho = IMorpho(address(morphoProxy));

        IrmMock irm = new IrmMock();
        CreditLineMock creditLine = new CreditLineMock(address(morpho));
        MarketParams memory marketParams = MarketParams({
            loanToken: address(waUSDC),
            collateralToken: USDC_ADDR,
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

        // Etch USD3 implementation directly at the hardcoded address
        USD3 usd3Impl = new USD3();
        vm.etch(USD3_ADDR, address(usd3Impl).code);
        _clearStorage(USD3_ADDR);
        USD3(USD3_ADDR).initialize(address(morpho), MarketParamsLib.id(marketParams), management, keeper);
        USD3(USD3_ADDR).reinitialize();
        usd3 = USD3(USD3_ADDR);

        vm.prank(morphoOwner);
        MorphoCredit(address(morpho)).setUsd3(USD3_ADDR);

        helper = new HelperMock(address(morpho));
        vm.prank(morphoOwner);
        MorphoCredit(address(morpho)).setHelper(address(helper));

        // Etch sUSD3 implementation directly at the hardcoded address
        sUSD3 susd3Impl = new sUSD3();
        vm.etch(SUSD3_ADDR, address(susd3Impl).code);
        _clearStorage(SUSD3_ADDR);
        sUSD3(SUSD3_ADDR).initialize(USD3_ADDR, management, keeper);
        susd3 = sUSD3(SUSD3_ADDR);

        vm.prank(management);
        usd3.setSUSD3(SUSD3_ADDR);
    }

    function depositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
        vm.prank(_user);
        asset.approve(address(_strategy), _amount);

        vm.prank(_user);
        _strategy.deposit(_amount, _user);
    }

    function mintAndDepositIntoStrategy(IStrategyInterface _strategy, address _user, uint256 _amount) public {
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

    function _clearStorage(address target) internal {
        vm.store(target, _INITIALIZABLE_SLOT, bytes32(0));
        vm.store(target, _TOKENIZED_STRATEGY_SLOT, bytes32(0));
        for (uint256 i; i < 103; i++) {
            vm.store(target, bytes32(i), bytes32(0));
        }
    }
}
