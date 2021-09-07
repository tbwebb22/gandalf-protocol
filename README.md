# GandalfProtocol

Disclaimer: This codebase requires more extensive testing before it should be deployed to mainnet.

## Overview
The Gandalf protocol enables decentralized active liquidity management for Uniswap v3 with the following properties:
 - A user can buy Gandalf tokens using any amount of either of the two tokens that compose the Uniswap pool.
 - The Gandalf token represents the user's share of the liquidity position.
 - A Gandalf pool only holds one liquidity position at any given time.
 - The owner defines the liquidity position tick range, and this range can be updated at any time by the owner.
 - If the Uniswap v3 pool price falls out of range of the current liquidity position, the Gandalf pool
    will move the ticks so the liquidity position is back in range upon the next user action.
 - Public view functions allow anyone to check the Gandalf token price relative to either token0 or token1,
    making tracking impermanent loss and fee yield easier for users to track.
 - The Gandalf pool automatically harvests fee yields and reinvests them into the liquidity position upon each user action.
 - Implements upgradeability utilizing the transparent proxy pattern

## Set up the environment

nvm use

npm install

Create your own .env file from the .env.example with a valid API key

## Run the tests

npx hardhat test

## To Do
- Write more extensive tests
- Add keeper reward for calling rebalance() function
- Add in governance contract that becomes the owner