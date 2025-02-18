// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILiquidityLogicActions {
    function initGenesisPool(
        address token,
        uint8 decimals,
        address user,
        uint256 tokenAmount,
        uint256 initialDToMint
    )
        external;
    function initPool(
        address token,
        uint8 decimals,
        address liquidityToken,
        address user,
        uint256 tokenAmount,
        uint256 liquidityTokenAmount
    )
        external;
    function addLiqDualToken(
        address token,
        address liquidityToken,
        address user,
        uint256 tokenAmount,
        uint256 liquidityTokenAmount
    )
        external;
    function removeLiquidity(address token, address user, uint256 liquidityTokenAmount) external;
    function addOnlyDLiquidity(
        address token,
        address liquidityToken,
        address user,
        uint256 liquidityTokenAmount
    )
        external;
    function addOnlyTokenLiquidity(address token, address user, uint256 amount) external;
    function depositToGlobalPool(
        address token,
        address user,
        uint256 amount,
        uint256 streamCount,
        uint256 swapPerStream
    )
        external;
    function withdrawFromGlobalPool(address token, address user, uint256 amount) external;
    function processDepositToGlobalPool(address token) external;
    function processWithdrawFromGlobalPool(address token) external;
    function processAddLiquidity(address poolA, address poolB) external;
    function processRemoveLiquidity(address token) external;
    function updatePoolAddress(address poolAddress) external;
    function updatePoolLogicAddress(address poolLogicAddress) external;
}
