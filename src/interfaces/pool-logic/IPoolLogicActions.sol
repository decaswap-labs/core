// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolLogicActions {
    function calculateLpUnitsToMint(uint256 amount, uint256 reserveA, uint256 totalLpUnits)
        external
        pure
        returns (uint256);

    function calculateDUnitsToMint(uint256 amount, uint256 reserveA, uint256 reserveD, uint256)
        external
        view
        returns (uint256);
    function updateBaseDAmount(uint256 amount) external;
    function updatePoolAddress(address) external;

    function calculateAssetTransfer(uint256, uint256, uint256) external pure returns (uint256);
    function calculateDToDeduct(uint256, uint256, uint256) external pure returns (uint256);
    function calculateStreamCount(uint256, uint256, uint256) external pure returns (uint256);
    function getSwapAmountOut(
        uint256 amountIn,
        uint256 reserveA,
        uint256 reserveB,
        uint256 reserveD1,
        uint256 reserveD2
    ) external pure returns (uint256, uint256);

    function getExecutionPrice(uint256 reserveA1, uint256 reserveA2) external pure returns (uint256);
}
