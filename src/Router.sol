// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolActions} from "./interfaces/pool/IPoolActions.sol";
import {IPoolStates} from "./interfaces/pool/IPoolStates.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IERC20} from "./interfaces/utils/IERC20.sol";
// @todo decide where to keep events. Router/Pool?
// @todo OZ safeERC20 or custom implementation?
// @todo ERC777 supported or not? (For reentrancy).
contract Router is Ownable, IRouter {
    address public override POOL_ADDRESS;
    IPoolActions pool;
    IPoolStates poolStates;

    constructor(address ownerAddress, address poolAddress) Ownable(ownerAddress) {

        POOL_ADDRESS = poolAddress;
        pool = IPoolActions(POOL_ADDRESS);
        poolStates = IPoolStates(POOL_ADDRESS);

        emit PoolAddressUpdated(address(0), POOL_ADDRESS);
    }

    function createPool(address token, uint amount, uint256 minLaunchReserveA, uint256 minLaunchReserveD,uint256 initialDToMint) external onlyOwner {
        if (poolExist(token)) revert InvalidPool();
        if (amount == 0) revert InvalidAmount();

        IERC20(token).transferFrom(msg.sender, POOL_ADDRESS, amount);
        IPoolLogic(poolStates.POOL_LOGIC()).createPool(token,msg.sender,amount,minLaunchReserveA,minLaunchReserveD,initialDToMint);
    }


    function addLiquidity(address token, uint256 amount) external override {
        // @todo confirm about the appoach, where to keep checks? PoolLogic/Pool/Router??Then refactor
        if (!poolExist(token)) revert InvalidPool();
        if (amount == 0) revert InvalidAmount();

        IERC20(token).transferFrom(msg.sender, POOL_ADDRESS, amount);
        IPoolLogic(poolStates.POOL_LOGIC()).addLiquidity(token,msg.sender,amount);

        emit LiquidityAdded(msg.sender, token, amount);
    }

    function removeLiquidity(address token, uint256 lpUnits) external override {
        if (!poolExist(token)) revert InvalidPool();
        if (lpUnits == 0 || lpUnits > poolStates.userLpUnitInfo(msg.sender, token)) revert InvalidAmount();

        IPoolLogic(poolStates.POOL_LOGIC()).removeLiquidity(token,msg.sender,lpUnits);

        emit LiquidityRemoved(msg.sender, token, lpUnits);
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 executionPrice) external {
        if (amountIn == 0) revert InvalidAmount();
        if (executionPrice == 0) revert InvalidExecutionPrice();
        if(!poolExist(tokenIn) || !poolExist(tokenOut)) revert InvalidPool();
        
        IERC20(tokenIn).transferFrom(msg.sender, POOL_ADDRESS, amountIn);
        IPoolLogic(poolStates.POOL_LOGIC()).swap(msg.sender,tokenIn,tokenOut,amountIn,executionPrice);
    }

    function updatePoolAddress(address newPoolAddress) external override onlyOwner {
        emit PoolAddressUpdated(POOL_ADDRESS, newPoolAddress);
        POOL_ADDRESS = newPoolAddress;
        pool = IPoolActions(POOL_ADDRESS);
        poolStates = IPoolStates(POOL_ADDRESS);
    }

    function poolExist(address tokenAddress) internal view returns (bool) {
        // TODO : Resolve this tuple unbundling issue
        (uint256 a, uint256 b, uint256 c, uint256 d, uint256 f, uint256 g, uint256 h, bool initialized) =
            poolStates.poolInfo(tokenAddress);
        return initialized;
    }
}
