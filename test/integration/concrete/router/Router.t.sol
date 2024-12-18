// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import {Deploys} from "test/shared/Deploys.t.sol";

// contract RouterTest is Deploys {
//     function setUp() public virtual override {
//         super.setUp();
//         _createPools();
//     }

//     function _createPools() internal {
//         vm.startPrank(owner);

//         uint256 initialDToMintPoolA = 30e18;
//         uint256 SLIPPAGE = 10;

//         uint256 tokenAAmount = 10_000e18;
//         uint256 tokenBAmount = 10_000e18;

//         router.initGenesisPool(address(tokenA), tokenAAmount, initialDToMintPoolA);

//         router.initPool(address(tokenB), address(tokenA), tokenBAmount, tokenAAmount);

//         // update pair slippage
//         pool.updatePairSlippage(address(tokenA), address(tokenB), SLIPPAGE);

//         vm.stopPrank();
//     }
// }
