// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IRouterErrors {
    error InvalidAmount();
    error InvalidPool();
    error InvalidExecutionPrice();
    error InvalidInitialDAmount();
    error InvalidToken();
    error DuplicatePool();
    error InvalidLiquidityTokenAmount();
    error SamePool();
}
