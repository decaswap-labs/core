// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {RouterTest} from "./Router.t.sol";
import {IRouterErrors} from "src/interfaces/router/IRouterErrors.sol";
import {Swap, LiquidityStream} from "src/lib/SwapQueue.sol";
import {console} from "forge-std/console.sol";
import {DSMath} from "src/lib/DSMath.sol";

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
}
