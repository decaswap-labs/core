// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolStates} from "./interfaces/pool/IPoolStates.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IPoolActions} from "./interfaces/pool/IPoolActions.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {Swap, LiquidityStream, StreamDetails, TYPE_OF_LP} from "./lib/SwapQueue.sol";

contract PoolLogic is Ownable, IPoolLogic {
    address public override POOL_ADDRESS;
    IPoolStates public pool;

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
            calculateLpUnitsToMint(0, tokenAmount, tokenAmount, initialDToMint, initialDToMint),
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
        // enqueue
        IPoolActions(POOL_ADDRESS).enqueueLiquidityStream(
            pairId,
            LiquidityStream({
                user: user,
                poolAStream: _createTokenStreamObj(token, tokenAmount), // poolA stream
                poolBStream: _createTokenStreamObj(liquidityToken, liquidityTokenAmount), // poolB stream
                typeofLp: TYPE_OF_LP.DUAL_TOKEN,
                dAmountOut: 0
            })
        );

        IPoolActions(POOL_ADDRESS).initPool(token);

        // stream D against token B
        _streamLiquidity(token, liquidityToken);
    }

    function addLiqDualToken(address tokenA, address tokenB, address user, uint256 amountA, uint256 amountB)
        external
        onlyRouter
    {
        bytes32 pairId = keccak256(abi.encodePacked(tokenA, tokenB));
        // enqueue
        IPoolActions(POOL_ADDRESS).enqueueLiquidityStream(
            pairId,
            LiquidityStream({
                user: user,
                poolAStream: _createTokenStreamObj(tokenA, amountA), // poolA stream
                poolBStream: _createTokenStreamObj(tokenB, amountB), // poolB stream
                typeofLp: TYPE_OF_LP.DUAL_TOKEN,
                dAmountOut: 0
            })
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
        (
            uint256 reserveD_A,
            uint256 poolOwnershipUnitsTotal_A,
            uint256 reserveA_A,
            uint256 initialDToMint_A,
            uint256 poolFeeCollected_A,
            bool initialized_A
        ) = pool.poolInfo(token);

        uint256 streamCountA = calculateStreamCount(amount, pool.globalSlippage(), reserveD_A);
        uint256 swapPerStreamA = amount / streamCountA;

        // encoding address with itself so pairId is same here and in _streamLiquidity() and _streamLiquidity() don't break
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

        _streamLiquidity(token, token); //WHY USING STREAMLIQUIDITY HERE?
    }

    function _streamA(LiquidityStream memory liqStream)
        internal
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
        // means the stream is completed
        if (poolANewStreamsRemaining == 0 && liqStream.poolBStream.streamsRemaining == 0) {
            IPoolActions(POOL_ADDRESS).dequeueSwap_poolStreamQueue(pairId);
        }
    }

    function _streamD(LiquidityStream memory liqStream)
        internal
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
        ) = pool.poolInfo(liqStream.poolAStream.token);
        poolBNewStreamsRemaining = liqStream.poolAStream.streamsRemaining;
        if (liqStream.poolBStream.swapAmountRemaining != 0) {
            poolBNewStreamsRemaining--;
            poolBReservesToAdd = liqStream.poolBStream.swapPerStream;
            (changeInD,) = getSwapAmountOut(liqStream.poolBStream.swapPerStream, reserveA_B, 0, reserveD_B, 0);
        }
        // means the stream is completed
        if (liqStream.poolAStream.streamsRemaining == 0 && poolBNewStreamsRemaining == 0) {
            IPoolActions(POOL_ADDRESS).dequeueSwap_poolStreamQueue(pairId);
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

        uint256 streamCount;
        uint256 swapPerStream;
        uint256 minPoolDepth;

        bytes32 poolId;

        // break into streams
        minPoolDepth = reserveD_In <= reserveD_Out ? reserveD_In : reserveD_Out;
        poolId = getPoolId(tokenIn, tokenOut); // for pair slippage only. Not an ID for pair direction queue
        streamCount = calculateStreamCount(amountIn, pool.pairSlippage(poolId), minPoolDepth);
        swapPerStream = amountIn / streamCount;

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

    function _executeStream(address tokenIn, address tokenOut) internal {
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
        bytes32 pairId = keccak256(abi.encodePacked(tokenIn, tokenOut));

        // loading the front swap from the stream queue
        (Swap[] memory swaps, uint256 front, uint256 back) = pool.pairStreamQueue(pairId);
        Swap memory frontSwap = swaps[front];

        // ------------------------ CHECK OPP DIR SWAP --------------------------- //

        //TODO: Deduct fees from amount out = 5BPS.
        bytes32 otherPairId = keccak256(abi.encodePacked(tokenOut, tokenIn));
        (Swap[] memory oppositeSwaps, uint256 oppositeFront, uint256 oppositeBack) = pool.pairStreamQueue(otherPairId);

        if (oppositeBack - oppositeFront != 0) {
            Swap memory oppositeSwap = oppositeSwaps[oppositeFront];

            // A->B, amountOutA is B
            uint256 amountOutA = (frontSwap.swapAmountRemaining * reserveA_In) / reserveA_Out;
            uint256 amountOutB = (oppositeSwap.swapAmountRemaining * reserveA_Out) / reserveA_In;
            /* 
            I have taken out amountOut of both swap directions
            Now one swap should consume the other one
            How to define that?

            I am selling 50 TKN for (10)-> Calculated USDC
            Alice is buying 50 USDC for (250)-> Calculated TKN

            I should be able to fill alice's order completely. By giving her 50 TKN, and take 10 USDC. 

            AmountIn1 = AmountIn1 - AmountIn1 // 50-50 (Order fulfilled as I have given all the TKN to alice)
            AmountOut1 = AmountOut1 // 10 (As Alice has given me 10 USDC, which equals to amount I have calculated)

            AmountIn2 = AmountIn2 - AmountOut2 // 50-10, as alice has given me 10. So she has 40 left
            AmountOut2 = AmountOut2 + AmountIn1 // 0+50, Alice wanted 250 tokens, but now she has only those 
            tokens which I was selling. Which is 50
        */
            // when both swaps consumes each other fully
            // if(frontSwap.swapAmountRemaining == amountOutB) {
            //     // consuming frontSwap fully
            //     bytes memory updatedSwapData_front = abi.encode(pairId, oppositeSwap.swapAmountRemaining, 0, true, 0, frontSwap.streamsCount, frontSwap.swapPerStream);
            //     IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_front);

            //     // consuming oppositeSwap fully
            //     bytes memory updatedSwapData_opposite = abi.encode(otherPairId, frontSwap.swapAmountRemaining, 0, true, 0, oppositeSwap.streamsCount, oppositeSwap.swapPerStream);
            //     IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_opposite);
            // require(back > front, "Queue is empty");
            // IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(pairId);

            // require(oppositeBack > oppositeFront, "Queue is empty");
            // IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(otherPairId);
            // // transferring tokens to frontSwapUser
            // IPoolActions(POOL_ADDRESS).transferTokens(frontSwap.tokenOut, frontSwap.user, oppositeSwap.swapAmountRemaining);
            // // transferring tokens to oppositeSwapUser
            // IPoolActions(POOL_ADDRESS).transferTokens(oppositeSwap.tokenOut, oppositeSwap.user, frontSwap.swapAmountRemaining);

            // }
            // else
            // consume front swap fully when true and vice versa
            if (frontSwap.swapAmountRemaining < amountOutB) {
                bytes memory updateReservesParams =
                    abi.encode(true, tokenIn, tokenOut, frontSwap.swapAmountRemaining, 0, amountOutA, 0);
                IPoolActions(POOL_ADDRESS).updateReserves(updateReservesParams);
                // updating frontSwap
                bytes memory updatedSwapData_front =
                    abi.encode(pairId, amountOutA, 0, true, 0, frontSwap.streamsCount, frontSwap.swapPerStream);
                IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_front);
                bytes memory updatedSwapData_opposite;

                if (amountOutA != oppositeSwap.swapPerStream) {
                    // recalc stream count and swap per stream
                    bytes32 poolId = getPoolId(tokenOut, tokenIn); // for pair slippage only. Not an ID for pair direction queue
                    uint256 minPoolDepth = reserveD_In <= reserveD_Out ? reserveD_In : reserveD_Out;
                    uint256 newStreamCount = calculateStreamCount(
                        oppositeSwap.swapAmountRemaining - amountOutA, pool.pairSlippage(poolId), minPoolDepth
                    );

                    uint256 newSwapPerStream = (oppositeSwap.swapAmountRemaining - amountOutA) / newStreamCount;
                    // updating oppositeSwap
                    updatedSwapData_opposite = abi.encode(
                        otherPairId,
                        frontSwap.swapAmountRemaining,
                        oppositeSwap.swapAmountRemaining - amountOutA,
                        oppositeSwap.completed,
                        newStreamCount,
                        newStreamCount,
                        newSwapPerStream
                    );
                } else {
                    // updating oppositeSwap
                    updatedSwapData_opposite = abi.encode(
                        otherPairId,
                        frontSwap.swapAmountRemaining,
                        oppositeSwap.swapAmountRemaining - amountOutA,
                        oppositeSwap.completed,
                        oppositeSwap.streamsRemaining - 1,
                        oppositeSwap.streamsCount,
                        oppositeSwap.swapPerStream
                    );
                }

                IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_opposite);

                completedSwapToken = frontSwap.tokenOut;
                swapUser = frontSwap.user;
                amountOutSwap = frontSwap.amountOut + amountOutA;

                require(back > front, "Queue is empty");
                IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(pairId);
            } else {
                bytes memory updateReservesParams =
                    abi.encode(false, tokenIn, tokenOut, amountOutB, 0, oppositeSwap.swapAmountRemaining, 0); // no change in D

                IPoolActions(POOL_ADDRESS).updateReserves(updateReservesParams);

                // consuming oppositeSwap fully
                bytes memory updatedSwapData_opposite = abi.encode(
                    otherPairId, amountOutB, 0, true, 0, oppositeSwap.streamsCount, oppositeSwap.swapPerStream
                );
                IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_opposite);

                bytes memory updatedSwapData_Front;

                if (amountOutB != frontSwap.swapPerStream) {
                    // recalc stream count and swap per stream
                    bytes32 poolId = getPoolId(tokenIn, tokenOut); // for pair slippage only. Not an ID for pair direction queue
                    uint256 minPoolDepth = reserveD_In <= reserveD_Out ? reserveD_In : reserveD_Out;
                    uint256 newStreamCount = calculateStreamCount(
                        frontSwap.swapAmountRemaining - amountOutB, pool.pairSlippage(poolId), minPoolDepth
                    );
                } else {
                    updatedSwapData_Front = abi.encode(
                        pairId,
                        oppositeSwap.swapAmountRemaining,
                        frontSwap.swapAmountRemaining - amountOutB,
                        frontSwap.completed,
                        frontSwap.streamsRemaining - 1,
                        frontSwap.streamsCount,
                        frontSwap.swapPerStream
                    );
                }
                // updating frontSwap
                IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_Front);

                completedSwapToken = oppositeSwap.tokenOut;
                swapUser = oppositeSwap.user;
                amountOutSwap = oppositeSwap.amountOut + amountOutB;

                require(oppositeBack > oppositeFront, "Queue is empty");
                IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(otherPairId);
            }
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
            bytes memory updatedSwapData_Front = abi.encode(
                pairId,
                amountOut,
                frontSwap.swapAmountRemaining - frontSwap.swapPerStream,
                frontSwap.completed,
                frontSwap.streamsRemaining,
                frontSwap.streamsCount,
                frontSwap.swapPerStream
            );
            IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_Front);

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
        if (lpUnitsDepth == 0) {
            return amount;
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

        return reserveD * amount / (reserveA);
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
        return (reserveA * lpUnits) / totalLpUnits;
    }

    function calculateDToDeduct(uint256 lpUnits, uint256 reserveD, uint256 totalLpUnits)
        public
        pure
        override
        returns (uint256)
    {
        return reserveD * (lpUnits / totalLpUnits);
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
        uint256 d1 = (amountIn * reserveD1) / (amountIn + reserveA);
        return (d1, ((d1 * reserveB) / (d1 + reserveD2)));
    }

    function getTokenOut(uint256 dAmount, uint256 reserveA, uint256 reserveD)
        external
        pure
        override
        returns (uint256)
    {
        return (dAmount * reserveA) / (dAmount + reserveD);
    }

    function getDOut(uint256 tokenAmount, uint256 reserveA, uint256 reserveD)
        external
        pure
        override
        returns (uint256)
    {
        return (tokenAmount * reserveD) / (tokenAmount + reserveA);
    }

    function getExecutionPrice(uint256 reserveA1, uint256 reserveA2) public pure override returns (uint256) {
        return (reserveA1 * 1e18 / reserveA2);
    }

    function updatePoolAddress(address poolAddress) external override onlyOwner {
        emit PoolAddressUpdated(POOL_ADDRESS, poolAddress);
        POOL_ADDRESS = poolAddress;
        pool = IPoolStates(POOL_ADDRESS);
    }

    function poolExist(address tokenAddress) private view returns (bool) {
        // TODO : Resolve this tuple unbundling issue
        (uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, bool initialized) = pool.poolInfo(tokenAddress);
        return initialized;
    }
}
