// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Swap, LiquidityStream, RemoveLiquidityStream} from "../../lib/SwapQueue.sol";

interface IPoolStates {
    function poolInfo(address)
        external
        view
        returns (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        );
    function userLpUnitInfo(address, address) external view returns (uint256);
    function userGlobalPoolInfo(address, address) external view returns (uint256);
    function VAULT_ADDRESS() external view returns (address);
    function ROUTER_ADDRESS() external view returns (address);
    function POOL_LOGIC() external view returns (address);
    function GLOBAL_POOL() external view returns (address);
    function pairSlippage(bytes32) external view returns (uint256);
    function globalSlippage() external view returns (uint256);
    // function pairSwapHistory(bytes32) external view returns(uint256,uint256);
    function pairStreamQueue(bytes32) external view returns (Swap[] memory swaps, uint256 front, uint256 back);
    function pairPendingQueue(bytes32) external view returns (Swap[] memory swaps, uint256 front, uint256 back);
    function liquidityStreamQueue(bytes32) external view returns (LiquidityStream[] memory liquidityStream);
    function removeLiquidityStreamQueue(address)
        external
        view
        returns (RemoveLiquidityStream[] memory removeLiquidityStream);

    function globalPoolDBalance(address) external view returns (uint256);
    function highestPriceMarker(bytes32) external view returns (uint256);
    function orderBook(bytes32 pairId, uint256 priceKey, bool isLimitOrder) external view returns (Swap[] memory);
}
