// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface IStrategyInterface is IStrategy {
    function vault() external view returns (IStrategy);
    function staking() external view returns (IStrategy);
    function depositorWhitelist(address) external view returns (bool);
    function setDepositorWhitelist(address _depositor, bool _allowed) external;
    function startCooldown(uint256 _shares) external;
    function cancelCooldown() external;
    function balanceOfAsset() external view returns (uint256);
    function balanceOfVault() external view returns (uint256);
    function balanceOfStake() external view returns (uint256);
    function valueOfVault() external view returns (uint256);
    function vaultsMaxWithdraw() external view returns (uint256);
}
