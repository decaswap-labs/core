// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Pool.sol";
import "../src/PoolLogic.sol";
import "../src/MockERC20.sol"; // Mock token for testing

contract PoolTest is Test {
    Pool public pool;
    PoolLogic poolLogic;
    MockERC20 public token;
    address public vault = address(1);
    address public router = address(2);
    address public user = address(4);
    address public nonAuthorized = address(5);

    function setUp() public {
        token = new MockERC20("Mock Token", "MTK", 18);
        poolLogic = new PoolLogic();
        pool = new Pool(vault, router, address(poolLogic));
        vm.prank(user);
        token.mint(user, 1000 * 1e18);
        token.approve(address(pool), 1000 * 1e18);
    }

    // Test case for adding liquidity
    function testAddLiquidity() public {
        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 minLaunchReserveA,
            uint256 minLaunchReserveD,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            address tokenAddress
        ) = pool.poolInfo(address(token));

        uint256 initialReserveA = reserveA;
        uint256 initialOwnershipUnits = poolOwnershipUnitsTotal;

        assertEq(initialReserveA, 0);
        assertEq(initialOwnershipUnits, 0);

        vm.prank(router); // Use router address to add liquidity
        pool.add(user, address(token), 100 * 1e18);


        (reserveD, poolOwnershipUnitsTotal,,,,,,) = pool.poolInfo(address(token));

        assertGt(reserveD, initialReserveA, "ReserveA should increase");
        assertGt(poolOwnershipUnitsTotal, initialOwnershipUnits, "Pool ownership units should increase");
    }

    // Test case for removing liquidity
    function testRemoveLiquidity() public {
        (
            uint256 reserveD,
            uint256 poolOwnershipUnitsTotal,
            uint256 reserveA,
            uint256 minLaunchReserveA,
            uint256 minLaunchReserveD,
            uint256 initialDToMint,
            uint256 poolFeeCollected,
            address tokenAddress
        ) = pool.poolInfo(address(token));

        uint256 amountToAdd = 100 * 1e18;
        uint256 amountToRemove = 5 * 1e17;

        // Add liquidity first using the router address
        vm.prank(router);
        pool.add(user, address(token), amountToAdd);

        uint256 initialBalance = token.balanceOf(user);
        uint256 lpUnits = pool.userLpUnitInfo(user, address(token));

        // Ensure there's enough liquidity to remove
        assertGe(lpUnits, amountToRemove, "Not enough liquidity to remove");

<<<<<<< Updated upstream
        (reserveD, poolOwnershipUnitsTotal, reserveA,,,) = pool.poolInfo(address(token));
=======
        (reserveD, poolOwnershipUnitsTotal, reserveA,,,,,) = pool.poolInfo(address(token));
>>>>>>> Stashed changes

        uint256 assetToTransfer = poolLogic.calculateAssetTransfer(amountToRemove, reserveA, poolOwnershipUnitsTotal);

        // Remove liquidity
        vm.prank(router); // Use router address to remove liquidity
        pool.remove(user, address(token), assetToTransfer);

        uint256 finalBalance = token.balanceOf(user);
        uint256 lpUnitsAfter = pool.userLpUnitInfo(user, address(token));

        // Assertions to ensure that the removal was successful

        // assertEq(finalBalance, initialBalance, "Should be equal");
        assertLt(lpUnitsAfter, lpUnits, "LP units should decrease");

        // Additional check to ensure that balance doesn't underflow
        assertGe(lpUnitsAfter, 0, "LP units should not be negative");
    }

    // Failure case: Add liquidity from non-authorized address
    function testAddLiquidityNonAuthorized() public {
        vm.prank(nonAuthorized); // Use a non-authorized address
        vm.expectRevert();
        pool.add(user, address(token), 100 * 1e18);
    }

    // Failure case: Remove liquidity without sufficient LP units
    function testRemoveLiquidityInsufficientLP() public {
        uint256 amountToAdd = 100 * 1e18;
        uint256 amountToRemove = 1 * 1e18;

        // Add liquidity first
        vm.prank(router);
        pool.add(user, address(token), amountToAdd);

        // Try to remove more liquidity than the user has LP units
        vm.prank(router);
        vm.expectRevert();
        pool.remove(user, address(token), amountToRemove * 2); // Attempt to remove double the amount
    }

    // Failure case: Remove liquidity from non-authorized address
    function testRemoveLiquidityNonAuthorized() public {
        uint256 amountToAdd = 100 * 1e18;
        uint256 amountToRemove = 5 * 1e17;

        // Add liquidity first
        vm.prank(router);
        pool.add(user, address(token), amountToAdd);

        vm.prank(nonAuthorized); // Use a non-authorized address
        vm.expectRevert();
        pool.remove(user, address(token), amountToRemove);
    }

    // Failure case: Remove liquidity with insufficient reserves
    function testRemoveLiquidityInsufficientReserves() public {
        uint256 amountToAdd = 100 * 1e18;
        uint256 amountToRemove = 5 * 1e17;

        // Add liquidity first
        vm.prank(router);
        pool.add(user, address(token), amountToAdd);

        uint256 lpUnits = pool.userLpUnitInfo(user, address(token));
        // Remove more liquidity than the pool can handle
        uint256 excessAmount = amountToRemove * 10; // Way more than what the pool can handle

        vm.prank(router);

        vm.expectRevert();

        pool.remove(user, address(token), excessAmount);
    }
}
