// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { Deploys } from "test/shared/DeploysForRouter.t.sol";
import { IRouterErrors } from "src/interfaces/router/IRouterErrors.sol";
import { LiquidityStream, GlobalPoolStream } from "src/lib/SwapQueue.sol";
import "forge-std/Test.sol";

contract RouterTest is Deploys {
    address nonAuthorized = makeAddr("nonAuthorized");

    function setUp() public virtual override {
        super.setUp();
    }

    // ======================================= ADD TO GLOBAL POOL ========================================//
    function _initGenesisPool(uint256 d, uint256 a) internal {
        vm.startPrank(owner);
        tokenA.approve(address(router), a);
        router.initGenesisPool(address(tokenA), a, d);
        vm.stopPrank();
    }

    function test_depositGlobalPool_oneStreamExecutionAndEnqueueInArray_eoaFlow_success() public {
        uint256 tokenAReserve = 500e18;
        uint256 dToMint = 100e18;
        _initGenesisPool(dToMint, tokenAReserve);

        uint256 depositAmount = 200e18;

        (uint256 reserveDBefore,, uint256 reserveABefore,,,, uint8 decimalsA) = pool.poolInfo(address(tokenA));

        uint256 dGlobalBalanceBefore = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceBefore = pool.userGlobalPoolInfo(owner, address(tokenA));
        uint256 userBalanceBefore = tokenA.balanceOf(owner);

        uint256 streamCount =
            poolLogic.calculateStreamCount(depositAmount, pool.globalSlippage(), reserveDBefore, decimalsA);
        uint256 swapPerStream = depositAmount / streamCount;

        if (depositAmount % streamCount != 0) {
            depositAmount = streamCount * swapPerStream;
        }

        (uint256 dOutPerStream,) = poolLogic.getSwapAmountOut(swapPerStream, reserveABefore, 0, reserveDBefore, 0);

        vm.startPrank(owner);
        router.depositToGlobalPool(address(tokenA), depositAmount);

        uint256 userBalanceAfter = tokenA.balanceOf(owner);

        uint256 dGlobalBalanceAfter = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceAfter = pool.userGlobalPoolInfo(owner, address(tokenA));

        bytes32 pairId = bytes32(abi.encodePacked(tokenA, tokenA));
        GlobalPoolStream[] memory globalPoolStream = pool.globalStreamQueueDeposit(pairId);
        (uint256 reserveDAfter,, uint256 reserveAAfter,,,,) = pool.poolInfo(address(tokenA));

        GlobalPoolStream memory globalStream = globalPoolStream[0];

        assertEq(userBalanceAfter, userBalanceBefore - depositAmount);

        assertEq(globalStream.amountOut, dOutPerStream);
        assertEq(globalStream.streamsRemaining, streamCount - 1);
        assertEq(globalStream.swapPerStream, swapPerStream);
        assertEq(globalStream.swapAmountRemaining, depositAmount - swapPerStream);

        assertEq(reserveDAfter, reserveDBefore - globalStream.amountOut);
        assertEq(reserveAAfter, reserveABefore + swapPerStream);

        assertEq(dGlobalBalanceAfter, dGlobalBalanceBefore + dOutPerStream);
        assertEq(userDPoolBalanceAfter, userDPoolBalanceBefore + dOutPerStream);
    }

    function test_depositGlobalPool_oneStreamExecution_eoaFlow_success() public {
        uint256 tokenAReserve = 500e18;
        uint256 dToMint = 100e18;
        _initGenesisPool(dToMint, tokenAReserve);

        uint256 depositAmount = 100e18; // for 1 stream

        (uint256 reserveDBefore,, uint256 reserveABefore,,,, uint8 decimalsA) = pool.poolInfo(address(tokenA));

        uint256 dGlobalBalanceBefore = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceBefore = pool.userGlobalPoolInfo(owner, address(tokenA));
        uint256 userBalanceBefore = tokenA.balanceOf(owner);

        uint256 streamCount =
            poolLogic.calculateStreamCount(depositAmount, pool.globalSlippage(), reserveDBefore, decimalsA);
        uint256 swapPerStream = depositAmount / streamCount;

        if (depositAmount % streamCount != 0) {
            depositAmount = streamCount * swapPerStream;
        }

        (uint256 dOutPerStream,) = poolLogic.getSwapAmountOut(swapPerStream, reserveABefore, 0, reserveDBefore, 0);

        vm.startPrank(owner);
        router.depositToGlobalPool(address(tokenA), depositAmount);

        uint256 userBalanceAfter = tokenA.balanceOf(owner);

        uint256 dGlobalBalanceAfter = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceAfter = pool.userGlobalPoolInfo(owner, address(tokenA));

        bytes32 pairId = bytes32(abi.encodePacked(tokenA, tokenA));
        GlobalPoolStream[] memory globalPoolStream = pool.globalStreamQueueDeposit(pairId);
        (uint256 reserveDAfter,, uint256 reserveAAfter,,,,) = pool.poolInfo(address(tokenA));

        assertEq(userBalanceAfter, userBalanceBefore - depositAmount);
        assertEq(reserveDAfter, reserveDBefore - dOutPerStream);
        assertEq(reserveAAfter, reserveABefore + swapPerStream);

        assertEq(dGlobalBalanceAfter, dGlobalBalanceBefore + dOutPerStream);
        assertEq(userDPoolBalanceAfter, userDPoolBalanceBefore + dOutPerStream);

        assertEq(globalPoolStream.length, 0);
    }

    function test_depositGlobalPool_invalidPool() public {
        vm.startPrank(owner);
        vm.expectRevert(IRouterErrors.InvalidPool.selector);
        router.depositToGlobalPool(address(tokenA), 1);
    }

    function test_depositGlobalPool_invalidAmount() public {
        _initGenesisPool(100e18, 100e18);
        vm.startPrank(owner);
        vm.expectRevert(IRouterErrors.InvalidAmount.selector);
        router.depositToGlobalPool(address(tokenA), 0);
    }

    // ------------------------------------------------- REMOVE GLOBAL POOL ------------------------------- //

    function test_withdrawGlobalPool_oneStreamExecutionAndEnqueueInArray_eoaFlow_success() public {
        uint256 tokenAReserve = 100e18;
        uint256 dToMint = 1000e18;
        _initGenesisPool(dToMint, tokenAReserve);

        uint256 depositAmount = 200e18;

        vm.startPrank(owner);
        router.depositToGlobalPool(address(tokenA), depositAmount);

        uint256 dToWtihdraw = pool.userGlobalPoolInfo(owner, address(tokenA));

        (uint256 reserveDBefore,, uint256 reserveABefore,,,, uint8 decimalsA) = pool.poolInfo(address(tokenA));

        uint256 dGlobalBalanceBefore = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceBefore = pool.userGlobalPoolInfo(owner, address(tokenA));
        // uint256 userBalanceBefore = tokenA.balanceOf(owner);

        uint256 streamCount =
            poolLogic.calculateStreamCount(dToWtihdraw, pool.globalSlippage(), reserveDBefore, decimalsA);
        uint256 swapPerStream = dToWtihdraw / streamCount;
        uint256 amountOutPerStream = poolLogic.getSwapAmountOutFromD(swapPerStream, reserveABefore, reserveDBefore);

        router.withdrawFromGlobalPool(address(tokenA), dToWtihdraw);

        // uint256 userBalanceAfter = tokenA.balanceOf(owner);

        bytes32 pairId = bytes32(abi.encodePacked(tokenA, tokenA));

        GlobalPoolStream[] memory globalPoolStream = pool.globalStreamQueueWithdraw(pairId);

        uint256 dGlobalBalanceAfter = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceAfter = pool.userGlobalPoolInfo(owner, address(tokenA));

        (uint256 reserveDAfter,, uint256 reserveAAfter,,,,) = pool.poolInfo(address(tokenA));

        GlobalPoolStream memory globalStream = globalPoolStream[0];

        assertEq(globalStream.amountOut, amountOutPerStream);
        assertEq(globalStream.streamsRemaining, streamCount - 1);
        assertEq(globalStream.swapPerStream, swapPerStream);
        assertEq(globalStream.swapAmountRemaining, dToWtihdraw - swapPerStream);

        assertEq(reserveDAfter, reserveDBefore + swapPerStream);
        assertEq(reserveAAfter, reserveABefore - amountOutPerStream);

        assertEq(dGlobalBalanceAfter, dGlobalBalanceBefore - globalStream.swapPerStream);
        assertEq(userDPoolBalanceAfter, userDPoolBalanceBefore - globalStream.swapPerStream);
    }

    function test_withdrawGlobalPool_oneStreamExecution_eoaFlow_success() public {
        uint256 tokenAReserve = 200e18;
        uint256 dToMint = 10e18;
        _initGenesisPool(dToMint, tokenAReserve);

        uint256 depositAmount = 100e18;
        vm.startPrank(owner);
        router.depositToGlobalPool(address(tokenA), depositAmount);

        uint256 dToWtihdraw = pool.userGlobalPoolInfo(owner, address(tokenA));

        (uint256 reserveDBefore,, uint256 reserveABefore,,,, uint8 decimalsA) = pool.poolInfo(address(tokenA));

        uint256 dGlobalBalanceBefore = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceBefore = pool.userGlobalPoolInfo(owner, address(tokenA));
        // uint256 userBalanceBefore = tokenA.balanceOf(owner);

        uint256 streamCount =
            poolLogic.calculateStreamCount(dToWtihdraw, pool.globalSlippage(), reserveDBefore, decimalsA);
        uint256 swapPerStream = dToWtihdraw / streamCount;
        uint256 amountOutPerStream = poolLogic.getSwapAmountOutFromD(swapPerStream, reserveABefore, reserveDBefore);

        uint256 userTokenBalanceBefore = tokenA.balanceOf(owner);

        router.withdrawFromGlobalPool(address(tokenA), dToWtihdraw);

        uint256 userBalanceAfter = tokenA.balanceOf(owner);

        uint256 dGlobalBalanceAfter = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceAfter = pool.userGlobalPoolInfo(owner, address(tokenA));

        (uint256 reserveDAfter,, uint256 reserveAAfter,,,,) = pool.poolInfo(address(tokenA));

        assertEq(reserveDAfter, reserveDBefore + swapPerStream);
        assertEq(reserveAAfter, reserveABefore - amountOutPerStream);

        assertEq(dGlobalBalanceAfter, dGlobalBalanceBefore - dToWtihdraw); //dividing by 2 because globalPool is being
            // withdrawn in 2 stream
        assertEq(userDPoolBalanceAfter, userDPoolBalanceBefore - dToWtihdraw);
        assertEq(userBalanceAfter, userTokenBalanceBefore + amountOutPerStream);
    }

    function test_withdrawFromGlobalPool_invalidPool() public {
        vm.startPrank(owner);
        vm.expectRevert(IRouterErrors.InvalidPool.selector);
        router.withdrawFromGlobalPool(address(tokenA), 1);
    }

    function test_withdrawFromGlobalPool_invalidAmount() public {
        _initGenesisPool(100e18, 100e18);
        vm.startPrank(owner);
        vm.expectRevert(IRouterErrors.InvalidAmount.selector);
        router.withdrawFromGlobalPool(address(tokenA), 1);
    }

    // ------------------------------------------------ EOA FLOW -------------------------------------------- //
    function test_processGlobalStreamPairDeposit_executeOneStreamOfMultipleObjects_success() public {
        uint256 tokenAReserve = 50_000e18;
        uint256 dToMint = 100e18;
        _initGenesisPool(dToMint, tokenAReserve);

        uint256 depositAmount = 300e18; //for 3 streams
        (,,,,,, uint8 decimalsA) = pool.poolInfo(address(tokenA));

        uint256 streamCount = poolLogic.calculateStreamCount(depositAmount, pool.globalSlippage(), dToMint, decimalsA);

        vm.startPrank(owner);
        for (uint256 i = 0; i < 10; i++) {
            router.depositToGlobalPool(address(tokenA), depositAmount);
        }

        bytes32 pairId = bytes32(abi.encodePacked(tokenA, tokenA));
        GlobalPoolStream[] memory globalPoolStream = pool.globalStreamQueueDeposit(pairId);

        for (uint256 i = 0; i < globalPoolStream.length; i++) {
            assertEq(globalPoolStream[i].streamsRemaining, streamCount - 1);
        }

        router.processGlobalStreamPairDeposit();

        GlobalPoolStream[] memory globalPoolStreamAfter = pool.globalStreamQueueDeposit(pairId);

        for (uint256 i = 0; i < globalPoolStreamAfter.length; i++) {
            assertEq(globalPoolStreamAfter[i].streamsRemaining, streamCount - 2);
        }
    }

    function test_processGlobalStreamPairDeposit_executeOneStreamOfMultipleObjectsAndEmptyTheArray_success() public {
        uint256 tokenAReserve = 50_000e18;
        uint256 dToMint = 100e18;
        _initGenesisPool(dToMint, tokenAReserve);

        uint256 depositAmount = 200e18; //for 2 streams
        (,,,,,, uint8 decimalsA) = pool.poolInfo(address(tokenA));

        uint256 streamCount = poolLogic.calculateStreamCount(depositAmount, pool.globalSlippage(), dToMint, decimalsA);

        vm.startPrank(owner);
        for (uint256 i = 0; i < 10; i++) {
            router.depositToGlobalPool(address(tokenA), depositAmount);
        }

        bytes32 pairId = bytes32(abi.encodePacked(tokenA, tokenA));
        GlobalPoolStream[] memory globalPoolStream = pool.globalStreamQueueDeposit(pairId);

        for (uint256 i = 0; i < globalPoolStream.length; i++) {
            assertEq(globalPoolStream[i].streamsRemaining, streamCount - 1);
        }

        router.processGlobalStreamPairDeposit();

        GlobalPoolStream[] memory globalPoolStreamAfter = pool.globalStreamQueueDeposit(pairId);

        assertEq(globalPoolStreamAfter.length, 0);
    }
    /*
    * @notice, for first swap, 10 stream, for 2nd 5 streams
    */

    function test_processGlobalStreamPairWithdraw_executeOneStreamOfMultipleObjects_success() public {
        uint256 tokenAReserve = 100e18;
        uint256 dToMint = 2000e18;
        _initGenesisPool(dToMint, tokenAReserve);

        uint256 depositAmount = 4000e18;

        uint256 totalTx = 2;

        vm.startPrank(owner);
        router.depositToGlobalPool(address(tokenA), depositAmount);

        uint256 dBalanceToWithdraw = pool.userGlobalPoolInfo(owner, address(tokenA));

        // (uint256 reserveDBefore,,,,,) = pool.poolInfo(address(tokenA));

        // uint256 streamCount =
        //     poolLogic.calculateStreamCount(dBalanceToWithdraw / totalTx, pool.globalSlippage(), reserveDBefore);

        uint256 dToWithdraw = dBalanceToWithdraw / totalTx;

        for (uint256 i = 0; i < totalTx; i++) {
            router.withdrawFromGlobalPool(address(tokenA), dToWithdraw);
        }
        bytes32 pairId = bytes32(abi.encodePacked(tokenA, tokenA));
        GlobalPoolStream[] memory globalPoolStreamBefore = pool.globalStreamQueueWithdraw(pairId);

        for (uint256 i = 0; i < globalPoolStreamBefore.length; i++) {
            assertEq(globalPoolStreamBefore[i].streamsRemaining, globalPoolStreamBefore[i].streamCount - 1);
        }

        router.processGlobalStreamPairWithdraw();

        GlobalPoolStream[] memory globalPoolStream = pool.globalStreamQueueWithdraw(pairId);

        for (uint256 i = 0; i < globalPoolStream.length; i++) {
            assertEq(globalPoolStream[i].streamsRemaining, globalPoolStream[i].streamCount - 2);
        }
    }

    function test_processGlobalStreamPairWithdraw_executeOneStreamOfMultipleObjectsAndEmptyArray_success() public {
        uint256 tokenAReserve = 100e18;
        uint256 dToMint = 2000e18;
        _initGenesisPool(dToMint, tokenAReserve);

        uint256 depositAmount = 4000e18; //for 3 streams

        vm.startPrank(owner);
        router.depositToGlobalPool(address(tokenA), depositAmount);

        uint256 dBalanceToWithdraw = pool.userGlobalPoolInfo(owner, address(tokenA));

        // (uint256 reserveDBefore,,,,,) = pool.poolInfo(address(tokenA));

        // uint256 streamCount = poolLogic.calculateStreamCount(dBalanceToWithdraw, pool.globalSlippage(),
        // reserveDBefore);

        router.withdrawFromGlobalPool(address(tokenA), dBalanceToWithdraw);
        bytes32 pairId = bytes32(abi.encodePacked(tokenA, tokenA));
        GlobalPoolStream[] memory globalPoolStreamBefore = pool.globalStreamQueueWithdraw(pairId);

        for (uint256 i = 0; i < globalPoolStreamBefore[0].streamCount; i++) {
            router.processGlobalStreamPairWithdraw();
        }

        GlobalPoolStream[] memory globalPoolStreamAfter = pool.globalStreamQueueWithdraw(pairId);
        assertEq(globalPoolStreamAfter.length, 0);
    }
}
