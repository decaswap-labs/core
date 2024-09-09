// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IRouterEvents {
    event LiquidityAdded(address,address,uint256);
    event LiquidityRemoved(address,address,uint256);
    event PoolAddressUpdated(address, address);
}