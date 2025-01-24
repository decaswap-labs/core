// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ILiquidityLogicEvents {
    event PoolAddressUpdated(address, address);
    event PoolLogicAddressUpdated(address, address);
    event OwnerUpdated(address, address);

    // Event 1: Add Liquidity Entered
    event AddLiquidityEntered(
        uint256 indexed id,
        address token,
        address user,
        uint256 amount,
        uint256 streamCount
    );

    // Event 2: Remove Liquidity Entered
    event RemoveLiquidityEntered(
        uint256 indexed id,
        address token,
        address user,
        uint256 amount,
        uint256 streamCount
    );

    // Event 3: Add Liquidity Stream Executed
    event AddLiquidityStreamExecuted(
        uint256 indexed id
    );

    // Event 4: Remove Liquidity Stream Executed
    event RemoveLiquidityStreamExecuted(
        uint256 indexed id
    );

    // Event 5: Genesis Pool Initialized
    event GenesisPoolInitialized(
        address indexed token,
        address indexed user,
        uint256 tokenAmount,
        uint256 initialDToMint
    );

    // Event 6: Pool Initialized
    event PoolInitialized(
        bytes32 indexed pairId,
        address indexed user,
        uint256 tokenAmount,
        uint256 dTokenAmount
    );
}
