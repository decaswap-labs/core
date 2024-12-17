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

    function test_swapTriggerOrder_success() public {
        vm.startPrank(owner);
        // Get initial pool reserves
        (uint256 reserveD_tokenA_before,, uint256 reserveA_tokenA_before,,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_before,, uint256 reserveA_tokenB_before,,,,) = pool.poolInfo(address(tokenB));

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
}
