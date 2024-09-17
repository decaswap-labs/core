// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolEvents {
    event PoolCreated(address, uint256, uint256);
    event LiquidityAdded(address, address, uint256, uint256, uint256);
    event LiquidityRemoved(address, address, uint256, uint256, uint256);
    event VaultAddressUpdated(address, address);
    event RouterAddressUpdated(address, address);
    event PoolLogicAddressUpdated(address, address);
    event MinLaunchReserveUpdated(address, uint256, uint256);
    event PairSlippageUpdated(address, address, uint256);
    event GlobalSlippageUpdated(uint256, uint256);
    event SwapAdded(bytes32, uint256, uint256, uint256, uint256, address, address, address);
    event StreamAdded(uint256, uint256, uint256, uint256, uint256, bytes32);
    event PendingStreamAdded(uint256, uint256, uint256, uint256, uint256, bytes32);
    event SwapCancelled(uint256, bytes32, uint256, uint256);
}
