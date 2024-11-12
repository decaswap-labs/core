# DECASwap AMM

This project is a work in progress.

## Overview

DECASWAP AMM (DAMM) is a permissionless, autonomous exchange platform. It is formed of three major elements, being the AMM itself, the token for the protocol $DECA and a DAO.

The AMM features a core SC Pool.sol. Users interact via an endpoint SC Router.sol. The Pool contract is responsible for containing the state of balances for all external and internal asset types interacting with or within the protocol, as well as holding the state for the surrounding contracts in the ecosystem (their ethereum addresses), in the image of the Eternal proxy pattern. The logics required to execute trades are split between several contracts. These govern the different types of transactions being executed in the protocol, listed as follows:

- `Router` endpoint for users

- `Pool` mint internal assets, store balances, upgradability functionalities

- `PoolLogic` add/remove liquidity streams, insert swap streams, rebalance pools, apply fees to stream execution

- `FeesLogic` apply fees to streams, calculate allocation, convert accumulated fees to `tokenOut`

- `Bot` process pairs, process liquidiy add/remove, execute functions to support arbitrage rebalancing

- `DECAToken` ERC20 token representing a proxy for the system

Together this contract architecture allows trading and generates revenues for the protocol, which are paid out to liquidity providers for pools and stakers of both the internal unit `D` (global pool) and the token `$DECA`. Any major changes, including upgrades to contracts and changes in fee structure or protocol design, are to be handed over to the DAO, and will be made according to the design principle of the Eternal storage upgradability pattern (NB it is an adapted implementation of this concept, not an off-the-shelf library).

The architecture introduces to the Ethereum ecosystem some novel design features. Namely being streaming swaps and payouts to LPs in USDC. Streams provide a manner of internal non-ERC20 tracking for assets in the internal unit D, which allows LPs to be exposed to both a secure system and a lucrative system, since all assets held in the pools are a proxy of value in the system as well as secure the stability of rebalancing and take fees through trade execution.

Users should thereafter receive an intuitive, streamlined, low risk experience from both angles of trading and liquidity provisioning in a permissionless swap environment, earning in USDC, being exposed to and earning fees from both trading and lending activity.

## Build

Built using Foundry [https://book.getfoundry.sh/]

## Whitepaper

Gitbook: https://decaswap-1.gitbook.io/decaswap-docs
