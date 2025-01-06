// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IFeesLogicActions {
    function proxyInitPool(address pool) external;
    function proxyExecuteSwapStream(address pool, uint32 amount) external;
    function proxyExecuteLiquidityStream(address pool, uint256 amount, uint32 pUnits, address liquidityProvider, bool isAdd) external returns(uint256);

    function updatePoolAddress(address poolAddress) external;
    function updatePoolLogicAddress(address _poolLogicAddress) external;
    function claimLPAllocation(address pool, address liquidityProvider) external payable returns(uint256);
    function createLpDeclaration(address _liquidityProvider, address _pool, uint32 _pUnits) external;
    function debitLpFeesFromSwapStream(address _pool, uint256 _feeInA) external;
    function debitBotFeesFromSwapStream(address pool, uint256 _amount) external;
    function transferAccumulatedFees(address _pool) external returns (uint256 fee);
    function updateLpDeclaration(address _liquidityProvider, address _pool, uint32 _pUnits, bool isAdd) external;
}