// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IFeesLogicActions} from "./fees/IFeesLogicActions.sol";
import {IFeesLogicEvents} from "./fees/IFeesLogicEvents.sol";
import {IFeesLogicErrors} from "./fees/IFeesLogicErrors.sol";
import {IFeesLogicStates} from "./fees/IFeesLogicStates.sol";

interface IFeesLogic is IFeesLogicActions, IFeesLogicEvents, IFeesLogicErrors, IFeesLogicStates {}
