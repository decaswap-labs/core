// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFeesLogicErrors {
    error NotAPool();
    error DeclarationNotFound(address pool, address liquidityProvider);
    error InternalError();
}