// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolStates} from "./interfaces/pool/IPoolStates.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IPoolActions} from "./interfaces/pool/IPoolActions.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Swap} from "./lib/SwapQueue.sol";

contract PoolLogic is Ownable, IPoolLogic {
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

    function createPool(
        address token,
        address user,
        uint256 amount,
        uint256 minLaunchReserveA,
        uint256 minLaunchReserveD,
        uint256 initialDToMint
    ) external onlyRouter {
        // hardcoding `poolFeeCollected` to zero as pool is just being created
        // reserveA == amount for 1st deposit
        bytes memory createPoolParams = abi.encode(
            token,
            user,
            amount,
            minLaunchReserveA,
            minLaunchReserveD,
            initialDToMint,
            calculateLpUnitsToMint(amount, 0, 0),
            calculateDUnitsToMint(amount, amount, 0, initialDToMint),
            0
        );
        IPoolActions(POOL_ADDRESS).createPool(createPoolParams);
    }

    function addLiquidity(address token, address user, uint256 amount) external onlyRouter {
        (uint256 reserveD, uint256 poolOwnershipUnitsTotal, uint256 reserveA,,, uint256 initialDToMint,,) =
            pool.poolInfo(address(token));
        uint256 newLpUnits = calculateLpUnitsToMint(amount, reserveA, poolOwnershipUnitsTotal);
        reserveA += amount;
        uint256 newDUnits = calculateDUnitsToMint(amount, reserveA, reserveD, initialDToMint);
        bytes memory addLiqParams = abi.encode(token, user, amount, newLpUnits, newDUnits, 0); // poolFeeCollected = 0 until logic is finalized
        IPoolActions(POOL_ADDRESS).addLiquidity(addLiqParams);
    }

    function removeLiquidity(address token, address user, uint256 lpUnits) external onlyRouter {
        (uint256 reserveD, uint256 poolOwnershipUnitsTotal, uint256 reserveA,,,,,) = pool.poolInfo(address(token));
        uint256 assetToTransfer = calculateAssetTransfer(lpUnits, reserveA, poolOwnershipUnitsTotal);
        uint256 dAmountToDeduct = calculateDToDeduct(lpUnits, reserveD, poolOwnershipUnitsTotal);
        bytes memory removeLiqParams = abi.encode(token, user, lpUnits, assetToTransfer, dAmountToDeduct, 0); // poolFeeCollected = 0 until logic is finalized
        IPoolActions(POOL_ADDRESS).removeLiquidity(removeLiqParams);
    }

    function swap(address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 executionPrice)
        external
        onlyRouter
    {
        (uint256 reserveD_In,, uint256 reserveA_In, uint256 minLaunchReserveA_In,,,,) = pool.poolInfo(address(tokenIn));

        (uint256 reserveD_Out,, uint256 reserveA_Out,, uint256 minLaunchReserveD_Out,,,) =
            pool.poolInfo(address(tokenOut));

        //check if the reserves are greater than min launch
        if (minLaunchReserveA_In > reserveA_In || minLaunchReserveD_Out > reserveD_Out) {
            revert MinLaunchReservesNotReached();
        }

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
        bytes32 pairId = keccak256(abi.encodePacked(tokenIn, tokenOut));
        // loading the front swap from the stream queue
        (Swap[] memory swaps, uint256 front, uint256 back) = pool.pairStreamQueue(pairId);
        // TODO Don't we need to return if the queue is empty?
        if (front == back) {
            return;
        }

        Swap memory frontSwap = swaps[front]; // Here we are grabbing the first swap from the queue

        (uint256 reserveD_In,, uint256 reserveA_In,,,,,) = pool.poolInfo(address(tokenIn));

        (uint256 reserveD_Out,, uint256 reserveA_Out,,,,,) = pool.poolInfo(address(tokenOut));

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
                0,
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

            (,, uint256 reserveA_In_New,,,,,) = pool.poolInfo(address(frontPendingSwap.tokenIn));

            (,, uint256 reserveA_Out_New,,,,,) = pool.poolInfo(address(frontPendingSwap.tokenOut));

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

        (uint256 reserveD_In,, uint256 reserveA_In,,,,,) = pool.poolInfo(address(tokenIn));
        (uint256 reserveD_Out,, uint256 reserveA_Out,,,,,) = pool.poolInfo(address(tokenOut));

        // the number of opposite swaps
        uint256 oppositeSwapsCount = oppositeBack - oppositeFront;
        Payout[] memory oppositePayouts = new Payout[](oppositeSwapsCount);

        // now we need to loop through the opposite swaps and to process them
        for (uint256 i = oppositeFront; i < oppositeBack; i++) {
            Swap memory oppositeSwap = oppositeSwaps[i];

            // tokenOutAmountIn is the amount of tokenOut that is remaining to be processed from the opposite swap
            uint256 tokenOutAmountIn = oppositeSwap.swapAmountRemaining;

            // we need to calculate the amount of tokenOut for the given tokenInAmountIn
            uint256 tokenOutAmountOut = (tokenInAmountIn * reserveA_In) / reserveA_Out;

            // we need to calculate the amount of tokenIn for the given tokenOutAmountIn
            uint256 tokenInAmountOut = (tokenOutAmountIn * reserveA_Out) / reserveA_In;

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

                // 3. we recalculate the main swap conditions
                uint256 newTokenInAmountIn = tokenInAmountIn - tokenInAmountOut;

                uint256 minPoolDepth = reserveD_In <= reserveD_Out ? reserveD_In : reserveD_Out;
                bytes32 poolId = getPoolId(tokenIn, tokenOut); // for pair slippage only. Not an ID for pair direction queue
                uint256 streamCount = calculateStreamCount(newTokenInAmountIn, pool.pairSlippage(poolId), minPoolDepth);
                uint256 swapPerStream = newTokenInAmountIn / streamCount;

                // updating memory frontSwap
                frontSwap.streamsCount = streamCount;
                frontSwap.streamsRemaining = streamCount;
                frontSwap.swapPerStream = swapPerStream;
                frontSwap.swapAmountRemaining = newTokenInAmountIn;
                frontSwap.amountOut += tokenOutAmountIn;

                // 4. we continue to the next oppositeSwap
                tokenInAmountIn -= tokenInAmountOut; // always positive from the condition above
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

                    uint256 minPoolDepth = reserveD_In <= reserveD_Out ? reserveD_In : reserveD_Out;
                    bytes32 poolId = getPoolId(tokenOut, tokenIn); // for pair slippage only. Not an ID for pair direction queue
                    uint256 streamCount =
                        calculateStreamCount(newTokenOutAmountIn, pool.pairSlippage(poolId), minPoolDepth);
                    uint256 swapPerStream = newTokenOutAmountIn / streamCount;

                    // updating memory oppositeSwap
                    oppositeSwap.streamsCount = streamCount;
                    oppositeSwap.swapPerStream = swapPerStream;
                    oppositeSwap.swapAmountRemaining = newTokenOutAmountIn;
                    oppositeSwap.amountOut += tokenInAmountOut;

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

        // 5. we transfer the tokens to the users
        // if (frontPayout.amount > 0) {
        //     IPoolActions(POOL_ADDRESS).transferTokens(frontPayout.token, frontPayout.swapUser, frontPayout.amount);
        // }

        for (uint256 i = 0; i < oppositePayouts.length; i++) {
            if (oppositePayouts[i].amount > 0) {
                IPoolActions(POOL_ADDRESS).transferTokens(
                    oppositePayouts[i].token, oppositePayouts[i].swapUser, oppositePayouts[i].amount
                );
            }
        }

        return frontSwap;
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

    function getPoolId(address tokenA, address tokenB) public pure returns (bytes32) {
        (address A, address B) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(A, B));
    }

    function calculateLpUnitsToMint(uint256 amount, uint256 reserveA, uint256 totalLpUnits)
        public
        pure
        returns (uint256)
    {
        if (reserveA == 0) {
            return amount;
        }

        return totalLpUnits * amount / (amount + reserveA);
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
        (,,,,,,, bool initialized) = pool.poolInfo(tokenAddress);
        return initialized;
    }
}
