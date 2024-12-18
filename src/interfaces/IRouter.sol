// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { IRouterActions } from "./router/IRouterActions.sol";
import { IRouterEvents } from "./router/IRouterEvents.sol";
import { IRouterErrors } from "./router/IRouterErrors.sol";
import { IRouterStates } from "./router/IRouterStates.sol";

interface IRouter is IRouterActions, IRouterStates, IRouterEvents, IRouterErrors { }
