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

    // ------------------------ Test Cases ------------------------

    function test_createPool_success() public {
        vm.startPrank(owner);

        uint256 tokenAAmount = 1000e18;
        uint256 minLaunchReserveAa = 500e18;
        uint256 minLaunchReserveDd = 50e18;
        uint256 initialDToMintt = 50e18;

        tokenA.approve(address(router), tokenAAmount);

        uint256 balanceBefore = tokenA.balanceOf(owner);

        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

        (
        uint256 reserveD,
        uint256 poolOwnershipUnitsTotal,
        uint256 reserveA,
        uint256 minLaunchReserveA,
        uint256 minLaunchReserveD,
        uint256 initialDToMint,
        uint256 poolFeeCollected,
        bool initialized
        ) = pool.poolInfo(address(tokenA));

        uint256 balanceAfter = tokenA.balanceOf(owner);

        console.log("%s:%s", reserveA);


        assertEq(reserveA, tokenAAmount);
        assertEq(reserveD, initialDToMintt);
        assertEq(minLaunchReserveA, minLaunchReserveAa);
        assertEq(minLaunchReserveD, minLaunchReserveDd);
        assertEq(balanceAfter, balanceBefore-tokenAAmount);

        vm.stopPrank();
    }


//    //Test: Successfully create a pool
//     function testCreatePool_Success() public {
//         vm.startPrank(user);
//         tokenA.approve(address(router), 100 * 1e18);
//         router.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
//         vm.stopPrank();
//         (
//         uint256 reserveD,
//         uint256 poolOwnershipUnitsTotal,
//         uint256 reserveA,
//         uint256 minLaunchReserveA,
//         uint256 minLaunchReserveD,
//         uint256 initialDToMint,
//         uint256 poolFeeCollected,
//         bool initialized
//         ) = pool.poolInfo(address(tokenA));

//         assertEq(reserveD, 10 * 1e18);
//         assertEq(poolOwnershipUnitsTotal, 100 * 1e18);
//         assertEq(initialized, true);
//         assertEq(tokenA.balanceOf(address(pool)),100 * 1e18);

//     }

    // // Test: Creating a pool that already exists
    // function testCreatePool_PoolAlreadyExists() public {
    //     vm.startPrank(user);
    //     router.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);

    //     vm.expectRevert(IRouterErrors.InvalidPool.selector);
    //     router.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
    //     vm.stopPrank();
    // }

    // // Test: Creating a pool from an unauthorized address
    // function testCreatePoolFromRouter_UnauthorizedAddress() public {
    //     vm.startPrank(nonAuthorized);
    //     vm.expectRevert(abi.encodeWithSelector(getOwnableUnauthorizedAccountSelector(),nonAuthorized));
    //     router.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
    //     vm.stopPrank();
    // }

    // function testCreatePoolFromPool_UnauthorizedAddress() public {
    //     vm.startPrank(nonAuthorized);
    //     vm.expectRevert(abi.encodeWithSelector(IPoolErrors.NotPoolLogic.selector,nonAuthorized));
    //     pool.createPool("0x");
    //     vm.stopPrank();
    // }

    // // Test: Creating pool with invalid token address
    // function testCreatePool_InvalidTokenAddress() public {
    //     vm.startPrank(user);
    //     vm.expectRevert(); // transferFrom on 0 address will revert
    //     router.createPool(address(0), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
    //     vm.stopPrank();
    // }



}