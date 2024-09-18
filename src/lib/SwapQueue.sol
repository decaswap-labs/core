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

struct PoolSwapData {
    uint256 poolSwapIdLatest;
    uint256 totalSwapsPool;
}

library Queue {
    struct QueueStruct {
        Swap[] data;
        uint256 front;
        uint256 back;
    }

    // Initialize the queue
    function init(QueueStruct storage queue) internal {
        queue.front = 0;
        queue.back = 0;
    }

    // Enqueue an element at the back
    function enqueue(QueueStruct storage queue, Swap memory value) internal {
        queue.data.push(value);
        queue.back++;
    }

    // Dequeue an element from the front
    function dequeue(QueueStruct storage queue) internal returns (Swap memory) {
        require(queue.back > queue.front, "Queue is empty");
        Swap memory value = queue.data[queue.front];
        queue.front++;
        return value;
    }

    // Peek at the element at the front of the queue
    function peek(QueueStruct storage queue) internal view returns (Swap memory) {
        require(queue.back > queue.front, "Queue is empty");
        return queue.data[queue.front];
    }

    // Check if the queue is empty
    function isEmpty(QueueStruct storage queue) internal view returns (bool) {
        return queue.back == queue.front;
    }

    // Get the length of the queue
    function length(QueueStruct storage queue) internal view returns (uint256) {
        return queue.back - queue.front;
    }

    // Iterate over the queue and return an array of the elements
    // function getQueue(QueueStruct storage queue) internal view returns (Swap[] memory) {
    //     uint256 length = queue.length();
    //     uint256[] memory result = new uint256[](length);
    //     for (uint256 i = 0; i < length; i++) {
    //         result[i] = queue.data[queue.front + i];
    //     }
    //     return result;
    // }
}
