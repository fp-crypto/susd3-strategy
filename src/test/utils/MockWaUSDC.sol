// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract MockWaUSDC is ERC20 {
    using Math for uint256;

    address private _asset;
    uint256 public sharePrice = 1e6;
    bool private _paused;

    constructor(address _usdc) ERC20("Wrapped Aave USDC", "waUSDC") {
        _asset = _usdc;
    }

    modifier whenNotPaused() {
        require(!_paused, "EnforcedPause");
        _;
    }

    function paused() public view returns (bool) { return _paused; }
    function setPaused(bool paused_) external { _paused = paused_; }
    function asset() public view returns (address) { return _asset; }
    function decimals() public pure override returns (uint8) { return 6; }

    function deposit(uint256 assets, address receiver) public whenNotPaused returns (uint256 shares) {
        shares = previewDeposit(assets);
        IERC20(_asset).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) public whenNotPaused returns (uint256 shares) {
        shares = previewWithdraw(assets);
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != type(uint256).max) _approve(owner, msg.sender, allowed - shares);
        }
        _burn(owner, shares);
        IERC20(_asset).transfer(receiver, assets);
    }

    function redeem(uint256 shares, address receiver, address owner) public whenNotPaused returns (uint256 assets) {
        assets = previewRedeem(shares);
        if (msg.sender != owner) {
            uint256 allowed = allowance(owner, msg.sender);
            if (allowed != type(uint256).max) _approve(owner, msg.sender, allowed - shares);
        }
        _burn(owner, shares);
        IERC20(_asset).transfer(receiver, assets);
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        if (totalSupply() == 0 && sharePrice == 1e6) return assets;
        return assets.mulDiv(1e6, sharePrice, Math.Rounding.Down);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        return shares.mulDiv(sharePrice, 1e6, Math.Rounding.Down);
    }

    function previewDeposit(uint256 assets) public view returns (uint256) { return convertToShares(assets); }
    function previewWithdraw(uint256 assets) public view returns (uint256) { return assets.mulDiv(1e6, sharePrice, Math.Rounding.Up); }
    function previewRedeem(uint256 shares) public view returns (uint256) { return convertToAssets(shares); }
    function previewMint(uint256 shares) public view returns (uint256) { return shares.mulDiv(sharePrice, 1e6, Math.Rounding.Up); }
    function totalAssets() public view returns (uint256) { return IERC20(_asset).balanceOf(address(this)); }

    function maxDeposit(address) public view returns (uint256) { return _paused ? 0 : type(uint256).max; }
    function maxMint(address) public view returns (uint256) { return _paused ? 0 : type(uint256).max; }
    function maxWithdraw(address owner) public view returns (uint256) { return _paused ? 0 : convertToAssets(balanceOf(owner)); }
    function maxRedeem(address owner) public view returns (uint256) { return _paused ? 0 : balanceOf(owner); }

    function mint(uint256 shares, address receiver) public whenNotPaused returns (uint256 assets) {
        assets = previewMint(shares);
        IERC20(_asset).transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
    }

    function simulateYield(uint256 percentIncrease) external {
        sharePrice = sharePrice.mulDiv(10000 + percentIncrease, 10000, Math.Rounding.Down);
    }

    function setSharePrice(uint256 newPrice) external {
        require(newPrice > 0, "Invalid price");
        sharePrice = newPrice;
    }
}
