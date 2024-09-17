// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolErrors {
    error NotRouter(address);
    error InvalidToken();
    error InvalidDReserve();
    error InvalidSlippage();
    error InvalidLpUnits();
}
