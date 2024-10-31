// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Pool.sol";
import "../src/PoolLogic.sol";
import "../src/Router.sol";
import "../src/interfaces/router/IRouterErrors.sol";
import "../src/interfaces/pool/IPoolErrors.sol";
import "../src/MockERC20.sol"; // Mock token for testing
import "./utils/Utils.t.sol";
import "forge-std/console.sol";

contract PoolTest is Test, Utils {
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
        tokenA.approve(address(pool), 1000e18);
        tokenB.approve(address(pool), 1000e18);
        router = new Router(owner, address(pool));

        pool.updateRouterAddress(address(router));
        poolLogic.updatePoolAddress(address(pool)); // Setting poolAddress (kind of initialization)

        vm.stopPrank();
    }

    // =================== GENESIS POOL ==================== //

    function test_initGenesisPool_success() public {
        vm.startPrank(owner);
        uint256 addLiquidityTokenAmount = 100e18;
        tokenA.transfer(address(poolLogic), addLiquidityTokenAmount);
        vm.stopPrank();

        vm.startPrank(address(poolLogic));
        uint256 dToMint = 50e18;
        uint256 lpUnitsBefore =
            poolLogic.calculateLpUnitsToMint(0, addLiquidityTokenAmount, addLiquidityTokenAmount, dToMint, 0);
        tokenA.transfer(address(pool), addLiquidityTokenAmount);

        bytes memory initPoolParams =
            abi.encode(address(tokenA), owner, addLiquidityTokenAmount, dToMint, lpUnitsBefore, dToMint, 0);

        pool.initGenesisPool(initPoolParams);

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
        assertEq(poolOwnershipUnitsTotal, lpUnitsAfter);
        assertEq(lpUnitsAfter, lpUnitsBefore);
        assertEq(reserveA, addLiquidityTokenAmount);
        assertEq(poolBalanceAfter, addLiquidityTokenAmount);
        assertEq(initialDToMint, dToMint);
        assertEq(initialized, true);
    }

    // function test_initGenesisPool_invalidOwner() public {
    //     vm.startPrank(owner);

    //     vm.expectRevert(abi.encodeWithSelector(getNotPoolLogicSelector(), owner));

    //     bytes memory initPoolParams = abi.encode(address(tokenA), owner, 0, 0, 0, 0, 0);

    //     pool.initGenesisPool(initPoolParams);
    // }

    // //------------- INIT PERMISSIONLESS POOL ---------------- //

    // function _initGenesisPool(uint256 dToMint, uint256 tokenLiquidityB, uint256 tokenLiquidityA) internal {
    //     vm.startPrank(owner);
    //     tokenB.transfer(address(pool), tokenLiquidityB);
    //     tokenA.transfer(address(pool), tokenLiquidityA);
    //     vm.stopPrank();

    //     vm.startPrank(address(poolLogic));

    //     uint256 lpUnitsBefore = poolLogic.calculateLpUnitsToMint(0, tokenLiquidityA, tokenLiquidityA, dToMint, 0);
    //     bytes memory initPoolParams =
    //         abi.encode(address(tokenA), owner, tokenLiquidityA, dToMint, lpUnitsBefore, dToMint, 0);
    //     pool.initGenesisPool(initPoolParams);
    //     vm.stopPrank();
    // }

    // function test_initPool_success() public {
    //     uint256 tokenBLiquidityAmount = 100e18;
    //     uint256 tokenAStreamLiquidityAmount = 50e18;
    //     uint256 dToMint = 10e18;

    //     _initGenesisPool(dToMint, tokenBLiquidityAmount, tokenAStreamLiquidityAmount);

    //     vm.startPrank(address(poolLogic));

    //     uint256 tokenAStreamCountBefore =
    //         poolLogic.calculateStreamCount(tokenAStreamLiquidityAmount, pool.globalSlippage(), dToMint);
    //     uint256 swapPerStream = tokenAStreamLiquidityAmount / tokenAStreamCountBefore;

    //     (uint256 reserveDBeforeB, uint256 poolOwnershipUnitsTotalBeforeB, uint256 reserveABeforeB,,,) =
    //         pool.poolInfo(address(tokenB));

    //     uint256 lpUnitsBefore = poolLogic.calculateLpUnitsToMint(0, tokenBLiquidityAmount, tokenBLiquidityAmount, 0, 0);

    //     bytes memory initPoolParams = abi.encode(address(tokenB), owner, tokenBLiquidityAmount, lpUnitsBefore, 0);

    //     pool.initPool(initPoolParams);

    //     (uint256 reserveDAfterB, uint256 poolOwnershipUnitsTotalAfterB, uint256 reserveAAfterB,,,) =
    //         pool.poolInfo(address(tokenB));

    //     assertEq(reserveDAfterB, reserveDBeforeB);
    //     assertEq(reserveAAfterB, reserveABeforeB + tokenBLiquidityAmount);
    // }

    // function test_initPool_invalidOwner() public {
    //     vm.startPrank(owner);

    //     vm.expectRevert(abi.encodeWithSelector(getNotPoolLogicSelector(), owner));

    //     bytes memory initPoolParams = abi.encode(address(tokenB), owner, 1, 1, 0);

    //     pool.initPool(initPoolParams);
    // }
}
