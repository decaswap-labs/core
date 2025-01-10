// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IPoolLogicEvents {
    event BaseDUpdated(uint256, uint256);
    event PoolAddressUpdated(address, address);
    event LiquidityLogicAddressUpdated(address, address);
    event OwnerUpdated(address, address);

    // Event 1: SwapEntered called every time when a swap is started
    event SwapEntered(
        uint256 indexed swapID,     // Unique identifier for the swap
        bytes32 indexed pairId,     // Token pair identifier (e.g., token AB)
        uint256 indexed swapAmount, // Total amount involved in the swap (tokenIn)
        uint256 executionPrice,     // Current execution price (D/token during swap)
        address user,               // Address of the user initiating the swap
        uint8 typeOfOrder           // 1 = TRIGGER, 2 = MARKET, 3 = LIMIT
    );

    // Event 2: SwapAgainstOrderBook called every time when a swap is settled against opposite swap
    event SwapAgainstOrderBook(
        uint256 indexed swapIdIncoming,         // Identifier linking the stream to its parent swap
        uint256 indexed swapIdOpposite,         // Identifier of the opposite swap
        uint256 settledAmountIn,                // (tokenIn) Amount involved in the stream
        uint256 settledAmountOut                // (tokenOut) Amount involved in the stream
    );

    // Event 3: SwapUpdated Called every time stream count is recalculated
    event SwapUpdated(
        uint256 indexed swapId,                     // Swap ID
        uint256 indexed streamCountRemaining,       // 0 as false if there is no opposite swap
        uint256 indexed swapPerStream               // Amount per stream
    );

    // Event 4: SwapAgainstPool called every time when a swap is settled against pool
    event SwapAgainstPool(
        uint256 indexed swapId,     // Identifier linking the stream to its parent swap
        uint256 amountIn,           // Input amount
        uint256 amountOut           // Output amount
    );
}
