// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Deploys} from "test/shared/DeploysForRouter.t.sol";
import {IRouterErrors} from "src/interfaces/router/IRouterErrors.sol";
import {LiquidityStream} from "src/lib/SwapQueue.sol";
import "forge-std/Test.sol";


contract RouterTest is Deploys {
    address nonAuthorized = makeAddr("nonAuthorized");

    function setUp() public virtual override {
        super.setUp();
    }

    // ======================================= PERMISSIONLESS POOLS ========================================//
    function _initGenesisPool(uint256 d, uint256 a) internal {
        vm.startPrank(owner);
        tokenA.approve(address(router), a);
        router.initGenesisPool(address(tokenA), a, d);
        vm.stopPrank();
    }

    function test_addLiqDualToken_success() public {
        uint256 tokenAReserve = 100e18;
        uint256 dToMint = 10e18;
        _initGenesisPool(dToMint, tokenAReserve);

        vm.startPrank(owner);
        uint256 streamTokenAmount = 100e18;
        uint256 streamToDTokenAmount = 50e18;

        tokenB.approve(address(router), streamTokenAmount);
        tokenA.approve(address(router), streamToDTokenAmount);

        // uint256 streamTokenStreamCount =
        //     poolLogic.calculateStreamCount(streamTokenAmount, pool.globalSlippage(), dToMint);
        // uint256 swapPerStreamInputToken = streamTokenAmount / streamTokenStreamCount;

        // uint256 streamToDTokenStreamCount =
        //     poolLogic.calculateStreamCount(streamToDTokenAmount, pool.globalSlippage(), dToMint);
        // uint256 swapPerStreamToDToken = streamToDTokenAmount / streamToDTokenStreamCount;

        // (uint256 reserveDBeforeA,, uint256 reserveABeforeA,,,) = pool.poolInfo(address(tokenA));

        // (uint256 reserveDBeforeB, uint256 poolOwnershipUnitsTotalBeforeB, uint256 reserveABeforeB,,,) =
        //     pool.poolInfo(address(tokenB));

        // (uint256 dToTransfer,) = poolLogic.getSwapAmountOut(swapPerStreamToDToken, reserveABeforeA, 0, reserveDBeforeA, 0);

        // uint256 lpUnitsBeforeFromToken = poolLogic.calculateLpUnitsToMint(0, swapPerStreamInputToken, swapPerStreamInputToken, 0, 0);
        // uint256 lpUnitsBeforeFromD = poolLogic.calculateLpUnitsToMint(lpUnitsBeforeFromToken, 0, swapPerStreamInputToken, dToTransfer, 0);

        // uint256 tokenBBalanceBefore = tokenB.balanceOf(owner);

        router.initPool(address(tokenB), address(tokenA), streamTokenAmount, streamToDTokenAmount);

        // uint256 tokenBBalanceAfter = tokenB.balanceOf(owner);

        // assertLt(tokenBBalanceAfter, tokenBBalanceBefore);
        // assertEq(tokenBBalanceAfter, tokenBBalanceBefore-streamTokenAmount);

        // (uint256 reserveDAfterA,, uint256 reserveAAfterA,,,) = pool.poolInfo(address(tokenA));
        // (uint256 reserveDAfterB, uint256 poolOwnershipUnitsTotalAfterB, uint256 reserveAAfterB,,,) =
        //     pool.poolInfo(address(tokenB));

        bytes32 pairId = keccak256(abi.encodePacked(address(tokenB), address(tokenA)));

        (LiquidityStream[] memory streams, uint256 front, uint256 back) = pool.liquidityStreamQueue(pairId);

        console.log(streams[front].poolBStream.streamsRemaining);
        console.log(streams[front].poolAStream.streamsRemaining);

        for(uint8 i = 0; i<streams[front].poolBStream.streamsRemaining; i++){
            router.processLiqStream(address(tokenB), address(tokenA));
        }

        (LiquidityStream[] memory streamsAfter, uint256 frontAfter, uint256 backAfter) = pool.liquidityStreamQueue(pairId);

        console.log("After",streams[frontAfter-1].poolBStream.streamsRemaining);
        console.log("After",streams[frontAfter-1].poolAStream.streamsRemaining);
        console.log("After",streams[frontAfter-1].poolAStream.swapAmountRemaining);


        // assertEq(streams[front].poolBStream.streamsRemaining, streamToDTokenStreamCount - 1);
        // assertEq(streams[front].poolBStream.swapPerStream, swapPerStreamToDToken);
        // assertEq(streams[front].poolBStream.swapAmountRemaining, streamToDTokenAmount - swapPerStreamToDToken);

        // assertEq(streams[front].poolAStream.streamsRemaining, streamTokenStreamCount - 1);
        // assertEq(streams[front].poolAStream.swapPerStream, swapPerStreamInputToken);
        // assertEq(streams[front].poolAStream.swapAmountRemaining, streamTokenAmount - swapPerStreamInputToken);

        // assertEq(reserveDAfterA, reserveDBeforeA - dToTransfer);
        // assertEq(reserveAAfterA, reserveABeforeA + swapPerStreamToDToken);

        // assertEq(poolOwnershipUnitsTotalAfterB, poolOwnershipUnitsTotalBeforeB + lpUnitsBeforeFromToken + lpUnitsBeforeFromD);
        // assertEq(reserveDAfterB, reserveDBeforeB + dToTransfer);
        // assertEq(reserveAAfterB, reserveABeforeB + swapPerStreamInputToken);
    }

}