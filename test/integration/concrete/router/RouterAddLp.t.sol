// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Deploys } from "test/shared/DeploysForRouter.t.sol";
import { IRouterErrors } from "src/interfaces/router/IRouterErrors.sol";
import { LiquidityStream } from "src/lib/SwapQueue.sol";
import {PoolLogicLib} from "src/lib/PoolLogicLib.sol";
import {MockERC20} from "src/MockERC20.sol";
import "forge-std/Test.sol";

contract RouterTest is Deploys {
    address nonAuthorized = makeAddr("nonAuthorized");

    function setUp() public virtual override {
        super.setUp();
    }

    // ======================================= PERMISSIONLESS POOLS ========================================//
    function _initGenesisPool(uint256 d, uint256 a, MockERC20 token) internal {
        vm.startPrank(owner);
        token.approve(address(router), a);
        router.initGenesisPool(address(token), a, d);
        vm.stopPrank();
    }

    function test_addLiqDualToken_success() public {
        uint256 tokenAReserve = 100e18;
        uint256 dToMint = 10e18;
        _initGenesisPool(dToMint, tokenAReserve, tokenA);
        _initGenesisPool(dToMint, tokenAReserve, tokenB);

        vm.startPrank(owner);

        uint256 inputTokenAmount = 50e18;
        uint256 liquidityTokenAmount = 25e18;

        tokenA.approve(address(router), inputTokenAmount);
        tokenB.approve(address(router), liquidityTokenAmount);

        (uint256 reserveD_Before_A, uint256 poolOwnershipUnitsTotal_Before_A, uint256 reserveA_Before_A,,,,) =
            pool.poolInfo(address(tokenA));

        (uint256 reserveD_Before_B, uint256 poolOwnershipUnitsTotal_Before_B, uint256 reserveA_Before_B,,,,) =
            pool.poolInfo(address(tokenB));

        uint256 inputTokenStreamCount =
            PoolLogicLib.calculateStreamCount(inputTokenAmount, pool.globalSlippage(), reserveD_Before_A, liquidityLogic.STREAM_COUNT_PRECISION(), tokenA.decimals());
        uint256 swapPerStreamInputToken = inputTokenAmount / inputTokenStreamCount;

        bytes32 poolId = PoolLogicLib.getPoolId(address(tokenA), address(tokenB));
        uint256 liquidityTokenStreamCount =
            PoolLogicLib.calculateStreamCount(liquidityTokenAmount, pool.pairSlippage(poolId), reserveD_Before_B, liquidityLogic.STREAM_COUNT_PRECISION(), tokenB.decimals());
        uint256 swapPerStreamLiquidityToken = liquidityTokenAmount / liquidityTokenStreamCount;

        console.log("inputTokenStreamCount", inputTokenStreamCount);
        console.log("liquidityTokenStreamCount", liquidityTokenStreamCount);

        (uint256 dToTransfer,) =
            PoolLogicLib.getSwapAmountOut(swapPerStreamLiquidityToken, reserveA_Before_B, reserveA_Before_A, reserveD_Before_B, reserveD_Before_A);

        uint256 lpUnitsBeforeFromToken = PoolLogicLib.calculateLpUnitsToMint(
            poolOwnershipUnitsTotal_Before_A,
            swapPerStreamInputToken,
            swapPerStreamInputToken + reserveA_Before_A,
            0,
            reserveD_Before_A
        );
        uint256 lpUnitsBeforeFromD = PoolLogicLib.calculateLpUnitsToMint(
            lpUnitsBeforeFromToken + poolOwnershipUnitsTotal_Before_A,
            0,
            swapPerStreamInputToken + reserveA_Before_A,
            dToTransfer,
            reserveD_Before_A
        );

        uint256 tokenABalanceBefore = tokenA.balanceOf(owner);
        uint256 tokenBBalanceBefore = tokenB.balanceOf(owner);


        router.addLiqDualToken(address(tokenA), address(tokenB), inputTokenAmount, liquidityTokenAmount);

        uint256 tokenABalanceAfter = tokenA.balanceOf(owner);
        uint256 tokenBBalanceAfter = tokenB.balanceOf(owner);

        // TODO Start working from here
        bytes32 pairId = bytes32(abi.encodePacked(address(tokenA), address(tokenB)));
        (LiquidityStream[] memory liquidityStreams) = pool.liquidityStreamQueue(pairId);
        assertEq(liquidityStreams[0].poolAStream.streamsRemaining, inputTokenStreamCount - 1);
        assertEq(liquidityStreams[0].poolBStream.streamsRemaining, liquidityTokenStreamCount - 1);

        assertEq(liquidityStreams[0].poolAStream.swapAmountRemaining, inputTokenAmount - swapPerStreamInputToken);
        assertEq(
            liquidityStreams[0].poolBStream.swapAmountRemaining, liquidityTokenAmount - swapPerStreamLiquidityToken
        );


        assertLt(tokenABalanceAfter, tokenABalanceBefore);
        assertEq(tokenABalanceAfter, tokenABalanceBefore - inputTokenAmount);
        assertLt(tokenBBalanceAfter, tokenBBalanceBefore);
        assertEq(tokenBBalanceAfter, tokenBBalanceBefore - liquidityTokenAmount);

        
        (uint256 reserveD_After_A,uint256 poolOwnershipUnitsTotal_After_A, uint256 reserveA_After_A,,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_After_B,, uint256 reserveA_After_B,,,,) =
            pool.poolInfo(address(tokenB));


        assertEq(reserveD_After_B, reserveD_Before_B - dToTransfer);
        assertEq(reserveA_After_B, reserveA_Before_B + swapPerStreamLiquidityToken);

        assertEq(
            poolOwnershipUnitsTotal_After_A, poolOwnershipUnitsTotal_Before_A + lpUnitsBeforeFromToken + lpUnitsBeforeFromD
        );
        assertEq(reserveD_After_A, reserveD_Before_A + dToTransfer);
        assertEq(reserveA_After_A, reserveA_Before_A + swapPerStreamInputToken);
        vm.stopPrank();
    }

    function test_addToPoolSingle_success() public {
        uint256 tokenAReserve = 100e18;
        uint256 dToMint = 10e18;
        _initGenesisPool(dToMint, tokenAReserve, tokenA);
        _initGenesisPool(dToMint, tokenAReserve, tokenB);

        vm.startPrank(owner);

        uint256 inputTokenAmount = 50e18;
        // uint256 liquidityTokenAmount = 25e18;

        tokenA.approve(address(router), inputTokenAmount);
        // tokenB.approve(address(router), liquidityTokenAmount);

        (uint256 reserveD_Before_A, uint256 poolOwnershipUnitsTotal_Before_A, uint256 reserveA_Before_A,,,,) =
            pool.poolInfo(address(tokenA));

        // (uint256 reserveD_Before_B, uint256 poolOwnershipUnitsTotal_Before_B, uint256 reserveA_Before_B,,,,) =
        //     pool.poolInfo(address(tokenB));

        uint256 inputTokenStreamCount =
            PoolLogicLib.calculateStreamCount(inputTokenAmount, pool.globalSlippage(), reserveD_Before_A, liquidityLogic.STREAM_COUNT_PRECISION(), tokenA.decimals());
        uint256 swapPerStreamInputToken = inputTokenAmount / inputTokenStreamCount;

        // bytes32 poolId = PoolLogicLib.getPoolId(address(tokenA), address(tokenB));
        // uint256 liquidityTokenStreamCount =
        //     PoolLogicLib.calculateStreamCount(liquidityTokenAmount, pool.pairSlippage(poolId), reserveD_Before_B, liquidityLogic.STREAM_COUNT_PRECISION(), tokenB.decimals());
        // uint256 swapPerStreamLiquidityToken = liquidityTokenAmount / liquidityTokenStreamCount;

        // console.log("inputTokenStreamCount", inputTokenStreamCount);
        // console.log("liquidityTokenStreamCount", liquidityTokenStreamCount);

        // (uint256 dToTransfer,) =
        //     PoolLogicLib.getSwapAmountOut(swapPerStreamLiquidityToken, reserveA_Before_B, reserveA_Before_A, reserveD_Before_B, reserveD_Before_A);

        uint256 lpUnitsBeforeFromToken = PoolLogicLib.calculateLpUnitsToMint(
            poolOwnershipUnitsTotal_Before_A,
            swapPerStreamInputToken,
            swapPerStreamInputToken + reserveA_Before_A,
            0,
            reserveD_Before_A
        );
        // uint256 lpUnitsBeforeFromD = PoolLogicLib.calculateLpUnitsToMint(
        //     lpUnitsBeforeFromToken + poolOwnershipUnitsTotal_Before_A,
        //     0,
        //     swapPerStreamInputToken + reserveA_Before_A,
        //     dToTransfer,
        //     reserveD_Before_A
        // );

        uint256 tokenABalanceBefore = tokenA.balanceOf(owner);
        // uint256 tokenBBalanceBefore = tokenB.balanceOf(owner);


        router.addOnlyTokenLiquidity(address(tokenA), inputTokenAmount);

        uint256 tokenABalanceAfter = tokenA.balanceOf(owner);
        // uint256 tokenBBalanceAfter = tokenB.balanceOf(owner);

        bytes32 pairId = bytes32(abi.encodePacked(address(tokenA), address(tokenA)));
        (LiquidityStream[] memory liquidityStreams) = pool.liquidityStreamQueue(pairId);
        console.log(liquidityStreams.length);
        assertEq(liquidityStreams[0].poolAStream.streamsRemaining, inputTokenStreamCount - 1);
        assertEq(liquidityStreams[0].poolBStream.streamsRemaining, 0);

        assertEq(liquidityStreams[0].poolAStream.swapAmountRemaining, inputTokenAmount - swapPerStreamInputToken);
            // assertEq(
            //     liquidityStreams[0].poolBStream.swapAmountRemaining, liquidityTokenAmount - swapPerStreamLiquidityToken
            // );

        assertLt(tokenABalanceAfter, tokenABalanceBefore);
        assertEq(tokenABalanceAfter, tokenABalanceBefore - inputTokenAmount);
        // assertLt(tokenBBalanceAfter, tokenBBalanceBefore);
        // assertEq(tokenBBalanceAfter, tokenBBalanceBefore - liquidityTokenAmount);

        
        (,uint256 poolOwnershipUnitsTotal_After_A, uint256 reserveA_After_A,,,,) = pool.poolInfo(address(tokenA));
        // (uint256 reserveD_After_B,, uint256 reserveA_After_B,,,,) =
        //     pool.poolInfo(address(tokenB));


        // assertEq(reserveD_After_B, reserveD_Before_B - dToTransfer);
        // assertEq(reserveA_After_B, reserveA_Before_B + swapPerStreamLiquidityToken);

        assertEq(
            poolOwnershipUnitsTotal_After_A, poolOwnershipUnitsTotal_Before_A + lpUnitsBeforeFromToken
        );
        // assertEq(reserveD_After_A, reserveD_Before_A + dToTransfer);
        assertEq(reserveA_After_A, reserveA_Before_A + swapPerStreamInputToken);
        vm.stopPrank();
    }

    // function test_streamDToPool_success() public {
    //     uint256 tokenAReserve = 100e18;
    //     uint256 dToMint = 10e18;
    //     _initGenesisPool(dToMint, tokenAReserve);

    //     vm.startPrank(owner);
    //     uint256 tokenAmount = 100e18;
    //     uint256 dToTokenAmount = 50e18;

    //     tokenB.approve(address(router), tokenAmount);
    //     tokenA.approve(address(router), dToTokenAmount);

    //     router.initPool(address(tokenB), address(tokenA), tokenAmount, dToTokenAmount);

    //     bytes32 pairId = keccak256(abi.encodePacked(address(tokenB), address(tokenA)));
    //     (LiquidityStream[] memory streams, uint256 front,) = pool.liquidityStreamQueue(pairId);

    //     for (uint8 i = 0; i < streams[front].poolBStream.streamsRemaining; i++) {
    //         router.processLiqStream(address(tokenB), address(tokenA));
    //     }
    //     (LiquidityStream[] memory streamsAfter, uint256 frontAfter,) = pool.liquidityStreamQueue(pairId);

    //     assertEq(streamsAfter[frontAfter - 1].poolBStream.streamsRemaining, 0);
    //     assertEq(streamsAfter[frontAfter - 1].poolAStream.streamsRemaining, 0);
    //     assertEq(streamsAfter[frontAfter - 1].poolAStream.swapAmountRemaining, 0);
    //     assertEq(streamsAfter[frontAfter - 1].poolBStream.swapAmountRemaining, 0);

    //     uint256 dToTokenAmountSingle = 25e18;

    //     tokenA.approve(address(router), dToTokenAmountSingle);

    //     (uint256 reserveDBeforeB, uint256 poolOwnershipUnitsTotalBeforeB, uint256 reserveABeforeB,,,) =
    //         pool.poolInfo(address(tokenB));

    //     (uint256 reserveDBeforeA,, uint256 reserveABeforeA,,,) = pool.poolInfo(address(tokenA));

    //     uint256 dStreamCount =
    //         poolLogic.calculateStreamCount(dToTokenAmountSingle, pool.globalSlippage(), reserveDBeforeA);
    //     uint256 swapPerStreamDToToken = dToTokenAmountSingle / dStreamCount;

    //     (uint256 dToTransfer,) =
    //         poolLogic.getSwapAmountOut(swapPerStreamDToToken, reserveABeforeA, 0, reserveDBeforeA, 0);

    //     uint256 lpUnitsBeforeFromD = poolLogic.calculateLpUnitsToMint(
    //         poolOwnershipUnitsTotalBeforeB, 0, reserveABeforeB, dToTransfer, reserveDBeforeB + dToTransfer
    //     );

    //     uint256 tokenABalanceBefore = tokenA.balanceOf(owner);

    //     router.streamDToPool(address(tokenB), address(tokenA), dToTokenAmountSingle);

    //     uint256 tokenABalanceAfter = tokenA.balanceOf(owner);

    //     (LiquidityStream[] memory streamsAfterDual, uint256 frontAD,) = pool.liquidityStreamQueue(pairId);

    //     assertEq(streamsAfterDual[frontAD].poolBStream.streamsRemaining, dStreamCount - 1);

    //     assertEq(
    //         streamsAfterDual[frontAD].poolBStream.swapAmountRemaining, dToTokenAmountSingle - swapPerStreamDToToken
    //     );
    //     assertLt(tokenABalanceAfter, tokenABalanceBefore);
    //     assertEq(tokenABalanceAfter, tokenABalanceBefore - dToTokenAmountSingle);

    //     (uint256 reserveDAfterB, uint256 poolOwnershipUnitsTotalAfterB,,,,) = pool.poolInfo(address(tokenB));

    //     (uint256 reserveDAfterA,, uint256 reserveAAfterA,,,) = pool.poolInfo(address(tokenA));

    //     assertEq(reserveDAfterA, reserveDBeforeA - dToTransfer);
    //     assertEq(reserveAAfterA, reserveABeforeA + swapPerStreamDToToken);

    //     assertEq(poolOwnershipUnitsTotalAfterB, poolOwnershipUnitsTotalBeforeB + lpUnitsBeforeFromD);
    //     assertEq(reserveDAfterB, reserveDBeforeB + dToTransfer);
    //     vm.stopPrank();
    // }

    // function _initPermissionlessPoolForBadCases() internal {
    //     uint256 tokenAReserve = 100e18;
    //     uint256 dToMint = 10e18;
    //     _initGenesisPool(dToMint, tokenAReserve);

    //     vm.startPrank(owner);
    //     uint256 tokenAmount = 100e18;
    //     uint256 dToTokenAmount = 50e18;

    //     tokenB.approve(address(router), tokenAmount);
    //     tokenA.approve(address(router), dToTokenAmount);

    //     router.initPool(address(tokenB), address(tokenA), tokenAmount, dToTokenAmount);
    //     vm.stopPrank();
    // }

    // function test_addLiqDualToken_samePool() public {
    //     vm.startPrank(owner);
    //     vm.expectRevert(IRouterErrors.SamePool.selector);
    //     router.addLiqDualToken(address(tokenB), address(tokenB), 1, 1);
    // }

    // function test_addLiqDualToken_poolNotExist() public {
    //     vm.startPrank(owner);
    //     vm.expectRevert(IRouterErrors.InvalidPool.selector);
    //     router.addLiqDualToken(address(tokenB), address(tokenA), 1, 1);
    // }

    // function test_addLiqDualToken_invalidAmount() public {
    //     _initPermissionlessPoolForBadCases();
    //     vm.startPrank(owner);
    //     vm.expectRevert(IRouterErrors.InvalidAmount.selector);
    //     router.addLiqDualToken(address(tokenB), address(tokenA), 0, 0);
    // }

    // function test_streamDToPool_samePool() public {
    //     vm.startPrank(owner);
    //     vm.expectRevert(IRouterErrors.SamePool.selector);
    //     router.streamDToPool(address(tokenB), address(tokenB), 1);
    // }

    // function test_streamDToPool_poolNotExist() public {
    //     vm.startPrank(owner);
    //     vm.expectRevert(IRouterErrors.InvalidPool.selector);
    //     router.streamDToPool(address(tokenB), address(tokenA), 1);
    // }

    // function test_streamDToPool_invalidAmount() public {
    //     _initPermissionlessPoolForBadCases();
    //     vm.startPrank(owner);
    //     vm.expectRevert(IRouterErrors.InvalidAmount.selector);
    //     router.streamDToPool(address(tokenB), address(tokenA), 0);
    // }

    // function test_addPoolSingle_poolNotExist() public {
    //     vm.startPrank(owner);
    //     vm.expectRevert(IRouterErrors.InvalidPool.selector);
    //     router.addToPoolSingle(address(tokenB), 1);
    // }

    // function test_addPoolSingle_invalidAmount() public {
    //     _initPermissionlessPoolForBadCases();
    //     vm.startPrank(owner);
    //     vm.expectRevert(IRouterErrors.InvalidAmount.selector);
    //     router.addToPoolSingle(address(tokenB), 0);
    // }
}
