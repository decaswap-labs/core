// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ILiquidityLogicEvents {
    event PoolAddressUpdated(address, address);
    event PoolLogicAddressUpdated(address, address);
    event OwnerUpdated(address, address);
}
