// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolStates} from "./interfaces/pool/IPoolStates.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IPoolActions} from "./interfaces/pool/IPoolActions.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Swap, LiquidityStream, StreamDetails, TYPE_OF_LP, GlobalPoolStream} from "src/lib/SwapQueue.sol";
import {DSMath} from "src/lib/DSMath.sol";

contract PoolLogic is Ownable, IPoolLogic {
    using DSMath for uint256;

    address public override POOL_ADDRESS;
    IPoolStates public pool;

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

    // function createPool(
    //     address token,
    //     address user,
    //     uint256 amount,
    //     uint256 minLaunchReserveA,
    //     uint256 minLaunchReserveD,
    //     uint256 initialDToMint
    // ) external onlyRouter {
    //     // hardcoding `poolFeeCollected` to zero as pool is just being created
    //     // reserveA == amount for 1st deposit
    //     bytes memory createPoolParams = abi.encode(
    //         token,
    //         user,
    //         amount,
    //         minLaunchReserveA,
    //         minLaunchReserveD,
    //         initialDToMint,
    //         calculateLpUnitsToMint(amount, 0, 0),
    //         calculateDUnitsToMint(amount, amount, 0, initialDToMint),
    //         0
    //     );
    //     IPoolActions(POOL_ADDRESS).createPool(createPoolParams);
    // }

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

    function depositToGlobalPool(address user, address token, uint256 amount) external override onlyRouter {
        bytes32 pairId = keccak256(abi.encodePacked(token, token));
        _enqueueGlobalPoolStream(pairId, user, token, amount);

        _streamGlobalStream(token);
    }

    function _enqueueGlobalPoolStream(
        bytes32 pairId,
        address user,
        address token, 
        uint256 amount
    ) internal {

        (uint256 reserveD,,,,,) = pool.poolInfo(address(token));
        uint256 streamCount = calculateStreamCount(amount, pool.globalSlippage(), reserveD);
        uint256 swapPerStream = amount/streamCount;

        IPoolActions(POOL_ADDRESS).enqueueGlobalPoolStream(
            pairId,
            GlobalPoolStream({
                user:user,
                tokenIn:token,
                tokenAmount:amount,
                streamCount:streamCount,
                streamsRemaining:streamCount,
                swapPerStream:swapPerStream,
                swapAmountRemaining:amount,
                dOut:0
            })
        );
    }

    function _streamGlobalStream(address poolA) internal {
        bytes32 pairId = keccak256(abi.encodePacked(poolA, poolA));
        (GlobalPoolStream[] memory globalPoolStream, uint256 front, uint256 back) = IPoolActions(POOL_ADDRESS).globalStreamQueue(pairId);
        // true = there are streams pending
        if (back - front != 0) {
            (
                uint256 reserveD,
                uint256 poolOwnershipUnitsTotal,
                uint256 reserveA,
                uint256 initialDToMint,
                uint256 poolFeeCollected,
                bool initialized
            ) = pool.poolInfo(poolA);

            // get the front stream
            GlobalPoolStream memory globalStream = globalPoolStream[front];

            (uint256 poolNewStreamsRemaining, uint256 poolReservesToAdd, uint256 changeInD) =
                _streamDGlobal(globalStream);

            // // update reserves
            bytes memory updatedReserves = abi.encode(poolA,poolReservesToAdd, changeInD);
            IPoolActions(POOL_ADDRESS).updateReservesGlobalStream(updatedReserves);

            bytes memory updatedGlobalPoolBalnace = abi.encode(changeInD);
            IPoolActions(POOL_ADDRESS).updateGlobalPoolBalance(updatedGlobalPoolBalnace);

            bytes memory updatedGlobalPoolUserBalanace = abi.encode(globalStream.user,poolA,changeInD);
            IPoolActions(POOL_ADDRESS).updateGlobalPoolUserBalance(updatedGlobalPoolUserBalanace);

            // update stream struct
            bytes memory updatedStreamData = abi.encode(
                pairId,
                poolNewStreamsRemaining,
                globalStream.swapPerStream,
                changeInD
            );
            IPoolActions(POOL_ADDRESS).updateGlobalStreamQueueStream(updatedStreamData);

            if (poolNewStreamsRemaining == 0) {
                IPoolActions(POOL_ADDRESS).dequeueGlobalStream_streamQueue(pairId);
            }
        }
    }

    function _streamA(LiquidityStream memory liqStream)
        internal
        view
        returns (uint256 poolANewStreamsRemaining, uint256 poolAReservesToAdd, uint256 lpUnitsAToMint)
    {
        // both poolStreamA and poolStreamB tokens should be same in case of single sided liquidity
        bytes32 pairId = keccak256(abi.encodePacked(liqStream.poolAStream.token, liqStream.poolBStream.token));
        (
            uint256 reserveD_A,
            uint256 poolOwnershipUnitsTotal_A,
            uint256 reserveA_A,
            uint256 initialDToMint_A,
            uint256 poolFeeCollected_A,
            bool initialized_A
        ) = pool.poolInfo(liqStream.poolAStream.token);
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
        bytes32 pairId = keccak256(abi.encodePacked(liqStream.poolAStream.token, liqStream.poolBStream.token));
        (
            uint256 reserveD_B,
            uint256 poolOwnershipUnitsTotal_B,
            uint256 reserveA_B,
            uint256 initialDToMint_B,
            uint256 poolFeeCollected_B,
            bool initialized_B
        ) = pool.poolInfo(liqStream.poolBStream.token);
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
        returns (uint256 poolBNewStreamsRemaining, uint256 poolBReservesToAdd, uint256 changeInD)
    {
        // both poolStreamA and poolStreamB tokens should be same in case of single sided liquidity
        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        ) = pool.poolInfo(globalStream.tokenIn);
        poolBNewStreamsRemaining = globalStream.streamsRemaining;
        if (globalStream.swapAmountRemaining != 0) {
            poolBNewStreamsRemaining--;
            poolBReservesToAdd = globalStream.swapPerStream;
            (changeInD,) = getSwapAmountOut(globalStream.swapPerStream, reserveA, 0, reserveD, 0);
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
            (
                uint256 reserveD_A,
                uint256 poolOwnershipUnitsTotal_A,
                uint256 reserveA_A,
                uint256 initialDToMint_A,
                uint256 poolFeeCollected_A,
                bool initialized_A
            ) = pool.poolInfo(poolA);

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

    function addLiquidity(address token, address user, uint256 amount) external onlyRouter {
        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        ) = pool.poolInfo(address(token));
        reserveA += amount;
        uint256 newLpUnits = calculateLpUnitsToMint(poolOwnershipUnitsTotal, amount, reserveA, 0, reserveD);
        uint256 newDUnits = calculateDUnitsToMint(amount, reserveA, reserveD, initialDToMint);
        bytes memory addLiqParams = abi.encode(token, user, amount, newLpUnits, newDUnits, 0); // poolFeeCollected = 0 until logic is finalized
        IPoolActions(POOL_ADDRESS).addLiquidity(addLiqParams);
    }

    function removeLiquidity(address token, address user, uint256 lpUnits) external onlyRouter {
        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        ) = pool.poolInfo(address(token));
        uint256 assetToTransfer = calculateAssetTransfer(lpUnits, reserveA, poolOwnershipUnitsTotal);
        uint256 dAmountToDeduct = calculateDToDeduct(lpUnits, reserveD, poolOwnershipUnitsTotal);
        bytes memory removeLiqParams = abi.encode(token, user, lpUnits, assetToTransfer, dAmountToDeduct, 0); // poolFeeCollected = 0 until logic is finalized
        IPoolActions(POOL_ADDRESS).removeLiquidity(removeLiqParams);
    }

    function swap(address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 executionPrice)
        external
        onlyRouter
    {
        (
            uint256 reserveD_In,
            uint256 poolOwnershipUnitsTotal_In,
            uint256 reserveA_In,
            uint256 initialDToMint_In,
            uint256 poolFeeCollected_In,
            bool initialized_In
        ) = pool.poolInfo(address(tokenIn));

        (
            uint256 reserveD_Out,
            uint256 poolOwnershipUnitsTotal_Out,
            uint256 reserveA_Out,
            uint256 initialDToMint_Out,
            uint256 poolFeeCollected_Out,
            bool initialized_Out
        ) = pool.poolInfo(address(tokenOut));

        // break into streams
        uint256 streamCount = getStreamCount(tokenIn, tokenOut, amountIn);
        uint256 swapPerStream = amountIn / streamCount;

        // initiate swapqueue per direction
        bytes32 pairId = keccak256(abi.encodePacked(tokenIn, tokenOut)); // for one direction

        uint256 currentPrice = getExecutionPrice(reserveA_In, reserveA_Out);

        _maintainQueue(
            pairId,
            Swap({
                swapID: 0, // will be filled in if/else
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
            }),
            currentPrice
        );

        _executeStream(tokenIn, tokenOut);
    }

    function processPair(address tokenIn, address tokenOut) external onlyRouter {
        _executeStream(tokenIn, tokenOut);
    }

    /**
     * @notice here we are executing the stream for the given pair
     * we are processing the front swap from the stream queue
     * @param tokenIn the token that is being swapped
     * @param tokenOut the token that is being received
     * //TODO: Deduct fees from amount out = 5BPS.
     */
    function _executeStream(address tokenIn, address tokenOut) internal {
        bytes32 pairId = keccak256(abi.encodePacked(tokenIn, tokenOut));
        // loading the front swap from the stream queue
        (Swap[] memory swaps, uint256 front, uint256 back) = pool.pairStreamQueue(pairId);
        // TODO Don't we need to return if the queue is empty?
        if (front == back) {
            return;
        }

        Swap memory frontSwap = swaps[front]; // Here we are grabbing the first swap from the queue

        (
            uint256 reserveD_In,
            uint256 poolOwnershipUnitsTotal_In,
            uint256 reserveA_In,
            uint256 initialDToMint_In,
            uint256 poolFeeCollected_In,
            bool initialized_In
        ) = pool.poolInfo(address(tokenIn));

        (
            uint256 reserveD_Out,
            uint256 poolOwnershipUnitsTotal_Out,
            uint256 reserveA_Out,
            uint256 initialDToMint_Out,
            uint256 poolFeeCollected_Out,
            bool initialized_Out
        ) = pool.poolInfo(address(tokenOut));

        address completedSwapToken;
        address swapUser;
        uint256 amountOutSwap;

        frontSwap = _processOppositeSwaps(frontSwap);
        bytes memory updatedSwapData_front;

        // the frontSwap has been totally consumed by the opposite swaps
        if (frontSwap.completed) {
            // we can update the swap stream queue
            updatedSwapData_front = abi.encode(
                pairId,
                frontSwap.amountOut,
                frontSwap.swapAmountRemaining,
                frontSwap.completed,
                frontSwap.streamsRemaining,
                frontSwap.streamsCount,
                frontSwap.swapPerStream
            );
            IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_front);

            // we can dequeue the swap stream queue
            IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(pairId);

            // we prepare the tokens to be transferred
            completedSwapToken = frontSwap.tokenOut;
            swapUser = frontSwap.user;
            amountOutSwap = frontSwap.amountOut;
        } else {
            (uint256 dToUpdate, uint256 amountOut) =
                getSwapAmountOut(frontSwap.swapPerStream, reserveA_In, reserveA_Out, reserveD_In, reserveD_Out);

            bytes memory updateReservesParams =
                abi.encode(true, tokenIn, tokenOut, frontSwap.swapPerStream, dToUpdate, amountOut, dToUpdate);
            IPoolActions(POOL_ADDRESS).updateReserves(updateReservesParams);

            frontSwap.streamsRemaining--;
            if (frontSwap.streamsRemaining == 0) {
                frontSwap.completed = true;
                completedSwapToken = frontSwap.tokenOut;
                swapUser = frontSwap.user;
                amountOutSwap = frontSwap.amountOut + amountOut;
            }
            // updating frontSwap
            updatedSwapData_front = abi.encode(
                pairId,
                amountOut,
                frontSwap.swapAmountRemaining - frontSwap.swapPerStream,
                frontSwap.completed,
                frontSwap.streamsRemaining,
                frontSwap.streamsCount,
                frontSwap.swapPerStream
            );
            IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_front);

            if (frontSwap.streamsRemaining == 0) {
                // @todo make a function of this error
                require(back > front, "Queue is empty");
                IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(pairId);
            }
        }

        // --------------------------- HANDLE PENDING SWAP INSERTION ----------------------------- //
        (Swap[] memory swaps_pending, uint256 front_pending, uint256 back_pending) = pool.pairPendingQueue(pairId);

        if (back_pending - front_pending > 0) {
            Swap memory frontPendingSwap = swaps_pending[front_pending];

            (,, uint256 reserveA_In_New,,,) = pool.poolInfo(address(frontPendingSwap.tokenIn));

            (,, uint256 reserveA_Out_New,,,) = pool.poolInfo(address(frontPendingSwap.tokenOut));

            uint256 executionPriceInOrder = frontPendingSwap.executionPrice;
            uint256 executionPriceLatest = getExecutionPrice(reserveA_In_New, reserveA_Out_New);

            if (executionPriceLatest >= executionPriceInOrder) {
                IPoolActions(POOL_ADDRESS).enqueueSwap_pairStreamQueue(pairId, frontPendingSwap);
                require(back_pending > front_pending, "Queue is empty");
                IPoolActions(POOL_ADDRESS).dequeueSwap_pairPendingQueue(pairId);
            }
        }

        // transferring tokens
        if (completedSwapToken != address(0)) {
            IPoolActions(POOL_ADDRESS).transferTokens(completedSwapToken, swapUser, amountOutSwap);
        }
    }

    /**
     * @notice here we are processing a swap, we are emptying the selected swap either with opposite swap either with the pool directly
     * this function does not update the frontSwap storage, it only processes the opposite swaps and returns the memory updated frontSwap
     * it also transfers the tokens to the users of the opposite swaps completed
     * @dev we need to be careful of the out of gas issue, we need to make sure that we are not processing a swap that is too big
     * @param frontSwap Swap struct
     * @return Swap memory the updated frontSwap or the given one if no opposite swaps found
     */
    function _processOppositeSwaps(Swap memory frontSwap) internal returns (Swap memory) {
        uint256 initialTokenInAmountIn = frontSwap.swapAmountRemaining;

        // tokenInAmountIn is the amount of tokenIn that is remaining to be processed from the selected swap
        uint256 tokenInAmountIn = initialTokenInAmountIn;
        address tokenIn = frontSwap.tokenIn;
        address tokenOut = frontSwap.tokenOut;

        // we need to look for the opposite swaps
        bytes32 oppositePairId = keccak256(abi.encodePacked(tokenOut, tokenIn));
        (Swap[] memory oppositeSwaps, uint256 oppositeFront, uint256 oppositeBack) =
            pool.pairStreamQueue(oppositePairId);

        if (oppositeBack - oppositeFront == 0) {
            return frontSwap;
        }

        (,, uint256 reserveA_In,,,) = pool.poolInfo(address(tokenIn));
        (,, uint256 reserveA_Out,,,) = pool.poolInfo(address(tokenOut));

        // the number of opposite swaps
        uint256 oppositeSwapsCount = oppositeBack - oppositeFront;
        Payout[] memory oppositePayouts = new Payout[](oppositeSwapsCount);

        // now we need to loop through the opposite swaps and to process them
        for (uint256 i = oppositeFront; i < oppositeBack; i++) {
            Swap memory oppositeSwap = oppositeSwaps[i];

            // tokenOutAmountIn is the amount of tokenOut that is remaining to be processed from the opposite swap
            uint256 tokenOutAmountIn = oppositeSwap.swapAmountRemaining;

            // we need to calculate the amount of tokenOut for the given tokenInAmountIn
            uint256 tokenOutAmountOut = getAmountOut(tokenInAmountIn, reserveA_In, reserveA_Out);

            // we need to calculate the amount of tokenIn for the given tokenOutAmountIn
            uint256 tokenInAmountOut = getAmountOut(tokenOutAmountIn, reserveA_Out, reserveA_In);

            // we need to check if the amount of tokenIn that we need to send to the user is less than the amount of tokenIn that is remaining to be processed
            if (tokenInAmountIn > tokenInAmountOut) {
                // 1. oppositeSwap is completed and is taken out of the stream queue
                bytes memory updatedSwapData_opposite = abi.encode(
                    oppositePairId, tokenInAmountOut, 0, true, 0, oppositeSwap.streamsCount, oppositeSwap.swapPerStream
                );
                IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_opposite);

                // 2. we keep in memory the swapUser, tokenOut address and the amountOutSwap in memory to transfer the tokens
                oppositePayouts[i - oppositeFront] = Payout({
                    swapUser: oppositeSwap.user,
                    token: oppositeSwap.tokenOut, // is equal to frontSwap.tokenIn
                    amount: oppositeSwap.amountOut + tokenInAmountOut
                });

                IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(oppositePairId);

                uint256 newTokenInAmountIn = tokenInAmountIn - tokenInAmountOut;

                // 3. we recalculate the main swap if it's needed

                // get new stream count only if it's consuming the last opp swap

                if (i == oppositeBack - 1) {
                    uint256 streamCount = getStreamCount(tokenIn, tokenOut, newTokenInAmountIn);
                    uint256 swapPerStream = newTokenInAmountIn / streamCount;
                    if (newTokenInAmountIn % streamCount != 0) newTokenInAmountIn = streamCount * swapPerStream;

                    // updating memory frontSwap
                    frontSwap.streamsCount = streamCount;
                    frontSwap.streamsRemaining = streamCount;
                    frontSwap.swapPerStream = swapPerStream;
                }

                frontSwap.swapAmountRemaining = newTokenInAmountIn;
                frontSwap.amountOut += tokenOutAmountIn;
                tokenInAmountIn = newTokenInAmountIn;
                // 4. we continue to the next oppositeSwap
            } else {
                // 1. frontSwap is completed and is taken out of the stream queue

                frontSwap.swapAmountRemaining = 0;
                frontSwap.streamsRemaining = 0;
                frontSwap.amountOut += tokenOutAmountOut;
                frontSwap.completed = true;

                // 2. we recalculate the oppositeSwap conditions and update it (if tokenInAmountIn == tokenInAmountOut we complete the oppositeSwap)

                // very unlikely to happen if both swaps consume eachother we complete the oppositeSwap
                if (tokenInAmountIn == tokenInAmountOut) {
                    bytes memory updatedSwapData_opposite = abi.encode(
                        oppositePairId,
                        tokenInAmountOut,
                        0,
                        true,
                        0,
                        oppositeSwap.streamsCount,
                        oppositeSwap.swapPerStream
                    );
                    IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_opposite);
                    IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(oppositePairId);

                    oppositePayouts[i] = Payout({
                        swapUser: oppositeSwap.user,
                        token: oppositeSwap.tokenOut, // is equal to frontSwap.tokenIn
                        amount: oppositeSwap.amountOut + tokenInAmountOut
                    });
                } else {
                    uint256 newTokenOutAmountIn = tokenOutAmountIn - tokenOutAmountOut;
                    uint256 streamCount = getStreamCount(tokenOut, tokenIn, newTokenOutAmountIn);
                    uint256 swapPerStream = newTokenOutAmountIn / streamCount;
                    if (newTokenOutAmountIn % streamCount != 0) newTokenOutAmountIn = streamCount * swapPerStream; // reAssigning newTokenOutAmountIn without dust tokens

                    // updating oppositeSwap
                    bytes memory updatedSwapData_opposite = abi.encode(
                        oppositePairId,
                        tokenInAmountOut,
                        newTokenOutAmountIn,
                        oppositeSwap.completed,
                        streamCount,
                        streamCount,
                        swapPerStream
                    );

                    IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_opposite);
                }
                // 3. we terminate the loop as we have completed the frontSwap
                break;
            }
        }

        for (uint256 i = 0; i < oppositePayouts.length; i++) {
            if (oppositePayouts[i].amount > 0) {
                IPoolActions(POOL_ADDRESS).transferTokens(
                    oppositePayouts[i].token, oppositePayouts[i].swapUser, oppositePayouts[i].amount
                );
            }
        }

        return frontSwap;
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

    function _createTokenStreamObj(address token, uint256 amount)
        internal
        view
        returns (StreamDetails memory streamDetails)
    {
        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        ) = pool.poolInfo(token);

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

        uint256 result = ((amount * 10000) / (((10000 - poolSlippage) * reserveD)));
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
        // TODO : Resolve this tuple unbundling issue
        (,,,,, bool initialized) = pool.poolInfo(tokenAddress);
        return initialized;
    }
}
