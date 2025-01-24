# Monorepo: Foundry Smart Contracts & NestJS Backend

This repository is a monorepo containing:
1. **Smart Contracts** (Foundry) located in the `smart-contract` folder.
2. **Backend** (NestJS monorepo) located in the `backend` folder.

---
# Smart Contract: Foundry

This folder contains the smart contracts for the DECASwap AMM, built using the [Foundry Framework](https://book.getfoundry.sh/).

## Setup

1. **Shift to smart-contract folder**:
   ```bash
   cd smart-contract
    ```
2. **Setup environment variables**:
    Copy .env.example and paste in .env file and update the values.
3. **Build**:
    Build the contracts:
    ```bash
    forge build
    ```
4. **Deployments**:
    Use Foundry’s forge script command to deploy the contract:
    ```bash
    forge script script/DeployAllContract.s.sol:DeployAllContract --rpc-url <NETWORK_RPC> --broadcast
    ```
5. **Verification**:
    Use Etherscan or a similar service to verify the contract code:
    ```bash
    forge verify-contract <LIQUIDITY_LOGIC_CONTRACT_ADDRESS> src/LiquidityLogic.sol:LiquidityLogic --chain-id <CHAIN_ID> --etherscan-api-key $ETHERSCAN_API_KEY
    forge verify-contract <POOL_CONTRACT_ADDRESS> src/Pool.sol:Pool --chain-id <CHAIN_ID> --etherscan-api-key $ETHERSCAN_API_KEY
    forge verify-contract <POOL_LOGIC_CONTRACT_ADDRESS> src/PoolLogic.sol:PoolLogic --chain-id <CHAIN_ID> --etherscan-api-key $ETHERSCAN_API_KEY
    forge verify-contract <ROUTER_CONTRACT_ADDRESS> src/Router.sol:Router --chain-id <CHAIN_ID> --etherscan-api-key $ETHERSCAN_API_KEY
    ```

---

# Backend: NestJS Monorepo

This folder contains the backend application, built using the [NestJS Framework](https://nestjs.com/). The backend is organized as a monorepo, containing the following modules:

1. **APIs** (`apps/apis`): The primary API services.
2. **Keeper** (`apps/keeper`): A background service for scheduled tasks or maintenance jobs.

---

## Setup

### Prerequisites

Ensure you have the following installed:
- [Node.js](https://nodejs.org/) (Version specified in `.nvmrc`)
- [nvm (Node Version Manager)](https://github.com/nvm-sh/nvm)

### Steps

1. **Shift to backend folder**:<br>
   ```bash
   cd backend
    ```
2. **Setup environment variables**:<br>
   Copy .env.example and paste in .env file and update the values.


3. **Select the Node.js Version**:<br>
   Use the `.nvmrc` file to install and use the required Node.js version:
   ```bash
   nvm install
   nvm use
    ```
   
4. **Install dependencies**:<br>
   Install the required dependencies:
   ```bash
   npm i
   ```
   
5. **Setup contract in backend**<br>
- Copy contract address from smart-contract and paste in .env file. 
- Copy abis from smart-contract and paste in backend/libs/utils/src/abis folder.

6. **Run modules**:<br>
    Run the required modules:
    ```bash
    npm run start:apis
    npm run start:keeper
    ```
