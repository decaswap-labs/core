// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IRouterActions{
    function addLiquidity(address, uint256) external ;
    function removeLiquidity(address, uint256) external ;
    function updatePoolAddress(address) external;
}