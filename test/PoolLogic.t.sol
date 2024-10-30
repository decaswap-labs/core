// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Pool.sol";
import "../src/PoolLogic.sol";
import "../src/Router.sol";
import "../src/interfaces/router/IRouterErrors.sol";
import "../src/interfaces/pool-logic/IPoolLogicErrors.sol";
import "../src/interfaces/pool/IPoolErrors.sol";
import "../src/MockERC20.sol"; // Mock token for testing
import "./utils/Utils.t.sol";

contract PoolLogicTest is Test, Utils {
    Pool public pool;
    PoolLogic poolLogic;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    Router public router;
    address public owner = address(0xD);
    address public nonAuthorized = address(0xE);

    function setUp() public {
        vm.startPrank(owner);

        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        poolLogic = new PoolLogic(owner, address(0)); // setting zero address for poolAddress as not deployed yet.
        pool = new Pool(address(0), address(router), address(poolLogic));

        // Approve pool contract to spend tokens
        tokenA.approve(address(router), 1000e18);
        tokenB.approve(address(router), 1000e18);
        router = new Router(owner, address(pool));

        pool.updateRouterAddress(address(router));
        poolLogic.updatePoolAddress(address(pool)); // Setting poolAddress (kind of initialization)

        vm.stopPrank();
    }

    // ================================== GENESIS POOL ============================== //

    function test_initGenesisPool_success() public {
        vm.startPrank(owner);
        uint256 addLiquidityTokenAmount = 100e18;
        tokenA.transfer(address(router), addLiquidityTokenAmount);
        vm.stopPrank();

        vm.startPrank(address(router));
        uint256 dToMint = 50e18;
        uint256 lpUnitsBefore =
            poolLogic.calculateLpUnitsToMint(0, addLiquidityTokenAmount, addLiquidityTokenAmount, dToMint, 0);
        tokenA.transfer(address(pool), addLiquidityTokenAmount);

        poolLogic.initGenesisPool(address(tokenA), owner, addLiquidityTokenAmount, dToMint);

        uint256 lpUnitsAfter = pool.userLpUnitInfo(owner, address(tokenA));

        assertEq(lpUnitsBefore, lpUnitsAfter);

        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            bool initialized
        ) = pool.poolInfo(address(tokenA));

        uint256 poolBalanceAfter = tokenA.balanceOf(address(pool));

        assertEq(reserveD, dToMint);
        assertEq(lpUnitsAfter, lpUnitsBefore);
        assertEq(poolOwnershipUnitsTotal, lpUnitsAfter);
        assertEq(reserveA, addLiquidityTokenAmount);
        assertEq(poolBalanceAfter, addLiquidityTokenAmount);
        assertEq(initialDToMint, dToMint);
        assertEq(initialized, true);
    }

    function test_initGenesisPool_invalidOwner() public {
        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(getNotRouterLogicSelector(), owner));

        poolLogic.initGenesisPool(address(tokenA), owner, 1, 1);
    }

    //------------- INIT PERMISSIONLESS POOL ---------------- //

    function _initGenesisPool(uint256 d, uint256 a, uint256 b) internal {
        vm.startPrank(owner);
        tokenB.transfer(address(pool), a);
        tokenA.transfer(address(pool), b);
        vm.stopPrank();

        vm.startPrank(address(router));
        poolLogic.initGenesisPool(address(tokenA), owner, a, d);
        vm.stopPrank();
    }

    function test_initPool_success() public {
        uint256 tokenBLiquidityAmount = 100e18;
        uint256 tokenAStreamLiquidityAmount = 50e18;
        uint256 dToMint = 10e18;

        _initGenesisPool(dToMint, tokenBLiquidityAmount, tokenAStreamLiquidityAmount);

        vm.startPrank(address(router));

        uint256 tokenAStreamCountBefore =
            poolLogic.calculateStreamCount(tokenAStreamLiquidityAmount, pool.globalSlippage(), dToMint);
        uint256 swapPerStream = tokenAStreamLiquidityAmount / tokenAStreamCountBefore;

        (uint256 reserveDBeforeA,, uint256 reserveABeforeA,,,) = pool.poolInfo(address(tokenA));

        (uint256 reserveDBeforeB, uint256 poolOwnershipUnitsTotalBeforeB, uint256 reserveABeforeB,,,) =
            pool.poolInfo(address(tokenB));

        (uint256 dToTransfer,) = poolLogic.getSwapAmountOut(swapPerStream, reserveABeforeA, 0, reserveDBeforeA, 0);
        uint256 lpUnitsBefore = poolLogic.calculateLpUnitsToMint(0, tokenBLiquidityAmount, tokenBLiquidityAmount, 0, 0);

        poolLogic.initPool(address(tokenB), address(tokenA), owner, tokenBLiquidityAmount, tokenAStreamLiquidityAmount);
        (uint256 reserveDAfterA,, uint256 reserveAAfterA,,,) = pool.poolInfo(address(tokenA));

        (uint256 reserveDAfterB, uint256 poolOwnershipUnitsTotalAfterB, uint256 reserveAAfterB,,,) =
            pool.poolInfo(address(tokenB));

        bytes32 pairId = keccak256(abi.encodePacked(address(tokenB), address(tokenA)));

        (LiquidityStream[] memory streams, uint256 front, uint256 back) = pool.liquidityStreamQueue(pairId);

        assertEq(streams[front].poolBStream.streamsRemaining, tokenAStreamCountBefore - 1);
        assertEq(streams[front].poolBStream.swapPerStream, swapPerStream);
        assertEq(streams[front].poolBStream.swapAmountRemaining, tokenAStreamLiquidityAmount - swapPerStream);

        assertEq(streams[front].poolAStream.streamCount, 0);
        assertEq(streams[front].poolAStream.swapPerStream, 0);

        assertEq(reserveDAfterA, reserveDBeforeA - dToTransfer);
        assertEq(reserveAAfterA, reserveABeforeA + swapPerStream);

        assertEq(poolOwnershipUnitsTotalAfterB, poolOwnershipUnitsTotalBeforeB + lpUnitsBefore);
        assertEq(reserveDAfterB, reserveDBeforeB + dToTransfer);
        assertEq(reserveAAfterB, reserveABeforeB + tokenBLiquidityAmount);
    }

    function test_initPool_invalidOwner() public {
        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(getNotRouterLogicSelector(), owner));

        poolLogic.initPool(address(tokenB), address(tokenA), owner, 1, 1);
    }
}
