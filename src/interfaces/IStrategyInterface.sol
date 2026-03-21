// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    function vault() external view returns (IStrategy);
    function staking() external view returns (IStrategy);
    function depositorWhitelist(address) external view returns (bool);
    function setDepositorWhitelist(address _depositor, bool _allowed) external;
    function sweep(address _token, uint256 _amount, address _recipient) external;
    function startCooldown(uint256 _shares) external;
    function cancelCooldown() external;
    function balanceOfAsset() external view returns (uint256);
    function balanceOfVault() external view returns (uint256);
    function balanceOfStake() external view returns (uint256);
    function valueOfVault() external view returns (uint256);
    function vaultsMaxWithdraw() external view returns (uint256);

    // Rewards
    function claimRewards(uint256 _totalAllocation, bytes32[] calldata _proof) external;

    // Auction
    function setAuction(address _auction) external;
    function setUseAuction(bool _useAuction) external;
    function setMinAmountToSell(uint256 _minAmountToSell) external;
    function auction() external view returns (address);
    function useAuction() external view returns (bool);
    function kickable(address _token) external view returns (uint256);
    function kickAuction(address _from) external returns (uint256);
    function auctionTrigger(address _from) external view returns (bool, bytes memory);
}
