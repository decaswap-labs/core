// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Deploys} from "test/shared/Deploys.t.sol";
import {Handler} from "test/integration/invariants/Handler.t.sol";
import {console} from "forge-std/Test.sol";

contract SwapBalanceAndReservesInvariantsTest is Deploys {
    Handler public handler;

    function setUp() public virtual override {
        super.setUp();
        handler = new Handler(router, tokenA, tokenB, owner);
        targetContract(address(handler));
    }

    function invariant_BalanceAAlwaysGEReservesA() public view {
        uint256 poolBalanceTokenA = tokenA.balanceOf(address(handler.pool()));
        (,, uint256 poolReserveTokenA,,,,,) = handler.pool().poolInfo(address(tokenA));

        assertGe(poolBalanceTokenA, poolReserveTokenA);
    }

    function invariant_BalanceBAlwaysGEReservesB() public view {
        uint256 poolBalanceTokenB = tokenB.balanceOf(address(handler.pool()));
        (,, uint256 poolReserveTokenB,,,,,) = handler.pool().poolInfo(address(tokenB));
        console.log("poolBalanceTokenB", poolBalanceTokenB);

        assertGe(poolBalanceTokenB, poolReserveTokenB);
    }
}
