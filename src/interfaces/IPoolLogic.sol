// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IPoolLogicActions } from "./pool-logic/IPoolLogicActions.sol";
import { IPoolLogicEvents } from "./pool-logic/IPoolLogicEvents.sol";
import { IPoolLogicErrors } from "./pool-logic/IPoolLogicErrors.sol";
import { IPoolLogicStates } from "./pool-logic/IPoolLogicStates.sol";

interface IPoolLogic is IPoolLogicActions, IPoolLogicEvents, IPoolLogicErrors, IPoolLogicStates { }
