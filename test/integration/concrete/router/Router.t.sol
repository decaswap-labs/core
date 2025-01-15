// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { DSMath } from "src/lib/DSMath.sol";
import { PoolLogicLib } from "src/lib/PoolLogicLib.sol";

import { Deploys } from "test/shared/Deploys.t.sol";

contract RouterTest is Deploys {
    function setUp() public virtual override {
        super.setUp();
        _createPools();
    }

    function _createPools() internal {
        vm.startPrank(owner);

        uint256 initialDToMintPoolA = 30e18;
        uint256 SLIPPAGE = 10;

        uint256 tokenAAmount = 10_000 * 10 ** tokenA.decimals();
        uint256 tokenBAmount = 10_000 * 10 ** tokenB.decimals();

        router.initGenesisPool(address(tokenA), tokenAAmount, initialDToMintPoolA);

        router.initPool(address(tokenB), address(tokenA), tokenBAmount, 10 * 10 ** tokenA.decimals());

        //         // update pair slippage
        pool.updatePairSlippage(address(tokenA), address(tokenB), SLIPPAGE);

        vm.stopPrank();
    }

    function _getCurrentPrice(address tokenIn, address tokenOut) internal view returns (uint256) {
        (,, uint256 reserveIn,,,, uint8 decimalsIn) = pool.poolInfo(tokenIn);
        (,, uint256 reserveOut,,,, uint8 decimalsOut) = pool.poolInfo(tokenOut);
        return PoolLogicLib.getExecutionPrice(reserveIn, reserveOut, decimalsIn, decimalsOut);
    }
}
