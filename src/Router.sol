// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IPoolActions} from "./interfaces/pool/IPoolActions.sol";
import {IPoolStates} from "./interfaces/pool/IPoolStates.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {IERC20} from "./interfaces/utils/IERC20.sol";
contract Router is Initializable, OwnableUpgradeable, IRouter {
    address public override POOL_ADDRESS;
    IPoolActions pool;
    IPoolStates poolStates;

    function initialize(address owner, address poolAddress) public initializer {
        __Ownable_init(owner);

        POOL_ADDRESS = poolAddress;
        pool = IPoolActions(POOL_ADDRESS);
        poolStates = IPoolStates(POOL_ADDRESS);

        emit PoolAddressUpdated(address(0), POOL_ADDRESS);
    }

    function createPool(address token, uint amount, uint256 minLaunchReserveA, uint256 minLaunchReserveD,uint256 initialDToMint) external onlyOwner {
        if (poolExist(token)) revert InvalidPool();
        if (amount == 0) revert InvalidAmount();
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IPoolLogic(poolStates.POOL_LOGIC()).createPool(token,msg.sender,amount,minLaunchReserveA,minLaunchReserveD,initialDToMint);
    }

    // @todo create a function for admin to create and add liq to the pool
    // current one in Pool.sol has some issues as it assumes it has got the tokens

    function addLiquidity(address token, uint256 amount) external override {
        // @todo confirm about the appoach, where to keep checks? PoolLogic/Pool/Router??Then refactor
        if (!poolExist(token)) revert InvalidPool();
        if (amount == 0) revert InvalidAmount();

        IERC20(token).transferFrom(msg.sender, POOL_ADDRESS, amount);
        IPoolLogic(poolStates.POOL_LOGIC()).addLiquidity(token,msg.sender,amount);

        emit LiquidityAdded(msg.sender, token, amount);
    }

    function removeLiquidity(address token, uint256 lpUnits) external override {
        if (!poolExist(token)) revert InvalidPool();

        if (lpUnits == 0 || lpUnits > poolStates.userLpUnitInfo(msg.sender, token)) revert InvalidAmount();

        pool.remove(msg.sender, token, lpUnits);

        emit LiquidityRemoved(msg.sender, token, lpUnits);
    }

    function updatePoolAddress(address newPoolAddress) external override onlyOwner {
        emit PoolAddressUpdated(POOL_ADDRESS, newPoolAddress);
        POOL_ADDRESS = newPoolAddress;
        pool = IPoolActions(POOL_ADDRESS);
        poolStates = IPoolStates(POOL_ADDRESS);
    }

    function poolExist(address tokenAddress) internal view returns (bool) {
        // TODO : Resolve this tuple unbundling issue
        (uint256 a, uint256 b, uint256 c, uint256 d, uint256 f, uint256 g, uint256 h, bool initialized) =
            poolStates.poolInfo(tokenAddress);
        return initialized;
    }
}
