// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPool} from "./interfaces/IPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolLogicActions} from "./interfaces/pool-logic/IPoolLogicActions.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Queue} from "./lib/SwapQueue.sol";
import {Swap} from "./lib/SwapQueue.sol";
import {PoolSwapData} from "./lib/SwapQueue.sol";
import {SwapSorter} from "./lib/QuickSort.sol";

contract Pool is IPool, Ownable {
    using SafeERC20 for IERC20;
    using Queue for Queue.QueueStruct;

    address public override VAULT_ADDRESS = address(0);
    address public override ROUTER_ADDRESS = address(0);
    address internal D_TOKEN = address(0xD);
    address public override POOL_LOGIC = address(0);
    uint256 public override globalSlippage = 10;

    IPoolLogicActions poolLogic;

    struct PoolInfo {
        uint256 reserveD;
        uint256 poolOwnershipUnitsTotal;
        uint256 reserveA;
        uint256 minLaunchReserveA;
        uint256 minLaunchReserveD;
        uint256 initialDToMint;
        uint256 poolFeeCollected;
        bool initialized;
    }

    struct VaultDepositInfo {
        uint256 tokenAmount;
        uint256 dAmount;
    }

    // PoolInfo struct
    mapping(address token => uint256 reserveD) private mapToken_reserveD;
    mapping(address token => uint256 poolOwnershipUnitsTotal) private mapToken_poolOwnershipUnitsTotal;
    mapping(address token => uint256 reserveA) private mapToken_reserveA;
    mapping(address token => uint256 minLaunchReserveA) private mapToken_minLaunchReserveA;
    mapping(address token => uint256 minLaunchReserveD) private mapToken_minLaunchReserveD;
    mapping(address token => uint256 initialDToMint) private mapToken_initialDToMint;
    mapping(address token => uint256 poolFeeCollected) private mapToken_poolFeeCollected;
    mapping(address token => bool initialized) private mapToken_initialized;

    mapping(address => mapping(address => uint256)) public override userLpUnitInfo;
    mapping(address => mapping(address => VaultDepositInfo)) public userVaultInfo;
    mapping(bytes32 => uint256) public override pairSlippage;
    // mapping(bytes32 => PoolSwapData) public override pairSwapHistory;
    // mapping(bytes32 => Queue.QueueStruct) public pairStreamQueue;
    // mapping(bytes32 => Queue.QueueStruct) public pairPendingQueue;
    // mapping(bytes32 => Queue.QueueStruct) public poolStreamQueue;

    // poolStreamQueue struct
    mapping(bytes32 pairId => Swap[] data) public mapPairId_poolStreamQueue_Swaps;
    mapping(bytes32 pairId => uint256 front) public mapPairId_poolStreamQueue_front;
    mapping(bytes32 pairId => uint256 back) public mapPairId_poolStreamQueue_back;

    // pairStreamQueue struct
    mapping(bytes32 pairId => Swap[] data) public mapPairId_pairStreamQueue_Swaps;
    mapping(bytes32 pairId => uint256 front) public mapPairId_pairStreamQueue_front;
    mapping(bytes32 pairId => uint256 back) public mapPairId_pairStreamQueue_back;

    // pairPendingQueue struct
    mapping(bytes32 pairId => Swap[] data) public mapPairId_pairPendingQueue_Swaps;
    mapping(bytes32 pairId => uint256 front) public mapPairId_pairPendingQueue_front;
    mapping(bytes32 pairId => uint256 back) public mapPairId_pairPendingQueue_back;

    modifier onlyRouter() {
        if (msg.sender != ROUTER_ADDRESS) revert NotRouter(msg.sender);
        _;
    }

    // @todo use a mapping and allow multiple logic contracts may be e.g lending/vault etc may be?
    modifier onlyPoolLogic() {
        if (msg.sender != POOL_LOGIC) revert NotPoolLogic(msg.sender);
        _;
    }

    constructor(address vaultAddress, address routerAddress, address poolLogicAddress) Ownable(msg.sender) {
        VAULT_ADDRESS = vaultAddress;
        ROUTER_ADDRESS = routerAddress;
        POOL_LOGIC = poolLogicAddress;
        poolLogic = IPoolLogicActions(POOL_LOGIC);

        emit VaultAddressUpdated(address(0), VAULT_ADDRESS);
        emit RouterAddressUpdated(address(0), ROUTER_ADDRESS);
        emit PoolLogicAddressUpdated(address(0), POOL_LOGIC);
    }

    //////////////////////////////////////////////////////////////////////////////
    // NOTE ignore code below for as all will be refactored after storage variable are set
    // commented logic so that code compiles with current tests
    ///////////////////////////////////////////////////////////////////////////////

    // creatPoolParams encoding format => (address token, address user, uint256 amount, uint256 minLaunchReserveA, uint256 minLaunchReserveD, uint256 initialDToMint, uint newLpUnits, uint newDUnits, uint256 poolFeeCollected)
    function createPool(bytes calldata creatPoolParams) external onlyPoolLogic {
        (
            address token,
            address user,
            uint256 amount,
            uint256 minLaunchReserveA,
            uint256 minLaunchReserveD,
            uint256 initialDToMint,
            uint256 newLpUnits,
            uint256 newDUnits,
            uint256 poolFeeCollected
        ) = abi.decode(
            creatPoolParams, (address, address, uint256, uint256, uint256, uint256, uint256, uint256, uint256)
        );
        _createPool(token, minLaunchReserveA, minLaunchReserveD, initialDToMint);
        bytes memory addLiqParam = abi.encode(token, user, amount, newLpUnits, newDUnits, poolFeeCollected);
        _addLiquidity(addLiqParam);
    }

    // addLiqParams encoding format => (address token, address user, uint amount, uint256 newLpUnits, uint256 newDUnits, uint256 poolFeeCollected)
    function _addLiquidity(bytes memory addLiqParams) internal {
        (address token, address user, uint256 amount, uint256 newLpUnits, uint256 newDUnits, uint256 poolFeeCollected) =
            abi.decode(addLiqParams, (address, address, uint256, uint256, uint256, uint256));

        mapToken_reserveA[token] += amount;
        mapToken_poolOwnershipUnitsTotal[token] += newLpUnits;
        mapToken_reserveD[token] += newDUnits;
        // @note may or may not be needed here.
        mapToken_poolFeeCollected[token] += poolFeeCollected;

        userLpUnitInfo[user][token] += newLpUnits;

        emit LiquidityAdded(user, token, amount, newLpUnits, newDUnits);
    }

    // removeLiqParams encoding format => (address token, address user, uint lpUnits, uint256 assetToTransfer, uint256 dAmountToDeduct, uint256 poolFeeCollected)
    function _removeLiquidity(bytes memory removeLiqParams) internal {
        (
            address token,
            address user,
            uint256 lpUnits,
            uint256 assetToTransfer,
            uint256 dAmountToDeduct,
            uint256 poolFeeCollected
        ) = abi.decode(removeLiqParams, (address, address, uint256, uint256, uint256, uint256));
        // deduct lp from user
        userLpUnitInfo[user][token] -= lpUnits;

        // updating pool state
        mapToken_reserveA[token] -= assetToTransfer;
        mapToken_reserveD[token] -= dAmountToDeduct;
        mapToken_poolOwnershipUnitsTotal[token] -= lpUnits;
        // @note may or may not be needed here.
        mapToken_poolFeeCollected[token] += poolFeeCollected;

        // transferring tokens to user
        IERC20(token).safeTransfer(user, assetToTransfer);

        emit LiquidityRemoved(user, token, lpUnits, assetToTransfer, dAmountToDeduct);
    }

    function dequeueSwap_poolStreamQueue(bytes32 pairId) external onlyPoolLogic {
        mapPairId_poolStreamQueue_front[pairId]++;
    }

    function dequeueSwap_pairStreamQueue(bytes32 pairId) external onlyPoolLogic {
        mapPairId_pairStreamQueue_front[pairId]++;
    }

    function dequeueSwap_pairPendingQueue(bytes32 pairId) external onlyPoolLogic {
        mapPairId_pairPendingQueue_front[pairId]++;
    }

    function enqueueSwap_poolStreamQueue(bytes32 pairId, Swap memory swap) external onlyPoolLogic {
        mapPairId_poolStreamQueue_Swaps[pairId].push(swap);
        mapPairId_poolStreamQueue_back[pairId]++;
    }

    function enqueueSwap_pairStreamQueue(bytes32 pairId, Swap memory swap) external onlyPoolLogic {
        mapPairId_pairStreamQueue_Swaps[pairId].push(swap);
        mapPairId_pairStreamQueue_back[pairId]++;
    }

    function enqueueSwap_pairPendingQueue(bytes32 pairId, Swap memory swap) external onlyPoolLogic {
        mapPairId_pairPendingQueue_Swaps[pairId].push(swap);
        mapPairId_pairPendingQueue_back[pairId]++;
    }

    function disablePool(address token) external override onlyOwner {
        // TODO
    }

    // addLiqParams encoding format => (address token, address user, uint amount, uint256 newLpUnits, uint256 newDUnits, uint256 poolFeeCollected)
    function addLiquidity(bytes memory addLiqParams) external onlyPoolLogic {
        _addLiquidity(addLiqParams);
    }

    // removeLiqParams encoding format => (address token, address user, uint lpUnits, uint256 assetToTransfer, uint256 dAmountToDeduct, uint256 poolFeeCollected)
    function removeLiquidity(bytes memory removeLiqParams) external onlyPoolLogic {
        _removeLiquidity(removeLiqParams);
    }

    // updateReservesParams encoding format => (bool aToB, address tokenA, address tokenB, uint256 reserveA_A, uint256 reserveD_A,uint256 reserveA_B, uint256 reserveD_B)
    function updateReserves(bytes memory updatedReservesParams) external onlyPoolLogic {
        (
            bool aToB,
            address tokenA,
            address tokenB,
            uint256 reserveA_A,
            uint256 reserveD_A,
            uint256 reserveA_B,
            uint256 reserveD_B
        ) = abi.decode(updatedReservesParams, (bool, address, address, uint256, uint256, uint256, uint256));
        if (aToB) {
            mapToken_reserveA[tokenA] += reserveA_A;
            mapToken_reserveD[tokenA] -= reserveD_A;

            mapToken_reserveA[tokenB] -= reserveA_B;
            mapToken_reserveD[tokenB] += reserveD_B;
        } else {
            mapToken_reserveA[tokenB] += reserveA_B;
            mapToken_reserveD[tokenB] -= reserveD_B;

            mapToken_reserveA[tokenA] -= reserveA_A;
            mapToken_reserveD[tokenA] += reserveD_A;
        }
    }

    // updatedSwapData encoding format => (bytes32 pairId, uint256 amountOut, uint256 swapAmountRemaining, bool completed, uint256 streamsRemaining, uint256 streamCount, uint256 swapPerStream)
    function updatePairStreamQueueSwap(bytes memory updatedSwapData) external onlyPoolLogic {
        (
            bytes32 pairId,
            uint256 amountOut,
            uint256 swapAmountRemaining,
            bool completed,
            uint256 streamsRemaining,
            uint256 streamCount,
            uint256 swapPerStream
        ) = abi.decode(updatedSwapData, (bytes32, uint256, uint256, bool, uint256, uint256, uint256));
        Swap storage swap = mapPairId_pairStreamQueue_Swaps[pairId][mapPairId_pairStreamQueue_front[pairId]];
        swap.amountOut += amountOut;
        swap.swapAmountRemaining = swapAmountRemaining;
        swap.completed = completed;
        swap.streamsRemaining = streamsRemaining;
        swap.streamsCount = streamCount;
        swap.swapPerStream = swapPerStream;
    }

    // @todo ask if we should sort it here, or pass sorted array from logic and just save
    function sortPairPendingQueue(bytes32 pairId) external onlyPoolLogic {
        // Sort the array w.r.t price
        SwapSorter.quickSort(mapPairId_pairPendingQueue_Swaps[pairId]);
    }

    function transferTokens(address token, address to, uint256 amount) external onlyPoolLogic {
        IERC20(token).safeTransfer(to, amount);
    }

    function depositVault(address user, uint256 amountIn, address tokenIn) external override onlyRouter {
        // if (amountIn == 0) revert InvalidTokenAmount();
        // if (!poolInfo[tokenIn].initialized) revert InvalidPool();

        // uint256 streamCount;
        // uint256 swapPerStream;
        // uint256 minPoolDepth;

        // bytes32 poolId;
        // bytes32 pairId;

        // minPoolDepth = poolInfo[tokenIn].reserveD;

        // streamCount = poolLogic.calculateStreamCount(amountIn, globalSlippage, minPoolDepth);
        // swapPerStream = amountIn / streamCount;

        // pairId = keccak256(abi.encodePacked(tokenIn, D_TOKEN)); // for one direction

        // uint256 currentPrice = poolLogic.getExecutionPrice(poolInfo[tokenIn].reserveA, poolInfo[tokenIn].reserveA);

        // poolStreamQueue[pairId].enqueue(
        //     Swap({
        //         swapID: pairStreamQueue[pairId].back,
        //         swapAmount: amountIn,
        //         executionPrice: currentPrice,
        //         swapAmountRemaining: amountIn,
        //         streamsCount: streamCount,
        //         streamsRemaining: streamCount,
        //         swapPerStream: swapPerStream,
        //         tokenIn: tokenIn,
        //         tokenOut: D_TOKEN,
        //         completed: false,
        //         amountOut: 0,
        //         user: user
        //     })
        // );

        // userVaultInfo[tokenIn][user] = VaultDepositInfo({tokenAmount: amountIn, dAmount: 0});

        // emit StreamAdded(poolStreamQueue[pairId].front, amountIn, currentPrice, streamCount, pairId);

        // _executeDepositVaultStream(pairId, tokenIn);
    }

    function withdrawVault(address user, uint256 amountIn, address tokenOut) external override onlyRouter {
        // if (!poolInfo[tokenOut].initialized) revert InvalidPool();
        // if (userVaultInfo[tokenOut][user].dAmount < amountIn) revert InvalidTokenAmount();

        // uint256 streamCount;
        // uint256 swapPerStream;
        // uint256 minPoolDepth;

        // bytes32 poolId;
        // bytes32 pairId;

        // minPoolDepth = poolInfo[tokenOut].reserveD;

        // streamCount = poolLogic.calculateStreamCount(amountIn, globalSlippage, minPoolDepth);
        // swapPerStream = amountIn / streamCount;

        // pairId = keccak256(abi.encodePacked(D_TOKEN, tokenOut)); // for one direction

        // uint256 currentPrice = poolLogic.getExecutionPrice(poolInfo[tokenOut].reserveA, poolInfo[tokenOut].reserveA);

        // poolStreamQueue[pairId].enqueue(
        //     Swap({
        //         swapID: pairStreamQueue[pairId].back,
        //         swapAmount: amountIn,
        //         executionPrice: currentPrice,
        //         swapAmountRemaining: amountIn,
        //         streamsCount: streamCount,
        //         streamsRemaining: streamCount,
        //         swapPerStream: swapPerStream,
        //         tokenIn: D_TOKEN,
        //         tokenOut: tokenOut,
        //         completed: false,
        //         amountOut: 0,
        //         user: user
        //     })
        // );

        //     emit StreamAdded(poolStreamQueue[pairId].front, amountIn, currentPrice, streamCount, pairId);

        //     _executeWithdrawVaultStream(pairId, tokenOut);
    }

    // neeed to add in interface
    function executeSwap(address user, uint256 amountIn, uint256 executionPrice, address tokenIn, address tokenOut)
        external
        override
        onlyRouter
    {
        // if (amountIn == 0) revert InvalidTokenAmount();
        // if (executionPrice == 0) revert InvalidExecutionPrice();
        // if (!poolInfo[tokenIn].initialized || !poolInfo[tokenOut].initialized) {
        //     revert InvalidPool();
        // }

        // uint256 streamCount;
        // uint256 swapPerStream;
        // uint256 minPoolDepth;

        // bytes32 poolId;
        // bytes32 pairId;

        // // TODO: Need to handle same vault deposit withdraw streams
        // // break into streams
        // minPoolDepth = poolInfo[tokenIn].reserveD <= poolInfo[tokenOut].reserveD
        //     ? poolInfo[tokenIn].reserveD
        //     : poolInfo[tokenOut].reserveD;
        // poolId = getPoolId(tokenIn, address(0xD)); // for pair slippage only. Not an ID for pair direction queue
        // streamCount = poolLogic.calculateStreamCount(amountIn, pairSlippage[poolId], minPoolDepth);
        // swapPerStream = amountIn / streamCount;

        // // initiate swapqueue per direction
        // pairId = keccak256(abi.encodePacked(tokenIn, tokenOut)); // for one direction

        // uint256 currentPrice = poolLogic.getExecutionPrice(poolInfo[tokenIn].reserveA, poolInfo[tokenOut].reserveA);

        // // if execution price 0 (stream queue) , otherwise another queue
        // // add into queue
        // if (executionPrice <= currentPrice) {
        //     pairStreamQueue[pairId].enqueue(
        //         Swap({
        //             swapID: pairStreamQueue[pairId].back,
        //             swapAmount: amountIn,
        //             executionPrice: executionPrice,
        //             swapAmountRemaining: amountIn,
        //             streamsCount: streamCount,
        //             streamsRemaining: streamCount,
        //             swapPerStream: swapPerStream,
        //             tokenIn: tokenIn,
        //             tokenOut: tokenOut,
        //             completed: false,
        //             amountOut: 0,
        //             user: user
        //         })
        //     );

        //     emit StreamAdded(pairStreamQueue[pairId].front, amountIn, executionPrice, streamCount, pairId);
        // } else {
        //     // adding to pending queue
        //     pairPendingQueue[pairId].enqueue(
        //         Swap({
        //             swapID: pairPendingQueue[pairId].back,
        //             swapAmount: amountIn,
        //             executionPrice: executionPrice,
        //             swapAmountRemaining: amountIn,
        //             streamsCount: streamCount,
        //             swapPerStream: swapPerStream,
        //             streamsRemaining: streamCount,
        //             tokenIn: tokenIn,
        //             tokenOut: tokenOut,
        //             completed: false,
        //             amountOut: 0,
        //             user: user
        //         })
        //     );

        //     // Sort the array w.r.t price
        //     SwapSorter.quickSort(pairPendingQueue[pairId].data);

        //     emit PendingStreamAdded(pairPendingQueue[pairId].front, amountIn, executionPrice, streamCount, pairId);
        // }
        // // execute pending streams
        // _executeStream(pairId, tokenIn, tokenOut);
    }

    function cancelSwap(uint256 swapId, bytes32 pairId, bool isStreaming) external {
        // uint256 amountIn;
        // uint256 amountOut;
        // if (isStreaming) {
        //     (pairStreamQueue[pairId], amountIn, amountOut) = _removeSwap(swapId, pairStreamQueue[pairId]);
        // } else {
        //     (pairPendingQueue[pairId], amountIn, amountOut) = _removeSwap(swapId, pairPendingQueue[pairId]);
        // }

        // emit SwapCancelled(swapId, pairId, amountIn, amountOut);
    }

    function updateRouterAddress(address routerAddress) external override onlyOwner {
        emit RouterAddressUpdated(ROUTER_ADDRESS, routerAddress);
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
        // emit MinLaunchReserveUpdated(token, poolInfo[token].minLaunchReserveA, newMinLaunchReserveA);
        // poolInfo[token].minLaunchReserveA = newMinLaunchReserveA;
    }

    function updatePairSlippage(address tokenA, address tokenB, uint256 newSlippage) external override onlyOwner {
        bytes32 poolId = getPoolId(tokenA, tokenB);
        pairSlippage[poolId] = newSlippage;
        emit PairSlippageUpdated(tokenA, tokenB, newSlippage);
    }

    function updateGlobalSlippage(uint256 newGlobalSlippage) external override onlyOwner {
        emit GlobalSlippageUpdated(globalSlippage, newGlobalSlippage);
        globalSlippage = newGlobalSlippage;
    }

    function getPoolId(address tokenA, address tokenB) public pure returns (bytes32) {
        (address A, address B) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(A, B));
    }

    // function getStreamStruct(bytes32 pairId) external view returns (Queue.QueueStruct memory) {
    //     return pairStreamQueue[pairId];
    // }

    // function getPendingStruct(bytes32 pairId) external view returns (Queue.QueueStruct memory) {
    //     return pairPendingQueue[pairId];
    // }

    function _createPool(address token, uint256 minLaunchReserveA, uint256 minLaunchReserveD, uint256 initialDToMint)
        internal
    {
        if (mapToken_initialized[token]) revert DuplicatePool();

        mapToken_initialized[token] = true;
        mapToken_minLaunchReserveA[token] = minLaunchReserveA;
        mapToken_minLaunchReserveD[token] = minLaunchReserveD;
        // @todo need confirmation on that. hardcoded?
        mapToken_initialDToMint[token] = initialDToMint;

        emit PoolCreated(token, minLaunchReserveA, minLaunchReserveD);
    }

    function _addLiquidity(address user, address token, uint256 amount) internal {
        // if (!poolInfo[token].initialized) revert InvalidToken();

        // if (amount == 0) revert InvalidTokenAmount();

        // // lp units
        // uint256 newLpUnits =
        //     poolLogic.calculateLpUnitsToMint(amount, poolInfo[token].reserveA, poolInfo[token].poolOwnershipUnitsTotal);
        // poolInfo[token].reserveA += amount;
        // poolInfo[token].poolOwnershipUnitsTotal += newLpUnits;

        // // d units
        // uint256 newDUnits = poolLogic.calculateDUnitsToMint(
        //     amount, poolInfo[token].reserveA, poolInfo[token].reserveD, poolInfo[token].initialDToMint
        // );
        // poolInfo[token].reserveD += newDUnits;

        // //mint D
        // userLpUnitInfo[user][token] += newDUnits;

        // emit LiquidityAdded(user, token, amount, newLpUnits, newDUnits);
    }

    function _removeLiquidity(address user, address token, uint256 lpUnits) internal {
        // if (!poolInfo[token].initialized) revert InvalidToken();

        // if (lpUnits == 0) revert InvalidTokenAmount();

        // // deduct lp from user
        // userLpUnitInfo[user][token] -= lpUnits;
        // // calculate asset to transfer
        // uint256 assetToTransfer =
        //     poolLogic.calculateAssetTransfer(lpUnits, poolInfo[token].reserveA, poolInfo[token].poolOwnershipUnitsTotal);
        // // minus d amount from reserve
        // uint256 dAmountToDeduct =
        //     poolLogic.calculateDToDeduct(lpUnits, poolInfo[token].reserveD, poolInfo[token].poolOwnershipUnitsTotal);

        // poolInfo[token].reserveD -= dAmountToDeduct;
        // poolInfo[token].reserveA -= assetToTransfer;
        // poolInfo[token].poolOwnershipUnitsTotal -= lpUnits;

        // // IERC20(token).transfer(user,assetToTransfer); // commented for test to run
        // emit LiquidityRemoved(user, token, lpUnits, assetToTransfer, dAmountToDeduct);
    }

    function _executeStream(bytes32 pairId, address tokenA, address tokenB) internal {
        //     //check if the reserves are greater than min launch
        //     if (
        //         poolInfo[tokenA].minLaunchReserveA > poolInfo[tokenA].reserveA
        //             || poolInfo[tokenB].minLaunchReserveD > poolInfo[tokenB].reserveD
        //     ) revert MinLaunchReservesNotReached();

        //     address completedSwapToken;
        //     address swapUser;
        //     uint256 amountOutSwap;
        //     // loading the front swap from the stream queue

        //     Swap storage frontSwap;
        //     Queue.QueueStruct storage pairStream = pairStreamQueue[pairId];
        //     frontSwap = pairStream.data[pairStream.front];

        //     // ------------------------ CHECK OPP DIR SWAP --------------------------- //
        //     //TODO: Deduct fees from amount out = 5BPS.
        //     bytes32 otherPairId = keccak256(abi.encodePacked(tokenB, tokenA));
        //     Queue.QueueStruct storage oppositePairStream = pairStreamQueue[otherPairId];

        //     if (oppositePairStream.data.length != 0) {
        //         Swap storage oppositeSwap = oppositePairStream.data[oppositePairStream.front];
        //         // A->B , dout1 is D1, amountOut1 is B
        //         (uint256 dOutA, uint256 amountOutA) = poolLogic.getSwapAmountOut(
        //             frontSwap.swapAmountRemaining,
        //             poolInfo[tokenA].reserveA,
        //             poolInfo[tokenB].reserveA,
        //             poolInfo[tokenA].reserveD,
        //             poolInfo[tokenB].reserveD
        //         );
        //         // B->A
        //         (uint256 dOutB, uint256 amountOutB) = poolLogic.getSwapAmountOut(
        //             oppositeSwap.swapAmountRemaining,
        //             poolInfo[tokenB].reserveA,
        //             poolInfo[tokenA].reserveA,
        //             poolInfo[tokenB].reserveD,
        //             poolInfo[tokenA].reserveD
        //         );

        //         /*
        //         I have taken out amountOut of both swap directions
        //         Now one swap should consume the other one
        //         How to define that?

        //         I am selling 50 TKN for (10)-> Calculated USDC
        //         Alice is buying 50 USDC for (250)-> Calculated TKN

        //         I should be able to fill alice's order completely. By giving her 50 TKN, and take 10 USDC.

        //         AmountIn1 = AmountIn1 - AmountIn1 // 50-50 (Order fulfilled as I have given all the TKN to alice)
        //         AmountOut1 = AmountOut1 // 10 (As Alice has given me 10 USDC, which equals to amount I have calculated)

        //         AmountIn2 = AmountIn2 - AmountOut2 // 50-10, as alice has given me 10. So she has 40 left
        //         AmountOut2 = AmountOut2 + AmountIn1 // 0+50, Alice wanted 250 tokens, but now she has only those
        //         tokens which I was selling. Which is 50
        //         */

        //         // TKN , TKN
        //         if (frontSwap.swapAmountRemaining < amountOutB) {
        //             // update pool
        //             poolInfo[tokenA].reserveA += frontSwap.swapAmountRemaining;
        //             poolInfo[tokenA].reserveD -= dOutA;

        //             poolInfo[tokenB].reserveA -= amountOutA;
        //             poolInfo[tokenB].reserveD += dOutA;

        //             oppositeSwap.amountOut += frontSwap.swapAmountRemaining;
        //             frontSwap.amountOut += amountOutA;
        //             oppositeSwap.swapAmountRemaining -= amountOutA;
        //             frontSwap.swapAmountRemaining = 0;

        //             frontSwap.completed = true;
        //             frontSwap.streamsRemaining = 0;

        //             // ----------- to set transfer
        //             completedSwapToken = frontSwap.tokenIn;
        //             swapUser = frontSwap.user;
        //             amountOutSwap = frontSwap.amountOut;
        //             // -----------

        //             pairStreamQueue[pairId].data[pairStream.front] = frontSwap;
        //             Queue.dequeue(pairStreamQueue[pairId]);
        //         } else {
        //             // update pool
        //             poolInfo[tokenB].reserveA += oppositeSwap.swapAmountRemaining;
        //             poolInfo[tokenB].reserveD -= dOutB;

        //             poolInfo[tokenA].reserveA -= amountOutB;
        //             poolInfo[tokenA].reserveD += dOutB;

        //             frontSwap.amountOut += oppositeSwap.swapAmountRemaining;
        //             oppositeSwap.amountOut += amountOutB;
        //             frontSwap.swapAmountRemaining -= amountOutB;
        //              oppositeSwap.swapAmountRemaining = 0;

        //             oppositeSwap.completed = true;
        //             oppositeSwap.streamsRemaining = 0;

        //             // ----------- to set transfer
        //             completedSwapToken = oppositeSwap.tokenIn;
        //             swapUser = oppositeSwap.user;
        //             amountOutSwap = oppositeSwap.amountOut; // error for opp dir swap
        //             emit AmountOut(amountOutSwap);
        //             // -----------

        //             pairStreamQueue[otherPairId].data[oppositePairStream.front] = oppositeSwap;
        //             Queue.dequeue(pairStreamQueue[otherPairId]);
        //         }
        //     } else {
        //         (uint256 dToUpdate, uint256 amountOut) = poolLogic.getSwapAmountOut(
        //             frontSwap.swapPerStream,
        //             poolInfo[tokenA].reserveA,
        //             poolInfo[tokenB].reserveA,
        //             poolInfo[tokenA].reserveD,
        //             poolInfo[tokenB].reserveD
        //         );
        //         // update pools
        //         poolInfo[tokenA].reserveD -= dToUpdate;
        //         poolInfo[tokenA].reserveA += frontSwap.swapPerStream;

        //         poolInfo[tokenB].reserveD += dToUpdate;
        //         poolInfo[tokenB].reserveA -= amountOut;
        //         // update swaps

        //         //TODO: Deduct fees from amount out = 5BPS.
        //         frontSwap.swapAmountRemaining -= frontSwap.swapPerStream;
        //         frontSwap.amountOut += amountOut;
        //         frontSwap.streamsRemaining--;

        //         if (frontSwap.streamsRemaining == 0) {
        //             frontSwap.completed = true;
        //             completedSwapToken = frontSwap.tokenIn;
        //             swapUser = frontSwap.user;
        //             amountOutSwap = frontSwap.amountOut;
        //         }

        //         pairStreamQueue[pairId].data[pairStream.front] = frontSwap;

        //         if (pairStreamQueue[pairId].data[pairStream.front].streamsCount == 0) {
        //             Queue.dequeue(pairStreamQueue[pairId]);
        //         }
        //     }
        //   //  if (completedSwapToken != address(0)) IERC20(completedSwapToken).transfer(swapUser, amountOutSwap);

        //     // --------------------------- HANDLE PENDING SWAP INSERTION ----------------------------- //
        //     if (pairPendingQueue[pairId].data.length > 0) {
        //         Swap storage frontPendingSwap;
        //         Queue.QueueStruct storage pairPending = pairPendingQueue[pairId];
        //         frontPendingSwap = pairPending.data[pairPending.front];

        //         uint256 executionPriceInOrder = frontPendingSwap.executionPrice;
        //         uint256 executionPriceLatest = poolLogic.getExecutionPrice(
        //             poolInfo[frontPendingSwap.tokenIn].reserveA, poolInfo[frontPendingSwap.tokenOut].reserveA
        //         );

        //         if (executionPriceLatest >= executionPriceInOrder) {
        //             pairStreamQueue[pairId].enqueue(frontPendingSwap);
        //             pairPendingQueue[pairId].dequeue();
        //         }
        //     }
    }

    function _executeDepositVaultStream(bytes32 pairId, address tokenA) internal {
        //     // loading the front swap from the stream queue
        //     Swap storage frontSwap;
        //     Queue.QueueStruct storage poolStream = poolStreamQueue[pairId];
        //     frontSwap = poolStream.data[poolStream.front];

        //     // ------------------------ CHECK OPP DIR SWAP --------------------------- //
        //     //TODO: Deduct fees from amount out = 5BPS.
        //     bytes32 otherPairId = keccak256(abi.encodePacked(D_TOKEN, tokenA));
        //     Queue.QueueStruct storage oppositePoolStream = poolStreamQueue[otherPairId];

        //     if (oppositePoolStream.data.length != 0) {
        //         Swap storage oppositeSwap = oppositePoolStream.data[oppositePoolStream.front];
        //         // A->B , dout1 is D1, amountOut1 is B
        //         uint256 dOutA =
        //             poolLogic.getDOut(frontSwap.swapAmountRemaining, poolInfo[tokenA].reserveA, poolInfo[tokenA].reserveD);
        //         // B->A
        //         uint256 amountOutB = poolLogic.getTokenOut(
        //             oppositeSwap.swapAmountRemaining, poolInfo[tokenA].reserveA, poolInfo[tokenA].reserveD
        //         );
        //         /*

        //         if I am depositing 10TKN -> ??? D (5)
        //         Alice is withdrawing 15 D -> ??? TKN (30)

        //         My order should be fulfilled completely by alice's.

        //         AmountIn1 = AmountIn1 - AmountIn1
        //         AmountOut1 = amountOut1

        //         AmountIn2 = AmountIn2 - AmountOut1
        //         AmountOut2 = AmountOut2 + AmountIn1

        //         */

        //         // TKN , TKN
        //         if (frontSwap.swapAmountRemaining < amountOutB) {
        //             // update pool

        //             frontSwap.amountOut = dOutA;

        //             //update user vault info
        //             userVaultInfo[tokenA][frontSwap.user].dAmount = dOutA;
        //             userVaultInfo[tokenA][frontSwap.user].tokenAmount = 0;

        //             frontSwap.completed = true;
        //             frontSwap.streamsRemaining = 0;

        //             oppositeSwap.swapAmountRemaining -= dOutA;
        //             oppositeSwap.amountOut += frontSwap.swapAmountRemaining;

        //             frontSwap.swapAmountRemaining = 0;

        //             // TODO: Complete stream and send it to vault
        //             // // ----------- to set transfer
        //             // completedSwapToken = frontSwap.tokenIn;
        //             // swapUser = frontSwap.user;
        //             // amountOutSwap = frontSwap.amountOut;
        //             // // -----------

        //             poolStreamQueue[pairId].data[poolStream.front] = frontSwap;
        //             Queue.dequeue(poolStreamQueue[pairId]);
        //         } else {
        //             oppositeSwap.amountOut = amountOutB;

        //             //update user vault info
        //             userVaultInfo[tokenA][oppositeSwap.user].tokenAmount = amountOutB;
        //             userVaultInfo[tokenA][oppositeSwap.user].dAmount = 0;

        //             frontSwap.swapAmountRemaining -= amountOutB;
        //             frontSwap.amountOut += oppositeSwap.swapAmountRemaining;

        //             oppositeSwap.swapAmountRemaining = 0;

        //             oppositeSwap.completed = true;
        //             oppositeSwap.streamsRemaining = 0;

        //             // // ----------- to set transfer
        //             // completedSwapToken = oppositeSwap.tokenIn;
        //             // swapUser = oppositeSwap.user;
        //             // amountOutSwap = oppositeSwap.amountOut;
        //             // // -----------

        //             poolStreamQueue[otherPairId].data[oppositePoolStream.front] = oppositeSwap;
        //             Queue.dequeue(poolStreamQueue[otherPairId]);
        //         }
        //     } else {
        //         uint256 dOutA =
        //             poolLogic.getDOut(frontSwap.swapPerStream, poolInfo[tokenA].reserveA, poolInfo[tokenA].reserveD);

        //         //TODO: Deduct fees from amount out = 5BPS.
        //         frontSwap.swapAmountRemaining -= frontSwap.swapPerStream;
        //         frontSwap.amountOut += dOutA;
        //         frontSwap.streamsRemaining--;

        //         // update user info
        //         userVaultInfo[tokenA][frontSwap.user].tokenAmount -= frontSwap.swapPerStream;
        //         userVaultInfo[tokenA][frontSwap.user].dAmount += dOutA;

        //         if (frontSwap.streamsRemaining == 0) {
        //             frontSwap.completed = true;
        //             // completedSwapToken = frontSwap.tokenIn;
        //             // swapUser = frontSwap.user;
        //             // amountOutSwap = frontSwap.amountOut;
        //         }

        //         poolStreamQueue[pairId].data[poolStream.front] = frontSwap;

        //         if (poolStreamQueue[pairId].data[poolStream.front].streamsCount == 0) {
        //             Queue.dequeue(poolStreamQueue[pairId]);
        //         }
        //     }
    }

    function _executeWithdrawVaultStream(bytes32 pairId, address tokenA) internal {
        //     // loading the front swap from the stream queue
        //     Swap storage frontSwap;
        //     Queue.QueueStruct storage poolStream = poolStreamQueue[pairId];
        //     frontSwap = poolStream.data[poolStream.front];

        //     // ------------------------ CHECK OPP DIR SWAP --------------------------- //
        //     //TODO: Deduct fees from amount out = 5BPS.
        //     bytes32 otherPairId = keccak256(abi.encodePacked(tokenA, D_TOKEN));
        //     Queue.QueueStruct storage oppositePoolStream = poolStreamQueue[otherPairId];

        //     if (oppositePoolStream.data.length != 0) {
        //         Swap storage oppositeSwap = oppositePoolStream.data[oppositePoolStream.front];
        //         // A->B , dout1 is D1, amountOut1 is B

        //         uint256 amountOutA = poolLogic.getTokenOut(
        //             frontSwap.swapAmountRemaining, poolInfo[tokenA].reserveA, poolInfo[tokenA].reserveD
        //         );

        //         uint256 dOutB = poolLogic.getDOut(
        //             oppositeSwap.swapAmountRemaining, poolInfo[tokenA].reserveA, poolInfo[tokenA].reserveD
        //         );
        //         // B->A

        //         /*

        //         Alice is withdrawing 15 D -> ??? TKN (30)
        //         if I am depositing 60TKN -> ??? D (30)

        //         Alice's order should be fulfilled completely by mine.

        //         AmountIn1 = AmountIn1 - AmountIn1
        //         AmountOut1 = amountOut1

        //         AmountIn2 = AmountIn2 - AmountOut1
        //         AmountOut2 = AmountOut2 + AmountIn1

        //         */

        //         // TKN , TKN
        //         if (frontSwap.swapAmountRemaining < dOutB) {
        //             // update pool

        //             frontSwap.amountOut += amountOutA;

        //             //update user vault info
        //             userVaultInfo[tokenA][frontSwap.user].dAmount = 0;
        //             userVaultInfo[tokenA][frontSwap.user].tokenAmount += amountOutA;

        //             frontSwap.completed = true;
        //             frontSwap.streamsRemaining = 0;

        //             oppositeSwap.swapAmountRemaining -= amountOutA;
        //             oppositeSwap.amountOut += frontSwap.swapAmountRemaining;

        //             frontSwap.swapAmountRemaining = 0;

        //             // TODO: Complete stream and send it to vault
        //             // // ----------- to set transfer
        //             // completedSwapToken = frontSwap.tokenIn;
        //             // swapUser = frontSwap.user;
        //             // amountOutSwap = frontSwap.amountOut;
        //             // // -----------

        //             poolStreamQueue[pairId].data[poolStream.front] = frontSwap;
        //             Queue.dequeue(poolStreamQueue[pairId]);
        //         } else {
        //             oppositeSwap.amountOut += dOutB;

        //             //update user vault info
        //             userVaultInfo[tokenA][oppositeSwap.user].tokenAmount = 0;
        //             userVaultInfo[tokenA][oppositeSwap.user].dAmount += dOutB;

        //             frontSwap.swapAmountRemaining -= dOutB;
        //             frontSwap.amountOut += oppositeSwap.swapAmountRemaining;

        //             oppositeSwap.swapAmountRemaining = 0;

        //             oppositeSwap.completed = true;
        //             oppositeSwap.streamsRemaining = 0;

        //             // // ----------- to set transfer
        //             // completedSwapToken = oppositeSwap.tokenIn;
        //             // swapUser = oppositeSwap.user;
        //             // amountOutSwap = oppositeSwap.amountOut;
        //             // // -----------

        //             poolStreamQueue[otherPairId].data[oppositePoolStream.front] = oppositeSwap;
        //             Queue.dequeue(poolStreamQueue[otherPairId]);
        //         }
        //     } else {
        //         uint256 amountOutA =
        //             poolLogic.getTokenOut(frontSwap.swapPerStream, poolInfo[tokenA].reserveA, poolInfo[tokenA].reserveD);

        //         // uint256 dOutA =
        //         //     poolLogic.getDOut(frontSwap.swapPerStream, poolInfo[tokenA].reserveA, poolInfo[tokenA].reserveD);

        //         //TODO: Deduct fees from amount out = 5BPS.
        //         frontSwap.swapAmountRemaining -= frontSwap.swapPerStream;
        //         frontSwap.amountOut += amountOutA;
        //         frontSwap.streamsRemaining--;

        //         // update user info
        //         userVaultInfo[tokenA][frontSwap.user].tokenAmount += amountOutA;
        //         userVaultInfo[tokenA][frontSwap.user].dAmount -= frontSwap.swapPerStream;

        //         if (frontSwap.streamsRemaining == 0) {
        //             frontSwap.completed = true;
        //             // completedSwapToken = frontSwap.tokenIn;
        //             // swapUser = frontSwap.user;
        //             // amountOutSwap = frontSwap.amountOut;
        //         }

        //         poolStreamQueue[pairId].data[poolStream.front] = frontSwap;

        //         if (poolStreamQueue[pairId].data[poolStream.front].streamsCount == 0) {
        //             Queue.dequeue(poolStreamQueue[pairId]);
        //         }
        //     }
    }

    // function _removeSwap(uint256 swapId, Queue.QueueStruct storage swapQueue)
    //     internal
    //     returns (Queue.QueueStruct storage, uint256, uint256)
    // {
    //     if (swapQueue.data[swapId].user == address(0)) revert InvalidSwap();
    //     // transferring the remaining amount
    //     uint256 amountIn = swapQueue.data[swapId].swapAmountRemaining;
    //     uint256 amountOut = swapQueue.data[swapId].amountOut;
    //     address user = swapQueue.data[swapId].user;
    //     address token = swapQueue.data[swapId].tokenIn;
    //     address tokenOut = swapQueue.data[swapId].tokenOut;

    //     //  IERC20(token).transfer(user, amountIn);
    //     //  IERC20(tokenOut).transfer(user, amountOut);

    //     if (swapId == 0) {
    //         swapQueue.front++;
    //     } else if (swapId == swapQueue.back) {
    //         Queue.dequeue(swapQueue);
    //     } else {
    //         // iterate over queue to fix the index data
    //         uint256 i = swapId;
    //         uint256 lengthOfIteration = swapQueue.data.length - 1;

    //         for (i; i < lengthOfIteration; i++) {
    //             swapQueue.data[i] = swapQueue.data[i + 1];
    //         }
    //         swapQueue.back--;
    //     }

    //     return (swapQueue, amountIn, amountOut);
    // }

    function poolInfo(address tokenAddress)
        external
        view
        returns (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 minLaunchReserveA,
            uint256 minLaunchReserveD,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        )
    {
        return (
            mapToken_reserveD[tokenAddress],
            mapToken_poolOwnershipUnitsTotal[tokenAddress],
            mapToken_reserveA[tokenAddress],
            mapToken_minLaunchReserveA[tokenAddress],
            mapToken_minLaunchReserveD[tokenAddress],
            mapToken_initialDToMint[tokenAddress],
            mapToken_poolFeeCollected[tokenAddress],
            mapToken_initialized[tokenAddress]
        );
    }

    function poolStreamQueue(bytes32 pairId) external view returns (Swap[] memory swaps, uint256 front, uint256 back) {
        return (
            mapPairId_poolStreamQueue_Swaps[pairId],
            mapPairId_poolStreamQueue_front[pairId],
            mapPairId_poolStreamQueue_back[pairId]
        );
    }

    function pairStreamQueue(bytes32 pairId) external view returns (Swap[] memory swaps, uint256 front, uint256 back) {
        return (
            mapPairId_pairStreamQueue_Swaps[pairId],
            mapPairId_pairStreamQueue_front[pairId],
            mapPairId_pairStreamQueue_back[pairId]
        );
    }

    function pairPendingQueue(bytes32 pairId)
        external
        view
        returns (Swap[] memory swaps, uint256 front, uint256 back)
    {
        return (
            mapPairId_pairPendingQueue_Swaps[pairId],
            mapPairId_pairPendingQueue_front[pairId],
            mapPairId_pairPendingQueue_back[pairId]
        );
    }
}
