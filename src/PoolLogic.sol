// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolStates} from "./interfaces/pool/IPoolStates.sol";
import {IPoolLogic} from "./interfaces/IPoolLogic.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract PoolLogic is Initializable, OwnableUpgradeable, IPoolLogic {

    uint256 internal BASE_D_AMOUNT = 1e18;
    uint256 internal DECIMAL = 1e18;

    address public override POOL_ADDRESS;
    IPoolStates pool;

    modifier onlyPool(){
        if(getPoolAddress(msg.sender) == address(0)) revert NotAPool();
        _;
    }

    function initialize(address poolAddress, address owner) public initializer {
        __Ownable_init(owner);

        POOL_ADDRESS = poolAddress;
        pool = IPoolStates(POOL_ADDRESS);
        emit PoolAddressUpdated(address(0), POOL_ADDRESS);
    }

    function calculateLpUnitsToMint(uint256 amount, uint256 reserveA, uint256 totalLpUnits) external pure returns(uint256) {
        if (reserveA == 0) {
            return amount;
        }

        return totalLpUnits * amount / (amount + reserveA);
    }

    function calculateDUnitsToMint(uint256 amount, uint256 reserveA, uint256 reserveD) external view returns(uint256) {
         if (reserveD == 0) {
            return BASE_D_AMOUNT;
        }

        return reserveD * amount / (reserveA);
    }

    // // 0.15% will be 15 poolSlippage. 100% is 100000 units
    // function calculateStreamCount(uint256 amount, uint256 poolSlippage, uint256 reserveD) external pure override returns(uint256) {
    //     // streamQuantity = SwappedAmount/(globalMinSlippage * PoolDepth)
    //     return amount * 10000/ (100000-poolSlippage * reserveD);
    // }

    function calculateAssetTransfer(uint256 lpUnits, uint256 reserveA, uint256 totalLpUnits) external pure returns(uint256) {
        return reserveA * (lpUnits/totalLpUnits);
    }

    function calculateDToDeduct(uint256 lpUnits, uint256 reserveD, uint256 totalLpUnits) external pure returns(uint256) {
        return reserveD * (lpUnits/totalLpUnits);
    }

    function updateBaseDAmount(uint256 newBaseDAmount) external override onlyOwner {
        emit BaseDUpdated(BASE_D_AMOUNT, newBaseDAmount);
        BASE_D_AMOUNT = newBaseDAmount;
    }

    function updatePoolAddress(address poolAddress) external override onlyOwner {
        emit PoolAddressUpdated(POOL_ADDRESS, poolAddress);
        POOL_ADDRESS = poolAddress;
        pool = IPoolStates(POOL_ADDRESS);
    }

    function getPoolAddress(address poolAddress) private view returns (address) {
        // TODO : Resolve this tuple unbundling issue
        (uint a, uint b, uint c, uint d, uint f, address tokenAddress) = pool.poolInfo(poolAddress);
        return tokenAddress;
    }
}