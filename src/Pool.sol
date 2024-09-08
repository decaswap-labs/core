// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPool} from "./interfaces/IPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Pool is IPool, Ownable{
   address immutable VAULT_ADDRESS = address(0);
   address immutable ROUTER_ADDRESS = address(0);
   uint256 public constant DECIMAL = 18;

    struct PoolInfo {
        uint256 dTotal;
        uint256 lpUnitsGlobal;
        uint256 reserveA;
        uint256 poolSlippage;
        uint256 minLaunchBalance;
        uint256 poolFeeCollected;
        address tokenAddress;    
    }

    mapping(address => PoolInfo) public override poolInfo;
    mapping(address => mapping(address=>uint256)) public override userLpUnitInfo;

    modifier onlyRouter(){
        if(msg.sender != ROUTER_ADDRESS) revert NotRouter(msg.sender);
        _;
    }

    constructor(address vaultAddress, address routerAddress) Ownable(msg.sender){
        VAULT_ADDRESS = vaultAddress;
        ROUTER_ADDRESS = routerAddress;
    }


    function createPool(address token, uint256 minLaunchBalance, uint256 dBalance, uint256 poolSlippage) external override onlyOwner {
        // poolInfo[token].tokenAddress = token;
        // poolInfo[token].minLaunchBalance = minLaunchBalance;
        // poolInfo[token].dTotal = dBalance*DECIMAL;
        // poolInfo[token].poolSlippage = poolSlippage;

        emit PoolCreated(token,minLaunchBalance);
    }

    function disablePool(address token) external override onlyOwner{
        // TODO
    }

    function add(address user, address token, uint256 amount) external override onlyRouter {
        
        // uint256 newLPUnits = LogicContract.mintLPUnits()
        // poolInfo[token].reserveA += amount;
        // poolInfo[token].lpUnitsGlobal+=amount;

        // //mint D
        // userLpUnitInfo[user][token] += amount;

        emit LiquidityAdded();
    }

    function remove(address token, uint256 lpUnits) external override onlyRouter {
        emit LiquidityRemoved();
        //TODO
    }

}
