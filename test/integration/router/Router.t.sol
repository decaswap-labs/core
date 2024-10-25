// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Deploys} from "test/shared/Deploys.t.sol";

contract RouterTest is Deploys {
    function setUp() public virtual override {
        super.setUp();
        _createPools();
    }

    function _createPools() internal {
        vm.startPrank(owner);

        uint256 initialDToMintPoolA = 50e18;
        uint256 initialDToMintPoolB = 10e18;
        uint256 SLIPPAGE = 10;

        uint256 tokenAAmount = 100e18;
        uint256 minLaunchReserveAPoolA = 25e18;
        uint256 minLaunchReserveDPoolA = 25e18;

        uint256 tokenBAmount = 100e18;
        uint256 minLaunchReserveAPoolB = 25e18;
        uint256 minLaunchReserveDPoolB = 5e18; // we can change this for error test

        router.createPool(
            address(tokenA), tokenAAmount, minLaunchReserveAPoolA, minLaunchReserveDPoolA, initialDToMintPoolA
        );

        router.createPool(
            address(tokenB), tokenBAmount, minLaunchReserveAPoolB, minLaunchReserveDPoolB, initialDToMintPoolB
        );

        // update pair slippage
        pool.updatePairSlippage(address(tokenA), address(tokenB), SLIPPAGE);

        vm.stopPrank();
    }
}