// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPool} from "./interfaces/IPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolLogicActions} from "./interfaces/pool-logic/IPoolLogicActions.sol";
import {IERC20} from "./interfaces/utils/IERC20.sol";
import {Queue} from "./lib/SwapQueue.sol";
import {Swap} from "./lib/SwapQueue.sol";
import {PoolSwapData} from "./lib/SwapQueue.sol";
import {SwapSorter} from "./lib/QuickSort.sol";

contract Pool is IPool, Ownable {
    using Queue for Queue.QueueStruct;

    address public override VAULT_ADDRESS = address(0);
    address public override ROUTER_ADDRESS = address(0);
    address public override POOL_LOGIC = address(0);
    uint256 public override globalSlippage = 10;

    IPoolLogicActions poolLogic;

    struct PoolInfo {
        uint256 reserveD;
        uint256 poolOwnershipUnitsTotal;
        uint256 reserveA;
        uint256 minLaunchReserveA;
        uint256 minLaunchReserveD;
        uint256 initialDToMint;
        uint256 poolFeeCollected;
        address tokenAddress;
    }

    mapping(address => PoolInfo) public override poolInfo;
    mapping(address => mapping(address => uint256)) public override userLpUnitInfo;
    mapping(bytes32 => uint256) public override pairSlippage;
    // mapping(bytes32 => PoolSwapData) public override pairSwapHistory;
    mapping(bytes32 => Queue.QueueStruct) public pairStreamQueue;
    mapping(bytes32 => Queue.QueueStruct) public pairPendingQueue;
    mapping(bytes32 => Queue.QueueStruct) public poolStreamQueue;

    modifier onlyRouter() {
        if (msg.sender != ROUTER_ADDRESS) revert NotRouter(msg.sender);
        _;
    }

    constructor(address vaultAddress, address routerAddress, address poolLogicAddress) Ownable(msg.sender) {
        VAULT_ADDRESS = vaultAddress;
        ROUTER_ADDRESS = routerAddress;
        POOL_LOGIC = poolLogicAddress;
        poolLogic = IPoolLogicActions(POOL_LOGIC);

        emit VaultAddressUpdated(address(0), VAULT_ADDRESS);
        emit RouterAddressUpdated(address(0), ROUTER_ADDRESS);
        emit PoolLogicAddressUpdated(address(0), POOL_LOGIC);
    }

    function createPool(
        address token,
        uint256 minLaunchReserveA,
        uint256 minLaunchReserveD,
        uint256 tokenAmount,
        uint256 initialDToMint
    ) external override onlyOwner {
        _createPool(token, minLaunchReserveA, minLaunchReserveD, initialDToMint);
        _addLiquidity(msg.sender, token, tokenAmount);
    }

    function disablePool(address token) external override onlyOwner {
        // TODO
    }

    function add(address user, address token, uint256 amountA) external override onlyRouter {
        _addLiquidity(user, token, amountA);
    }

    function remove(address user, address token, uint256 lpUnits) external override onlyRouter {
        _removeLiquidity(user, token, lpUnits);
    }

    function depositVault() external override onlyRouter {}

    function withdrawVault() external override onlyRouter {}

    // neeed to add in interface
    function executeSwap(address user, uint256 amountIn, uint256 executionPrice, address tokenIn, address tokenOut)
        external
        override
        onlyRouter
    {
        if (amountIn == 0) revert InvalidTokenAmount();
        if (executionPrice == 0) revert InvalidExecutionPrice();
        if (poolInfo[tokenIn].tokenAddress == address(0) || poolInfo[tokenOut].tokenAddress == address(0)) {
            revert InvalidPool();
        }

        uint256 streamCount;
        uint256 swapPerStream;
        uint256 minPoolDepth;

        bytes32 poolId;
        bytes32 pairId;

        // TODO: Need to handle same vault deposit withdraw streams
        // break into streams
        minPoolDepth = poolInfo[tokenIn].reserveD <= poolInfo[tokenOut].reserveD
            ? poolInfo[tokenIn].reserveD
            : poolInfo[tokenOut].reserveD;
        poolId = getPoolId(tokenIn, tokenOut); // for pair slippage only. Not an ID for pair direction queue
        streamCount = poolLogic.calculateStreamCount(amountIn, pairSlippage[poolId], minPoolDepth);
        swapPerStream = amountIn / streamCount;

        // initiate swapqueue per direction
        pairId = keccak256(abi.encodePacked(tokenIn, tokenOut)); // for one direction

        uint256 currentPrice = poolLogic.getExecutionPrice(poolInfo[tokenIn].reserveA, poolInfo[tokenOut].reserveA);

        // if execution price 0 (stream queue) , otherwise another queue
        // add into queue

        if (executionPrice <= currentPrice) {
            pairStreamQueue[pairId].enqueue(
                Swap({
                    swapID: pairStreamQueue[pairId].back,
                    swapAmount: amountIn,
                    executionPrice: executionPrice,
                    swapAmountRemaining: amountIn,
                    streamsCount: streamCount,
                    streamsRemaining: streamCount,
                    swapPerStream: swapPerStream,
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    completed: false,
                    amountOut: 0,
                    user: user
                })
            );

            emit StreamAdded(pairStreamQueue[pairId].front, amountIn, executionPrice, amountIn, streamCount, pairId);
        } else {
            // adding to pending queue
            pairPendingQueue[pairId].enqueue(
                Swap({
                    swapID: pairPendingQueue[pairId].back,
                    swapAmount: amountIn,
                    executionPrice: executionPrice,
                    swapAmountRemaining: amountIn,
                    streamsCount: streamCount,
                    swapPerStream: swapPerStream,
                    streamsRemaining: streamCount,
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    completed: false,
                    amountOut: 0,
                    user: user
                })
            );

            // Sort the array w.r.t price
            SwapSorter.quickSort(pairPendingQueue[pairId].data);

            emit PendingStreamAdded(
                pairPendingQueue[pairId].front, amountIn, executionPrice, amountIn, streamCount, pairId
            );
        }
        // execute pending streams
        _executeStream(pairId, tokenIn, tokenOut);
    }

    function cancelSwap(uint256 swapId, bytes32 pairId, bool isStreaming) external {
        uint256 amountIn;
        uint256 amountOut;
        if (isStreaming) {
            (pairStreamQueue[pairId], amountIn, amountOut) = _removeSwap(swapId, pairStreamQueue[pairId]);
        } else {
            (pairPendingQueue[pairId], amountIn, amountOut) = _removeSwap(swapId, pairPendingQueue[pairId]);
        }

        emit SwapCancelled(swapId, pairId, amountIn, amountOut);
    }

    function updateRouterAddress(address routerAddress) external override onlyOwner {
        emit RouterAddressUpdated(ROUTER_ADDRESS, routerAddress);
        ROUTER_ADDRESS = routerAddress;
    }

    function updateVaultAddress(address vaultAddress) external override onlyOwner {
        emit VaultAddressUpdated(VAULT_ADDRESS, vaultAddress);
        VAULT_ADDRESS = vaultAddress;
    }

    function updatePoolLogicAddress(address poolLogicAddress) external override onlyOwner {
        emit PoolLogicAddressUpdated(POOL_LOGIC, poolLogicAddress);
        POOL_LOGIC = poolLogicAddress;
        poolLogic = IPoolLogicActions(POOL_LOGIC);
    }

    function updateMinLaunchReserveA(address token, uint256 newMinLaunchReserveA) external override onlyOwner {
        emit MinLaunchReserveUpdated(token, poolInfo[token].minLaunchReserveA, newMinLaunchReserveA);
        poolInfo[token].minLaunchReserveA = newMinLaunchReserveA;
    }

    function updatePairSlippage(address tokenA, address tokenB, uint256 newSlippage) external override onlyOwner {
        bytes32 poolId = getPoolId(tokenA, tokenB);
        pairSlippage[poolId] = newSlippage;
        emit PairSlippageUpdated(tokenA, tokenB, newSlippage);
    }

    function updateGlobalSlippage(uint256 newGlobalSlippage) external override onlyOwner {
        emit GlobalSlippageUpdated(globalSlippage, newGlobalSlippage);
        globalSlippage = newGlobalSlippage;
    }

    function getPoolId(address tokenA, address tokenB) public pure returns (bytes32) {
        (address A, address B) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(A, B));
    }

    function _createPool(address token, uint256 minLaunchReserveA, uint256 minLaunchReserveD, uint256 initialDToMint)
        internal
    {
        if (token == address(0)) revert InvalidToken();

        if (initialDToMint == 0) revert InvalidInitialDAmount();

        poolInfo[token].tokenAddress = token;
        poolInfo[token].minLaunchReserveA = minLaunchReserveA;
        poolInfo[token].minLaunchReserveD = minLaunchReserveD;
        poolInfo[token].initialDToMint = initialDToMint;

        emit PoolCreated(token, minLaunchReserveA, minLaunchReserveD);
    }

    function _addLiquidity(address user, address token, uint256 amount) internal {
        if (poolInfo[token].tokenAddress == address(0)) revert InvalidToken();

        if (amount == 0) revert InvalidTokenAmount();

        // lp units
        uint256 newLpUnits =
            poolLogic.calculateLpUnitsToMint(amount, poolInfo[token].reserveA, poolInfo[token].poolOwnershipUnitsTotal);
        poolInfo[token].reserveA += amount;
        poolInfo[token].poolOwnershipUnitsTotal += newLpUnits;

        // d units
        uint256 newDUnits = poolLogic.calculateDUnitsToMint(
            amount, poolInfo[token].reserveA, poolInfo[token].reserveD, poolInfo[token].initialDToMint
        );
        poolInfo[token].reserveD += newDUnits;

        //mint D
        userLpUnitInfo[user][token] += newDUnits;

        emit LiquidityAdded(user, token, amount, newLpUnits, newDUnits);
    }

    function _removeLiquidity(address user, address token, uint256 lpUnits) internal {
        if (poolInfo[token].tokenAddress == address(0)) revert InvalidToken();

        if (lpUnits == 0) revert InvalidTokenAmount();

        // deduct lp from user
        userLpUnitInfo[user][token] -= lpUnits;
        // calculate asset to transfer
        uint256 assetToTransfer =
            poolLogic.calculateAssetTransfer(lpUnits, poolInfo[token].reserveA, poolInfo[token].poolOwnershipUnitsTotal);
        // minus d amount from reserve
        uint256 dAmountToDeduct =
            poolLogic.calculateDToDeduct(lpUnits, poolInfo[token].reserveD, poolInfo[token].poolOwnershipUnitsTotal);

        poolInfo[token].reserveD -= dAmountToDeduct;
        poolInfo[token].reserveA -= assetToTransfer;
        poolInfo[token].poolOwnershipUnitsTotal -= lpUnits;

        // IERC20(token).transfer(user,assetToTransfer); // commented for test to run
        emit LiquidityRemoved(user, token, lpUnits, assetToTransfer, dAmountToDeduct);
    }

    function _executeStream(bytes32 pairId, address tokenIn, address tokenOut) internal {
        //check if the reserves are greater than min launch
        if (
            poolInfo[tokenIn].minLaunchReserveA > poolInfo[tokenIn].reserveA
                || poolInfo[tokenIn].minLaunchReserveD > poolInfo[tokenIn].reserveD
        ) revert MinLaunchReservesNotReached();

        // loading the front swap from the stream queue
        Swap storage frontSwap;
        Queue.QueueStruct storage pairStream = pairStreamQueue[pairId];
        frontSwap = pairStream.data[pairStream.front];

        // ------------------------ CHECK OPP DIR SWAP --------------------------- //
        //TODO: Deduct fees from amount out = 5BPS.
        bytes32 otherPairId = keccak256(abi.encodePacked(tokenOut, tokenIn));
        Queue.QueueStruct storage oppositePairStream = pairStreamQueue[otherPairId];
        Swap storage oppositeSwap = oppositePairStream.data[oppositePairStream.front];

        if (oppositeSwap.user != address(0)) {
            // D not used
            (uint256 dOut2, uint256 amountOut2) = poolLogic.getSwapAmountOut(
                oppositeSwap.swapAmountRemaining,
                poolInfo[tokenOut].reserveA,
                poolInfo[tokenIn].reserveA,
                poolInfo[tokenOut].reserveD,
                poolInfo[tokenIn].reserveD
            );

            // D not used
            (uint256 dOut1, uint256 amountOut1) = poolLogic.getSwapAmountOut(
                frontSwap.swapAmountRemaining,
                poolInfo[tokenIn].reserveA,
                poolInfo[tokenOut].reserveA,
                poolInfo[tokenIn].reserveD,
                poolInfo[tokenOut].reserveD
            );

            if (frontSwap.swapAmountRemaining < amountOut2) {
                oppositeSwap.amountOut += frontSwap.swapAmountRemaining;
                frontSwap.amountOut = amountOut1;
                oppositeSwap.swapAmountRemaining -= frontSwap.swapAmountRemaining;

                frontSwap.completed = true;
                frontSwap.streamsRemaining = 0;

                pairStreamQueue[pairId].data[pairStream.front] = frontSwap;
                Queue.dequeue(pairStreamQueue[pairId]);
            } else {
                frontSwap.amountOut += oppositeSwap.swapAmountRemaining;
                oppositeSwap.amountOut = amountOut2;
                frontSwap.swapAmountRemaining -= oppositeSwap.swapAmountRemaining;

                oppositeSwap.completed = true;
                oppositeSwap.streamsRemaining = 0;

                pairStreamQueue[otherPairId].data[oppositePairStream.front] = oppositeSwap;
                Queue.dequeue(pairStreamQueue[otherPairId]);
            }
        } else {
            (uint256 dToUpdate, uint256 amountOut) = poolLogic.getSwapAmountOut(
                frontSwap.swapPerStream,
                poolInfo[tokenIn].reserveA,
                poolInfo[tokenOut].reserveA,
                poolInfo[tokenIn].reserveD,
                poolInfo[tokenOut].reserveD
            );
            // update pools
            poolInfo[tokenIn].reserveD -= dToUpdate;
            poolInfo[tokenIn].reserveA += frontSwap.swapPerStream;

            poolInfo[tokenOut].reserveD += dToUpdate;
            poolInfo[tokenOut].reserveD -= amountOut;
            // update swaps

            //TODO: Deduct fees from amount out = 5BPS.
            frontSwap.swapAmountRemaining -= frontSwap.swapPerStream;
            frontSwap.amountOut += amountOut;
            frontSwap.streamsRemaining--;

            if (frontSwap.streamsRemaining == 0) frontSwap.completed = true;

            pairStreamQueue[pairId].data[pairStream.front] = frontSwap;

            if (pairStreamQueue[pairId].data[pairStream.front].streamsCount == 0) {
                Queue.dequeue(pairStreamQueue[pairId]);
            }
        }

        // --------------------------- HANDLE PENDING SWAP INSERTION ----------------------------- //
        Swap storage frontPendingSwap;
        Queue.QueueStruct storage pairPending = pairPendingQueue[pairId];
        frontPendingSwap = pairPending.data[pairPending.front];

        uint256 executionPriceInOrder = frontPendingSwap.executionPrice;
        uint256 executionPriceLatest = poolLogic.getExecutionPrice(
            poolInfo[frontPendingSwap.tokenIn].reserveA, poolInfo[frontPendingSwap.tokenOut].reserveA
        );

        if (executionPriceLatest >= executionPriceInOrder) {
            pairStreamQueue[pairId].enqueue(frontPendingSwap);
            pairPendingQueue[pairId].dequeue();
        }
    }

    function _removeSwap(uint256 swapId, Queue.QueueStruct storage swapQueue)
        internal
        returns (Queue.QueueStruct storage, uint256, uint256)
    {
        if (swapQueue.data[swapId].user == address(0)) revert InvalidSwap();
        // transferring the remaining amount
        uint256 amountIn = swapQueue.data[swapId].swapAmountRemaining;
        uint256 amountOut = swapQueue.data[swapId].amountOut;
        address user = swapQueue.data[swapId].user;
        address token = swapQueue.data[swapId].tokenIn;
        address tokenOut = swapQueue.data[swapId].tokenOut;

        IERC20(token).transfer(user, amountIn);
        IERC20(tokenOut).transfer(user, amountOut);

        if (swapId == 0) {
            swapQueue.front++;
        } else if (swapId == swapQueue.back) {
            Queue.dequeue(swapQueue);
        } else {
            // iterate over queue to fix the index data
            uint256 i = swapId;
            uint256 lengthOfIteration = swapQueue.data.length - 1;

            for (i; i < lengthOfIteration; i++) {
                swapQueue.data[i] = swapQueue.data[i + 1];
            }
            swapQueue.back--;
        }

        return (swapQueue, amountIn, amountOut);
    }
}
