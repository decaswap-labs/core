# Blockchain Project Design Specification (Mk1)

## Introduction

**_ CHANGE _** ALL **_ OF _** THIS **_ TO _** QUESTIONS **_ FOR _** JP \*\*

This design specification outlines the first iteration (Mk1) of our ethereum-based protocol, inspired by the primitives observed in **Thorchain**.

The primary goal of this document is to define technical mechanics that are to be featured in the architecture, in the aim of acheiving the protocol's main goals and USPs, being:

1. Streaming Liquidity
   Deposits, swaps and ultimately lends will be supported by the Thorchain primitive of _continuous liquidity_. This effectively means that a deposit of liquiditiy by a provider is turned into a 'stream' by splitting the capital inoput into a number of smaller chunks. These chunks will be valued with each block, and as such will aim to retain a 15BPS margin to any price quotation. This minimises MEV attack vectors whilst simultaneously provides methods by which trades can be executed in a manner more efficient than seen in traditional (e.g. Uniswap v2/v3) swapping protocols.

2. Payout in USDC
   Liquidity providers will be paid out in USDC. This gives a more favourable exposure to impermenant loss and generally gives rise to a more stable pool with time: higher USDC focused liquidity provisioning will result from incentivise providers.

3. Synthetic Mappings
   By utilising mappings instead of ERC20 (or similar) tokens in the minting of synthetic assets, gas fees are significantly reduced. Firstly the cost of changing a storage slot in the EVM is less than minting tokens. Secondly, via streaming and pending swaps, trades can be 'matched' in an incoming stream with a pending trade, making the stream process cheaper and faster, executing transactions in the same block where applicable.

### Key Benefits and Features

- **USDC Payouts for Liquidity Providers (LPs)**: LPs are rewarded in a stable asset, **USDC**, mitigating their exposure to volatile assets and significantly reducing the risk of **impermanent loss**.
- **Streaming Swaps**: Swaps are broken down into continuous "streams" rather than single, atomic transactions. This minimizes the risk of **MEV** and helps regulate arbitrage opportunities by distributing swaps over time, leading to fairer pricing.
- **Minimized Impermanent Loss**: The protocol architecture, through its USDC payouts and swap mechanics, is designed to reduce **impermanent loss**, a key risk in traditional automated market makers (AMMs).

## Protocol Design

The protocol's design decisions have been made with the goal of enhancing LP protection, improving swap efficiency, and ensuring a fairer market environment for all users. Below is an explanation of the key design decisions, followed by a breakdown of the architecture on a contract-by-contract basis.

### Design Decisions

1. **LP Payout Mechanism**: LPs are rewarded in **USDC** rather than the native pool tokens. This reduces their exposure to price volatility and thus their risk of incurring **impermanent loss**. This payout method also aligns incentives to attract stable and long-term liquidity.

2. **Streaming Swaps**: Unlike traditional swaps that execute immediately, **streaming swaps** break down a swap into a series of smaller transactions over time. This not only reduces the likelihood of front-running and **MEV** exploitation but also provides more opportunities for **natural arbitrage**, which helps stabilize price fluctuations in the protocol.

3. **Arbitrage Regulation**: The protocol takes an innovative approach to arbitrage by regulating the process through streaming swaps, reducing extreme fluctuations and limiting arbitrage opportunities to natural market conditions. This reduces profit-seeking behaviors that might otherwise destabilize the pool or lead to harmful pricing discrepancies.

## Contract Architecture

The protocol is composed of several smart contracts, each responsible for a different aspect of the system. Below is an overview of the key contracts and their roles:

### 1. **Liquidity Pool Contract**

- **Purpose**: Manages liquidity deposits, withdrawals, and the associated payouts to LPs.
- **Key Features**:
  - Tracks user contributions and dynamically calculates share ownership.
  - Issues payouts in **USDC**, based on the performance of the pool.
  - Reduces **impermanent loss** by stabilizing LP rewards.

### 2. **Swap Contract**

- **Purpose**: Manages the streaming swap functionality.
- **Key Features**:
  - Allows users to initiate swaps between assets over a designated period.
  - Executes swaps in small batches to reduce **MEV** risk and regulate arbitrage.
  - Uses a time-weighted average pricing (TWAP) mechanism to ensure fair pricing over the duration of the swap.

### 3. **Arbitrage Controller Contract**

- **Purpose**: Manages and regulates arbitrage opportunities.
- **Key Features**:
  - Monitors price discrepancies across liquidity pools and external markets.
  - Limits arbitrage opportunities by ensuring swaps are spread out, preventing sudden shifts in pool balances.
  - Works in tandem with the **Streaming Swap Contract** to provide more predictable pricing.

### 4. **USDC Distribution Contract**

- **Purpose**: Handles the distribution of rewards in USDC to liquidity providers.
- **Key Features**:
  - Aggregates fees and profits from the protocol and distributes them in stablecoins to LPs.
  - Ensures a consistent flow of rewards to mitigate the risk of **impermanent loss**.
  - Supports LP reinvestment back into the liquidity pool.

## Future Considerations (Mk2 and Beyond)

The Mk1 specification lays the foundation for future developments. The Mk2 version of the protocol will introduce more **embellished and universal features** to further enhance the user experience, LP rewards, and protocol security. Some key areas of focus include:

- **Cross-Chain Liquidity**: Introducing support for cross-chain swaps and liquidity provisioning across multiple blockchains.
- **Dynamic Fee Structures**: Implementing dynamic fee models to optimize the protocol’s performance based on network conditions.
- **Governance Mechanism**: Introducing decentralized governance to allow the community to influence key protocol parameters and decisions.
- **Enhanced MEV Protection**: Continued refinement of mechanisms to further reduce the impact of MEV on users and the protocol.
- **Advanced Impermanent Loss Protection**: Investigating methods to hedge against or further minimize impermanent loss through advanced algorithms and external integrations (e.g., insurance protocols).

---

This design specification represents the first iteration (Mk1) of our protocol. As we gather more data and community feedback, the specification will evolve in future versions (e.g., Mk2) to incorporate new features and address potential limitations in the current architecture.
