// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ILiquidityLogicActions} from "./liquidity-logic/ILiquidityLogicActions.sol";
import {ILiquidityLogicErrors} from "./liquidity-logic/ILiquidityLogicErrors.sol";

interface ILiquidityLogic is ILiquidityLogicActions, ILiquidityLogicErrors {}
