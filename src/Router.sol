// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolActions} from "./interfaces/pool/IPoolActions.sol";
import {IPoolLogicActions} from "./interfaces/pool-logic/IPoolLogicActions.sol";
import {IPoolStates} from "./interfaces/pool/IPoolStates.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {console} from "forge-std/console.sol";


// @todo decide where to keep events. Router/Pool?
// @todo remove unused errors

contract Router is Ownable, ReentrancyGuard, IRouter {
    using SafeERC20 for IERC20;

    address public override POOL_ADDRESS;
    IPoolActions public pool;
    IPoolStates public poolStates;

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
        if (poolExist(token)) revert DuplicatePool();
        if (tokenAmount == 0) revert InvalidAmount();
        if (dToMint == 0) revert InvalidInitialDAmount();

        IERC20(token).safeTransferFrom(msg.sender, POOL_ADDRESS, tokenAmount);

        IPoolLogic(poolStates.POOL_LOGIC()).initGenesisPool(token, msg.sender, tokenAmount, dToMint);
    }

    function initPool(address token, address liquidityToken, uint256 tokenAmount, uint256 liquidityTokenAmount)
        external
        returns (bool success)
    {
        if (!poolExist(liquidityToken)) revert InvalidPool();
        if (poolExist(token)) revert DuplicatePool();
        if (tokenAmount == 0) revert InvalidAmount();
        if (liquidityTokenAmount == 0) revert InvalidLiquidityTokenAmount();

        IERC20(token).safeTransferFrom(msg.sender, POOL_ADDRESS, tokenAmount);
        IERC20(liquidityToken).safeTransferFrom(msg.sender, POOL_ADDRESS, liquidityTokenAmount);
        IPoolLogic(poolStates.POOL_LOGIC()).initPool(
            token, liquidityToken, msg.sender, tokenAmount, liquidityTokenAmount
        );
    }

    function addLiqDualToken(address tokenA, address tokenB, uint256 amountA, uint256 amountB) external {
        if (tokenA == tokenB) revert SamePool();
        if (!poolExist(tokenA)) revert InvalidPool();
        if (!poolExist(tokenB)) revert InvalidPool();
        if (amountA == 0) revert InvalidAmount();
        if (amountB == 0) revert InvalidAmount();

        IERC20(tokenA).safeTransferFrom(msg.sender, POOL_ADDRESS, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, POOL_ADDRESS, amountB);

        IPoolLogic(poolStates.POOL_LOGIC()).addLiqDualToken(tokenA, tokenB, msg.sender, amountA, amountB);
    }

    function streamDToPool(address tokenA, address tokenB, uint256 amountB) external {
        if (tokenA == tokenB) revert SamePool();
        if (!poolExist(tokenA)) revert InvalidPool();
        if (!poolExist(tokenB)) revert InvalidPool();
        if (amountB == 0) revert InvalidAmount();

        IERC20(tokenB).safeTransferFrom(msg.sender, POOL_ADDRESS, amountB);

        IPoolLogic(poolStates.POOL_LOGIC()).streamDToPool(tokenA, tokenB, msg.sender, amountB);
    }

    function addToPoolSingle(address token, uint256 amount) external {
        if (!poolExist(token)) revert InvalidPool();
        if (amount == 0) revert InvalidAmount();

        IERC20(token).safeTransferFrom(msg.sender, POOL_ADDRESS, amount);

        IPoolLogic(poolStates.POOL_LOGIC()).addToPoolSingle(token, msg.sender, amount);
    }

    function processLiqStream(address poolA, address poolB) external {
        if (poolA == poolB) revert SamePool();
        if (!poolExist(poolA) || !poolExist(poolB)) revert InvalidPool();
        IPoolLogic(poolStates.POOL_LOGIC()).processLiqStream(poolA, poolB);
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
        (uint256 reserveD,,,,,) = poolStates.poolInfo(address(token));
        uint256 streamCount = IPoolLogicActions(poolStates.POOL_LOGIC()).calculateStreamCount(
            lpUnits, poolStates.globalSlippage(), reserveD
        );
        if (lpUnits % streamCount != 0) {
            uint256 swapPerStream = lpUnits / streamCount;
            lpUnits = streamCount * swapPerStream;
        }
        IPoolLogic(poolStates.POOL_LOGIC()).removeLiquidity(token, msg.sender, lpUnits);

        emit LiquidityRemoved(msg.sender, token, lpUnits);
    }

    function processRemoveLiquidity(address token) external {
        if (!poolExist(token)) revert InvalidPool();
        IPoolLogic(poolStates.POOL_LOGIC()).processRemoveLiquidity(token);
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 executionPrice) external nonReentrant {
        if (amountIn == 0) revert InvalidAmount();
        if (executionPrice == 0) revert InvalidExecutionPrice();
        if (!poolExist(tokenIn) || !poolExist(tokenOut)) revert InvalidPool();

        // uint256 streamCount = IPoolLogic(poolStates.POOL_LOGIC()).getStreamCount(tokenIn, tokenOut, amountIn);
        // if (amountIn % streamCount != 0) {
        //     uint256 swapPerStream = amountIn / streamCount;
        //     amountIn = streamCount * swapPerStream;
        // }

        IERC20(tokenIn).safeTransferFrom(msg.sender, POOL_ADDRESS, amountIn);
        IPoolLogic(poolStates.POOL_LOGIC()).swap(msg.sender, tokenIn, tokenOut, amountIn, executionPrice);
    }

    function depositToGlobalPool(address token, uint256 amount) external override nonReentrant {
        if (!poolExist(token)) revert InvalidPool();
        if (amount == 0) revert InvalidAmount();
    
        // calculate and remove dust residual        
        uint256 streamCount = IPoolLogic(poolStates.POOL_LOGIC()).getStreamCountForDPool(token, amount);
        uint256 swapPerStream;
        if (amount % streamCount != 0) {
            swapPerStream = amount / streamCount;
            amount = streamCount * swapPerStream;
        }else{
            swapPerStream = amount/streamCount;
        }

        IERC20(token).safeTransferFrom(msg.sender, POOL_ADDRESS, amount);
        IPoolLogic(poolStates.POOL_LOGIC()).depositToGlobalPool(msg.sender, token, amount, streamCount, swapPerStream);
    }

    function withdrawFromGlobalPool(address poolAddress, uint256 dAmount) external override nonReentrant {
        if (!poolExist(poolAddress)) revert InvalidPool();
        if (poolStates.userGlobalPoolInfo(msg.sender, poolAddress) < dAmount) revert InvalidAmount();
        IPoolLogic(poolStates.POOL_LOGIC()).withdrawFromGlobalPool(msg.sender, poolAddress, dAmount);
    }

    function processGlobalStreamPairDeposit(address token) external override nonReentrant {
        if (!poolExist(token)) revert InvalidPool();
        IPoolLogic(poolStates.POOL_LOGIC()).processGlobalStreamPairDeposit(token);
    }

    function processGlobalStreamPairWithdraw(address token) external override nonReentrant {
        if (!poolExist(token)) revert InvalidPool();
        IPoolLogic(poolStates.POOL_LOGIC()).processGlobalStreamPairWithdraw(token);
    }

    function processPair(address tokenIn, address tokenOut) external nonReentrant {
        if (tokenIn == tokenOut) revert SamePool();
        if (!poolExist(tokenIn) || !poolExist(tokenOut)) revert InvalidPool();
        // IPoolLogic(poolStates.POOL_LOGIC()).processPair(tokenIn, tokenOut);
    }

    function updatePoolAddress(address newPoolAddress) external override onlyOwner {
        emit PoolAddressUpdated(POOL_ADDRESS, newPoolAddress);
        POOL_ADDRESS = newPoolAddress;
        pool = IPoolActions(POOL_ADDRESS);
        poolStates = IPoolStates(POOL_ADDRESS);
    }

    function poolExist(address tokenAddress) internal view returns (bool) {
        if (tokenAddress == address(0)) revert InvalidToken();
        (,,,,, bool initialized) = poolStates.poolInfo(tokenAddress);
        return initialized;
    }
}
