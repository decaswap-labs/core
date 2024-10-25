// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RouterTest} from "./Router.t.sol";
import {IRouterErrors} from "src/interfaces/router/IRouterErrors.sol";
import {Swap} from "src/lib/SwapQueue.sol";
import {console} from "forge-std/console.sol";

contract RouterTest_Swap is RouterTest {
    address private tokenC = makeAddr("tokenC");
    uint256 private constant TOKEN_A_SWAP_AMOUNT = 30 ether;
    bytes32 pairId;
    bytes32 oppositePairId;

    function setUp() public virtual override {
        super.setUp();
        pairId = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));
        oppositePairId = keccak256(abi.encodePacked(address(tokenB), address(tokenA)));
    }

    function testRevert_router_swap_whenAmountInIsZero() public {
        vm.prank(owner);
        vm.expectRevert(IRouterErrors.InvalidAmount.selector);
        router.swap(address(tokenA), address(tokenB), 0, 1 ether);
    }

    function testRevert_router_swap_whenExecutionPriceIsZero() public {
        vm.prank(owner);
        vm.expectRevert(IRouterErrors.InvalidExecutionPrice.selector);
        router.swap(address(tokenA), address(tokenB), 1 ether, 0);
    }

    function testRevert_router_swap_whenInvalidPool() public {
        vm.prank(owner);
        vm.expectRevert(IRouterErrors.InvalidPool.selector);
        router.swap(address(tokenA), address(tokenC), 1 ether, 1 ether);
    }

    function test_router_swap_addToPendingQueue() public {
        (uint256 reserveD_tokenA_beforeSwap,, uint256 reserveA_tokenA_beforeSwap,,,,,) = pool.poolInfo(address(tokenA));

        (uint256 reserveD_tokenB_beforeSwap,, uint256 reserveA_tokenB_beforeSwap,,,,,) = pool.poolInfo(address(tokenB));

        uint256 executionPriceBeforeSwap =
            poolLogic.getExecutionPrice(reserveA_tokenA_beforeSwap, reserveA_tokenB_beforeSwap);

        // to add the swap in the pending stream we need to have a swap price execution higher than the current price

        uint256 swapExecutionPrice = executionPriceBeforeSwap + 1;

        uint256 minPoolDepth = reserveD_tokenA_beforeSwap <= reserveD_tokenB_beforeSwap
            ? reserveD_tokenA_beforeSwap
            : reserveD_tokenB_beforeSwap;
        bytes32 poolId = poolLogic.getPoolId(address(tokenA), address(tokenB)); // for pair slippage only. Not an ID for pair direction queue
        uint256 streamCount =
            poolLogic.calculateStreamCount(TOKEN_A_SWAP_AMOUNT, pool.pairSlippage(poolId), minPoolDepth);
        uint256 swapPerStream = TOKEN_A_SWAP_AMOUNT / streamCount;

        uint256 swapperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_beforeSwap = tokenA.balanceOf(address(pool));

        vm.startPrank(owner);
        tokenA.approve(address(router), TOKEN_A_SWAP_AMOUNT);
        router.swap(address(tokenA), address(tokenB), TOKEN_A_SWAP_AMOUNT, swapExecutionPrice);
        vm.stopPrank();

        uint256 swapperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_afterSwap = tokenA.balanceOf(address(pool));

        (,, uint256 reserveA_tokenA_afterSwap,,,,,) = pool.poolInfo(address(tokenA));
        (,, uint256 reserveA_tokenB_afterSwap,,,,,) = pool.poolInfo(address(tokenB));

        uint256 executionPriceAfterSwap =
            poolLogic.getExecutionPrice(reserveA_tokenA_afterSwap, reserveA_tokenB_afterSwap);
        (Swap[] memory swaps_pending, uint256 front,) = pool.pairPendingQueue(pairId);
        Swap memory swap = swaps_pending[front];
        assertEq(reserveA_tokenA_beforeSwap, reserveA_tokenA_afterSwap);
        assertEq(reserveA_tokenB_beforeSwap, reserveA_tokenB_afterSwap);
        assertEq(executionPriceBeforeSwap, executionPriceAfterSwap);
        assertEq(swapperTokenABalance_afterSwap, swapperTokenABalance_beforeSwap - TOKEN_A_SWAP_AMOUNT);
        assertEq(poolTokenABalance_afterSwap, poolTokenABalance_beforeSwap + TOKEN_A_SWAP_AMOUNT);

        // check the swap
        assertEq(swap.swapAmount, TOKEN_A_SWAP_AMOUNT);
        assertEq(swap.swapAmountRemaining, TOKEN_A_SWAP_AMOUNT);
        assertEq(swap.streamsCount, streamCount);
        assertEq(swap.streamsRemaining, streamCount);
        assertEq(swap.swapPerStream, swapPerStream);
        assertEq(swap.executionPrice, swapExecutionPrice);
        assertEq(swap.amountOut, 0);
        assertEq(swap.user, owner);
        assertEq(swap.tokenIn, address(tokenA));
        assertEq(swap.tokenOut, address(tokenB));
        assertEq(swap.completed, false);
    }

    /**
     * @notice This test will add a swap to the streaming queue and partially execute it
     * because the streamCount will be above 1, the swap won't be totally executed but only partially
     */
    function test_router_swap_addToStreamingQueueAndPartiallyExecuteSwap() public {
        (uint256 reserveD_tokenA_beforeSwap,, uint256 reserveA_tokenA_beforeSwap,,,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_beforeSwap,, uint256 reserveA_tokenB_beforeSwap,,,,,) = pool.poolInfo(address(tokenB));

        uint256 executionPriceBeforeSwap =
            poolLogic.getExecutionPrice(reserveA_tokenA_beforeSwap, reserveA_tokenB_beforeSwap);

        // to add the swap in the straming queue we need to have a swap price execution lower or equal to the current price
        uint256 swapExecutionPrice = executionPriceBeforeSwap;

        uint256 minPoolDepth = reserveD_tokenA_beforeSwap <= reserveD_tokenB_beforeSwap
            ? reserveD_tokenA_beforeSwap
            : reserveD_tokenB_beforeSwap;
        bytes32 poolId = poolLogic.getPoolId(address(tokenA), address(tokenB)); // for pair slippage only. Not an ID for pair direction queue
        uint256 streamCount =
            poolLogic.calculateStreamCount(TOKEN_A_SWAP_AMOUNT, pool.pairSlippage(poolId), minPoolDepth);
        uint256 swapPerStream = TOKEN_A_SWAP_AMOUNT / streamCount;

        uint256 swapperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_beforeSwap = tokenA.balanceOf(address(pool));
        (uint256 dToUpdate, uint256 tokenBAmountOut) = poolLogic.getSwapAmountOut(
            swapPerStream,
            reserveA_tokenA_beforeSwap,
            reserveA_tokenB_beforeSwap,
            reserveD_tokenA_beforeSwap,
            reserveD_tokenB_beforeSwap
        );

        vm.startPrank(owner);
        tokenA.approve(address(router), TOKEN_A_SWAP_AMOUNT);
        router.swap(address(tokenA), address(tokenB), TOKEN_A_SWAP_AMOUNT, swapExecutionPrice);
        vm.stopPrank();

        uint256 swapperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_afterSwap = tokenA.balanceOf(address(pool));

        (uint256 reserveD_tokenA_afterSwap,, uint256 reserveA_tokenA_afterSwap,,,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_afterSwap,, uint256 reserveA_tokenB_afterSwap,,,,,) = pool.poolInfo(address(tokenB));

        uint256 executionPriceAfterSwap =
            poolLogic.getExecutionPrice(reserveA_tokenA_afterSwap, reserveA_tokenB_afterSwap);
        (Swap[] memory swaps_streaming, uint256 front,) = pool.pairStreamQueue(pairId);
        Swap memory swap = swaps_streaming[front];
        assertEq(reserveA_tokenA_beforeSwap, reserveA_tokenA_afterSwap - swapPerStream);
        assertEq(reserveA_tokenB_beforeSwap, reserveA_tokenB_afterSwap + tokenBAmountOut);
        assertEq(reserveD_tokenA_afterSwap, reserveD_tokenA_beforeSwap - dToUpdate);
        assertEq(reserveD_tokenB_afterSwap, reserveD_tokenB_beforeSwap + dToUpdate);
        assertGt(executionPriceAfterSwap, executionPriceBeforeSwap);
        assertEq(swapperTokenABalance_afterSwap, swapperTokenABalance_beforeSwap - TOKEN_A_SWAP_AMOUNT);
        assertEq(poolTokenABalance_afterSwap, poolTokenABalance_beforeSwap + TOKEN_A_SWAP_AMOUNT);

        // check the swap
        assertEq(swap.swapAmount, TOKEN_A_SWAP_AMOUNT);
        assertEq(swap.swapAmountRemaining, TOKEN_A_SWAP_AMOUNT - swapPerStream);
        assertEq(swap.streamsCount, streamCount);
        assertEq(swap.streamsRemaining, streamCount - 1);
        assertEq(swap.swapPerStream, swapPerStream);
        assertEq(swap.executionPrice, swapExecutionPrice);
        assertEq(swap.amountOut, tokenBAmountOut);
        assertEq(swap.user, owner);
        assertEq(swap.tokenIn, address(tokenA));
        assertEq(swap.tokenOut, address(tokenB));
        assertEq(swap.completed, false);
    }

    /**
     * @notice This test will add a swap to the streaming queue and fully execute it by consuming opposite swaps
     */
    function test_router_swap_fullyExecuteSwapWithOppositeSwaps() public {
        uint256 oppositeSwapsCount = 5;
        address[] memory oppositeSwapUsers = new address[](oppositeSwapsCount);
        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            address user = makeAddr("oppositeSwapUser");
            tokenB.mint(user, 50 ether);
            tokenB.approve(address(router), 50 ether);
            oppositeSwapUsers[i] = user;
        }

        // we need to add swaps to the opposite pair to be able to fully execute the swap
        // let's make sure that the opposite swaps have streamCount > 1 to have them ready to be consumed in the streameQueue
        uint256 tokenBSwapAmount = 20 ether;

        (uint256 reserveD_tokenA_beforeSwap,,,,,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_beforeSwap,,,,,,,) = pool.poolInfo(address(tokenB));

        uint256 minPoolDepth = reserveD_tokenA_beforeSwap <= reserveD_tokenB_beforeSwap
            ? reserveD_tokenA_beforeSwap
            : reserveD_tokenB_beforeSwap;

        bytes32 poolId = poolLogic.getPoolId(address(tokenA), address(tokenB));
        uint256 streamCount = poolLogic.calculateStreamCount(tokenBSwapAmount, pool.pairSlippage(poolId), minPoolDepth);

        assertGt(streamCount, 1);

        // now let's add the opposite swap to the streaming queue
        uint256 reserveD_tokenA;
        uint256 reserveA_tokenA;
        uint256 reserveD_tokenB;
        uint256 reserveA_tokenB;
        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            (reserveD_tokenA,, reserveA_tokenA,,,,,) = pool.poolInfo(address(tokenA));
            (reserveD_tokenB,, reserveA_tokenB,,,,,) = pool.poolInfo(address(tokenB));

            uint256 executionPriceOppositeSwap = poolLogic.getExecutionPrice(reserveA_tokenB, reserveA_tokenA);
            vm.prank(oppositeSwapUsers[i]);
            router.swap(address(tokenB), address(tokenA), tokenBSwapAmount, executionPriceOppositeSwap);
        }

        // at this point we have multiple opposite swaps in the streaming queue
        (Swap[] memory oppositeSwaps, uint256 oppositeFront, uint256 oppositeBack) =
            pool.pairStreamQueue(oppositePairId);

        assertGt(oppositeBack, oppositeFront);

        // we want to know how many tokenAAmountOut is needed to fully execute the opposite swaps
        uint256 tokenOutAmountIn;
        for (uint256 i = oppositeFront; i < oppositeBack; i++) {
            Swap memory oppositeSwap = oppositeSwaps[i];
            tokenOutAmountIn += oppositeSwap.swapAmountRemaining;
        }

        (reserveD_tokenA,, reserveA_tokenA,,,,,) = pool.poolInfo(address(tokenA));
        (reserveD_tokenB,, reserveA_tokenB,,,,,) = pool.poolInfo(address(tokenB));

        // tokenAAmount needed to consume the opposite swaps;
        uint256 tokenInAmountOut = (tokenOutAmountIn * reserveA_tokenB) / reserveA_tokenA;
        uint256 executionPrice = poolLogic.getExecutionPrice(reserveA_tokenA, reserveA_tokenB);

        uint256 swapTokenAAmountIn = tokenInAmountOut - 0.1 ether;
        uint256 swapTokenBAmountOut = (swapTokenAAmountIn * reserveA_tokenA) / reserveA_tokenB;
        uint256 swaperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 swaperTokenBBalance_beforeSwap = tokenB.balanceOf(owner);
        vm.startPrank(owner);
        tokenA.approve(address(router), swapTokenAAmountIn);
        router.swap(address(tokenA), address(tokenB), swapTokenAAmountIn, executionPrice);
        vm.stopPrank();

        uint256 swaperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 swaperTokenBBalance_afterSwap = tokenB.balanceOf(owner);

        (, uint256 front, uint256 back) = pool.pairStreamQueue(pairId);
        assertEq(back, front);
        assertEq(swaperTokenABalance_afterSwap, swaperTokenABalance_beforeSwap - swapTokenAAmountIn);
        assertEq(swaperTokenBBalance_afterSwap, swaperTokenBBalance_beforeSwap + swapTokenBAmountOut);
    }
}
