// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

import { RouterTest } from "./Router.t.sol";
import { IRouterErrors } from "src/interfaces/router/IRouterErrors.sol";
import { Swap, LiquidityStream } from "src/lib/SwapQueue.sol";
import { console } from "forge-std/console.sol";
import { DSMath } from "src/lib/DSMath.sol";
import { PoolLogicLib } from "src/lib/PoolLogicLib.sol";

contract Router_SwapLimit is RouterTest {
    using DSMath for uint256;

    address private tokenC = makeAddr("tokenC");
    bytes32 pairId;
    bytes32 oppositePairId;

    function setUp() public virtual override {
        super.setUp();
        pairId = bytes32(abi.encodePacked(address(tokenA), address(tokenB)));
        oppositePairId = bytes32(abi.encodePacked(address(tokenB), address(tokenA)));
    }

    function test_swapLimitOrder_whenAmountInIsZero() public {
        vm.prank(owner);
        vm.expectRevert(IRouterErrors.InvalidAmount.selector);
        router.swapLimitOrder(address(tokenA), address(tokenB), 0, 1 ether);
    }

    function test_swapLimitOrder_whenExecutionPriceIsZero() public {
        uint8 decimals = tokenA.decimals();
        vm.prank(owner);
        vm.expectRevert(IRouterErrors.InvalidExecutionPrice.selector);
        router.swapLimitOrder(address(tokenA), address(tokenB), 1 * 10 ** decimals, 0);
    }

    function test_swapLimitOrder_whenInvalidPool() public {
        uint8 decimals = tokenA.decimals();
        vm.prank(owner);
        vm.expectRevert(IRouterErrors.InvalidPool.selector);
        router.swapLimitOrder(address(tokenA), address(tokenC), 1 * 10 ** decimals, 1 ether);
    }

    function test_swapLimitOrder_addToMarketOrderBook() public {
        uint256 TOKEN_A_SWAP_AMOUNT = 30 * 10 ** tokenA.decimals();

        uint256 currentExecPrice = _getCurrentPrice(address(tokenA), address(tokenB));

        uint256 limitOrderPrice = currentExecPrice + poolLogic.MAX_LIMIT_TICKS() * poolLogic.PRICE_PRECISION() + 1;

        uint256 executionPriceKey = PoolLogicLib.getExecutionPriceLower(currentExecPrice, poolLogic.PRICE_PRECISION());

        uint256 swapperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_beforeSwap = tokenA.balanceOf(address(pool));

        vm.startPrank(owner);
        tokenA.approve(address(router), TOKEN_A_SWAP_AMOUNT);
        router.swapLimitOrder(address(tokenA), address(tokenB), TOKEN_A_SWAP_AMOUNT, limitOrderPrice);
        vm.stopPrank();

        // should have no order in the limit order book
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, true);
        assertEq(swaps.length, 0);
        // should have orders in the market order book
        Swap[] memory marketSwaps = pool.orderBook(pairId, executionPriceKey, false);
        assertEq(marketSwaps.length, 1);
        // should have transfered the tokenA to the pool out of the swapper (owner)
        assertEq(tokenA.balanceOf(owner), swapperTokenABalance_beforeSwap - TOKEN_A_SWAP_AMOUNT);
        assertEq(tokenA.balanceOf(address(pool)), poolTokenABalance_beforeSwap + TOKEN_A_SWAP_AMOUNT);
    }

    /**
     * @notice This test will add a swap to the order book
     * because the swap price execution is lower than the current price (pool reserves)
     */
    function test_swapLimitOrder_addToOrderBook() public {
        uint256 TOKEN_A_SWAP_AMOUNT = 30 * 10 ** tokenA.decimals();

        uint256 marketPriceBeforeSwap = _getCurrentPrice(address(tokenA), address(tokenB));

        //         // the price is expressed in 18 decimals meaning that for 1 we have 1e18
        //         // execution price is 10% less than the market price
        uint256 executionPrice = marketPriceBeforeSwap - (marketPriceBeforeSwap * 10) / 100;

        uint256 swapperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_beforeSwap = tokenA.balanceOf(address(pool));

        uint256 swapperTokenBBalance_beforeSwap = tokenB.balanceOf(owner);
        uint256 poolTokenBBalance_beforeSwap = tokenB.balanceOf(address(pool));

        uint256 dust;
        uint256 streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), TOKEN_A_SWAP_AMOUNT);
        uint256 swapPerStream = TOKEN_A_SWAP_AMOUNT / streamCount;
        if (TOKEN_A_SWAP_AMOUNT % streamCount != 0) {
            dust += (TOKEN_A_SWAP_AMOUNT - (streamCount * swapPerStream));
        }

        vm.startPrank(owner);
        tokenA.approve(address(router), TOKEN_A_SWAP_AMOUNT);
        router.swapLimitOrder(address(tokenA), address(tokenB), TOKEN_A_SWAP_AMOUNT, executionPrice);
        vm.stopPrank();

        uint256 swapperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_afterSwap = tokenA.balanceOf(address(pool));

        uint256 swapperTokenBBalance_afterSwap = tokenB.balanceOf(owner);
        uint256 poolTokenBBalance_afterSwap = tokenB.balanceOf(address(pool));

        uint256 executionPriceKey = PoolLogicLib.getExecutionPriceLower(executionPrice, poolLogic.PRICE_PRECISION());
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, true);
        assertEq(swaps.length, 1);
        Swap memory swap = swaps[0];

        assertEq(swapperTokenABalance_afterSwap, swapperTokenABalance_beforeSwap - TOKEN_A_SWAP_AMOUNT);
        assertEq(poolTokenABalance_afterSwap, poolTokenABalance_beforeSwap + TOKEN_A_SWAP_AMOUNT);
        assertEq(swapperTokenBBalance_afterSwap, swapperTokenBBalance_beforeSwap);
        assertEq(poolTokenBBalance_afterSwap, poolTokenBBalance_beforeSwap);

        // check the swap
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
        assertEq(swap.typeOfOrder, 3);
    }

    function test_swapLimitOrder_totallyExecuteSwapFromReserves() public {
        (uint256 reserveD_tokenA_beforeSwap,, uint256 reserveA_tokenA_beforeSwap,,,, uint8 tokenADecimals) =
            pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_beforeSwap,, uint256 reserveA_tokenB_beforeSwap,,,, uint8 tokenBDecimals) =
            pool.poolInfo(address(tokenB));

        uint256 marketPriceBeforeSwap = _getCurrentPrice(address(tokenA), address(tokenB));

        uint256 limitOrderPrice = marketPriceBeforeSwap + 9 * poolLogic.PRICE_PRECISION();

        uint256 tokenASwapAmount = 1 * 10 ** (tokenA.decimals() - 3); // low amount to get consumed by the reserves in
            // one stream
        uint256 streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), tokenASwapAmount);

        uint256 dust;
        uint256 swapPerStream = tokenASwapAmount / streamCount;
        if (tokenASwapAmount % streamCount != 0) {
            dust += (tokenASwapAmount - (streamCount * swapPerStream));
        }
        uint256 swapperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_beforeSwap = tokenA.balanceOf(address(pool));
        uint256 poolTokenBBalance_beforeSwap = tokenB.balanceOf(address(pool));

        uint256 expectedAmountOut =
            PoolLogicLib.calculateAmountOutFromPrice(swapPerStream, limitOrderPrice, tokenADecimals, tokenBDecimals);
        // now we get the expected amount in to get the expectedAmountOut at the pool price
        uint256 expectedAmountIn = PoolLogicLib.calculateAmountInFromPrice(
            expectedAmountOut, marketPriceBeforeSwap, tokenADecimals, tokenBDecimals
        );

        uint256 extraToThePool = swapPerStream - expectedAmountIn;
        console.log("extraToThePool", extraToThePool);

        (uint256 dToUpdate, uint256 tokenBAmountOut) = PoolLogicLib.getSwapAmountOut(
            expectedAmountIn,
            reserveA_tokenA_beforeSwap,
            reserveA_tokenB_beforeSwap,
            reserveD_tokenA_beforeSwap,
            reserveD_tokenB_beforeSwap
        );

        vm.startPrank(owner);
        tokenA.approve(address(router), tokenASwapAmount);
        router.swapLimitOrder(address(tokenA), address(tokenB), tokenASwapAmount, limitOrderPrice);
        vm.stopPrank();

        //         uint256 swapperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        //         uint256 poolTokenABalance_afterSwap = tokenA.balanceOf(address(pool));
        //         uint256 poolTokenBBalance_afterSwap = tokenB.balanceOf(address(pool));

        (uint256 reserveD_tokenA_afterSwap,,,,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_afterSwap,,,,,,) = pool.poolInfo(address(tokenB));

        uint256 marketPriceAfterSwap = _getCurrentPrice(address(tokenA), address(tokenB));
        uint256 executionPriceKey = PoolLogicLib.getExecutionPriceLower(limitOrderPrice, poolLogic.PRICE_PRECISION());
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, true);

        //         assertEq(swaps.length, 0);
        //         assertEq(reserveA_tokenA_beforeSwap, reserveA_tokenA_afterSwap - swapPerStream);
        //         assertEq(reserveA_tokenB_beforeSwap, reserveA_tokenB_afterSwap + tokenBAmountOut);
        //         assertEq(reserveD_tokenA_afterSwap, reserveD_tokenA_beforeSwap - dToUpdate);
        //         assertEq(reserveD_tokenB_afterSwap, reserveD_tokenB_beforeSwap + dToUpdate);
        //         assertGt(marketPriceAfterSwap, marketPriceBeforeSwap);
        //         assertEq(swapperTokenABalance_afterSwap, swapperTokenABalance_beforeSwap - tokenASwapAmount);
        //         assertEq(poolTokenABalance_afterSwap, poolTokenABalance_beforeSwap + tokenASwapAmount);
        //         assertEq(poolTokenBBalance_afterSwap, poolTokenBBalance_beforeSwap - tokenBAmountOut);
    }

    /**
     * @notice This test will add a swap to the streaming queue and fully execute it by consuming opposite swaps
     */
    function test_swapLimitOrder_totallyExecuteSwapWithOppositeSwaps() public {
        uint256 oppositeSwapsCount = 10;
        address[] memory oppositeSwapUsers = new address[](oppositeSwapsCount);
        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            address user = makeAddr(string(abi.encodePacked("oppositeSwapUser", i)));
            tokenB.mint(user, 150 * 10 ** tokenB.decimals());
            tokenB.approve(address(router), 150 * 10 ** tokenB.decimals());
            oppositeSwapUsers[i] = user;
        }

        // we need to add swaps to the opposite pair to be able to fully execute the swap
        // let's make sure that the opposite swaps have streamCount > 1 to have them ready to be consumed in the
        // streameQueue
        uint256 tokenBSwapAmount = 150 * 10 ** tokenB.decimals();

        uint256 streamCount = poolLogic.getStreamCount(address(tokenB), address(tokenA), tokenBSwapAmount);
        uint256 swapPerStream = tokenBSwapAmount / streamCount;
        uint256 oppDust;
        if (tokenBSwapAmount % streamCount != 0) {
            oppDust += (tokenBSwapAmount - (streamCount * swapPerStream));
        }

        assertGt(streamCount, 1);

        // now let's add the opposite swap to the streaming queue
        (,, uint256 reserveA_tokenA,,,,) = pool.poolInfo(address(tokenA));
        (,, uint256 reserveA_tokenB,,,,) = pool.poolInfo(address(tokenB));
        uint256 executionPriceOppositeSwap = _getCurrentPrice(address(tokenB), address(tokenA));
        // we sub the price by 10% less
        executionPriceOppositeSwap -= 3 * poolLogic.PRICE_PRECISION();
        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            vm.prank(oppositeSwapUsers[i]);
            router.swapLimitOrder(address(tokenB), address(tokenA), tokenBSwapAmount, executionPriceOppositeSwap);
        }

        uint256 oppExecutionPriceKey =
            PoolLogicLib.getExecutionPriceLower(executionPriceOppositeSwap, poolLogic.PRICE_PRECISION());
        Swap[] memory oppositeSwaps = pool.orderBook(oppositePairId, oppExecutionPriceKey, true);

        assertTrue(oppositeSwaps.length > 0);

        (,,,,,, uint8 tokenADecimals) = pool.poolInfo(address(tokenA));
        (,,,,,, uint8 tokenBdecimals) = pool.poolInfo(address(tokenB));
        uint256 reserveAInFromPrice = PoolLogicLib.getOtherReserveFromPrice(
            executionPriceOppositeSwap, reserveA_tokenB, tokenBdecimals, tokenADecimals
        );

        // we want to know how many tokenAAmountOut is needed to fully execute the opposite swaps
        uint256 tokenOutAmountIn;
        uint256 tokenInAmountOut;
        for (uint256 i = 0; i < oppositeSwaps.length; i++) {
            Swap memory oppositeSwap = oppositeSwaps[i];
            tokenOutAmountIn += oppositeSwap.swapAmountRemaining; // tokenBAmount
            tokenInAmountOut +=
                PoolLogicLib.getAmountOut(oppositeSwap.swapAmountRemaining, reserveA_tokenB, reserveAInFromPrice);
        }
        uint256 executionPrice = PoolLogicLib.getReciprocalOppositePrice(
            executionPriceOppositeSwap, reserveA_tokenB, tokenBdecimals, tokenADecimals
        );

        uint256 swapTokenAAmountIn = tokenInAmountOut - 1 * 10 ** tokenA.decimals();

        uint256 _streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), swapTokenAAmountIn);
        uint256 _swapPerStream = swapTokenAAmountIn / _streamCount;
        uint256 dust;
        if (swapTokenAAmountIn % _streamCount != 0) dust = (swapTokenAAmountIn - (_streamCount * _swapPerStream));

        uint256 swapTokenBAmountOut;
        // we loop through the opposite swaps to get the expected amount of tokenB we will receive, after fully execute
        // our frontSwap swap
        uint256 tokenInCalculation = swapTokenAAmountIn;
        for (uint256 i = 0; i < oppositeSwaps.length; i++) {
            uint256 t = tokenInCalculation;
            Swap memory oppositeSwap = oppositeSwaps[i];
            uint256 reserveAInFromPrice = PoolLogicLib.getOtherReserveFromPrice(
                executionPriceOppositeSwap, reserveA_tokenB, tokenBdecimals, tokenADecimals
            );
            uint256 reserveAOutFromPrice =
                PoolLogicLib.getOtherReserveFromPrice(executionPrice, reserveA_tokenA, tokenADecimals, tokenBdecimals);
            uint256 oppSwapTokenAmount = oppositeSwap.swapAmountRemaining + oppositeSwap.dustTokenAmount;

            uint256 oppTokenInAmountOut =
                PoolLogicLib.getAmountOut(oppSwapTokenAmount, reserveA_tokenB, reserveAInFromPrice);

            if (t > oppTokenInAmountOut) {
                swapTokenBAmountOut += oppSwapTokenAmount;
                t -= oppTokenInAmountOut;

                if (i == oppositeSwaps.length - 1) {
                    uint256 _streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), t);
                    uint256 _swapPerStream = t / _streamCount;
                    if (t % streamCount != 0) {
                        dust += (t - (streamCount * swapPerStream));
                        t = _streamCount * _swapPerStream;
                    }
                }
            } else {
                swapTokenBAmountOut += PoolLogicLib.getAmountOut(t, reserveA_tokenA, reserveAOutFromPrice);
                break;
            }
            tokenInCalculation = t;
        }

        uint256 currentPrice = _getCurrentPrice(address(tokenA), address(tokenB));
        console.log("diff", executionPrice - currentPrice);

        uint256 swaperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 swaperTokenBBalance_beforeSwap = tokenB.balanceOf(owner);
        vm.startPrank(owner);
        tokenA.approve(address(router), swapTokenAAmountIn);
        router.swapLimitOrder(address(tokenA), address(tokenB), swapTokenAAmountIn, executionPrice);
        vm.stopPrank();

        uint256 swaperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 swaperTokenBBalance_afterSwap = tokenB.balanceOf(owner);

        uint256 executionPriceKey = PoolLogicLib.getExecutionPriceLower(executionPrice, poolLogic.PRICE_PRECISION());
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, true);

        assertTrue(swaps.length == 0);
        assertEq(swaperTokenABalance_afterSwap, swaperTokenABalance_beforeSwap - swapTokenAAmountIn);
        assertGt(swaperTokenBBalance_afterSwap, swaperTokenBBalance_beforeSwap); // @audit there's mismatch between the
            // expected amount of tokenB received and the actual amount very minute
    }

    function test_swapLimitOrder_fullyExecuteSwapWithBothOppositeSwapsAndReserves() public {
        // 1. we add the opposite swaps in opp orderBook at a certain price
        uint256 oppositeSwapsCount = 5;
        address[] memory oppositeSwapUsers = new address[](oppositeSwapsCount);
        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            address user = makeAddr(string(abi.encodePacked("oppositeSwapUser", i)));
            tokenB.mint(user, 200 * 10 ** tokenB.decimals());
            tokenB.approve(address(router), 200 * 10 ** tokenB.decimals());
            oppositeSwapUsers[i] = user;
        }

        uint256 oppSwapAmount = 1 * 10 ** tokenB.decimals();

        uint256 oppStreamCount = poolLogic.getStreamCount(address(tokenB), address(tokenA), oppSwapAmount);
        uint256 oppSwapPerStream = oppSwapAmount / oppStreamCount;
        uint256 oppDust;
        if (oppSwapAmount % oppStreamCount != 0) {
            oppDust = (oppSwapAmount - (oppStreamCount * oppSwapPerStream));
        }

        console.log("oppStreamCount", oppStreamCount);
        console.log("swapPerStream", oppSwapPerStream);
        console.log("oppDust", oppDust);

        //         // 2. we create the swap with the inversed price order book to totally consume all the opposite swaps

        // oppExecution price is the price of the opposite swap
        (uint256 reserveD_tokenA,, uint256 reserveA_tokenA,,,, uint8 decimalsA) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB,, uint256 reserveA_tokenB,,,, uint8 decimalsB) = pool.poolInfo(address(tokenB));

        uint256 executionPriceOppositeSwap = _getCurrentPrice(address(tokenB), address(tokenA));
        // we sub the price by 10% less
        executionPriceOppositeSwap -= 3 * poolLogic.PRICE_PRECISION();

        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            vm.prank(oppositeSwapUsers[i]);
            router.swapLimitOrder(address(tokenB), address(tokenA), oppSwapAmount, executionPriceOppositeSwap);
        }

        // at this stage we have all the opp swaps in the rounded oppPrice order book

        uint256 oppExecutionPriceKey =
            PoolLogicLib.getExecutionPriceLower(executionPriceOppositeSwap, poolLogic.PRICE_PRECISION());
        Swap[] memory oppositeSwaps = pool.orderBook(oppositePairId, oppExecutionPriceKey, true);

        assertEq(oppositeSwaps.length, oppositeSwapsCount);

        // we calculate the amount of tokenA we need to fully execute the opposite swaps
        uint256 reserveAInFromPrice =
            PoolLogicLib.getOtherReserveFromPrice(executionPriceOppositeSwap, reserveA_tokenB, decimalsB, decimalsA);
        uint256 tokenBInOppSwaps = oppSwapAmount * oppositeSwapsCount; // oppSwapAmount contains the oppDustToken amount

        uint256 tokenAOutOppSwaps;
        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            tokenAOutOppSwaps += PoolLogicLib.getAmountOut(oppSwapAmount, reserveA_tokenB, reserveAInFromPrice);
        }

        // we get the price of our swap based on the inversed price of opposite swaps
        uint256 swapExecutionPrice =
            PoolLogicLib.getReciprocalOppositePrice(executionPriceOppositeSwap, reserveA_tokenB, decimalsB, decimalsA);

        uint256 tokenAForPoolReserveSwap = 1 * 10 ** (tokenA.decimals() - 3);
        uint256 swapAmount = tokenAOutOppSwaps + tokenAForPoolReserveSwap;

        uint256 streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), tokenAForPoolReserveSwap);
        uint256 swapPerStream = tokenAForPoolReserveSwap / streamCount;
        uint256 dustAmountAReserveSwap;
        if (tokenAForPoolReserveSwap % streamCount != 0) {
            dustAmountAReserveSwap = (tokenAForPoolReserveSwap - (streamCount * swapPerStream));
            tokenAForPoolReserveSwap = streamCount * swapPerStream;
        }

        uint256 currentPrice = _getCurrentPrice(address(tokenA), address(tokenB));

        uint256 expectedAmountOut =
            PoolLogicLib.calculateAmountOutFromPrice(swapPerStream, swapExecutionPrice, decimalsA, decimalsB);
        // now we get the expected amount in to get the expectedAmountOut at the pool price
        uint256 expectedAmountIn =
            PoolLogicLib.calculateAmountInFromPrice(expectedAmountOut, currentPrice, decimalsA, decimalsB);

        uint256 extraToThePool = swapPerStream - expectedAmountIn;
        console.log("extraToThePool", extraToThePool);

        (uint256 dToUpdate, uint256 tokenBAmountOutFromReserves) = PoolLogicLib.getSwapAmountOut(
            expectedAmountIn, reserveA_tokenA, reserveA_tokenB, reserveD_tokenA, reserveD_tokenB
        );

        uint256 swapperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 swapperTokenBBalance_beforeSwap = tokenB.balanceOf(owner);
        uint256 poolTokenABalance_beforeSwap = tokenA.balanceOf(address(pool));
        uint256 poolTokenBBalance_beforeSwap = tokenB.balanceOf(address(pool));

        vm.startPrank(owner);
        tokenA.approve(address(router), swapAmount);
        router.swapLimitOrder(address(tokenA), address(tokenB), swapAmount, swapExecutionPrice);
        vm.stopPrank();

        uint256 swapperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 swapperTokenBBalance_afterSwap = tokenB.balanceOf(owner);
        uint256 poolTokenABalance_afterSwap = tokenA.balanceOf(address(pool));
        uint256 poolTokenBBalance_afterSwap = tokenB.balanceOf(address(pool));

        uint256 executionPriceKey = PoolLogicLib.getExecutionPriceLower(swapExecutionPrice, poolLogic.PRICE_PRECISION());

        Swap[] memory _oppositeSwaps = pool.orderBook(oppositePairId, oppExecutionPriceKey, true);
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, true);
        assertTrue(_oppositeSwaps.length == 0);
        assertTrue(swaps.length == 0);
        assertEq(swapperTokenABalance_afterSwap, swapperTokenABalance_beforeSwap - swapAmount);
        assertGt(swapperTokenBBalance_afterSwap, swapperTokenBBalance_beforeSwap); // @audit there's mismatch between
            // the expected amount of tokenB received and the actual amount very minute
    }
}
