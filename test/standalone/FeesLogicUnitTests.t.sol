// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/lib/LPDeclaration.sol";

import {console} from "forge-std/Test.sol";
import {DeploysForFees} from "./DeploysForFees.t.sol";
import {FeesLogic} from "src/FeesLogic.sol";
import {MockERC20} from "src/MockERC20.sol";
import {Pool} from "src/Pool.sol";
import {PoolLogic} from "src/PoolLogic.sol";
import {Router} from "src/Router.sol";

contract FeesLogicUnitTests is DeploysForFees {

    using LPDeclaration for LPDeclaration.Declaration;

    address public liquidityProvider = makeAddr("LP");
    address public bot = makeAddr("Bot");
    address public lp1= makeAddr("LP1");
    address public lp2= makeAddr("LP2");
    address public lpFalse= makeAddr("LPFalse");

    event LpDeclarationCreated(address indexed liquidityProvider);
    event LpDeclarationUpdated(address indexed provider);

    function setUp() public virtual override {
        super.setUp();
        // @dev this needs to be updated to replace some proxy functions on interration
    }

    function test_ProxyInitPool() public {
        vm.startPrank(owner);
        feesLogic.proxyInitPool(address(tokenA));
        assertEq(feesLogic.poolEpochCounter(address(pool)), 0);
        assertEq(feesLogic.poolEpochCounterFees(address(pool), 0), 0);
        assertEq(feesLogic.pools(0), address(tokenA));
        vm.stopPrank();
    }

    function test_ProxyExecuteSwapStream() public {
        vm.startPrank(owner);
        feesLogic.proxyInitPool(address(tokenA));
        feesLogic.proxyExecuteSwapStream(address(tokenA), 10000);
        uint256 inferredAmount = ((10000 * 15) / 10000);
        assertEq(feesLogic.poolEpochCounterFees(address(tokenA), 0), inferredAmount); 
        vm.stopPrank();
    }

    function test_Core_CreateLpDeclaration() public {
        vm.prank(lp1);
        feesLogic.createLpDeclaration(lp1, address(tokenA), 100);
        uint32 epochs0 = feesLogic.poolLpEpochs(address(tokenA), lp1, 0);
        assertEq(epochs0, 0);
        uint32 pUnits0 = feesLogic.poolLpPUnits(address(tokenA), lp1, 0);
        assertEq(pUnits0, 100);
    }

    function test_Core_UpdateLpDeclaration_Add() public {
        vm.prank(lp1);
        feesLogic.createLpDeclaration(lp1, address(tokenA), 100);
        feesLogic.updateLpDeclaration(lp1, address(tokenA), 100, true);
        uint32 epochs0 = feesLogic.poolLpEpochs(address(tokenA), lp1, 0);
        assertEq(epochs0, 0);
        uint32 pUnits0 = feesLogic.poolLpPUnits(address(tokenA), lp1, 0);
        assertEq(pUnits0, 100);
    }

    function test_Liquidity_AddSingle_SingleLP() public {
        vm.startPrank(bot);
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
        assertEq(feesLogic.poolEpochCounter(address(tokenA)), 1);
        assertEq(feesLogic.poolEpochPDepth(address(tokenA), 1), 100);
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 0), 1);
        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 0), 100);
        assertEq(feesLogic.instaBotFees(address(tokenA), bot), 5);
    }

    function test_Liquidity_AddDouble_SingleLP() public {
        vm.startPrank(bot);
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
        assertEq(feesLogic.poolEpochCounter(address(tokenA)), 1);
        assertEq(feesLogic.poolEpochPDepth(address(tokenA), 1), 100);
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 0), 1);
        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 0), 100);
        assertEq(feesLogic.instaBotFees(address(tokenA), bot), 5);
    
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
        assertEq(feesLogic.poolEpochCounter(address(tokenA)), 2);
        assertEq(feesLogic.poolEpochPDepth(address(tokenA), 2), 200);
        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 1), 200);
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 0), 1);
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 1), 2);
        assertEq(feesLogic.instaBotFees(address(tokenA), bot), 10);

    }

    function test_Liquidity_AddDouble_RemoveSingle_SingleLP() public {
        vm.startPrank(bot);
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, false);

        assertEq(feesLogic.poolEpochCounter(address(tokenA)), 3);
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 2), 3);
        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 2), 100);
        assertEq(feesLogic.poolEpochPDepth(address(tokenA), 1), 100);
        assertEq(feesLogic.poolEpochPDepth(address(tokenA), 2), 200);
        assertEq(feesLogic.poolEpochPDepth(address(tokenA), 3), 100);
        assertEq(feesLogic.instaBotFees(address(tokenA), bot), 15);

    }

    function test_Liquidity_AddDouble_RemoveDouble_CloseDeclaration_SingleLP() public {
        vm.startPrank(bot);
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, false);
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, false);

        assertEq(feesLogic.poolEpochCounter(address(tokenA)), 4);
        // declarations that are closed should resolve array[array.length - 1] to zero
        // this is a double measure on security to ensure that any LP trying to reclaim fees are unable to do so
        // @audit a reentrancy guard should exist on the fees contract to stop recursive claims of fees 
        // assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 0), 0);
        // assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 4), 0);
        assertEq(feesLogic.poolEpochPDepth(address(tokenA), 1), 100);
        assertEq(feesLogic.poolEpochPDepth(address(tokenA), 2), 200);
        assertEq(feesLogic.poolEpochPDepth(address(tokenA), 3), 100);
        assertEq(feesLogic.poolEpochPDepth(address(tokenA), 4), 0);
        assertEq(feesLogic.instaBotFees(address(tokenA), bot), 20);
    }


    function test_Fees_DebitLpFees_SingleSwapStream() public {
        // this test runs on the assumption that we debit fees from each stream execution
        // the actual reality is that we debit fees from the end of a swap. 
        // this function call, and the structure of parameters around it,
        // should remain the same
        vm.startPrank(bot);
        feesLogic.proxyInitPool(address(tokenA));
        feesLogic.debitLpFeesFromSwapStream(address(tokenA), 1000);
        assertEq(feesLogic.poolEpochCounterFees(address(tokenA), 0), 1000);
    }

    function test_ProxySwap_CheckDebitBotFees_SingleSwapStream() public {
        vm.prank(bot);
        feesLogic.proxyExecuteSwapStream(address(tokenA), 10000);
        uint256 inferredBotFeeAmount = ((10000 * 5) / 10000);
        assertEq(feesLogic.instaBotFees(address(tokenA), bot), inferredBotFeeAmount);
        // feesLogic.debitBotFeesFromSwapStream(1000);
        // assertEq(feesLogic.instaBotFees(bot), 1000);
    }

    function test_ProxySwap_CheckDebitBotAndLpFees_MacroSwapStream() public {
        vm.startPrank(bot);
        for (uint256 i = 0; i < 10; i++) {
        feesLogic.proxyExecuteSwapStream(address(tokenA), 10000);
        }
        uint256 inferredLpFeeAmount = 10 * ((10000 * 15) / 10000);
        assertEq(feesLogic.poolEpochCounterFees(address(tokenA), 0), inferredLpFeeAmount);
        uint256 inferredBotFeeAmount = 10 * ((10000 * 5) / 10000);
        assertEq(feesLogic.instaBotFees(address(tokenA), bot), inferredBotFeeAmount);
        // feesLogic.debitBotFeesFromSwapStream(1000);
        // assertEq(feesLogic.instaBotFees(bot), 1000);
    }

    function test_ProxyEnvironmentSetup_SingleLP() public {
        vm.startPrank(bot);
        // here we add liquidity to a pool for two LPs
        // note lp1 will have 100% ownership of the pool
        for (uint256 i = 1; i <= 5; i++) {
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
        }
        // check the states 
        // global
        assertEq(feesLogic.poolEpochCounter(address(tokenA)), 5);
        assertEq(feesLogic.poolEpochCounterFees(address(tokenA), 5), 0);
        assertEq(feesLogic.poolEpochPDepth(address(tokenA), 5), 500);
        // lp1
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 4), 5);
        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 4), 500);

        // now we execute 10 swaps across that pool to accumulate fees
        for (uint256 i = 0; i < 10; i++) {
        feesLogic.proxyExecuteSwapStream(address(tokenA), 10000);
        }

        //now move the epoch one forwards to allow declarations to claim
        // @todo this should be a separate test
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lpFalse, true);

        // and check relevant states
        uint256 currentFeeAccumulation = feesLogic.poolEpochCounterFees(address(tokenA), 5);
        assertEq(currentFeeAccumulation, 150);

        // let's also ensure the bot has the correct fee assignment
        uint256 proposedBotAccumulator = feesLogic.instaBotFees(address(tokenA), bot);
        assertEq(proposedBotAccumulator, 80);
    }

    function test_ProxyEnvironmentSetup_DualLP_1() public {
        vm.startPrank(bot);
        // here we add liquidity to a pool for two LPs
        // note lp1 will have 60% ownership of the pool
        // note lp2 will have 40% ownership of the pool
        for (uint256 i = 1; i <= 5; i++) {
            if (i % 2 != 0) {
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
            }
            else {
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp2, true);
            }
        }
        // check the states 
        // global
        assertEq(feesLogic.poolEpochCounter(address(tokenA)), 5);
        assertEq(feesLogic.poolEpochCounterFees(address(tokenA), 5), 0);
        assertEq(feesLogic.poolEpochPDepth(address(tokenA), 5), 500);
        // lp1
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 2), 5);
        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 2), 300);
        // lp2
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp2, 1), 4);
        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp2, 1), 200);

        // now we execute 10 swaps across that pool to accumulate fees
        for (uint256 i = 0; i < 10; i++) {
        feesLogic.proxyExecuteSwapStream(address(tokenA), 10000);
        }

        //and we execute on more spurious liquidity stream to increase the epoch count
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lpFalse, true);

        // and check relevant states
        uint256 currentFeeAccumulation = feesLogic.poolEpochCounterFees(address(tokenA), 5);
        assertEq(currentFeeAccumulation, 150);
    }

    function test_ProxyEnvironmentSetup_DualLP_2() public {
        vm.startPrank(bot);
        // here we add liquidity to a pool for one LP
        for (uint256 i = 1; i <= 3; i++) {
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
        }

        // and then do the same with a different LP to increase the epoch count
        for (uint256 i = 1; i <= 3; i++) {
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lpFalse, true);
        }

        //and now we add some more for lp 1 to test the iterative procedure for multiple despotis
        for (uint256 i = 1; i <= 3; i++) {
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
        }

        // so we can expect the array for lp1 to look like
        // [1, 2, 3, 7, 8, 9]
        //and relative pUnits to look like
        // [100, 200, 300, 400, 500, 600]
        // so lets write these assertions
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 0), 1);
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 1), 2);
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 2), 3);
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 3), 7);
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 4), 8);
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 5), 9);

        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 0), 100);
        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 1), 200);
        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 2), 300);
        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 3), 400);
        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 4), 500);
        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 5), 600);

        // now lets bang a load of swap streams to accumulate fees
        for (uint256 i = 0; i < 10; i++) {
        feesLogic.proxyExecuteSwapStream(address(tokenA), 10000);
        }

        // and then increase the epoch by depositing more liquidity
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lpFalse, true);

        // now our poolPDepth per epoch would look like 
        // [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
        // and our fee accumulation would be 150 in epoch 9
        // and our bot fees would be 80
        // and current epoch would be 9 

    }

    function test_ProxyEnvironmentSetup_DualLP_2_NoChecks() public {
        vm.startPrank(bot);
        // here we add liquidity to a pool for one LP
        for (uint256 i = 1; i <= 3; i++) {
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
        }

        // and then do the same with a different LP to increase the epoch count
        for (uint256 i = 1; i <= 3; i++) {
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lpFalse, true);
        }

        //and now we add some more for lp 1 to test the iterative procedure for multiple despotis
        for (uint256 i = 1; i <= 3; i++) {
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
        }

        for (uint256 i = 0; i < 10; i++) {
        feesLogic.proxyExecuteSwapStream(address(tokenA), 10000);
        }

        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lpFalse, true);

    }

    function test_ProxyEnvironmentSetup_DualLP_3() public {
        vm.startPrank(bot);
        // here we add liquidity to a pool for one LP
        for (uint256 i = 1; i <= 10; i++) {
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp1, true);
        }

        // and then do the same with a different LP to increase the epoch count
        for (uint256 i = 1; i <= 90; i++) {
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lpFalse, true);
        }

        // //and now we add some more for lp 1 to test the iterative procedure for multiple despotis
        // for (uint256 i = 1; i <= 3; i++) {
        // feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lp2, true);
        // }

        // // so we can expect the array for lp1 to look like
        // // [1, 2, 3, 7, 8, 9]
        // //and relative pUnits to look like
        // // [100, 200, 300, 400, 500, 600]
        // // so lets write these assertions
        // assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 0), 1);
        // assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 1), 2);
        // assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 2), 3);
        // assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 3), 7);
        // assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 4), 8);
        // assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 5), 9);

        // assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 0), 100);
        // assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 1), 200);
        // assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 2), 300);
        // assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 3), 400);
        // assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 4), 500);
        // assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 5), 600);

        // now lets bang a load of swap streams to accumulate fees
        for (uint256 i = 0; i < 10; i++) {
        feesLogic.proxyExecuteSwapStream(address(tokenA), 10000);
        }

        // and then increase the epoch by depositing more liquidity
        feesLogic.proxyExecuteLiquidityStream(address(tokenA), 10000, 100, lpFalse, true);

        // now our poolPDepth per epoch would look like 
        // [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]
        // and our fee accumulation would be 150 in epoch 9
        // and our bot fees would be 80
        // and current epoch would be 9 

        assertEq(feesLogic.poolLpPUnits(address(tokenA), lp1, 9), 1000);
        assertEq(feesLogic.poolLpEpochs(address(tokenA), lp1, 9), 10);
        assertEq(feesLogic.poolEpochCounterFees(address(tokenA), 100), 150);

    }

    function test_Claim_SingleLP() public {
        test_ProxyEnvironmentSetup_SingleLP();

        uint256 accruedFee = feesLogic.claimLPAllocation(address(tokenA), lp1);
        assertEq(accruedFee, 67);
    }

    function test_Revert_ClaimAllocation() public {
        vm.expectRevert();
        feesLogic.claimLPAllocation(address(tokenA), lp1);
    }

    function test_Revert_CLaimAllocation_ClaimOnCurrentEpoch() public {
        vm.expectRevert();
        feesLogic.claimLPAllocation(address(tokenA), lp1);
    }

    function test_Claim_DualLP_1() public {
        test_ProxyEnvironmentSetup_DualLP_1();
        // effectively here, in epoch 5, we have 150 fees accumulated
        // lp1 should be able to claim 9/20 of those fees = 67.5
        // truncation in rounding errors should mean the LP receives 67
        // balances must be appropriately updated
        uint256 accruedFee = feesLogic.claimLPAllocation(address(tokenA), lp1);
        assertEq(accruedFee, 40);
        // lp2 should be able to claim 6/20 of those fees = 45
        // truncation in rounding errors should mean the LP receives 45
        // balances must be appropriately updated
        uint256 accruedFee2 = feesLogic.claimLPAllocation(address(tokenA), lp2);
        assertEq(accruedFee2, 27);
    }

    function test_Claim_DualLP_2() public {
        test_ProxyEnvironmentSetup_DualLP_2();
        uint256 accruedFee = feesLogic.claimLPAllocation(address(tokenA), lp1);
        assertEq(accruedFee, 45);
    }

    function test_Claim_DualLP_3() public {
        test_ProxyEnvironmentSetup_DualLP_2_NoChecks();
        test_ProxyEnvironmentSetup_DualLP_2_NoChecks();
        test_ProxyEnvironmentSetup_DualLP_2_NoChecks();

        test_ProxyEnvironmentSetup_DualLP_2_NoChecks();
        test_ProxyEnvironmentSetup_DualLP_2_NoChecks();
        test_ProxyEnvironmentSetup_DualLP_2_NoChecks();

        test_ProxyEnvironmentSetup_DualLP_2_NoChecks();
        test_ProxyEnvironmentSetup_DualLP_2_NoChecks();
        test_ProxyEnvironmentSetup_DualLP_2_NoChecks();
        test_ProxyEnvironmentSetup_DualLP_2_NoChecks();

        uint256 allocation = feesLogic.claimLPAllocation(address(tokenA), lp1);
        assertEq(allocation, 415);
    }
}