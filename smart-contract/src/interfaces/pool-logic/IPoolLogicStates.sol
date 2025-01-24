// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolLogicStates {
    function POOL_ADDRESS() external view returns (address);
    function owner() external view returns (address);
    function STREAM_COUNT_PRECISION() external view returns (uint256);
}
