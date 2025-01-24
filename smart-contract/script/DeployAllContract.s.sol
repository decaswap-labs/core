// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

// import "forge-std/Script.sol";
// import "../src/Router.sol";
// import "../src/Pool.sol";
// import "../src/PoolLogic.sol";

// contract DeployAllContract is Script {
//     function run() external {
//         address ZERO_ADDRESS = address(0);
//         // Fetch the OWNER_ADDRESS from the environment variables
//         address ownerAddress = vm.envAddress("OWNER_ADDRESS");
//         console.log("Owner address:", ownerAddress);

//         // Fetch the VAULT_ADDRESS from the environment variables
//         address vaultAddress = vm.envAddress("VAULT_ADDRESS");
//         console.log("Vault address:", vaultAddress);

//         // Fetch the PRIVATE_KEY from the environment variables
//         uint256 privateKey = vm.envUint("PRIVATE_KEY");

//         // Start broadcasting transactions
//         vm.startBroadcast(privateKey);

//         // Step 1: Deploy Pool contract
//         Pool pool = new Pool(vaultAddress, ZERO_ADDRESS, ZERO_ADDRESS);
//         console.log("Pool deployed to:", address(pool));

//         // Step 2: Deploy PoolLogic contract with Pool address
//         PoolLogic poolLogic = new PoolLogic(ownerAddress, address(pool));
//         console.log("PoolLogic deployed to:", address(poolLogic));

//         // Step 3: Deploy Router contract with Pool address
//         Router router = new Router(ownerAddress, address(pool));
//         console.log("Router deployed to:", address(router));

//         // Step 4: Update Pool contract with Router address
//         pool.updateRouterAddress(address(router));
//         console.log("Router address updated in Pool:", address(router));

//         // Step 5: Update Pool contract with PoolLogic address
//         pool.updatePoolLogicAddress(address(poolLogic));
//         console.log("PoolLogic address updated in Pool:", address(poolLogic));

//         // Stop broadcasting transactions
//         vm.stopBroadcast();
//     }
// }
