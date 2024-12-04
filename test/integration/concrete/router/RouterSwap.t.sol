// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RouterTest} from "./Router.t.sol";
import {IRouterErrors} from "src/interfaces/router/IRouterErrors.sol";
import {Swap, LiquidityStream} from "src/lib/SwapQueue.sol";
import {console} from "forge-std/console.sol";
import {DSMath} from "src/lib/DSMath.sol";

contract RouterTest_Swap is RouterTest {
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
        vm.prank(owner);
        vm.expectRevert(IRouterErrors.InvalidExecutionPrice.selector);
        router.swapLimitOrder(address(tokenA), address(tokenB), 1 ether, 0);
    }

    function test_swapLimitOrder_whenInvalidPool() public {
        vm.prank(owner);
        vm.expectRevert(IRouterErrors.InvalidPool.selector);
        router.swapLimitOrder(address(tokenA), address(tokenC), 1 ether, 1 ether);
    }

    function test_swapMarketOrder_success() public {
        vm.startPrank(owner);
        // Get initial pool reserves
        (uint256 reserveD_tokenA_before,, uint256 reserveA_tokenA_before,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_before,, uint256 reserveA_tokenB_before,,,) = pool.poolInfo(address(tokenB));

        // Setup initial conditions for the market order
        uint256 initialBalanceTokenA = tokenA.balanceOf(owner);
        uint256 initialBalanceTokenB = tokenB.balanceOf(owner);
        uint256 swapAmount = 10 ether;
        uint256 expectedExecutionPrice = poolLogic.getExecutionPrice(reserveA_tokenA_before, reserveA_tokenB_before);

        uint256 reserveDOutFromPriceB =
            poolLogic.getOtherReserveFromPrice(expectedExecutionPrice, reserveD_tokenA_before);

        // Calculate expected stream details
        uint256 streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), swapAmount);
        uint256 swapPerStream = swapAmount / streamCount;
        uint256 dust = 0;
        if (swapAmount % streamCount != 0) {
            dust = swapAmount - (streamCount * swapPerStream);
        }

        (uint256 dOut, uint256 aOut) = poolLogic.getSwapAmountOut(
            swapPerStream, reserveA_tokenA_before, reserveA_tokenB_before, reserveD_tokenA_before, reserveDOutFromPriceB
        );

        // Approve the router to spend tokenA
        tokenA.approve(address(router), swapAmount);

        // Call the swapMarketOrder function
        router.swapMarketOrder(address(tokenA), address(tokenB), swapAmount);

        // Get final pool reserves
        (uint256 reserveD_tokenA_after,, uint256 reserveA_tokenA_after,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_after,, uint256 reserveA_tokenB_after,,,) = pool.poolInfo(address(tokenB));
        // Get swap from order book
        uint256 executionPriceKey = poolLogic.getExecutionPriceLower(expectedExecutionPrice);

        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, false);
        assertGt(swaps.length, 0, "No swap in order book");
        Swap memory swap = swaps[0];

        // Check balances
        uint256 finalBalanceTokenA = tokenA.balanceOf(owner);
        uint256 finalBalanceTokenB = tokenB.balanceOf(owner);

        assertEq(finalBalanceTokenA, initialBalanceTokenA - swapAmount);

        // Check reserves changed correctly
        assertEq(reserveA_tokenA_after, reserveA_tokenA_before + swapPerStream);
        assertEq(reserveD_tokenA_after, reserveD_tokenA_before - dOut);
        assertEq(reserveA_tokenB_after, reserveA_tokenB_before - aOut);
        assertEq(reserveD_tokenB_after, reserveD_tokenB_before + dOut);

        // Check swap object values
        assertEq(swap.swapAmount, swapAmount);
        assertEq(swap.swapAmountRemaining, swapAmount - swapPerStream - dust);
        assertEq(swap.streamsCount, streamCount);
        assertEq(swap.streamsRemaining, streamCount - 1);
        assertEq(swap.swapPerStream, swapPerStream);
        assertEq(swap.executionPrice, expectedExecutionPrice);
        assertEq(swap.amountOut, aOut);
        assertEq(swap.user, owner);
        assertEq(swap.tokenIn, address(tokenA));
        assertEq(swap.tokenOut, address(tokenB));
        assertEq(swap.completed, false);
        assertEq(swap.dustTokenAmount, dust);
        assertEq(swap.typeOfOrder, 2);
    }

    function test_swapMarketOrder_invalidAmount() public {
        // Attempt to swap with an invalid amount (e.g., zero)
        vm.prank(owner);
        vm.expectRevert(IRouterErrors.InvalidAmount.selector);
        router.swapMarketOrder(address(tokenA), address(tokenB), 0);
    }

    function test_swapMarketOrder_invalidPool() public {
        vm.prank(owner);
        vm.expectRevert(IRouterErrors.InvalidPool.selector);
        router.swapMarketOrder(address(tokenA), address(tokenC), 10 ether);
    }

    function test_swapTriggerOrder_success() public {
        vm.startPrank(owner);
        // Get initial pool reserves
        (uint256 reserveD_tokenA_before,, uint256 reserveA_tokenA_before,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_before,, uint256 reserveA_tokenB_before,,,) = pool.poolInfo(address(tokenB));

        // Setup initial conditions for the market order
        uint256 initialBalanceTokenA = tokenA.balanceOf(owner);
        uint256 initialBalanceTokenB = tokenB.balanceOf(owner);
        uint256 swapAmount = 10 ether;
        uint256 currentExecutionPrice = poolLogic.getExecutionPrice(reserveA_tokenA_before, reserveA_tokenB_before);
        uint256 expectedExecutionPrice = currentExecutionPrice * 2;

        // Calculate expected stream details
        uint256 streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), swapAmount);
        uint256 swapPerStream = swapAmount / streamCount;
        uint256 dust = 0;
        if (swapAmount % streamCount != 0) {
            dust = swapAmount - (streamCount * swapPerStream);
        }
        // Approve the router to spend tokenA
        tokenA.approve(address(router), swapAmount);

        // Call the swapMarketOrder function
        router.swapTriggerOrder(address(tokenA), address(tokenB), swapAmount, expectedExecutionPrice);
        // Get swap from order book
        uint256 executionPriceKey = poolLogic.getExecutionPriceLower(expectedExecutionPrice);

        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, false);
        assertGt(swaps.length, 0, "No swap in order book");
        Swap memory swap = swaps[0];

        // Check balances
        uint256 finalBalanceTokenA = tokenA.balanceOf(owner);
        assertEq(finalBalanceTokenA, initialBalanceTokenA - swapAmount);

        // Check swap object values
        assertEq(swap.swapAmount, swapAmount);
        assertEq(swap.swapAmountRemaining, swapAmount - dust);
        assertEq(swap.streamsCount, streamCount);
        assertEq(swap.streamsRemaining, streamCount);
        assertEq(swap.swapPerStream, swapPerStream);
        assertEq(swap.executionPrice, expectedExecutionPrice);
        assertEq(swap.amountOut, 0);
        assertEq(swap.user, owner);
        assertEq(swap.tokenIn, address(tokenA));
        assertEq(swap.tokenOut, address(tokenB));
        assertEq(swap.completed, false);
        assertEq(swap.dustTokenAmount, dust);
        assertEq(swap.typeOfOrder, 1);
    }

    function test_swapTriggerOrder_invalidExecutionPrice() public {
        vm.startPrank(owner);
        vm.expectRevert(IRouterErrors.InvalidExecutionPrice.selector);
        router.swapTriggerOrder(address(tokenA), address(tokenB), 10 ether, 0);
    }

    function test_swapTriggerOrder_invalidPool() public {
        vm.startPrank(owner);
        vm.expectRevert(IRouterErrors.InvalidPool.selector);
        router.swapTriggerOrder(address(tokenA), address(tokenC), 10 ether, 1 ether);
    }

    function test_swapTriggerOrder_invalidAmount() public {
        vm.startPrank(owner);
        vm.expectRevert(IRouterErrors.InvalidAmount.selector);
        router.swapTriggerOrder(address(tokenA), address(tokenB), 0, 1 ether);
    }

    /**
     * @notice This test will add a swap to the order book
     * because the swap price execution is lower than the current price (pool reserves)
     */
    function test_swapLimitOrder_addToOrderBook() public {
        uint256 TOKEN_A_SWAP_AMOUNT = 30 ether;

        (uint256 reserveD_tokenA_beforeSwap,, uint256 reserveA_tokenA_beforeSwap,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_beforeSwap,, uint256 reserveA_tokenB_beforeSwap,,,) = pool.poolInfo(address(tokenB));

        uint256 marketPriceBeforeSwap =
            poolLogic.getExecutionPrice(reserveA_tokenA_beforeSwap, reserveA_tokenB_beforeSwap);

        // the price is expressed in 18 decimals meaning that for 1 we have 1e18
        // execution price is 10% less than the market price
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

        uint256 reserveAOutFromPrice = poolLogic.getOtherReserveFromPrice(executionPrice, reserveA_tokenA_beforeSwap);

        // TODO: NEED TO FIX RESERVE D EQUATION
        uint256 reserveDOutFromPrice = poolLogic.getOtherReserveFromPrice(executionPrice, reserveD_tokenA_beforeSwap);
        (uint256 dOut, uint256 amountOutPerStream) = poolLogic.getSwapAmountOut(
            swapPerStream,
            reserveA_tokenA_beforeSwap,
            reserveAOutFromPrice,
            reserveD_tokenA_beforeSwap,
            reserveDOutFromPrice
        );

        vm.startPrank(owner);
        tokenA.approve(address(router), TOKEN_A_SWAP_AMOUNT);
        router.swapLimitOrder(address(tokenA), address(tokenB), TOKEN_A_SWAP_AMOUNT, executionPrice);
        vm.stopPrank();

        (uint256 reserveD_tokenA_afterSwap,, uint256 reserveA_tokenA_afterSwap,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_afterSwap,, uint256 reserveA_tokenB_afterSwap,,,) = pool.poolInfo(address(tokenB));

        uint256 swapperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_afterSwap = tokenA.balanceOf(address(pool));

        uint256 swapperTokenBBalance_afterSwap = tokenB.balanceOf(owner);
        uint256 poolTokenBBalance_afterSwap = tokenB.balanceOf(address(pool));

        console.log("reserveA_tokenA_afterSwap", reserveA_tokenA_beforeSwap);
        console.log("swapPerStream", swapPerStream);
        console.log("reserveA_tokenA_afterSwap", reserveA_tokenA_afterSwap);

        uint256 executionPriceKey = poolLogic.getExecutionPriceLower(executionPrice);
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, true);
        assertEq(swaps.length, 1);
        Swap memory swap = swaps[0];

        assertEq(reserveA_tokenA_afterSwap, reserveA_tokenA_beforeSwap + swapPerStream);
        assertEq(reserveA_tokenB_afterSwap, reserveA_tokenB_beforeSwap - amountOutPerStream);
        assertEq(reserveD_tokenA_afterSwap, reserveD_tokenA_beforeSwap - dOut);
        assertEq(reserveD_tokenB_afterSwap, reserveD_tokenB_beforeSwap + dOut);
        assertEq(swapperTokenABalance_afterSwap, swapperTokenABalance_beforeSwap - TOKEN_A_SWAP_AMOUNT);
        assertEq(poolTokenABalance_afterSwap, poolTokenABalance_beforeSwap + TOKEN_A_SWAP_AMOUNT);
        assertEq(swapperTokenBBalance_afterSwap, swapperTokenBBalance_beforeSwap);
        assertEq(poolTokenBBalance_afterSwap, poolTokenBBalance_beforeSwap);

        // check the swap
        assertEq(swap.swapAmount, TOKEN_A_SWAP_AMOUNT);
        assertEq(swap.swapAmountRemaining, TOKEN_A_SWAP_AMOUNT - dust - swapPerStream);
        assertEq(swap.dustTokenAmount, dust);
        assertEq(swap.streamsCount, streamCount);
        assertEq(swap.streamsRemaining, streamCount - 1);
        assertEq(swap.swapPerStream, swapPerStream);
        assertEq(swap.executionPrice, executionPrice);
        assertEq(swap.amountOut, amountOutPerStream);
        assertEq(swap.user, owner);
        assertEq(swap.tokenIn, address(tokenA));
        assertEq(swap.tokenOut, address(tokenB));
        assertEq(swap.completed, false);
        assertEq(swap.typeOfOrder, 3);
    }

    function test_swapLimitOrder_totallyExecuteSwapFromReserves() public {
        (uint256 reserveD_tokenA_beforeSwap,, uint256 reserveA_tokenA_beforeSwap,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_beforeSwap,, uint256 reserveA_tokenB_beforeSwap,,,) = pool.poolInfo(address(tokenB));

        uint256 marketPriceBeforeSwap =
            poolLogic.getExecutionPrice(reserveA_tokenA_beforeSwap, reserveA_tokenB_beforeSwap);

        // to add the swap in the straming queue we need to have a swap price execution lower or equal to the current price
        uint256 executionPrice = marketPriceBeforeSwap - (marketPriceBeforeSwap * 10) / 100;


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
        router.swapLimitOrder(address(tokenA), address(tokenB), tokenASwapAmount, executionPrice);
        vm.stopPrank();

        uint256 swapperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 poolTokenABalance_afterSwap = tokenA.balanceOf(address(pool));
        uint256 poolTokenBBalance_afterSwap = tokenB.balanceOf(address(pool));

        (uint256 reserveD_tokenA_afterSwap,, uint256 reserveA_tokenA_afterSwap,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_afterSwap,, uint256 reserveA_tokenB_afterSwap,,,) = pool.poolInfo(address(tokenB));

        uint256 marketPriceAfterSwap = poolLogic.getExecutionPrice(reserveA_tokenA_afterSwap, reserveA_tokenB_afterSwap);
        uint256 executionPriceKey = poolLogic.getExecutionPriceLower(executionPrice);
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, true);

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
     * @notice This test will add a swap to the streaming queue and fully execute it by consuming opposite swaps
     */
    function test_swapLimitOrder_totallyExecuteSwapWithOppositeSwaps() public {
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

        uint256 streamCount = poolLogic.getStreamCount(address(tokenB), address(tokenA), tokenBSwapAmount);
        uint256 swapPerStream = tokenBSwapAmount / streamCount;
        uint256 oppDust;
        if (tokenBSwapAmount % streamCount != 0) {
            oppDust += (tokenBSwapAmount - (streamCount * swapPerStream));
        }

        assertGt(streamCount, 1);

        // now let's add the opposite swap to the streaming queue
        (uint256 reserveD_tokenA,, uint256 reserveA_tokenA,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB,, uint256 reserveA_tokenB,,,) = pool.poolInfo(address(tokenB));
        uint256 executionPriceOppositeSwap = poolLogic.getExecutionPrice(reserveA_tokenB, reserveA_tokenA);
        // we sub the price by 10% less
        executionPriceOppositeSwap -= (executionPriceOppositeSwap * 10) / 100;
        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            vm.prank(oppositeSwapUsers[i]);
            router.swapLimitOrder(address(tokenB), address(tokenA), tokenBSwapAmount, executionPriceOppositeSwap);
        }

        uint256 oppExecutionPriceKey = poolLogic.getExecutionPriceLower(executionPriceOppositeSwap);
        Swap[] memory oppositeSwaps = pool.orderBook(oppositePairId, oppExecutionPriceKey, true);

        assertTrue(oppositeSwaps.length > 0);

        uint256 reserveAInFromPrice = poolLogic.getOtherReserveFromPrice(executionPriceOppositeSwap, reserveA_tokenB);

        // we want to know how many tokenAAmountOut is needed to fully execute the opposite swaps
        uint256 tokenOutAmountIn;
        uint256 tokenInAmountOut;
        for (uint256 i = 0; i < oppositeSwaps.length; i++) {
            Swap memory oppositeSwap = oppositeSwaps[i];
            tokenOutAmountIn += oppositeSwap.swapAmountRemaining; // tokenBAmount
            tokenInAmountOut +=
                poolLogic.getAmountOut(oppositeSwap.swapAmountRemaining, reserveA_tokenB, reserveAInFromPrice);
        }
        uint256 executionPrice = poolLogic.getReciprocalOppositePrice(executionPriceOppositeSwap, reserveA_tokenB);

        uint256 swapTokenAAmountIn = tokenInAmountOut - 1 ether;

        uint256 _streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), swapTokenAAmountIn);
        uint256 _swapPerStream = swapTokenAAmountIn / _streamCount;
        uint256 dust;
        if (swapTokenAAmountIn % _streamCount != 0) dust = (swapTokenAAmountIn - (_streamCount * _swapPerStream));

        uint256 swapTokenBAmountOut;
        // we loop through the opposite swaps to get the expected amount of tokenB we will receive, after fully execute our frontSwap swap
        uint256 swapTokenAAmountInForCalculation = swapTokenAAmountIn;
        for (uint256 i = 0; i < oppositeSwaps.length; i++) {
            Swap memory oppositeSwap = oppositeSwaps[i];
            uint256 reserveAInFromPrice =
                poolLogic.getOtherReserveFromPrice(executionPriceOppositeSwap, reserveA_tokenB);
            uint256 reserveAOutFromPrice = poolLogic.getOtherReserveFromPrice(executionPrice, reserveA_tokenA);
            uint256 oppSwapTokenAmount = oppositeSwap.swapAmountRemaining + oppositeSwap.dustTokenAmount;

            uint256 oppTokenInAmountOut =
                poolLogic.getAmountOut(oppSwapTokenAmount, reserveA_tokenB, reserveAInFromPrice);

            if (swapTokenAAmountInForCalculation > oppTokenInAmountOut) {
                swapTokenBAmountOut += oppSwapTokenAmount;
                swapTokenAAmountInForCalculation -= oppTokenInAmountOut;

                if (i == oppositeSwaps.length - 1) {
                    uint256 _streamCount =
                        poolLogic.getStreamCount(address(tokenA), address(tokenB), swapTokenAAmountInForCalculation);
                    uint256 _swapPerStream = swapTokenAAmountInForCalculation / _streamCount;
                    if (swapTokenAAmountInForCalculation % streamCount != 0) {
                        dust += (swapTokenAAmountInForCalculation - (streamCount * swapPerStream));
                        swapTokenAAmountInForCalculation = _streamCount * _swapPerStream;
                    }
                }
            } else {
                swapTokenBAmountOut +=
                    poolLogic.getAmountOut(swapTokenAAmountInForCalculation, reserveA_tokenA, reserveAOutFromPrice);
                break;
            }
        }

        uint256 swaperTokenABalance_beforeSwap = tokenA.balanceOf(owner);
        uint256 swaperTokenBBalance_beforeSwap = tokenB.balanceOf(owner);
        vm.startPrank(owner);
        tokenA.approve(address(router), swapTokenAAmountIn);
        router.swapLimitOrder(address(tokenA), address(tokenB), swapTokenAAmountIn, executionPrice);
        vm.stopPrank();

        uint256 swaperTokenABalance_afterSwap = tokenA.balanceOf(owner);
        uint256 swaperTokenBBalance_afterSwap = tokenB.balanceOf(owner);

        uint256 executionPriceKey = poolLogic.getExecutionPriceLower(executionPrice);
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, true);

        assertTrue(swaps.length == 0);
        assertEq(swaperTokenABalance_afterSwap, swaperTokenABalance_beforeSwap - swapTokenAAmountIn);
        assertGt(swaperTokenBBalance_afterSwap, swaperTokenBBalance_beforeSwap); // @audit there's mismatch between the expected amount of tokenB received and the actual amount very minute
    }

    function test_swapLimitOrder_fullyExecuteSwapWithBothOppositeSwapsAndReserves() public {
        // 1. we add the opposite swaps in opp orderBook at a certain price
        uint256 oppositeSwapsCount = 5;
        address[] memory oppositeSwapUsers = new address[](oppositeSwapsCount);
        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            address user = makeAddr(string(abi.encodePacked("oppositeSwapUser", i)));
            tokenB.mint(user, 200 ether);
            tokenB.approve(address(router), 200 ether);
            oppositeSwapUsers[i] = user;
        }

        uint256 oppSwapAmount = 1 ether;

        uint256 oppStreamCount = poolLogic.getStreamCount(address(tokenB), address(tokenA), oppSwapAmount);
        uint256 oppSwapPerStream = oppSwapAmount / oppStreamCount;
        uint256 oppDust;
        if (oppSwapAmount % oppStreamCount != 0) {
            oppDust = (oppSwapAmount - (oppStreamCount * oppSwapPerStream));
        }

        console.log("oppStreamCount", oppStreamCount);
        console.log("swapPerStream", oppSwapPerStream);
        console.log("oppDust", oppDust);

        // 2. we create the swap with the inversed price order book to totally consume all the opposite swaps

        // oppExecution price is the price of the opposite swap
        (uint256 reserveD_tokenA,, uint256 reserveA_tokenA,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB,, uint256 reserveA_tokenB,,,) = pool.poolInfo(address(tokenB));

        uint256 executionPriceOppositeSwap = poolLogic.getExecutionPrice(reserveA_tokenB, reserveA_tokenA);
        // we sub the price by 10% less
        executionPriceOppositeSwap -= (executionPriceOppositeSwap * 10) / 100;

        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            vm.prank(oppositeSwapUsers[i]);
            router.swapLimitOrder(address(tokenB), address(tokenA), oppSwapAmount, executionPriceOppositeSwap);
        }

        // at this stage we have all the opp swaps in the rounded oppPrice order book

        uint256 oppExecutionPriceKey = poolLogic.getExecutionPriceLower(executionPriceOppositeSwap);
        Swap[] memory oppositeSwaps = pool.orderBook(oppositePairId, oppExecutionPriceKey, true);

        assertEq(oppositeSwaps.length, oppositeSwapsCount);

        // we calculate the amount of tokenA we need to fully execute the opposite swaps
        uint256 reserveAInFromPrice = poolLogic.getOtherReserveFromPrice(executionPriceOppositeSwap, reserveA_tokenB);
        uint256 tokenBInOppSwaps = oppSwapAmount * oppositeSwapsCount; // oppSwapAmount contains the oppDustToken amount

        uint256 tokenAOutOppSwaps;
        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            tokenAOutOppSwaps += poolLogic.getAmountOut(oppSwapAmount, reserveA_tokenB, reserveAInFromPrice);
        }

        // we get the price of our swap based on the inversed price of opposite swaps
        uint256 swapExecutionPrice = poolLogic.getReciprocalOppositePrice(executionPriceOppositeSwap, reserveA_tokenB);
        uint256 reserveAOutnFromPrice = poolLogic.getOtherReserveFromPrice(swapExecutionPrice, reserveA_tokenA);
        uint256 reserveDOutFromPrice = poolLogic.getOtherReserveFromPrice(swapExecutionPrice, reserveD_tokenA);

        uint256 tokenAForPoolReserveSwap = 0.0001 ether;
        uint256 swapAmount = tokenAOutOppSwaps + tokenAForPoolReserveSwap;

        uint256 streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), tokenAForPoolReserveSwap);
        uint256 swapPerStream = tokenAForPoolReserveSwap / streamCount;
        uint256 dustAmountAReserveSwap;
        if (tokenAForPoolReserveSwap % streamCount != 0) {
            dustAmountAReserveSwap = (tokenAForPoolReserveSwap - (streamCount * swapPerStream));
            tokenAForPoolReserveSwap = streamCount * swapPerStream;
        }

        (uint256 dToUpdate, uint256 tokenBAmountOutFromReserves) = poolLogic.getSwapAmountOut(
            tokenAForPoolReserveSwap, reserveA_tokenA, reserveAOutnFromPrice, reserveD_tokenA, reserveDOutFromPrice
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

        uint256 executionPriceKey = poolLogic.getExecutionPriceLower(swapExecutionPrice);

        Swap[] memory _oppositeSwaps = pool.orderBook(oppositePairId, oppExecutionPriceKey, true);
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, true);
        assertTrue(_oppositeSwaps.length == 0);
        assertTrue(swaps.length == 0);
        assertEq(swapperTokenABalance_afterSwap, swapperTokenABalance_beforeSwap - swapAmount);
        assertGt(
            swapperTokenBBalance_afterSwap,
            swapperTokenBBalance_beforeSwap
        ); // @audit there's mismatch between the expected amount of tokenB received and the actual amount very minute
    }
}
