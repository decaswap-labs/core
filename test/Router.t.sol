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

    function test_createPoo_unauthorizedAddress() public {
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

    function test_addLiquidity_invalidToken() public {
        vm.startPrank(owner);

        vm.expectRevert(IRouterErrors.InvalidPool.selector);

        router.addLiquidity(address(tokenB), 1);

        vm.stopPrank();
    }

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

    function test_removeLiquidity_invalidToken() public {
        vm.startPrank(owner);

        vm.expectRevert(IRouterErrors.InvalidPool.selector);

        router.removeLiquidity(address(tokenB), 1);

        vm.stopPrank();
    }

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

    function test_updatePoolAddress_success() public {
        vm.startPrank(owner);

        Pool poolNew = new Pool(address(0), address(router), address(poolLogic));

        router.updatePoolAddress(address(poolNew));

        address poolAddress = router.POOL_ADDRESS();

        assertEq(poolAddress, address(poolNew));
    }

    function test_updatePoolAddress_unauthorizedAddress() public {
        vm.startPrank(nonAuthorized);

        vm.expectRevert(abi.encodeWithSelector(getOwnableUnauthorizedAccountSelector(), nonAuthorized));

        router.updatePoolAddress(address(0x123));
    }

    ---------------------- SWAP ------------------------- //

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

        uint256 pendingExecutionPrice = executionPriceAfterSwap + 1;

        router.swap(address(tokenA), address(tokenB), pendingSwapAmount, pendingExecutionPrice);

        bytes32 pairId = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));

        (Swap[] memory swapsPending, uint256 frontP, uint256 backP) = pool.pairPendingQueue(pairId);
        console.log("Length %s", swapsPending.length);
        console.log("Length %s", frontP); // @todo giving +1 idk why. Need to check this Nabeel
        console.log("Length %s", backP);

        Swap memory swapPending = swapsPending[frontP-1];

        assertGe(swapsPending.length , 1);
        assertEq(swapPending.executionPrice, pendingExecutionPrice);
        assertEq(swapPending.swapAmountRemaining, pendingSwapAmount);
    }

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

        uint256 tokenASwapAmount = 30e18;

        uint256 executionPriceBeforeSwap = poolLogic.getExecutionPrice(tokenAAmount, tokenBAmount);

        router.swap(address(tokenA), address(tokenB), tokenASwapAmount, executionPriceBeforeSwap);

        (uint256 reserveDTokenAAfterSwap,, uint256 reserveATokenAAfterSwap,,,,,) = pool.poolInfo(address(tokenA));

        (uint256 reserveDTokenBAfterSwap,, uint256 reserveATokenBAfterSwap,,,,,) = pool.poolInfo(address(tokenB));

        uint256 executionPriceAfterSwap = poolLogic.getExecutionPrice(reserveATokenAAfterSwap, reserveATokenBAfterSwap);

        uint256 pendingSwapAmount = tokenASwapAmount / 2;

        uint256 pendingExecutionPrice = executionPriceAfterSwap + 1;

        // this should enter in pending, then to stream.
        router.swap(address(tokenA), address(tokenB), pendingSwapAmount, pendingExecutionPrice);

        bytes32 pairId = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));

        (Swap[] memory swapsStreamBefore, uint256 frontB, uint256 backB) = pool.pairStreamQueue(pairId);

        uint256 lengthOfStreamBefore = swapsStreamBefore.length;
        
        router.swap(address(tokenA), address(tokenB), tokenASwapAmount, pendingExecutionPrice/2); //inserting to streamQueue

        // (Swap[] memory swapsStreamAfter, uint256 frontA, uint256 backA) = pool.pairStreamQueue(pairId);
    
        // uint256 lengthOfStreamAfter = swapsStreamAfter.length;

        // assertEq(lengthOfStreamAfter, lengthOfStreamBefore+1);
        // assertEq(swapsStreamAfter[backA].executionPrice , pendingExecutionPrice);

    }

    // function test_streamingSwapTransferToken_success() public {

    // }
}
