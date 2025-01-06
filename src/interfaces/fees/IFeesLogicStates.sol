// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IFeesLogicStates {
    function POOL_ADDRESS() external view returns (address);
    function POOL_LOGIC_ADDRESS() external view returns (address);
    function BOT_FEE_BPS() external view returns (uint256);
    function LP_FEE_BPS() external view returns (uint256);
    function GLOBAL_FEE_PERCENTAGE() external view returns (uint256);
    function POOL_LP_FEE_PERCENTAGE() external view returns (uint256);
    function DECA_FEE_PERCENTAGE() external view returns (uint256);
    function DECA_ADDRESS() external view returns (address);
    function REWARD_TOKEN_ADDRESS() external view returns (address);
}