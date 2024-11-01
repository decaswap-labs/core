// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Deploys} from "test/shared/DeploysForRouter.t.sol";


contract RouterTest is Deploys {
    address nonAuthorized = makeAddr("nonAuthorized");

    function setUp() public virtual override {
        super.setUp();
        // _createPools();
    }

    // function _createPools() internal {
    //     vm.startPrank(owner);

    //     uint256 initialDToMintPoolA = 30e18;
    //     uint256 initialDToMintPoolB = 20e18;
    //     uint256 SLIPPAGE = 10;

    //     uint256 tokenAAmount = 10000e18;
    //     uint256 minLaunchReserveAPoolA = 10e18;
    //     uint256 minLaunchReserveDPoolA = 10e18;

    //     uint256 tokenBAmount = 10000e18;
    //     uint256 minLaunchReserveAPoolB = 10e18;
    //     uint256 minLaunchReserveDPoolB = 10e18; // we can change this for error test

    //     router.createPool(
    //         address(tokenA), tokenAAmount, minLaunchReserveAPoolA, minLaunchReserveDPoolA, initialDToMintPoolA
    //     );

    //     router.createPool(
    //         address(tokenB), tokenBAmount, minLaunchReserveAPoolB, minLaunchReserveDPoolB, initialDToMintPoolB
    //     );

    //     // update pair slippage
    //     pool.updatePairSlippage(address(tokenA), address(tokenB), SLIPPAGE);

    //     vm.stopPrank();
    // }


    function test_initGenesisPool_success() public {
        uint256 addLiquidityTokenAmount = 100e18;
        uint256 dToMint = 50e18;
        uint256 lpUnitsBefore =
            poolLogic.calculateLpUnitsToMint(0, addLiquidityTokenAmount, addLiquidityTokenAmount, dToMint, 0); //@todo this can change

        vm.startPrank(owner);
        tokenA.approve(address(router), addLiquidityTokenAmount);
        router.initGenesisPool(address(tokenA), addLiquidityTokenAmount, dToMint);
        uint256 lpUnitsAfter = pool.userLpUnitInfo(owner, address(tokenA));

        assertEq(lpUnitsBefore, lpUnitsAfter);

        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        ) = pool.poolInfo(address(tokenA));
        uint256 poolBalanceAfter = tokenA.balanceOf(address(pool));

        assertEq(reserveD, dToMint);
        assertEq(poolOwnershipUnitsTotal, lpUnitsAfter);
        assertEq(lpUnitsBefore, lpUnitsAfter);
        assertEq(reserveA, addLiquidityTokenAmount);
        assertEq(poolBalanceAfter, addLiquidityTokenAmount);
        assertEq(initialDToMint, dToMint);
        assertEq(initialized, true);
    }

    function test_initGenesisPool_invalidTokenAmount() public {
        vm.startPrank(owner);
        vm.expectRevert(IRouterErrors.InvalidAmount.selector);
        router.initGenesisPool(address(tokenA), 0, 1);
    }

    function test_initGenesisPool_invalidDAmount() public {
        vm.startPrank(owner);
        vm.expectRevert(IRouterErrors.InvalidInitialDAmount.selector);
        router.initGenesisPool(address(tokenA), 1, 0);
    }

    function test_initGenesisPool_invalidToken() public {
        vm.startPrank(owner);
        vm.expectRevert(IRouterErrors.InvalidToken.selector);
        router.initGenesisPool(address(0), 1, 0);
    }

    function test_initGenesisPool_notOwner() public {
        vm.startPrank(nonAuthorized);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), nonAuthorized));
        router.initGenesisPool(address(tokenA), 1, 1);
    }
}
