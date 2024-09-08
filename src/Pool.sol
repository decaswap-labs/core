// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPool} from "./interfaces/IPool.sol";

contract Pool is IPool{
   address immutable VAULT_ADDRESS = address(0);
   address immutable ROUTER_ADDRESS = address(0);

    struct PoolInfo {
        uint256 dTotal;
        uint256 lpUnitsGlobal;
        uint256 reserveA;
        uint256 poolSlippage;
        uint256 minLaunchBalance;
        uint256 poolFeeCollected;
        address tokenAddress;    
    }

    struct User {
        address userAddress;
        uint256 lpUnits;
    }

    mapping(address => PoolInfo) public override poolInfo;
    mapping(address => mapping(address=>User)) public override userInfo;

    modifier onlyRouter(){
        if(msg.sender != ROUTER_ADDRESS) revert NotRouter(msg.sender);
        _;
    }

    constructor(address vaultAddress, address routerAddress) public {
        VAULT_ADDRESS = vaultAddress;
        ROUTER_ADDRESS = routerAddress;
    }


    function createPool(address token, uint256 minLaunchBalance, uint256 dBalance) external override onlyOwner {
        emit PoolCreated();
    }

    function disablePool(address token) external override onlyOwner{

    }

    function add(token, amount) external override onlyRouter {
        emit LiquidityAdded();
    }

    function remove(token, lpUnits) external override onlyRouter {
        emit LiquidityRemoved();
    }
}
