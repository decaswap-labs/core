// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolStates} from "./interfaces/pool/IPoolStates.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IPoolActions} from "./interfaces/pool/IPoolActions.sol";
import {IERC20} from "./interfaces/utils/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {Swap} from "./lib/SwapQueue.sol";

contract PoolLogic is Ownable, IPoolLogic {
    uint256 internal BASE_D_AMOUNT = 1e18;
    uint256 internal DECIMAL = 1e18;

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
        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 minLaunchReserveA,
            uint256 minLaunchReserveD,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        ) = pool.poolInfo(address(token));
        uint256 newLpUnits = calculateLpUnitsToMint(amount, reserveA, poolOwnershipUnitsTotal);
        reserveA += amount;
        uint256 newDUnits = calculateDUnitsToMint(amount, reserveA, reserveD, initialDToMint);
        bytes memory addLiqParams = abi.encode(token, user, amount, newLpUnits, newDUnits, 0); // poolFeeCollected = 0 until logic is finalized
        IPoolActions(POOL_ADDRESS).addLiquidity(addLiqParams);
    }

    function removeLiquidity(address token, address user, uint256 lpUnits) external onlyRouter {
        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 minLaunchReserveA,
            uint256 minLaunchReserveD,
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
            uint256 minLaunchReserveA_In,
            uint256 minLaunchReserveD_In,
            uint256 initialDToMint_In,
            uint256 poolFeeCollected_In,
            bool initialized_In
        ) = pool.poolInfo(address(tokenIn));

        (
            uint256 reserveD_Out,
            uint256 poolOwnershipUnitsTotal_Out,
            uint256 reserveA_Out,
            uint256 minLaunchReserveA_Out,
            uint256 minLaunchReserveD_Out,
            uint256 initialDToMint_Out,
            uint256 poolFeeCollected_Out,
            bool initialized_Out
        ) = pool.poolInfo(address(tokenOut));

        //check if the reserves are greater than min launch
        if (minLaunchReserveA_In > reserveA_In || minLaunchReserveD_Out > reserveD_Out) {
            revert MinLaunchReservesNotReached();
        }

        uint256 streamCount;
        uint256 swapPerStream;
        uint256 minPoolDepth;

        bytes32 poolId;
        bytes32 pairId;

        // break into streams
        minPoolDepth = reserveD_In <= reserveD_Out
            ? reserveD_In
            : reserveD_Out;
        poolId = getPoolId(tokenIn, tokenOut); // for pair slippage only. Not an ID for pair direction queue
        streamCount = calculateStreamCount(amountIn, pool.pairSlippage(poolId), minPoolDepth);
        swapPerStream = amountIn / streamCount;

        // initiate swapqueue per direction
        pairId = keccak256(abi.encodePacked(tokenIn, tokenOut)); // for one direction

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

        _executeStream(pairId, tokenIn, tokenOut);
    }

    function _executeStream(bytes32 pairId, address tokenIn, address tokenOut) internal {
        (
            uint256 reserveD_In,
            uint256 poolOwnershipUnitsTotal_In,
            uint256 reserveA_In,
            uint256 minLaunchReserveA_In,
            uint256 minLaunchReserveD_In,
            uint256 initialDToMint_In,
            uint256 poolFeeCollected_In,
            bool initialized_In
        ) = pool.poolInfo(address(tokenIn));

        (
            uint256 reserveD_Out,
            uint256 poolOwnershipUnitsTotal_Out,
            uint256 reserveA_Out,
            uint256 minLaunchReserveA_Out,
            uint256 minLaunchReserveD_Out,
            uint256 initialDToMint_Out,
            uint256 poolFeeCollected_Out,
            bool initialized_Out
        ) = pool.poolInfo(address(tokenOut));

        address completedSwapToken;
        address swapUser;
        uint256 amountOutSwap;

        // loading the front swap from the stream queue
        (Swap[] memory swaps, uint256 front, uint256 back) = pool.pairStreamQueue(pairId);
        Swap memory frontSwap = swaps[front];

        // ------------------------ CHECK OPP DIR SWAP --------------------------- //

        //TODO: Deduct fees from amount out = 5BPS.
        bytes32 otherPairId = keccak256(abi.encodePacked(tokenOut, tokenIn));
        (Swap[] memory oppositeSwaps, uint256 oppositeFront, uint256 oppositeBack) = pool.pairStreamQueue(otherPairId);

        if (oppositeBack - oppositeFront != 0) {
            Swap memory oppositeSwap = oppositeSwaps[oppositeFront];
            // A->B , dout1 is D1, amountOut1 is B
            (uint256 dOutA, uint256 amountOutA) =
                getSwapAmountOut(frontSwap.swapAmountRemaining, reserveA_In, reserveA_Out, reserveD_In, reserveD_Out);
            // B->A
            (uint256 dOutB, uint256 amountOutB) =
                getSwapAmountOut(oppositeSwap.swapAmountRemaining, reserveA_Out, reserveA_In, reserveD_Out, reserveD_In);

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

            // TKN , TKN
            if (frontSwap.swapAmountRemaining < amountOutB) {
                bytes memory updateReservesParams =
                    abi.encode(true, tokenIn, tokenOut, frontSwap.swapAmountRemaining, dOutA, amountOutA, dOutA);
                IPoolActions(POOL_ADDRESS).updateReserves(updateReservesParams);
                // updating frontSwap
                bytes memory updatedSwapData_front = abi.encode(pairId, amountOutA, 0, true, 0);
                IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_front);
                // updating oppositeSwap
                bytes memory updatedSwapData_opposite = abi.encode(
                    otherPairId,
                    frontSwap.swapAmountRemaining,
                    oppositeSwap.swapAmountRemaining - amountOutA,
                    oppositeSwap.completed,
                    oppositeSwap.streamsRemaining
                );
                IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_opposite);

                completedSwapToken = frontSwap.tokenIn;
                swapUser = frontSwap.user;
                amountOutSwap = frontSwap.amountOut + amountOutA;

                require(back > front, "Queue is empty");
                IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(pairId);
            } else {
                bytes memory updateReservesParams =
                    abi.encode(false, tokenIn, tokenOut, amountOutB, dOutB, oppositeSwap.swapAmountRemaining, dOutB);
                IPoolActions(POOL_ADDRESS).updateReserves(updateReservesParams);
                // updating frontSwap
                bytes memory updatedSwapData_Front = abi.encode(
                    pairId,
                    oppositeSwap.swapAmountRemaining,
                    frontSwap.swapAmountRemaining - amountOutB,
                    frontSwap.completed,
                    frontSwap.streamsRemaining
                );
                IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_Front);
                // updating oppositeSwap
                bytes memory updatedSwapData_opposite = abi.encode(otherPairId, amountOutB, 0, true, 0);
                IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_opposite);

                completedSwapToken = oppositeSwap.tokenIn;
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
                completedSwapToken = frontSwap.tokenIn;
                swapUser = frontSwap.user;
                amountOutSwap = frontSwap.amountOut + amountOut;
            }
            // updating frontSwap
            bytes memory updatedSwapData_Front = abi.encode(
                pairId,
                amountOut,
                frontSwap.swapAmountRemaining - frontSwap.swapPerStream,
                frontSwap.completed,
                frontSwap.streamsRemaining
            );
            IPoolActions(POOL_ADDRESS).updatePairStreamQueueSwap(updatedSwapData_Front);

            if (frontSwap.streamsRemaining == 0) {
                // @todo make a function of this error
                require(back > front, "Queue is empty");
                IPoolActions(POOL_ADDRESS).dequeueSwap_pairStreamQueue(pairId);
            }
        }

        // transferring tokens
        if (completedSwapToken != address(0)) IPoolActions(POOL_ADDRESS).transferTokens(completedSwapToken, swapUser, amountOutSwap);

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
                if (swapDetails.executionPrice >= swaps_pending[back-1].executionPrice) {
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

    function updateBaseDAmount(uint256 newBaseDAmount) external override onlyOwner {
        emit BaseDUpdated(BASE_D_AMOUNT, newBaseDAmount);
        BASE_D_AMOUNT = newBaseDAmount;
    }

    function updatePoolAddress(address poolAddress) external override onlyOwner {
        emit PoolAddressUpdated(POOL_ADDRESS, poolAddress);
        POOL_ADDRESS = poolAddress;
        pool = IPoolStates(POOL_ADDRESS);
    }

    function poolExist(address tokenAddress) private view returns (bool) {
        // TODO : Resolve this tuple unbundling issue
        (uint256 a, uint256 b, uint256 c, uint256 d, uint256 f, uint256 g, uint256 h, bool initialized) =
            pool.poolInfo(tokenAddress);
        return initialized;
    }
}
