// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolStates} from "./interfaces/pool/IPoolStates.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IPoolActions} from "./interfaces/pool/IPoolActions.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    Swap,
    LiquidityStream,
    StreamDetails,
    TYPE_OF_LP,
    RemoveLiquidityStream,
    GlobalPoolStream
} from "src/lib/SwapQueue.sol";
import {DSMath} from "src/lib/DSMath.sol";
import {console} from "forge-std/console.sol";

contract PoolLogic is Ownable, IPoolLogic {
    using DSMath for uint256;

    address public override POOL_ADDRESS;
    IPoolStates public pool;
    uint256 public constant PRICE_PRECISION = 1_000_000_000;
    uint256 public constant STREAM_COUNT_PRECISION = 10_000;

    struct Payout {
        address swapUser;
        address token;
        uint256 amount;
    }

    modifier onlyRouter() {
        if (msg.sender != pool.ROUTER_ADDRESS()) revert NotRouter(msg.sender);
        _;
    }

    constructor(address ownerAddress, address poolAddress) Ownable(ownerAddress) {
        POOL_ADDRESS = poolAddress;
        pool = IPoolStates(POOL_ADDRESS);
        emit PoolAddressUpdated(address(0), POOL_ADDRESS);
    }

    function initGenesisPool(address token, address user, uint256 tokenAmount, uint256 initialDToMint)
        external
        onlyRouter
    {
        // hardcoding `poolFeeCollected` to zero as pool is just being created
        // reserveA == amount for 1st deposit
        bytes memory initPoolParams = abi.encode(
            token,
            user,
            tokenAmount,
            initialDToMint,
            tokenAmount, //no need to call formula
            initialDToMint,
            0
        );
        IPoolActions(POOL_ADDRESS).initGenesisPool(initPoolParams);
    }

    function initPool(
        address token,
        address liquidityToken,
        address user,
        uint256 tokenAmount,
        uint256 liquidityTokenAmount
    ) external onlyRouter {
        bytes32 pairId = keccak256(abi.encodePacked(token, liquidityToken));

        StreamDetails memory poolBStream = _createTokenStreamObj(liquidityToken, liquidityTokenAmount);
        // streamCount of `token` == streamCount of `liquidityToken`, because reservesD of `token` are 0 at this point
        StreamDetails memory poolAStream = StreamDetails({
            token: token,
            amount: tokenAmount,
            streamCount: poolBStream.streamCount,
            streamsRemaining: poolBStream.streamsRemaining,
            swapPerStream: tokenAmount / poolBStream.streamCount,
            swapAmountRemaining: tokenAmount
        });
        // enqueue
        _enqueueLiqStream(
            pairId,
            user,
            TYPE_OF_LP.DUAL_TOKEN,
            poolAStream, // poolA stream
            poolBStream // poolB stream
        );

        IPoolActions(POOL_ADDRESS).initPool(token);

        // process Liquidity streams in the queue
        _streamLiquidity(token, liquidityToken);
    }

    function addLiqDualToken(address tokenA, address tokenB, address user, uint256 amountA, uint256 amountB)
        external
        onlyRouter
    {
        bytes32 pairId = keccak256(abi.encodePacked(tokenA, tokenB));
        // enqueue
        _enqueueLiqStream(
            pairId,
            user,
            TYPE_OF_LP.DUAL_TOKEN,
            _createTokenStreamObj(tokenA, amountA), // poolA stream
            _createTokenStreamObj(tokenB, amountB) // poolB stream
        );

        _streamLiquidity(tokenA, tokenB);
    }

    function streamDToPool(address tokenA, address tokenB, address user, uint256 amountB) external onlyRouter {
        bytes32 pairId = keccak256(abi.encodePacked(tokenA, tokenB));
        // poolAStream will be empty as tokens are added to poolB and D is streamed from B -> A
        StreamDetails memory poolAStream;
        poolAStream.token = tokenA;
        // enqueue
        _enqueueLiqStream(
            pairId,
            user,
            TYPE_OF_LP.SINGLE_TOKEN,
            poolAStream, // poolA stream
            _createTokenStreamObj(tokenB, amountB) // poolB stream
        );

        _streamLiquidity(tokenA, tokenB);
    }

    function addToPoolSingle(address token, address user, uint256 amount) external onlyRouter {
        // encoding address with itself so pairId is same here and in _streamLiquidity()
        bytes32 pairId = keccak256(abi.encodePacked(token, token));
        StreamDetails memory poolBStream;
        poolBStream.token = token;
        // enqueue
        _enqueueLiqStream(
            pairId,
            user,
            TYPE_OF_LP.SINGLE_TOKEN,
            _createTokenStreamObj(token, amount), // poolA stream
            poolBStream // poolB stream
        );

        _streamLiquidity(token, token);
    }

    function depositToGlobalPool(
        address user,
        address token,
        uint256 amount,
        uint256 streamCount,
        uint256 swapPerStream
    ) external override onlyRouter {
        bytes32 pairId = bytes32(abi.encodePacked(token, token));
        _settleDPoolStream(pairId, user, token, amount, streamCount, swapPerStream, true);

        // _enqueueGlobalPoolStream(pairId, user, token, amount, true);

        // _streamGlobalStream(token);
    }

    function withdrawFromGlobalPool(address user, address token, uint256 amount) external override onlyRouter {
        bytes32 pairId = bytes32(abi.encodePacked(token, token));

        (uint256 reserveD,,,,,) = pool.poolInfo(address(token));
        uint256 streamCount = calculateStreamCount(amount, pool.globalSlippage(), reserveD);
        uint256 swapPerStream = amount / streamCount;

        _settleDPoolStream(pairId, user, token, amount, streamCount, swapPerStream, false);

        // _enqueueGlobalPoolStream(pairId, user, token, amount, false);
        // _streamGlobalStream(token);
    }

    function _settleDPoolStream(
        bytes32 pairId,
        address user,
        address token,
        uint256 amount,
        uint256 streamCount,
        uint256 swapPerStream,
        bool isDeposit
    ) internal {
        GlobalPoolStream memory localStream = GlobalPoolStream({
            user: user,
            tokenIn: token,
            tokenAmount: amount,
            streamCount: streamCount,
            streamsRemaining: streamCount,
            swapPerStream: swapPerStream,
            swapAmountRemaining: amount,
            amountOut: 0,
            deposit: isDeposit
        });

        GlobalPoolStream memory updatedStream = _streamGlobalPoolSingle(localStream);
        if (updatedStream.streamsRemaining != 0) {
            updatedStream.swapAmountRemaining = updatedStream.swapAmountRemaining - updatedStream.swapPerStream;
            if (updatedStream.deposit) {
                IPoolActions(POOL_ADDRESS).enqueueGlobalPoolDepositStream(pairId, updatedStream);
            } else {
                // @audit for d, as the damount will be very low as compared to the reserve, stream will likely happen
                IPoolActions(POOL_ADDRESS).enqueueGlobalPoolWithdrawStream(pairId, updatedStream);
            }
        } else {
            if (!updatedStream.deposit) {
                IPoolActions(POOL_ADDRESS).transferTokens(token, user, updatedStream.amountOut);
            }
        }
    }

    function _streamGlobalPoolSingle(GlobalPoolStream memory stream) internal returns (GlobalPoolStream memory) {
        uint256 poolNewStreamRemaining;
        uint256 poolReservesToAdd;
        uint256 changeInD;
        uint256 amountOut;

        if (stream.deposit) {
            (poolNewStreamRemaining, poolReservesToAdd, changeInD) = _streamDGlobal(stream);
            stream.amountOut += changeInD;

            // // update reserves
            bytes memory updatedReserves = abi.encode(stream.tokenIn, poolReservesToAdd, changeInD, true);
            IPoolActions(POOL_ADDRESS).updateReservesGlobalStream(updatedReserves);

            bytes memory updatedGlobalPoolBalnace = abi.encode(changeInD, true);
            IPoolActions(POOL_ADDRESS).updateGlobalPoolBalance(updatedGlobalPoolBalnace);

            bytes memory updatedGlobalPoolUserBalanace = abi.encode(stream.user, stream.tokenIn, changeInD, true);
            IPoolActions(POOL_ADDRESS).updateGlobalPoolUserBalance(updatedGlobalPoolUserBalanace);
        } else {
            (poolNewStreamRemaining, poolReservesToAdd, amountOut) = _streamDGlobal(stream);
            stream.amountOut = amountOut;

            // // update reserves
            bytes memory updatedReserves = abi.encode(stream.tokenIn, poolReservesToAdd, amountOut, false);
            IPoolActions(POOL_ADDRESS).updateReservesGlobalStream(updatedReserves);

            bytes memory updatedGlobalPoolBalnace = abi.encode(stream.swapPerStream, false);
            IPoolActions(POOL_ADDRESS).updateGlobalPoolBalance(updatedGlobalPoolBalnace);

            bytes memory updatedGlobalPoolUserBalanace =
                abi.encode(stream.user, stream.tokenIn, stream.swapPerStream, false);
            IPoolActions(POOL_ADDRESS).updateGlobalPoolUserBalance(updatedGlobalPoolUserBalanace);
        }
        stream.streamsRemaining = poolNewStreamRemaining;
        return stream;
    }

    function processGlobalStreamPairWithdraw() external override onlyRouter {
        // _streamGlobalStream(token);
        _streamGlobalPoolWithdrawMultiple();
    }

    function processGlobalStreamPairDeposit() external override onlyRouter {
        _streamGlobalPoolDepositMultiple();
    }

    /// @notice Executes market orders for a given token from the order book
    function processMarketAndTriggerOrders() external override onlyRouter {
        address[] memory poolAddresses = IPoolActions(POOL_ADDRESS).getPoolAddresses();

        for (uint256 j = 0; j < poolAddresses.length;) {
            address token = poolAddresses[j];
            bytes32 pairId = keccak256(abi.encodePacked(token, token));
            (,, uint256 reserveA,,,) = pool.poolInfo(address(token));
            uint256 currentExecPrice = getExecutionPrice(reserveA, reserveA);
            uint256 executionPriceKey = getExecutionPriceLower(currentExecPrice);

            // Get market orders (isLimitOrder = false)
            Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, false);

            // Process each swap in the order book
            for (uint256 i = 0; i < swaps.length;) {
                Swap memory currentSwap = swaps[i];

                // @todo: handle trigger orders

                if(currentSwap.typeOfOrder == 1){
                    currentSwap = _settleCurrentSwapAgainstPool(currentSwap, currentExecPrice);
                    // Update the order book entry
                    bytes memory updatedSwapData = abi.encode(
                        pairId,
                        currentSwap.amountOut,
                        currentSwap.swapAmountRemaining,    
                        currentSwap.completed,
                        currentSwap.streamsRemaining,
                        currentSwap.streamsCount,
                        currentSwap.swapPerStream,
                        currentSwap.dustTokenAmount,
                        currentSwap.typeOfOrder
                    );

                    // Update swap object in the order book
                    IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData, executionPriceKey, i, false);

                    // If swap is completed, dequeue it and transfer tokens
                    if (currentSwap.streamsRemaining == 0) {
                        IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(pairId, executionPriceKey, i, false);
                        IPoolActions(POOL_ADDRESS).transferTokens(
                        currentSwap.tokenOut, currentSwap.user, currentSwap.amountOut
                        );
                    }
                }else if(currentSwap.typeOfOrder == 2 && currentSwap.executionPrice == currentExecPrice) {
                    currentSwap = _settleCurrentSwapAgainstPool(currentSwap, currentExecPrice);
                    currentSwap.typeOfOrder = 1;
                    // Update the order book entry
                    bytes memory updatedSwapData = abi.encode(
                        pairId,
                        currentSwap.amountOut,
                        currentSwap.swapAmountRemaining,    
                        currentSwap.completed,
                        currentSwap.streamsRemaining,
                        currentSwap.streamsCount,
                        currentSwap.swapPerStream,
                        currentSwap.dustTokenAmount,
                        currentSwap.typeOfOrder
                    );

                    // Update swap object in the order book
                    IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData, executionPriceKey, i, false);

                    // If swap is completed, dequeue it and transfer tokens
                    if (currentSwap.streamsRemaining == 0) {
                        IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(pairId, executionPriceKey, i, false);
                        IPoolActions(POOL_ADDRESS).transferTokens(
                        currentSwap.tokenOut, currentSwap.user, currentSwap.amountOut
                        );
                    }

                }


                unchecked {
                    ++i;
                }
            }

            unchecked {
                ++j;
            }
        }
    }

    function _streamGlobalPoolDepositMultiple() internal {
        address[] memory poolAddresses = IPoolActions(POOL_ADDRESS).getPoolAddresses();
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            address token = poolAddresses[i];
            bytes32 pairId = bytes32(abi.encodePacked(token, token));
            GlobalPoolStream[] memory globalPoolStream = IPoolActions(POOL_ADDRESS).globalStreamQueueDeposit(pairId);
            if (globalPoolStream.length > 0) {
                uint256 streamRemoved;
                uint256 count;

                for (uint256 i = 0; i < globalPoolStream.length;) {
                    GlobalPoolStream memory stream = _streamGlobalPoolSingle(globalPoolStream[i]);
                    if (stream.streamsRemaining == 0) {
                        streamRemoved++;
                        IPoolActions(POOL_ADDRESS).dequeueGlobalPoolDepositStream(pairId, i);
                        uint256 lastIndex = globalPoolStream.length - streamRemoved;
                        globalPoolStream[i] = globalPoolStream[lastIndex];
                        delete globalPoolStream[lastIndex];
                    } else {
                        IPoolActions(POOL_ADDRESS).updateGlobalPoolDepositStream(stream, pairId, i);
                        unchecked {
                            i++;
                        }
                    }
                    if (count == globalPoolStream.length - 1) {
                        break;
                    }
                    count++;
                }
            }
        }
    }

    function _streamGlobalPoolWithdrawMultiple() internal {
        address[] memory poolAddresses = IPoolActions(POOL_ADDRESS).getPoolAddresses();
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            address token = poolAddresses[i];
            bytes32 pairId = bytes32(abi.encodePacked(token, token));
            GlobalPoolStream[] memory globalPoolStream = IPoolActions(POOL_ADDRESS).globalStreamQueueWithdraw(pairId);

            if (globalPoolStream.length > 0) {
                uint256 streamRemoved;
                uint256 count;

                for (uint256 i = 0; i < globalPoolStream.length;) {
                    GlobalPoolStream memory stream = _streamGlobalPoolSingle(globalPoolStream[i]);

                    if (stream.streamsRemaining == 0) {
                        streamRemoved++;
                        IPoolActions(POOL_ADDRESS).dequeueGlobalPoolWithdrawStream(pairId, i);
                        IPoolActions(POOL_ADDRESS).transferTokens(
                            globalPoolStream[i].tokenIn, globalPoolStream[i].user, globalPoolStream[i].amountOut
                        );
                        uint256 lastIndex = globalPoolStream.length - streamRemoved;
                        globalPoolStream[i] = globalPoolStream[lastIndex];
                        delete globalPoolStream[lastIndex];
                    } else {
                        IPoolActions(POOL_ADDRESS).updateGlobalPoolWithdrawStream(stream, pairId, i);
                        unchecked {
                            i++;
                        }
                    }
                    if (count == globalPoolStream.length - 1) {
                        break;
                    }
                    count++;
                }
            }
        }
    }

    // function _enqueueGlobalPoolStream(bytes32 pairId, address user, address token, uint256 amount, bool isDeposit)
    //     internal
    // {
    //     (uint256 reserveD,,,,,) = pool.poolInfo(address(token));
    //     uint256 streamCount = calculateStreamCount(amount, pool.globalSlippage(), reserveD);

    //     // START FROM HERE

    //     /*
    //     * Break stream count and collect dust amount as well.
    //     * Update queue function for array insertion
    //     * Make queues for deposits and withdrawals separately
    //     * EOA flow, where only after enqueuing, 1 stream will be handled
    //     * Bot flow, where after pairId, whole array's 1 stream is executed
    //     */

    //     uint256 swapPerStream = amount / streamCount;
    //     if (amount % streamCount != 0) {
    //         amount = streamCount * swapPerStream;
    //     }

    //     GlobalPoolStream memory localDStream = GlobalPoolStream({
    //         user: user,
    //         tokenIn: token,
    //         tokenAmount: amount,
    //         streamCount: streamCount,
    //         streamsRemaining: streamCount,
    //         swapPerStream: swapPerStream,
    //         swapAmountRemaining: amount,
    //         amountOut: 0,
    //         deposit: isDeposit
    //     });

    //     // IPoolActions(POOL_ADDRESS).enqueueGlobalPoolDepositStream(
    //     //     pairId,
    //     //     GlobalPoolStream({
    //     //         user: user,
    //     //         tokenIn: token,
    //     //         tokenAmount: amount,
    //     //         streamCount: streamCount,
    //     //         streamsRemaining: streamCount,
    //     //         swapPerStream: swapPerStream,
    //     //         swapAmountRemaining: amount,
    //     //         amountOut: 0,
    //     //         deposit: isDeposit
    //     //     })
    //     // );
    // }

    // function _streamGlobalStream(address poolA) internal {
    //     bytes32 pairId = keccak256(abi.encodePacked(poolA, poolA));
    //     (GlobalPoolStream[] memory globalPoolStream, uint256 front, uint256 back) =
    //         IPoolActions(POOL_ADDRESS).globalStreamQueue(pairId);
    //     // true = there are streams pending
    //     if (back - front != 0) {
    //         (
    //             uint256 reserveD,
    //             uint256 poolOwnershipUnitsTotal,
    //             uint256 reserveA,
    //             uint256 initialDToMint,
    //             uint256 poolFeeCollected,
    //             bool initialized
    //         ) = pool.poolInfo(poolA);

    //         // get the front stream
    //         GlobalPoolStream memory globalStream = globalPoolStream[front];

    //         if (globalStream.deposit) {
    //             (uint256 poolNewStreamsRemaining, uint256 poolReservesToAdd, uint256 changeInD) =
    //                 _streamDGlobal(globalStream);

    //             // // update reserves
    //             bytes memory updatedReserves = abi.encode(poolA, poolReservesToAdd, changeInD, true);
    //             IPoolActions(POOL_ADDRESS).updateReservesGlobalStream(updatedReserves);

    //             bytes memory updatedGlobalPoolBalnace = abi.encode(changeInD, true);
    //             IPoolActions(POOL_ADDRESS).updateGlobalPoolBalance(updatedGlobalPoolBalnace);

    //             bytes memory updatedGlobalPoolUserBalanace = abi.encode(globalStream.user, poolA, changeInD, true);
    //             IPoolActions(POOL_ADDRESS).updateGlobalPoolUserBalance(updatedGlobalPoolUserBalanace);

    //             // update stream struct
    //             bytes memory updatedStreamData =
    //                 abi.encode(pairId, poolNewStreamsRemaining, globalStream.swapPerStream, changeInD);
    //             IPoolActions(POOL_ADDRESS).updateGlobalStreamQueueStream(updatedStreamData);

    //             if (poolNewStreamsRemaining == 0) {
    //                 IPoolActions(POOL_ADDRESS).dequeueGlobalStream_streamQueue(pairId);
    //             }
    //         } else {
    //             (uint256 poolNewStreamsRemaining, uint256 poolReservesToAdd, uint256 amountOut) =
    //                 _streamDGlobal(globalStream);

    //             // // update reserves
    //             bytes memory updatedReserves = abi.encode(poolA, poolReservesToAdd, amountOut, false);
    //             IPoolActions(POOL_ADDRESS).updateReservesGlobalStream(updatedReserves);

    //             bytes memory updatedGlobalPoolBalnace = abi.encode(globalStream.swapPerStream, false);
    //             IPoolActions(POOL_ADDRESS).updateGlobalPoolBalance(updatedGlobalPoolBalnace);

    //             bytes memory updatedGlobalPoolUserBalanace =
    //                 abi.encode(globalStream.user, poolA, globalStream.swapPerStream, false);
    //             IPoolActions(POOL_ADDRESS).updateGlobalPoolUserBalance(updatedGlobalPoolUserBalanace);

    //             // update stream struct
    //             bytes memory updatedStreamData =
    //                 abi.encode(pairId, poolNewStreamsRemaining, globalStream.swapPerStream, amountOut);
    //             IPoolActions(POOL_ADDRESS).updateGlobalStreamQueueStream(updatedStreamData);

    //             if (poolNewStreamsRemaining == 0) {
    //                 IPoolActions(POOL_ADDRESS).transferTokens(
    //                     poolA, globalStream.user, globalStream.amountOut + amountOut
    //                 );
    //                 IPoolActions(POOL_ADDRESS).dequeueGlobalStream_streamQueue(pairId);
    //             }
    //         }
    //     }
    // }

    function _streamA(LiquidityStream memory liqStream)
        internal
        view
        returns (uint256 poolANewStreamsRemaining, uint256 poolAReservesToAdd, uint256 lpUnitsAToMint)
    {
        // both poolStreamA and poolStreamB tokens should be same in case of single sided liquidity
        (uint256 reserveD_A, uint256 poolOwnershipUnitsTotal_A, uint256 reserveA_A,,,) =
            pool.poolInfo(liqStream.poolAStream.token);
        poolANewStreamsRemaining = liqStream.poolAStream.streamsRemaining;

        if (liqStream.poolAStream.swapAmountRemaining != 0) {
            poolANewStreamsRemaining--;
            poolAReservesToAdd = liqStream.poolAStream.swapPerStream;
            lpUnitsAToMint = calculateLpUnitsToMint(
                poolOwnershipUnitsTotal_A, poolAReservesToAdd, poolAReservesToAdd + reserveA_A, 0, reserveD_A
            );
        }
    }

    function _streamD(LiquidityStream memory liqStream)
        internal
        view
        returns (uint256 poolBNewStreamsRemaining, uint256 poolBReservesToAdd, uint256 changeInD)
    {
        // both poolStreamA and poolStreamB tokens should be same in case of single sided liquidity
        (uint256 reserveD_B,, uint256 reserveA_B,,,) = pool.poolInfo(liqStream.poolBStream.token);
        poolBNewStreamsRemaining = liqStream.poolBStream.streamsRemaining;
        if (liqStream.poolBStream.swapAmountRemaining != 0) {
            poolBNewStreamsRemaining--;
            poolBReservesToAdd = liqStream.poolBStream.swapPerStream;
            (changeInD,) = getSwapAmountOut(liqStream.poolBStream.swapPerStream, reserveA_B, 0, reserveD_B, 0);
        }
    }

    function _streamDGlobal(GlobalPoolStream memory globalStream)
        internal
        view
        returns (uint256 poolNewStreamsRemaining, uint256 poolReservesToAdd, uint256 amountOut)
    {
        // both poolStreamA and poolStreamB tokens should be same in case of single sided liquidity
        (uint256 reserveD,, uint256 reserveA,,,) = pool.poolInfo(globalStream.tokenIn);
        poolNewStreamsRemaining = globalStream.streamsRemaining;
        poolNewStreamsRemaining--;
        poolReservesToAdd = globalStream.swapPerStream;
        if (globalStream.deposit) {
            (amountOut,) = getSwapAmountOut(globalStream.swapPerStream, reserveA, 0, reserveD, 0);
        } else {
            amountOut = getSwapAmountOutFromD(globalStream.swapPerStream, reserveA, reserveD);
        }
    }

    function _enqueueLiqStream(
        bytes32 pairId,
        address user,
        TYPE_OF_LP typeofLp,
        StreamDetails memory poolAStream,
        StreamDetails memory poolBStream
    ) internal {
        IPoolActions(POOL_ADDRESS).enqueueLiquidityStream(
            pairId,
            LiquidityStream({
                user: user,
                poolAStream: poolAStream, // poolA stream
                poolBStream: poolBStream, // poolB stream
                dAmountOut: 0,
                typeofLp: typeofLp
            })
        );
    }

    function processLiqStream(address poolA, address poolB) external onlyRouter {
        _streamLiquidity(poolA, poolB);
    }

    function _streamLiquidity(address poolA, address poolB) internal {
        bytes32 pairId = keccak256(abi.encodePacked(poolA, poolB));
        (LiquidityStream[] memory liquidityStreams, uint256 front, uint256 back) = pool.liquidityStreamQueue(pairId);
        // true = there are streams pending
        if (back - front != 0) {
            (uint256 reserveD_A, uint256 poolOwnershipUnitsTotal_A, uint256 reserveA_A,,,) = pool.poolInfo(poolA);

            // get the front stream
            LiquidityStream memory liquidityStream = liquidityStreams[front];

            (uint256 poolANewStreamsRemaining, uint256 poolAReservesToAdd, uint256 lpUnitsAToMint) =
                _streamA(liquidityStream);
            (uint256 poolBNewStreamsRemaining, uint256 poolBReservesToAdd, uint256 changeInD) =
                _streamD(liquidityStream);

            uint256 lpUnitsFromStreamD;
            if (changeInD > 0) {
                // calc lpUnits user will receive adding D to poolA
                lpUnitsFromStreamD = calculateLpUnitsToMint(
                    poolOwnershipUnitsTotal_A + lpUnitsAToMint,
                    0,
                    poolAReservesToAdd + reserveA_A,
                    changeInD,
                    reserveD_A
                );
            }
            // update reserves
            bytes memory updatedReserves = abi.encode(poolA, poolB, poolAReservesToAdd, poolBReservesToAdd, changeInD);
            IPoolActions(POOL_ADDRESS).updateReservesWhenStreamingLiq(updatedReserves);

            // updating lpUnits
            bytes memory updatedLpUnitsInfo =
                abi.encode(poolA, liquidityStream.user, lpUnitsAToMint + lpUnitsFromStreamD);
            IPoolActions(POOL_ADDRESS).updateUserLpUnits(updatedLpUnitsInfo);

            // update stream struct
            bytes memory updatedStreamData = abi.encode(
                pairId,
                poolAReservesToAdd,
                poolBReservesToAdd,
                poolANewStreamsRemaining,
                poolBNewStreamsRemaining,
                changeInD
            );
            IPoolActions(POOL_ADDRESS).updateStreamQueueLiqStream(updatedStreamData);

            if (poolANewStreamsRemaining == 0 && poolBNewStreamsRemaining == 0) {
                IPoolActions(POOL_ADDRESS).dequeueLiquidityStream_streamQueue(pairId);
            }
        }
    }

    function removeLiquidity(address token, address user, uint256 lpUnits) external onlyRouter {
        (uint256 reserveD,,,,,) = pool.poolInfo(address(token));
        uint256 streamCount = calculateStreamCount(lpUnits, pool.globalSlippage(), reserveD);
        uint256 lpUnitsPerStream = lpUnits / streamCount;
        RemoveLiquidityStream memory removeLiqStream = RemoveLiquidityStream({
            user: user,
            lpAmount: lpUnits,
            streamCountTotal: streamCount,
            streamCountRemaining: streamCount,
            conversionPerStream: lpUnitsPerStream,
            tokenAmountOut: 0,
            conversionRemaining: lpUnits
        });
        IPoolActions(POOL_ADDRESS).enqueueRemoveLiquidityStream(token, removeLiqStream);
        _executeRemoveLiquidity(token);
    }

    /// @notice External function to process pending remove liquidity requests for a specific token
    /// @dev Can only be called by the router contract
    /// @dev Delegates to internal _executeRemoveLiquidity function to handle the actual processing
    /// @param token The address of the token for which to process remove liquidity requests
    function processRemoveLiquidity(address token) external onlyRouter {
        _executeRemoveLiquidity(token);
    }

    function _executeRemoveLiquidity(address token) internal {
        (RemoveLiquidityStream[] memory removeLiqStreams, uint256 front, uint256 back) =
            pool.removeLiquidityStreamQueue(token);
        if (front == back) {
            return;
        }

        (, uint256 poolOwnershipUnitsTotal, uint256 reserveA,,,) = pool.poolInfo(address(token));

        RemoveLiquidityStream memory frontStream = removeLiqStreams[front];

        uint256 assetToTransfer =
            calculateAssetTransfer(frontStream.conversionPerStream, reserveA, poolOwnershipUnitsTotal);
        frontStream.conversionRemaining -= frontStream.conversionPerStream;
        frontStream.streamCountRemaining--;
        frontStream.tokenAmountOut += assetToTransfer;

        bytes memory updatedRemoveLiqData =
            abi.encode(token, assetToTransfer, frontStream.conversionRemaining, frontStream.streamCountRemaining);
        IPoolActions(POOL_ADDRESS).updateReservesAndRemoveLiqStream(updatedRemoveLiqData);

        if (frontStream.streamCountRemaining == 0) {
            IPoolActions(POOL_ADDRESS).transferTokens(token, frontStream.user, frontStream.tokenAmountOut);
            IPoolActions(POOL_ADDRESS).dequeueRemoveLiquidity_streamQueue(token);
        }
    }

    function swap(address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 executionPrice)
        external
        onlyRouter
    {
        // uint256 swapId = IPoolActions(POOL_ADDRESS).getNextSwapId();

        // Swap memory currentSwap = Swap({
        //     swapID: swapId, // will be filled in if/else
        //     swapAmount: amountIn,
        //     executionPrice: executionPrice,
        //     swapAmountRemaining: amountIn,
        //     streamsCount: 0,
        //     swapPerStream: 0,
        //     streamsRemaining: 0,
        //     tokenIn: tokenIn,
        //     tokenOut: tokenOut,
        //     completed: false,
        //     amountOut: 0,
        //     user: user,
        //     dustTokenAmount: 0,
        //     typeOfOrder: 2
        // });

        // (,, uint256 reserveA_In,,,) = pool.poolInfo(address(tokenIn));

        // (,, uint256 reserveA_Out,,,) = pool.poolInfo(address(tokenOut));

        // uint256 currentExecPrice = getExecutionPrice(reserveA_In, reserveA_Out);
        // bytes32 pairId = bytes32(abi.encodePacked(tokenIn, tokenOut)); // for one direction
        // uint256 executionPriceKey = getExecutionPriceLower(executionPrice); //KEY

        // // if price of order less than current, then just insert it in order book
        // if (executionPrice < currentExecPrice) {
        //     uint256 streamCount = getStreamCount(tokenIn, tokenOut, currentSwap.swapAmount);
        //     uint256 swapPerStream = currentSwap.swapAmount / streamCount;
        //     if (currentSwap.swapAmount % streamCount != 0) {
        //         currentSwap.dustTokenAmount += (currentSwap.swapAmount - (streamCount * swapPerStream));
        //         currentSwap.swapAmountRemaining = streamCount * swapPerStream;
        //     }
        //     currentSwap.streamsCount = streamCount;
        //     currentSwap.streamsRemaining = streamCount;
        //     currentSwap.swapPerStream = swapPerStream;

        //     _insertInOrderBook(pairId, currentSwap, executionPriceKey);
        // } else {
        //     if (executionPrice > pool.highestPriceMarker(pairId)) {
        //         IPoolActions(POOL_ADDRESS).setHighestPriceMarker(pairId, executionPrice);
        //     }

        //     uint256 executionPriceReciprocal = getReciprocalOppositePrice(executionPrice, reserveA_In);
        //     uint256 executionPriceLower = getExecutionPriceLower(executionPriceReciprocal);

        //     currentSwap = _settleCurrentSwapAgainstOpposite(
        //         currentSwap, executionPriceLower, executionPrice, executionPriceReciprocal
        //     );

        //     if (currentSwap.completed) {
        //         IPoolActions(POOL_ADDRESS).transferTokens(tokenOut, user, currentSwap.amountOut);
        //     } else {
        //         /*
        //             * pool processing, swap should be consumed against pool, reserves will be updated in this case
        //             * swap should be broken down into streams
        //             * if stream's are completed, do something with dust token??? and transferOut the amountOut
        //             * if streams are not completed, then just enqueue the swap, and update the reserves.
        //         */

        //         uint256 streamCount = getStreamCount(tokenIn, tokenOut, currentSwap.swapAmountRemaining);
        //         uint256 swapPerStream = currentSwap.swapAmountRemaining / streamCount;
        //         if (currentSwap.swapAmountRemaining % streamCount != 0) {
        //             currentSwap.dustTokenAmount += (currentSwap.swapAmountRemaining - (streamCount * swapPerStream));
        //             currentSwap.swapAmountRemaining = streamCount * swapPerStream;
        //         }
        //         currentSwap.streamsCount = streamCount;
        //         currentSwap.streamsRemaining = streamCount;
        //         currentSwap.swapPerStream = swapPerStream;

        //         currentSwap = _settleCurrentSwapAgainstPool(currentSwap, executionPrice); // amountOut is updated
        //         if (currentSwap.completed) {
        //             IPoolActions(POOL_ADDRESS).transferTokens(
        //                 currentSwap.tokenOut, currentSwap.user, currentSwap.amountOut
        //             );
        //         } else {
        //             _insertInOrderBook(pairId, currentSwap, executionPriceKey);
        //         }
        //     }
        // }
    }

    function swapMarketOrder(address user, address tokenIn, address tokenOut, uint256 amountIn) external onlyRouter {
        uint256 swapId = IPoolActions(POOL_ADDRESS).getNextSwapId();
        (,, uint256 reserveA_In,,,) = pool.poolInfo(address(tokenIn));
        (,, uint256 reserveA_Out,,,) = pool.poolInfo(address(tokenOut));
        uint256 currentExecPrice = getExecutionPrice(reserveA_In, reserveA_Out);

        Swap memory currentSwap = Swap({
            swapID: swapId, // will be filled in if/else
            swapAmount: amountIn,
            executionPrice: currentExecPrice,
            swapAmountRemaining: amountIn,
            streamsCount: 0,
            swapPerStream: 0,
            streamsRemaining: 0,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            completed: false,
            amountOut: 0,
            user: user,
            dustTokenAmount: 0,
            typeOfOrder: 1
        });

        bytes32 pairId = bytes32(abi.encodePacked(tokenIn, tokenOut)); // for one direction
        uint256 executionPriceKey = getExecutionPriceLower(currentExecPrice); //KEY
        uint256 streamCount = getStreamCount(tokenIn, tokenOut, currentSwap.swapAmountRemaining);
        uint256 swapPerStream = currentSwap.swapAmountRemaining / streamCount;
        if (currentSwap.swapAmountRemaining % streamCount != 0) {
            currentSwap.dustTokenAmount += (currentSwap.swapAmountRemaining - (streamCount * swapPerStream));
            currentSwap.swapAmountRemaining = streamCount * swapPerStream;
        }
        currentSwap.streamsCount = streamCount;
        currentSwap.streamsRemaining = streamCount;
        currentSwap.swapPerStream = swapPerStream;

        currentSwap = _settleCurrentSwapAgainstPool(currentSwap, currentExecPrice); // amountOut is updated
        if (currentSwap.completed) {
            IPoolActions(POOL_ADDRESS).transferTokens(currentSwap.tokenOut, currentSwap.user, currentSwap.amountOut);
        } else {
            _insertInOrderBook(pairId, currentSwap, executionPriceKey, false);
        }
    }

    function swapTriggerOrder(
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 triggerExecutionPrice
    ) external onlyRouter {
        uint256 swapId = IPoolActions(POOL_ADDRESS).getNextSwapId();
        (,, uint256 reserveA_In,,,) = pool.poolInfo(address(tokenIn));
        (,, uint256 reserveA_Out,,,) = pool.poolInfo(address(tokenOut));

        Swap memory currentSwap = Swap({
            swapID: swapId, // will be filled in if/else
            swapAmount: amountIn,
            executionPrice: triggerExecutionPrice,
            swapAmountRemaining: amountIn,
            streamsCount: 0,
            swapPerStream: 0,
            streamsRemaining: 0,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            completed: false,
            amountOut: 0,
            user: user,
            dustTokenAmount: 0,
            typeOfOrder: 2
        });

        bytes32 pairId = bytes32(abi.encodePacked(tokenIn, tokenOut)); // for one direction

        if (triggerExecutionPrice > pool.highestPriceMarker(pairId)) {
            IPoolActions(POOL_ADDRESS).setHighestPriceMarker(pairId, triggerExecutionPrice);
        }

        uint256 currentExecPrice = getExecutionPrice(reserveA_In, reserveA_Out);
        uint256 executionPriceKey = getExecutionPriceLower(triggerExecutionPrice); //KEY
        uint256 streamCount = getStreamCount(tokenIn, tokenOut, currentSwap.swapAmountRemaining);
        uint256 swapPerStream = currentSwap.swapAmountRemaining / streamCount;
        if (currentSwap.swapAmountRemaining % streamCount != 0) {
            currentSwap.dustTokenAmount += (currentSwap.swapAmountRemaining - (streamCount * swapPerStream));
            currentSwap.swapAmountRemaining = streamCount * swapPerStream;
        }
        currentSwap.streamsCount = streamCount;
        currentSwap.streamsRemaining = streamCount;
        currentSwap.swapPerStream = swapPerStream;

        _insertInOrderBook(pairId, currentSwap, executionPriceKey, false);
    }

    function swapLimitOrder(address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 limitOrderPrice)
        external
        onlyRouter
    {
        uint256 swapId = IPoolActions(POOL_ADDRESS).getNextSwapId();

        Swap memory currentSwap = Swap({
            swapID: swapId, // will be filled in if/else
            swapAmount: amountIn,
            executionPrice: limitOrderPrice,
            swapAmountRemaining: amountIn,
            streamsCount: 0,
            swapPerStream: 0,
            streamsRemaining: 0,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            completed: false,
            amountOut: 0,
            user: user,
            dustTokenAmount: 0,
            typeOfOrder: 3
        });

        (,, uint256 reserveA_In,,,) = pool.poolInfo(address(tokenIn));

        // (,, uint256 reserveA_Out,,,) = pool.poolInfo(address(tokenOut));

        // uint256 currentExecPrice = getExecutionPrice(reserveA_In, reserveA_Out);
        bytes32 pairId = bytes32(abi.encodePacked(tokenIn, tokenOut)); // for one direction
        uint256 executionPriceKey = getExecutionPriceLower(limitOrderPrice); //KEY

        // if price of order less than current, then just insert it in order book
        // if (executionPrice < currentExecPrice) {
        //     uint256 streamCount = getStreamCount(tokenIn, tokenOut, currentSwap.swapAmount);
        //     uint256 swapPerStream = currentSwap.swapAmount / streamCount;
        //     if (currentSwap.swapAmount % streamCount != 0) {
        //         currentSwap.dustTokenAmount += (currentSwap.swapAmount - (streamCount * swapPerStream));
        //         currentSwap.swapAmountRemaining = streamCount * swapPerStream;
        //     }
        //     currentSwap.streamsCount = streamCount;
        //     currentSwap.streamsRemaining = streamCount;
        //     currentSwap.swapPerStream = swapPerStream;

        //     _insertInOrderBook(pairId, currentSwap, executionPriceKey, true);
        // } else {
        if (limitOrderPrice > pool.highestPriceMarker(pairId)) {
            IPoolActions(POOL_ADDRESS).setHighestPriceMarker(pairId, limitOrderPrice);
        }

        uint256 executionPriceReciprocal = getReciprocalOppositePrice(limitOrderPrice, reserveA_In);
        uint256 executionPriceKeyOpp = getExecutionPriceLower(executionPriceReciprocal);

        currentSwap = _settleCurrentLimitOrderAgainstOpposite(
            currentSwap, executionPriceKeyOpp, limitOrderPrice, executionPriceReciprocal
        );

        console.log("currentSwap.swapID BEFORE SETTLEMENT", currentSwap.swapID);

        if (currentSwap.completed) {
            console.log("currentSwap.swapID", currentSwap.swapID);
            IPoolActions(POOL_ADDRESS).transferTokens(tokenOut, user, currentSwap.amountOut);
        } else {
            /*
                    * pool processing, swap should be consumed against pool, reserves will be updated in this case
                    * swap should be broken down into streams
                    * if stream's are completed, do something with dust token??? and transferOut the amountOut
                    * if streams are not completed, then just enqueue the swap, and update the reserves.
                */

            uint256 streamCount = getStreamCount(tokenIn, tokenOut, currentSwap.swapAmountRemaining);
            uint256 swapPerStream = currentSwap.swapAmountRemaining / streamCount;
            if (currentSwap.swapAmountRemaining % streamCount != 0) {
                currentSwap.dustTokenAmount += (currentSwap.swapAmountRemaining - (streamCount * swapPerStream));
                currentSwap.swapAmountRemaining = streamCount * swapPerStream;
            }
            currentSwap.streamsCount = streamCount;
            currentSwap.streamsRemaining = streamCount;
            currentSwap.swapPerStream = swapPerStream;

            currentSwap = _settleCurrentSwapAgainstPool(currentSwap, limitOrderPrice); // amountOut is updated
            if (currentSwap.completed) {
                IPoolActions(POOL_ADDRESS).transferTokens(currentSwap.tokenOut, currentSwap.user, currentSwap.amountOut);
            } else {
                _insertInOrderBook(pairId, currentSwap, executionPriceKey, true);
            }
        }
    }

    function processLimitOrders(address tokenIn, address tokenOut) external onlyRouter {
        bytes32 currentPairId = bytes32(abi.encodePacked(tokenIn, tokenOut));
        uint256 startingExecutionPrice = pool.highestPriceMarker(currentPairId);
        uint256 priceKey = getExecutionPriceLower(startingExecutionPrice);

        (,, uint256 reserveA_In,,,) = pool.poolInfo(address(tokenIn));
        (,, uint256 reserveA_Out,,,) = pool.poolInfo(address(tokenOut));
        uint256 poolReservesPriceKey = getExecutionPriceLower(getExecutionPrice(reserveA_In, reserveA_Out)); // @noticewhy this?

        while (priceKey > poolReservesPriceKey) {
            _executeStream(currentPairId, priceKey); // Appelle la fonction pour ce priceKey.
            (,, reserveA_In,,,) = pool.poolInfo(address(tokenIn));
            (,, reserveA_Out,,,) = pool.poolInfo(address(tokenOut));
            poolReservesPriceKey = getExecutionPriceLower(getExecutionPrice(reserveA_In, reserveA_Out));
            priceKey -= PRICE_PRECISION; // 1 Gwei ou autre précision utilisée.
                // need get reserve price for the next priceKey
        }
    }

    function _executeStream(bytes32 pairId, uint256 executionPriceKey) internal {
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, true);
        if (swaps.length == 0) {
            return;
        }
        uint256 swapRemoved;
        for (uint256 i = 0; i < swaps.length;) {
            Swap memory currentSwap = swaps[i];
            uint256 swapExecutionPrice = currentSwap.executionPrice;

            (,, uint256 reserveA_In,,,) = pool.poolInfo(address(currentSwap.tokenIn));
            uint256 executionPriceReciprocal = getReciprocalOppositePrice(swapExecutionPrice, reserveA_In);
            uint256 oppPriceKey = getExecutionPriceLower(executionPriceReciprocal);

            currentSwap = _settleCurrentSwapAgainstOpposite(
                currentSwap, oppPriceKey, swapExecutionPrice, executionPriceReciprocal
            );
            if (currentSwap.completed) {
                // if the swap is completed, we keep looping to consume the opposite swaps
                IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(pairId, executionPriceKey, 0, true);
                IPoolActions(POOL_ADDRESS).transferTokens(currentSwap.tokenOut, currentSwap.user, currentSwap.amountOut);
                swapRemoved++;
                uint256 lastIndex = swaps.length - swapRemoved;
                swaps[i] = swaps[lastIndex];
                delete swaps[lastIndex];
                if (lastIndex == 0) {
                    // TODO we need to decrement the priceKey and find next collection of swaps
                    // it means no more swaps to process for the current priceKey
                    return;
                }
            } else {
                // we recalculate the streams for the current swap
                // I don't think we need to save it now
                uint256 streamCount =
                    getStreamCount(currentSwap.tokenIn, currentSwap.tokenOut, currentSwap.swapAmountRemaining);
                uint256 swapPerStream = currentSwap.swapAmountRemaining / streamCount;
                currentSwap.streamsCount = streamCount;
                currentSwap.swapPerStream = swapPerStream;
                if (currentSwap.swapAmountRemaining % streamCount != 0) {
                    currentSwap.dustTokenAmount += (currentSwap.swapAmountRemaining - (streamCount * swapPerStream));
                    currentSwap.swapAmountRemaining = streamCount * swapPerStream; // reAssigning newTokenOutAmountIn without dust tokens
                }

                swaps[i] = currentSwap;
                break;
            }
        }

        uint256 count;
        for (uint256 i; i < swaps.length - 1;) {
            // settle against pool;
            Swap memory currentSwap = swaps[i];
            currentSwap = _settleCurrentSwapAgainstPool(currentSwap, currentSwap.executionPrice);
            if (currentSwap.completed) {
                swapRemoved++;
                IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(pairId, executionPriceKey, i, true);
                IPoolActions(POOL_ADDRESS).transferTokens(currentSwap.tokenOut, currentSwap.user, currentSwap.amountOut);
                uint256 lastIndex = swaps.length - swapRemoved;
                swaps[i] = swaps[lastIndex];
                delete swaps[lastIndex];
                if (lastIndex == 0) {
                    break;
                }
            } else {
                // update the swap
                bytes memory updatedSwapData = abi.encode(
                    pairId,
                    currentSwap.swapAmount,
                    currentSwap.swapAmountRemaining,
                    currentSwap.completed,
                    currentSwap.streamsRemaining,
                    currentSwap.streamsCount,
                    currentSwap.swapPerStream,
                    currentSwap.dustTokenAmount
                );

                IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData, executionPriceKey, i, true);
                unchecked {
                    ++i;
                }
            }
            if (count == swaps.length - 1) {
                break;
            }
            count++;
        }
    }

    function _settleCurrentLimitOrderAgainstOpposite(
        Swap memory currentSwap,
        uint256 executionPriceOppositeKey,
        uint256 executionPriceCurrentSwap,
        uint256 executionPriceOppositeSwap
    ) internal returns (Swap memory) {
        uint256 initialTokenInAmountIn = currentSwap.swapAmountRemaining;
        uint256 dustTokenInAmountIn = currentSwap.dustTokenAmount;

        // tokenInAmountIn is the amount of tokenIn that is remaining to be processed from the selected swap
        // it contains the dust token amount
        uint256 tokenInAmountIn = initialTokenInAmountIn + dustTokenInAmountIn;
        address tokenIn = currentSwap.tokenIn;
        address tokenOut = currentSwap.tokenOut;

        // we need to look for the opposite swaps
        bytes32 oppositePairId = bytes32(abi.encodePacked(tokenOut, tokenIn));
        //NEED TO CHANGE THIS. ORDERBOOK IS NOW DIFFERENT
        Swap[] memory oppositeSwaps = pool.orderBook(oppositePairId, executionPriceOppositeKey, true);

        if (oppositeSwaps.length == 0) {
            return currentSwap; // will call pool handling function
        }
        /* 
            iterate on all the opposite swaps
            And check that if the amountOut of the oppositeSwap < currentSwapAmountIn
            if yes the consume oppositeSwap, and move on to the next oppositeSwap
            transferOut the swapAmoutOut asset

            if amountOut of oppositeSwap > currentSwapAmountIn 
            then consume the currentSwap, break the loop
            transferIn the swapAmountIn assets
            update the oppositeSwap struct
        */
        (,, uint256 reserveA_In,,,) = pool.poolInfo(address(tokenIn));
        (,, uint256 reserveA_Out,,,) = pool.poolInfo(address(tokenOut));

        uint256 reserveAInFromPrice = getOtherReserveFromPrice(executionPriceOppositeSwap, reserveA_Out);
        uint256 reserveAOutFromPrice = getOtherReserveFromPrice(executionPriceCurrentSwap, reserveA_In);

        // the number of opposite swaps
        // uint256 oppositeSwapsCount = oppositeBack - oppositeFront;
        // Payout[] memory oppositePayouts = new Payout[](oppositeSwapsCount);

        // now we need to loop through the opposite swaps and to process them
        uint256 swapRemoved;
        for (uint256 i = 0; i < oppositeSwaps.length;) {
            Swap memory oppositeSwap = oppositeSwaps[i];

            // tokenOutAmountIn is the amount of tokenOut that is remaining to be processed from the opposite swap
            // it contains opp swap dust token
            uint256 tokenOutAmountIn = oppositeSwap.swapAmountRemaining + oppositeSwap.dustTokenAmount;

            // we need to calculate the amount of tokenOut for the given tokenInAmountIn -> tokenA -> tokenB
            uint256 tokenOutAmountOut = getAmountOut(tokenInAmountIn, reserveA_In, reserveAOutFromPrice);

            // we need to calculate the amount of tokenIn for the given tokenOutAmountIn -> tokenB -> tokenA
            uint256 tokenInAmountOut = getAmountOut(tokenOutAmountIn, reserveA_Out, reserveAInFromPrice);

            // we need to check if the amount of tokenIn that we need to send to the user is less than the amount of tokenIn that is remaining to be processed
            if (tokenInAmountIn > tokenInAmountOut) {
                // 1. we keep in memory the swapUser, tokenOut address and the amountOutSwap in memory to transfer the tokens

                IPoolActions(POOL_ADDRESS).transferTokens(
                    oppositeSwap.tokenOut, oppositeSwap.user, tokenInAmountOut + oppositeSwap.amountOut
                );

                IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(
                    oppositePairId, executionPriceOppositeKey, i, true
                );

                uint256 newTokenInAmountIn = tokenInAmountIn - tokenInAmountOut;

                currentSwap.swapAmountRemaining = newTokenInAmountIn;
                currentSwap.amountOut += tokenOutAmountIn;
                tokenInAmountIn = newTokenInAmountIn;
                // 4. we continue to the next oppositeSwap

                swapRemoved++;
                if (swapRemoved == oppositeSwaps.length) {
                    break;
                }
                uint256 lastIndex = oppositeSwaps.length - swapRemoved;
                oppositeSwaps[i] = oppositeSwaps[lastIndex];
                delete oppositeSwaps[lastIndex];
            } else {
                // 1. frontSwap is completed and is taken out of the stream queue

                currentSwap.amountOut += tokenOutAmountOut;
                currentSwap.completed = true; // we don't need to do this
                currentSwap.dustTokenAmount = 0;

                // 2. we recalculate the oppositeSwap conditions and update it (if tokenInAmountIn == tokenInAmountOut we complete the oppositeSwap)

                //both swaps consuming each other
                if (tokenInAmountIn == tokenInAmountOut) {
                    IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(
                        oppositePairId, executionPriceOppositeKey, i, true
                    );

                    IPoolActions(POOL_ADDRESS).transferTokens(
                        oppositeSwap.tokenOut, oppositeSwap.user, tokenInAmountOut + oppositeSwap.amountOut
                    );
                } else {
                    // only front is getting consumed. so we need to update opposite one
                    uint256 newTokenOutAmountIn = tokenOutAmountIn - tokenOutAmountOut;
                    uint256 streamCount = getStreamCount(tokenOut, tokenIn, newTokenOutAmountIn);
                    uint256 swapPerStream = newTokenOutAmountIn / streamCount;
                    uint256 dustTokenAmount;
                    if (newTokenOutAmountIn % streamCount != 0) {
                        dustTokenAmount += (newTokenOutAmountIn - (streamCount * swapPerStream));
                        newTokenOutAmountIn = streamCount * swapPerStream; // reAssigning newTokenOutAmountIn without dust tokens
                    }

                    // updating oppositeSwap
                    bytes memory updatedSwapData_opposite = abi.encode(
                        oppositePairId,
                        tokenOutAmountOut,
                        newTokenOutAmountIn,
                        oppositeSwap.completed,
                        streamCount,
                        streamCount,
                        swapPerStream,
                        dustTokenAmount,
                        2
                    );

                    IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(
                        updatedSwapData_opposite, executionPriceOppositeKey, i, true
                    );
                }
                // 3. we terminate the loop as we have completed the frontSwap
                break;
            }
        }

        return currentSwap;
    }

    function _settleCurrentSwapAgainstOpposite(
        Swap memory currentSwap,
        uint256 executionPriceOppositeKey,
        uint256 executionPriceCurrentSwap,
        uint256 executionPriceOppositeSwap
    ) internal returns (Swap memory) {
        uint256 initialTokenInAmountIn = currentSwap.swapAmountRemaining;
        uint256 dustTokenInAmountIn = currentSwap.dustTokenAmount;

        // tokenInAmountIn is the amount of tokenIn that is remaining to be processed from the selected swap
        // it contains the dust token amount
        uint256 tokenInAmountIn = initialTokenInAmountIn + dustTokenInAmountIn;
        address tokenIn = currentSwap.tokenIn;
        address tokenOut = currentSwap.tokenOut;

        // we need to look for the opposite swaps
        bytes32 oppositePairId = bytes32(abi.encodePacked(tokenOut, tokenIn));
        Swap[] memory oppositeSwaps;

        uint256 priceKey = executionPriceOppositeKey;

        while (true) {
            oppositeSwaps = pool.orderBook(oppositePairId, priceKey, true);
            if (oppositeSwaps.length == 0) {
                priceKey = priceKey - PRICE_PRECISION; // will call pool handling function
            } else {
                break;
            }
        }

        /*
            iterate on all the opposite swaps
            And check that if the amountOut of the oppositeSwap < currentSwapAmountIn
            if yes the consume oppositeSwap, and move on to the next oppositeSwap
            transferOut the swapAmoutOut asset

            if amountOut of oppositeSwap > currentSwapAmountIn
            then consume the currentSwap, break the loop
            transferIn the swapAmountIn assets
            update the oppositeSwap struct
        */
        (,, uint256 reserveA_In,,,) = pool.poolInfo(address(tokenIn));
        (,, uint256 reserveA_Out,,,) = pool.poolInfo(address(tokenOut));

        uint256 reserveAInFromPrice = getOtherReserveFromPrice(executionPriceOppositeSwap, reserveA_Out);
        uint256 reserveAOutFromPrice = getOtherReserveFromPrice(executionPriceCurrentSwap, reserveA_In);

        // the number of opposite swaps
        // uint256 oppositeSwapsCount = oppositeBack - oppositeFront;
        // Payout[] memory oppositePayouts = new Payout[](oppositeSwapsCount);

        // now we need to loop through the opposite swaps and to process them
        uint256 swapRemoved;
        for (uint256 i = 0; i < oppositeSwaps.length;) {
            Swap memory oppositeSwap = oppositeSwaps[i];

            // tokenOutAmountIn is the amount of tokenOut that is remaining to be processed from the opposite swap
            // it contains opp swap dust token
            uint256 tokenOutAmountIn = oppositeSwap.swapAmountRemaining + oppositeSwap.dustTokenAmount;

            // we need to calculate the amount of tokenOut for the given tokenInAmountIn -> tokenA -> tokenB
            uint256 tokenOutAmountOut = getAmountOut(tokenInAmountIn, reserveA_In, reserveAOutFromPrice);

            // we need to calculate the amount of tokenIn for the given tokenOutAmountIn -> tokenB -> tokenA
            uint256 tokenInAmountOut = getAmountOut(tokenOutAmountIn, reserveA_Out, reserveAInFromPrice);

            // we need to check if the amount of tokenIn that we need to send to the user is less than the amount of tokenIn that is remaining to be processed
            if (tokenInAmountIn > tokenInAmountOut) {
                // 1. we keep in memory the swapUser, tokenOut address and the amountOutSwap in memory to transfer the tokens

                IPoolActions(POOL_ADDRESS).transferTokens(
                    oppositeSwap.tokenOut, oppositeSwap.user, tokenInAmountOut + oppositeSwap.amountOut
                );

                IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(oppositePairId, executionPriceOppositeKey, i, true);

                uint256 newTokenInAmountIn = tokenInAmountIn - tokenInAmountOut;

                currentSwap.swapAmountRemaining = newTokenInAmountIn;
                currentSwap.amountOut += tokenOutAmountIn;
                tokenInAmountIn = newTokenInAmountIn;
                // 4. we continue to the next oppositeSwap

                swapRemoved++;
                if (swapRemoved == oppositeSwaps.length) {
                    break;
                }
                uint256 lastIndex = oppositeSwaps.length - swapRemoved;
                oppositeSwaps[i] = oppositeSwaps[lastIndex];
                delete oppositeSwaps[lastIndex];
            } else {
                // 1. frontSwap is completed and is taken out of the stream queue

                currentSwap.amountOut += tokenOutAmountOut;
                currentSwap.completed = true; // we don't need to do this
                currentSwap.dustTokenAmount = 0;

                // 2. we recalculate the oppositeSwap conditions and update it (if tokenInAmountIn == tokenInAmountOut we complete the oppositeSwap)

                //both swaps consuming each other
                if (tokenInAmountIn == tokenInAmountOut) {
                    IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(oppositePairId, executionPriceOppositeKey, i, true);

                    IPoolActions(POOL_ADDRESS).transferTokens(
                        oppositeSwap.tokenOut, oppositeSwap.user, tokenInAmountOut + oppositeSwap.amountOut
                    );
                } else {
                    // only front is getting consumed. so we need to update opposite one
                    uint256 newTokenOutAmountIn = tokenOutAmountIn - tokenOutAmountOut;
                    uint256 streamCount = getStreamCount(tokenOut, tokenIn, newTokenOutAmountIn);
                    uint256 swapPerStream = newTokenOutAmountIn / streamCount;
                    uint256 dustTokenAmount;
                    if (newTokenOutAmountIn % streamCount != 0) {
                        dustTokenAmount += (newTokenOutAmountIn - (streamCount * swapPerStream));
                        newTokenOutAmountIn = streamCount * swapPerStream; // reAssigning newTokenOutAmountIn without dust tokens
                    }

                    // updating oppositeSwap
                    bytes memory updatedSwapData_opposite = abi.encode(
                        oppositePairId,
                        tokenOutAmountOut,
                        newTokenOutAmountIn,
                        oppositeSwap.completed,
                        streamCount,
                        streamCount,
                        swapPerStream,
                        dustTokenAmount
                    );

                    IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(
                        updatedSwapData_opposite, executionPriceOppositeKey, i, true
                    );
                }
                // 3. we terminate the loop as we have completed the frontSwap
                break;
            }
        }

        return currentSwap;
    }

    function _settleCurrentSwapAgainstPool(Swap memory currentSwap, uint256 executionPriceCurrentSwap)
        internal
        returns (Swap memory)
    {
        (uint256 reserveD_In,, uint256 reserveA_In,,,) = pool.poolInfo(address(currentSwap.tokenIn));
        uint256 reserveAOutFromPrice = getOtherReserveFromPrice(executionPriceCurrentSwap, reserveA_In);

        // TODO: NEED TO FIX RESERVE D EQUATION
        uint256 reserveDOutFromPrice = getOtherReserveFromPrice(executionPriceCurrentSwap, reserveD_In);

        uint256 swapAmountIn = currentSwap.swapPerStream;

        // the logic here is that we add, if present, the dust token amount to the swapAmountRemaining on the last swap (when streamsRemaining == 1)
        if (currentSwap.streamsRemaining == 1) {
            swapAmountIn += currentSwap.dustTokenAmount;
        }

        console.log("swapAmountIn", swapAmountIn);
        console.log("reserveA_In", reserveA_In);

        (uint256 dToUpdate, uint256 amountOut) =
            getSwapAmountOut(swapAmountIn, reserveA_In, reserveAOutFromPrice, reserveD_In, reserveDOutFromPrice);

        bytes memory updateReservesParams =
            abi.encode(true, currentSwap.tokenIn, currentSwap.tokenOut, swapAmountIn, dToUpdate, amountOut, dToUpdate);
        IPoolActions(POOL_ADDRESS).updateReserves(updateReservesParams);

        currentSwap.streamsRemaining--;
        if (currentSwap.streamsRemaining == 0) {
            currentSwap.completed = true;
        } else {
            currentSwap.swapAmountRemaining -= swapAmountIn;
        }
        currentSwap.amountOut += amountOut;

        return currentSwap;
    }

    function _insertInOrderBook(bytes32 pairId, Swap memory _swap, uint256 executionPriceKey, bool isLimitOrder)
        internal
    {
        IPoolActions(POOL_ADDRESS).updateOrderBook(pairId, _swap, executionPriceKey, isLimitOrder);
    }

    /**
     * @notice here we are maintaining the queue for the given pairId only
     * if the price is less than the execution price we add the swap to the stream queue
     * if the price is greater than the execution price we add the swap to the pending queue
     * @param pairId bytes32 the pairId for the given pair
     * @param swapDetails Swap the swap details
     * @param currentPrice uint256 the current price of the pair
     */
    function _maintainQueue(bytes32 pairId, Swap memory swapDetails, uint256 currentPrice) internal {
        // if execution price 0 (stream queue) , otherwise another queue
        // add into queue
        if (swapDetails.executionPrice <= currentPrice) {
            (,, uint256 back) = pool.pairStreamQueue(pairId);
            swapDetails.swapID = back;
            IPoolActions(POOL_ADDRESS).enqueueSwap_pairStreamQueue(pairId, swapDetails);
        } else {
            (Swap[] memory swaps_pending, uint256 front, uint256 back) = pool.pairPendingQueue(pairId);
            swapDetails.swapID = back;

            if (back - front == 0) {
                IPoolActions(POOL_ADDRESS).enqueueSwap_pairPendingQueue(pairId, swapDetails);
            } else {
                if (swapDetails.executionPrice >= swaps_pending[back - 1].executionPrice) {
                    IPoolActions(POOL_ADDRESS).enqueueSwap_pairPendingQueue(pairId, swapDetails);
                } else {
                    IPoolActions(POOL_ADDRESS).enqueueSwap_pairPendingQueue(pairId, swapDetails);
                    IPoolActions(POOL_ADDRESS).sortPairPendingQueue(pairId);
                }
            }
        }
    }

    function getStreamCount(address tokenIn, address tokenOut, uint256 amountIn) public view returns (uint256) {
        (uint256 reserveD_In,,,,,) = pool.poolInfo(address(tokenIn));
        (uint256 reserveD_Out,,,,,) = pool.poolInfo(address(tokenOut));

        uint256 minPoolDepth = reserveD_In <= reserveD_Out ? reserveD_In : reserveD_Out;
        bytes32 poolId = getPoolId(tokenIn, tokenOut); // for pair slippage only. Not an ID for pair direction queue
        return calculateStreamCount(amountIn, pool.pairSlippage(poolId), minPoolDepth);
    }

    function getStreamCountForDPool(address tokenIn, uint256 amountIn) external view override returns (uint256) {
        (uint256 reserveD,,,,,) = pool.poolInfo(address(tokenIn));
        return calculateStreamCount(amountIn, pool.globalSlippage(), reserveD);
    }

    function getExecutionPriceLower(uint256 executionPrice) public pure returns (uint256) {
        uint256 mod = executionPrice % PRICE_PRECISION; // @audit decide decimals for precission + use global variable for precission
        return executionPrice - mod;
    }

    function getReciprocalOppositePrice(uint256 executionPrice, uint256 reserveA) public pure returns (uint256) {
        // and divide rB/rA;
        uint256 reserveB = getOtherReserveFromPrice(executionPrice, reserveA); // @audit confirm scaling
        return getExecutionPrice(reserveB, reserveA); // @audit returned price needs to go in getExecutionPriceLower() ??
    }

    function getOtherReserveFromPrice(uint256 executionPrice, uint256 reserveA) public pure returns (uint256) {
        return reserveA.wdiv(executionPrice); // @audit confirm scaling
    }

    function _createTokenStreamObj(address token, uint256 amount)
        internal
        view
        returns (StreamDetails memory streamDetails)
    {
        (uint256 reserveD,,,,,) = pool.poolInfo(token);

        uint256 streamCount = calculateStreamCount(amount, pool.globalSlippage(), reserveD);
        uint256 swapPerStream = amount / streamCount;
        streamDetails = StreamDetails({
            token: token,
            amount: amount,
            streamCount: streamCount,
            streamsRemaining: streamCount,
            swapPerStream: swapPerStream,
            swapAmountRemaining: amount
        });
    }

    function getPoolId(address tokenA, address tokenB) public pure returns (bytes32) {
        (address A, address B) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(A, B));
    }

    function calculateLpUnitsToMint(
        uint256 lpUnitsDepth, // P => depth of lpUnits
        uint256 amount, // a => assets incoming
        uint256 reserveA, // A => assets depth
        uint256 dIncoming, // d
        uint256 dUnitsDepth // D => depth of dUnits
    ) public pure returns (uint256) {
        // p = P * (dA + Da + 2da)/(dA + Da + 2DA)
        if (lpUnitsDepth == 0 && dIncoming == 0) {
            return amount;
        } else if (lpUnitsDepth == 0 && amount == 0) {
            return dIncoming;
        }

        uint256 num = (dIncoming * reserveA) + (dUnitsDepth * amount) + (2 * dIncoming * amount);
        uint256 den = (dIncoming * reserveA) + (dUnitsDepth * amount) + (2 * dUnitsDepth * reserveA);

        return lpUnitsDepth * (num / den);
    }

    function calculateDUnitsToMint(uint256 amount, uint256 reserveA, uint256 reserveD, uint256 initialDToMint)
        public
        pure
        returns (uint256)
    {
        if (reserveD == 0) {
            return initialDToMint;
        }

        return reserveD.wmul(amount).wdiv(reserveA);
    }

    // 0.15% will be 15 poolSlippage. 100% is 100000 units
    function calculateStreamCount(uint256 amount, uint256 poolSlippage, uint256 reserveD)
        public
        pure
        override
        returns (uint256)
    {
        if (amount == 0) return 0;
        // streamQuantity = SwappedAmount/(globalMinSlippage * PoolDepth)

        // (10e18 * 10000) / (10000-15 * 15e18)

        uint256 result = ((amount * STREAM_COUNT_PRECISION) / (((STREAM_COUNT_PRECISION - poolSlippage) * reserveD)));
        return result < 1 ? 1 : result;
    }

    function calculateAssetTransfer(uint256 lpUnits, uint256 reserveA, uint256 totalLpUnits)
        public
        pure
        override
        returns (uint256)
    {
        return (reserveA.wmul(lpUnits)).wdiv(totalLpUnits);
    }

    function calculateDToDeduct(uint256 lpUnits, uint256 reserveD, uint256 totalLpUnits)
        public
        pure
        override
        returns (uint256)
    {
        return reserveD.wmul(lpUnits).wdiv(totalLpUnits);
    }

    function getSwapAmountOut(
        uint256 amountIn,
        uint256 reserveA,
        uint256 reserveB,
        uint256 reserveD1,
        uint256 reserveD2
    ) public pure override returns (uint256, uint256) {
        // d1 = a * D1 / a + A
        // return d1 -> this will be updated in the pool
        // b = d * B / d + D2 -> this will be returned to the pool

        //         10 * 1e18
        //         100000000000000000000
        //         1000000000000000000
        uint256 d1 = (amountIn.wmul(reserveD1)).wdiv(amountIn + reserveA);
        return (d1, ((d1 * reserveB) / (d1 + reserveD2)));
    }

    function getSwapAmountOutFromD(uint256 dIn, uint256 reserveA, uint256 reserveD) public pure returns (uint256) {
        return ((dIn * reserveA) / (dIn + reserveD));
    }

    function getTokenOut(uint256 dAmount, uint256 reserveA, uint256 reserveD)
        external
        pure
        override
        returns (uint256)
    {
        return (dAmount.wmul(reserveA)).wdiv(dAmount + reserveD);
    }

    function getDOut(uint256 tokenAmount, uint256 reserveA, uint256 reserveD)
        external
        pure
        override
        returns (uint256)
    {
        return (tokenAmount.wmul(reserveD)).wdiv(tokenAmount + reserveA);
    }

    function getExecutionPrice(uint256 reserveA1, uint256 reserveA2) public pure override returns (uint256) {
        return reserveA1.wdiv(reserveA2);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        return amountIn.wmul(reserveIn).wdiv(reserveOut);
    }

    function updatePoolAddress(address poolAddress) external override onlyOwner {
        emit PoolAddressUpdated(POOL_ADDRESS, poolAddress);
        POOL_ADDRESS = poolAddress;
        pool = IPoolStates(POOL_ADDRESS);
    }

    function poolExist(address tokenAddress) private view returns (bool) {
        (,,,,, bool initialized) = pool.poolInfo(tokenAddress);
        return initialized;
    }
}
