// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library ScaleDecimals {
    /// @notice Scale the amount to the target decimals.
    /// @param amount The amount to scale.
    /// @param fromDecimals The decimals of the amount.
    /// @param toDecimals The target decimals.
    function scaleAmountToDecimals(uint256 amount, uint8 fromDecimals, uint8 toDecimals)
        internal
        pure
        returns (uint256)
    {
        if (fromDecimals == toDecimals) return amount;
        if (fromDecimals > toDecimals) return amount / (10 ** (fromDecimals - toDecimals));
        return amount * (10 ** (18 - fromDecimals));
    }
}
