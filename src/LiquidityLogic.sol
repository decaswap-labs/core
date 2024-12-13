// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IPoolStates} from "./interfaces/pool/IPoolStates.sol";
import {IPoolActions} from "./interfaces/pool/IPoolActions.sol";
import {
    Swap,
    LiquidityStream,
    StreamDetails,
    RemoveLiquidityStream,
    GlobalPoolStream
} from "src/lib/SwapQueue.sol";
import {DSMath} from "src/lib/DSMath.sol";
import {PoolLogicLib} from "src/lib/PoolLogicLib.sol";
import {ILiquidityLogic} from "src/interfaces/ILiquidityLogic.sol";

contract LiquidityLogic is ILiquidityLogic{

    using DSMath for uint256;

    address public  POOL_ADDRESS;
    address public  POOL_LOGIC_ADDRESS;
    address public  owner;
    IPoolStates public poolStates;
    IPoolActions public poolActions;

    modifier onlyPoolLogic() {
        if (msg.sender != POOL_LOGIC_ADDRESS) revert NotPoolLogic(msg.sender);
        _;
    }

    constructor(address ownerAddress, address poolAddress, address poolLogicAddress){
        POOL_ADDRESS = poolAddress;
        POOL_LOGIC_ADDRESS = poolLogicAddress;
        poolStates = IPoolStates(POOL_ADDRESS);
        poolActions = IPoolActions(POOL_ADDRESS);
        owner = ownerAddress;
    }

    function initGenesisPool(address token, address user, uint256 tokenAmount, uint256 initialDToMint) external {
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

    function initPool(address token, address liquidityToken, address user, uint256 tokenAmount, uint256 liquidityTokenAmount) external {
        bytes32 pairId = keccak256(abi.encodePacked(token, liquidityToken));
        // create liquidity stream for liquidityToken which is used to swap D  
        StreamDetails memory poolBStream = _createLiquidityStream(liquidityToken, liquidityTokenAmount);
        // streamCount of `token` == streamCount of `liquidityToken`, because reservesD of `token` are 0 at this point
        uint256 swapPerStream = tokenAmount / poolBStream.streamCount;
        uint256 dustTokenAmount;
        if(tokenAmount % poolBStream.streamCount != 0){
            dustTokenAmount = tokenAmount - (poolBStream.streamCount * swapPerStream);
        }
        StreamDetails memory poolAStream = StreamDetails({
            token: token,
            amount: tokenAmount,
            streamCount: poolBStream.streamCount,
            streamsRemaining: poolBStream.streamsRemaining,
            swapPerStream: swapPerStream,
            swapAmountRemaining: tokenAmount,
            dustTokenAmount: dustTokenAmount
        });

        LiquidityStream memory currentLiquidityStream = LiquidityStream({
            user: user,
            poolAStream: poolAStream,
            poolBStream: poolBStream,
            dAmountOut: 0
        });
        
        _settleCurrentLiquidity(currentLiquidityStream);
        
        if(currentLiquidityStream.poolAStream.streamsRemaining != 0 || currentLiquidityStream.poolBStream.streamsRemaining != 0){
            poolActions.enqueueLiquidityStream(
                pairId,
                currentLiquidityStream
            );
        }
    } 



    function addLiqDualToken(address token, address liquidityToken, address user, uint256 tokenAmount, uint256 liquidityTokenAmount) external {
        bytes32 pairId = keccak256(abi.encodePacked(token, liquidityToken));
        StreamDetails memory poolAStream = _createLiquidityStream(token, tokenAmount);
        StreamDetails memory poolBStream = _createLiquidityStream(liquidityToken, liquidityTokenAmount);
        
        LiquidityStream memory currentLiquidityStream = LiquidityStream({
            user: user,
            poolAStream: poolAStream,
            poolBStream: poolBStream,
            dAmountOut: 0
        });
        _settleCurrentLiquidity(currentLiquidityStream);
        if(currentLiquidityStream.poolAStream.streamsRemaining != 0 || currentLiquidityStream.poolBStream.streamsRemaining != 0){
            poolActions.enqueueLiquidityStream(
                pairId,
                currentLiquidityStream
            );
        }
    }

    function addOnlyDLiquidity(address token, address liquidityToken, address user, uint256 liquidityTokenAmount) external {    
        bytes32 pairId = keccak256(abi.encodePacked(token, liquidityToken));
        // poolAStream will be empty as tokens are added to poolB and D is streamed from B -> A
        StreamDetails memory poolBStream = _createLiquidityStream(liquidityToken, liquidityTokenAmount);
        StreamDetails memory poolAStream;
        LiquidityStream memory currentLiquidityStream = LiquidityStream({
            user: user,
            poolAStream: poolAStream,
            poolBStream: poolBStream,
            dAmountOut: 0
        });
        _settleCurrentLiquidity(currentLiquidityStream);
        if(currentLiquidityStream.poolBStream.streamsRemaining != 0){
            poolActions.enqueueLiquidityStream(
                pairId,
                currentLiquidityStream
            );
        }
    }

    // TODO: Update the enqueueLiquidityStream to use the new struct
    function addOnlyTokenLiquidity(address token, address user, uint256 amount) external {                
        // encoding address with itself so pairId is same here and in _streamLiquidity()
        bytes32 pairId = keccak256(abi.encodePacked(token, token));
        StreamDetails memory poolAStream = _createLiquidityStream(token, amount);
        StreamDetails memory poolBStream;
        LiquidityStream memory currentLiquidityStream = LiquidityStream({
            user: user,
            poolAStream: poolAStream,
            poolBStream: poolBStream,
            dAmountOut: 0
        });
        _settleCurrentLiquidity(currentLiquidityStream);
        if(currentLiquidityStream.poolAStream.streamsRemaining != 0){
            poolActions.enqueueLiquidityStream(
                pairId,
                currentLiquidityStream
            );
        }
    }

    function removeLiquidity(address token,  address user, uint256 lpUnits) external {
        (uint256 reserveD,,,,,) = poolStates.poolInfo(address(token));
        uint256 streamCount = PoolLogicLib.calculateStreamCount(lpUnits, poolStates.globalSlippage(), reserveD);
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
        poolActions.enqueueRemoveLiquidityStream(token, removeLiqStream);
        _streamRemoveLiquidity(token);
    }

    function depositToGlobalPool(address token, address user, uint256 amount, uint256 streamCount, uint256 swapPerStream) external {
        bytes32 pairId = bytes32(abi.encodePacked(token, token));

        GlobalPoolStream memory localStream = GlobalPoolStream({
            user: user,
            tokenIn: token,
            tokenAmount: amount,
            streamCount: streamCount,
            streamsRemaining: streamCount,
            swapPerStream: swapPerStream,
            swapAmountRemaining: amount,
            amountOut: 0,
            deposit: true
        });

        _handleDPoolObject(localStream);
    }

    function withdrawFromGlobalPool(address token, address user, uint256 amount) external {
        bytes32 pairId = bytes32(abi.encodePacked(token, token));

        (uint256 reserveD,,,,,) = poolStates.poolInfo(address(token));
        uint256 streamCount = PoolLogicLib.calculateStreamCount(amount, poolStates.globalSlippage(), reserveD);
        uint256 swapPerStream = amount / streamCount;

        GlobalPoolStream memory localStream = GlobalPoolStream({
            user: user,
            tokenIn: token,
            tokenAmount: amount,
            streamCount: streamCount,
            streamsRemaining: streamCount,
            swapPerStream: swapPerStream,
            swapAmountRemaining: amount,
            amountOut: 0,
            deposit: false
        });

        _handleDPoolObject(localStream);
    }

    function processAddLiquidity(address poolA, address poolB) external onlyRouter {
        _streamAddLiquidity(poolA, poolB);
    }

    function processRemoveLiquidity(address token) external onlyRouter {
        _streamRemoveLiquidity(token);
    }

    function processDepositToGlobalPool(address token) external onlyRouter {
        _streamDPoolDeposit(token);
    }

    function processWithdrawFromGlobalPool(address token) external onlyRouter {
        _streamDPoolWithdraw(token);
    }

    function _handleDPoolObject(
        GlobalPoolStream memory stream
    ) internal {
        bytes32 pairId = bytes32(abi.encodePacked(stream.tokenIn, stream.tokenIn));
        GlobalPoolStream memory updatedStream = _streamDPoolOnlyOneObject(stream);
        if (updatedStream.streamsRemaining != 0) {
            updatedStream.swapAmountRemaining = stream.swapAmountRemaining - updatedStream.swapPerStream;
            if (stream.deposit) {
                IPoolActions(POOL_ADDRESS).enqueueGlobalPoolDepositStream(pairId, updatedStream);
            } else {
                // @audit for d, as the damount will be very low as compared to the reserve, stream will likely happen
                IPoolActions(POOL_ADDRESS).enqueueGlobalPoolWithdrawStream(pairId, updatedStream);
            }
        } else {
            if (!updatedStream.deposit) {
                IPoolActions(POOL_ADDRESS).transferTokens(updatedStream.tokenIn, updatedStream.user, updatedStream.amountOut);
            }
        }
    }

    function _settleCurrentLiquidity(LiquidityStream memory liquidityStream) internal returns (LiquidityStream memory) {
        (uint256 reserveD_A, uint256 poolOwnershipUnitsTotal_A, uint256 reserveA_A,,,) = poolStates.poolInfo(liquidityStream.poolAStream.token);
        (uint256 poolANewStreamsRemaining, uint256 poolAReservesToAdd, uint256 lpUnitsAToMint) =
            _streamToken(liquidityStream);
        (uint256 poolBNewStreamsRemaining, uint256 poolBReservesToAdd, uint256 changeInD) =
            _streamD(liquidityStream);

        uint256 lpUnitsFromStreamD;
        if (changeInD > 0) {
            // calc lpUnits user will receive adding D to poolA
            lpUnitsFromStreamD = PoolLogicLib.calculateLpUnitsToMint(
                poolOwnershipUnitsTotal_A + lpUnitsAToMint,
                0,
                poolAReservesToAdd + reserveA_A,
                changeInD,
                reserveD_A
            );
        }
        // update reserves
        bytes memory updatedReserves = abi.encode(poolA, poolB, poolAReservesToAdd, poolBReservesToAdd, changeInD);
        poolActions.updateReservesWhenStreamingLiq(updatedReserves);

        // updating lpUnits
        bytes memory updatedLpUnitsInfo =
            abi.encode(poolA, liquidityStream.user, lpUnitsAToMint + lpUnitsFromStreamD);
        poolActions.updateUserLpUnits(updatedLpUnitsInfo);

        return liquidityStream;

    }   

    function _streamDPoolOnlyOneObject(GlobalPoolStream memory stream) internal returns (GlobalPoolStream memory) {
        uint256 poolNewStreamRemaining;
        uint256 poolReservesToAdd;
        uint256 changeInD;
        uint256 amountOut;
        if (stream.deposit) {
            (poolNewStreamRemaining, poolReservesToAdd, changeInD) = _streamDPoolCalculation(stream);
            stream.amountOut += changeInD;

            // // update reserves
            bytes memory updatedReserves = abi.encode(stream.tokenIn, poolReservesToAdd, changeInD, true);
            IPoolActions(POOL_ADDRESS).updateReservesGlobalStream(updatedReserves);

            bytes memory updatedGlobalPoolBalnace = abi.encode(changeInD, true);
            IPoolActions(POOL_ADDRESS).updateGlobalPoolBalance(updatedGlobalPoolBalnace);

            bytes memory updatedGlobalPoolUserBalanace = abi.encode(stream.user, stream.tokenIn, changeInD, true);
            IPoolActions(POOL_ADDRESS).updateGlobalPoolUserBalance(updatedGlobalPoolUserBalanace);
        } else {
            (poolNewStreamRemaining, poolReservesToAdd, amountOut) = _streamDPoolCalculation(stream);
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

    function _createLiquidityStream(address token, uint256 amount)
        internal
        view
        returns (StreamDetails memory streamDetails)
    {
        (uint256 reserveD,,,,,) = poolStates.poolInfo(token);
        uint256 streamCount = PoolLogicLib.calculateStreamCount(amount, poolStates.globalSlippage(), reserveD);
        uint256 swapPerStream = amount / streamCount;
        uint256 dustTokenAmount;
        if(amount % streamCount != 0){  
            dustTokenAmount = amount - (streamCount * swapPerStream);
        }
        streamDetails = StreamDetails({
            token: token,
            amount: amount,
            streamCount: streamCount,
            streamsRemaining: streamCount,
            swapPerStream: swapPerStream,
            swapAmountRemaining: amount,
            dustTokenAmount: dustTokenAmount
        });
    }

    function _streamAddLiquidity(address poolA, address poolB) internal {
        bytes32 pairId = keccak256(abi.encodePacked(poolA, poolB));
        (LiquidityStream[] memory liquidityStreams, uint256 front, uint256 back) = poolStates.liquidityStreamQueue(pairId);
        // true = there are streams pending
        if (back - front != 0) {
            (uint256 reserveD_A, uint256 poolOwnershipUnitsTotal_A, uint256 reserveA_A,,,) = poolStates.poolInfo(poolA);

            // get the front stream
            LiquidityStream memory liquidityStream = liquidityStreams[front];

            (uint256 poolANewStreamsRemaining, uint256 poolAReservesToAdd, uint256 lpUnitsAToMint) =
                _streamToken(liquidityStream);
            (uint256 poolBNewStreamsRemaining, uint256 poolBReservesToAdd, uint256 changeInD) =
                _streamD(liquidityStream);

            uint256 lpUnitsFromStreamD;
            if (changeInD > 0) {
                // calc lpUnits user will receive adding D to poolA
                lpUnitsFromStreamD = PoolLogicLib.calculateLpUnitsToMint(
                    poolOwnershipUnitsTotal_A + lpUnitsAToMint,
                    0,
                    poolAReservesToAdd + reserveA_A,
                    changeInD,
                    reserveD_A
                );
            }
            // update reserves
            bytes memory updatedReserves = abi.encode(poolA, poolB, poolAReservesToAdd, poolBReservesToAdd, changeInD);
            poolActions.updateReservesWhenStreamingLiq(updatedReserves);

            // updating lpUnits
            bytes memory updatedLpUnitsInfo =
                abi.encode(poolA, liquidityStream.user, lpUnitsAToMint + lpUnitsFromStreamD);
            poolActions.updateUserLpUnits(updatedLpUnitsInfo);

            // update stream struct
            bytes memory updatedStreamData = abi.encode(
                pairId,
                poolAReservesToAdd,
                poolBReservesToAdd,
                poolANewStreamsRemaining,
                poolBNewStreamsRemaining,
                changeInD
            );
            poolActions.updateStreamQueueLiqStream(updatedStreamData);

            if (poolANewStreamsRemaining == 0 && poolBNewStreamsRemaining == 0) {
                poolActions.dequeueLiquidityStream_streamQueue(pairId);
            }
        }
    }

    function _streamD(LiquidityStream memory liqStream)
        internal
        view
        returns (uint256 poolBNewStreamsRemaining, uint256 poolBReservesToAdd, uint256 changeInD)
    {
        // both poolStreamA and poolStreamB tokens should be same in case of single sided liquidity
        (uint256 reserveD_B,, uint256 reserveA_B,,,) = poolStates.poolInfo(liqStream.poolBStream.token);
        poolBNewStreamsRemaining = liqStream.poolBStream.streamsRemaining;
        if (liqStream.poolBStream.swapAmountRemaining != 0) {
            poolBNewStreamsRemaining--;
            poolBReservesToAdd = liqStream.poolBStream.swapPerStream;
            (changeInD,) = PoolLogicLib.getSwapAmountOut(liqStream.poolBStream.swapPerStream, reserveA_B, 0, reserveD_B, 0);
        }
    }

    function _streamToken(LiquidityStream memory liqStream)
        internal
        view
        returns (uint256 poolANewStreamsRemaining, uint256 poolAReservesToAdd, uint256 lpUnitsAToMint)
    {
        // both poolStreamA and poolStreamB tokens should be same in case of single sided liquidity
        (uint256 reserveD_A, uint256 poolOwnershipUnitsTotal_A, uint256 reserveA_A,,,) =
            poolStates.poolInfo(liqStream.poolAStream.token);
        poolANewStreamsRemaining = liqStream.poolAStream.streamsRemaining;

        if (liqStream.poolAStream.swapAmountRemaining != 0) {
            poolANewStreamsRemaining--;
            poolAReservesToAdd = liqStream.poolAStream.swapPerStream;
            lpUnitsAToMint = PoolLogicLib.calculateLpUnitsToMint(
                poolOwnershipUnitsTotal_A, poolAReservesToAdd, poolAReservesToAdd + reserveA_A, 0, reserveD_A
            );
        }
    }

    function _streamDPoolCalculation(GlobalPoolStream memory stream) internal view returns (uint256 poolNewStreamsRemaining, uint256 poolReservesToAdd, uint256 amountOut) {
        // both poolStreamA and poolStreamB tokens should be same in case of single sided liquidity
        (uint256 reserveD,, uint256 reserveA,,,) = poolStates.poolInfo(stream.tokenIn);
        poolNewStreamsRemaining = stream.streamsRemaining;
        poolNewStreamsRemaining--;
        poolReservesToAdd = stream.swapPerStream;
        if (stream.deposit) {
            (amountOut,) = PoolLogicLib.getSwapAmountOut(stream.swapPerStream, reserveA, 0, reserveD, 0);
        } else {
            amountOut = PoolLogicLib.getSwapAmountOutFromD(stream.swapPerStream, reserveA, reserveD);
        }
    }

    function _streamRemoveLiquidity(address token) internal {
        (RemoveLiquidityStream[] memory removeLiqStreams, uint256 front, uint256 back) =
            poolStates.removeLiquidityStreamQueue(token);
        if (front == back) {
            return;
        }

        (, uint256 poolOwnershipUnitsTotal, uint256 reserveA,,,) = poolStates.poolInfo(address(token));

        RemoveLiquidityStream memory frontStream = removeLiqStreams[front];

        uint256 assetToTransfer =
            PoolLogicLib.calculateAssetTransfer(frontStream.conversionPerStream, reserveA, poolOwnershipUnitsTotal);
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

    function _streamDPoolDeposit(address poolA) internal {
        address[] memory poolAddresses = IPoolActions(POOL_ADDRESS).getPoolAddresses();
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            address token = poolAddresses[i];
            bytes32 pairId = bytes32(abi.encodePacked(token, token));
            GlobalPoolStream[] memory globalPoolStream = IPoolActions(POOL_ADDRESS).globalStreamQueueDeposit(pairId);
            if (globalPoolStream.length > 0) {
                uint256 streamRemoved;
                uint256 count;

                for (uint256 i = 0; i < globalPoolStream.length;) {
                    GlobalPoolStream memory stream = _streamDPoolOnlyOneObject(globalPoolStream[i]);
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

    function _streamDPoolWithdraw(address poolA) internal {
        address[] memory poolAddresses = IPoolActions(POOL_ADDRESS).getPoolAddresses();
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            address token = poolAddresses[i];
            bytes32 pairId = bytes32(abi.encodePacked(token, token));
            GlobalPoolStream[] memory globalPoolStream = IPoolActions(POOL_ADDRESS).globalStreamQueueWithdraw(pairId);

            if (globalPoolStream.length > 0) {
                uint256 streamRemoved;
                uint256 count;

                for (uint256 i = 0; i < globalPoolStream.length;) {
                    GlobalPoolStream memory stream = _streamDPoolOnlyOneObject(globalPoolStream[i]);

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

}   
