// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILiquidityLogicActions {
    function initGenesisPool(address token, address user, uint256 tokenAmount, uint256 initialDToMint) external;
    function initPool(address token, address liquidityToken, address user, uint256 tokenAmount, uint256 liquidityTokenAmount) external;
    function addLiqDualToken(address token, address liquidityToken, address user, uint256 tokenAmount, uint256 liquidityTokenAmount) external;
    function removeLiquidity(address token, address user, uint256 liquidityTokenAmount) external;
    function addOnlyDLiquidity(address token, address liquidityToken, address user, uint256 liquidityTokenAmount) external;
    function addOnlyTokenLiquidity(address token, address user, uint256 amount) external;
    function depositToGlobalPool(address token, address user, uint256 amount, uint256 streamCount, uint256 swapPerStream) external;
    function withdrawFromGlobalPool(address token, address user, uint256 amount) external;
}   