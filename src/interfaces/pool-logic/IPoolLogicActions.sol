// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolLogicActions{
    function mintLpUnits(uint256 amount, uint256 reserveA, uint256 totalLpUnits) external returns(uint256);
    function mintDUnits(uint256 amount, uint256 reserveA, uint256 reserveD) external returns(uint256);
    function updateBaseDAmount(uint amount) external;
    function updatePoolAddress(address) external;
}