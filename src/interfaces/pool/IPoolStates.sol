// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolStates {
    function poolInfo(address) external view returns(uint256,uint256,uint256,uint256,uint256,uint256,address);
    function userInfo(address,address) external view returns(address,uint256);
}