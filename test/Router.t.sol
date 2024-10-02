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

        uint256 userLpUnits = pool.userLpUnitInfo(address(tokenA), owner);

        uint256 balanceAfter = tokenA.balanceOf(owner);

        // assertEq(reserveA, tokenAAmount);
        assertEq(reserveD, initialDToMintt);
        // assertEq(minLaunchReserveA, minLaunchReserveAa);
        assertEq(minLaunchReserveD, minLaunchReserveDd);
        assertEq(balanceAfter, balanceBefore-tokenAAmount);
        assertEq(userLpUnits, poolOwnershipUnitsTotal);

        vm.stopPrank();
    }


    // Test: Creating a pool that already exists
    function test_createPool_poolAlreadyExists() public {
        vm.startPrank(owner);

        uint256 tokenAAmount = 1000e18;
        uint256 minLaunchReserveAa = 500e18;
        uint256 minLaunchReserveDd = 50e18;
        uint256 initialDToMintt = 50e18;

        tokenA.approve(address(router), tokenAAmount);

        uint256 balanceBefore = tokenA.balanceOf(owner);

        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);

        vm.expectRevert(IRouterErrors.InvalidPool.selector);

        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);


        vm.stopPrank();
    }

    // // Test: Creating a pool from an unauthorized address
    function test_createPoo_unauthorizedAddress() public {
        vm.startPrank(nonAuthorized);
        vm.expectRevert(abi.encodeWithSelector(getOwnableUnauthorizedAccountSelector(),nonAuthorized));
        uint256 tokenAAmount = 1000e18;
        uint256 minLaunchReserveAa = 500e18;
        uint256 minLaunchReserveDd = 50e18;
        uint256 initialDToMintt = 50e18;

        tokenA.approve(address(router), tokenAAmount);

        uint256 balanceBefore = tokenA.balanceOf(owner);

        router.createPool(address(tokenA), tokenAAmount, minLaunchReserveAa, minLaunchReserveDd, initialDToMintt);        vm.stopPrank();
    }
}