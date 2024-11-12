// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Swap} from "./SwapQueue.sol";

library SwapSorter {
    // Function to sort an array of Swaps based on swapAmount using iterative QuickSort
    function quickSort(Swap[] storage arr) public view returns (Swap[] storage) {
        if (arr.length <= 1) {
            return arr; // Already sorted
        }

        // Stack to store start and end indices of subarrays
        uint256[] memory stack = new uint256[](arr.length * 2);
        uint256 top = 0;

        // Initial values for the stack
        stack[top++] = 0;
        stack[top++] = arr.length - 1;

        // Continue until the stack is empty
        while (top > 0) {
            uint256 end = stack[--top];
            uint256 start = stack[--top];

            if (start >= end) {
                continue;
            }

            // Partition the array
            uint256 pivotIndex = partition(arr, start, end);

            // Push the indices of the subarrays to the stack
            if (pivotIndex > 0 && pivotIndex - 1 > start) {
                stack[top++] = start;
                stack[top++] = pivotIndex - 1;
            }

            if (pivotIndex + 1 < end) {
                stack[top++] = pivotIndex + 1;
                stack[top++] = end;
            }
        }

        return arr;
    }

    // Partition function to divide the array into two halves based on swapAmount
    function partition(Swap[] memory arr, uint256 low, uint256 high) internal pure returns (uint256) {
        uint256 pivot = arr[high].swapAmount; // Select the pivot based on swapAmount
        uint256 i = low;

        for (uint256 j = low; j < high; j++) {
            if (arr[j].swapAmount < pivot) {
                // Swap arr[i] and arr[j]
                Swap memory temp = arr[i];
                arr[i] = arr[j];
                arr[j] = temp;
                i++;
            }
        }

        // Swap arr[i] and arr[high] (the pivot element)
        Swap memory temp2 = arr[i];
        arr[i] = arr[high];
        arr[high] = temp2;

        return i; // Return the pivot index
    }
}
