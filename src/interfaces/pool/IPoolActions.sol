// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolActions {
    function createPool(address, uint256, uint256, uint256, uint256) external;
    function disablePool(address) external;
    function add(address, address, uint256) external;
    function remove(address, address, uint256) external;
    function executeSwap(address user, uint256 amountIn, uint256 executionPrice, address tokenIn, address tokenOut)
        external;

    function updatePoolLogicAddress(address) external;
    function updateVaultAddress(address) external;
    function updateRouterAddress(address) external;
    function updateMinLaunchReserveA(address, uint256) external;
    function updatePairSlippage(address, address, uint256) external;
    function updateGlobalSlippage(uint256) external;
}
