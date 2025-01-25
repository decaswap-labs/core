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

import { console } from "forge-std/console.sol";

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
            uint256 executionPriceKey = PoolLogicLib.getExecutionPriceKey(currentExecPrice, PRICE_PRECISION);

            // Get market orders (isLimitOrder = false)
            Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, false);

            // Process each swap in the order book
            for (uint256 i = 0; i < swaps.length;) {
                Swap memory currentSwap = swaps[i];

                // @todo: handle trigger orders

                if (currentSwap.typeOfOrder == 2) {
                    currentSwap = _executeStreamAgainstPool(currentSwap);
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
                    IPoolActions(POOL_ADDRESS).updateSwap(updatedSwapData, executionPriceKey, i, false);

                    // If swap is completed, dequeue it and transfer tokens
                    if (currentSwap.streamsRemaining == 0) {
                        IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(pairId, executionPriceKey, i, false);
                        IPoolActions(POOL_ADDRESS).transferTokens(
                            currentSwap.tokenOut, currentSwap.user, currentSwap.amountOut
                        );
                    }
                } else if (currentSwap.typeOfOrder == 1 && currentSwap.executionPrice == currentExecPrice) {
                    currentSwap = _executeStreamAgainstPool(currentSwap);
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
                    IPoolActions(POOL_ADDRESS).updateSwap(updatedSwapData, executionPriceKey, i, false);

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

    function swapMarketOrder(address user, address tokenIn, address tokenOut, uint256 amountIn) public onlyRouter {
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
        uint256 executionPriceKey = PoolLogicLib.getExecutionPriceKey(currentExecPrice, PRICE_PRECISION); //KEY

        currentSwap = _updateSwapStreamInfo(currentSwap);

        currentSwap = _executeStreamAgainstPool(currentSwap); // amountOut is updated
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

        uint256 triggerExecutionPriceKey = PoolLogicLib.getExecutionPriceKey(triggerExecutionPrice, PRICE_PRECISION);

        if (triggerExecutionPriceKey > pool.highestPriceKey(pairId)) {
            IPoolActions(POOL_ADDRESS).setHighestPriceKey(pairId, triggerExecutionPriceKey);
        }

        currentSwap = _updateSwapStreamInfo(currentSwap);

        _insertInOrderBook(pairId, currentSwap, triggerExecutionPriceKey, false);
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
        (,, uint256 reserveA_In,,,, uint8 decimals_In) = pool.poolInfo(tokenIn);
        (,, uint256 reserveA_Out,,,, uint8 decimals_Out) = pool.poolInfo(tokenOut);

        uint256 currentExecPrice = PoolLogicLib.getExecutionPrice(reserveA_In, reserveA_Out, decimals_In, decimals_Out);

        if (limitOrderPrice > currentExecPrice + (MAX_LIMIT_TICKS * PRICE_PRECISION)) {
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

        bytes32 pairId = bytes32(abi.encodePacked(tokenIn, tokenOut));

        uint256 limitOrderPriceKey = PoolLogicLib.getExecutionPriceKey(limitOrderPrice, PRICE_PRECISION);

        if (limitOrderPriceKey > pool.highestPriceKey(pairId)) {
            IPoolActions(POOL_ADDRESS).setHighestPriceKey(pairId, limitOrderPriceKey);
        }

        if (limitOrderPrice < currentExecPrice) {
            currentSwap = _updateSwapStreamInfo(currentSwap);

            _insertInOrderBook(pairId, currentSwap, limitOrderPriceKey, true);
            return;
        }

        uint256 oppositeExecutionPriceKey =
            PoolLogicLib.getExecutionPriceKey(PoolLogicLib.getOppositePrice(currentExecPrice), PRICE_PRECISION);

        currentSwap = _swappingAgainstOppositeSwaps(currentSwap, oppositeExecutionPriceKey);

        if (currentSwap.completed) {
            IPoolActions(POOL_ADDRESS).transferTokens(tokenOut, user, currentSwap.amountOut);
        } else {
            // calculate streams count and swap per stream, then process the swap with the pool

            currentSwap = _updateSwapStreamInfo(currentSwap);

            currentSwap = _executeStreamAgainstPool(currentSwap); // amountOut is updated
            if (currentSwap.completed) {
                IPoolActions(POOL_ADDRESS).transferTokens(currentSwap.tokenOut, currentSwap.user, currentSwap.amountOut);
            } else {
                _insertInOrderBook(pairId, currentSwap, limitOrderPriceKey, true);
            }
        }
    }

    function processLimitOrders(address tokenIn, address tokenOut) external onlyRouter {
        bytes32 currentPairId = bytes32(abi.encodePacked(tokenIn, tokenOut));
        uint256 priceKey = pool.highestPriceKey(currentPairId);

        (,, uint256 reserveA_In,,,, uint8 decimals_In) = pool.poolInfo(address(tokenIn));
        (,, uint256 reserveA_Out,,,, uint8 decimals_Out) = pool.poolInfo(address(tokenOut));
        uint256 poolReservesPriceKey = PoolLogicLib.getExecutionPriceKey(
            PoolLogicLib.getExecutionPrice(reserveA_In, reserveA_Out, decimals_In, decimals_Out), PRICE_PRECISION
        );

        console.log("priceKey", priceKey);
        console.log("poolReservesPriceKey", poolReservesPriceKey);

        uint16 limitLoop;
        while (priceKey > poolReservesPriceKey) {
            limitLoop++;
            (bool poolSwapExecuted, bool orderBookEmpty) = _executeStreams(currentPairId, priceKey); // Appelle la
                // fonction pour ce priceKey.
            if (poolSwapExecuted) {
                // @audit this code block may be substituted for a leaner dedicated function,
                //      can be used in processing of market orders in single price key
                /**
                 * thinking somewhere along the lines of
                 *             uint256 slipImpactFromSwap ~ x (proportional to TokenOutAmountOut && poolReserveTokenOut)
                 *             return uint256 cumulativeSlipImpact += slipImpact
                 *             // if (cumulativeSlipImpact > PRICE_PRECISION) { handle } //
                 */
                (,, reserveA_In,,,,) = pool.poolInfo(address(tokenIn));
                (,, reserveA_Out,,,,) = pool.poolInfo(address(tokenOut));
                poolReservesPriceKey = PoolLogicLib.getExecutionPriceKey(
                    PoolLogicLib.getExecutionPrice(reserveA_In, reserveA_Out, decimals_In, decimals_Out),
                    PRICE_PRECISION
                );
            }

            if (orderBookEmpty) {
                IPoolActions(POOL_ADDRESS).setHighestPriceKey(currentPairId, priceKey);
            }

            priceKey -= PRICE_PRECISION; // 1 Gwei ou autre précision utilisée.
                // update A->B highest price marker
                // need get reserve price for the next priceKey
            console.log("priceKey", priceKey);
            console.log("poolReservesPriceKey", poolReservesPriceKey);
            console.log("limitLoop", limitLoop);
            if (limitLoop > 50) {
                console.log("LIMIT LOOP REACHED!!!!!", limitLoop);
                return;
            }
        }
    }

    // @note dedicate some limititation on price gap and opp swaps count on single prcieKey for maintenance bot call !!
    // @audit ensure we are decrementing the highestPriceKLey on the completion of swaps in memory at a given key

    function _executeStreams(
        bytes32 pairId,
        uint256 executionPriceKey
    )
        internal
        returns (bool poolSwapExecuted, bool orderBookEmpty)
    {
        Swap[] memory swaps = pool.orderBook(pairId, executionPriceKey, true);
        if (swaps.length == 0) {
            return (poolSwapExecuted, orderBookEmpty = true);
        }
        uint256 swapRemoved;
        for (uint256 i = 0; i < swaps.length;) {
            Swap memory currentSwap = swaps[i];

            uint256 oppositeExecutionPriceKey = PoolLogicLib.getExecutionPriceKey(
                PoolLogicLib.getOppositePrice(currentSwap.executionPrice), PRICE_PRECISION
            );

            uint256 amountInRemaining;
            (currentSwap, amountInRemaining) = _streamingAgainstOppositeSwaps(currentSwap, oppositeExecutionPriceKey);
            console.log("amountInRemaining", amountInRemaining);

            if (amountInRemaining == 0) {
                // if completed
                if (currentSwap.completed) {
                    // if the swap is completed, we keep looping to consume the opposite swaps
                    IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(pairId, executionPriceKey, 0, true);

                    swapRemoved++;
                    uint256 lastIndex = swaps.length - swapRemoved;
                    swaps[i] = swaps[lastIndex];
                    delete swaps[lastIndex];

                    IPoolActions(POOL_ADDRESS).transferTokens(
                        currentSwap.tokenOut, currentSwap.user, currentSwap.amountOut
                    );

                    if (lastIndex == 0) {
                        // TODO we need to decrement the priceKey and find next collection of swaps
                        // it means no more swaps to process for the current priceKey
                        return (poolSwapExecuted, orderBookEmpty = true);
                    }
                } else {
                    currentSwap = _updateSwapStreamInfo(currentSwap);
                    bytes memory updatedSwapData = abi.encode(
                        pairId,
                        currentSwap.swapAmount,
                        currentSwap.swapAmountRemaining,
                        currentSwap.completed,
                        currentSwap.streamsRemaining,
                        currentSwap.streamsCount,
                        currentSwap.swapPerStream,
                        currentSwap.dustTokenAmount,
                        currentSwap.typeOfOrder
                    );

                    IPoolActions(POOL_ADDRESS).updateSwap(updatedSwapData, executionPriceKey, i, true);
                    unchecked {
                        ++i;
                    }
                }

                // we go to the next swap without trying to stream against pool
                console.log("here we continue");
                continue;
            } else {
                // we go against pool with the remaining amount
                // @audit the current swap is only in memory and is not saved storage
                currentSwap = _swappingAgainstPool(currentSwap, amountInRemaining);
                currentSwap.streamsRemaining--;
                poolSwapExecuted = true;
                if (currentSwap.streamsRemaining == 0) {
                    currentSwap.completed = true;
                    swapRemoved++;
                    IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(pairId, executionPriceKey, i, true);

                    uint256 lastIndex = swaps.length - swapRemoved;
                    swaps[i] = swaps[lastIndex];
                    delete swaps[lastIndex];
                    IPoolActions(POOL_ADDRESS).transferTokens(
                        currentSwap.tokenOut, currentSwap.user, currentSwap.amountOut
                    );
                    if (lastIndex == 0) {
                        return (poolSwapExecuted, orderBookEmpty = true);
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
                        currentSwap.dustTokenAmount,
                        currentSwap.typeOfOrder
                    );
                    console.log("currentSwap.swapAmount", currentSwap.swapAmount);
                    console.log("currentSwap.swapAmountRemaining", currentSwap.swapAmountRemaining);
                    console.log("currentSwap.completed", currentSwap.completed);
                    console.log("currentSwap.streamsRemaining", currentSwap.streamsRemaining);
                    console.log("currentSwap.streamsCount", currentSwap.streamsCount);
                    console.log("currentSwap.swapPerStream", currentSwap.swapPerStream);
                    console.log("currentSwap.dustTokenAmount", currentSwap.dustTokenAmount);
                    console.log("currentSwap.typeOfOrder", currentSwap.typeOfOrder);

                    IPoolActions(POOL_ADDRESS).updateSwap(updatedSwapData, executionPriceKey, i, true);
                    unchecked {
                        ++i;
                    }
                }
            }
        }
    }

    function _swappingAgainstOppositeSwaps(
        Swap memory currentSwap,
        uint256 currentOppositePriceKey
    )
        internal
        returns (Swap memory)
    {
        uint256 tokenInAmountIn = currentSwap.swapAmount;
        uint256 amountInRemaining;
        (currentSwap, amountInRemaining) =
            _matchAgainstOppositeSwaps(currentSwap, currentOppositePriceKey, tokenInAmountIn);

        uint256 consumedAmountIn = tokenInAmountIn - amountInRemaining;
        currentSwap.swapAmountRemaining -= consumedAmountIn;

        if (amountInRemaining == 0) {
            currentSwap.completed = true;
        }

        return currentSwap;
    }

    function _streamingAgainstOppositeSwaps(
        Swap memory currentSwap,
        uint256 currentOppositePriceKey
    )
        internal
        returns (Swap memory, uint256 amountInRemaining)
    {
        uint256 tokenInAmountIn = currentSwap.swapPerStream;

        if (currentSwap.streamsRemaining == 1) {
            tokenInAmountIn += currentSwap.dustTokenAmount;
        }

        console.log("tokenInAmountIn", tokenInAmountIn);

        (currentSwap, amountInRemaining) =
            _matchAgainstOppositeSwaps(currentSwap, currentOppositePriceKey, tokenInAmountIn);

        uint256 consumedAmountIn = tokenInAmountIn - amountInRemaining;
        currentSwap.swapAmountRemaining -= consumedAmountIn;

        if (amountInRemaining == 0) {
            currentSwap.streamsRemaining--;
            if (currentSwap.streamsRemaining == 0) {
                currentSwap.dustTokenAmount = 0; // don't know if we need this update
                currentSwap.completed = true; // don't know if we need this update
            }
        }

        return (currentSwap, amountInRemaining);
    }

    // @audit need a way to exit gracefully if the gap btw currentOppositePriceKey and currentOppositePriceKey is too
    // big
    function _matchAgainstOppositeSwaps(
        Swap memory currentSwap,
        uint256 oppositeCurrentPoolPrice,
        uint256 tokenInAmountIn
    )
        private
        returns (Swap memory, uint256 amountInRemaining)
    {
        amountInRemaining = tokenInAmountIn;
        address tokenIn = currentSwap.tokenIn;
        address tokenOut = currentSwap.tokenOut;
        (,,,,,, uint8 decimals_In) = pool.poolInfo(address(tokenIn));
        (,,,,,, uint8 decimals_Out) = pool.poolInfo(address(tokenOut));
        uint256 executionPriceCurrentSwap = currentSwap.executionPrice;

        bytes32 oppositePairId = bytes32(abi.encodePacked(tokenOut, tokenIn));
        uint256 oppositeCachedPriceKey = pool.highestPriceKey(oppositePairId);

        // quick bounding
        uint16 limitLoop;
        // @audit need ot handle out of boundaries for the price_key decrementation while loop
        while (oppositeCachedPriceKey >= oppositeCurrentPoolPrice) {
            limitLoop++;
            if (limitLoop > 4) {
                console.log("LIMIT OPPOSITE SWAPS LOOPS REACHED!!!!!", limitLoop);
                return (currentSwap, amountInRemaining);
            }
            Swap[] memory oppositeSwaps = pool.orderBook(oppositePairId, oppositeCachedPriceKey, true);

            if (oppositeSwaps.length == 0) {
                oppositeCachedPriceKey -= PRICE_PRECISION;
                IPoolActions(POOL_ADDRESS).setHighestPriceKey(oppositePairId, oppositeCachedPriceKey);
                continue;
            }

            uint256 swapRemoved;
            // @audit need ot handle out of boundaries for the oppositeSwaps array
            for (uint256 i = 0; i < oppositeSwaps.length;) {
                Swap memory oppositeSwap = oppositeSwaps[i];

                // tokenOutAmountIn is the amount of tokenOut that is remaining to be processed from the opposite swap
                // it contains opp swap dust token
                uint256 tokenOutAmountIn = oppositeSwap.swapAmountRemaining + oppositeSwap.dustTokenAmount;

                // we need to calculate the amount of tokenOut for the given tokenInAmountIn -> tokenA -> tokenB
                // uint256 tokenOutAmountOut = PoolLogicLib.getAmountOut(tokenInAmountIn, reserveA_In,
                // reserveAOutFromPrice);
                uint256 tokenOutAmountOut = PoolLogicLib.calculateExpectedAmountFromPrice(
                    tokenInAmountIn, executionPriceCurrentSwap, decimals_In, decimals_Out
                );

                // we need to calculate the amount of tokenIn for the given tokenOutAmountIn -> tokenB -> tokenA
                uint256 tokenInAmountOut = PoolLogicLib.calculateExpectedAmountFromPrice(
                    tokenOutAmountIn, oppositeSwap.executionPrice, decimals_Out, decimals_In
                );

                // we need to check if the amount of tokenIn that we need to send to the user is less than the amount of
                // tokenIn that is remaining to be processed
                if (tokenInAmountIn > tokenInAmountOut) {
                    // 1. we keep in memory the swapUser, tokenOut address and the amountOutSwap in memory to transfer
                    // the
                    // tokens

                    IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(
                        oppositePairId, oppositeCachedPriceKey, i, true
                    );

                    uint256 newTokenInAmountIn = tokenInAmountIn - tokenInAmountOut;

                    // currentSwap.swapAmountRemaining = newTokenInAmountIn;
                    currentSwap.amountOut += tokenOutAmountIn;
                    tokenInAmountIn = newTokenInAmountIn;

                    amountInRemaining -= tokenInAmountOut;
                    // 4. we continue to the next oppositeSwap

                    swapRemoved++;
                    // if all opposite swaps for the given price key are consumed we need to update the highestPriceKey
                    if (swapRemoved == oppositeSwaps.length) {
                        oppositeCachedPriceKey -= PRICE_PRECISION;
                        IPoolActions(POOL_ADDRESS).setHighestPriceKey(oppositePairId, oppositeCachedPriceKey);
                        break;
                    }
                    uint256 lastIndex = oppositeSwaps.length - swapRemoved;
                    oppositeSwaps[i] = oppositeSwaps[lastIndex];

                    IPoolActions(POOL_ADDRESS).transferTokens(
                        oppositeSwap.tokenOut, oppositeSwap.user, tokenInAmountOut + oppositeSwap.amountOut
                    );

                    delete oppositeSwaps[lastIndex];
                } else {
                    // 1. frontSwap is completed and is taken out of the stream queue

                    currentSwap.amountOut += tokenOutAmountOut;
                    // currentSwap.swapAmountRemaining -= amountInRemaining;
                    amountInRemaining = 0;

                    // 2. we recalculate the oppositeSwap conditions and update it (if tokenInAmountIn ==
                    // tokenInAmountOut
                    // we complete the oppositeSwap)

                    //both swaps consuming each other
                    if (tokenInAmountIn == tokenInAmountOut) {
                        IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(
                            oppositePairId, oppositeCachedPriceKey, i, true
                        );

                        IPoolActions(POOL_ADDRESS).transferTokens(
                            oppositeSwap.tokenOut, oppositeSwap.user, tokenInAmountOut + oppositeSwap.amountOut
                        );
                    } else {
                        // only front is getting consumed. so we need to update opposite one

                        oppositeSwap.swapAmountRemaining = tokenOutAmountIn - tokenOutAmountOut;
                        oppositeSwap.amountOut += tokenInAmountIn;

                        oppositeSwap = _updateSwapStreamInfo(oppositeSwap);

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
                            oppositeSwap.typeOfOrder
                        );

                        IPoolActions(POOL_ADDRESS).updateSwap(updatedSwapData_opposite, oppositeCachedPriceKey, i, true);
                    }
                    // 3. we terminate the loop as we have completed the frontSwap
                    return (currentSwap, amountInRemaining);
                }
            }
            continue;
        }

        return (currentSwap, amountInRemaining);
    }

    function _executeStreamAgainstPool(Swap memory currentSwap) internal returns (Swap memory) {
        uint256 swapAmountIn = currentSwap.swapPerStream;

        if (currentSwap.streamsRemaining == 1) {
            swapAmountIn += currentSwap.dustTokenAmount;
        }

        // @note at this point only market orders are processed at market price
        uint256 amountOut;
        if (currentSwap.typeOfOrder == 2) {
            (, amountOut) = _computePoolReservesAtMarket(currentSwap.tokenIn, currentSwap.tokenOut, swapAmountIn);
        } else {
            (, amountOut) = _computePoolReservesAtExecutionPrice(
                currentSwap.tokenIn, currentSwap.tokenOut, currentSwap.executionPrice, swapAmountIn
            );
        }

        currentSwap.streamsRemaining--;
        if (currentSwap.streamsRemaining == 0) {
            currentSwap.completed = true;
        } else {
            currentSwap.swapAmountRemaining -= swapAmountIn;
        }
        currentSwap.amountOut += amountOut;

        return currentSwap;
    }

    function _swappingAgainstPool(Swap memory currentSwap, uint256 swapAmount) private returns (Swap memory) {
        uint256 swapAmountIn = swapAmount;

        // @note at this point only market orders are processed at market price
        uint256 amountOut;
        if (currentSwap.typeOfOrder == 2) {
            (, amountOut) = _computePoolReservesAtMarket(currentSwap.tokenIn, currentSwap.tokenOut, swapAmountIn);
        } else {
            (, amountOut) = _computePoolReservesAtExecutionPrice(
                currentSwap.tokenIn, currentSwap.tokenOut, currentSwap.executionPrice, swapAmountIn
            );
        }

        currentSwap.swapAmountRemaining -= swapAmountIn;
        currentSwap.amountOut += amountOut;

        return currentSwap;
    }

    // @audit should we keep this concept ??
    function _computePoolReservesAtExecutionPrice(
        address tokenIn,
        address tokenOut,
        uint256 executionPrice,
        uint256 amountToSwap
    )
        private
        returns (uint256 dToUpdate, uint256 amountOut)
    {
        uint256 swapAmountIn = amountToSwap;

        (uint256 reserveD_In,, uint256 reserveA_In,,,, uint8 decimals_In) = pool.poolInfo(tokenIn);
        (uint256 reserveD_Out,, uint256 reserveA_Out,,,, uint8 decimals_Out) = pool.poolInfo(tokenOut);

        uint256 currentExecPrice = PoolLogicLib.getExecutionPrice(reserveA_In, reserveA_Out, decimals_In, decimals_Out);

        // @note if executionPrice <= currentExecPrice, we need to swap at the pool price
        if (executionPrice <= currentExecPrice) {
            return _computePoolReservesAtMarket(tokenIn, tokenOut, swapAmountIn);
        }

        uint256 expectedAmountOut =
            PoolLogicLib.calculateExpectedAmountFromPrice(swapAmountIn, executionPrice, decimals_In, decimals_Out);
        // now we get the expected amount in to get the expectedAmountOut at the pool price
        uint256 amountIn = PoolLogicLib.calculateExpectedAmountFromPrice(
            expectedAmountOut, PoolLogicLib.getOppositePrice(currentExecPrice), decimals_Out, decimals_In
        );

        (dToUpdate, amountOut) =
            PoolLogicLib.getSwapAmountOut(amountIn, reserveA_In, reserveA_Out, reserveD_In, reserveD_Out);

        bytes memory updateReservesParams =
            abi.encode(true, tokenIn, tokenOut, swapAmountIn, dToUpdate, amountOut, dToUpdate);
        IPoolActions(POOL_ADDRESS).updateReserves(updateReservesParams);
    }

    function _computePoolReservesAtMarket(
        address tokenIn,
        address tokenOut,
        uint256 amountToSwap
    )
        private
        returns (uint256 dToUpdate, uint256 amountOut)
    {
        uint256 swapAmountIn = amountToSwap;

        (uint256 reserveD_In,, uint256 reserveA_In,,,,) = pool.poolInfo(tokenIn);
        (uint256 reserveD_Out,, uint256 reserveA_Out,,,,) = pool.poolInfo(tokenOut);

        (dToUpdate, amountOut) =
            PoolLogicLib.getSwapAmountOut(swapAmountIn, reserveA_In, reserveA_Out, reserveD_In, reserveD_Out);

        bytes memory updateReservesParams =
            abi.encode(true, tokenIn, tokenOut, swapAmountIn, dToUpdate, amountOut, dToUpdate);
        IPoolActions(POOL_ADDRESS).updateReserves(updateReservesParams);
    }

    function _insertInOrderBook(
        bytes32 pairId,
        Swap memory _swap,
        uint256 executionPriceKey,
        bool isLimitOrder
    )
        internal
    {
        IPoolActions(POOL_ADDRESS).addSwapToOrderBook(pairId, _swap, executionPriceKey, isLimitOrder);
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

    function _updateSwapStreamInfo(Swap memory _swap) private view returns (Swap memory) {
        uint256 streamCount = getStreamCount(_swap.tokenIn, _swap.tokenOut, _swap.swapAmountRemaining);
        uint256 swapPerStream = _swap.swapAmountRemaining / streamCount;
        if (_swap.swapAmountRemaining % streamCount != 0) {
            _swap.dustTokenAmount = (_swap.swapAmountRemaining - (streamCount * swapPerStream));
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
