// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolLogicErrors {
    error NotAPool();
    // @todo gather common errors in one file
    error NotRouter(address);
    error InvalidTokenAmount();
    error InvalidPool();
    error MinLaunchReservesNotReached();
}
