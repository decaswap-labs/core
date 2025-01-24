// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";
import { MockERC20 } from "src/MockERC20.sol";
import { PoolLogic } from "src/PoolLogic.sol";
import { Pool } from "src/Pool.sol";
import { Router } from "src/Router.sol";
import { LiquidityLogic } from "src/LiquidityLogic.sol";

contract Deploys is Test {
    address public owner = makeAddr("owner");
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    PoolLogic public poolLogic;
    LiquidityLogic public liquidityLogic;
    Pool public pool;
    Router public router;

    modifier ownerAction() {
        vm.startPrank(owner);
        _;
        vm.stopPrank();
    }

    function setUp() public virtual {
        _createTokensInAndOut();
        _createPoolLogic();
        _createLiquidityLogic();
        _createPool();
        _createRouter();
        _updateDatas();
    }

    function _createTokensInAndOut() internal ownerAction {
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);
    }

    function _createPoolLogic() internal ownerAction {
        poolLogic = new PoolLogic(owner, address(0), address(0));
    }

    function _createLiquidityLogic() internal ownerAction {
        liquidityLogic = new LiquidityLogic(owner, address(0), address(0));
    }

    function _createPool() internal ownerAction {
        pool = new Pool(address(0), address(router), address(poolLogic), address(liquidityLogic));
    }

    function _createRouter() internal ownerAction {
        router = new Router(owner, address(pool));
    }

    function _updateDatas() internal ownerAction {
        pool.updateRouterAddress(address(router));
        poolLogic.updatePoolAddress(address(pool));
        poolLogic.updateLiquidityLogicAddress(address(liquidityLogic));
        liquidityLogic.updatePoolAddress(address(pool));
        liquidityLogic.updatePoolLogicAddress(address(poolLogic));
    }
}
