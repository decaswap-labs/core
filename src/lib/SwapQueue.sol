// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

struct Swap {
    uint256 swapID;
    uint256 swapAmount;
    uint256 swapAmountRemaining;
    uint256 streamsCount;
    uint256 streamsRemaining;
    uint256 swapPerStream;
    uint256 executionPrice; // using executionPrice current ratio of D/token during deposit/withdraw
    uint256 amountOut;
    uint256 dustTokenAmount;
    address user;
    address tokenIn;
    address tokenOut;
    uint8 typeOfOrder; // 1 = TRIGGER , 2 = MARKET , 3 = LIMIT
    bool completed;
}
/* $10, we will iterate over all the swaps <=$10, n=50, 50 streams */

struct AddLiquidityEntry {
    uint256 id;
    address user;
    address token;
    uint256 amount;
    uint256 streamCount;
    uint256 streamsRemaining;
    uint256 swapPerStream;
    uint256 swapAmountRemaining;
    uint256 dustTokenAmount;
    // StreamDetails poolAStream;
    // StreamDetails poolBStream;
}

// struct StreamDetails {
//     address token;
//     uint256 amount;
//     uint256 streamCount;
//     uint256 streamsRemaining;
//     uint256 swapPerStream;
//     uint256 swapAmountRemaining;
//     uint256 dustTokenAmount;
// }

struct RemoveLiquidityEntry {
    uint256 id;
    address user;
    uint256 lpAmount;
    uint256 streamCount;
    uint256 streamCountRemaining;
    uint256 swapPerStream;
    uint256 tokenAmountOut;
    uint256 swapAmountRemaining;
    uint256 dustLpUnits;
}

struct PoolSwapData {
    uint256 poolSwapIdLatest;
    uint256 totalSwapsPool;
}

struct GlobalPoolStream {
    uint256 globalPoolStreamId;
    address user;
    address tokenIn;
    uint256 tokenAmount;
    uint256 streamCount;
    uint256 streamsRemaining;
    uint256 swapPerStream;
    uint256 swapAmountRemaining;
    uint256 amountOut;
    bool deposit;
}
