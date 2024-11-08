// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Swap, LiquidityStream} from "../../lib/SwapQueue.sol";

interface IPoolActions {
    // creatPoolParams encoding format => (address token, address user, uint256 amount, uint256 minLaunchReserveA, uint256 minLaunchReserveD, uint256 initialDToMint, uint newLpUnits, uint newDUnits, uint256 poolFeeCollected)
    // function createPool(bytes calldata creatPoolParams) external;
    // initGenesisPool encoding format => (address token, address user, uint256 amount, uint256 initialDToMint, uint newLpUnits, uint newDUnits, uint256 poolFeeCollected)
    function initGenesisPool(bytes calldata initPoolParams) external;
    function initPool(address tokenAddress) external;
    // updatedLpUnits encoding format => (address token, address user, uint lpUnits)
    function updateUserLpUnits(bytes memory updatedLpUnits) external;
    // addLiqParams encoding format => (address token, address user, uint amount, uint256 newLpUnits, uint256 newDUnits, uint256 poolFeeCollected)
    function addLiquidity(bytes memory addLiqParams) external;
    // removeLiqParams encoding format => (address token, address user, uint lpUnits, uint256 assetToTransfer, uint256 dAmountToDeduct, uint256 poolFeeCollected)
    function removeLiquidity(bytes memory removeLiqParams) external;
    function enqueueSwap_pairStreamQueue(bytes32 pairId, Swap memory swap) external;
    function enqueueSwap_pairPendingQueue(bytes32 pairId, Swap memory swap) external;
    function enqueueLiquidityStream(bytes32 pairId, LiquidityStream memory liquidityStream) external;
    function dequeueSwap_pairStreamQueue(bytes32 pairId) external;
    function dequeueSwap_pairPendingQueue(bytes32 pairId) external;
    function dequeueLiquidityStream_streamQueue(bytes32 pairId) external;
    // updateReservesParams encoding format => (bool aToB, address tokenA, address tokenB, uint256 reserveA_A, uint256 reserveD_A,uint256 reserveA_B, uint256 reserveD_B)
    function updateReserves(bytes memory updateReservesParams) external;
    // updateReservesParams encoding format => (address tokenA, address tokenB, uint256 reserveA_A, uint256 reserveA_B, uint256 changeInD)
    function updateReservesWhenStreamingLiq(bytes memory updatedReservesParams) external;
    // updatedStreamData encoding format => (bytes32 pairId, uint256 amountAToDeduct, uint256 amountBToDeduct, uint256 poolAStreamsRemaining,uint256 poolBStreamsRemaining, uint dAmountOut)
    function updateStreamQueueLiqStream(bytes memory updatedStreamData) external;
    // updatedSwapData encoding format => (bytes32 pairId, uint256 amountOut, uint256 swapAmountRemaining, bool completed, uint256 streamsRemaining, uint256 streamCount, uint256 swapPerStream)
    function updatePairStreamQueueSwap(bytes memory updatedSwapData) external;
    function transferTokens(address tokenAddress, address to, uint256 amount) external;
    function sortPairPendingQueue(bytes32 pairId) external;

    function updatePoolLogicAddress(address) external;
    function updateVaultAddress(address) external;
    function updateRouterAddress(address) external;
    function updatePairSlippage(address, address, uint256) external;
    function updateGlobalSlippage(uint256) external;
}
