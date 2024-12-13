// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RouterTest} from "./Router.t.sol";
import {IRouterErrors} from "src/interfaces/router/IRouterErrors.sol";
import {Swap, LiquidityStream} from "src/lib/SwapQueue.sol";
import {console} from "forge-std/console.sol";
import {DSMath} from "src/lib/DSMath.sol";

contract RouterTest_ProcessPair is RouterTest {
    using DSMath for uint256;

    uint256 private TOKEN_A_SWAP_AMOUNT = 30 ether;
    uint256 private TOKEN_B_SWAP_AMOUNT = 30 ether;
    bytes32 pairId;
    bytes32 oppositePairId;
    address private invalidPool = makeAddr("invalidPool");

    function setUp() public virtual override {
        super.setUp();
        pairId = bytes32(abi.encodePacked(address(tokenA), address(tokenB)));
        oppositePairId = bytes32(abi.encodePacked(address(tokenB), address(tokenA)));
    }

    function testRevert_router_processPair_whenSamePool() public {
        vm.expectRevert(IRouterErrors.SamePool.selector);
        router.processPair(address(tokenA), address(tokenA));
    }

    function testRevert_router_processPair_whenInvalidPool() public {
        vm.expectRevert(IRouterErrors.InvalidPool.selector);
        router.processPair(address(invalidPool), address(tokenA));
    }

    ///////////////////////////////  SINGLE PRICE KEY  ///////////////////////////////

    //swaps at priceKey directly stream with pool as no opp swaps found
    function test_router_processPair_swapsStreamWithPool() public {
        uint8 deltaCount = 2;
        uint8 orderBookCount = 5;
        // first we creating swaps above the current price...
        // swaps will be stream with pool and the rest will be added to the price key order book

        // 1. get the current price
        (,, uint256 reserveA_tokenA_beforeSwap,,,) = pool.poolInfo(address(tokenA));
        (,, uint256 reserveA_tokenB_beforeSwap,,,) = pool.poolInfo(address(tokenB));

        uint256 marketPriceBeforeSwap =
            poolLogic.getExecutionPrice(reserveA_tokenA_beforeSwap, reserveA_tokenB_beforeSwap);

        console.log("executionPriceBeforeSwap", marketPriceBeforeSwap);

        // 2. create swaps above the current price but not more than 50 * PRICE_PRECISION

        uint256 executionPrice = marketPriceBeforeSwap + poolLogic.MAX_LIMIT_TICKS() * poolLogic.PRICE_PRECISION();
        uint256 executionPriceStart = executionPrice;

        // for (uint256 j = 0; j < orderBookCount; j++) {
        for (uint256 i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("swapUser", i)));
            vm.startPrank(user);
            tokenA.mint(user, TOKEN_A_SWAP_AMOUNT * 2);
            tokenA.approve(address(router), TOKEN_A_SWAP_AMOUNT * 2);
            router.swapLimitOrder(address(tokenA), address(tokenB), TOKEN_A_SWAP_AMOUNT, executionPrice);
            vm.stopPrank();
        }
        //     executionPrice -= deltaCount * poolLogic.PRICE_PRECISION();
        // }

        (,, uint256 reserveA_tokenA_afterSwap,,,) = pool.poolInfo(address(tokenA));
        (,, uint256 reserveA_tokenB_afterSwap,,,) = pool.poolInfo(address(tokenB));

        uint256 marketPriceAfterSwap = poolLogic.getExecutionPrice(reserveA_tokenA_afterSwap, reserveA_tokenB_afterSwap);

        console.log("marketPriceAfterSwap", marketPriceAfterSwap);
        // console.log("% price:", ((marketPriceAfterSwap - marketPriceBeforeSwap) * 100).wdiv(marketPriceBeforeSwap));

        // 3. we get the actual order book for the price key to get the swap details
        uint256 priceKey = poolLogic.getExecutionPriceLower(executionPriceStart);
        Swap[] memory swaps = pool.orderBook(pairId, priceKey, true);
        // Swap memory swap = swaps[0];
        // uint256 streamsRemainingBF = swap.streamsRemaining;
        // uint256 swapIdBF = swap.swapID;

        // 4. process the pair
        router.processPair(address(tokenA), address(tokenB));

        // 5. get the actual order book for the price key to get the swap details
        // swaps = pool.orderBook(pairId, priceKey, true);
        // swap = swaps[0];
        // uint256 streamsRemainingAF = swap.streamsRemaining;
        // uint256 swapIdAF = swap.swapID;

        // assertEq(swapIdBF, swapIdAF, "swapIdBF != swapIdAF");
        // assertEq(streamsRemainingAF, streamsRemainingBF - 1, "streamsCountAF != streamsCountBF");
    }

    //swaps at priceKey get consumed by opp swaps
    function test_router_processPair_swapsGetConsumedByOppSwaps() public {
        uint8 deltaCount = 3;
        uint8 orderBookCount = 5;
        // if it is the case it means that at the result of the processSwap, the price key order book will be empty

        (,, uint256 reserveA_tokenA,,,) = pool.poolInfo(address(tokenA));
        (,, uint256 reserveA_tokenB,,,) = pool.poolInfo(address(tokenB));

        uint256 marketBtoAPriceBeforeSwap = poolLogic.getExecutionPrice(reserveA_tokenB, reserveA_tokenA);

        console.log("BtoAexecutionPriceBeforeSwap", marketBtoAPriceBeforeSwap);

        // create swaps below the current price
        // these swaps will be stright added to the BtoA price key order book
        uint256 executionPriceBtoA = marketBtoAPriceBeforeSwap - (marketBtoAPriceBeforeSwap * 10) / 100;

        uint256 oppPriceKey = poolLogic.getExecutionPriceLower(executionPriceBtoA);
        console.log("oppPriceKey", oppPriceKey);

        uint256 marketAtoBPriceBeforeSwap = poolLogic.getExecutionPrice(reserveA_tokenA, reserveA_tokenB);

        // get the inverse BtoA price to get the wanted AtoB price
        uint256 executionPriceAtoB = poolLogic.getReciprocalOppositePrice(executionPriceBtoA, reserveA_tokenB);

        assertTrue(executionPriceAtoB > marketAtoBPriceBeforeSwap, "executionPriceAtoB <= marketAtoBPriceBeforeSwap");

        address swaper = makeAddr("swaper");
        vm.startPrank(swaper);
        tokenA.mint(swaper, TOKEN_A_SWAP_AMOUNT);
        tokenA.approve(address(router), TOKEN_A_SWAP_AMOUNT);
        router.swapLimitOrder(address(tokenA), address(tokenB), TOKEN_A_SWAP_AMOUNT, executionPriceAtoB);
        vm.stopPrank();

        for (uint256 i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("oppositeSwapUser", i)));
            vm.startPrank(user);
            tokenB.mint(user, TOKEN_B_SWAP_AMOUNT * 100);
            tokenB.approve(address(router), TOKEN_B_SWAP_AMOUNT * 100);
            router.swapLimitOrder(address(tokenB), address(tokenA), TOKEN_B_SWAP_AMOUNT * 100, executionPriceBtoA);
            vm.stopPrank();
        }

        (,, reserveA_tokenA,,,) = pool.poolInfo(address(tokenA));
        (,, reserveA_tokenB,,,) = pool.poolInfo(address(tokenB));

        router.processPair(address(tokenA), address(tokenB));

        uint256 priceKey = poolLogic.getExecutionPriceLower(executionPriceAtoB);
        Swap[] memory swaps = pool.orderBook(pairId, priceKey, true);
        Swap[] memory oppSwaps = pool.orderBook(oppositePairId, oppPriceKey, true);

        assertTrue(swaps.length == 0, "swaps.length != 0");
        assertTrue(oppSwaps.length > 0, "oppSwaps.length == 0");
    }

    //swaps at priceKey consumes opp swaps and stream with pool
    function test_router_processPair_swapsConsumeOppSwapsAndGetStreamed() public {
        (,, uint256 reserveA_tokenA,,,) = pool.poolInfo(address(tokenA));
        (,, uint256 reserveA_tokenB,,,) = pool.poolInfo(address(tokenB));

        uint256 marketBtoAPriceBeforeSwap = poolLogic.getExecutionPrice(reserveA_tokenB, reserveA_tokenA);

        console.log("BtoAexecutionPriceBeforeSwap", marketBtoAPriceBeforeSwap);

        // create swaps below the current price
        // these swaps will be stright added to the BtoA price key order book
        uint256 executionPriceBtoA = marketBtoAPriceBeforeSwap - (marketBtoAPriceBeforeSwap * 10) / 100;

        uint256 oppPriceKey = poolLogic.getExecutionPriceLower(executionPriceBtoA);
        console.log("oppPriceKey", oppPriceKey);

        uint256 marketAtoBPriceBeforeSwap = poolLogic.getExecutionPrice(reserveA_tokenA, reserveA_tokenB);

        // get the inverse BtoA price to get the wanted AtoB price
        uint256 executionPriceAtoB = poolLogic.getReciprocalOppositePrice(executionPriceBtoA, reserveA_tokenB);

        assertTrue(executionPriceAtoB > marketAtoBPriceBeforeSwap, "executionPriceAtoB <= marketAtoBPriceBeforeSwap");

        address swaper = makeAddr("swaper");
        vm.startPrank(swaper);
        tokenA.mint(swaper, TOKEN_A_SWAP_AMOUNT * 1000);
        tokenA.approve(address(router), TOKEN_A_SWAP_AMOUNT * 1000);
        router.swapLimitOrder(address(tokenA), address(tokenB), TOKEN_A_SWAP_AMOUNT * 1000, executionPriceAtoB);
        vm.stopPrank();

        for (uint256 i = 0; i < 5; i++) {
            address user = makeAddr(string(abi.encodePacked("oppositeSwapUser", i)));
            vm.startPrank(user);
            tokenB.mint(user, TOKEN_A_SWAP_AMOUNT);
            tokenB.approve(address(router), TOKEN_A_SWAP_AMOUNT);
            router.swapLimitOrder(address(tokenB), address(tokenA), TOKEN_A_SWAP_AMOUNT, executionPriceBtoA);
            vm.stopPrank();
        }

        (,, reserveA_tokenA,,,) = pool.poolInfo(address(tokenA));
        (,, reserveA_tokenB,,,) = pool.poolInfo(address(tokenB));

        router.processPair(address(tokenA), address(tokenB));

        uint256 priceKey = poolLogic.getExecutionPriceLower(executionPriceAtoB);
        Swap[] memory swaps = pool.orderBook(pairId, priceKey, true);
        Swap[] memory oppSwaps = pool.orderBook(oppositePairId, oppPriceKey, true);

        assertTrue(swaps.length > 0, "swaps.length == 0");
        assertTrue(oppSwaps.length == 0, "oppSwaps.length >= 0");
    }
}
