## Overview

This repository contains a swap and bridge implementation using UniswapV2 and the CCIP protocol for bridging ERC20 tokens.

**TokenSender** is a contract that allows a user to swap tokens for WETH and then bridge them to a destination chain using CCIP.

**TokenReceiver** is a contract that allows a user to receive bridged WETH from a source chain and swap it for the original token on the receiving chain using UniswapV2.

- The owner of the sender contract should make sure there is enough LINK in the contract to pay for the CCIP message fees.

## Advantages

-   **Simplifies cross-chain token management**
-   **Works with any ERC20 token that has WETH liquidity**
-   **Leverages established DEX infrastructure**

## Disadvantages

-   **Higher fees due to double swaps**
-   **More slippage exposure**
-   **Not optimal for tokens that don't need conversion (e.g., stablecoins)**

## Potential improvements

-   Adding more DEX options for better liquidity
-   Adding direct bridging path for common tokens (e.g. use CCIP lanes for stable coins)

## To Run Tests:

-   Uncomment the UniswapV2Router02 import in `script/Imports.s.sol`
-   Run `forge build` to build the UniswapV2Router02 contract artifact
-   Comment the import again
-   Uncomment the UniswapV2Factory import in `script/Imports.s.sol`
-   Run `forge build` to build the UniswapV2Factory contract artifact
-   Comment the import again
-   Then add this hash to the `pairFor` function on line 24 in `lib/v2-periphery/contracts/libraries/UniswapV2Library.sol`: `77820097bae7b0b30c784fe9efdd81e53e0438eaedc27794a7682e3886a792d6`
-   Run `forge test` to run the tests

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
