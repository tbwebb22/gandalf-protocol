// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface IGandalfPool {
    /// @notice Allows the user to buy gandalf token using any amount of token0 and token1
    /// @notice The Amount of gandalf token the user receives represents their share of the liquidity position
    /// @param token0Amount The amount of token 0 the user wants to spend to buy the Gandalf token
    /// @param token1Amount The amount of token 1 the user wants to spend to buy the Gandalf token
    /// @param minGandalfTokenAmount The minimum amount of the Gandalf token the user is willing to receive
    /// @param deadline The timestamp at which the transaction will expire
    function buyGandalfToken(uint256 token0Amount, uint256 token1Amount, uint256 minGandalfTokenAmount, uint256 deadline) external;

    /// @notice Allows a user to sell their gandalf tokens for their share of the liquidity position
    /// @notice And receive either token0 or token1 in return
    /// @param gandalfTokenAmount The amount of Gandalf token the user wants to sell
    /// @param minTokenAmountToReceive The minimum amount of token0 or token1 the user is willing to receive
    /// @param receiveInToken0 Boolean indicating whether the user wants to receive token0 or token1
    /// @param deadline The timestamp at which the transaction will expire
    function sellGandalfToken(uint256 gandalfTokenAmount, uint256 minTokenAmountToReceive, bool receiveInToken0, uint256 deadline) external;

    /// @notice Rebalances the liquidity position by collecting fees, moving desired liquidity range ticks if needed,
    /// @notice Making swaps between token0 and token1 if needed, and adding to liquidity position if funds are available
    function rebalance() external;

    /// @notice Allows the owner to set a new Gandalf Pool Fee Numerator
    /// @param gandalfPoolFeeNumerator_ The new Gandalf Pool Fee Numerator
    function setGandalfPoolFeeNumerator(uint24 gandalfPoolFeeNumerator_) external;

    /// @notice Allows the owner to set a new Uniswap v3 Pool Slippage Numerator
    /// @param uniswapV3PoolSlippageNumerator_ The new Uniswap v3 Pool Slippage Numerator
    function setUniswapV3PoolSlippageNumerator(uint24 uniswapV3PoolSlippageNumerator_) external;

    /// @notice Allows the owner to set a new Desired Tick Range
    /// @param desiredTickRange_ The new Desired Tick Range
    function setDesiredTickRange(uint24 desiredTickRange_) external;

    /// @notice Gets the estimated amount of token0 or token1 user will receive when selling
    /// @notice the specified amount of Gandalf Token
    /// @param gandalfTokenAmountSold The amount of Gandalf Token being sold
    /// @param receiveInToken0 Boolean indicating whether the user wants to receive token0 or token1
    /// @return maxTokenAmountToReceive The max amount of the token the user could receive from sell
    function getTokenAmountToReceiveFromSell(uint256 gandalfTokenAmountSold, bool receiveInToken0) external view returns (uint256 maxTokenAmountToReceive);

    /// @notice Returns the current price of the Uniswap pool represented as a tick
    /// @return The tick of the current price
    function getCurrentPriceTick() external view returns (int24);

    /// @notice Gets the current price represented as a tick, rounded according to the tick spacing
    /// @return The current price tick rounded
    function getCurrentPriceTickRounded() external view returns (int24);

    /// @notice Gets the tick spacing of the Uniswap pool
    /// @return The pool tick spacing
    function getTickSpacing() external view returns (int24);

    /// @notice Gets the desired tickLower and tickUpper based on the current price and the desiredTickRange
    /// @return newDesiredTickLower The new tick lower desired for the liquidity position
    /// @return newDesiredTickUpper The new tick upper desired for the liquidity position
    function getNewDesiredTicks() external view returns (int24 newDesiredTickLower, int24 newDesiredTickUpper);

    /// @notice Returns whether the liquidity position needs an update
    /// @notice This can return true when the price has moved outside of the current liquidity position range,
    /// @notice or when the desired tick range has been updated by the owner
    /// @return bool Indicates whether the liquidity position needs to be updated
    function getIfLiquidityPositionNeedsUpdate() external view returns (bool);

    /// @notice Returns whether the current Uniswap pool price is within the liquidity position range
    /// @return priceInLiquidityRange Returns true if the current price is within the liquidity position range
    function getPriceInActualLiquidityRange() external view returns (bool priceInLiquidityRange);

    /// @notice Returns whether the current Uniswap pool price within the desired liquidity position range
    /// @return priceInLiquidityRange Returns true if the current price within the desired liquidity position range
    function getPriceInDesiredLiquidityRange() external view returns (bool priceInLiquidityRange);

    /// @notice Returns the current sqrtPriceX96 of the Uniswap pool
    /// @return sqrtPriceX96 The current price of the Uniswap pool
    function getSqrtPriceX96() external view returns (uint160 sqrtPriceX96);

    /// @notice Gets the estimated token amount out from a swap. This calculation takes into account
    /// @notice the pool fee, but assumes that no slippage occurs
    /// @param tokenIn The address of the token being swapped
    /// @param tokenOut The address of the token being swapped for
    /// @param amountIn The amount of tokenIn being swapped
    /// @param fee The fee to apply to the estimated swap
    /// @return amountOut The estimated amount of tokenOut that will be received from the swap
    function getEstimatedTokenOut(address tokenIn, address tokenOut, uint256 amountIn, uint24 fee) external view returns (uint256 amountOut);

    /// @notice Gets the amount out minimum to use for a swap, according to the configured allowable slippage numerator
    /// @param tokenIn The address of the token being swapped
    /// @param tokenOut The address of the token being swapped for
    /// @param amountIn The amount of tokenIn being swapped
    /// @return amountOutMinimum The minimum amount of tokenOut to use for the swap
    function getAmountOutMinimum(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOutMinimum);

    /// @notice Gets the value of token0 and token1 held by this contract in terms of token0 value
    /// @return The reserve value relative to token0
    function getReserveValueInToken0() external view returns (uint256);

    /// @notice Gets the value of token0 and token1 held by the liquidity position in terms of token0 value
    /// @return The liquidity position value relative to token0    
    function getLiquidityPositionValueInToken0() external view returns (uint256);

    /// @notice Gets the total value (reserves + liquidity position) in terms of token 0 value
    /// @return The total value relative to token0
    function getTotalValueInToken0() external view returns (uint256);

    /// @notice Gets the total value (reserves + liquidity position) in terms of token 0 value
    /// @return The total value relative to token0
    function getTotalValueInToken1() external view returns (uint256);

    /// @notice Returns the total liquidity amount held by the current liquidity position
    /// @return liquidityAmount The liquidity amount of the current liquidity position
    function getLiquidityPositionLiquidityAmount() external view returns (uint128 liquidityAmount);

    /// @notice Returns the desired reserve amounts of token0 and token1 that are needed
    /// @notice to add the maximum amount of liquidity to the current liquidity position
    /// @param token0Amount The desired amount of token0
    /// @param token1Amount The desired amount of token1
    function getDesiredReserveAmounts() external view returns (uint256 token0Amount, uint256 token1Amount);

    /// @notice Returns whether the specified tick range is valid. For the tick range to be valid, it needs to be evenly
    /// @notice divisible by the tick spacing, and be greater than or equal to (tickSpacing * 2)
    function getIsTickRangeValid(uint24 tickRange) external view returns (bool);

    /// @notice Returns the pool fee of the Uniswap pool liquidity is being provided to
    /// @return The Uniswap pool fee
    function getUniswapV3PoolFee() external view returns (uint24);

    /// @notice Returns the Gandalf pool fee numerator, that gets divided by FEE_DENOMINATOR
    /// @notice to calculate the fee percentage
    /// @return The Gandalf Pool Fee Numerator
    function getGandalfPoolFeeNumerator() external view returns (uint24);

    /// @notice Returns the Gandalf pool fee numerator, that gets divided by SLIPPAGE_DENOMINATOR
    /// @notice to calculate the slippage percentage
    /// @return The Uniswap Pool Slippage Numerator   
    function getUniswapV3PoolSlippageNumerator() external view returns (uint24);

    /// @notice Returns the desired tick range
    /// @return The desired tick range
    function getDesiredTickRange() external view returns (uint24);

    /// @notice Returns the desired tick lower
    /// @return The desired tick lower
    function getDesiredTickLower() external view returns (int24);

    /// @notice Returns the desired tick upper
    /// @return The desired tick upper
    function getDesiredTickUpper() external view returns (int24);

    /// @notice Returns the actual tick lower of the current liquidity position
    /// @return actualTickLower The actual tick lower of the current liquidity position
    function getActualTickLower() external view returns (int24 actualTickLower);

    /// @notice Returns the actual tick upper of the current liquidity position
    /// @return actualTickUpper The actual tick upper of the current liquidity position
    function getActualTickUpper() external view returns (int24 actualTickUpper);

    /// @notice Returns the token ID of the current liquidity position
    /// @return The token ID of the current liquidity position
    function getLiquidityPositionTokenId() external view returns (uint256);

    /// @notice Returns the address of the Uniswap v3 Factory Address
    /// @return The Uniswap v3 Factory Address
    function getUniswapV3FactoryAddress() external view returns (address);

    /// @notice Returns the Uniswap v3 Swap Router Address
    /// @return The Uniswap v3 Swap Router Address
    function getUniswapV3SwapRouterAddress() external view returns (address);

    /// @notice Returns the Uniswap v3 Position Manager Address
    /// @return The Uniswap v3 Position Manager Address
    function getUniswapV3PositionManagerAddress() external view returns (address);

    /// @notice Returns the Uniswap v3 Pool Address
    /// @return The Uniswap v3 Pool Address
    function getUniswapV3PoolAddress() external view returns (address);

    /// @notice Returns the address of token 0 of the Uniswap pool
    /// @return The token 0 address
    function getToken0() external view returns (address);

    /// @notice Returns the address of token 1 of the Uniswap pool
    /// @return The token 1 address
    function getToken1() external view returns (address);

    /// @notice Returns the price of the Gandalf token relative to token 0 scaled by 10^18
    /// @return The price in token 0 scaled by 10^18
    function getGandalfTokenPriceInToken0() external view returns (uint256);


    /// @notice Returns the price of the Gandalf token relative to token 1 scaled by 10^18
    /// @return The price in token 1 scaled by 10^18
    function getGandalfTokenPriceInToken1() external view returns (uint256);

    /// @notice Returns the fee denominator constant
    /// @return The fee denominator constant
    function getFeeDenominator() external pure returns (uint24);

    /// @notice Takes the address of two unsorted tokens and returns the tokens sorted for use with Uniswap v3
    /// @param tokenA The address of the first unsorted token
    /// @param tokenB The address of the second unsorted token
    /// @return token0_ The address of the sorted token 0
    /// @return token1_ The address of the sorted token 1
    function getTokensSorted(address tokenA, address tokenB) external pure returns (address token0_, address token1_);

    /// @notice Returns the slippage denominator used for calculating the allowable slippage percentage
    /// @return The slippage denominator
    function getSlippageDenominator() external pure returns (uint24);
}