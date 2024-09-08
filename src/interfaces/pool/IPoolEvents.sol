// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolEvents {

    event PoolCreated(address, uint256);
    event LiquidityAdded();
    event LiquidityRemoved();

}