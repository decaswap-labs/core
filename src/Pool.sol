// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPool} from "./interfaces/IPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolLogicActions} from "./interfaces/pool-logic/IPoolLogicActions.sol";

contract Pool is IPool, Ownable{
    address public override VAULT_ADDRESS = address(0);
    address public override ROUTER_ADDRESS = address(0);
    address public override POOL_LOGIC = address(0);

    IPoolLogicActions poolLogic;

    struct PoolInfo {
        uint256 reserveD;
        uint256 poolOwnershipUnitsTotal;
        uint256 reserveA;
        uint256 poolSlippage;
        uint256 minLaunchReserveA;
        uint256 poolFeeCollected;
        address tokenAddress;    
    }

    mapping(address => PoolInfo) public override poolInfo;
    mapping(address => mapping(address=>uint256)) public override userLpUnitInfo;

    modifier onlyRouter(){
        if(msg.sender != ROUTER_ADDRESS) revert NotRouter(msg.sender);
        _;
    }

    constructor(address vaultAddress, address routerAddress, address poolLogicAddress) Ownable(msg.sender){
        VAULT_ADDRESS = vaultAddress;
        ROUTER_ADDRESS = routerAddress;
        POOL_LOGIC = poolLogicAddress;
        poolLogic = IPoolLogicActions(POOL_LOGIC);

        emit VaultAddressUpdated(address(0), VAULT_ADDRESS);
        emit RouterAddressUpdated(address(0), ROUTER_ADDRESS);
        emit PoolLogicAddressUpdated(address(0), POOL_LOGIC);
    }


    function createPool(address token, uint256 minLaunchReserveA, uint256 poolSlippage) external override onlyOwner {
        if (token == address(0)){
            revert InvalidToken();
        }

        if (poolSlippage == 0){
            revert InvalidSlippage();
        }
        
        poolInfo[token].tokenAddress = token;
        poolInfo[token].minLaunchReserveA = minLaunchReserveA;
        poolInfo[token].poolSlippage = poolSlippage;

        emit PoolCreated(token,minLaunchReserveA);
    }

    function disablePool(address token) external override onlyOwner{
        // TODO
    }

    function add(address user, address token, uint256 amount) external override onlyRouter {
        
        // lp units
        uint256 newLpUnits = poolLogic.mintLpUnits(amount, poolInfo[token].reserveA, poolInfo[token].poolOwnershipUnitsTotal);
        poolInfo[token].reserveA += amount;
        poolInfo[token].poolOwnershipUnitsTotal+= newLpUnits;

        // d units
        uint256 newDUnits = poolLogic.mintDUnits(amount, poolInfo[token].reserveA, poolInfo[token].reserveD);
        poolInfo[token].reserveD += newDUnits;

        //mint D
        userLpUnitInfo[user][token] += newDUnits;

        emit LiquidityAdded(user, token, amount, newLpUnits, newDUnits);
    }

    function remove(address token, uint256 lpUnits) external override onlyRouter {
        emit LiquidityRemoved();
        //TODO
    }

    function updateRouterAddress(address routerAddress) external override onlyOwner {
        emit RouterAddressUpdated(ROUTER_ADDRESS,routerAddress);
        ROUTER_ADDRESS = routerAddress;
    }

    function updateVaultAddress(address vaultAddress) external override onlyOwner {
        emit VaultAddressUpdated(VAULT_ADDRESS, vaultAddress);
        VAULT_ADDRESS = vaultAddress;
    }

    function updatePoolLogicAddress(address poolLogicAddress) external override onlyOwner {
        emit PoolLogicAddressUpdated(POOL_LOGIC, poolLogicAddress);
        poolLogic = IPoolLogicActions(POOL_LOGIC);
    }


}
