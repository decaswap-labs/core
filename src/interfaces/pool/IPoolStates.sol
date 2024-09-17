// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Swap} from "../../lib/SwapQueue.sol";

interface IPoolStates {

    function poolInfo(address)
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256, address);
    function userLpUnitInfo(address, address) external view returns (uint256);
    function VAULT_ADDRESS() external view returns (address);
    function ROUTER_ADDRESS() external view returns (address);
    function POOL_LOGIC() external view returns (address);
    function pairSlippage(bytes32) external view returns (uint256);
    function globalSlippage() external view returns (uint256);
    // function pairSwapHistory(bytes32) external view returns(uint256,uint256);
    // function pairPendingQueue(bytes32) external view returns(Swap[] memory,uint,uint);
    // function pairStreamQueue(bytes32) external view returns(Swap[] memory,uint,uint);
}
