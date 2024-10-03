// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Pool.sol";
import "../src/PoolLogic.sol";
import "../src/Router.sol";
import "../src/interfaces/router/IRouterErrors.sol";
import "../src/MockERC20.sol"; // Mock token for testing
import "./utils/Utils.t.sol";


contract RouterTest is Test, Utils {

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

        poolLogic = new PoolLogic(owner,address(0)); // setting zero address for poolAddress as not deployed yet.
        pool = new Pool(address(0), address(router), address(poolLogic));

        // Approve pool contract to spend tokens
        tokenA.approve(address(pool), 1000e18);
        tokenB.approve(address(pool), 1000e18);
        router = new Router(owner,address(pool));

        pool.updateRouterAddress(address(router));
        poolLogic.updatePoolAddress(address(pool)); // Setting poolAddress (kind of initialization)

        vm.stopPrank();

    }

    // //------------- CREATE POOL TEST ---------------- //
    // function test_createPool_success() public {
    //     vm.startPrank(owner);

    //     uint256 tokenAAmount = 1000e18;
    //     uint256 minLaunchReserveAa = 500e18;
    //     uint256 minLaunchReserveDd = 50e18;
    //     uint256 initialDToMintt = 50e18;

    //     tokenA.approve(address(router), tokenAAmount);

    //     uint256 balanceBefore = tokenA.balanceOf(owner);

    //     router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

    //     (
    //     uint256 reserveD,
    //     uint256 poolOwnershipUnitsTotal,
    //     uint256 reserveA,
    //     uint256 minLaunchReserveA,
    //     uint256 minLaunchReserveD,
    //     uint256 initialDToMint,
    //     uint256 poolFeeCollected,
    //     bool initialized
    //     ) = pool.poolInfo(address(tokenA));

    //     uint256 userLpUnits = pool.userLpUnitInfo(owner,address(tokenA));

    //     uint256 balanceAfter = tokenA.balanceOf(owner);

    //     assertEq(reserveA, tokenAAmount);
    //     assertEq(reserveD, initialDToMintt);
    //     assertEq(minLaunchReserveA, minLaunchReserveAa);
    //     assertEq(minLaunchReserveD, minLaunchReserveDd);
    //     assertEq(balanceAfter, balanceBefore-tokenAAmount);
    //     assertEq(userLpUnits, poolOwnershipUnitsTotal);

    //     vm.stopPrank();
    // }

    // function test_createPool_poolAlreadyExists() public {
    //     vm.startPrank(owner);

    //     uint256 tokenAAmount = 1000e18;
    //     uint256 minLaunchReserveAa = 500e18;
    //     uint256 minLaunchReserveDd = 50e18;
    //     uint256 initialDToMintt = 50e18;

    //     tokenA.approve(address(router), tokenAAmount);
    //     uint256 balanceBefore = tokenA.balanceOf(owner);
    //     router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

    //     vm.expectRevert(IRouterErrors.InvalidPool.selector);
    //     router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

    //     vm.stopPrank();
    // }

    // function test_createPoo_unauthorizedAddress() public {
    //     vm.startPrank(nonAuthorized);

    //     uint256 tokenAAmount = 1000e18;
    //     uint256 minLaunchReserveAa = 500e18;
    //     uint256 minLaunchReserveDd = 50e18;
    //     uint256 initialDToMintt = 50e18;

    //     tokenA.approve(address(router), tokenAAmount);

    //     uint256 balanceBefore = tokenA.balanceOf(owner);

    //     vm.expectRevert(abi.encodeWithSelector(getOwnableUnauthorizedAccountSelector(), nonAuthorized));

    //     router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);        
        
    //     vm.stopPrank();
    // }

    // // ------------ ADD LIQUIDITY TEST --------------- //
    // function test_addLiquidity_success() public {
    //     vm.startPrank(owner);

    //     uint256 tokenAAmount = 1000e18;
    //     uint256 minLaunchReserveAa = 500e18;
    //     uint256 minLaunchReserveDd = 50e18;
    //     uint256 initialDToMintt = 50e18;

    //     tokenA.approve(address(router), tokenAAmount);
    //     uint256 balanceBefore = tokenA.balanceOf(owner);
    //     router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

    //     (
    //     uint256 reserveDBefore,
    //     uint256 poolOwnershipUnitsTotalBefore,
    //     uint256 reserveABefore,
    //     uint256 minLaunchReserveABefore,
    //     uint256 minLaunchReserveDBefore,
    //     uint256 initialDToMintBefore,
    //     uint256 poolFeeCollectedBefore,
    //     bool initializedB
    //     ) = pool.poolInfo(address(tokenA));

    //     uint256 amountALiquidity = 1000e18;

    //     uint256 lpUnitsToMint = poolLogic.calculateLpUnitsToMint(amountALiquidity, reserveABefore, poolOwnershipUnitsTotalBefore);
    //     uint256 dUnitsToMint = poolLogic.calculateDUnitsToMint(amountALiquidity, reserveABefore+amountALiquidity, reserveDBefore, 0);
    //     uint256 userLpUnitsBefore = pool.userLpUnitInfo(owner,address(tokenA));
    //     console.log("%s", userLpUnitsBefore);

    //     tokenA.approve(address(router), amountALiquidity);

    //     router.addLiquidity(address(tokenA), amountALiquidity);

    //     (
    //     uint256 reserveDAfter,
    //     uint256 poolOwnershipUnitsTotalAfter,
    //     uint256 reserveAAfter,
    //     uint256 minLaunchReserveAAfter, //unchanged
    //     uint256 minLaunchReserveDAfter, //unchanged
    //     uint256 initialDToMintAfter, //unchanged
    //     uint256 poolFeeCollectedAfter, //unchanged
    //     bool initializedA
    //     ) = pool.poolInfo(address(tokenA));

    //     uint256 userLpUnitsAfter = pool.userLpUnitInfo(owner,address(tokenA));

    //     assertEq(reserveAAfter, reserveABefore+amountALiquidity);
    //     assertEq(reserveDAfter, reserveDBefore+dUnitsToMint);
    //     assertEq(poolOwnershipUnitsTotalAfter, poolOwnershipUnitsTotalBefore+lpUnitsToMint);
    //     assertEq(userLpUnitsAfter, userLpUnitsBefore+lpUnitsToMint);

    // }

    // function test_addLiquidity_invalidToken() public {
    //     vm.startPrank(owner);

    //     vm.expectRevert(IRouterErrors.InvalidPool.selector);

    //     router.addLiquidity(address(tokenB), 1);

    //     vm.stopPrank();
    // }

    // function test_addLiquidity_invalidAmount() public {
    //     vm.startPrank(owner);

    //     uint256 tokenAAmount = 1000e18;
    //     uint256 minLaunchReserveAa = 500e18;
    //     uint256 minLaunchReserveDd = 50e18;
    //     uint256 initialDToMintt = 50e18;

    //     tokenA.approve(address(router), tokenAAmount);
    //     uint256 balanceBefore = tokenA.balanceOf(owner);
    //     router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

    //     vm.expectRevert(IRouterErrors.InvalidAmount.selector);

    //     uint256 amountALiquidity = 0;

    //     router.addLiquidity(address(tokenA), amountALiquidity);

    //     vm.stopPrank();
    // }

    // ------------ REMOVE LIQUIDITY TEST ------------- //
    function test_removeLiquidity_success() public {
        vm.startPrank(owner);

        uint256 tokenAAmount = 1000e18;
        uint256 minLaunchReserveAa = 500e18;
        uint256 minLaunchReserveDd = 50e18;
        uint256 initialDToMintt = 50e18;

        tokenA.approve(address(router), tokenAAmount);
        uint256 balanceBefore = tokenA.balanceOf(owner);
        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

        (
        uint256 reserveDBefore,
        uint256 poolOwnershipUnitsTotalBefore,
        uint256 reserveABefore,
        uint256 minLaunchReserveABefore,
        uint256 minLaunchReserveDBefore,
        uint256 initialDToMintBefore,
        uint256 poolFeeCollectedBefore,
        bool initializedB
        ) = pool.poolInfo(address(tokenA));


        uint256 userLpAmount = pool.userLpUnitInfo(owner, address(tokenA));
        uint256 assetToTransfer = poolLogic.calculateAssetTransfer(userLpAmount, reserveABefore, poolOwnershipUnitsTotalBefore);
        uint256 dToDeduct = poolLogic.calculateDToDeduct(userLpAmount, reserveDBefore, poolOwnershipUnitsTotalBefore);

        router.removeLiquidity(address(tokenA), userLpAmount);

        (
        uint256 reserveDAfter,
        uint256 poolOwnershipUnitsTotalAfter,
        uint256 reserveAAfter,
        uint256 minLaunchReserveAAfter, //unchanged
        uint256 minLaunchReserveDAfter, //uncahnged
        uint256 initialDToMintAfter, //unchanged
        uint256 poolFeeCollectedAfter, //unchanged
        bool initializedd //unchanged
        ) = pool.poolInfo(address(tokenA));


        uint256 userLpUnitsAfter = pool.userLpUnitInfo(address(tokenA), owner);
        uint256 balanceAfter = tokenA.balanceOf(owner);

        console.log("%s", balanceBefore);
        console.log("%s", assetToTransfer);
        console.log("%s", balanceAfter);

        assertEq(balanceAfter, balanceBefore+assetToTransfer);
        assertEq(reserveDAfter, reserveDBefore-dToDeduct);
        assertEq(reserveAAfter, reserveABefore-assetToTransfer);
        assertEq(poolOwnershipUnitsTotalAfter, poolOwnershipUnitsTotalBefore - userLpAmount);

    }

    function test_removeLiquidity_invalidToken() public {
        vm.startPrank(owner);

        vm.expectRevert(IRouterErrors.InvalidPool.selector);

        router.removeLiquidity(address(tokenB), 1);

        vm.stopPrank();
    }

    function test_removeLiquidity_invalidAmount() public {
        vm.startPrank(owner);

        uint256 tokenAAmount = 1000e18;
        uint256 minLaunchReserveAa = 500e18;
        uint256 minLaunchReserveDd = 50e18;
        uint256 initialDToMintt = 50e18;

        tokenA.approve(address(router), tokenAAmount);

        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

        vm.expectRevert(IRouterErrors.InvalidAmount.selector);

        uint256 lpUnits = 0;

        router.removeLiquidity(address(tokenA), lpUnits);

        vm.stopPrank();
    }
}