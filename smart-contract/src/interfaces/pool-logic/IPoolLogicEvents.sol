// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolLogicEvents {
    event BaseDUpdated(uint256, uint256);
    event PoolAddressUpdated(address, address);
    event LiquidityLogicAddressUpdated(address, address);
    event OwnerUpdated(address, address);
}
