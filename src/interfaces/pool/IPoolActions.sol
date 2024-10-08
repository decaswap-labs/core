// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import {Swap} from "../../lib/SwapQueue.sol";

interface IPoolActions {
    // creatPoolParams encoding format => (address token, address user, uint256 amount, uint256 minLaunchReserveA, uint256 minLaunchReserveD, uint256 initialDToMint, uint newLpUnits, uint newDUnits, uint256 poolFeeCollected)
    function createPool(bytes calldata creatPoolParams) external;
    function disablePool(address) external;
    // addLiqParams encoding format => (address token, address user, uint amount, uint256 newLpUnits, uint256 newDUnits, uint256 poolFeeCollected)
    function addLiquidity(bytes memory addLiqParams) external;
    // removeLiqParams encoding format => (address token, address user, uint lpUnits, uint256 assetToTransfer, uint256 dAmountToDeduct, uint256 poolFeeCollected)
    function removeLiquidity(bytes memory removeLiqParams) external;
    function enqueueSwap_poolStreamQueue(bytes32 pairId, Swap memory swap) external;
    function enqueueSwap_pairStreamQueue(bytes32 pairId, Swap memory swap) external;
    function enqueueSwap_pairPendingQueue(bytes32 pairId, Swap memory swap) external;
    function dequeueSwap_poolStreamQueue(bytes32 pairId) external;
    function dequeueSwap_pairStreamQueue(bytes32 pairId) external;
    function dequeueSwap_pairPendingQueue(bytes32 pairId) external;
    // updateReservesParams encoding format => (bool aToB, address tokenA, address tokenB, uint256 reserveA_A, uint256 reserveD_A,uint256 reserveA_B, uint256 reserveD_B)
    function updateReserves(bytes memory updateReservesParams) external;
        // updatedSwapData encoding format => (bytes32 pairId, uint256 amountOut, uint256 swapAmountRemaining, bool completed, uint256 streamsRemaining)
    function updatePairStreamQueueSwap(bytes memory updatedSwapData) external;
    function sortPairPendingQueue(bytes32 pairId) external;
    function executeSwap(address, uint256, uint256, address, address) external;
    function depositVault(address, uint256, address) external;
    function withdrawVault(address, uint256, address) external;

    function updatePoolLogicAddress(address) external;
    function updateVaultAddress(address) external;
    function updateRouterAddress(address) external;
    function updateMinLaunchReserveA(address, uint256) external;
    function updatePairSlippage(address, address, uint256) external;
    function updateGlobalSlippage(uint256) external;
}
