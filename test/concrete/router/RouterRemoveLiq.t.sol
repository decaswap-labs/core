// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Deploys} from "test/shared/DeploysForRouter.t.sol";
import {IRouterErrors} from "src/interfaces/router/IRouterErrors.sol";
import {LiquidityStream,RemoveLiquidityStream} from "src/lib/SwapQueue.sol";
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

    function test_removeLiqFromGenesisPoolSingleStream_success() public {

        uint256 tokenAReserve = 100e18;
        uint256 dToMint = 10e18;
        _initGenesisPool(dToMint, tokenAReserve);

        vm.startPrank(owner);

        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        ) = pool.poolInfo(address(tokenA));

        
        uint userLpUnits = pool.userLpUnitInfo(owner,address(tokenA));

        uint256 expectedStreamCount = poolLogic.calculateStreamCount(userLpUnits, pool.globalSlippage(), reserveD);
        uint expectedConversionPerStream = userLpUnits / expectedStreamCount;
        uint expectedTokenAmountOutPerStream = poolLogic.calculateAssetTransfer(expectedConversionPerStream, reserveA, poolOwnershipUnitsTotal);
        uint userTokenBalanceBefore = tokenA.balanceOf(owner);
        router.removeLiquidity(address(tokenA), userLpUnits);

        (RemoveLiquidityStream[] memory removeLiqStreams, uint front, uint back) = pool.removeLiquidityStreamQueue(address(tokenA));
        RemoveLiquidityStream memory removeLiqStream = removeLiqStreams[front];
        
        
        assertEq(front,back-1); // as stream is not being consumed yet
        assertEq(removeLiqStream.lpAmount,userLpUnits);
        assertEq(removeLiqStream.user,owner);
        assertEq(removeLiqStream.tokenAmountOut,expectedTokenAmountOutPerStream);
        assertEq(removeLiqStream.conversionRemaining,userLpUnits-expectedConversionPerStream);
        assertEq(removeLiqStream.streamCountTotal,expectedStreamCount);
        assertEq(removeLiqStream.streamCountRemaining,expectedStreamCount-1);
        assertEq(removeLiqStream.conversionPerStream,expectedConversionPerStream);
        assertEq(pool.userLpUnitInfo(owner,address(tokenA)),0);

        // checking reserves after

        (
            uint256 reserveDA_After,
            uint256 poolOwnershipUnitsTotal_After,
            uint256 reserveA_After,
            uint256 initialDToMint_After,
            uint256 poolFeeCollected_After,
            bool initialized_After
        ) = pool.poolInfo(address(tokenA));

        assertEq(reserveDA_After,reserveD);
        assertEq(poolOwnershipUnitsTotal_After,poolOwnershipUnitsTotal - expectedConversionPerStream);
        assertEq(reserveA_After,reserveA - expectedTokenAmountOutPerStream);
        assertEq(initialDToMint_After,initialDToMint);
        assertEq(poolFeeCollected_After,poolFeeCollected);
        assertEq(initialized_After,initialized);

        // checking user should not receive tokens
        assertEq(tokenA.balanceOf(owner),userTokenBalanceBefore);


    }

    function test_removeLiqFromGenesisPoolCompleteStream_success() public {

        uint256 tokenAReserve = 100e18;
        uint256 dToMint = 10e18;
        _initGenesisPool(dToMint, tokenAReserve);

        vm.startPrank(owner);

        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        ) = pool.poolInfo(address(tokenA));

        
        uint userLpUnits = pool.userLpUnitInfo(owner,address(tokenA));

        uint256 expectedStreamCount = poolLogic.calculateStreamCount(userLpUnits, pool.globalSlippage(), reserveD);
        uint expectedConversionPerStream = userLpUnits / expectedStreamCount;
        uint expectedTokenAmountOutPerStream = poolLogic.calculateAssetTransfer(expectedConversionPerStream, reserveA, poolOwnershipUnitsTotal);
        (RemoveLiquidityStream[] memory removeLiqStreams, uint front, uint back) = pool.removeLiquidityStreamQueue(address(tokenA));
        uint userTokenBalanceBefore = tokenA.balanceOf(owner);
        router.removeLiquidity(address(tokenA), userLpUnits);

        assertEq(pool.userLpUnitInfo(owner,address(tokenA)),0);

        for(uint i; i < expectedStreamCount; i++) {
            router.processRemoveLiquidity(address(tokenA));
        }

        (RemoveLiquidityStream[] memory removeLiqStreams_After, uint front_After, uint back_After) = pool.removeLiquidityStreamQueue(address(tokenA));
        RemoveLiquidityStream memory removeLiqStream = removeLiqStreams_After[front_After - 1];
        
        
        assertEq(front,back); // as stream is consumed
        assertEq(removeLiqStream.lpAmount,userLpUnits);
        assertEq(removeLiqStream.user,owner);
        assertEq(removeLiqStream.tokenAmountOut,expectedTokenAmountOutPerStream * expectedStreamCount);
        assertEq(removeLiqStream.conversionRemaining,0);
        assertEq(removeLiqStream.streamCountTotal,expectedStreamCount);
        assertEq(removeLiqStream.streamCountRemaining,0);
        assertEq(removeLiqStream.conversionPerStream,expectedConversionPerStream);
        assertEq(pool.userLpUnitInfo(owner,address(tokenA)),0);
        

        // checking reserves after

        (
            uint256 reserveDA_After,
            uint256 poolOwnershipUnitsTotal_After,
            uint256 reserveA_After,
            uint256 initialDToMint_After,
            uint256 poolFeeCollected_After,
            bool initialized_After
        ) = pool.poolInfo(address(tokenA));

        assertEq(reserveDA_After,reserveD);
        assertEq(poolOwnershipUnitsTotal_After,poolOwnershipUnitsTotal - (expectedConversionPerStream * expectedStreamCount));
        assertEq(reserveA_After,reserveA - (expectedTokenAmountOutPerStream * expectedStreamCount));
        assertEq(initialDToMint_After,initialDToMint);
        assertEq(poolFeeCollected_After,poolFeeCollected);
        assertEq(initialized_After,initialized);

        // checking if user received tokens
        assertEq(tokenA.balanceOf(owner),userTokenBalanceBefore + removeLiqStream.tokenAmountOut);
    }

    function test_removeLiqFromPermissionlesspoolSingleStream_success() public {

        uint256 tokenAReserve = 100e18;
        uint256 dToMint = 10e18;
        _initGenesisPool(dToMint, tokenAReserve);

        vm.startPrank(owner);
        uint256 tokenAmount = 100e18;
        uint256 dToTokenAmount = 50e18;

        tokenB.approve(address(router), tokenAmount);
        tokenA.approve(address(router), dToTokenAmount);
        
        router.initPool(address(tokenB), address(tokenA), tokenAmount, dToTokenAmount);

        bytes32 pairId = keccak256(abi.encodePacked(address(tokenB), address(tokenA)));
        (LiquidityStream[] memory streams, uint256 front, uint256 back) = pool.liquidityStreamQueue(pairId);

        for(uint8 i = 0; i<streams[front].poolBStream.streamsRemaining; i++){
            router.processLiqStream(address(tokenB), address(tokenA));
        }

        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        ) = pool.poolInfo(address(tokenB));

        uint userLpUnits_poolB = pool.userLpUnitInfo(owner,address(tokenB));
        uint userTokenBalanceBefore = tokenB.balanceOf(owner);
        uint256 expectedStreamCount = poolLogic.calculateStreamCount(userLpUnits_poolB, pool.globalSlippage(), reserveD);
        uint expectedConversionPerStream = userLpUnits_poolB / expectedStreamCount;
        uint expectedTokenAmountOutPerStream = poolLogic.calculateAssetTransfer(expectedConversionPerStream, reserveA, poolOwnershipUnitsTotal);
        uint dust = userLpUnits_poolB % expectedStreamCount; 
        if(dust != 0 ) {
            userLpUnits_poolB = expectedConversionPerStream * expectedStreamCount;
        }
        router.removeLiquidity(address(tokenB), userLpUnits_poolB);

        (RemoveLiquidityStream[] memory removeLiqStreams, uint removeLiqStreamfront, uint removeLiqStreamback) = pool.removeLiquidityStreamQueue(address(tokenB));
        RemoveLiquidityStream memory removeLiqStream = removeLiqStreams[removeLiqStreamfront];
        
        
        assertEq(removeLiqStreamfront,removeLiqStreamback-1); // as stream is not being consumed yet
        assertEq(removeLiqStream.lpAmount,userLpUnits_poolB);
        assertEq(removeLiqStream.user,owner);
        assertEq(removeLiqStream.tokenAmountOut,expectedTokenAmountOutPerStream);
        assertEq(removeLiqStream.conversionRemaining,userLpUnits_poolB-expectedConversionPerStream);
        assertEq(removeLiqStream.streamCountTotal,expectedStreamCount);
        assertEq(removeLiqStream.streamCountRemaining,expectedStreamCount-1);
        assertEq(removeLiqStream.conversionPerStream,expectedConversionPerStream);
        assertEq(pool.userLpUnitInfo(owner,address(tokenB)),dust);

        // checking reserves after

        (
            uint256 reserveDA_After,
            uint256 poolOwnershipUnitsTotal_After,
            uint256 reserveA_After,
            uint256 initialDToMint_After,
            uint256 poolFeeCollected_After,
            bool initialized_After
        ) = pool.poolInfo(address(tokenB));

        assertEq(reserveDA_After,reserveD);
        assertEq(poolOwnershipUnitsTotal_After,poolOwnershipUnitsTotal - expectedConversionPerStream);
        assertEq(reserveA_After,reserveA - expectedTokenAmountOutPerStream);
        assertEq(initialDToMint_After,initialDToMint);
        assertEq(poolFeeCollected_After,poolFeeCollected);
        assertEq(initialized_After,initialized);

        // checking user should not receive tokens
        assertEq(tokenB.balanceOf(owner),userTokenBalanceBefore);

    }

    function test_removeLiqFromPermissionlesspoolCompleteStream_success() public {

        uint256 tokenAReserve = 100e18;
        uint256 dToMint = 10e18;
        _initGenesisPool(dToMint, tokenAReserve);

        vm.startPrank(owner);
        uint256 tokenAmount = 100e18;
        uint256 dToTokenAmount = 50e18;

        tokenB.approve(address(router), tokenAmount);
        tokenA.approve(address(router), dToTokenAmount);
        
        router.initPool(address(tokenB), address(tokenA), tokenAmount, dToTokenAmount);

        bytes32 pairId = keccak256(abi.encodePacked(address(tokenB), address(tokenA)));
        (LiquidityStream[] memory streams, uint256 front, uint256 back) = pool.liquidityStreamQueue(pairId);

        for(uint8 i = 0; i<streams[front].poolBStream.streamsRemaining; i++){
            router.processLiqStream(address(tokenB), address(tokenA));
        }

        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        ) = pool.poolInfo(address(tokenB));

        uint userLpUnits_poolB = pool.userLpUnitInfo(owner,address(tokenB));
        uint userTokenBalanceBefore = tokenB.balanceOf(owner);
        uint256 expectedStreamCount = poolLogic.calculateStreamCount(userLpUnits_poolB, pool.globalSlippage(), reserveD);
        uint expectedConversionPerStream = userLpUnits_poolB / expectedStreamCount;
        uint dust = userLpUnits_poolB % expectedStreamCount; 
        if(dust != 0 ) {
            userLpUnits_poolB = expectedConversionPerStream * expectedStreamCount;
        }
        router.removeLiquidity(address(tokenB), userLpUnits_poolB);
        assertEq(pool.userLpUnitInfo(owner,address(tokenB)),dust);

        uint expectedTokenAmountAfterStreamExec;
        uint poolOwnershipUnitsTotalCached = poolOwnershipUnitsTotal;
        uint reservesACached = reserveA;
        for(uint i; i < expectedStreamCount; i++) {
            router.processRemoveLiquidity(address(tokenB));
            uint expectedAmountOut = poolLogic.calculateAssetTransfer(expectedConversionPerStream, reservesACached, poolOwnershipUnitsTotalCached);
            expectedTokenAmountAfterStreamExec += expectedAmountOut; 
            poolOwnershipUnitsTotalCached -= expectedConversionPerStream;
            reservesACached -= expectedAmountOut;
        }

        (RemoveLiquidityStream[] memory removeLiqStreams, uint removeLiqStreamfront, uint removeLiqStreamback) = pool.removeLiquidityStreamQueue(address(tokenB));
        RemoveLiquidityStream memory removeLiqStream = removeLiqStreams[removeLiqStreamfront - 1];
        
        
        assertEq(removeLiqStreamfront,removeLiqStreamback); // as stream is consumed
        assertEq(removeLiqStream.lpAmount,userLpUnits_poolB);
        assertEq(removeLiqStream.user,owner);
        assertEq(removeLiqStream.tokenAmountOut,expectedTokenAmountAfterStreamExec);
        assertEq(removeLiqStream.conversionRemaining,0);
        assertEq(removeLiqStream.streamCountTotal,expectedStreamCount);
        assertEq(removeLiqStream.streamCountRemaining,0);
        assertEq(removeLiqStream.conversionPerStream,expectedConversionPerStream);
        assertEq(pool.userLpUnitInfo(owner,address(tokenB)),dust);

        // checking reserves after
{
        (
            uint256 reserveDA_After,
            uint256 poolOwnershipUnitsTotal_After,
            uint256 reserveA_After,
            uint256 initialDToMint_After,
            uint256 poolFeeCollected_After,
            bool initialized_After
        ) = pool.poolInfo(address(tokenB));

        assertEq(reserveDA_After,reserveD);
        assertEq(poolOwnershipUnitsTotal_After,poolOwnershipUnitsTotalCached);
        assertEq(reserveA_After,reservesACached);
        assertEq(initialDToMint_After,initialDToMint);
        assertEq(poolFeeCollected_After,poolFeeCollected);
        assertEq(initialized_After,initialized);
    }

        // checking user should receive tokens as the stream is completed
        assertEq(tokenB.balanceOf(owner),userTokenBalanceBefore +  expectedTokenAmountAfterStreamExec);

    }

    function test_removeLiquidity_invalidPool() public {
        vm.expectRevert(IRouterErrors.InvalidPool.selector);
        router.removeLiquidity(address(tokenA), 1);
    }
    
    function test_removeLiquidity_invalidAmount() public {
        uint256 tokenAReserve = 100e18;
        uint256 dToMint = 10e18;
        _initGenesisPool(dToMint, tokenAReserve);
        vm.startPrank(owner);
        // when 0 value
        vm.expectRevert(IRouterErrors.InvalidAmount.selector);
        router.removeLiquidity(address(tokenA), 0);

        // passing value more than user's lp balance
        uint userLpUnits = pool.userLpUnitInfo(owner, address(tokenA));
        vm.expectRevert(IRouterErrors.InvalidAmount.selector);
        router.removeLiquidity(address(tokenA), userLpUnits + 1); // +1 to make balance more than what user has

        // calling with a user who has no lp units
        address randomUser = address(0x1234);
        vm.startPrank(randomUser);
        vm.expectRevert(IRouterErrors.InvalidAmount.selector);
        router.removeLiquidity(address(tokenA), 1);

    }
    


}