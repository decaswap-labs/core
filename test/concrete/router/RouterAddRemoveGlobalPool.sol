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

    function test_depositGlobalPool_success() public {
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
        (uint256 dOutPerStream,) = poolLogic.getSwapAmountOut(swapPerStream, reserveABefore, 0, reserveDBefore, 0);

        vm.startPrank(owner);
        router.depositToGlobalPool(address(tokenA), depositAmount);

        uint256 userBalanceAfter = tokenA.balanceOf(owner);

        uint256 dGlobalBalanceAfter = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceAfter = pool.userGlobalPoolInfo(owner, address(tokenA));

        bytes32 pairId = keccak256(abi.encodePacked(tokenA, tokenA));
        (GlobalPoolStream[] memory globalPoolStream, uint256 front, uint256 back) = pool.globalStreamQueue(pairId);
        (uint256 reserveDAfter,, uint256 reserveAAfter,,,) = pool.poolInfo(address(tokenA));

        GlobalPoolStream memory globalStream = globalPoolStream[front];

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

    function test_depositGlobalPoolCompleteStreaming_success() public {
        uint256 tokenAReserve = 500e18;
        uint256 dToMint = 100e18;
        _initGenesisPool(dToMint, tokenAReserve);

        uint256 depositAmount = 100e18;

        (uint256 reserveDBefore,, uint256 reserveABefore,,,) = pool.poolInfo(address(tokenA));

        uint256 dGlobalBalanceBefore = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceBefore = pool.userGlobalPoolInfo(owner, address(tokenA));
        uint256 userBalanceBefore = tokenA.balanceOf(owner);

        uint256 streamCount = poolLogic.calculateStreamCount(depositAmount, pool.globalSlippage(), reserveDBefore);
        uint256 swapPerStream = depositAmount / streamCount;
        (uint256 dOutPerStream,) = poolLogic.getSwapAmountOut(swapPerStream, reserveABefore, 0, reserveDBefore, 0);

        vm.startPrank(owner);
        router.depositToGlobalPool(address(tokenA), depositAmount);

        uint256 userBalanceAfter = tokenA.balanceOf(owner);

        uint256 dGlobalBalanceAfter = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceAfter = pool.userGlobalPoolInfo(owner, address(tokenA));

        bytes32 pairId = keccak256(abi.encodePacked(tokenA, tokenA));
        (GlobalPoolStream[] memory globalPoolStream, uint256 front, uint256 back) = pool.globalStreamQueue(pairId);
        (uint256 reserveDAfter,, uint256 reserveAAfter,,,) = pool.poolInfo(address(tokenA));

        assertEq(front, back);

        GlobalPoolStream memory globalStream = globalPoolStream[front - 1];

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

    function test_withdrawGlobalPool_success() public {
        uint256 tokenAReserve = 500e18;
        uint256 dToMint = 100e18;
        _initGenesisPool(dToMint, tokenAReserve);

        uint256 depositAmount = 100e18;

        vm.startPrank(owner);
        router.depositToGlobalPool(address(tokenA), depositAmount);

        bytes32 pairId = keccak256(abi.encodePacked(tokenA, tokenA));
        (GlobalPoolStream[] memory globalPoolStreamBefore, uint256 frontB, uint256 backB) =
            pool.globalStreamQueue(pairId);

        if (frontB == backB) frontB = frontB - 1;
        uint256 dToWtihdraw = globalPoolStreamBefore[frontB].amountOut;

        (uint256 reserveDBefore,, uint256 reserveABefore,,,) = pool.poolInfo(address(tokenA));

        uint256 dGlobalBalanceBefore = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceBefore = pool.userGlobalPoolInfo(owner, address(tokenA));
        uint256 userBalanceBefore = tokenA.balanceOf(owner);

        uint256 streamCount = poolLogic.calculateStreamCount(dToWtihdraw, pool.globalSlippage(), reserveDBefore);
        uint256 swapPerStream = dToWtihdraw / streamCount;
        uint256 amountOutPerStream = poolLogic.getSwapAmountOutFromD(swapPerStream, reserveABefore, reserveDBefore);

        router.withdrawFromGlobalPool(address(tokenA), dToWtihdraw);

        uint256 userBalanceAfter = tokenA.balanceOf(owner);

        (GlobalPoolStream[] memory globalPoolStreamAfter, uint256 frontA, uint256 backA) =
            pool.globalStreamQueue(pairId);
        if (frontA == backA) {
            frontA = frontA - 1;
            assertEq(userBalanceAfter, userBalanceBefore + amountOutPerStream);
        }

        uint256 dGlobalBalanceAfter = pool.globalPoolDBalance(pool.GLOBAL_POOL());
        uint256 userDPoolBalanceAfter = pool.userGlobalPoolInfo(owner, address(tokenA));

        (uint256 reserveDAfter,, uint256 reserveAAfter,,,) = pool.poolInfo(address(tokenA));

        GlobalPoolStream memory globalStream = globalPoolStreamAfter[frontA];

        assertEq(globalStream.amountOut, amountOutPerStream);
        assertEq(globalStream.streamsRemaining, streamCount - 1);
        assertEq(globalStream.swapPerStream, swapPerStream);
        assertEq(globalStream.swapAmountRemaining, dToWtihdraw - swapPerStream);

        assertEq(reserveDAfter, reserveDBefore + swapPerStream);
        assertEq(reserveAAfter, reserveABefore - globalStream.amountOut);

        assertEq(dGlobalBalanceAfter, dGlobalBalanceBefore - dToWtihdraw);
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
