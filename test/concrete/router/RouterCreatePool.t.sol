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

    // =============================== GENESIS POOLS ============================= //
    function test_initGenesisPool_success() public {
        uint256 addLiquidityTokenAmount = 100e18;
        uint256 dToMint = 50e18;
        uint256 lpUnitsBefore = addLiquidityTokenAmount;

        vm.startPrank(owner);
        tokenA.approve(address(router), addLiquidityTokenAmount);
        router.initGenesisPool(address(tokenA), addLiquidityTokenAmount, dToMint);
        uint256 lpUnitsAfter = pool.userLpUnitInfo(owner, address(tokenA));

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

    // ======================================= PERMISSIONLESS POOLS ========================================//
    function _initGenesisPool(uint256 d, uint256 a) internal {
        vm.startPrank(owner);
        tokenA.approve(address(router), a);
        router.initGenesisPool(address(tokenA), a, d);
        vm.stopPrank();
    }

    function test_initPool_success() public {
        uint256 tokenAReserve = 100e18;
        uint256 dToMint = 10e18;
        _initGenesisPool(dToMint, tokenAReserve);

        vm.startPrank(owner);
        uint256 streamTokenAmount = 100e18;
        uint256 streamToDTokenAmount = 50e18;

        tokenB.approve(address(router), streamTokenAmount);
        tokenA.approve(address(router), streamToDTokenAmount);

        uint256 streamTokenStreamCount =
            poolLogic.calculateStreamCount(streamTokenAmount, pool.globalSlippage(), dToMint);
        uint256 swapPerStreamInputToken = streamTokenAmount / streamTokenStreamCount;

        uint256 streamToDTokenStreamCount =
            poolLogic.calculateStreamCount(streamToDTokenAmount, pool.globalSlippage(), dToMint);
        uint256 swapPerStreamToDToken = streamToDTokenAmount / streamToDTokenStreamCount;

        (uint256 reserveDBeforeA,, uint256 reserveABeforeA,,,) = pool.poolInfo(address(tokenA));

        (uint256 reserveDBeforeB, uint256 poolOwnershipUnitsTotalBeforeB, uint256 reserveABeforeB,,,) =
            pool.poolInfo(address(tokenB));

        (uint256 dToTransfer,) = poolLogic.getSwapAmountOut(swapPerStreamToDToken, reserveABeforeA, 0, reserveDBeforeA, 0);

        uint256 lpUnitsBeforeFromToken = poolLogic.calculateLpUnitsToMint(0, swapPerStreamInputToken, swapPerStreamInputToken, 0, 0);
        uint256 lpUnitsBeforeFromD = poolLogic.calculateLpUnitsToMint(lpUnitsBeforeFromToken, 0, swapPerStreamInputToken, dToTransfer, 0);

        uint256 tokenBBalanceBefore = tokenB.balanceOf(owner);

        router.initPool(address(tokenB), address(tokenA), streamTokenAmount, streamToDTokenAmount);

        uint256 tokenBBalanceAfter = tokenB.balanceOf(owner);

        assertLt(tokenBBalanceAfter, tokenBBalanceBefore);
        assertEq(tokenBBalanceAfter, tokenBBalanceBefore-streamTokenAmount);

        (uint256 reserveDAfterA,, uint256 reserveAAfterA,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveDAfterB, uint256 poolOwnershipUnitsTotalAfterB, uint256 reserveAAfterB,,,) =
            pool.poolInfo(address(tokenB));

        bytes32 pairId = keccak256(abi.encodePacked(address(tokenB), address(tokenA)));

        (LiquidityStream[] memory streams, uint256 front, uint256 back) = pool.liquidityStreamQueue(pairId);

        assertEq(streams[front].poolBStream.streamsRemaining, streamToDTokenStreamCount - 1);
        assertEq(streams[front].poolBStream.swapPerStream, swapPerStreamToDToken);
        assertEq(streams[front].poolBStream.swapAmountRemaining, streamToDTokenAmount - swapPerStreamToDToken);

        assertEq(streams[front].poolAStream.streamsRemaining, streamTokenStreamCount - 1);
        assertEq(streams[front].poolAStream.swapPerStream, swapPerStreamInputToken);
        assertEq(streams[front].poolAStream.swapAmountRemaining, streamTokenAmount - swapPerStreamInputToken);

        assertEq(reserveDAfterA, reserveDBeforeA - dToTransfer);
        assertEq(reserveAAfterA, reserveABeforeA + swapPerStreamToDToken);

        assertEq(poolOwnershipUnitsTotalAfterB, poolOwnershipUnitsTotalBeforeB + lpUnitsBeforeFromToken + lpUnitsBeforeFromD);
        assertEq(reserveDAfterB, reserveDBeforeB + dToTransfer);
        assertEq(reserveAAfterB, reserveABeforeB + swapPerStreamInputToken);
    }

    function _initGenesisPoolsForBadCases() internal {
        vm.startPrank(owner);
        tokenA.approve(address(router), 100e18);
        router.initGenesisPool(address(tokenA), 100e18, 10e18);
        vm.stopPrank();
    }

    function test_initPool_invalidPool() public {
        vm.startPrank(owner);
        vm.expectRevert(IRouterErrors.InvalidPool.selector);
        router.initPool(address(tokenB), address(0xEedd), 1, 1);
    }

    function test_initPool_duplicatePool() public {
        _initGenesisPoolsForBadCases();
        vm.startPrank(owner);
        tokenB.approve(address(router), 100e18);
        router.initGenesisPool(address(tokenB), 100e18, 10e18);
        vm.expectRevert(IRouterErrors.DuplicatePool.selector);
        router.initPool(address(tokenA), address(tokenB), 1, 1);
    }

    function test_initPool_invalidAmount() public {
        _initGenesisPoolsForBadCases();
        vm.startPrank(owner);
        vm.expectRevert(IRouterErrors.InvalidAmount.selector);
        router.initPool(address(tokenB), address(tokenA), 0, 1);
    }

    function test_initPool_invalidLiquidityAmount() public {
        _initGenesisPoolsForBadCases();
        vm.startPrank(owner);
        vm.expectRevert(IRouterErrors.InvalidLiquidityTokenAmount.selector);
        router.initPool(address(tokenB), address(tokenA), 1, 0);
    }
}
