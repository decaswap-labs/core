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

    function mintLpUnits(uint256 amount, uint256 reserveA, uint256 totalLpUnits) external override onlyPool returns(uint256) {
        if (reserveA == 0) {
            return amount;
        }

        uint256 lpUnits = totalLpUnits * amount / (amount + reserveA);
        emit LPUnitsMinted(lpUnits);
        return lpUnits;
    }

    function mintDUnits(uint256 amount, uint256 reserveA, uint256 reserveD) external override onlyPool returns(uint256) {
         if (reserveD == 0) {
            return BASE_D_AMOUNT;
        }

        uint256 dUints = reserveD * amount / (reserveA);
        emit DUnitsMinted(dUints);
        return dUints;
    }

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
        (uint a, uint b, uint c, uint d, uint f, uint g, address tokenAddress) = pool.poolInfo(poolAddress);
        return tokenAddress;
    }
}