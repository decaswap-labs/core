// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { RouterTest } from "./Router.t.sol";
import { IRouterErrors } from "src/interfaces/router/IRouterErrors.sol";
import { Swap, LiquidityStream } from "src/lib/SwapQueue.sol";
import { console } from "forge-std/console.sol";
import { DSMath } from "src/lib/DSMath.sol";

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

    function test_swapMarketOrder_success() public {
        vm.startPrank(owner);
        // Get initial pool reserves
        (uint256 reserveD_tokenA_before,, uint256 reserveA_tokenA_before,,,, uint8 decimals_A) =
            pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_before,, uint256 reserveA_tokenB_before,,,, uint8 decimals_B) =
            pool.poolInfo(address(tokenB));

        // Setup initial conditions for the market order
        uint256 initialBalanceTokenA = tokenA.balanceOf(owner);
        uint256 initialBalanceTokenB = tokenB.balanceOf(owner);
        uint256 swapAmount = 10 ether;
        uint256 expectedExecutionPrice =
            poolLogic.getExecutionPrice(reserveA_tokenA_before, reserveA_tokenB_before, decimals_A, decimals_B);

        // Calculate expected stream details
        uint256 streamCount = poolLogic.getStreamCount(address(tokenA), address(tokenB), swapAmount);
        uint256 swapPerStream = swapAmount / streamCount;
        uint256 dust = 0;
        if (swapAmount % streamCount != 0) {
            dust = swapAmount - (streamCount * swapPerStream);
        }

        (uint256 dOut, uint256 aOut) = poolLogic.getSwapAmountOut(
            swapPerStream,
            reserveA_tokenA_before,
            reserveA_tokenB_before,
            reserveD_tokenA_before,
            reserveD_tokenB_before
        );

        // Approve the router to spend tokenA
        tokenA.approve(address(router), swapAmount);

        // Call the swapMarketOrder function
        router.swapMarketOrder(address(tokenA), address(tokenB), swapAmount);

        // Get final pool reserves
        (uint256 reserveD_tokenA_after,, uint256 reserveA_tokenA_after,,,,) = pool.poolInfo(address(tokenA));
        (uint256 reserveD_tokenB_after,, uint256 reserveA_tokenB_after,,,,) = pool.poolInfo(address(tokenB));
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
}
