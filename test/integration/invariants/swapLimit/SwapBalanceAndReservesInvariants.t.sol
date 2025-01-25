// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Deploys } from "test/shared/Deploys.t.sol";
import { SwapLimitHandlerTest } from "test/integration/invariants/swapLimit/SwapLimitHandler.t.sol";
import { console } from "forge-std/Test.sol";

contract SwapBalanceAndReservesInvariantsTest is Deploys {
    SwapLimitHandlerTest public handler;

    function setUp() public virtual override {
        super.setUp();
        handler = new SwapLimitHandlerTest(router, tokenA, tokenB, owner);
        targetContract(address(handler));
    }

    function invariant_BalanceAlwaysGEReserves() public view {
        uint256 poolBalanceTokenA = tokenA.balanceOf(address(handler.pool()));
        uint256 poolBalanceTokenB = tokenB.balanceOf(address(handler.pool()));
        (,, uint256 poolReserveTokenA,,,,) = handler.pool().poolInfo(address(tokenA));
        (,, uint256 poolReserveTokenB,,,,) = handler.pool().poolInfo(address(tokenB));

        assertGe(poolBalanceTokenA, poolReserveTokenA);
        assertGe(poolBalanceTokenB, poolReserveTokenB);
    }
}
