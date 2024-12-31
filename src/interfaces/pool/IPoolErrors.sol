// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolErrors {
    error NotRouter(address);
    // error NotPoolLogic(address);
    error InvalidToken();
    error InvalidTokenAmount();
    error MinLaunchReservesNotReached();
    error InvalidExecutionPrice();
    error InvalidPool();
    error InvalidSwap();
    error DuplicatePool();
    error NotValidCaller(address);
}
