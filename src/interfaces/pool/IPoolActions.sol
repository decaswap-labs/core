// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolActions{

    function createPool(address token, uint minLaunchBalance, uint256 poolSlippage, uint256 tokenAmount) external;
    function disablePool(address newPool) external;
    function add(address user, address token, uint) external;
    function remove(address user, address token, uint lpUints) external;

    function updatePoolLogicAddress(address) external;
    function updateVaultAddress(address) external;
    function updateRouterAddress(address) external;
    function updateMinLaunchReserveA(address, uint256) external;
    function updateMinSlippage(address, uint256) external;

}