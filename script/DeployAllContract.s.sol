// SPDX - License - Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/Router.sol";
import "../src/Pool.sol";
import "../src/PoolLogic.sol";
import "../src/LiquidityLogic.sol";

contract DeployAllContract is Script {
    function run() external {
        address ZERO_ADDRESS = address(0);
        // Fetch the OWNER_ADDRESS from the environment variables
        address ownerAddress = vm.envAddress("OWNER_ADDRESS");
        console.log("Owner address:", ownerAddress);

        // Fetch the VAULT_ADDRESS from the environment variables
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        console.log("Vault address:", vaultAddress);

        // Fetch the PRIVATE_KEY from the environment variables
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(privateKey);

        // Step 1: Deploy PoolLogic contract
        PoolLogic poolLogic = new PoolLogic(ownerAddress, ZERO_ADDRESS, ZERO_ADDRESS);
        console.log("PoolLogic deployed to:", address(poolLogic));

        // Step 2: Deploy PoolLogic contract
        LiquidityLogic liquidityLogic = new LiquidityLogic(ownerAddress, ZERO_ADDRESS, ZERO_ADDRESS);
        console.log("LiquidityLogic deployed to:", address(liquidityLogic));

        // Step 3: Deploy Pool contract
        Pool pool = new Pool(vaultAddress, ZERO_ADDRESS, address(poolLogic), address(liquidityLogic));
        console.log("Pool deployed to:", address(pool));

        // Step 4: Deploy Router contract with Pool address
        Router router = new Router(ownerAddress, address(pool));
        console.log("Router deployed to:", address(router));

        // Step 5: Update Pool contract with Router address
        pool.updateRouterAddress(address(router));
        console.log("Router address updated in Pool:", address(router));

        // Step 6: Update Pool logic contract with Pool address
        poolLogic.updatePoolAddress(address(pool));
        console.log("Pool address updated in PoolLogic:", address(pool));

        // Step 7: Update Pool logic contract with LiquidityLogic address
        poolLogic.updateLiquidityLogicAddress(address(liquidityLogic));
        console.log("LiquidityLogic address updated in PoolLogic:", address(liquidityLogic));

        // Step 8: Update LiquidityLogic contract with Pool address
        liquidityLogic.updatePoolAddress(address(pool));
        console.log("Pool address updated in LiquidityLogic:", address(pool));

        // Step 9: Update LiquidityLogic contract with PoolLogic address
        liquidityLogic.updatePoolLogicAddress(address(poolLogic));
        console.log("PoolLogic address updated in LiquidityLogic:", address(poolLogic));

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
