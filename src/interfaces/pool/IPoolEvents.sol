// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolEvents {

    event PoolCreated(address, uint256);
    event LiquidityAdded(address, address, uint256, uint256, uint256);
    event LiquidityRemoved();
    event VaultAddressUpdated(address, address);
    event RouterAddressUpdated(address, address);
    event PoolLogicAddressUpdated(address, address);
}