// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolStates} from "./interfaces/pool/IPoolStates.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IPoolActions} from "./interfaces/pool/IPoolActions.sol";
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
    
    constructor(address ownerAddress,address poolAddress) Ownable(ownerAddress){

        POOL_ADDRESS = poolAddress;
        pool = IPoolStates(POOL_ADDRESS);
        emit PoolAddressUpdated(address(0), POOL_ADDRESS);

    }

    function createPool(address token, address user, uint256  amount, uint256 minLaunchReserveA, uint256 minLaunchReserveD,uint256 initialDToMint) external onlyRouter {
        // hardcoding `poolFeeCollected` to zero as pool is just being created
        // reserveA == amount for 1st deposit
        bytes memory createPoolParams = abi.encode(token,user,amount,minLaunchReserveA,minLaunchReserveD,initialDToMint,calculateLpUnitsToMint(amount,0,0),calculateDUnitsToMint(amount,amount,0, initialDToMint),0); 
        IPoolActions(POOL_ADDRESS).createPool(createPoolParams);
    }

    function addLiquidity(address token, address user, uint256  amount) external onlyRouter {
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
        uint newLpUnits = calculateLpUnitsToMint(amount,reserveA,poolOwnershipUnitsTotal);
        reserveA += amount;
        uint newDUnits = calculateDUnitsToMint(amount,reserveA,reserveD, initialDToMint);
        bytes memory addLiqParams = abi.encode(token,user,amount,newLpUnits,newDUnits,0); // poolFeeCollected = 0 until logic is finalized
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
        uint256 assetToTransfer = calculateAssetTransfer(lpUnits,reserveA,poolOwnershipUnitsTotal);
        uint256 dAmountToDeduct = calculateDToDeduct(lpUnits,reserveD,poolOwnershipUnitsTotal);
        bytes memory removeLiqParams = abi.encode(token,user,lpUnits,assetToTransfer,dAmountToDeduct,0); // poolFeeCollected = 0 until logic is finalized
        IPoolActions(POOL_ADDRESS).removeLiquidity(removeLiqParams);
    }

    function swap(address user, address tokenIn, address tokenOut, uint256 amountIn, uint256 executionPrice) external {
        if (amountIn == 0) revert InvalidTokenAmount();
        if (executionPrice == 0) revert InvalidExecutionPrice();
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

        if (!initialized_In || !initialized_Out) {
            revert InvalidPool();
        }

        uint256 streamCount;
        uint256 swapPerStream;
        uint256 minPoolDepth;

        bytes32 poolId;
        bytes32 pairId;

        // TODO: Need to handle same vault deposit withdraw streams
        // break into streams
        minPoolDepth = reserveD_In <= reserveD_Out
            ? reserveD_In
            : reserveD_Out;
        poolId = getPoolId(tokenIn, address(0xD)); // for pair slippage only. Not an ID for pair direction queue
        streamCount = calculateStreamCount(amountIn, pool.pairSlippage(poolId), minPoolDepth);
        swapPerStream = amountIn / streamCount;
        
        // initiate swapqueue per direction
        pairId = keccak256(abi.encodePacked(tokenIn, tokenOut)); // for one direction

        uint256 currentPrice = getExecutionPrice(reserveA_In,reserveA_Out);
    
        Swap memory swapDetails = Swap({
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
        });
        // if execution price 0 (stream queue) , otherwise another queue
        // add into queue
        if (executionPrice <= currentPrice) {
            (,, uint back) = pool.pairStreamQueue(pairId);
            swapDetails.swapID = back;
            IPoolActions(POOL_ADDRESS).enqueueSwap_pairStreamQueue(pairId, swapDetails);
        }
        else {
            (,, uint back) = pool.pairPendingQueue(pairId);
            swapDetails.swapID = back;
            IPoolActions(POOL_ADDRESS).enqueueSwap_pairPendingQueue(pairId, swapDetails);
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

       uint256 result =((amount * 10000) / (((10000 - poolSlippage) * reserveD)));
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
    ) external pure override returns (uint256, uint256) {
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
