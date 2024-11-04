// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolLogicActions {
    function createPool(
        address token,
        address user,
        uint256 amount,
        uint256 minLaunchReserveA,
        uint256 minLaunchReserveD,
        uint256 initialDToMint
    ) external;
    function addLiquidity(address token, address user, uint256 amount) external;
    function removeLiquidity(address token, address user, uint256 lpUnits) external;
    function swap(address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 executionPrice) external;
    function processPair(address tokenIn, address tokenOut) external;
    function calculateLpUnitsToMint(uint256, uint256, uint256) external pure returns (uint256);

    function getStreamCount(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256);
    function calculateDUnitsToMint(uint256, uint256, uint256, uint256) external view returns (uint256);
    function updatePoolAddress(address) external;

    function calculateAssetTransfer(uint256, uint256, uint256) external pure returns (uint256);
    function calculateDToDeduct(uint256, uint256, uint256) external pure returns (uint256);
    function calculateStreamCount(uint256, uint256, uint256) external pure returns (uint256);
    function getSwapAmountOut(uint256, uint256, uint256, uint256, uint256) external pure returns (uint256, uint256);

    function getExecutionPrice(uint256, uint256) external pure returns (uint256);
    function getTokenOut(uint256, uint256, uint256) external pure returns (uint256);
    function getDOut(uint256, uint256, uint256) external pure returns (uint256);
}
