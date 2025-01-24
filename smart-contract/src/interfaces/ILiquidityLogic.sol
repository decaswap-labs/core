// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ILiquidityLogicActions } from "./liquidity-logic/ILiquidityLogicActions.sol";
import { ILiquidityLogicErrors } from "./liquidity-logic/ILiquidityLogicErrors.sol";
import { ILiquidityLogicStates } from "./liquidity-logic/ILiquidityLogicStates.sol";
import { ILiquidityLogicEvents } from "./liquidity-logic/ILiquidityLogicEvents.sol";

interface ILiquidityLogic is
    ILiquidityLogicActions,
    ILiquidityLogicErrors,
    ILiquidityLogicStates,
    ILiquidityLogicEvents
{ }
