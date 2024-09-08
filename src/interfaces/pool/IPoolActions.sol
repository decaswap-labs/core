// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolActions{
    function createPool(address token, uint minLaunchBalance, uint dBalance, uint) external;
    function disablePool(address newPool) external;
    // function swap(address tokenIn, address tokenOut, uint amountIn) external;
    function add(address token, uint amount) external;
    function remove(address token, uint lpUints) external;

}