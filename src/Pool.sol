// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPool} from "./interfaces/IPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolLogicActions} from "./interfaces/pool-logic/IPoolLogicActions.sol";
import {IERC20} from "./interfaces/utils/IERC20.sol";
import {Queue} from "./lib/SwapQueue.sol";
import {Swap} from "./lib/SwapQueue.sol";
import {PoolSwapData} from "./lib/SwapQueue.sol";

contract Pool is IPool, Ownable{
    using Queue for Queue.QueueStruct;

    address public override VAULT_ADDRESS = address(0);
    address public override ROUTER_ADDRESS = address(0);
    address public override POOL_LOGIC = address(0);
    uint256 public override globalSlippage = 0;


    IPoolLogicActions poolLogic;

    struct PoolInfo {
        uint256 reserveD;
        uint256 poolOwnershipUnitsTotal;
        uint256 reserveA;
        uint256 minLaunchReserveA;
        uint256 poolFeeCollected;
        address tokenAddress;    
    }

    mapping(address => PoolInfo) public override poolInfo;
    mapping(address => mapping(address=>uint256)) public override userLpUnitInfo;
    mapping(bytes32 => uint256) public override pairSlippage;
    // mapping(bytes32 => PoolSwapData) public override pairSwapHistory;
    mapping(bytes32 => Queue.QueueStruct) public pairStreamQueue;
    mapping(bytes32 => Queue.QueueStruct) public pairPendingQueue;

    modifier onlyRouter(){
        if(msg.sender != ROUTER_ADDRESS) revert NotRouter(msg.sender);
        _;
    }

    constructor(address vaultAddress, address routerAddress, address poolLogicAddress) Ownable(msg.sender){
        VAULT_ADDRESS = vaultAddress;
        ROUTER_ADDRESS = routerAddress;
        POOL_LOGIC = poolLogicAddress;
        poolLogic = IPoolLogicActions(POOL_LOGIC);

        emit VaultAddressUpdated(address(0), VAULT_ADDRESS);
        emit RouterAddressUpdated(address(0), ROUTER_ADDRESS);
        emit PoolLogicAddressUpdated(address(0), POOL_LOGIC);
    }


    function createPool(address token, uint256 minLaunchReserveA, uint256 tokenAmount) external override onlyOwner {
        _createPool(token,minLaunchReserveA);
        _addLiquidity(msg.sender, token, tokenAmount);
    }

    function disablePool(address token) external override onlyOwner{
        // TODO
    }

    function add(address user, address token, uint256 amount) external override onlyRouter {
        _addLiquidity(user,token,amount);
    }

    function remove(address user, address token, uint256 lpUnits) external override onlyRouter {
        _removeLiquidity(user,token,lpUnits);
    }
     
    // neeed to add in interface
    function executeSwap(address user, uint256 amountIn, uint256 executionPrice, address tokenIn, address tokenOut) external override onlyRouter{
        uint256 streamCount;
        uint256 swapPerStream;
        uint256 minPoolDepth;

        bytes32 poolId;
        bytes32 pairId;

        // TODO: Need to handle same vault deposit withdraw streams
        // if(tokenOut == address(0)) {
        //     streamCount = poolLogic.calculateStreamCount(amountIn, globalSlippage , poolInfo[tokenIn].reserveD);
        // }
        
        // break into streams
        minPoolDepth = poolInfo[tokenIn].reserveD <= poolInfo[tokenOut].reserveD? poolInfo[tokenIn].reserveD : poolInfo[tokenOut].reserveD;
        poolId = getPoolId(tokenIn, tokenOut); // for pair slippage only. Not an ID for pair direction queue
        streamCount = poolLogic.calculateStreamCount(amountIn, pairSlippage[poolId] , minPoolDepth);
        swapPerStream = amountIn / streamCount;

        // initiate swapqueue per direction
        pairId = keccak256(abi.encodePacked(tokenIn, tokenOut)); // for one direction

        // update history
        // pairSwapHistory[pairId] = PoolSwapData({
        //     poolSwapIdLatest: pairSwapHistory[pairId].poolSwapIdLatest + 1,
        //     totalSwapsPool: pairSwapHistory[pairId].totalSwapsPool + 1
        // });


        // if execution price 0 (stream queue) , otherwise another queue
        // add into queue
        if(executionPrice == 0){

            pairStreamQueue[pairId].enqueue(Swap({
                swapID: pairStreamQueue[pairId].front,
                swapAmount: amountIn,
                executionPrice: executionPrice,
                swapAmountRemainign: amountIn,
                streamsCount: streamCount,
                streamsRemaining: streamCount,
                swapPerStream: swapPerStream,
                tokenIn: tokenIn,
                tokenOut : tokenOut,
                completed: false,
                amountOut: 0,
                user: user
            }));

            emit StreamAdded(pairStreamQueue[pairId].front,amountIn, executionPrice, amountIn, streamCount, pairId);

        }else{ // adding to pending queue
            pairPendingQueue[pairId].enqueue(Swap({                
                swapID: pairPendingQueue[pairId].front,
                swapAmount: amountIn,
                executionPrice: executionPrice,
                swapAmountRemainign: amountIn,
                streamsCount: streamCount,
                swapPerStream: swapPerStream,
                streamsRemaining: streamCount,
                tokenIn: tokenIn,
                tokenOut : tokenOut,
                completed: false,
                amountOut: 0,
                user: user
            }));

            emit PendingStreamAdded(pairPendingQueue[pairId].front,amountIn, executionPrice, amountIn, streamCount, pairId);
        }
        // execute pending streams
        _executeStream(pairId, tokenIn, tokenOut);
    }

    function updateRouterAddress(address routerAddress) external override onlyOwner {
        emit RouterAddressUpdated(ROUTER_ADDRESS,routerAddress);
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

    function updateGlobalSlippage(uint256 newGlobalSlippage) external override onlyOwner{
        emit GlobalSlippageUpdated(globalSlippage, newGlobalSlippage);
        globalSlippage = newGlobalSlippage;
    }

    function getPoolId(address tokenA, address tokenB) public pure returns(bytes32){
        (address A, address B) = tokenA < tokenB ? (tokenA,tokenB):(tokenB,tokenA);
        return keccak256(abi.encodePacked(A,B));
    }

    function _createPool(address token, uint256 minLaunchReserveA) internal {
        if (token == address(0)){
            revert InvalidToken();
        }
        
        poolInfo[token].tokenAddress = token;
        poolInfo[token].minLaunchReserveA = minLaunchReserveA;

        emit PoolCreated(token,minLaunchReserveA);
    }

    function _addLiquidity(address user, address token, uint256 amount) internal {
                // lp units
        uint256 newLpUnits = poolLogic.calculateLpUnitsToMint(amount, poolInfo[token].reserveA, poolInfo[token].poolOwnershipUnitsTotal);
        poolInfo[token].reserveA += amount;
        poolInfo[token].poolOwnershipUnitsTotal+= newLpUnits;

        // d units
        uint256 newDUnits = poolLogic.calculateDUnitsToMint(amount, poolInfo[token].reserveA, poolInfo[token].reserveD);
        poolInfo[token].reserveD += newDUnits;

        //mint D
        userLpUnitInfo[user][token] += newDUnits;

        emit LiquidityAdded(user, token, amount, newLpUnits, newDUnits);
    }

    function _removeLiquidity(address user, address token, uint256 lpUnits) internal {

        // deduct lp from user
        userLpUnitInfo[user][token] -= lpUnits;
        // calculate asset to transfer
        uint256 assetToTransfer = poolLogic.calculateAssetTransfer(lpUnits, poolInfo[token].reserveA, poolInfo[token].poolOwnershipUnitsTotal);
        // minus d amount from reserve
        uint256 dAmountToDeduct = poolLogic.calculateDToDeduct(lpUnits, poolInfo[token].reserveD, poolInfo[token].poolOwnershipUnitsTotal);
        
        poolInfo[token].reserveD -= dAmountToDeduct;
        poolInfo[token].reserveA -= assetToTransfer;
        poolInfo[token].poolOwnershipUnitsTotal -= lpUnits;

        IERC20(token).transfer(user,assetToTransfer);

        emit LiquidityRemoved(user,token,lpUnits,assetToTransfer,dAmountToDeduct);

    }

    function _executeStream(bytes32 pairId, address tokenIn, address tokenOut) internal {
        // load swap from queue
        Queue.QueueStruct storage pairStream = pairStreamQueue[pairId];
        for (uint8 i= uint8(pairStream.front); i<= uint8(Queue.length(pairStream)); i++){
            Swap storage tempSwap = pairStream.data[i];
            
            // if not equal then execute stream, otherwise look for opposite direction swap
            if(tempSwap.streamsRemaining != tempSwap.streamsCount) {

                (uint256 dToUpdate,uint256 amountOut) = poolLogic.getSwapAmountOut(tempSwap.swapPerStream, poolInfo[tokenIn].reserveA, 
                poolInfo[tokenOut].reserveA, poolInfo[tokenIn].reserveD, poolInfo[tokenOut].reserveD);
                // update pools
                poolInfo[tokenIn].reserveD -= dToUpdate;
                poolInfo[tokenIn].reserveA += tempSwap.swapPerStream;

                poolInfo[tokenOut].reserveD += dToUpdate;
                poolInfo[tokenOut].reserveD -= amountOut;
                // update swaps 

                //TODO: Deduct fees from amount out = 5BPS.
                tempSwap.swapAmountRemainign -= tempSwap.swapPerStream;
                tempSwap.amountOut += amountOut;
                tempSwap.streamsCount--;
            }else if(tempSwap.streamsRemaining == tempSwap.streamsCount){
                //TODO: find opposing direction swap and execute full
            }else{
                //TODO: find pending swap and execute it, if price is reached.
            }
        }
    }

}
