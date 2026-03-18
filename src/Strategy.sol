// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Base4626Compounder, ERC20, IStrategy} from "@periphery/Bases/4626Compounder/Base4626Compounder.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ISUSD3 {
    function startCooldown(uint256 shares) external;
    function cancelCooldown() external;
    function availableDepositLimit(address owner) external view returns (uint256);
}

contract Strategy is Base4626Compounder {
    using SafeERC20 for ERC20;

    IStrategy public immutable staking;

    mapping(address => bool) public depositorWhitelist;

    event DepositorWhitelistUpdated(address indexed depositor, bool allowed);

    constructor(
        address _asset,
        string memory _name,
        address _vault,
        address _staking
    ) Base4626Compounder(_asset, _name, _vault) {
        require(IStrategy(_staking).asset() == _vault, "wrong staking");
        staking = IStrategy(_staking);

        ERC20(_vault).forceApprove(_staking, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                        CORE OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function _stake() internal override {
        uint256 balance = vault.balanceOf(address(this));
        if (balance > 0) {
            staking.deposit(balance, address(this));
        }
    }

    function _unStake(uint256 _amount) internal override {
        staking.withdraw(_amount, address(this), address(this));
    }

    function balanceOfStake() public view override returns (uint256) {
        return staking.convertToAssets(staking.balanceOf(address(this)));
    }

    function vaultsMaxWithdraw() public view override returns (uint256) {
        uint256 looseVaultShares = vault.maxRedeem(address(this));
        uint256 stakingRedeemable = staking.maxRedeem(address(this));
        uint256 redeemableVaultShares = staking.convertToAssets(stakingRedeemable);
        return vault.convertToAssets(looseVaultShares + redeemableVaultShares);
    }

    function _claimAndSellRewards() internal override {}

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _claimAndSellRewards();

        if (!TokenizedStrategy.isShutdown()) {
            uint256 looseAsset = balanceOfAsset();
            if (looseAsset > 0) {
                vault.deposit(looseAsset, address(this));
            }
            _stake();
        }

        _totalAssets = balanceOfAsset() + valueOfVault();
    }

    function _tend(uint256 /*_totalIdle*/) internal override {
        _stake();
    }

    function _tendTrigger() internal view override returns (bool) {
        return vault.balanceOf(address(this)) > 0;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT / WITHDRAW LIMITS
    //////////////////////////////////////////////////////////////*/

    function availableDepositLimit(
        address _owner
    ) public view override returns (uint256) {
        if (!depositorWhitelist[_owner]) {
            return 0;
        }

        uint256 vaultLimit = super.availableDepositLimit(_owner);

        uint256 stakingCapUSD3 = ISUSD3(address(staking)).availableDepositLimit(address(this));
        uint256 stakingCapUSDC = vault.convertToAssets(stakingCapUSD3);

        return vaultLimit < stakingCapUSDC ? vaultLimit : stakingCapUSDC;
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setDepositorWhitelist(
        address _depositor,
        bool _allowed
    ) external onlyManagement {
        depositorWhitelist[_depositor] = _allowed;
        emit DepositorWhitelistUpdated(_depositor, _allowed);
    }

    function startCooldown(uint256 _shares) external onlyManagement {
        ISUSD3(address(staking)).startCooldown(_shares);
    }

    function cancelCooldown() external onlyManagement {
        ISUSD3(address(staking)).cancelCooldown();
    }
}
