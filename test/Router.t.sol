// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Pool.sol";
import "../src/PoolLogic.sol";
import "../src/Router.sol";
import "../src/interfaces/router/IRouterErrors.sol";
import "../src/interfaces/pool/IPoolErrors.sol";
import "../src/MockERC20.sol"; // Mock token for testing
import "./utils/Utils.t.sol";

contract RouterTest is Test, Utils {
    Pool public pool;
    PoolLogic poolLogic;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    Router public router;
    address public owner = address(0xD);
    address public nonAuthorized = address(0xE);

    function setUp() public {
        vm.startPrank(owner);

        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        poolLogic = new PoolLogic(owner, address(0)); // setting zero address for poolAddress as not deployed yet.
        pool = new Pool(address(0), address(router), address(poolLogic));

        // Approve pool contract to spend tokens
        tokenA.approve(address(pool), 1000e18);
        tokenB.approve(address(pool), 1000e18);
        router = new Router(owner, address(pool));

        pool.updateRouterAddress(address(router));
        poolLogic.updatePoolAddress(address(pool)); // Setting poolAddress (kind of initialization)

        vm.stopPrank();
    }

    //------------- CREATE POOL TEST ---------------- //

    // test to create pool success
    function test_createPool_success() public {
        vm.startPrank(owner);

        uint256 tokenAAmount = 1000e18;
        uint256 minLaunchReserveAa = 500e18;
        uint256 minLaunchReserveDd = 50e18;
        uint256 initialDToMintt = 50e18;

        tokenA.approve(address(router), tokenAAmount);

        uint256 balanceBefore = tokenA.balanceOf(owner);

        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 minLaunchReserveA,
            uint256 minLaunchReserveD,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        ) = pool.poolInfo(address(tokenA));

        uint256 userLpUnits = pool.userLpUnitInfo(owner, address(tokenA));

        uint256 balanceAfter = tokenA.balanceOf(owner);

        assertEq(reserveA, tokenAAmount);
        assertEq(reserveD, initialDToMintt);
        assertEq(minLaunchReserveA, minLaunchReserveAa);
        assertEq(minLaunchReserveD, minLaunchReserveDd);
        assertEq(balanceAfter, balanceBefore - tokenAAmount);
        assertEq(userLpUnits, poolOwnershipUnitsTotal);

        vm.stopPrank();
    }  

    // test to check crte pool method fails if pool already exists
    function test_createPool_poolAlreadyExists() public {
        vm.startPrank(owner);

        uint256 tokenAAmount = 1000e18;
        uint256 minLaunchReserveAa = 500e18;
        uint256 minLaunchReserveDd = 50e18;
        uint256 initialDToMintt = 50e18;

        tokenA.approve(address(router), tokenAAmount);
        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

        vm.expectRevert(IPoolErrors.DuplicatePool.selector);
        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

        vm.stopPrank();
    }

    // test to check crte pool method fails if access from invalid addrs
    function test_createPool_unauthorizedAddress() public {
        vm.startPrank(nonAuthorized);

        uint256 tokenAAmount = 1000e18;
        uint256 minLaunchReserveAa = 500e18;
        uint256 minLaunchReserveDd = 50e18;
        uint256 initialDToMintt = 50e18;

        tokenA.approve(address(router), tokenAAmount);

        uint256 balanceBefore = tokenA.balanceOf(owner);

        vm.expectRevert(abi.encodeWithSelector(getOwnableUnauthorizedAccountSelector(), nonAuthorized));

        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

        vm.stopPrank();
    }

    // ------------ ADD LIQUIDITY TEST --------------- //

    // test to add ldty success
    function test_addLiquidity_success() public {
        vm.startPrank(owner);

        uint256 tokenAAmount = 1000e18;
        uint256 minLaunchReserveAa = 500e18;
        uint256 minLaunchReserveDd = 50e18;
        uint256 initialDToMintt = 50e18;

        tokenA.approve(address(router), tokenAAmount);
        uint256 balanceBefore = tokenA.balanceOf(owner);
        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

        (
            uint256 reserveDBefore,
            uint256 poolOwnershipUnitsTotalBefore,
            uint256 reserveABefore,
            uint256 minLaunchReserveABefore,
            uint256 minLaunchReserveDBefore,
            uint256 initialDToMintBefore,
            uint256 poolFeeCollectedBefore,
            bool initializedB
        ) = pool.poolInfo(address(tokenA));

        uint256 amountALiquidity = 1000e18;

        uint256 lpUnitsToMint =
            poolLogic.calculateLpUnitsToMint(amountALiquidity, reserveABefore, poolOwnershipUnitsTotalBefore);
        uint256 dUnitsToMint =
            poolLogic.calculateDUnitsToMint(amountALiquidity, reserveABefore + amountALiquidity, reserveDBefore, 0);
        uint256 userLpUnitsBefore = pool.userLpUnitInfo(owner, address(tokenA));

        tokenA.approve(address(router), amountALiquidity);

        router.addLiquidity(address(tokenA), amountALiquidity);

        (
            uint256 reserveDAfter,
            uint256 poolOwnershipUnitsTotalAfter,
            uint256 reserveAAfter,
            uint256 minLaunchReserveAAfter, //unchanged
            uint256 minLaunchReserveDAfter, //unchanged
            uint256 initialDToMintAfter, //unchanged
            uint256 poolFeeCollectedAfter, //unchanged
            bool initializedA
        ) = pool.poolInfo(address(tokenA));

        uint256 userLpUnitsAfter = pool.userLpUnitInfo(owner, address(tokenA));

        assertEq(reserveAAfter, reserveABefore + amountALiquidity);
        assertEq(reserveDAfter, reserveDBefore + dUnitsToMint);
        assertEq(poolOwnershipUnitsTotalAfter, poolOwnershipUnitsTotalBefore + lpUnitsToMint);
        assertEq(userLpUnitsAfter, userLpUnitsBefore + lpUnitsToMint);
    }

    // test to check add ldty method fails given invalid tkn
    function test_addLiquidity_invalidToken() public {
        vm.startPrank(owner);

        vm.expectRevert(IRouterErrors.InvalidPool.selector);

        router.addLiquidity(address(tokenB), 1);

        vm.stopPrank();
    }

    // test to check add ldty method fails given invalid amnt
    function test_addLiquidity_invalidAmount() public {
        vm.startPrank(owner);

        uint256 tokenAAmount = 1000e18;
        uint256 minLaunchReserveAa = 500e18;
        uint256 minLaunchReserveDd = 50e18;
        uint256 initialDToMintt = 50e18;

        tokenA.approve(address(router), tokenAAmount);
        uint256 balanceBefore = tokenA.balanceOf(owner);
        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

        vm.expectRevert(IRouterErrors.InvalidAmount.selector);

        uint256 amountALiquidity = 0;

        router.addLiquidity(address(tokenA), amountALiquidity);

        vm.stopPrank();
    }

    // ------------ REMOVE LIQUIDITY TEST ------------- //

    // test to remove lqdty successfuly
    function test_removeLiquidity_success() public {
        vm.startPrank(owner);

        uint256 tokenAAmount = 1000e18;
        uint256 minLaunchReserveAa = 500e18;
        uint256 minLaunchReserveDd = 50e18;
        uint256 initialDToMintt = 50e18;

        tokenA.approve(address(router), tokenAAmount);
        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

        uint256 balanceBefore = tokenA.balanceOf(owner);

        (
            uint256 reserveDBefore,
            uint256 poolOwnershipUnitsTotalBefore,
            uint256 reserveABefore,
            uint256 minLaunchReserveABefore,
            uint256 minLaunchReserveDBefore,
            uint256 initialDToMintBefore,
            uint256 poolFeeCollectedBefore,
            bool initializedB
        ) = pool.poolInfo(address(tokenA));

        uint256 userLpAmount = pool.userLpUnitInfo(owner, address(tokenA));

        uint256 assetToTransfer =
            poolLogic.calculateAssetTransfer(userLpAmount, reserveABefore, poolOwnershipUnitsTotalBefore);
        uint256 dToDeduct = poolLogic.calculateDToDeduct(userLpAmount, reserveDBefore, poolOwnershipUnitsTotalBefore);

        router.removeLiquidity(address(tokenA), userLpAmount);

        (
            uint256 reserveDAfter,
            uint256 poolOwnershipUnitsTotalAfter,
            uint256 reserveAAfter,
            uint256 minLaunchReserveAAfter, //unchanged
            uint256 minLaunchReserveDAfter, //uncahnged
            uint256 initialDToMintAfter, //unchanged
            uint256 poolFeeCollectedAfter, //unchanged
            bool initializedd //unchanged
        ) = pool.poolInfo(address(tokenA));

        uint256 userLpUnitsAfter = pool.userLpUnitInfo(address(tokenA), owner);
        uint256 balanceAfter = tokenA.balanceOf(owner);

        assertEq(balanceAfter, balanceBefore + assetToTransfer);
        assertEq(reserveDAfter, reserveDBefore - dToDeduct);
        assertEq(reserveAAfter, reserveABefore - assetToTransfer);
        assertEq(poolOwnershipUnitsTotalAfter, poolOwnershipUnitsTotalBefore - userLpAmount);
    }

    // test to check rmv lqty fails given invalid tkn
    function test_removeLiquidity_invalidToken() public {
        vm.startPrank(owner);

        vm.expectRevert(IRouterErrors.InvalidPool.selector);

        router.removeLiquidity(address(tokenB), 1);

        vm.stopPrank();
    }

    // test to check rmv lqty fails given invalid amnt
    function test_removeLiquidity_invalidAmount() public {
        vm.startPrank(owner);

        uint256 tokenAAmount = 1000e18;
        uint256 minLaunchReserveAa = 500e18;
        uint256 minLaunchReserveDd = 50e18;
        uint256 initialDToMintt = 50e18;

        tokenA.approve(address(router), tokenAAmount);

        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

        vm.expectRevert(IRouterErrors.InvalidAmount.selector);

        uint256 lpUnits = 0;

        router.removeLiquidity(address(tokenA), lpUnits);

        vm.stopPrank();
    }

    // ------------ UPDATE POOL ADDRESS --------------- //
    
    // test to update pool address
    function test_updatePoolAddress_success() public {
        vm.startPrank(owner);

        Pool poolNew = new Pool(address(0), address(router), address(poolLogic));

        router.updatePoolAddress(address(poolNew));

        address poolAddress = router.POOL_ADDRESS();

        assertEq(poolAddress, address(poolNew));
    }

    // test to check method fails of updating address by invalid address
    function test_updatePoolAddress_unauthorizedAddress() public {
        vm.startPrank(nonAuthorized);

        vm.expectRevert(abi.encodeWithSelector(getOwnableUnauthorizedAccountSelector(), nonAuthorized));

        router.updatePoolAddress(address(0x123));
    }

    // ---------------------- SWAP ------------------------- //

    // test to add swap to stream queue, and execute 1 stream of it
    function test_streamingSwap_success() public {
        /*
            1. Create pool with tokens (100 TKNA)
            2. Create second pool with tokens (100 TKNB)
            3. Set pair slippage to 10
            3. Now we have to swap 20 TKNA to TKNB
            4. Calculate streams before hand
            5. Calculate execution price before hand
            6. Caluclate execution price which will be after executing a swap ---> Need to find this
            6. Calculate swap per stream before hand
            7. Calculate swapAmountOut of only 1 stream before hand
            8. Make swap object
            9. Enter swap object
            10. Assert swapAmountIn to the amountIn-swapPerStream
            11. Assert execution price and stream count (should be  = streamCount - 1)
            12. Assert amountOut of swap, should be equal to swapAmountOut calculated before
            13. Assert new execution price
            14. Assert PoolA reserveA, reserveD
            15. Assert PoolB reserveA, reserveD
        */

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

        uint256 tokenASwapAmount = 30e18;

        uint256 streamsBeforeSwap = poolLogic.calculateStreamCount(tokenASwapAmount, SLIPPAGE, initialDToMintPoolB); //passed poolB D because its less.

        uint256 swapPerStreamLocal = tokenASwapAmount / streamsBeforeSwap;

        uint256 executionPriceBeforeSwap = poolLogic.getExecutionPrice(tokenAAmount, tokenBAmount);

        (uint256 dOutA, uint256 swapAmountOutBeforeSwap) = poolLogic.getSwapAmountOut(
            swapPerStreamLocal, tokenAAmount, tokenBAmount, initialDToMintPoolA, initialDToMintPoolB
        );

        console.log("%s Streams ====>", streamsBeforeSwap);
        console.log("%s Swap Per Stream ====>", swapPerStreamLocal);
        console.log("%s Exec Price ====>", executionPriceBeforeSwap);
        console.log("%s Amount Out ====>", swapAmountOutBeforeSwap);

        router.swap(address(tokenA), address(tokenB), tokenASwapAmount, executionPriceBeforeSwap);

        // get swap from queue
        bytes32 pairId = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));
        (Swap[] memory swaps, uint256 front, uint256 back) = pool.pairStreamQueue(pairId);
        Swap memory swap = swaps[front];

        assertEq(swap.swapAmountRemaining, tokenASwapAmount - swapPerStreamLocal);
        assertEq(swap.streamsRemaining, streamsBeforeSwap - 1);
        assertEq(swap.executionPrice, executionPriceBeforeSwap);

        (uint256 reserveDTokenAAfterSwap,, uint256 reserveATokenAAfterSwap,,,,,) = pool.poolInfo(address(tokenA));

        (uint256 reserveDTokenBAfterSwap,, uint256 reserveATokenBAfterSwap,,,,,) = pool.poolInfo(address(tokenB));

        assertEq(reserveATokenAAfterSwap, tokenAAmount + swapPerStreamLocal);
        assertEq(reserveDTokenAAfterSwap, initialDToMintPoolA - dOutA);
        assertEq(reserveATokenBAfterSwap, tokenBAmount - swapAmountOutBeforeSwap);
        assertEq(reserveDTokenBAfterSwap, initialDToMintPoolB + dOutA);

        uint256 executionPriceAfterSwap = poolLogic.getExecutionPrice(reserveATokenAAfterSwap, reserveATokenBAfterSwap);
        console.log("%s Exec Price ====>", executionPriceAfterSwap);
    }

    // test to check the method fails if invalid pool is given
    function test_swap_invalidToken() public {
        vm.startPrank(owner);

        uint256 initialDToMintPoolA = 50e18;

        uint256 tokenAAmount = 100e18;
        uint256 minLaunchReserveAPoolA = 25e18;
        uint256 minLaunchReserveDPoolA = 25e18;

        router.createPool(
            address(tokenA), tokenAAmount, minLaunchReserveAPoolA, minLaunchReserveDPoolA, initialDToMintPoolA
        );
        vm.expectRevert(IRouterErrors.InvalidPool.selector);
        router.swap(address(tokenA), address(0x0), 1, 1);
    }

    // test to check the method fails if invalid amount given
    function test_swap_invalidAmount() public {
        vm.startPrank(owner);

        uint256 initialDToMintPoolA = 50e18;

        uint256 tokenAAmount = 100e18;
        uint256 minLaunchReserveAPoolA = 25e18;
        uint256 minLaunchReserveDPoolA = 25e18;

        router.createPool(
            address(tokenA), tokenAAmount, minLaunchReserveAPoolA, minLaunchReserveDPoolA, initialDToMintPoolA
        );
        vm.expectRevert(IRouterErrors.InvalidAmount.selector);
        router.swap(address(tokenA), address(0x0), 0, 1);
    }
    
    // test to check the method fails if invalid exec price given
    function test_swap_invalidExecPrice() public {
        vm.startPrank(owner);

        uint256 initialDToMintPoolA = 50e18;

        uint256 tokenAAmount = 100e18;
        uint256 minLaunchReserveAPoolA = 25e18;
        uint256 minLaunchReserveDPoolA = 25e18;

        router.createPool(
            address(tokenA), tokenAAmount, minLaunchReserveAPoolA, minLaunchReserveDPoolA, initialDToMintPoolA
        );
        vm.expectRevert(IRouterErrors.InvalidExecutionPrice.selector);
        router.swap(address(tokenA), address(0x0), 1, 0);
    }

    // test to add pending swap in pending queue
    function test_streamingSwapAddPending_success() public {
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

        uint256 tokenASwapAmount = 30e18;

        uint256 executionPriceBeforeSwap = poolLogic.getExecutionPrice(tokenAAmount, tokenBAmount);

        router.swap(address(tokenA), address(tokenB), tokenASwapAmount, executionPriceBeforeSwap);

        (uint256 reserveDTokenAAfterSwap,, uint256 reserveATokenAAfterSwap,,,,,) = pool.poolInfo(address(tokenA));

        (uint256 reserveDTokenBAfterSwap,, uint256 reserveATokenBAfterSwap,,,,,) = pool.poolInfo(address(tokenB));

        uint256 executionPriceAfterSwap = poolLogic.getExecutionPrice(reserveATokenAAfterSwap, reserveATokenBAfterSwap);

        uint256 pendingSwapAmount = tokenASwapAmount / 2;

        uint256 pendingExecutionPrice = executionPriceAfterSwap*2;

        router.swap(address(tokenA), address(tokenB), pendingSwapAmount, pendingExecutionPrice);

        bytes32 pairId = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));

        (Swap[] memory swapsPending, uint256 frontP, uint256 backP) = pool.pairPendingQueue(pairId);
        console.log("Length %s", swapsPending.length);
        console.log("Length %s", frontP);
        console.log("Length %s", backP);

        Swap memory swapPending = swapsPending[frontP];

        assertGe(swapsPending.length, 1);
        assertEq(swapPending.executionPrice, pendingExecutionPrice);
        assertEq(swapPending.swapAmountRemaining, pendingSwapAmount);
    }

    // test to add swap to pending queue, then stream the queue so that pending adds back to stream queue
    function test_streamingSwapAddPendingToStream_success() public {
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

        uint256 tokenASwapAmount = 80e18;

        uint256 executionPriceBeforeSwap = poolLogic.getExecutionPrice(tokenAAmount, tokenBAmount);

        router.swap(address(tokenA), address(tokenB), tokenASwapAmount, executionPriceBeforeSwap);

        (uint256 reserveDTokenAAfterSwap,, uint256 reserveATokenAAfterSwap,,,,,) = pool.poolInfo(address(tokenA));

        (uint256 reserveDTokenBAfterSwap,, uint256 reserveATokenBAfterSwap,,,,,) = pool.poolInfo(address(tokenB));

        uint256 executionPriceAfterSwap = poolLogic.getExecutionPrice(reserveATokenAAfterSwap, reserveATokenBAfterSwap);

        uint256 pendingSwapAmount = tokenASwapAmount / 2;

        uint256 pendingExecutionPrice = executionPriceAfterSwap + 1;

        bytes32 pairId = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));

        (Swap[] memory swapsStreamBefore, uint256 frontB, uint256 backB) = pool.pairStreamQueue(pairId);

        uint256 lengthOfStreamBefore = swapsStreamBefore.length;

        // this should enter in pending, then to stream.
        router.swap(address(tokenA), address(tokenB), pendingSwapAmount, pendingExecutionPrice);

        (Swap[] memory swapsStreamAfter, uint256 frontA, uint256 backA) = pool.pairStreamQueue(pairId);

        uint256 lengthOfStreamAfter = swapsStreamAfter.length;

        assertEq(lengthOfStreamAfter, lengthOfStreamBefore+1);
        assertEq(swapsStreamAfter[backA-1].executionPrice , pendingExecutionPrice);
    }

    // test to check the execution of whole swap and test token transfer
    function test_streamingSwapTransferToken_success() public {
        vm.startPrank(owner);

        uint256 initialDToMintPoolA = 50e18;
        uint256 initialDToMintPoolB = 50e18;
        uint256 SLIPPAGE = 10;

        uint256 tokenAAmount = 100e18;
        uint256 minLaunchReserveAPoolA = 25e18;
        uint256 minLaunchReserveDPoolA = 25e18;

        uint256 tokenBAmount = 100e18;
        uint256 minLaunchReserveAPoolB = 25e18;
        uint256 minLaunchReserveDPoolB = 25e18; // we can change this for error test

        router.createPool(
            address(tokenA), tokenAAmount, minLaunchReserveAPoolA, minLaunchReserveDPoolA, initialDToMintPoolA
        );

        router.createPool(
            address(tokenB), tokenBAmount, minLaunchReserveAPoolB, minLaunchReserveDPoolB, initialDToMintPoolB
        );

        // update pair slippage
        pool.updatePairSlippage(address(tokenA), address(tokenB), SLIPPAGE);

        uint256 tokenASwapAmount = 30e18;

        uint256 streamsBeforeSwap = poolLogic.calculateStreamCount(tokenASwapAmount, SLIPPAGE, initialDToMintPoolB); //passed poolB D because its less.

        uint256 swapPerStreamLocal = tokenASwapAmount / streamsBeforeSwap;

        uint256 executionPriceBeforeSwap = poolLogic.getExecutionPrice(tokenAAmount, tokenBAmount);

        (uint256 dOutA, uint256 swapAmountOutBeforeSwap) = poolLogic.getSwapAmountOut(
            swapPerStreamLocal, tokenAAmount, tokenBAmount, initialDToMintPoolA, initialDToMintPoolB
        );

        uint256 userBalanceABefore = tokenA.balanceOf(owner);
        uint256 userBalanceBBefore = tokenB.balanceOf(owner);

        router.swap(address(tokenA), address(tokenB), tokenASwapAmount, executionPriceBeforeSwap);

        uint256 userBalanceAAfter = tokenA.balanceOf(owner);
        uint256 userBalanceBAfter = tokenB.balanceOf(owner);

        // get swap from queue
        bytes32 pairId = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));

        (Swap[] memory swaps, uint256 front, uint256 back) = pool.pairStreamQueue(pairId);

        console.log("%s balance a before ====>", userBalanceABefore);
        console.log("%s balance a after ====>", userBalanceAAfter);
        console.log("%s transfer amount a ====>", tokenASwapAmount);
        console.log("%s balance b before ====>", userBalanceBBefore);
        console.log("%s balance b after ====>", userBalanceBAfter);

        assertEq(front,back);

        assertEq(swaps[front-1].completed , true);

        assertEq(userBalanceAAfter, userBalanceABefore - tokenASwapAmount);

        assertEq(userBalanceBAfter, userBalanceABefore + swapAmountOutBeforeSwap);
    }

    // test to enter opp direction swap and also execute it in the same stream
    function test_oppositeDirectionSwapExecution_success() public {
        /* 
            1. Create pool with tokens (100 TKNA)
            2. Create second pool with tokens (100 TKNB)
            3. Set pair slippage to 10
            4. Now we have to swap 30 TKNA to TKNB in a manner that is should have 3 streams
            5. Now we have to swap  10 TKNB to TKNA in a manner that it should be consumed by first swap
            4. Calculate streams of both swaps before hand
            6. Calculate swap per stream before hand
            7. Calculate swapAmountOut of only 1 stream of swap1 and whole swap2
            8. Make swap object x2
            9. Enter swap object x2
            10 Calculate balance1 of swap2 before
            11. Assert execution price and streamRemaining of swap2 == 0
            12. Assert amountOut of swap1 to swapAmountOut1
            13. calculate of balance1 of swap2 after and assert balance1After = balance1Before + swapAmountOut2
            14. Assert PoolA reserveA, reserveD
            15. Assert PoolB reserveA, reserveD
        */

        vm.startPrank(owner);

        uint256 initialDToMintPoolA = 10e18;
        uint256 initialDToMintPoolB = 10e18;
        uint256 SLIPPAGE = 10;

        uint256 tokenAAmount = 100e18;
        uint256 minLaunchReserveAPoolA = 5e18;
        uint256 minLaunchReserveDPoolA = 5e18;

        uint256 tokenBAmount = 100e18;
        uint256 minLaunchReserveAPoolB = 5e18;
        uint256 minLaunchReserveDPoolB = 5e18; // we can change this for error test

        bytes32 pairIdAtoB = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));
        bytes32 pairIdBtoA = keccak256(abi.encodePacked(address(tokenB), address(tokenA)));

        router.createPool(
            address(tokenA), tokenAAmount, minLaunchReserveAPoolA, minLaunchReserveDPoolA, initialDToMintPoolA
        );

        router.createPool(
            address(tokenB), tokenBAmount, minLaunchReserveAPoolB, minLaunchReserveDPoolB, initialDToMintPoolB
        );

        address user1 = address(0xFff);
        address user2 = address(0xddd);

        uint256 user1TokenABalanceBefore = 100e18;
        uint256 user2TokenBBalanceBefore = 100e18;

        tokenA.transfer(user1, user1TokenABalanceBefore);
        tokenB.transfer(user2, user2TokenBBalanceBefore);

        //---------------------------------------------------------------------------------------------//

        // update pair slippage
        pool.updatePairSlippage(address(tokenA), address(tokenB), SLIPPAGE);

        uint256 tokenASwapAmount = 40e18; //4 streams
        uint256 tokenBSwapAmount = 15e18; //1 stream

        vm.stopPrank();
        // sending 1 as exec price as we want them to stream not go to pending

        vm.startPrank(user1);
        router.swap(address(tokenA), address(tokenB), tokenASwapAmount, 1);
        vm.stopPrank();

        (uint256 reserveDA,, uint256 reserveAA,,,,,) = pool.poolInfo(address(tokenA));

        (uint256 reserveDB,, uint256 reserveAB,,,,,) = pool.poolInfo(address(tokenB));

        uint256 dToPass = reserveDA <= reserveDB ? reserveDA : reserveDB;

        uint256 streamsBeforeSwapBtoA = poolLogic.calculateStreamCount(tokenBSwapAmount, SLIPPAGE, dToPass); //passed poolB D because its less.

        (Swap[] memory swapsAtoB, uint256 frontAtoB, uint256 backAtoB) = pool.pairStreamQueue(pairIdAtoB);

        uint256 streamsBeforeSwapAtoB = swapsAtoB[frontAtoB].streamsRemaining;

        console.log("B -> A %s", streamsBeforeSwapBtoA); // 1
        console.log("A -> B %s", streamsBeforeSwapAtoB); // 3
        console.log("A -> B %s", swapsAtoB[frontAtoB].swapAmountRemaining);

        uint256 swapBtoAPerStreamLocal = tokenBSwapAmount / streamsBeforeSwapBtoA;

        (, uint256 swapAmountOutBtoABeforeSwap) =
            poolLogic.getSwapAmountOut(swapBtoAPerStreamLocal, reserveAB, reserveAA, reserveDB, reserveDA);

        vm.startPrank(user2);
        router.swap(address(tokenB), address(tokenA), tokenBSwapAmount, 1);
        vm.stopPrank();

        vm.startPrank(owner);

        uint256 user2TokenABalanceAfter = tokenA.balanceOf(user2);
        uint256 user2TokenBBalanceAfter = tokenB.balanceOf(user2);

        // // get swap from queue
        (Swap[] memory swapsAtoBAfterSwap, uint256 frontAtoBa, uint256 backAtoBa) = pool.pairStreamQueue(pairIdAtoB);
        Swap memory swapAtoB = swapsAtoBAfterSwap[frontAtoBa-1]; // @todo, array out of bound error. You are increamenting the swapQueue of AtoB instead of BtoA

        (uint256 reserveDAa,, uint256 reserveAAa,,,,,) = pool.poolInfo(address(tokenA));

        (uint256 reserveDBb,, uint256 reserveABb,,,,,) = pool.poolInfo(address(tokenB));

        uint256 dToPassAgain = reserveDAa <= reserveDBb ? reserveDAa : reserveDBb;

        uint256 streamsAfterExecuteOfSwap1 = poolLogic.calculateStreamCount(swapAtoB.swapAmountRemaining, SLIPPAGE, dToPassAgain);

        assertEq(swapAtoB.streamsRemaining, streamsAfterExecuteOfSwap1-1); // @todo, swapAtoB returning stream == 0. Whereas in terms of formula it's 1

        (Swap[] memory swapsBtoA, uint256 frontBtoA, uint256 backBtoA) = pool.pairStreamQueue(pairIdBtoA);
        assertEq(frontBtoA, backBtoA-1); // @todo, front not increamenting. 
        // assertEq(swapsBtoA[frontBtoA].completed, true);

        console.log("AMMMOUNTTT %s",swapsBtoA[frontBtoA].swapAmountRemaining); // should return 0.

        // assertEq(user2TokenABalanceAfter, swapAmountOutBtoABeforeSwap); 
        // assertEq(user2TokenBBalanceAfter, user2TokenBBalanceBefore - swapBtoAPerStreamLocal); 

        //@todo: you are updating the swap which is consuming the other one, instead of updating the swap which is consumed.
    }
}
