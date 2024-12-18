// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {DSMath} from "src/lib/DSMath.sol";
import {ScaleDecimals} from "src/lib/ScaleDecimals.sol";

import {Deploys} from "test/shared/Deploys.t.sol";

contract RouterTest is Deploys {
    using DSMath for uint256;
    using ScaleDecimals for uint256;

    function setUp() public virtual override {
        super.setUp();
        _createPools();
    }

    function _createPools() internal {
        vm.startPrank(owner);

        uint256 initialDToMintPoolA = 30e18;
        uint256 SLIPPAGE = 10;

        uint256 tokenAAmount = 10_000e18;
        uint256 tokenBAmount = 10_000e18;

        router.initGenesisPool(address(tokenA), tokenAAmount, initialDToMintPoolA);

        router.initPool(address(tokenB), address(tokenA), tokenBAmount, 10 ether);

        // update pair slippage
        pool.updatePairSlippage(address(tokenA), address(tokenB), SLIPPAGE);

        vm.stopPrank();
    }

    function _calculateAmountOutFromPrice(uint256 amountIn, uint256 price, uint8 decimalsIn, uint8 decimalsOut)
        internal
        pure
        returns (uint256)
    {
        require(price > 0, "Price must be greater than 0");

        // Scale amountA to 18 decimals
        uint256 scaledAmountIn = amountIn.scaleAmountToDecimals(decimalsIn, 18);

        // Calculate AmountB: amountB = scaledAmountA / price
        uint256 scaledAmountOut = scaledAmountIn.wdiv(price);

        // Scale back to target decimals
        return scaledAmountOut.scaleAmountToDecimals(18, decimalsOut);
    }

    /// @notice Calculate the TokenA amount given TokenB amount, price, and decimals.
    /// @param tokenAmountOut The amount of TokenB.
    /// @param price The price (TokenA / TokenB), scaled to 18 decimals.
    /// @param decimalsIn Decimals of TokenA.
    /// @param decimalsOut Decimals of TokenB.
    /// @return tokenAmountIn The equivalent amount of TokenA.
    function _calculateAmountInFromPrice(uint256 tokenAmountOut, uint256 price, uint8 decimalsIn, uint8 decimalsOut)
        internal
        pure
        returns (uint256)
    {
        require(price > 0, "Price must be greater than 0");

        // Scale tokenAmountB to 18 decimals
        uint256 scaledAmountOut = tokenAmountOut.scaleAmountToDecimals(decimalsOut, 18);

        // Calculate TokenA amount: tokenAmountIn = scaledAmountOut * price
        uint256 scaledAmountIn = scaledAmountOut.wmul(price);

        // Scale back to TokenA decimals
        return scaledAmountIn.scaleAmountToDecimals(18, decimalsIn);
    }
}
