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
        tokenA.approve(address(pool), 1000e18);
        tokenB.approve(address(pool), 1000e18);
        router = new Router(owner, address(pool));

        pool.updateRouterAddress(address(router));
        poolLogic.updatePoolAddress(address(pool)); // Setting poolAddress (kind of initialization)

        vm.stopPrank();
    }

    // ================================== GENESIS POOL ============================== //

    // function test_initGenesisPool_success() public {
    //     vm.startPrank(owner);
    //     uint256 addLiquidityTokenAmount = 100e18;
    //     tokenA.transfer(address(router), addLiquidityTokenAmount);
    //     vm.stopPrank();

    //     vm.startPrank(address(router));
    //     uint256 dToMint = 50e18;
    //     uint256 lpUnitsBefore = poolLogic.calculateLpUnitsToMint(addLiquidityTokenAmount, 0, 0);
    //     tokenA.transfer(address(pool), addLiquidityTokenAmount);

    //     poolLogic.initGenesisPool(address(tokenA), owner, addLiquidityTokenAmount, dToMint);

    //     uint256 lpUnitsAfter = pool.userLpUnitInfo(owner, address(tokenA));

    //     assertEq(lpUnitsBefore, lpUnitsAfter);

    //     (
    //         uint256 reserveD,
    //         uint256 poolOwnershipUnitsTotal,
    //         uint256 reserveA,
    //         uint256 initialDToMint,
    //         uint256 poolFeeCollected,
    //         bool initialized
    //     ) = pool.poolInfo(address(tokenA));

    //     uint256 poolBalanceAfter = tokenA.balanceOf(address(pool));

    //     assertEq(reserveD, dToMint);
    //     assertEq(poolOwnershipUnitsTotal, lpUnitsAfter);
    //     assertEq(reserveA, addLiquidityTokenAmount);
    //     assertEq(poolBalanceAfter, addLiquidityTokenAmount);
    //     assertEq(initialDToMint, dToMint);
    //     assertEq(initialized, true);
    // }

    function test_initGenesisPool_invalidOwner() public {
        vm.startPrank(owner);

        vm.expectRevert(abi.encodeWithSelector(getNotRouterLogicSelector(), owner));

        poolLogic.initGenesisPool(address(tokenA), owner, 1, 1);
    }

    //------------- CREATE POOL TEST ---------------- //
    // function test_createPool_success() public {
    //     vm.startPrank(owner);

    //     uint256 tokenAAmount = 1000e18;
    //     uint256 minLaunchReserveAa = 500e18;
    //     uint256 minLaunchReserveDd = 50e18;
    //     uint256 initialDToMintt = 50e18;

    //     uint256 balanceBefore = tokenA.balanceOf(owner);

    //     tokenA.transfer(address(pool), tokenAAmount);

    //     poolLogic.createPool(
    //         address(tokenA), owner, tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt
    //     );

    //     (
    //         uint256 reserveD,
    //         uint256 poolOwnershipUnitsTotal,
    //         uint256 reserveA,
    //         uint256 minLaunchReserveA,
    //         uint256 minLaunchReserveD,
    //         uint256 initialDToMint,
    //         uint256 poolFeeCollected,
    //         bool initialized
    //     ) = pool.poolInfo(address(tokenA));

    //     uint256 userLpUnits = pool.userLpUnitInfo(owner, address(tokenA));

    //     uint256 balanceAfter = tokenA.balanceOf(owner);

    //     assertEq(reserveA, tokenAAmount);
    //     assertEq(reserveD, initialDToMintt);
    //     assertEq(minLaunchReserveA, minLaunchReserveAa);
    //     assertEq(minLaunchReserveD, minLaunchReserveDd);
    //     assertEq(balanceAfter, balanceBefore - tokenAAmount);
    //     assertEq(userLpUnits, poolOwnershipUnitsTotal);

    //     vm.stopPrank();
    // }

    // function test_createPool_poolAlreadyExists() public {
    //     vm.startPrank(owner);

    //     uint256 tokenAAmount = 1000e18;
    //     uint256 minLaunchReserveAa = 500e18;
    //     uint256 minLaunchReserveDd = 50e18;
    //     uint256 initialDToMintt = 50e18;

    //     tokenA.transfer(address(pool), tokenAAmount);

    //     poolLogic.createPool(
    //         address(tokenA), owner, tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt
    //     );

    //     vm.expectRevert(IPoolErrors.DuplicatePool.selector);
    //     poolLogic.createPool(
    //         address(tokenA), owner, tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt
    //     );

    //     vm.stopPrank();
    // }

    // function test_createPool_unauthorizedAddress() public {
    //     vm.startPrank(nonAuthorized);

    //     uint256 tokenAAmount = 1000e18;
    //     uint256 minLaunchReserveAa = 500e18;
    //     uint256 minLaunchReserveDd = 50e18;
    //     uint256 initialDToMintt = 50e18;

    //     vm.expectRevert(abi.encodeWithSelector(IPoolLogicErrors.NotRouter.selector, nonAuthorized));

    //     poolLogic.createPool(
    //         address(tokenA), owner, tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt
    //     );

    //     vm.stopPrank();
    // }

    // // ------------ ADD LIQUIDITY TEST --------------- //
    // function test_addLiquidity_success() public {
    //     vm.startPrank(owner);

    //     uint256 tokenAAmount = 1000e18;
    //     uint256 minLaunchReserveAa = 500e18;
    //     uint256 minLaunchReserveDd = 50e18;
    //     uint256 initialDToMintt = 50e18;

    //     uint256 balanceBefore = tokenA.balanceOf(owner);

    //     tokenA.transfer(address(pool), tokenAAmount);

    //     poolLogic.createPool(
    //         address(tokenA), owner, tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt
    //     );

    //     (
    //         uint256 reserveDBefore,
    //         uint256 poolOwnershipUnitsTotalBefore,
    //         uint256 reserveABefore,
    //         uint256 minLaunchReserveABefore,
    //         uint256 minLaunchReserveDBefore,
    //         uint256 initialDToMintBefore,
    //         uint256 poolFeeCollectedBefore,
    //         bool initializedB
    //     ) = pool.poolInfo(address(tokenA));

    //     uint256 amountALiquidity = 1000e18;

    //     uint256 lpUnitsToMint =
    //         poolLogic.calculateLpUnitsToMint(amountALiquidity, reserveABefore, poolOwnershipUnitsTotalBefore);
    //     uint256 dUnitsToMint =
    //         poolLogic.calculateDUnitsToMint(amountALiquidity, reserveABefore + amountALiquidity, reserveDBefore, 0);
    //     uint256 userLpUnitsBefore = pool.userLpUnitInfo(owner, address(tokenA));

    //     tokenA.transfer(address(pool), amountALiquidity);

    //     poolLogic.addLiquidity(address(tokenA), owner, amountALiquidity);

    //     (
    //         uint256 reserveDAfter,
    //         uint256 poolOwnershipUnitsTotalAfter,
    //         uint256 reserveAAfter,
    //         uint256 minLaunchReserveAAfter, //unchanged
    //         uint256 minLaunchReserveDAfter, //unchanged
    //         uint256 initialDToMintAfter, //unchanged
    //         uint256 poolFeeCollectedAfter, //unchanged
    //         bool initializedA
    //     ) = pool.poolInfo(address(tokenA));

    //     uint256 userLpUnitsAfter = pool.userLpUnitInfo(owner, address(tokenA));

    //     assertEq(reserveAAfter, reserveABefore + amountALiquidity);
    //     assertEq(reserveDAfter, reserveDBefore + dUnitsToMint);
    //     assertEq(poolOwnershipUnitsTotalAfter, poolOwnershipUnitsTotalBefore + lpUnitsToMint);
    //     assertEq(userLpUnitsAfter, userLpUnitsBefore + lpUnitsToMint);
    // }

    // function test_addLiquidity_unauthorizedAddress() public {
    //     vm.startPrank(nonAuthorized);

    //     vm.expectRevert(abi.encodeWithSelector(IPoolLogicErrors.NotRouter.selector, nonAuthorized));

    //     poolLogic.addLiquidity(address(tokenA), owner, 0);

    //     vm.stopPrank();
    // }

    // // ------------ REMOVE LIQUIDITY TEST ------------- //
    // function test_removeLiquidity_success() public {
    //     vm.startPrank(owner);

    //     uint256 tokenAAmount = 1000e18;
    //     uint256 minLaunchReserveAa = 500e18;
    //     uint256 minLaunchReserveDd = 50e18;
    //     uint256 initialDToMintt = 50e18;

    //     tokenA.transfer(address(pool), tokenAAmount);
    //     poolLogic.createPool(
    //         address(tokenA), owner, tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt
    //     );

    //     uint256 balanceBefore = tokenA.balanceOf(owner);

    //     (
    //         uint256 reserveDBefore,
    //         uint256 poolOwnershipUnitsTotalBefore,
    //         uint256 reserveABefore,
    //         uint256 minLaunchReserveABefore,
    //         uint256 minLaunchReserveDBefore,
    //         uint256 initialDToMintBefore,
    //         uint256 poolFeeCollectedBefore,
    //         bool initializedB
    //     ) = pool.poolInfo(address(tokenA));

    //     uint256 userLpAmount = pool.userLpUnitInfo(owner, address(tokenA));

    //     uint256 assetToTransfer =
    //         poolLogic.calculateAssetTransfer(userLpAmount, reserveABefore, poolOwnershipUnitsTotalBefore);
    //     uint256 dToDeduct = poolLogic.calculateDToDeduct(userLpAmount, reserveDBefore, poolOwnershipUnitsTotalBefore);

    //     poolLogic.removeLiquidity(address(tokenA), owner, userLpAmount);

    //     (
    //         uint256 reserveDAfter,
    //         uint256 poolOwnershipUnitsTotalAfter,
    //         uint256 reserveAAfter,
    //         uint256 minLaunchReserveAAfter, //unchanged
    //         uint256 minLaunchReserveDAfter, //uncahnged
    //         uint256 initialDToMintAfter, //unchanged
    //         uint256 poolFeeCollectedAfter, //unchanged
    //         bool initializedd //unchanged
    //     ) = pool.poolInfo(address(tokenA));

    //     uint256 userLpUnitsAfter = pool.userLpUnitInfo(address(tokenA), owner);
    //     uint256 balanceAfter = tokenA.balanceOf(owner);

    //     assertEq(balanceAfter, balanceBefore + assetToTransfer);
    //     assertEq(reserveDAfter, reserveDBefore - dToDeduct);
    //     assertEq(reserveAAfter, reserveABefore - assetToTransfer);
    //     assertEq(poolOwnershipUnitsTotalAfter, poolOwnershipUnitsTotalBefore - userLpAmount);
    // }

    // function test_removeLiquidity_unauthorizedAddress() public {
    //     vm.startPrank(nonAuthorized);

    //     vm.expectRevert(abi.encodeWithSelector(IPoolLogicErrors.NotRouter.selector, nonAuthorized));

    //     poolLogic.removeLiquidity(address(tokenA), owner, 0);

    //     vm.stopPrank();
    // }
}
