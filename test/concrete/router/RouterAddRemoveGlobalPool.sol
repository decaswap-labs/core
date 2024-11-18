// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Deploys} from "test/shared/DeploysForRouter.t.sol";
import {IRouterErrors} from "src/interfaces/router/IRouterErrors.sol";
import {LiquidityStream, GlobalPoolStream} from "src/lib/SwapQueue.sol";
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

        (uint256 reserveDBefore,, uint256 reserveABefore,,,) = pool.poolInfo(address(tokenA));

        uint256 dGlobalBalanceBefore = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceBefore = pool.userGlobalPoolInfo(owner, address(tokenA));
        uint256 userBalanceBefore = tokenA.balanceOf(owner);

        uint256 streamCount = poolLogic.calculateStreamCount(depositAmount, pool.globalSlippage(), reserveDBefore);
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
        (uint256 reserveDAfter,, uint256 reserveAAfter,,,) = pool.poolInfo(address(tokenA));

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

        (uint256 reserveDBefore,, uint256 reserveABefore,,,) = pool.poolInfo(address(tokenA));

        uint256 dGlobalBalanceBefore = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceBefore = pool.userGlobalPoolInfo(owner, address(tokenA));
        uint256 userBalanceBefore = tokenA.balanceOf(owner);

        uint256 streamCount = poolLogic.calculateStreamCount(depositAmount, pool.globalSlippage(), reserveDBefore);
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
        (uint256 reserveDAfter,, uint256 reserveAAfter,,,) = pool.poolInfo(address(tokenA));

        assertEq(userBalanceAfter, userBalanceBefore - depositAmount);
        assertEq(reserveDAfter, reserveDBefore - dOutPerStream);
        assertEq(reserveAAfter, reserveABefore + swapPerStream);

        assertEq(dGlobalBalanceAfter, dGlobalBalanceBefore + dOutPerStream);
        assertEq(userDPoolBalanceAfter, userDPoolBalanceBefore + dOutPerStream);

        assertEq(globalPoolStream.length,0);
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

        (uint256 reserveDBefore,, uint256 reserveABefore,,,) = pool.poolInfo(address(tokenA));

        uint256 dGlobalBalanceBefore = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceBefore = pool.userGlobalPoolInfo(owner, address(tokenA));
        uint256 userBalanceBefore = tokenA.balanceOf(owner);

        uint256 streamCount = poolLogic.calculateStreamCount(dToWtihdraw, pool.globalSlippage(), reserveDBefore);
        uint256 swapPerStream = dToWtihdraw / streamCount;
        uint256 amountOutPerStream = poolLogic.getSwapAmountOutFromD(swapPerStream, reserveABefore, reserveDBefore);

        router.withdrawFromGlobalPool(address(tokenA), dToWtihdraw);

        uint256 userBalanceAfter = tokenA.balanceOf(owner);

        bytes32 pairId = bytes32(abi.encodePacked(tokenA, tokenA));

        GlobalPoolStream[] memory globalPoolStream =
            pool.globalStreamQueueWithdraw(pairId);

        uint256 dGlobalBalanceAfter = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceAfter = pool.userGlobalPoolInfo(owner, address(tokenA));

        (uint256 reserveDAfter,, uint256 reserveAAfter,,,) = pool.poolInfo(address(tokenA));

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

        (uint256 reserveDBefore,, uint256 reserveABefore,,,) = pool.poolInfo(address(tokenA));

        uint256 dGlobalBalanceBefore = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceBefore = pool.userGlobalPoolInfo(owner, address(tokenA));
        uint256 userBalanceBefore = tokenA.balanceOf(owner);

        uint256 streamCount = poolLogic.calculateStreamCount(dToWtihdraw, pool.globalSlippage(), reserveDBefore);
        console.log(streamCount);
        uint256 swapPerStream = dToWtihdraw / streamCount;
        uint256 amountOutPerStream = poolLogic.getSwapAmountOutFromD(swapPerStream, reserveABefore, reserveDBefore);

        router.withdrawFromGlobalPool(address(tokenA), dToWtihdraw);

        uint256 userBalanceAfter = tokenA.balanceOf(owner);

        uint256 dGlobalBalanceAfter = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceAfter = pool.userGlobalPoolInfo(owner, address(tokenA));

        (uint256 reserveDAfter,, uint256 reserveAAfter,,,) = pool.poolInfo(address(tokenA));

        assertEq(reserveDAfter, reserveDBefore + swapPerStream);
        assertEq(reserveAAfter, reserveABefore - amountOutPerStream);
    
        assertEq(dGlobalBalanceAfter, dGlobalBalanceBefore - dToWtihdraw); //dividing by 2 because globalPool is being withdrawn in 2 stream
        assertEq(userDPoolBalanceAfter, userDPoolBalanceBefore - dToWtihdraw);
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
}
