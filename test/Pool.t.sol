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
    address public vault = address(1);
    Router public router;
    address public user = address(4);
    address public nonAuthorized = address(5);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
        poolLogic = new PoolLogic(user,address(0)); // setting zero address for poolAddress as not deployed yet.
        vm.prank(user);
        pool = new Pool(vault, address(router), address(poolLogic));
        // Mint tokens for liquidity adding
        tokenA.mint(user, 1000 ether);
        tokenB.mint(user, 1000 ether);

        // Approve pool contract to spend tokens
        vm.prank(user);
        tokenA.approve(address(pool), 1000 ether);
        tokenB.approve(address(pool), 1000 ether);

        router = new Router(user,address(pool));
        vm.startPrank(user);
        pool.updateRouterAddress(address(router));
        poolLogic.updatePoolAddress(address(pool)); // Setting poolAddress (kind of initialization)

    }

    // ------------------------ Test Cases ------------------------


   //Test: Successfully create a pool
    function testCreatePool_Success() public {
        vm.startPrank(user);
        tokenA.approve(address(router), 100 * 1e18);
        router.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
        vm.stopPrank();
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

        assertEq(reserveD, 10 * 1e18);
        assertEq(poolOwnershipUnitsTotal, 100 * 1e18);
        assertEq(initialized, true);
        assertEq(tokenA.balanceOf(address(pool)),100 * 1e18);

    }

    // Test: Creating a pool that already exists
    function testCreatePool_PoolAlreadyExists() public {
        vm.startPrank(user);
        router.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);

        vm.expectRevert(IRouterErrors.InvalidPool.selector);
        router.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
        vm.stopPrank();
    }

    // Test: Creating a pool from an unauthorized address
    function testCreatePoolFromRouter_UnauthorizedAddress() public {
        vm.startPrank(nonAuthorized);
        vm.expectRevert(abi.encodeWithSelector(getOwnableUnauthorizedAccountSelector(),nonAuthorized));
        router.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
        vm.stopPrank();
    }

    function testCreatePoolFromPool_UnauthorizedAddress() public {
        vm.startPrank(nonAuthorized);
        vm.expectRevert(abi.encodeWithSelector(IPoolErrors.NotPoolLogic.selector,nonAuthorized));
        pool.createPool("0x");
        vm.stopPrank();
    }

    // Test: Creating pool with invalid token address
    function testCreatePool_InvalidTokenAddress() public {
        vm.startPrank(user);
        vm.expectRevert(); // transferFrom on 0 address will revert
        router.createPool(address(0), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
        vm.stopPrank();
    }

    // Test: Successfully add liquidity
    function testAddLiquidity() public {
        vm.startPrank(user);
        router.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
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
        
        vm.stopPrank();

        console.log("Before ReserveA: ",reserveA);
        console.log("Before ReserveD: ",reserveD);
        console.log("After poolOwnershipUnitsTotal: ",poolOwnershipUnitsTotal);

        uint256 initialReserveD = reserveD;
        uint256 initialOwnershipUnits = poolOwnershipUnitsTotal;

        assertEq(initialReserveD, 10 * 1e18);
        assertEq(initialOwnershipUnits, 100 * 1e18);
        assertEq(tokenA.balanceOf(address(pool)),100 * 1e18);   

        uint beforeTokenABalance = tokenA.balanceOf(address(pool));
        vm.startPrank(user);
        router.addLiquidity(address(tokenA), 100 * 1e18);
        vm.stopPrank();

        (reserveD, poolOwnershipUnitsTotal, reserveA, , , , ,) = pool.poolInfo(address(tokenA));

        console.log("After ReserveA: ",reserveA);
        console.log("After ReserveD: ",reserveD);
        console.log("After poolOwnershipUnitsTotal: ",poolOwnershipUnitsTotal);

        assertGt(reserveD, initialReserveD, "ReserveA should increase");
        assertGt(poolOwnershipUnitsTotal, initialOwnershipUnits, "Pool ownership units should increase");
        assertEq(tokenA.balanceOf(address(pool)),beforeTokenABalance + 100 * 1e18);
    }

    // Test: Adding 0 amount liquidity
    function testadd_InvalidAmount() public {
        vm.startPrank(user);
        router.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
        vm.expectRevert(IRouterErrors.InvalidAmount.selector);
        router.addLiquidity(address(tokenA),0); // 0 amount
        vm.stopPrank();
    }

    //Test: Adding liquidity in POOL by unauthorized addresses
    function testadd_Unauthorized() public {
        vm.startPrank(user);
        router.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
        vm.stopPrank();
        vm.startPrank(nonAuthorized);
        vm.expectRevert(abi.encodeWithSelector(IPoolErrors.NotPoolLogic.selector,nonAuthorized));
        pool.addLiquidity("0x");
        vm.stopPrank();
    }

    // Test: Adding liquidity to a pool that doesn't exist
    function testadd_NonExistentPool() public {
        vm.startPrank(user);
        router.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);
        vm.expectRevert(IRouterErrors.InvalidPool.selector);
        router.addLiquidity(address(0xDEADBEEF), 100 * 1e18);
        vm.stopPrank();
    }

    // // Test: Successfully remove liquidity
    // function testRemoveLiquidity_Success() public {
    //     vm.prank(user);
    //     pool.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);

    //     vm.prank(router);
    //     pool.add(user, address(tokenA), 100 * 1e18);

    //     uint256 reserveA;
    //     uint256 poolOwnershipUnitsTotal;
    //     uint256 userlpunit = pool.userLpUnitInfo(user,address(tokenA));

    //     (, poolOwnershipUnitsTotal, reserveA, , , , ,) = pool.poolInfo(address(tokenA));

    //     console.log("poolOwnershipUnitsTotal: ",poolOwnershipUnitsTotal);
    //     console.log("userLpUnit: ",userlpunit);

    //     uint256 initialReserveA = reserveA;

    //     vm.prank(router);
    //     pool.remove(user, address(tokenA), 5 * 1e18);

    //     (, , reserveA, , , , ,) = pool.poolInfo(address(tokenA));

    //     uint256 finalReserveA = reserveA; 

    //     console.log("initialReserveA: ",initialReserveA);       
    //     console.log("finalReserveA: ",finalReserveA);

    //     assertGt(initialReserveA, finalReserveA);
    // }

    // // // Test: Remove liquidity with insufficient LP units
    // function testRemoveLiquidity_InsufficientLP() public {
    //     vm.prank(user);
    //     pool.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);

    //     vm.prank(router);
    //     pool.add(user, address(tokenA), 100 * 1e18);

    //     uint256 userlpunit = pool.userLpUnitInfo(user,address(tokenA));

    //     console.log("userLpUnit: ",userlpunit);

    //     vm.prank(router);
    //     vm.expectRevert();
    //     pool.remove(user, address(tokenA), 16 * 1e18);

    // }

    // // // Test: Remove liquidity from a non-authorized address
    // function testRemoveLiquidity_UnauthorizedAddress() public {
    //     vm.prank(user);
    //     pool.createPool(address(tokenA), 100 * 1e18, 100 * 1e18, 100 * 1e18, 10 * 1e18);

    //     vm.prank(router);
    //     pool.add(user, address(tokenA), 100 * 1e18);

    //     vm.prank(user);
    //     vm.expectRevert();
    //     pool.remove(user, address(tokenA), 5 * 1e18);
    // }

    // // // Test: Successful stream swap execution
    // function testExecuteSwap_Success() public {
    //     vm.prank(user);
    //     pool.createPool(address(tokenA), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);
    //     vm.prank(user);
    //     pool.createPool(address(tokenB), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);

    //     vm.prank(router);
    //     pool.add(user, address(tokenA), 10 * 1e18);
    //     vm.prank(router);
    //     pool.add(user, address(tokenB), 10 * 1e18);

    //     (uint256 A_reserveD, ,uint256 A_reserveA, uint256 A_minLaunchReserveA, uint256 A_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenA));
    //     (uint256 B_reserveD, ,uint256 B_reserveA, uint256 B_minLaunchReserveB, uint256 B_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenB));

    //     uint256 Before_A_reserveD = A_reserveD;
    //     uint256 Before_A_reserveA = A_reserveA;
    //     uint256 Before_B_reserveD = B_reserveD;
    //     uint256 Before_B_reserveA = B_reserveA;        

    //     bytes32 id = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));


    //     vm.prank(router);
    //     pool.executeSwap(user,10 * 1e18,1,address(tokenA),address(tokenB)); //A->B
        
    //   Queue.QueueStruct memory queue = pool.getStreamStruct(id);
  

    //    uint256 streamsCountAfter = queue.data[queue.front].streamsCount;    

    //    console.log("streamsCountAfter",streamsCountAfter);

    //     ( A_reserveD, , A_reserveA,  A_minLaunchReserveA,  A_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenA));
    //     ( B_reserveD, , B_reserveA,  B_minLaunchReserveB,  B_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenB));

    //     uint256 After_A_reserveD = A_reserveD;
    //     uint256 After_A_reserveA = A_reserveA;
    //     uint256 After_B_reserveD = B_reserveD;
    //     uint256 After_B_reserveA = B_reserveA; 

    //     assertLt(After_A_reserveD, Before_A_reserveD);
    //     assertGt(After_B_reserveD, Before_B_reserveD);
    //     assertGt(After_A_reserveA, Before_A_reserveA);
    //     assertLt(After_B_reserveA, Before_B_reserveA);

    // }

    // // Test: Pending queue swap insertion
    //  function testPendingQueueSwap() public {
    //     vm.prank(user);
    //     pool.createPool(address(tokenA), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);
    //             (
    //     uint256 A_poolOwnershipUnitsTotal,
    //     uint256 A_reserveD,
    //     uint256 A_reserveA,
    //     uint256 A_minLaunchReserveA,
    //     uint256 A_minLaunchReserveD,
    //     uint256 A_initialDToMint,
    //     uint256 A_poolFeeCollected,
    //     bool A_initlialized
    //     ) = pool.poolInfo(address(tokenA));

    //     vm.prank(user);
    //     pool.createPool(address(tokenB), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);
    //     (
    //     uint256 B_reserveD,
    //     uint256 B_poolOwnershipUnitsTotal,
    //     uint256 B_reserveA,
    //     uint256 B_minLaunchReserveA,
    //     uint256 B_minLaunchReserveD,
    //     uint256 B_initialDToMint,
    //     uint256 B_poolFeeCollected,
    //     bool B_initlialized
    //     ) = pool.poolInfo(address(tokenB));

    //     uint256 before_Current_price = (A_reserveA * 1e18 / B_reserveA);
    //     console.log("before_Current_price: ",before_Current_price);

    //     vm.prank(router);
    //     pool.executeSwap(user,10 * 1e18,1e18,address(tokenA),address(tokenB)); //A->B

    //      (
    //     A_poolOwnershipUnitsTotal,
    //     A_reserveD,
    //     A_reserveA,
    //     A_minLaunchReserveA,
    //     A_minLaunchReserveD,
    //     A_initialDToMint,
    //     A_poolFeeCollected,
    //     A_initlialized
    //     ) = pool.poolInfo(address(tokenA));

    //     (
    //     B_reserveD,
    //     B_poolOwnershipUnitsTotal,
    //     B_reserveA,
    //     B_minLaunchReserveA,
    //     B_minLaunchReserveD,
    //     B_initialDToMint,
    //     B_poolFeeCollected,
    //     B_initlialized
    //     ) = pool.poolInfo(address(tokenB));


    //     uint256 After_Current_price = (A_reserveA * 1e18 / B_reserveA);
    //     console.log("after_Current_price: ",After_Current_price);

    //     vm.prank(router);
    //     pool.executeSwap(user,10 * 1e18,1.02e18,address(tokenA),address(tokenB)); //A->B

    //    bytes32 id = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));

    //    Queue.QueueStruct memory queue = pool.getPendingStruct(id);   

    //    console.log("queue.data.length: ",queue.data.length);


    // }

    // // // Test: Cancellation of a swap in the stream queue
    // function testCancelSwap() public {
    //     vm.prank(user);
    //     pool.createPool(address(tokenA), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);
    //     vm.prank(user);
    //     pool.createPool(address(tokenB), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);

    //     vm.prank(router);
    //     pool.add(user, address(tokenA), 10 * 1e18);
    //     vm.prank(router);
    //     pool.add(user, address(tokenB), 10 * 1e18);

    //     vm.prank(router);
    //     pool.executeSwap(user,10 * 1e18,1,address(tokenA),address(tokenB)); //A->B

    //     (uint256 A_reserveD, ,uint256 A_reserveA, uint256 A_minLaunchReserveA, uint256 A_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenA));
    //     (uint256 B_reserveD, ,uint256 B_reserveA, uint256 B_minLaunchReserveB, uint256 B_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenB));

        
    //      bytes32 id = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));
        
    //     Queue.QueueStruct memory queue = pool.getStreamStruct(id);

    //     uint256 streamsCountBefore = queue.data[queue.front].streamsCount;    

    //    console.log("streamsCountBefore",streamsCountBefore);
        
    //    uint256 swapID = queue.data[queue.front].swapID;


    //     vm.prank(user);
    //     pool.cancelSwap(swapID,id,true);

    //     ( A_reserveD, , A_reserveA,  A_minLaunchReserveA,  A_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenA));
    //     ( B_reserveD, , B_reserveA,  B_minLaunchReserveB,  B_minLaunchReserveD, , ,) = pool.poolInfo(address(tokenB));

    //     console.log("A_reserveA",A_reserveA);
    //     console.log("A_reserveD",A_reserveD);
    //     console.log("B_reserveA",B_reserveA);
    //     console.log("B_reserveA",B_reserveA);

    //     //     Queue.QueueStruct memory queue1 = pool.getStreamStruct(id);
    //     //    uint256 streamsCountAfter = queue1.data[queue1.front].streamsCount;    

    //     //    console.log("streamsCountAfter",streamsCountAfter);

    //     //    uint256 swapAmountRemaining = queue.data[queue.front].swapAmountRemaining;    

    //     //    console.log("swapAmountRemaining",swapAmountRemaining);

    //   //  assertEq(streamsCountAfter, 10);
    //   //  assertEq(swapAmountRemaining, 0);
    // }

    // // Test: Swap between two tokens in opposite directions
    // function testSwapOppositeDirections() public {
    //     vm.prank(user);
    //     pool.createPool(address(tokenA), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);
    //     vm.prank(user);
    //     pool.createPool(address(tokenB), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);

    //     vm.prank(router);
    //     pool.add(user, address(tokenA), 10 * 1e18);
    //     vm.prank(router);
    //     pool.add(user, address(tokenB), 10 * 1e18);

    //     vm.prank(router);
    //     pool.executeSwap(user,10 * 1e18,1,address(tokenA),address(tokenB)); //A->B

    //     vm.prank(router);
    //     pool.executeSwap(user,10 * 1e18,1,address(tokenB),address(tokenA)); //B->A
 
    //     console.log(tokenA.balanceOf(address(pool)));
    //     console.log(tokenB.balanceOf(address(pool)));

    // }

    // //Test: Failing stream swap execution (insufficient liquidity)
    // // function testExecuteSwap_InsufficientLiquidity() public {
    // //     vm.prank(user);
    // //     pool.createPool(address(tokenA), 1 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);
    // //     vm.prank(user);
    // //     pool.createPool(address(tokenB), 1 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);

        
    // //     vm.prank(router);
    // //     vm.expectRevert();
    // //     pool.executeSwap(user, 1000e18,1e18,address(tokenA),address(tokenB)); //A->B
    // // }

    // //Test: Failing pending queue swap insertion (invalid price)
    // function testPendingQueueSwap_InvalidPrice() public {
    //     vm.prank(user);
    //     pool.createPool(address(tokenA), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);

    //     vm.prank(user);
    //     pool.createPool(address(tokenB), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);


    //     vm.prank(router);
    //     pool.executeSwap(user,10 * 1e18,1e18,address(tokenA),address(tokenB));

    //             (
    //     uint256 A_poolOwnershipUnitsTotal,
    //     uint256 A_reserveD,
    //     uint256 A_reserveA,
    //     uint256 A_minLaunchReserveA,
    //     uint256 A_minLaunchReserveD,
    //     uint256 A_initialDToMint,
    //     uint256 A_poolFeeCollected,
    //     bool A_initlialized
    //     ) = pool.poolInfo(address(tokenA));

    //     (
    //     uint256 B_reserveD,
    //     uint256 B_poolOwnershipUnitsTotal,
    //     uint256 B_reserveA,
    //     uint256 B_minLaunchReserveA,
    //     uint256 B_minLaunchReserveD,
    //     uint256 B_initialDToMint,
    //     uint256 B_poolFeeCollected,
    //     bool B_initlialized
    //     ) = pool.poolInfo(address(tokenB));

    //     uint256 before_Current_price = (A_reserveA * 1e18 / B_reserveA);
    //     console.log("before_Current_price: ",before_Current_price);

    //     vm.prank(router);
    //     pool.executeSwap(user,10 * 1e18,1009999999999999998,address(tokenA),address(tokenB));

    //    bytes32 id = keccak256(abi.encodePacked(address(tokenA), address(tokenB)));

    //    Queue.QueueStruct memory queue = pool.getPendingStruct(id);

    //    assertEq(queue.data.length, 0);

    // }

    //     function testDepositVault_Success() public {
    //     vm.prank(user);
    //     pool.createPool(address(tokenA), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);

    //     // Simulate the depositVault function
    //     vm.prank(router);
    //     pool.depositVault(user, 1e18, address(tokenA));

    //     // Check that the vault has been updated for the user
    //     (uint256 tokenAmount, uint256 dAmount) = pool.userVaultInfo(address(tokenA), user);

    //     console.log("tokenAmount: ",tokenAmount);
    //     console.log("dAmount: ",dAmount);

    //     assertEq(tokenAmount, 0);
    //     assertEq(dAmount, 9900990099009900); // Initially, the deposited D token amount should be zero
    // }

    // function testDepositInvalidToken() public {
           
    //         vm.prank(user);
    //         pool.createPool(address(tokenA), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);
    //         vm.expectRevert();
    //         vm.prank(router);  
    //         pool.depositVault(user, 1e18, address(0));

    // }

    //     function testWithdrawVaultSuccessful() public {

    //     vm.prank(user);
    //     pool.createPool(address(tokenA), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);

    //     // Simulate the depositVault function
    //     vm.prank(router);
    //     pool.depositVault(user, 1e18, address(tokenA));

    //     // Simulate the withdrawVault function
    //     vm.prank(router);
    //     pool.withdrawVault(user, 9900990099009900, address(tokenA));

    //     // Check that the vault has been updated for the user
    //     (uint256 tokenAmount, uint256 dAmount) = pool.userVaultInfo(address(tokenA), user);

    //     assertEq(tokenAmount, 0);
    //     assertEq(dAmount, 9900990099009900);
    // }


    // function testWithdrawVaultwithInsufficientAmount() public {

    //     vm.prank(user);
    //     pool.createPool(address(tokenA), 100 * 1e18, 1 * 1e18, 100 * 1e18, 1 * 1e18);

    //     // Simulate the depositVault function
    //     vm.prank(router);
    //     pool.depositVault(user, 1e18, address(tokenA));

    //     // Simulate the withdrawVault function
    //     vm.expectRevert();
    //     vm.prank(router);
    //     pool.withdrawVault(user, 1e18, address(tokenA));

    // }    
}
