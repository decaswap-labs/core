// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.13;

import { Test, console } from "forge-std/Test.sol";
import { Router } from "src/Router.sol";
import { PoolLogic } from "src/PoolLogic.sol";
import { Pool } from "src/Pool.sol";
import { MockERC20 } from "src/MockERC20.sol";
import { PoolLogicLib } from "src/lib/PoolLogicLib.sol";
import { console } from "forge-std/Test.sol";

contract Handler is Test {
    Router public router;
    PoolLogic public poolLogic;
    Pool public pool;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    address public owner;

    uint96 public constant MAX_DEPOSIT_SIZE = 10_000 ether;

    constructor(Router _router, MockERC20 _tokenA, MockERC20 _tokenB, address _owner) {
        router = _router;
        poolLogic = PoolLogic(router.poolStates().POOL_LOGIC());
        pool = Pool(router.POOL_ADDRESS());
        tokenA = _tokenA;
        tokenB = _tokenB;
        owner = _owner;

        vm.startPrank(owner);

        uint256 initialDToMintPoolA = 10 ether;
        uint256 SLIPPAGE = 10;

        uint256 tokenAAmount = 500_000 ether;
        uint256 tokenBAmount = 1_000_000 ether;

        router.initGenesisPool(address(tokenA), tokenAAmount, initialDToMintPoolA);

        router.initPool(address(tokenB), address(tokenA), tokenBAmount, tokenAAmount);

        // update pair slippage
        pool.updatePairSlippage(address(tokenA), address(tokenB), SLIPPAGE);

        vm.stopPrank();
    }

    function swap(uint256 seed, uint256 amountIn) public {
        MockERC20 tokenIn = _getTokenFromSeed(seed);
        MockERC20 tokenOut = tokenIn == tokenA ? tokenB : tokenA;
        amountIn = bound(amountIn, 1, MAX_DEPOSIT_SIZE);
        uint256 executionPrice = _getCurrentPrice(address(tokenIn), address(tokenOut));
        uint256 executionpriceDelta = bound(seed, 1, executionPrice / 10);
        bool addDelta = _getBoolFromSeed(seed);
        executionPrice = addDelta ? executionPrice + executionpriceDelta : executionPrice - executionpriceDelta;

        vm.startPrank(msg.sender);
        tokenIn.mint(msg.sender, amountIn);
        tokenIn.approve(address(router), amountIn);

        router.swapLimitOrder(address(tokenIn), address(tokenOut), amountIn, executionPrice);

        vm.stopPrank();
    }

    function _getTokenFromSeed(uint256 collateralSeed) private view returns (MockERC20) {
        if (collateralSeed % 2 == 0) {
            return tokenA;
        } else {
            return tokenB;
        }
    }

    function _getBoolFromSeed(uint256 seed) private pure returns (bool) {
        return seed % 2 == 0;
    }

    function _getCurrentPrice(address tokenIn, address tokenOut) private view returns (uint256) {
        (,, uint256 reserveIn,,,, uint8 decimalsIn) = pool.poolInfo(tokenIn);
        (,, uint256 reserveOut,,,, uint8 decimalsOut) = pool.poolInfo(tokenOut);
        return PoolLogicLib.getExecutionPrice(reserveIn, reserveOut, decimalsIn, decimalsOut);
    }
}
