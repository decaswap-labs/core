// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPoolActions} from "./pool/IPoolActions.sol";
import {IPoolStates} from "./pool/IPoolStates.sol";
import {IPoolEvents} from "./pool/IPoolEvents.sol";
import {IPoolErrors} from "./pool/IPoolErrors.sol";

interface IPool is IPoolActions, IPoolStates, IPoolEvents, IPoolErrors {}
