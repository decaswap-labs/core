// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IPoolActions} from "./interfaces/pool/IPoolActions.sol";
import {IPoolStates} from "./interfaces/pool/IPoolStates.sol";
import {IRouter} from "./interfaces/IRouter.sol";

contract Router is Initializable,OwnableUpgradeable, IRouter{

    address public override POOL_ADDRESS;
    IPoolActions pool;
    IPoolStates poolStates;


    function initialize(address owner, address poolAddress) public initializer {
        __Ownable_init(owner);

        POOL_ADDRESS = poolAddress;
        pool = IPoolActions(POOL_ADDRESS);
        poolStates = IPoolStates(POOL_ADDRESS);

        emit PoolAddressUpdated(address(0), POOL_ADDRESS);
    }

    function addLiquidity(address token, uint256 amount) external override {
        if(getPoolAddress(token) == address(0)) revert InvalidPool();

        if(amount == 0) revert InvalidAmount();

        pool.add(msg.sender, token, amount);

        emit LiquidityAdded(msg.sender, token, amount);
    }

    function removeLiquidity(address token, uint256 lpUnits) external override{
        if(getPoolAddress(token) == address(0)) revert InvalidPool();

        if(lpUnits == 0 || lpUnits > poolStates.userLpUnitInfo(msg.sender, token)) revert InvalidAmount();

        pool.remove(msg.sender, token, lpUnits);

        emit LiquidityRemoved(msg.sender, token, lpUnits);
    }

    function updatePoolAddress(address newPoolAddress) external override onlyOwner {
        emit PoolAddressUpdated(POOL_ADDRESS, newPoolAddress);
        POOL_ADDRESS = newPoolAddress;
        pool = IPoolActions(POOL_ADDRESS);
        poolStates = IPoolStates(POOL_ADDRESS);
    }

    function getPoolAddress(address token) internal returns(address){
        // TODO : Resolve this tuple unbundling issue
        (uint a, uint b, uint c, uint d, uint f, uint g, address tokenAddress) = poolStates.poolInfo(token);
        return tokenAddress;
    }

}