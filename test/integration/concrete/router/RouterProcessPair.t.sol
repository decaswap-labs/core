// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { RouterTest } from "./Router.t.sol";
import { IRouterErrors } from "src/interfaces/router/IRouterErrors.sol";
import { Swap, LiquidityStream } from "src/lib/SwapQueue.sol";
import { console } from "forge-std/console.sol";
import { DSMath } from "src/lib/DSMath.sol";

contract RouterTest_ProcessPair is RouterTest {
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

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////  SINGLE PRICE KEY
    // /////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    function test_router_processPair_singlePriceKey_againstPool() public {
        // 1 we need to create swaps below the current price
        uint256 currentPrice = _getCurrentPrice(address(tokenA), address(tokenB));
        uint256 executionPrice = currentPrice - 1;
        // we create 10 swaps

        uint256 swapsCount = 10;
        uint256 swapTokenAAmountIn = 100 * 10 ** tokenA.decimals();
        address[] memory swapUsers = new address[](swapsCount);
        for (uint256 i = 0; i < swapsCount; i++) {
            address user = makeAddr(string(abi.encodePacked("swapUser", i)));
            vm.startPrank(user);
            tokenA.mint(user, swapTokenAAmountIn);
            tokenA.approve(address(router), swapTokenAAmountIn);
            router.swapLimitOrder(address(tokenA), address(tokenB), swapTokenAAmountIn, executionPrice);
            vm.stopPrank();
            swapUsers[i] = user;
        }

        // 2 we need to low down the current price below the price key of the swaps order book

        uint256 swapTokenBAmountIn = 10_000 * 10 ** tokenB.decimals();
        vm.startPrank(owner);
        tokenB.approve(address(router), swapTokenBAmountIn);
        router.swapMarketOrder(address(tokenB), address(tokenA), swapTokenBAmountIn);
        vm.stopPrank();

        console.log("current price", _getCurrentPrice(address(tokenA), address(tokenB)));
        console.log("execution price", executionPrice);
        // console.log("delta", executionPrice - _getCurrentPrice(address(tokenA), address(tokenB)));

        // 3 we need to process pair of these swaps and observe that we:
        router.processPair(address(tokenA), address(tokenB)); // !!here we are exiting the processPair function because
            // poolPrice above the price key!!

        // 3.1 consumed 1 stream on each swap on the pair against the pool

        // 3.2 the higher price key should be the same as we didn't consume totally the order book
    }

    function test_router_processPair_singlePrice_againstOppositeSwaps() public {
        // 1 we create the opposite swaps

        // we get the opposite price
        uint256 currentOppositePrice = _getCurrentPrice(address(tokenB), address(tokenA));
        uint256 executionOppositePrice = currentOppositePrice - 1;

        // we insert 10 opposite swaps below the current opposite price
        uint256 oppositeSwapsCount = 10;
        uint256 swapTokenBAmountIn = 100 * 10 ** tokenB.decimals();
        address[] memory oppositeSwapUsers = new address[](oppositeSwapsCount);
        for (uint256 i = 0; i < oppositeSwapsCount; i++) {
            address user = makeAddr(string(abi.encodePacked("oppositeSwapUser", i)));
            vm.startPrank(user);
            tokenB.mint(user, swapTokenBAmountIn);
            tokenB.approve(address(router), swapTokenBAmountIn);
            router.swapLimitOrder(address(tokenB), address(tokenA), swapTokenBAmountIn, executionOppositePrice);
            vm.stopPrank();
            oppositeSwapUsers[i] = user;
        }

        uint256 currentPrice = _getCurrentPrice(address(tokenA), address(tokenB));
        uint256 executionPrice = currentPrice - 1;

        // we insert 10 opposite swaps below the current opposite price
        uint256 swapsCount = 5;
        uint256 swapTokenAAmountIn = 10 * 10 ** tokenB.decimals();
        address[] memory swapUsers = new address[](swapsCount);
        for (uint256 i = 0; i < swapsCount; i++) {
            address user = makeAddr(string(abi.encodePacked("swapUser", i)));
            vm.startPrank(user);
            tokenA.mint(user, swapTokenAAmountIn);
            tokenA.approve(address(router), swapTokenAAmountIn);
            router.swapLimitOrder(address(tokenA), address(tokenB), swapTokenAAmountIn, executionPrice);
            vm.stopPrank();
            swapUsers[i] = user;
        }

        uint256 swapMarketTokenBAmountIn = 1 * 10 ** tokenB.decimals();
        vm.startPrank(owner);
        tokenB.approve(address(router), swapMarketTokenBAmountIn);
        router.swapMarketOrder(address(tokenB), address(tokenA), swapMarketTokenBAmountIn);
        vm.stopPrank();

        uint256 priceKey = pool.highestPriceKey(pairId);
        currentPrice = _getCurrentPrice(address(tokenA), address(tokenB));
        console.log("current price", currentPrice);
        console.log("price key", priceKey);

        router.processPair(address(tokenA), address(tokenB));
    }
}
