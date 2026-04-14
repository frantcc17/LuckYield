// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IUSDYOracle.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockUSDYOracle
 * @notice Simulates the Ondo RWADynamicRateOracle for local testing.
 *         The price starts at 1.00 USDC per USDY and increases by 0.01% daily.
 *         Owner can manually set the price to trigger draw conditions quickly.
 */
contract MockUSDYOracle is IUSDYOracle, Ownable {
    /// @dev Price expressed as USDC per 1 USDY, scaled by 1e18
    ///      e.g. 1.05 USDC/USDY → 1.05e18
    uint256 private _price;

    /// @notice Daily yield rate: 0.01% = 10 bps expressed as 1e18 scale
    uint256 public constant DAILY_RATE = 1e18 * 10 / 10_000; // 0.001 * 1e18

    uint256 public lastUpdateTimestamp;

    event PriceUpdated(uint256 oldPrice, uint256 newPrice);

    constructor() Ownable(msg.sender) {
        _price               = 1e18; // Start at $1.00 per USDY
        lastUpdateTimestamp  = block.timestamp;
    }

    /// @inheritdoc IUSDYOracle
    function getPrice() external view override returns (uint256) {
        // Simulate daily accrual since last update
        uint256 elapsed = (block.timestamp - lastUpdateTimestamp) / 1 days;
        uint256 accrued = _price;
        for (uint256 i = 0; i < elapsed && i < 365; i++) {
            accrued += (accrued * 10) / 10_000; // +0.01% per day
        }
        return accrued;
    }

    /// @notice Owner can manually set price for testing (e.g., to trigger draw)
    function setPrice(uint256 newPrice) external onlyOwner {
        emit PriceUpdated(_price, newPrice);
        _price              = newPrice;
        lastUpdateTimestamp = block.timestamp;
    }

    /// @notice Simulate n days of yield accrual
    function simulateDays(uint256 n) external onlyOwner {
        for (uint256 i = 0; i < n; i++) {
            _price += (_price * 10) / 10_000;
        }
        lastUpdateTimestamp = block.timestamp;
        emit PriceUpdated(_price, _price);
    }
}

/**
 * @title MockUSDY
 * @notice ERC20 mock representing Ondo's USDY token.
 *         Mintable by owner to simulate Ondo's mint-on-deposit flow.
 */
contract MockUSDY is ERC20, Ownable {
    constructor() ERC20("Mock USDY", "mUSDY") Ownable(msg.sender) {}

    /// @notice Mint USDY to an address (simulates Ondo router behavior)
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /// @notice Burn USDY (simulates Ondo redemption)
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}

/**
 * @title MockUSDC
 * @notice 6-decimal USDC mock for local testing.
 */
contract MockUSDC is ERC20, Ownable {
    constructor() ERC20("Mock USDC", "mUSDC") Ownable(msg.sender) {}

    function decimals() public pure override returns (uint8) { return 6; }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
