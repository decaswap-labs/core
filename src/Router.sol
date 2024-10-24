// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolActions} from "./interfaces/pool/IPoolActions.sol";
import {IPoolStates} from "./interfaces/pool/IPoolStates.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// @todo decide where to keep events. Router/Pool?
// @todo remove unused errors

contract Router is Ownable, ReentrancyGuard, IRouter {
    using SafeERC20 for IERC20;

    address public override POOL_ADDRESS;
    IPoolActions pool;
    IPoolStates poolStates;

    constructor(address ownerAddress, address poolAddress) Ownable(ownerAddress) {
        POOL_ADDRESS = poolAddress;
        pool = IPoolActions(POOL_ADDRESS);
        poolStates = IPoolStates(POOL_ADDRESS);

        emit PoolAddressUpdated(address(0), POOL_ADDRESS);
    }

    // function createPool(
    //     address token,
    //     uint256 amount,
    //     uint256 minLaunchReserveA,
    //     uint256 minLaunchReserveD,
    //     uint256 initialDToMint
    // ) external onlyOwner {
    //     if (amount == 0) revert InvalidAmount();
    //     if (token == address(0)) revert InvalidToken();
    //     if (initialDToMint == 0) revert InvalidInitialDAmount();

    //     IERC20(token).safeTransferFrom(msg.sender, POOL_ADDRESS, amount);
    //     IPoolLogic(poolStates.POOL_LOGIC()).createPool(
    //         token, msg.sender, amount, minLaunchReserveA, minLaunchReserveD, initialDToMint
    //     );
    // }

    function initGenesisPool(address token, uint256 tokenAmount, uint256 dToMint) external onlyOwner {
        if (tokenAmount == 0) revert InvalidAmount();
        if (token == address(0)) revert InvalidToken();
        if (dToMint == 0) revert InvalidInitialDAmount();

        IERC20(token).safeTransferFrom(msg.sender, POOL_ADDRESS, tokenAmount);

        IPoolLogic(poolStates.POOL_LOGIC()).initGenesisPool(token, msg.sender, tokenAmount, dToMint);
    }

    function addLiquidity(address token, uint256 amount) external override nonReentrant {
        // @todo confirm about the appoach, where to keep checks? PoolLogic/Pool/Router??Then refactor
        if (!poolExist(token)) revert InvalidPool();
        if (amount == 0) revert InvalidAmount();

        IERC20(token).safeTransferFrom(msg.sender, POOL_ADDRESS, amount);
        IPoolLogic(poolStates.POOL_LOGIC()).addLiquidity(token, msg.sender, amount);

        emit LiquidityAdded(msg.sender, token, amount);
    }

    function removeLiquidity(address token, uint256 lpUnits) external override nonReentrant {
        if (!poolExist(token)) revert InvalidPool();
        if (lpUnits == 0 || lpUnits > poolStates.userLpUnitInfo(msg.sender, token)) revert InvalidAmount();

        IPoolLogic(poolStates.POOL_LOGIC()).removeLiquidity(token, msg.sender, lpUnits);

        emit LiquidityRemoved(msg.sender, token, lpUnits);
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 executionPrice) external nonReentrant {
        if (amountIn == 0) revert InvalidAmount();
        if (executionPrice == 0) revert InvalidExecutionPrice();
        if (!poolExist(tokenIn) || !poolExist(tokenOut)) revert InvalidPool();

        IERC20(tokenIn).safeTransferFrom(msg.sender, POOL_ADDRESS, amountIn);
        IPoolLogic(poolStates.POOL_LOGIC()).swap(msg.sender, tokenIn, tokenOut, amountIn, executionPrice);
    }

    function processPair(address tokenIn, address tokenOut) external nonReentrant {
        if (!poolExist(tokenIn) || !poolExist(tokenOut)) revert InvalidPool();
        IPoolLogic(poolStates.POOL_LOGIC()).processPair(tokenIn, tokenOut);
    }

    function updatePoolAddress(address newPoolAddress) external override onlyOwner {
        emit PoolAddressUpdated(POOL_ADDRESS, newPoolAddress);
        POOL_ADDRESS = newPoolAddress;
        pool = IPoolActions(POOL_ADDRESS);
        poolStates = IPoolStates(POOL_ADDRESS);
    }

    function poolExist(address tokenAddress) internal view returns (bool) {
        // TODO : Resolve this tuple unbundling issue
        (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, bool initialized) = poolStates.poolInfo(tokenAddress);
        return initialized;
    }
}
