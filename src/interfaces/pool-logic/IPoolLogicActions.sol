// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolLogicActions {
    // function createPool(
    //     address token,
    //     address user,
    //     uint256 amount,
    //     uint256 minLaunchReserveA,
    //     uint256 minLaunchReserveD,
    //     uint256 initialDToMint
    // ) external;
    function initGenesisPool(address token, address user, uint256 tokenAmount, uint256 initialDToMint) external;
    function initPool(
        address token,
        address liquidityToken,
        address user,
        uint256 tokenAmount,
        uint256 liquidityTokenAmount
    ) external;

    function addLiqDualToken(address tokenA, address tokenB, address user, uint256 amountA, uint256 amountB) external;
    function addOnlyTokenLiquidity(address token, address user, uint256 amount) external;
    function addOnlyDLiquidity(address tokenA, address tokenB, address user, uint256 amountB) external;
    function processLiqStream(address tokenA, address tokenB) external;
    function removeLiquidity(address token, address user, uint256 lpUnits) external;
    function depositToGlobalPool(
        address user,
        address token,
        uint256 amount,
        uint256 streamCount,
        uint256 swapPerStream
    ) external;
    function withdrawFromGlobalPool(address user, address token, uint256 amount) external;
    function swap(address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 executionPrice) external;
    function swapLimitOrder(address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 limitOrderPrice)
        external;
    function swapTriggerOrder(
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 triggerExecutionPrice
    ) external;
    function swapMarketOrder(address user, address tokenIn, address tokenOut, uint256 amountIn) external;
    function processLimitOrders(address tokenIn, address tokenOut) external;

    function getStreamCount(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256);
    function getStreamCountForDPool(address tokenIn, uint256 amountIn) external view returns (uint256);
    function updatePoolAddress(address) external;

    function processGlobalStreamPairDeposit(address token) external;
    function processGlobalStreamPairWithdraw(address token) external;
    function processMarketAndTriggerOrders() external;

    function processAddLiquidity(address poolA, address poolB) external;
    function processRemoveLiquidity(address token) external;

    function updateOwner(address ownerAddress) external;
}
