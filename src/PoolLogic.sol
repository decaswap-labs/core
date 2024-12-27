// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// internal libs
import { Swap, LiquidityStream, StreamDetails, RemoveLiquidityStream, GlobalPoolStream } from "src/lib/SwapQueue.sol";
import { DSMath } from "src/lib/DSMath.sol";
import { ScaleDecimals } from "src/lib/ScaleDecimals.sol";
import { PoolLogicLib } from "src/lib/PoolLogicLib.sol";

// interfaces
import { IPoolStates } from "./interfaces/pool/IPoolStates.sol";
import { IPoolLogic } from "./interfaces/IPoolLogic.sol";
import { IPoolActions } from "./interfaces/pool/IPoolActions.sol";
import { ILiquidityLogic } from "./interfaces/ILiquidityLogic.sol";

contract PoolLogic is IPoolLogic {
    using DSMath for uint256;
    using ScaleDecimals for uint256;

    // have setters for these values
    uint256 public constant PRICE_PRECISION = 1_000_000_000; // @audit test optimization
    uint8 public MAX_LIMIT_TICKS = 10;

    address public override POOL_ADDRESS;
    address public override owner;
    IPoolStates public pool;
    ILiquidityLogic public liquidityLogic;

    struct Payout {
        address swapUser;
        address token;
        uint256 amount;
    }

    modifier onlyRouter() {
        if (msg.sender != pool.ROUTER_ADDRESS()) revert NotRouter(msg.sender);
        _;
    }

    constructor(address ownerAddress, address poolAddress, address liquidityLogicAddress) {
        POOL_ADDRESS = poolAddress;
        pool = IPoolStates(POOL_ADDRESS);
        liquidityLogic = ILiquidityLogic(liquidityLogicAddress);
        owner = ownerAddress;
        emit PoolAddressUpdated(address(0), POOL_ADDRESS);
    }

    function initGenesisPool(
        address token,
        uint8 decimals,
        address user,
        uint256 tokenAmount,
        uint256 initialDToMint
    )
        external
        onlyRouter
    {
        liquidityLogic.initGenesisPool(token, decimals, user, tokenAmount, initialDToMint);
    }

    function initPool(
        address token,
        uint8 decimals,
        address liquidityToken,
        address user,
        uint256 tokenAmount,
        uint256 liquidityTokenAmount
    )
        external
        onlyRouter
    {
        IPoolActions(POOL_ADDRESS).initPool(token, decimals);
        liquidityLogic.initPool(token, decimals, liquidityToken, user, tokenAmount, liquidityTokenAmount);
    }

    function addLiqDualToken(
        address tokenA,
        address tokenB,
        address user,
        uint256 amountA,
        uint256 amountB
    )
        external
        onlyRouter
    {
        liquidityLogic.addLiqDualToken(tokenA, tokenB, user, amountA, amountB);
    }

    function addOnlyDLiquidity(address tokenA, address tokenB, address user, uint256 amountB) external onlyRouter {
        liquidityLogic.addOnlyDLiquidity(tokenA, tokenB, user, amountB);
    }

    function addOnlyTokenLiquidity(address token, address user, uint256 amount) external onlyRouter {
        liquidityLogic.addOnlyTokenLiquidity(token, user, amount);
    }

    function depositToGlobalPool(
        address user,
        address token,
        uint256 amount,
        uint256 streamCount,
        uint256 swapPerStream
    )
        external
        override
        onlyRouter
    {
        liquidityLogic.depositToGlobalPool(token, user, amount, streamCount, swapPerStream);
    }

    function withdrawFromGlobalPool(address user, address token, uint256 amount) external override onlyRouter {
        liquidityLogic.withdrawFromGlobalPool(token, user, amount);
    }

    function processGlobalStreamPairWithdraw(address token) external override onlyRouter {
        liquidityLogic.processWithdrawFromGlobalPool(token);
    }

    function processGlobalStreamPairDeposit(address token) external override onlyRouter {
        liquidityLogic.processDepositToGlobalPool(token);
    }

    function processAddLiquidity(address poolA, address poolB) external override onlyRouter {
        liquidityLogic.processAddLiquidity(poolA, poolB);
    }

    function processRemoveLiquidity(address token) external override onlyRouter {
        liquidityLogic.processRemoveLiquidity(token);
    }

    /// @notice Executes market orders for a given token from the order book
    function processMarketAndTriggerOrders() external override onlyRouter {
        address[] memory poolAddresses = IPoolActions(POOL_ADDRESS).getPoolAddresses();

        for (uint256 j = 0; j < poolAddresses.length;) {
            address token = poolAddresses[j];
            bytes32 pairId = keccak256(abi.encodePacked(token, token));
            (,, uint256 reserveA_In,,,, uint8 decimals_In) = pool.poolInfo(address(token));
            uint256 currentExecPrice =
                PoolLogicLib.getExecutionPrice(reserveA_In, reserveA_In, decimals_In, decimals_In);
            uint256 executionPriceKey = PoolLogicLib.getExecutionPriceLower(currentExecPrice, PRICE_PRECISION);

            // Get market orders (isLimitOrder = false)
            Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, false);

            // Process each swap in the order book
            for (uint256 i = 0; i < swaps.length;) {
                Swap memory currentSwap = swaps[i];

                // @todo: handle trigger orders

                if (currentSwap.typeOfOrder == 2) {
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
                } else if (currentSwap.typeOfOrder == 1 && currentSwap.executionPrice == currentExecPrice) {
                    currentSwap = _settleCurrentSwapAgainstPool(currentSwap, currentExecPrice);
                    currentSwap.typeOfOrder++;
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

    function processLiqStream(address poolA, address poolB) external onlyRouter {
        // _streamLiquidity(poolA, poolB);
    }

    function removeLiquidity(address token, address user, uint256 lpUnits) external onlyRouter {
        liquidityLogic.removeLiquidity(token, user, lpUnits);
    }

    function swap(
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 executionPrice
    )
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

    function swapMarketOrder(address user, address tokenIn, address tokenOut, uint256 amountIn) public onlyRouter {
        uint256 swapId = IPoolActions(POOL_ADDRESS).getNextSwapId();
        (,, uint256 reserveA_In,,,, uint8 decimals_In) = pool.poolInfo(address(tokenIn));
        (,, uint256 reserveA_Out,,,, uint8 decimals_Out) = pool.poolInfo(address(tokenOut));
        uint256 currentExecPrice = PoolLogicLib.getExecutionPrice(reserveA_In, reserveA_Out, decimals_In, decimals_Out);

        Swap memory currentSwap = Swap({
            swapID: IPoolActions(POOL_ADDRESS).getNextSwapId(),
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
            typeOfOrder: 2
        });

        bytes32 pairId = bytes32(abi.encodePacked(tokenIn, tokenOut)); // for one direction
        uint256 executionPriceKey = PoolLogicLib.getExecutionPriceLower(currentExecPrice, PRICE_PRECISION); //KEY
        uint256 streamCount = getStreamCount(tokenIn, tokenOut, currentSwap.swapAmountRemaining);
        uint256 swapPerStream = currentSwap.swapAmountRemaining / streamCount;
        if (currentSwap.swapAmountRemaining % streamCount != 0) {
            currentSwap.dustTokenAmount += (currentSwap.swapAmountRemaining - (streamCount * swapPerStream));
            currentSwap.swapAmountRemaining = streamCount * swapPerStream;
        }
        currentSwap.streamsCount = streamCount;
        currentSwap.streamsRemaining = streamCount;
        currentSwap.swapPerStream = swapPerStream;

        // currentSwap = updateSwapStreamInfo(currentSwap);

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
    )
        external
        onlyRouter
    {
        Swap memory currentSwap = Swap({
            swapID: IPoolActions(POOL_ADDRESS).getNextSwapId(), // will be filled in if/else
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
            typeOfOrder: 1
        });

        bytes32 pairId = bytes32(abi.encodePacked(tokenIn, tokenOut)); // for one direction

        if (triggerExecutionPrice > pool.highestPriceMarker(pairId)) {
            IPoolActions(POOL_ADDRESS).setHighestPriceMarker(pairId, triggerExecutionPrice);
        }

        // uint256 streamCount = getStreamCount(tokenIn, tokenOut, currentSwap.swapAmountRemaining);
        // uint256 swapPerStream = currentSwap.swapAmountRemaining / streamCount;
        // if (currentSwap.swapAmountRemaining % streamCount != 0) {
        //     currentSwap.dustTokenAmount += (currentSwap.swapAmountRemaining - (streamCount * swapPerStream));
        //     currentSwap.swapAmountRemaining = streamCount * swapPerStream;
        // }
        // currentSwap.streamsCount = streamCount;
        // currentSwap.streamsRemaining = streamCount;
        // currentSwap.swapPerStream = swapPerStream;

        currentSwap = updateSwapStreamInfo(currentSwap);
        uint256 executionPriceKey = PoolLogicLib.getExecutionPriceLower(triggerExecutionPrice, PRICE_PRECISION); //KEY

        _insertInOrderBook(pairId, currentSwap, executionPriceKey, false);
    }

    function swapLimitOrder(
        address user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 limitOrderPrice
    )
        external
        onlyRouter
    {
        // 1. we need to check if the limitOrderPrice key is higher than the MAX_LIMIT ticks limit of the current price
        // key
        (,, uint256 reserveA_In,,,, uint8 decimals_In) = pool.poolInfo(tokenIn);
        (,, uint256 reserveA_Out,,,, uint8 decimals_Out) = pool.poolInfo(tokenOut);

        // get the current PriceKey
        uint256 currentExecPrice = PoolLogicLib.getExecutionPrice(reserveA_In, reserveA_Out, decimals_In, decimals_Out);

        // check if the limitOrderPriceKey is higher than the current price key by MAX_LIMIT * times the PRICE_PRECISION
        if (limitOrderPrice > currentExecPrice + MAX_LIMIT_TICKS * PRICE_PRECISION) {
            // if yes, then we need to process the limit order as a market order
            swapMarketOrder(user, tokenIn, tokenOut, amountIn);
            return;
        }

        Swap memory currentSwap = Swap({
            swapID: IPoolActions(POOL_ADDRESS).getNextSwapId(),
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

        bytes32 pairId = bytes32(abi.encodePacked(tokenIn, tokenOut)); // for one direction

        uint256 limitOrderPriceKey = PoolLogicLib.getExecutionPriceLower(limitOrderPrice, PRICE_PRECISION);

        /// @notice if price of order less than current, then just insert it in order book and return
        if (limitOrderPrice < currentExecPrice) {
            currentSwap = updateSwapStreamInfo(currentSwap);

            _insertInOrderBook(pairId, currentSwap, limitOrderPriceKey, true);
            return;
        }

        /// @notice update the highest price marker if the limit order price is higher than the current highest price
        /// marker
        if (limitOrderPrice > pool.highestPriceMarker(pairId)) {
            IPoolActions(POOL_ADDRESS).setHighestPriceMarker(pairId, limitOrderPrice);
        }

        // 1. process swap with opposite swaps
        uint256 executionPriceReciprocal =
            PoolLogicLib.getReciprocalOppositePrice(limitOrderPrice, reserveA_In, decimals_In, decimals_Out);
        uint256 executionPriceKeyOpp = PoolLogicLib.getExecutionPriceLower(executionPriceReciprocal, PRICE_PRECISION);

        currentSwap = _settleCurrentLimitOrderAgainstOpposite(
            currentSwap, executionPriceKeyOpp, limitOrderPrice, executionPriceReciprocal
        );

        if (currentSwap.completed) {
            IPoolActions(POOL_ADDRESS).transferTokens(tokenOut, user, currentSwap.amountOut);
            // 2. calculate streams count and swap per stream, then process the swap with the pool
        } else {
            /*
            * pool processing, swap should be consumed against pool, reserves will be updated in this case
                    * swap should be broken down into streams
            * if stream's are completed, do something with dust token??? and transferOut the amountOut
                    * if streams are not completed, then just enqueue the swap, and update the reserves.
                */

            // uint256 streamCount = getStreamCount(tokenIn, tokenOut, currentSwap.swapAmountRemaining);
            // uint256 swapPerStream = currentSwap.swapAmountRemaining / streamCount;
            // if (currentSwap.swapAmountRemaining % streamCount != 0) {
            //     currentSwap.dustTokenAmount += (currentSwap.swapAmountRemaining - (streamCount * swapPerStream));
            //     currentSwap.swapAmountRemaining = streamCount * swapPerStream;
            // }
            // currentSwap.streamsCount = streamCount;
            // currentSwap.streamsRemaining = streamCount;
            // currentSwap.swapPerStream = swapPerStream;

            currentSwap = updateSwapStreamInfo(currentSwap);

            // don't we need to insert in order book here if the limitOrderPrice is lower from the current price

            currentSwap = _settleCurrentSwapAgainstPool(currentSwap, limitOrderPrice); // amountOut is updated
            if (currentSwap.completed) {
                IPoolActions(POOL_ADDRESS).transferTokens(currentSwap.tokenOut, currentSwap.user, currentSwap.amountOut);
            } else {
                _insertInOrderBook(pairId, currentSwap, limitOrderPriceKey, true);
            }
        }
    }

    function processLimitOrders(address tokenIn, address tokenOut) external onlyRouter {
        bytes32 currentPairId = bytes32(abi.encodePacked(tokenIn, tokenOut));
        uint256 startingExecutionPrice = pool.highestPriceMarker(currentPairId);
        uint256 priceKey = PoolLogicLib.getExecutionPriceLower(startingExecutionPrice, PRICE_PRECISION);

        (,, uint256 reserveA_In,,,, uint8 decimals_In) = pool.poolInfo(address(tokenIn));
        (,, uint256 reserveA_Out,,,, uint8 decimals_Out) = pool.poolInfo(address(tokenOut));
        uint256 poolReservesPriceKey = PoolLogicLib.getExecutionPriceLower(
            PoolLogicLib.getExecutionPrice(reserveA_In, reserveA_Out, decimals_In, decimals_Out), PRICE_PRECISION
        ); // @noticewhy
            // this?

        while (priceKey > poolReservesPriceKey) {
            _executeStream(currentPairId, priceKey); // Appelle la fonction pour ce priceKey.
            (,, reserveA_In,,,, decimals_In) = pool.poolInfo(address(tokenIn));
            (,, reserveA_Out,,,, decimals_Out) = pool.poolInfo(address(tokenOut));
            poolReservesPriceKey = PoolLogicLib.getExecutionPriceLower(
                PoolLogicLib.getExecutionPrice(reserveA_In, reserveA_Out, decimals_In, decimals_Out), PRICE_PRECISION
            );
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

            (,, uint256 reserveA_In,,,, uint8 decimals_In) = pool.poolInfo(address(currentSwap.tokenIn));
            (,,,,,, uint8 decimals_Out) = pool.poolInfo(address(currentSwap.tokenIn));
            uint256 executionPriceReciprocal =
                PoolLogicLib.getReciprocalOppositePrice(swapExecutionPrice, reserveA_In, decimals_In, decimals_Out);
            uint256 oppPriceKey = PoolLogicLib.getExecutionPriceLower(executionPriceReciprocal, PRICE_PRECISION);

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
                    currentSwap.swapAmountRemaining = streamCount * swapPerStream; // reAssigning newTokenOutAmountIn
                        // without dust tokens
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
    )
        internal
        returns (Swap memory)
    {
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
        (,, uint256 reserveA_In,,,, uint8 decimals_In) = pool.poolInfo(address(tokenIn));
        (,, uint256 reserveA_Out,,,, uint8 decimals_Out) = pool.poolInfo(address(tokenOut));

        uint256 reserveAInFromPrice =
            PoolLogicLib.getOtherReserveFromPrice(executionPriceOppositeSwap, reserveA_Out, decimals_Out, decimals_In);
        uint256 reserveAOutFromPrice =
            PoolLogicLib.getOtherReserveFromPrice(executionPriceCurrentSwap, reserveA_In, decimals_In, decimals_Out);

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
            uint256 tokenOutAmountOut = PoolLogicLib.getAmountOut(tokenInAmountIn, reserveA_In, reserveAOutFromPrice);

            // we need to calculate the amount of tokenIn for the given tokenOutAmountIn -> tokenB -> tokenA
            uint256 tokenInAmountOut = PoolLogicLib.getAmountOut(tokenOutAmountIn, reserveA_Out, reserveAInFromPrice);

            // we need to check if the amount of tokenIn that we need to send to the user is less than the amount of
            // tokenIn that is remaining to be processed
            if (tokenInAmountIn > tokenInAmountOut) {
                // 1. we keep in memory the swapUser, tokenOut address and the amountOutSwap in memory to transfer the
                // tokens

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

                // 2. we recalculate the oppositeSwap conditions and update it (if tokenInAmountIn == tokenInAmountOut
                // we complete the oppositeSwap)

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
                    // uint256 newTokenOutAmountIn = tokenOutAmountIn - tokenOutAmountOut;

                    oppositeSwap.swapAmountRemaining = tokenOutAmountIn - tokenOutAmountOut;
                    oppositeSwap.amountOut += tokenInAmountIn;

                    // uint256 streamCount = getStreamCount(tokenOut, tokenIn, newTokenOutAmountIn);
                    // uint256 swapPerStream = newTokenOutAmountIn / streamCount;
                    // uint256 dustTokenAmount;
                    // if (newTokenOutAmountIn % streamCount != 0) {
                    //     dustTokenAmount += (newTokenOutAmountIn - (streamCount * swapPerStream));
                    //     newTokenOutAmountIn = streamCount * swapPerStream; // reAssigning newTokenOutAmountIn without
                    // dust tokens
                    // }

                    oppositeSwap = updateSwapStreamInfo(oppositeSwap);

                    // updating oppositeSwap
                    bytes memory updatedSwapData_opposite = abi.encode(
                        oppositePairId,
                        oppositeSwap.amountOut,
                        oppositeSwap.swapAmountRemaining,
                        oppositeSwap.completed,
                        oppositeSwap.streamsCount,
                        oppositeSwap.streamsCount,
                        oppositeSwap.swapPerStream,
                        oppositeSwap.dustTokenAmount,
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
    )
        internal
        returns (Swap memory)
    {
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
                priceKey = priceKey - PoolLogic.PRICE_PRECISION; // will call pool handling function
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
        (,, uint256 reserveA_In,,,, uint8 decimals_In) = pool.poolInfo(address(tokenIn));
        (,, uint256 reserveA_Out,,,, uint8 decimals_Out) = pool.poolInfo(address(tokenOut));

        uint256 reserveAInFromPrice =
            PoolLogicLib.getOtherReserveFromPrice(executionPriceOppositeSwap, reserveA_Out, decimals_Out, decimals_In);
        uint256 reserveAOutFromPrice =
            PoolLogicLib.getOtherReserveFromPrice(executionPriceCurrentSwap, reserveA_In, decimals_In, decimals_Out);

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
            uint256 tokenOutAmountOut = PoolLogicLib.getAmountOut(tokenInAmountIn, reserveA_In, reserveAOutFromPrice);

            // we need to calculate the amount of tokenIn for the given tokenOutAmountIn -> tokenB -> tokenA
            uint256 tokenInAmountOut = PoolLogicLib.getAmountOut(tokenOutAmountIn, reserveA_Out, reserveAInFromPrice);

            // we need to check if the amount of tokenIn that we need to send to the user is less than the amount of
            // tokenIn that is remaining to be processed
            if (tokenInAmountIn > tokenInAmountOut) {
                // 1. we keep in memory the swapUser, tokenOut address and the amountOutSwap in memory to transfer the
                // tokens

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

                // 2. we recalculate the oppositeSwap conditions and update it (if tokenInAmountIn == tokenInAmountOut
                // we complete the oppositeSwap)

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
                        newTokenOutAmountIn = streamCount * swapPerStream; // reAssigning newTokenOutAmountIn without
                            // dust tokens
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

    function _settleCurrentSwapAgainstPool(
        Swap memory currentSwap,
        uint256 executionPriceCurrentSwap
    )
        internal
        returns (Swap memory)
    {
        uint256 swapAmountIn = currentSwap.swapPerStream;
        uint256 amountIn;

        (uint256 reserveD_In,, uint256 reserveA_In,,,,) = pool.poolInfo(address(currentSwap.tokenIn));
        (uint256 reserveD_Out,, uint256 reserveA_Out,,,,) = pool.poolInfo(address(currentSwap.tokenOut));

        // TODO we probably need to separate this limit order logic in a separate function
        if (currentSwap.typeOfOrder == 2) {
            amountIn = swapAmountIn;
        } else {
            (,,,,,, uint8 decimals_In) = pool.poolInfo(address(currentSwap.tokenIn));
            (,,,,,, uint8 decimals_Out) = pool.poolInfo(address(currentSwap.tokenOut));
            uint256 currentExecPrice =
                PoolLogicLib.getExecutionPrice(reserveA_In, reserveA_Out, decimals_In, decimals_Out);

            uint256 expectedAmountOut = PoolLogicLib.calculateAmountOutFromPrice(
                swapAmountIn, executionPriceCurrentSwap, decimals_In, decimals_Out
            );
            // now we get the expected amount in to get the expectedAmountOut at the pool price
            amountIn =
                PoolLogicLib.calculateAmountInFromPrice(expectedAmountOut, currentExecPrice, decimals_In, decimals_Out);

            // uint256 extraToThePool = swapAmountIn - amountIn;
        }

        // the logic here is that we add, if present, the dust token amount to the swapAmountRemaining on the last swap
        // (when streamsRemaining == 1)
        if (currentSwap.streamsRemaining == 1) {
            amountIn += currentSwap.dustTokenAmount;
        }

        (uint256 dToUpdate, uint256 amountOut) =
            PoolLogicLib.getSwapAmountOut(amountIn, reserveA_In, reserveA_Out, reserveD_In, reserveD_Out);

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

    function _insertInOrderBook(
        bytes32 pairId,
        Swap memory _swap,
        uint256 executionPriceKey,
        bool isLimitOrder
    )
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
        (uint256 reserveD_In,,,,,, uint8 decimalsIn) = pool.poolInfo(address(tokenIn));
        (uint256 reserveD_Out,,,,,,) = pool.poolInfo(address(tokenOut));

        uint256 minPoolDepth = reserveD_In <= reserveD_Out ? reserveD_In : reserveD_Out;
        bytes32 poolId = PoolLogicLib.getPoolId(tokenIn, tokenOut); // for pair slippage only. Not an ID for pair
            // direction queue
        return PoolLogicLib.calculateStreamCount(
            amountIn, pool.pairSlippage(poolId), minPoolDepth, liquidityLogic.STREAM_COUNT_PRECISION(), decimalsIn
        );
    }

    function getStreamCountForDPool(address tokenIn, uint256 amountIn) external view override returns (uint256) {
        (uint256 reserveD,,,,,, uint8 decimalsIn) = pool.poolInfo(address(tokenIn));
        return PoolLogicLib.calculateStreamCount(
            amountIn, pool.globalSlippage(), reserveD, liquidityLogic.STREAM_COUNT_PRECISION(), decimalsIn
        );
    }

    // TODO!!!!  Access control is missing
    function updatePoolAddress(address poolAddress) external override {
        require(msg.sender == owner);
        emit PoolAddressUpdated(POOL_ADDRESS, poolAddress);
        POOL_ADDRESS = poolAddress;
        pool = IPoolStates(POOL_ADDRESS);
    }

    // TODO!!!!  Access control is missing
    function updateLiquidityLogicAddress(address liquidityLogicAddress) external override {
        require(msg.sender == owner);
        emit LiquidityLogicAddressUpdated(address(liquidityLogic), liquidityLogicAddress);
        liquidityLogic = ILiquidityLogic(liquidityLogicAddress);
    }

    function poolExist(address tokenAddress) private view returns (bool) {
        (,,,,, bool initialized,) = pool.poolInfo(tokenAddress);
        return initialized;
    }

    // function getCurrentPrice(
    //     address tokenIn,
    //     address tokenOut
    // )
    //     public
    //     view
    //     returns (uint256 currentPrice, uint256 reserveA_In, uint256 reserveA_Out)
    // {
    //     uint8 decimals_In;
    //     uint8 decimals_Out;
    //     (,, reserveA_In,,,, decimals_In) = pool.poolInfo(address(tokenIn));
    //     (,, reserveA_Out,,,, decimals_Out) = pool.poolInfo(address(tokenOut));
    //     currentPrice = getExecutionPrice(reserveA_In, reserveA_Out, decimals_In, decimals_Out);
    // }

    function updateSwapStreamInfo(Swap memory _swap) private view returns (Swap memory) {
        uint256 streamCount = getStreamCount(_swap.tokenIn, _swap.tokenOut, _swap.swapAmountRemaining);
        uint256 swapPerStream = _swap.swapAmountRemaining / streamCount;
        if (_swap.swapAmountRemaining % streamCount != 0) {
            _swap.dustTokenAmount += (_swap.swapAmountRemaining - (streamCount * swapPerStream));
            _swap.swapAmountRemaining = streamCount * swapPerStream;
        }
        _swap.streamsCount = streamCount;
        _swap.streamsRemaining = streamCount;
        _swap.swapPerStream = swapPerStream;

        return _swap;
    }

    function updateOwner(address ownerAddress) external override {
        require(msg.sender == owner);
        emit OwnerUpdated(owner, ownerAddress);
        owner = ownerAddress;
    }

    function STREAM_COUNT_PRECISION() external view override returns (uint256) {
        return liquidityLogic.STREAM_COUNT_PRECISION();
    }
}
