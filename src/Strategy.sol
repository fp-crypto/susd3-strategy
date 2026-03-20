// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Base4626Compounder, ERC20, IStrategy} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {AuctionSwapper} from "@periphery/swappers/AuctionSwapper.sol";
import {BaseStrategy} from "@tokenized-strategy/BaseStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ISUSD3 {
    function startCooldown(uint256 shares) external;
    function cancelCooldown() external;
    function availableDepositLimit(address owner) external view returns (uint256);
}

interface IRewardsDistributor {
    function claim(address user, uint256 totalAllocation, bytes32[] calldata proof) external;
}

contract Strategy is Base4626Compounder, AuctionSwapper {
    using SafeERC20 for ERC20;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USD3 = 0x056B269Eb1f75477a8666ae8C7fE01b64dD55eCc;
    address internal constant SUSD3 = 0xf689555121e529Ff0463e191F9Bd9d1E496164a7;
    address internal constant JANE = 0x333333330522F64EE8d0b3039c460b41670e3404;
    address internal constant REWARDS_DISTRIBUTOR = 0xaC6985D4dBcd89CCAD71DB9bf0309eaF57F064e8;

    IStrategy public immutable staking;

    mapping(address => bool) public depositorWhitelist;

    event DepositorWhitelistUpdated(address indexed depositor, bool allowed);

    constructor(string memory _name) Base4626Compounder(USDC, _name, USD3) {
        staking = IStrategy(SUSD3);
        ERC20(USD3).forceApprove(SUSD3, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        CORE OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc Base4626Compounder
    function _stake() internal override {
        uint256 balance = vault.balanceOf(address(this));
        if (balance > 0) {
            staking.deposit(balance, address(this));
        }
    }

    /// @inheritdoc Base4626Compounder
    function _unStake(uint256 _amount) internal override {
        staking.withdraw(_amount, address(this), address(this));
    }

    /// @inheritdoc Base4626Compounder
    function balanceOfStake() public view override returns (uint256) {
        return staking.previewRedeem(staking.balanceOf(address(this)));
    }

    /// @inheritdoc Base4626Compounder
    function vaultsMaxWithdraw() public view override returns (uint256) {
        uint256 looseVaultShares = vault.maxRedeem(address(this));
        uint256 stakingRedeemable = staking.maxRedeem(address(this));
        uint256 redeemableVaultShares = staking.previewRedeem(stakingRedeemable);
        return vault.previewRedeem(looseVaultShares + redeemableVaultShares);
    }

    /// @inheritdoc Base4626Compounder
    function _claimAndSellRewards() internal override {
        if (useAuction && kickable(JANE) >= minAmountToSell) {
            _kickAuction(JANE);
        }
    }

    /// @inheritdoc BaseStrategy
    function _tend(
        uint256 /*_totalIdle*/
    )
        internal
        override
    {
        _stake();
    }

    /// @inheritdoc BaseStrategy
    function _tendTrigger() internal view override returns (bool) {
        return vault.balanceOf(address(this)) > 0;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT / WITHDRAW LIMITS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc Base4626Compounder
    function availableDepositLimit(address _owner) public view override returns (uint256) {
        if (!depositorWhitelist[_owner]) {
            return 0;
        }

        uint256 vaultLimit = super.availableDepositLimit(_owner);

        uint256 stakingCapUSD3 = ISUSD3(address(staking)).availableDepositLimit(address(this));
        uint256 stakingCapUSDC = vault.previewRedeem(stakingCapUSD3);

        return vaultLimit < stakingCapUSDC ? vaultLimit : stakingCapUSDC;
    }

    /*//////////////////////////////////////////////////////////////
                        REWARDS
    //////////////////////////////////////////////////////////////*/

    function claimRewards(uint256 _totalAllocation, bytes32[] calldata _proof) external {
        IRewardsDistributor(REWARDS_DISTRIBUTOR).claim(address(this), _totalAllocation, _proof);
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setDepositorWhitelist(address _depositor, bool _allowed) external onlyManagement {
        depositorWhitelist[_depositor] = _allowed;
        emit DepositorWhitelistUpdated(_depositor, _allowed);
    }

    function setAuction(address _auction) external onlyManagement {
        _setAuction(_auction);
    }

    function setUseAuction(bool _useAuction) external onlyManagement {
        _setUseAuction(_useAuction);
    }

    function setMinAmountToSell(uint256 _minAmountToSell) external onlyManagement {
        _setMinAmountToSell(_minAmountToSell);
    }

    function startCooldown(uint256 _shares) external onlyManagement {
        ISUSD3(address(staking)).startCooldown(_shares);
    }

    function cancelCooldown() external onlyManagement {
        ISUSD3(address(staking)).cancelCooldown();
    }
}
