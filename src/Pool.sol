// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IPool} from "./interfaces/IPool.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolLogicActions} from "./interfaces/pool-logic/IPoolLogicActions.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Queue} from "./lib/SwapQueue.sol";
import {Swap, LiquidityStream} from "./lib/SwapQueue.sol"; // @todo keep structs in a different place
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

    // DStreamQueue struct
    mapping(bytes32 pairId => LiquidityStream[] liquidityStream) public mapPairId_streamQueue_liquidityStream;
    mapping(bytes32 pairId => uint256 front) public mapPairId_streamQueue_front;
    mapping(bytes32 pairId => uint256 back) public mapPairId_streamQueue_back;

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

    // creatPoolParams encoding format => (address token, address user, uint256 amount, uint256 minLaunchReserveA, uint256 minLaunchReserveD, uint256 initialDToMint, uint newLpUnits, uint newDUnits, uint256 poolFeeCollected)
    // function createPool(bytes calldata creatPoolParams) external onlyPoolLogic {
    //     (
    //         address token,
    //         address user,
    //         uint256 amount,
    //         uint256 minLaunchReserveA,
    //         uint256 minLaunchReserveD,
    //         uint256 initialDToMint,
    //         uint256 newLpUnits,
    //         uint256 newDUnits,
    //         uint256 poolFeeCollected
    //     ) = abi.decode(
    //         creatPoolParams, (address, address, uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    //     );
    //     _createPool(token, minLaunchReserveA, minLaunchReserveD, initialDToMint);
    //     bytes memory addLiqParam = abi.encode(token, user, amount, newLpUnits, newDUnits, poolFeeCollected);
    //     _addLiquidity(addLiqParam);
    // }

    // initGenesisPool encoding format => (address token, address user, uint256 amount, uint256 initialDToMint, uint newLpUnits, uint newDUnits, uint256 poolFeeCollected)
    function initGenesisPool(bytes calldata initPoolParams) external onlyPoolLogic {
        (
            address token,
            address user,
            uint256 amount,
            uint256 initialDToMint,
            uint256 newLpUnits,
            uint256 newDUnits,
            uint256 poolFeeCollected
        ) = abi.decode(initPoolParams, (address, address, uint256, uint256, uint256, uint256, uint256));
        _initPool(token, initialDToMint);
        bytes memory addLiqParam = abi.encode(token, user, amount, newLpUnits, newDUnits, poolFeeCollected);
        mapToken_reserveD[token] += newDUnits;
        _addLiquidity(addLiqParam);
    }

    // initPool encoding format => (address token, address user, uint256 amount, uint newLpUnits, uint256 poolFeeCollected)
    function initPool(bytes calldata initPoolParams) external onlyPoolLogic {
        (address token, address user, uint256 amount, uint256 newLpUnits, uint256 poolFeeCollected) =
            abi.decode(initPoolParams, (address, address, uint256, uint256, uint256));
        _initPool(token, 0);
        bytes memory addLiqParam = abi.encode(token, user, amount, newLpUnits, 0, poolFeeCollected);
        _addLiquidity(addLiqParam);
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

    function enqueueLiquidityStream(bytes32 pairId, LiquidityStream memory liquidityStream) external onlyPoolLogic {
        mapPairId_streamQueue_liquidityStream[pairId].push(liquidityStream);
        mapPairId_streamQueue_back[pairId]++;
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

    // updateReservesParams encoding format => (address tokenA, address tokenB, uint256 reserveA_A, uint256 reserveA_B, uint256 changeInD)
    function updateReservesWhenStreamingLiq(bytes memory updatedReservesParams) external onlyPoolLogic {
        (address tokenA, address tokenB, uint256 reserveA_A, uint256 reserveA_B, uint256 changeInD) =
            abi.decode(updatedReservesParams, (address, address, uint256, uint256, uint256));
        mapToken_reserveA[tokenA] += reserveA_A;
        mapToken_reserveD[tokenA] += changeInD;

        mapToken_reserveA[tokenB] += reserveA_B;
        mapToken_reserveD[tokenB] -= changeInD;
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

    // updatedStreamData encoding format => (bytes32 pairId, uint256 amountAToDeduct, uint256 amountBToDeduct, uint256 poolAStreamsRemaining,uint256 poolBStreamsRemaining, uint dAmountOut)
    function updateStreamQueueLiqStream(bytes memory updatedStreamData) external onlyPoolLogic {
        (
            bytes32 pairId,
            uint256 amountAToDeduct,
            uint256 amountBToDeduct,
            uint256 poolAStreamsRemaining,
            uint256 poolBStreamsRemaining,
            uint256 dAmountOut
        ) = abi.decode(updatedStreamData, (bytes32, uint256, uint256, uint256, uint256, uint256));
        LiquidityStream storage liquidityStream =
            mapPairId_streamQueue_liquidityStream[pairId][mapPairId_streamQueue_front[pairId]];
        liquidityStream.poolAStream.swapAmountRemaining -= amountAToDeduct;
        liquidityStream.poolBStream.swapAmountRemaining -= amountBToDeduct;
        liquidityStream.poolAStream.streamsRemaining = poolAStreamsRemaining;
        liquidityStream.poolBStream.streamsRemaining = poolBStreamsRemaining;
        liquidityStream.dAmountOut += dAmountOut;
    }

    // @todo ask if we should sort it here, or pass sorted array from logic and just save
    function sortPairPendingQueue(bytes32 pairId) external onlyPoolLogic {
        // Sort the array w.r.t price
        SwapSorter.quickSort(mapPairId_pairPendingQueue_Swaps[pairId]);
    }

    function transferTokens(address token, address to, uint256 amount) external onlyPoolLogic {
        IERC20(token).safeTransfer(to, amount);
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

    function updatePairSlippage(address tokenA, address tokenB, uint256 newSlippage) external override onlyOwner {
        bytes32 poolId = getPoolId(tokenA, tokenB);
        pairSlippage[poolId] = newSlippage;
        emit PairSlippageUpdated(tokenA, tokenB, newSlippage);
    }

    function updateGlobalSlippage(uint256 newGlobalSlippage) external override onlyOwner {
        emit GlobalSlippageUpdated(globalSlippage, newGlobalSlippage);
        globalSlippage = newGlobalSlippage;
    }

    // function _createPool(address token, uint256 minLaunchReserveA, uint256 minLaunchReserveD, uint256 initialDToMint)
    //     internal
    // {
    //     if (mapToken_initialized[token]) revert DuplicatePool();

    //     mapToken_initialized[token] = true;
    //     mapToken_minLaunchReserveA[token] = minLaunchReserveA;
    //     mapToken_minLaunchReserveD[token] = minLaunchReserveD;
    //     // @todo need confirmation on that. hardcoded?
    //     mapToken_initialDToMint[token] = initialDToMint;

    //     emit PoolCreated(token, minLaunchReserveA, minLaunchReserveD);
    // }

    function _initPool(address token, uint256 initialDToMint) internal {
        if (mapToken_initialized[token]) revert DuplicatePool();

        mapToken_initialized[token] = true;
        // @todo need confirmation on that. hardcoded?
        mapToken_initialDToMint[token] = initialDToMint;

        emit PoolCreated(token, initialDToMint);
    }

    // addLiqParams encoding format => (address token, address user, uint amount, uint256 newLpUnits, uint256 newDUnits, uint256 poolFeeCollected)
    function _addLiquidity(bytes memory addLiqParams) internal {
        (address token, address user, uint256 amount, uint256 newLpUnits, uint256 newDUnits, uint256 poolFeeCollected) =
            abi.decode(addLiqParams, (address, address, uint256, uint256, uint256, uint256));

        mapToken_reserveA[token] += amount;
        mapToken_poolOwnershipUnitsTotal[token] += newLpUnits;
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
        mapToken_poolFeeCollected[token] += poolFeeCollected;

        IERC20(token).safeTransfer(user, assetToTransfer);

        emit LiquidityRemoved(user, token, lpUnits, assetToTransfer, dAmountToDeduct);
    }

    function poolInfo(address tokenAddress)
        external
        view
        returns (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        )
    {
        return (
            mapToken_reserveD[tokenAddress],
            mapToken_poolOwnershipUnitsTotal[tokenAddress],
            mapToken_reserveA[tokenAddress],
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

    function liquidityStreamQueue(bytes32 pairId)
        external
        view
        returns (LiquidityStream[] memory liquidityStream, uint256 front, uint256 back)
    {
        return (
            mapPairId_streamQueue_liquidityStream[pairId],
            mapPairId_streamQueue_front[pairId],
            mapPairId_streamQueue_back[pairId]
        );
    }

    function getPoolId(address tokenA, address tokenB) public pure returns (bytes32) {
        (address A, address B) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(A, B));
    }
}
