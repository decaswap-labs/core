// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { DSMath } from "src/lib/DSMath.sol";
import { ScaleDecimals } from "src/lib/ScaleDecimals.sol";

library PoolLogicLib {
    using DSMath for uint256;
    using ScaleDecimals for uint256;

    function getExecutionPrice(
        uint256 reserveA_In,
        uint256 reserveA_Out,
        uint8 decimals_In,
        uint8 decimals_Out
    )
        public
        pure
        returns (uint256)
    {
        return reserveA_In.scaleAmountToDecimals(decimals_In, 18).wdiv(
            reserveA_Out.scaleAmountToDecimals(decimals_Out, 18)
        );
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        return (amountIn * reserveOut) / reserveIn;
    }

    function getSwapAmountOut(
        uint256 amountIn,
        uint256 reserveA_In,
        uint256 reserveA_Out,
        uint256 reserveD_In,
        uint256 reserveD_Out
    )
        public
        pure
        returns (uint256, uint256)
    {
        // d1 = a * D1 / a + A
        // return d1 -> this will be updated in the pool
        // b = d * B / d + D2 -> this will be returned to the pool

        //         10 * 1e18
        //         100000000000000000000
        //         1000000000000000000
        uint256 d1 = (amountIn * reserveD_In) / (amountIn + reserveA_In);
        return (d1, ((d1 * reserveA_Out) / (d1 + reserveD_Out)));
    }

    function getSwapAmountOutFromD(uint256 dIn, uint256 reserveA, uint256 reserveD) public pure returns (uint256) {
        return ((dIn * reserveA) / (dIn + reserveD));
    }

    function getTokenOut(uint256 dAmount, uint256 reserveA, uint256 reserveD) external pure returns (uint256) {
        return (dAmount * reserveA) / (dAmount + reserveD);
    }

    function getDOut(uint256 tokenAmount, uint256 reserveA, uint256 reserveD) external pure returns (uint256) {
        return (tokenAmount * reserveD) / (tokenAmount + reserveA);
    }

    // 0.15% will be 15 poolSlippage. 100% is 100000 units
    function calculateStreamCount(
        uint256 amountIn,
        uint256 poolSlippage,
        uint256 reserveD,
        uint256 streamCountPrecision,
        uint8 decimalsIn
    )
        public
        pure
        returns (uint256)
    {
        if (amountIn == 0) return 0;
        // streamQuantity = SwappedAmount/(globalMinSlippage * PoolDepth)

        // (10e18 * 10000) / (10000-15 * 15e18)

        uint256 scaledAmountIn = amountIn.scaleAmountToDecimals(decimalsIn, 18);

        uint256 result = ((scaledAmountIn * streamCountPrecision) / (((streamCountPrecision - poolSlippage) * reserveD)));
        return result < 1 ? 1 : result;
    }

    function calculateAssetTransfer(
        uint256 lpUnits,
        uint256 reserveA,
        uint256 totalLpUnits
    )
        public
        pure
        returns (uint256)
    {
        return (reserveA.wmul(lpUnits)).wdiv(totalLpUnits);
    }

    function calculateDToDeduct(
        uint256 lpUnits,
        uint256 reserveD,
        uint256 totalLpUnits
    )
        public
        pure
        returns (uint256)
    {
        return reserveD.wmul(lpUnits).wdiv(totalLpUnits);
    }

    function getPoolId(address tokenA, address tokenB) public pure returns (bytes32) {
        (address A, address B) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(A, B));
    }

    function calculateLpUnitsToMint(
        uint256 lpUnitsDepth, // P => depth of lpUnits
        uint256 amount, // a => assets incoming
        uint256 reserveA, // A => assets depth
        uint256 dIncoming, // d
        uint256 dUnitsDepth // D => depth of dUnits
    )
        public
        pure
        returns (uint256)
    {
        // p = P * (dA + Da + 2da)/(dA + Da + 2DA)
        if (lpUnitsDepth == 0 && dIncoming == 0) {
            return amount;
        } else if (lpUnitsDepth == 0 && amount == 0) {
            return dIncoming;
        }

        uint256 num = (dIncoming * reserveA) + (dUnitsDepth * amount) + (2 * dIncoming * amount);
        uint256 den = (dIncoming * reserveA) + (dUnitsDepth * amount) + (2 * dUnitsDepth * reserveA);

        return lpUnitsDepth * (num / den);
    }

    function calculateDUnitsToMint(
        uint256 amount,
        uint256 reserveA,
        uint256 reserveD,
        uint256 initialDToMint
    )
        public
        pure
        returns (uint256)
    {
        if (reserveD == 0) {
            return initialDToMint;
        }

        return reserveD.wmul(amount).wdiv(reserveA);
    }

    function getExecutionPriceLower(uint256 executionPrice, uint256 pricePrecision) public pure returns (uint256) {
        uint256 mod = executionPrice % pricePrecision; // @audit decide decimals for precission + use global variable
            // for precission
        return executionPrice - mod;
    }

    function getReciprocalOppositePrice(
        uint256 executionPrice,
        uint256 reserveA_In,
        uint8 decimals_In,
        uint8 decimals_Out
    )
        public
        pure
        returns (uint256)
    {
        uint256 reserveA_Out = getOtherReserveFromPrice(executionPrice, reserveA_In, decimals_In, decimals_Out);
        return getExecutionPrice(reserveA_Out, reserveA_In, decimals_Out, decimals_In);
    }

    function getOtherReserveFromPrice(
        uint256 executionPrice,
        uint256 reserveA_In,
        uint8 decimals_In,
        uint8 decimals_Out
    )
        public
        pure
        returns (uint256)
    {
        return (reserveA_In.scaleAmountToDecimals(decimals_In, 18).wdiv(executionPrice)).scaleAmountToDecimals(
            18, decimals_Out
        ); // @audit confirm scaling
    }

    function calculateAmountOutFromPrice(
        uint256 amountIn,
        uint256 price,
        uint8 decimalsIn,
        uint8 decimalsOut
    )
        public
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

    /// @notice Calculate the TokenIn amount given TokenOut amount, price, and decimals.
    /// @param tokenAmountOut The amount of TokenOut given.
    /// @param price The price (TokenIn / TokenOut), scaled to 18 decimals.
    /// @param decimalsIn Decimals of TokenIn.
    /// @param decimalsOut Decimals of TokenOut.
    /// @return tokenAmountIn The equivalent amount of TokenIn.
    function calculateAmountInFromPrice(
        uint256 tokenAmountOut,
        uint256 price,
        uint8 decimalsIn,
        uint8 decimalsOut
    )
        public
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
