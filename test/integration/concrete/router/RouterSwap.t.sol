// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RouterTest} from "./Router.t.sol";
import {IRouterErrors} from "src/interfaces/router/IRouterErrors.sol";
import {Swap, LiquidityStream} from "src/lib/SwapQueue.sol";
import {console} from "forge-std/console.sol";

contract RouterTest_Swap is RouterTest {
    address private tokenC = makeAddr("tokenC");
    uint256 private TOKEN_A_SWAP_AMOUNT = 30 ether;
    bytes32 pairId;
    bytes32 oppositePairId;

    function setUp() public virtual override {
        super.setUp();
        pairId = bytes32(abi.encodePacked(address(tokenA), address(tokenB)));
        oppositePairId = bytes32(abi.encodePacked(address(tokenB), address(tokenA)));
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

    /**
     * @notice This test will add a swap to the order book
     * because the swap price execution is lower than the current price (pool reserves)
     */
    function test_router_swap_addToOrderBook() public {
        (,, uint256 reserveA_tokenA_beforeSwap,,,) = pool.poolInfo(address(tokenA));
        (,, uint256 reserveA_tokenB_beforeSwap,,,) = pool.poolInfo(address(tokenB));

        uint256 marketPriceBeforeSwap =
            poolLogic.getExecutionPrice(reserveA_tokenA_beforeSwap, reserveA_tokenB_beforeSwap);

        console.log("executionPriceBeforeSwap", marketPriceBeforeSwap);

        // the price is expressed in 18 decimals meaning that for 1 we have 1e18
        // execution price is 10% less than the market price
        uint256 executionPrice = marketPriceBeforeSwap - (marketPriceBeforeSwap * 10) / 100;

        uint256 swapperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_beforeSwap = tokenA.balanceOf(address(pool));

        uint256 swapperTokenBBalance_beforeSwap = tokenB.balanceOf(owner);
        uint256 poolTokenBBalance_beforeSwap = tokenB.balanceOf(address(pool));

        vm.startPrank(owner);
        tokenA.approve(address(router), TOKEN_A_SWAP_AMOUNT);
        router.swap(address(tokenA), address(tokenB), TOKEN_A_SWAP_AMOUNT, executionPrice);
        vm.stopPrank();

        uint256 dust;
        uint256 streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), TOKEN_A_SWAP_AMOUNT);
        uint256 swapPerStream = TOKEN_A_SWAP_AMOUNT / streamCount;
        if (TOKEN_A_SWAP_AMOUNT % streamCount != 0) {
            dust += (TOKEN_A_SWAP_AMOUNT - (streamCount * swapPerStream));
        }

        uint256 swapperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_afterSwap = tokenA.balanceOf(address(pool));

        uint256 swapperTokenBBalance_afterSwap = tokenB.balanceOf(owner);
        uint256 poolTokenBBalance_afterSwap = tokenB.balanceOf(address(pool));

        (,, uint256 reserveA_tokenA_afterSwap,,,) = pool.poolInfo(address(tokenA));
        (,, uint256 reserveA_tokenB_afterSwap,,,) = pool.poolInfo(address(tokenB));

        uint256 marketPriceAfterSwap = poolLogic.getExecutionPrice(reserveA_tokenA_afterSwap, reserveA_tokenB_afterSwap);

        uint256 executionPriceKey = poolLogic.getExecutionPriceLower(executionPrice);
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey);
        assertEq(swaps.length, 1);
        Swap memory swap = swaps[0];

        assertEq(reserveA_tokenA_beforeSwap, reserveA_tokenA_afterSwap);
        assertEq(reserveA_tokenB_beforeSwap, reserveA_tokenB_afterSwap);
        assertEq(marketPriceBeforeSwap, marketPriceAfterSwap);
        assertEq(swapperTokenABalance_afterSwap, swapperTokenABalance_beforeSwap - TOKEN_A_SWAP_AMOUNT);
        assertEq(poolTokenABalance_afterSwap, poolTokenABalance_beforeSwap + TOKEN_A_SWAP_AMOUNT);
        assertEq(swapperTokenBBalance_afterSwap, swapperTokenBBalance_beforeSwap);
        assertEq(poolTokenBBalance_afterSwap, poolTokenBBalance_beforeSwap);

        // // check the swap
        assertEq(swap.swapAmount, TOKEN_A_SWAP_AMOUNT);
        assertEq(swap.swapAmountRemaining, TOKEN_A_SWAP_AMOUNT - dust);
        assertEq(swap.dustTokenAmount, dust);
        assertEq(swap.streamsCount, streamCount);
        assertEq(swap.streamsRemaining, streamCount);
        assertEq(swap.swapPerStream, swapPerStream);
        assertEq(swap.executionPrice, executionPrice);
        assertEq(swap.amountOut, 0);
        assertEq(swap.user, owner);
        assertEq(swap.tokenIn, address(tokenA));
        assertEq(swap.tokenOut, address(tokenB));
        assertEq(swap.completed, false);
    }

    function test_router_swap_totallyExecuteSwapFromReserves() public {
        (uint256 reserveD_tokenA_beforeSwap,, uint256 reserveA_tokenA_beforeSwap,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_beforeSwap,, uint256 reserveA_tokenB_beforeSwap,,,) = pool.poolInfo(address(tokenB));

        uint256 marketPriceBeforeSwap =
            poolLogic.getExecutionPrice(reserveA_tokenA_beforeSwap, reserveA_tokenB_beforeSwap);

        console.log("executionPriceBeforeSwap", marketPriceBeforeSwap);

        // to add the swap in the straming queue we need to have a swap price execution lower or equal to the current price
        uint256 executionPrice = marketPriceBeforeSwap;

        uint256 tokenASwapAmount = 0.125 ether; // low amount to get consumed by the reserves in one stream
        uint256 streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), tokenASwapAmount);

        uint256 dust;
        uint256 swapPerStream = tokenASwapAmount / streamCount;
        if (tokenASwapAmount % streamCount != 0) {
            dust += (tokenASwapAmount - (streamCount * swapPerStream));
        }
        uint256 swapperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_beforeSwap = tokenA.balanceOf(address(pool));
        uint256 poolTokenBBalance_beforeSwap = tokenB.balanceOf(address(pool));

        (uint256 _dToUpdate, uint256 _tokenBAmountOut) = poolLogic.getSwapAmountOut(
            swapPerStream,
            reserveA_tokenA_beforeSwap,
            reserveA_tokenB_beforeSwap,
            reserveD_tokenA_beforeSwap,
            reserveD_tokenB_beforeSwap
        );
        console.log("reserveA_tokenB_beforeSwap", reserveA_tokenB_beforeSwap);
        console.log("reserveD_tokenB_beforeSwap", reserveD_tokenB_beforeSwap);
        console.log("_tokenBAmountOut", _tokenBAmountOut);

        uint256 reserveA_tokenB_FromPrice =
            poolLogic.getOtherReserveFromPrice(executionPrice, reserveA_tokenA_beforeSwap);
        uint256 reserveD_tokenB_FromPrice =
            poolLogic.getOtherReserveFromPrice(executionPrice, reserveD_tokenA_beforeSwap);

        (uint256 dToUpdate, uint256 tokenBAmountOut) = poolLogic.getSwapAmountOut(
            swapPerStream,
            reserveA_tokenA_beforeSwap,
            reserveA_tokenB_FromPrice,
            reserveD_tokenA_beforeSwap,
            reserveD_tokenB_FromPrice
        );

        console.log("reserveA_tokenB_FromPrice", reserveA_tokenB_FromPrice);
        console.log("reserveD_tokenB_FromPrice", reserveD_tokenB_FromPrice);
        console.log("tokenBAmountOut", tokenBAmountOut);

        vm.startPrank(owner);
        tokenA.approve(address(router), tokenASwapAmount);
        router.swap(address(tokenA), address(tokenB), tokenASwapAmount, executionPrice);
        vm.stopPrank();

        uint256 swapperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_afterSwap = tokenA.balanceOf(address(pool));
        uint256 poolTokenBBalance_afterSwap = tokenB.balanceOf(address(pool));

        (uint256 reserveD_tokenA_afterSwap,, uint256 reserveA_tokenA_afterSwap,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_afterSwap,, uint256 reserveA_tokenB_afterSwap,,,) = pool.poolInfo(address(tokenB));

        uint256 marketPriceAfterSwap = poolLogic.getExecutionPrice(reserveA_tokenA_afterSwap, reserveA_tokenB_afterSwap);
        uint256 executionPriceKey = poolLogic.getExecutionPriceLower(executionPrice);
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey);

        assertEq(swaps.length, 0);
        assertEq(reserveA_tokenA_beforeSwap, reserveA_tokenA_afterSwap - swapPerStream);
        assertEq(reserveA_tokenB_beforeSwap, reserveA_tokenB_afterSwap + tokenBAmountOut);
        assertEq(reserveD_tokenA_afterSwap, reserveD_tokenA_beforeSwap - dToUpdate);
        assertEq(reserveD_tokenB_afterSwap, reserveD_tokenB_beforeSwap + dToUpdate);
        assertGt(marketPriceAfterSwap, marketPriceBeforeSwap);
        assertEq(swapperTokenABalance_afterSwap, swapperTokenABalance_beforeSwap - tokenASwapAmount);
        assertEq(poolTokenABalance_afterSwap, poolTokenABalance_beforeSwap + tokenASwapAmount);
        assertEq(poolTokenBBalance_afterSwap, poolTokenBBalance_beforeSwap - tokenBAmountOut);
    }

    /**
     * @notice This test will add a swap to the streaming queue and partially execute it
     * because the streamCount will be above 1, the swap won't be totally executed but only partially
     */
    function test_router_swap_partiallyExecuteSwapAndAddToOrderBook() public {
        uint256 tokenASwapAmount = 300 ether;
        (uint256 reserveD_tokenA_beforeSwap,, uint256 reserveA_tokenA_beforeSwap,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_beforeSwap,, uint256 reserveA_tokenB_beforeSwap,,,) = pool.poolInfo(address(tokenB));

        uint256 executionPriceBeforeSwap =
            poolLogic.getExecutionPrice(reserveA_tokenA_beforeSwap, reserveA_tokenB_beforeSwap);

        // to add the swap in the straming queue we need to have a swap price execution lower or equal to the current price
        uint256 executionPrice = executionPriceBeforeSwap;

        uint256 streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), tokenASwapAmount);
        uint256 swapPerStream = tokenASwapAmount / streamCount;
        uint256 dust;
        if (tokenASwapAmount % streamCount != 0) {
            dust += (tokenASwapAmount - (streamCount * swapPerStream));
        }

        uint256 swapperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_beforeSwap = tokenA.balanceOf(address(pool));
        (uint256 _dToUpdate, uint256 _tokenBAmountOut) = poolLogic.getSwapAmountOut(
            swapPerStream,
            reserveA_tokenA_beforeSwap,
            reserveA_tokenB_beforeSwap,
            reserveD_tokenA_beforeSwap,
            reserveD_tokenB_beforeSwap
        );

        uint256 reserveA_tokenB_FromPrice =
            poolLogic.getOtherReserveFromPrice(executionPrice, reserveA_tokenA_beforeSwap);
        uint256 reserveD_tokenB_FromPrice =
            poolLogic.getOtherReserveFromPrice(executionPrice, reserveD_tokenA_beforeSwap);

        (uint256 dToUpdate, uint256 tokenBAmountOut) = poolLogic.getSwapAmountOut(
            swapPerStream,
            reserveA_tokenA_beforeSwap,
            reserveA_tokenB_FromPrice,
            reserveD_tokenA_beforeSwap,
            reserveD_tokenB_FromPrice
        );

        console.log("reserveA_tokenB_FromPrice", reserveA_tokenB_FromPrice);
        console.log("reserveD_tokenB_FromPrice", reserveD_tokenB_FromPrice);
        console.log("tokenBAmountOut", tokenBAmountOut);

        vm.startPrank(owner);
        tokenA.approve(address(router), tokenASwapAmount);
        router.swap(address(tokenA), address(tokenB), tokenASwapAmount, executionPrice);
        vm.stopPrank();

        uint256 swapperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_afterSwap = tokenA.balanceOf(address(pool));

        (uint256 reserveD_tokenA_afterSwap,, uint256 reserveA_tokenA_afterSwap,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_afterSwap,, uint256 reserveA_tokenB_afterSwap,,,) = pool.poolInfo(address(tokenB));

        uint256 executionPriceAfterSwap =
            poolLogic.getExecutionPrice(reserveA_tokenA_afterSwap, reserveA_tokenB_afterSwap);

        uint256 executionPriceKey = poolLogic.getExecutionPriceLower(executionPrice);
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey);
        Swap memory swap = swaps[0];

        assertEq(reserveA_tokenA_beforeSwap, reserveA_tokenA_afterSwap - swapPerStream);
        assertEq(reserveA_tokenB_beforeSwap, reserveA_tokenB_afterSwap + tokenBAmountOut);
        assertEq(reserveD_tokenA_afterSwap, reserveD_tokenA_beforeSwap - dToUpdate);
        assertEq(reserveD_tokenB_afterSwap, reserveD_tokenB_beforeSwap + dToUpdate);
        assertGt(executionPriceAfterSwap, executionPriceBeforeSwap);
        assertEq(swapperTokenABalance_afterSwap, swapperTokenABalance_beforeSwap - tokenASwapAmount);
        assertEq(poolTokenABalance_afterSwap, poolTokenABalance_beforeSwap + tokenASwapAmount);

        // check the swap
        assertEq(swap.swapAmount, tokenASwapAmount);
        assertEq(swap.swapAmountRemaining, tokenASwapAmount - swapPerStream - dust);
        assertEq(swap.streamsCount, streamCount);
        assertEq(swap.streamsRemaining, streamCount - 1);
        assertEq(swap.swapPerStream, swapPerStream);
        assertEq(swap.executionPrice, executionPrice);
        assertEq(swap.amountOut, tokenBAmountOut);
        assertEq(swap.user, owner);
        assertEq(swap.tokenIn, address(tokenA));
        assertEq(swap.tokenOut, address(tokenB));
        assertEq(swap.completed, false);
    }

    /**
     * @notice This test will add a swap to the streaming queue and fully execute it by consuming opposite swaps
     */
    function test_router_swap_totallyExecuteSwapWithOppositeSwaps() public {
        uint256 oppositeSwapsCount = 10;
        address[] memory oppositeSwapUsers = new address[](oppositeSwapsCount);
        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            address user = makeAddr(string(abi.encodePacked("oppositeSwapUser", i)));
            tokenB.mint(user, 150 ether);
            tokenB.approve(address(router), 150 ether);
            oppositeSwapUsers[i] = user;
        }

        // we need to add swaps to the opposite pair to be able to fully execute the swap
        // let's make sure that the opposite swaps have streamCount > 1 to have them ready to be consumed in the streameQueue
        uint256 tokenBSwapAmount = 150 ether;

        (uint256 reserveD_tokenA_beforeSwap,,,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_beforeSwap,,,,,) = pool.poolInfo(address(tokenB));

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
            (reserveD_tokenA,, reserveA_tokenA,,,) = pool.poolInfo(address(tokenA));
            (reserveD_tokenB,, reserveA_tokenB,,,) = pool.poolInfo(address(tokenB));

            uint256 executionPriceOppositeSwap = poolLogic.getExecutionPrice(reserveA_tokenB, reserveA_tokenA);
            vm.prank(oppositeSwapUsers[i]);
            router.swap(address(tokenB), address(tokenA), tokenBSwapAmount, executionPriceOppositeSwap);
        }

        // at this point we have multiple opposite swaps in the streaming queue
        (Swap[] memory oppositeSwaps, uint256 oppositeFront, uint256 oppositeBack) =
            pool.pairStreamQueue(oppositePairId);

        assertGt(oppositeBack, oppositeFront);

        (reserveD_tokenA,, reserveA_tokenA,,,) = pool.poolInfo(address(tokenA));
        (reserveD_tokenB,, reserveA_tokenB,,,) = pool.poolInfo(address(tokenB));

        // we want to know how many tokenAAmountOut is needed to fully execute the opposite swaps
        uint256 tokenOutAmountIn;
        uint256 tokenInAmountOut;
        for (uint256 i = oppositeFront; i < oppositeBack; i++) {
            Swap memory oppositeSwap = oppositeSwaps[i];
            tokenOutAmountIn += oppositeSwap.swapAmountRemaining;
            tokenInAmountOut +=
                poolLogic.getAmountOut(oppositeSwap.swapAmountRemaining, reserveA_tokenB, reserveA_tokenA);
        }

        // tokenAAmount needed to consume the opposite swaps;
        uint256 executionPrice = poolLogic.getExecutionPrice(reserveA_tokenA, reserveA_tokenB);

        (reserveD_tokenA,, reserveA_tokenA,,,) = pool.poolInfo(address(tokenA));
        (reserveD_tokenB,, reserveA_tokenB,,,) = pool.poolInfo(address(tokenB));

        uint256 swapTokenAAmountIn = tokenInAmountOut - 1 ether;

        streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), swapTokenAAmountIn);
        uint256 swapPerStream = swapTokenAAmountIn / streamCount;
        if (swapTokenAAmountIn % streamCount != 0) swapTokenAAmountIn = streamCount * swapPerStream;

        uint256 swapTokenBAmountOut;
        // we loop through the opposite swaps to get the expected amount of tokenB we will receive, after fully execute our frontSwap swap
        uint256 swapTokenAAmountInForCalculation = swapTokenAAmountIn;
        for (uint256 i = oppositeFront; i < oppositeBack; i++) {
            Swap memory oppositeSwap = oppositeSwaps[i];
            uint256 oppTokenInAmountOut =
                poolLogic.getAmountOut(oppositeSwap.swapAmountRemaining, reserveA_tokenB, reserveA_tokenA);

            if (swapTokenAAmountInForCalculation > oppTokenInAmountOut) {
                swapTokenBAmountOut += oppositeSwap.swapAmountRemaining;
                swapTokenAAmountInForCalculation -= oppTokenInAmountOut;

                if (i == oppositeBack - 1) {
                    uint256 _streamCount =
                        poolLogic.getStreamCount(address(tokenA), address(tokenB), swapTokenAAmountInForCalculation);
                    uint256 _swapPerStream = swapTokenAAmountInForCalculation / _streamCount;
                    if (swapTokenAAmountInForCalculation % streamCount != 0) {
                        swapTokenAAmountInForCalculation = _streamCount * _swapPerStream;
                    }
                }
            } else {
                swapTokenBAmountOut +=
                    poolLogic.getAmountOut(swapTokenAAmountInForCalculation, reserveA_tokenA, reserveA_tokenB);
                break;
            }
        }

        uint256 swaperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 swaperTokenBBalance_beforeSwap = tokenB.balanceOf(owner);
        vm.startPrank(owner);
        tokenA.approve(address(router), swapTokenAAmountIn);
        router.swap(address(tokenA), address(tokenB), swapTokenAAmountIn, executionPrice);
        vm.stopPrank();

        uint256 swaperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 swaperTokenBBalance_afterSwap = tokenB.balanceOf(owner);

        (, uint256 front, uint256 back) = pool.pairStreamQueue(pairId);
        console.log("exxx", uint256(149034482758620689648));
        console.log("Expected", swapTokenBAmountOut);
        assertEq(back, front);
        assertEq(swaperTokenABalance_afterSwap, swaperTokenABalance_beforeSwap - swapTokenAAmountIn);
        assertEq(swaperTokenBBalance_afterSwap, swaperTokenBBalance_beforeSwap + swapTokenBAmountOut);
    }

    /**
     * @notice This test will add a swap to the streaming queue and fully execute it by consuming opposite swaps
     */
    function test_router_swap_fullyExecuteSwapWithBothOppositeSwapsAndReserves() public {
        uint256 oppositeSwapsCount = 5;
        address[] memory oppositeSwapUsers = new address[](oppositeSwapsCount);
        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            address user = makeAddr(string(abi.encodePacked("oppositeSwapUser", i)));
            tokenB.mint(user, 200 ether);
            tokenB.approve(address(router), 200 ether);
            oppositeSwapUsers[i] = user;
        }

        // we need to add swaps to the opposite pair to be able to fully execute the swap
        // let's make sure that the opposite swaps have streamCount > 1 to have them ready to be consumed in the streameQueue
        uint256 tokenBSwapAmount = 100 ether;

        (uint256 reserveD_tokenA_beforeSwap,,,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_beforeSwap,,,,,) = pool.poolInfo(address(tokenB));

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
            (reserveD_tokenA,, reserveA_tokenA,,,) = pool.poolInfo(address(tokenA));
            (reserveD_tokenB,, reserveA_tokenB,,,) = pool.poolInfo(address(tokenB));

            uint256 executionPriceOppositeSwap = poolLogic.getExecutionPrice(reserveA_tokenB, reserveA_tokenA);
            vm.prank(oppositeSwapUsers[i]);
            router.swap(address(tokenB), address(tokenA), tokenBSwapAmount, executionPriceOppositeSwap);
        }

        // at this point we have multiple opposite swaps in the streaming queue
        (Swap[] memory oppositeSwaps, uint256 oppositeFront, uint256 oppositeBack) =
            pool.pairStreamQueue(oppositePairId);

        assertGt(oppositeBack, oppositeFront);

        (reserveD_tokenA,, reserveA_tokenA,,,) = pool.poolInfo(address(tokenA));
        (reserveD_tokenB,, reserveA_tokenB,,,) = pool.poolInfo(address(tokenB));

        // we want to know how many tokenAAmountOut is needed to fully execute the opposite swaps
        uint256 tokenOutAmountIn;
        uint256 tokenInAmountOut;
        for (uint256 i = oppositeFront; i < oppositeBack; i++) {
            Swap memory oppositeSwap = oppositeSwaps[i];
            tokenOutAmountIn += oppositeSwap.swapAmountRemaining;
            tokenInAmountOut +=
                poolLogic.getAmountOut(oppositeSwap.swapAmountRemaining, reserveA_tokenB, reserveA_tokenA);
        }

        // tokenAAmount needed to consume the opposite swaps;
        uint256 executionPrice = poolLogic.getExecutionPrice(reserveA_tokenA, reserveA_tokenB);

        uint256 swapTokenAAmountIn = tokenInAmountOut + 0.1 ether;
        streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), swapTokenAAmountIn);
        uint256 swapPerStream = swapTokenAAmountIn / streamCount;
        if (swapTokenAAmountIn % streamCount != 0) swapTokenAAmountIn = streamCount * swapPerStream;

        uint256 swapTokenAAmountInForCalculation = swapTokenAAmountIn;

        for (uint256 i = oppositeFront; i < oppositeBack; i++) {
            Swap memory oppositeSwap = oppositeSwaps[i];
            uint256 oppTokenInAmountOut =
                poolLogic.getAmountOut(oppositeSwap.swapAmountRemaining, reserveA_tokenB, reserveA_tokenA);
            swapTokenAAmountInForCalculation -= oppTokenInAmountOut;
            // recalculate the stream count if needed
            if (i == oppositeBack - 1) {
                uint256 _streamCount =
                    poolLogic.getStreamCount(address(tokenA), address(tokenB), swapTokenAAmountInForCalculation);
                uint256 _swapPerStream = swapTokenAAmountInForCalculation / _streamCount;
                if (swapTokenAAmountInForCalculation % _streamCount != 0) {
                    swapTokenAAmountInForCalculation = _streamCount * _swapPerStream;
                }
            }
        }

        // dust tokens not included in the swap
        uint256 dustTokens = (swapTokenAAmountIn - tokenInAmountOut) - swapTokenAAmountInForCalculation;

        uint256 swapTokenBAmountOutFromOppSwaps = tokenOutAmountIn;
        (, uint256 swapTokenBAmoutOutFromReserve) = poolLogic.getSwapAmountOut(
            swapTokenAAmountIn - tokenInAmountOut, reserveA_tokenA, reserveA_tokenB, reserveD_tokenA, reserveD_tokenB
        );
        uint256 swaperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 swaperTokenBBalance_beforeSwap = tokenB.balanceOf(owner);
        vm.startPrank(owner);
        tokenA.approve(address(router), swapTokenAAmountIn);
        router.swap(address(tokenA), address(tokenB), swapTokenAAmountIn, executionPrice);
        vm.stopPrank();

        (,, uint256 reserveA_tokenA_afterSwap,,,) = pool.poolInfo(address(tokenA));
        (,, uint256 reserveA_tokenB_afterSwap,,,) = pool.poolInfo(address(tokenB));

        uint256 swaperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 swaperTokenBBalance_afterSwap = tokenB.balanceOf(owner);

        (, uint256 front, uint256 back) = pool.pairStreamQueue(pairId);
        (, uint256 oppFront, uint256 oppBack) = pool.pairStreamQueue(oppositePairId);

        console.log("dustTokens", dustTokens);
        assertEq(back, front);
        assertEq(oppBack, oppFront);
        assertEq(swaperTokenABalance_afterSwap, swaperTokenABalance_beforeSwap - swapTokenAAmountIn);
        assertEq(
            swaperTokenBBalance_afterSwap,
            swaperTokenBBalance_beforeSwap + swapTokenBAmountOutFromOppSwaps + swapTokenBAmoutOutFromReserve
        );
        assertEq(reserveA_tokenA_afterSwap, reserveA_tokenA + swapTokenAAmountIn - tokenInAmountOut - dustTokens);
        assertEq(reserveA_tokenB_afterSwap, reserveA_tokenB - swapTokenBAmoutOutFromReserve);
    }
}
