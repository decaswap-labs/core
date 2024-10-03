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
