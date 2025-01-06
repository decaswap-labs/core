// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFeesLogicEvents {
    event FeesWithdrawn(address indexed pool, address indexed user, uint256 amount);
    event LpDeclarationCreated(address indexed provider);
    event LpDeclarationUpdated(address indexed provider);
    event PoolAddressUpdated(address, address);
    event LPDeclarationUpdated(address indexed provider, address indexed pool, uint32 pUnits, uint32 epoch, bool isAdd);
}
