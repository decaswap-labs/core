// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolLogicEvents {
    event LPUnitsMinted(uint256);
    event DUnitsMinted(uint256);
    event BaseDUpdated(uint256, uint256);
    event PoolAddressUpdated(address, address);
}