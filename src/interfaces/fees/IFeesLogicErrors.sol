// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFeesLogicErrors {
    error NotAPool();
    error DeclarationNotFound(address pool, address liquidityProvider);
    error InternalError();
    error NoDeclarationExists();
    error InvalidEpoch();
    error EpochNotClosed();
    error NoFeesToClaim();
}