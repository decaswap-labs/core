// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract Utils {
    function getOwnableUnauthorizedAccountSelector() public pure returns (bytes4) {
        return bytes4(keccak256("OwnableUnauthorizedAccount(address)"));
    }

    function getNotPoolLogicSelector() public pure returns (bytes4) {
        return bytes4(keccak256("NotPoolLogic(address)"));
    }

    function getNotRouterLogicSelector() public pure returns (bytes4) {
        return bytes4(keccak256("NotRouter(address)"));
    }
}
