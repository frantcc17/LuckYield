// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IUSDYOracle
 * @notice Interface for Ondo Finance's RWADynamicRateOracle.
 *         Returns the current exchange rate of USDY in USDC terms.
 */
interface IUSDYOracle {
    /**
     * @notice Returns the current price of 1 USDY in USDC, scaled by 1e18.
     * @dev    For example: if 1 USDY = $1.05 USDC, returns 1.05e18.
     *         Production address (Arbitrum Mainnet): 0x996...  (verify on Ondo docs)
     */
    function getPrice() external view returns (uint256);
}
