// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {DSMath} from "./DSMath.sol";

library PoolLogicLib {
    using DSMath for uint256;

    uint256 public constant PRICE_PRECISION = 1_000_000_000;
    uint256 public constant STREAM_COUNT_PRECISION = 10_000;

    function getExecutionPrice(uint256 reserveA1, uint256 reserveA2) public pure  returns (uint256) {
        return reserveA1.wdiv(reserveA2);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        return amountIn.wmul(reserveIn).wdiv(reserveOut);
    }

    function getSwapAmountOut(
        uint256 amountIn,
        uint256 reserveA,
        uint256 reserveB,
        uint256 reserveD1,
        uint256 reserveD2
    ) public pure returns (uint256, uint256) {
        // d1 = a * D1 / a + A
        // return d1 -> this will be updated in the pool
        // b = d * B / d + D2 -> this will be returned to the pool

        //         10 * 1e18
        //         100000000000000000000
        //         1000000000000000000
        uint256 d1 = (amountIn.wmul(reserveD1)).wdiv(amountIn + reserveA);
        return (d1, ((d1 * reserveB) / (d1 + reserveD2)));
    }

    function getSwapAmountOutFromD(uint256 dIn, uint256 reserveA, uint256 reserveD) public pure returns (uint256) {
        return ((dIn * reserveA) / (dIn + reserveD));
    }

    function getTokenOut(uint256 dAmount, uint256 reserveA, uint256 reserveD)
        external
        pure
        returns (uint256)
    {
        return (dAmount.wmul(reserveA)).wdiv(dAmount + reserveD);
    }

    function getDOut(uint256 tokenAmount, uint256 reserveA, uint256 reserveD)
        external
        pure
        returns (uint256)
    {
        return (tokenAmount.wmul(reserveD)).wdiv(tokenAmount + reserveA);
    }

      // 0.15% will be 15 poolSlippage. 100% is 100000 units
    function calculateStreamCount(uint256 amount, uint256 poolSlippage, uint256 reserveD)
        public
        pure
        returns (uint256)
    {
        if (amount == 0) return 0;
        // streamQuantity = SwappedAmount/(globalMinSlippage * PoolDepth)

        // (10e18 * 10000) / (10000-15 * 15e18)

        uint256 result = ((amount * STREAM_COUNT_PRECISION) / (((STREAM_COUNT_PRECISION - poolSlippage) * reserveD)));
        return result < 1 ? 1 : result;
    }

    function calculateAssetTransfer(uint256 lpUnits, uint256 reserveA, uint256 totalLpUnits)
        public
        pure
        returns (uint256)
    {
        return (reserveA.wmul(lpUnits)).wdiv(totalLpUnits);
    }

    function calculateDToDeduct(uint256 lpUnits, uint256 reserveD, uint256 totalLpUnits)
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
    ) public pure returns (uint256) {
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

    function calculateDUnitsToMint(uint256 amount, uint256 reserveA, uint256 reserveD, uint256 initialDToMint)
        public
        pure
        returns (uint256)
    {
        if (reserveD == 0) {
            return initialDToMint;
        }

        return reserveD.wmul(amount).wdiv(reserveA);
    }

    function getExecutionPriceLower(uint256 executionPrice) public pure returns (uint256) {
        uint256 mod = executionPrice % PRICE_PRECISION; // @audit decide decimals for precission + use global variable for precission
        return executionPrice - mod;
    }

    function getReciprocalOppositePrice(uint256 executionPrice, uint256 reserveA) public pure returns (uint256) {
        // and divide rB/rA;
        uint256 reserveB = getOtherReserveFromPrice(executionPrice, reserveA); // @audit confirm scaling
        return getExecutionPrice(reserveB, reserveA); // @audit returned price needs to go in getExecutionPriceLower() ??
    }

    function getOtherReserveFromPrice(uint256 executionPrice, uint256 reserveA) public pure returns (uint256) {
        return reserveA.wdiv(executionPrice); // @audit confirm scaling
    }


}