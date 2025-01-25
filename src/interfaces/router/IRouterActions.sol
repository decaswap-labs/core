// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IRouterActions {
    function removeLiquidity(address, uint256) external;
    function updatePoolAddress(address) external;
    function depositToGlobalPool(address, uint256) external;
    function withdrawFromGlobalPool(address pool, uint256 dAmount) external;
    function processGlobalStreamPairDeposit(address token) external;
    function processGlobalStreamPairWithdraw(address token) external;
    function processMarketOrders() external;
    function swapMarketOrder(address tokenIn, address tokenOut, uint256 amountIn) external;
    function swapTriggerOrder(address tokenIn, address tokenOut, uint256 amountIn, uint256 executionPrice) external;
    function swapLimitOrder(address tokenIn, address tokenOut, uint256 amountIn, uint256 executionPrice) external;
    function processLimitOrders(address tokenIn, address tokenOut) external;
}
