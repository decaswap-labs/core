// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Pool.sol";
import "../src/PoolLogic.sol";
import "../src/MockERC20.sol"; // Mock token for testing
contract PoolTest is Test {
    Pool public pool;
    PoolLogic poolLogic;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    address public vault = address(1);
    address public router = address(2);
    address public user = address(4);
    address public nonAuthorized = address(5);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        poolLogic = new PoolLogic();
        vm.prank(user);
        pool = new Pool(vault, router, address(poolLogic));
        // Mint tokens for liquidity adding
        tokenA.mint(user, 1000 ether);
        tokenB.mint(user, 1000 ether);

        // Approve pool contract to spend tokens
        vm.prank(user);
        tokenA.approve(address(pool), 1000 ether);
        tokenB.approve(address(pool), 1000 ether);
    }

    // ------------------------ Test Cases ------------------------


   // Test: Successfully create a pool
    function testCreatePool_Success() public {
        vm.prank(user);

        pool.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);

        (
        uint256 reserveD,
        uint256 poolOwnershipUnitsTotal,
        uint256 reserveA,
        uint256 minLaunchReserveA,
        uint256 minLaunchReserveD,
        uint256 initialDToMint,
        uint256 poolFeeCollected,
        address tokenAddress
        ) = pool.poolInfo(address(tokenA));

        assertEq(reserveD, 10 * 1e18);
        assertEq(poolOwnershipUnitsTotal, 100 * 1e18);

    }

    // Test: Creating a pool that already exists
    function testCreatePool_PoolAlreadyExists() public {
        vm.prank(user);
        pool.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);

        vm.expectRevert();
        pool.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
    }

    // Test: Creating a pool from an unauthorized address
    function testCreatePool_UnauthorizedAddress() public {
        vm.prank(nonAuthorized);
        vm.expectRevert();
        pool.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
    }

    // Test: Creating pool with invalid token address
    function testCreatePool_InvalidTokenAddress() public {
        vm.prank(user);
        vm.expectRevert();
        pool.createPool(address(0), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
    }

    // Test: Successfully add liquidity
    function testAddLiquidity() public {
        vm.prank(user);
        pool.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
        (
        uint256 reserveD,
        uint256 poolOwnershipUnitsTotal,
        uint256 reserveA,
        uint256 minLaunchReserveA,
        uint256 minLaunchReserveD,
        uint256 initialDToMint,
        uint256 poolFeeCollected,
        address tokenAddress
        ) = pool.poolInfo(address(tokenA));

        console.log("Before ReserveA: ",reserveA);
        console.log("Before ReserveD: ",reserveD);
        console.log("After poolOwnershipUnitsTotal: ",poolOwnershipUnitsTotal);

        uint256 initialReserveD = reserveD;
        uint256 initialOwnershipUnits = poolOwnershipUnitsTotal;

        assertEq(initialReserveD, 10 * 1e18);
        assertEq(initialOwnershipUnits, 100 * 1e18);

        vm.prank(router); // Use router address to add liquidity
        pool.add(user, address(tokenA), 100 * 1e18);

        (reserveD, poolOwnershipUnitsTotal, reserveA, , , , ,) = pool.poolInfo(address(tokenA));

        console.log("After ReserveA: ",reserveA);
        console.log("After ReserveD: ",reserveD);
        console.log("After poolOwnershipUnitsTotal: ",poolOwnershipUnitsTotal);

        assertGt(reserveD, initialReserveD, "ReserveA should increase");
        assertGt(poolOwnershipUnitsTotal, initialOwnershipUnits, "Pool ownership units should increase");
    }

    // //Test: Adding liquidity by unauthorized addresses
    function testadd_Unauthorized() public {
        vm.prank(user);
        pool.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
        vm.expectRevert();
        pool.add(user, address(tokenA), 100 * 1e18);
    }

    // // Test: Adding liquidity to a pool that doesn't exist
    function testadd_NonExistentPool() public {
        vm.prank(user);
        pool.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
        vm.prank(router);
        vm.expectRevert();
        pool.add(user, address(0xDEADBEEF), 100 * 1e18);
    }

    // // Test: Successfully remove liquidity
    function testRemoveLiquidity_Success() public {
        vm.prank(user);
        pool.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);

        vm.prank(router);
        pool.add(user, address(tokenA), 100 * 1e18);

        uint256 reserveA;
        uint256 poolOwnershipUnitsTotal;
        uint256 userlpunit = pool.userLpUnitInfo(user,address(tokenA));

        (, poolOwnershipUnitsTotal, reserveA, , , , ,) = pool.poolInfo(address(tokenA));

        console.log("poolOwnershipUnitsTotal: ",poolOwnershipUnitsTotal);
        console.log("userLpUnit: ",userlpunit);

        uint256 initialReserveA = reserveA;

        vm.prank(router);
        pool.remove(user, address(tokenA), 5 * 1e18);

        (, , reserveA, , , , ,) = pool.poolInfo(address(tokenA));

        uint256 finalReserveA = reserveA; 

        console.log("initialReserveA: ",initialReserveA);       
        console.log("finalReserveA: ",finalReserveA);

        assertGt(initialReserveA, finalReserveA);
    }

    // // Test: Remove liquidity with insufficient LP units
    function testRemoveLiquidity_InsufficientLP() public {
        vm.prank(user);
        pool.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);

        vm.prank(router);
        pool.add(user, address(tokenA), 100 * 1e18);

        uint256 userlpunit = pool.userLpUnitInfo(user,address(tokenA));

        console.log("userLpUnit: ",userlpunit);

        vm.prank(router);
        vm.expectRevert();
        pool.remove(user, address(tokenA), 16 * 1e18);

    }

    // // Test: Remove liquidity from a non-authorized address
    function testRemoveLiquidity_UnauthorizedAddress() public {
        vm.prank(user);
        pool.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);

        vm.prank(router);
        pool.add(user, address(tokenA), 100 * 1e18);

        vm.prank(user);
        vm.expectRevert();
        pool.remove(user, address(tokenA), 5 * 1e18);
    }

    // // Test: Successful stream swap execution
    function testExecuteSwap_Success() public {
        vm.prank(user);
        pool.createPool(address(tokenA), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);
        vm.prank(user);
        pool.createPool(address(tokenB), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);

        vm.prank(router);
        pool.add(user, address(tokenA), 10 * 1e18);
        vm.prank(router);
        pool.add(user, address(tokenB), 10 * 1e18);

        (uint256 A_reserveD, ,uint256 A_reserveA, uint256 A_minLaunchReserveA, uint256 A_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenA));
        (uint256 B_reserveD, ,uint256 B_reserveA, uint256 B_minLaunchReserveB, uint256 B_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenB));

        uint256 Before_A_reserveD = A_reserveD;
        uint256 Before_A_reserveA = A_reserveA;
        uint256 Before_B_reserveD = B_reserveD;
        uint256 Before_B_reserveA = B_reserveA;        

        bytes32 id = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));


        vm.prank(router);
        pool.executeSwap(user,10 * 1e18,1,address(tokenA),address(tokenB)); //A->B
        
      Queue.QueueStruct memory queue = pool.getStreamStruct(id);
  

       uint256 streamsCountAfter = queue.data[queue.front].streamsCount;    

       console.log("streamsCountAfter",streamsCountAfter);

        ( A_reserveD, , A_reserveA,  A_minLaunchReserveA,  A_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenA));
        ( B_reserveD, , B_reserveA,  B_minLaunchReserveB,  B_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenB));

        uint256 After_A_reserveD = A_reserveD;
        uint256 After_A_reserveA = A_reserveA;
        uint256 After_B_reserveD = B_reserveD;
        uint256 After_B_reserveA = B_reserveA; 

        assertLt(After_A_reserveD, Before_A_reserveD);
        assertGt(After_B_reserveD, Before_B_reserveD);
        assertGt(After_A_reserveA, Before_A_reserveA);
        assertLt(After_B_reserveA, Before_B_reserveA);

    }

    // Test: Pending queue swap insertion
    //  function testPendingQueueSwap() public {
    //     vm.prank(user);
    //     pool.createPool(address(tokenA), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);
    //     vm.prank(user);
    //     pool.createPool(address(tokenB), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);

    //     vm.prank(router);
    //     pool.executeSwap(user,10 * 1e18,1,address(tokenA),address(tokenB)); //A->B

    //     vm.prank(router);
    //     pool.executeSwap(user,10 * 1e18,2,address(tokenA),address(tokenB)); //A->B

    //     bytes32 id = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));
    //     Queue.QueueStruct memory queue = pool.getPendingStruct(id);

    //     uint256 streamsCount = queue.data[queue.front].streamsCount;    

    //    console.log("streamsCount",streamsCount);

    // }

    // // Test: Cancellation of a swap in the stream queue
    function testCancelSwap() public {
        vm.prank(user);
        pool.createPool(address(tokenA), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);
        vm.prank(user);
        pool.createPool(address(tokenB), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);

        vm.prank(router);
        pool.add(user, address(tokenA), 10 * 1e18);
        vm.prank(router);
        pool.add(user, address(tokenB), 10 * 1e18);

        vm.prank(router);
        pool.executeSwap(user,10 * 1e18,1,address(tokenA),address(tokenB)); //A->B

        (uint256 A_reserveD, ,uint256 A_reserveA, uint256 A_minLaunchReserveA, uint256 A_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenA));
        (uint256 B_reserveD, ,uint256 B_reserveA, uint256 B_minLaunchReserveB, uint256 B_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenB));

        
         bytes32 id = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));
        
        Queue.QueueStruct memory queue = pool.getStreamStruct(id);

        uint256 streamsCountBefore = queue.data[queue.front].streamsCount;    

       console.log("streamsCountBefore",streamsCountBefore);
        
       uint256 swapID = queue.data[queue.front].swapID;


        vm.prank(user);
        pool.cancelSwap(swapID,id,true);

        ( A_reserveD, , A_reserveA,  A_minLaunchReserveA,  A_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenA));
        ( B_reserveD, , B_reserveA,  B_minLaunchReserveB,  B_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenB));

        console.log("A_reserveA",A_reserveA);
        console.log("A_reserveD",A_reserveD);
        console.log("B_reserveA",B_reserveA);
        console.log("B_reserveA",B_reserveA);

        //     Queue.QueueStruct memory queue1 = pool.getStreamStruct(id);
        //    uint256 streamsCountAfter = queue1.data[queue1.front].streamsCount;    

        //    console.log("streamsCountAfter",streamsCountAfter);

        //    uint256 swapAmountRemaining = queue.data[queue.front].swapAmountRemaining;    

        //    console.log("swapAmountRemaining",swapAmountRemaining);

      //  assertEq(streamsCountAfter, 10);
      //  assertEq(swapAmountRemaining, 0);
    }

    // Test: Swap between two tokens in opposite directions
    function testSwapOppositeDirections() public {
        vm.prank(user);
        pool.createPool(address(tokenA), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);
        vm.prank(user);
        pool.createPool(address(tokenB), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);

        vm.prank(router);
        pool.add(user, address(tokenA), 10 * 1e18);
        vm.prank(router);
        pool.add(user, address(tokenB), 10 * 1e18);

        vm.prank(router);
        pool.executeSwap(user,10 * 1e18,1,address(tokenA),address(tokenB)); //A->B

    //    vm.expectEmit(true, true, true, true);
    //    emit AmountOut(10 * 1e18);

        vm.prank(router);
        pool.executeSwap(user,10 * 1e18,1,address(tokenB),address(tokenA)); //B->A
 
        console.log(tokenA.balanceOf(address(pool)));
        console.log(tokenB.balanceOf(address(pool)));

       // assertEq(tokenA.balanceOf(user), 500 ether, "Opposite direction swap failed.");
    }

    // // Test: Failing stream swap execution (insufficient liquidity)
    // function testFailExecuteSwap_InsufficientLiquidity() public {
    //     vm.prank(user);
    //     pool.createPool(address(tokenA), address(tokenB));

    //     vm.expectRevert("Insufficient liquidity");
    //     pool.executeSwap(address(tokenA), address(tokenB), 1000 ether);
    // }

    // // Test: Failing pending queue swap insertion (invalid price)
    // function testFailPendingQueueSwap_InvalidPrice() public {
    //     vm.prank(user);
    //     pool.createPool(address(tokenA), address(tokenB));

    //     vm.expectRevert("Invalid price");
    //     pool.executeSwap(address(tokenA), address(tokenB), 100 ether, 0);
    // }

    // // Test: Failing swap between two tokens (mismatched amounts)
    // function testFailSwap_MismatchedAmounts() public {
    //     vm.prank(user);
    //     pool.createPool(address(tokenA), address(tokenB));

    //     vm.expectRevert("Mismatched amounts");
    //     pool.executeSwap(address(tokenA), address(tokenB), 100 ether, 200 ether);
    // }
}
