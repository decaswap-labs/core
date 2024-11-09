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
    address user;
    address tokenIn;
    address tokenOut;
    bool completed;
}
/* $10, we will iterate over all the swaps <=$10, n=50, 50 streams */ 

struct LiquidityStream {
    address user;
    StreamDetails poolAStream;
    StreamDetails poolBStream;
    uint256 dAmountOut; // how much D has been taken out from poolB
    TYPE_OF_LP typeofLp;
}

struct StreamDetails {
    address token;
    uint256 amount;
    uint256 streamCount;
    uint256 streamsRemaining;
    uint256 swapPerStream;
    uint256 swapAmountRemaining;
}

enum TYPE_OF_LP {
    SINGLE_TOKEN,
    DUAL_TOKEN
}

struct PoolSwapData {
    uint256 poolSwapIdLatest;
    uint256 totalSwapsPool;
}

struct GlobalPoolStream{
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

library Queue {
    struct QueueStruct {
        Swap[] data;
        uint256 front;
        uint256 back;
    }
}
