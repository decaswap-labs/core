// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Swap, LiquidityStream, RemoveLiquidityStream, GlobalPoolStream} from "../../lib/SwapQueue.sol";

interface IPoolActions {
    // creatPoolParams encoding format => (address token, address user, uint256 amount, uint256 minLaunchReserveA, uint256 minLaunchReserveD, uint256 initialDToMint, uint newLpUnits, uint newDUnits, uint256 poolFeeCollected)
    // function createPool(bytes calldata creatPoolParams) external;
    // initGenesisPool encoding format => (address token, address user, uint256 amount, uint256 initialDToMint, uint newLpUnits, uint newDUnits, uint256 poolFeeCollected)
    function initGenesisPool(bytes calldata initPoolParams) external;
    function initPool(address tokenAddress, uint8 decimals) external;
    // updatedLpUnits encoding format => (address token, address user, uint lpUnits)
    function updateUserLpUnits(bytes memory updatedLpUnits) external;
    // updatedReservesAndRemoveLiqData encoding format => (address token, uint256 reservesToRemove, uint conversionRemaining, uint streamCountRemaining)
    function updateReservesAndRemoveLiqStream(bytes memory updatedReservesAndRemoveLiqData) external;
    function enqueueSwap_pairStreamQueue(bytes32 pairId, Swap memory swap) external;
    function enqueueSwap_pairPendingQueue(bytes32 pairId, Swap memory swap) external;
    function enqueueLiquidityStream(bytes32 pairId, LiquidityStream memory liquidityStream) external;
    function enqueueRemoveLiquidityStream(address token, RemoveLiquidityStream memory removeLiquidityStream) external;
    function enqueueGlobalPoolDepositStream(bytes32 pairId, GlobalPoolStream memory globaPoolStream) external;
    function enqueueGlobalPoolWithdrawStream(bytes32 pairId, GlobalPoolStream memory globaPoolStream) external;

    function dequeueSwap_pairStreamQueue(bytes32 pairId, uint256 executionPriceKey, uint256 index, bool isLimitOrder)
        external;
    function dequeueSwap_pairPendingQueue(bytes32 pairId) external;
    function dequeueLiquidityStream_streamQueue(bytes32 pairId) external;
    function dequeueRemoveLiquidity_streamQueue(address token) external;
    function dequeueGlobalStream_streamQueue(bytes32 pairId) external;
    function dequeueGlobalPoolDepositStream(bytes32 pairId, uint256 index) external;
    function dequeueGlobalPoolWithdrawStream(bytes32 pairId, uint256 index) external;
    // updateReservesParams encoding format => (bool aToB, address tokenA, address tokenB, uint256 reserveA_A, uint256 reserveD_A,uint256 reserveA_B, uint256 reserveD_B)
    function updateReserves(bytes memory updateReservesParams) external;
    // updateReservesParams encoding format => (address tokenA, address tokenB, uint256 reserveA_A, uint256 reserveA_B, uint256 changeInD)
    function updateReservesWhenStreamingLiq(bytes memory updatedReservesParams) external;
    // updatedStreamData encoding format => (bytes32 pairId, uint256 amountAToDeduct, uint256 amountBToDeduct, uint256 poolAStreamsRemaining,uint256 poolBStreamsRemaining, uint dAmountOut)
    function updateStreamQueueLiqStream(bytes memory updatedStreamData) external;
    // updatedSwapData encoding format => (bytes32 pairId, uint256 amountOut, uint256 swapAmountRemaining, bool completed, uint256 streamsRemaining, uint256 streamCount, uint256 swapPerStream)
    function updateReservesGlobalStream(bytes memory updatedReservesParams) external;
    function updateGlobalPoolBalance(bytes memory updatedBalance) external;
    function updateGlobalPoolUserBalance(bytes memory userBalance) external;
    // function updateGlobalStreamQueueStream(bytes memory updatedStream) external;
    function transferTokens(address tokenAddress, address to, uint256 amount) external;
    function sortPairPendingQueue(bytes32 pairId) external;
    function globalStreamQueueDeposit(bytes32 pairId) external returns (GlobalPoolStream[] memory globalPoolStream);
    function globalStreamQueueWithdraw(bytes32 pairId) external returns (GlobalPoolStream[] memory globalPoolStream);
    function updatePairStreamQueueSwap(
        bytes memory updatedSwapData,
        uint256 executionPriceKey,
        uint256 index,
        bool isLimitOrder
    ) external;
    function updatePoolLogicAddress(address) external;
    function updateVaultAddress(address) external;
    function updateRouterAddress(address) external;
    function updatePairSlippage(address, address, uint256) external;
    function updateGlobalSlippage(uint256) external;
    function updateGlobalPoolDepositStream(GlobalPoolStream memory stream, bytes32 pairId, uint256 index) external;
    function updateGlobalPoolWithdrawStream(GlobalPoolStream memory stream, bytes32 pairId, uint256 index) external;

    function updateOrderBook(bytes32, Swap memory swap, uint256, bool) external;

    function getNextSwapId() external returns (uint256);
    function getReserveA(address pool) external view returns (uint256);
    function getReserveD(address pool) external view returns (uint256);

    function setHighestPriceMarker(bytes32 pairId, uint256 value) external;

    function getPoolAddresses() external view returns (address[] memory);
}
