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

    /// @notice The sUSD3 staking vault.
    IStrategy public immutable staking;

    /// @notice Maximum total assets the strategy will accept.
    uint256 public depositLimit = type(uint256).max;

    /// @notice Whether a given address is allowed to deposit.
    mapping(address => bool) public depositorWhitelist;

    /// @notice Emitted when a depositor's whitelist status changes.
    /// @param depositor The address whose status changed.
    /// @param allowed The new whitelist status.
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
        uint256 stakingCapUSDC = vault.previewMint(stakingCapUSD3);

        uint256 currentAssets = TokenizedStrategy.totalAssets();
        uint256 limitCap = depositLimit > currentAssets ? depositLimit - currentAssets : 0;

        uint256 limit = vaultLimit < stakingCapUSDC ? vaultLimit : stakingCapUSDC;
        return limit < limitCap ? limit : limitCap;
    }

    /*//////////////////////////////////////////////////////////////
                        REWARDS
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim JANE rewards from the merkle distributor.
    /// @param _totalAllocation Total allocation for this strategy in the merkle tree.
    /// @param _proof Merkle proof for the claim.
    function claimRewards(uint256 _totalAllocation, bytes32[] calldata _proof) external {
        IRewardsDistributor(REWARDS_DISTRIBUTOR).claim(address(this), _totalAllocation, _proof);
    }

    /*//////////////////////////////////////////////////////////////
                        MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Set the maximum total assets the strategy will accept.
    /// @param _depositLimit The new deposit limit.
    function setDepositLimit(uint256 _depositLimit) external onlyManagement {
        depositLimit = _depositLimit;
    }

    /// @notice Set whether a depositor is allowed to deposit.
    /// @param _depositor Address to update.
    /// @param _allowed Whether the address is whitelisted.
    function setDepositorWhitelist(address _depositor, bool _allowed) external onlyManagement {
        depositorWhitelist[_depositor] = _allowed;
        emit DepositorWhitelistUpdated(_depositor, _allowed);
    }

    /// @notice Set the auction contract to use for selling rewards.
    /// @param _auction The auction contract address.
    function setAuction(address _auction) external onlyManagement {
        _setAuction(_auction);
    }

    /// @notice Enable or disable auction usage for reward selling.
    /// @param _useAuction Whether to use auctions.
    function setUseAuction(bool _useAuction) external onlyManagement {
        _setUseAuction(_useAuction);
    }

    /// @notice Set the minimum JANE amount required to kick an auction.
    /// @param _minAmountToSell Minimum token amount.
    function setMinAmountToSell(uint256 _minAmountToSell) external onlyManagement {
        _setMinAmountToSell(_minAmountToSell);
    }

    /// @notice Start the sUSD3 cooldown period for withdrawals.
    /// @param _shares Number of sUSD3 shares to cooldown.
    function startCooldown(uint256 _shares) external onlyManagement {
        ISUSD3(address(staking)).startCooldown(_shares);
    }

    /// @notice Cancel any active sUSD3 cooldown.
    function cancelCooldown() external onlyManagement {
        ISUSD3(address(staking)).cancelCooldown();
    }

    /// @notice Sweep any token that is not asset, vault, or staking to a recipient.
    /// @param _token The token to sweep.
    /// @param _amount The amount to sweep.
    /// @param _recipient The address to send the tokens to.
    function sweep(address _token, uint256 _amount, address _recipient) external onlyManagement {
        require(_token != address(asset), "!asset");
        require(_token != address(vault), "!vault");
        require(_token != address(staking), "!staking");
        ERC20(_token).safeTransfer(_recipient, _amount);
    }
}
