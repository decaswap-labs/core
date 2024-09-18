// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolLogicActions {
    function calculateLpUnitsToMint(uint256, uint256, uint256) external pure returns (uint256);

    function calculateDUnitsToMint(uint256, uint256, uint256, uint256) external view returns (uint256);
    function updateBaseDAmount(uint256) external;
    function updatePoolAddress(address) external;

    function calculateAssetTransfer(uint256, uint256, uint256) external pure returns (uint256);
    function calculateDToDeduct(uint256, uint256, uint256) external pure returns (uint256);
    function calculateStreamCount(uint256, uint256, uint256) external pure returns (uint256);
    function getSwapAmountOut(uint256, uint256, uint256, uint256, uint256) external pure returns (uint256, uint256);

    function getExecutionPrice(uint256, uint256) external pure returns (uint256);
    function getTokenOut(uint256, uint256, uint256) external pure returns (uint256);
    function getDOut(uint256, uint256, uint256) external pure returns (uint256);
}
