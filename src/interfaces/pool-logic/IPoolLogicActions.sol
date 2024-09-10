// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolLogicActions{
    function calculateLpUnitsToMint(uint256 amount, uint256 reserveA, uint256 totalLpUnits) external pure returns(uint256);
    function calculateDUnitsToMint(uint256 amount, uint256 reserveA, uint256 reserveD) external view returns(uint256);
    function updateBaseDAmount(uint amount) external;
    function updatePoolAddress(address) external;
    
    function calculateAssetTransfer(uint,uint,uint) external pure returns(uint256);
    function calculateDToDeduct(uint,uint,uint) external pure returns(uint256);
}