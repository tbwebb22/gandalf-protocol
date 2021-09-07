// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "./interfaces/IGandalfPool.sol";

contract GandalfPool is
    Initializable,
    OwnableUpgradeable,
    ERC20Upgradeable,
    IGandalfPool
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    uint24 private constant FEE_DENOMINATOR = 1_000_000;
    uint24 private constant SLIPPAGE_DENOMINATOR = 1_000_000;
    uint24 private uniswapV3PoolFee;
    uint24 private gandalfPoolFeeNumerator;
    uint24 private uniswapV3PoolSlippageNumerator;
    uint24 private desiredTickRange;
    int24 private desiredTickLower;
    int24 private desiredTickUpper;
    uint256 private liquidityPositionTokenId;
    address private uniswapV3FactoryAddress;
    address private uniswapV3SwapRouterAddress;
    address private uniswapV3PositionManagerAddress;
    address private uniswapV3PoolAddress;
    address private token0;
    address private token1;

    modifier liquidityPositionMinted() {
        require(liquidityPositionTokenId > 0, "No liquidity position minted");
        _;
    }

    modifier nonZeroSupply() {
        require(totalSupply() > 0, "Supply must be greater than zero to calculate price");
        _;
    }

    /* ========================================================================================= */
    /*                                     External Functions                                    */
    /* ========================================================================================= */

    /// @param owner_ The address that ownership of the contract gets transferred to
    /// @param name_ The name of this contract's ERC-20 token 
    /// @param symbol_ The symbol of this contract's ERC-20 token
    /// @param uniswapV3FactoryAddress_ The address of the Uniswap v3 Factory contract
    /// @param uniswapV3SwapRouterAddress_ The address of the Uniswap v3 Swap Router contract
    /// @param uniswapV3PositionManagerAddress_ The address of the Uniswap v3 Position Manager contract
    /// @param tokenA_ The address of the unsorted token A of the Uniswap pool liquidity is being provided to
    /// @param tokenB_ The address of the unsorted token B of the Uniswap pool liquidity is being provided to
    /// @param uniswapV3PoolSlippageNumerator_ The numerator of the maximum amount of slippage to allow for swaps
    /// @param uniswapV3PoolFee_ The fee of the Uniswap pool liquidity is being provided to
    /// @param desiredTickRange_ The initial range in ticks of the liquidity range
    /// @param gandalfPoolFeeNumerator_ The fee numerator applied to all buys and sells of the gandalf token
    function initialize(
        address owner_,
        string memory name_,
        string memory symbol_,
        address uniswapV3FactoryAddress_,
        address uniswapV3SwapRouterAddress_,
        address uniswapV3PositionManagerAddress_,
        address tokenA_,
        address tokenB_,
        uint24 uniswapV3PoolSlippageNumerator_,
        uint24 uniswapV3PoolFee_,
        uint24 desiredTickRange_,
        uint24 gandalfPoolFeeNumerator_
    ) external initializer {
        __Ownable_init();
        __ERC20_init(name_, symbol_);
        transferOwnership(owner_);

        uniswapV3FactoryAddress = uniswapV3FactoryAddress_;
        uniswapV3SwapRouterAddress = uniswapV3SwapRouterAddress_;
        uniswapV3PositionManagerAddress = uniswapV3PositionManagerAddress_;
        uniswapV3PoolFee = uniswapV3PoolFee_;
        uniswapV3PoolAddress = IUniswapV3Factory(uniswapV3FactoryAddress_).getPool(tokenA_, tokenB_, uniswapV3PoolFee_);

        require(uniswapV3PoolAddress != address(0), "Pool does not exist");

        _setGandalfPoolFeeNumerator(gandalfPoolFeeNumerator_);
        _setUniswapV3PoolSlippageNumerator(uniswapV3PoolSlippageNumerator_);
        _setDesiredTickRange(desiredTickRange_);

        (token0, token1) = getTokensSorted(tokenA_, tokenB_);

        IERC20Upgradeable(token0).approve(uniswapV3SwapRouterAddress_, type(uint256).max);
        IERC20Upgradeable(token0).approve(uniswapV3PositionManagerAddress_, type(uint256).max);
        IERC20Upgradeable(token1).approve(uniswapV3SwapRouterAddress_, type(uint256).max);
        IERC20Upgradeable(token1).approve(uniswapV3PositionManagerAddress_, type(uint256).max);
    }

    /// @notice Allows the user to buy gandalf token using any amount of token0 and token1
    /// @notice The Amount of gandalf token the user receives represents their share of the liquidity position
    /// @param token0Amount The amount of token 0 the user wants to spend to buy the Gandalf token
    /// @param token1Amount The amount of token 1 the user wants to spend to buy the Gandalf token
    /// @param minGandalfTokenAmount The minimum amount of the Gandalf token the user is willing to receive
    /// @param deadline The timestamp at which the transaction will expire
    function buyGandalfToken(uint256 token0Amount, uint256 token1Amount, uint256 minGandalfTokenAmount, uint256 deadline) external override {
        require(token0Amount.add(token1Amount) > 0, "Sum of token amounts must be greater than zero");
        require(deadline >= block.timestamp, "Transaction deadline expired");

        uint256 gandalfTokenAmountToReceive;
        if(getTotalValueInToken0() > 0) {
            uint256 totalValueInToken0Before = getTotalValueInToken0();

            _transferTokensFromUser(token0Amount, token1Amount);
            
            uint256 totalValueInToken0After = getTotalValueInToken0();

            gandalfTokenAmountToReceive = (totalValueInToken0After.sub(totalValueInToken0Before)).mul(totalSupply()).mul((FEE_DENOMINATOR - gandalfPoolFeeNumerator)).div(totalValueInToken0Before).div(FEE_DENOMINATOR);
        } else {
            _transferTokensFromUser(token0Amount, token1Amount);

            gandalfTokenAmountToReceive = 1_000_000 * 10 ** decimals();
        }

        require(gandalfTokenAmountToReceive >= minGandalfTokenAmount, "Minimum gandalf token amount cannot be met");

        _mint(msg.sender, gandalfTokenAmountToReceive);

        _rebalance();
    }

    /// @notice Allows a user to sell their gandalf tokens for their share of the liquidity position
    /// @notice And receive either token0 or token1 in return
    /// @param gandalfTokenAmount The amount of Gandalf token the user wants to sell
    /// @param minTokenAmountToReceive The minimum amount of token0 or token1 the user is willing to receive
    /// @param receiveInToken0 Boolean indicating whether the user wants to receive token0 or token1
    /// @param deadline The timestamp at which the transaction will expire
    function sellGandalfToken(uint256 gandalfTokenAmount, uint256 minTokenAmountToReceive, bool receiveInToken0, uint256 deadline) external override {
        require(deadline >= block.timestamp, "Transaction deadline expired");

        uint256 tokenAmountToReceiveBeforeFee = getTokenAmountToReceiveFromSell(gandalfTokenAmount, receiveInToken0);
        
        uint128 decreaseLiquidityAmount = uint128(uint256(getLiquidityPositionLiquidityAmount()).mul(gandalfTokenAmount).div(totalSupply()));

        _decreaseLiquidityPosition(decreaseLiquidityAmount);

        _collect();

        (address tokenIn, address tokenOut) = receiveInToken0 ? (token1, token0) : (token0, token1);

        _swapExactInput(tokenIn, tokenOut, IERC20Upgradeable(tokenIn).balanceOf(address(this)));

        if(tokenAmountToReceiveBeforeFee > IERC20Upgradeable(tokenOut).balanceOf(address(this))) {
            tokenAmountToReceiveBeforeFee = IERC20Upgradeable(tokenOut).balanceOf(address(this));
        }

        uint256 tokenAmountToReceiveAfterFee = tokenAmountToReceiveBeforeFee.mul(FEE_DENOMINATOR - gandalfPoolFeeNumerator).div(FEE_DENOMINATOR);
      
        require(tokenAmountToReceiveAfterFee >= minTokenAmountToReceive, "Minimum token amount cannot be met");

        IERC20Upgradeable(tokenOut).safeTransfer(msg.sender, tokenAmountToReceiveAfterFee);

        _burn(msg.sender, gandalfTokenAmount);

        _rebalance();
    }

    /// @notice Rebalances the liquidity position by collecting fees, moving desired liquidity range ticks if needed,
    /// @notice Making swaps between token0 and token1 if needed, and adding to liquidity position if funds are available
    function rebalance() external override {
        _rebalance();
    }

    /* ========================================================================================= */
    /*                             External onlyOwner Functions                                  */
    /* ========================================================================================= */

    /// @notice Allows the owner to set a new Gandalf Pool Fee Numerator
    /// @param gandalfPoolFeeNumerator_ The new Gandalf Pool Fee Numerator
    function setGandalfPoolFeeNumerator(uint24 gandalfPoolFeeNumerator_) external override onlyOwner {
        _setGandalfPoolFeeNumerator(gandalfPoolFeeNumerator_);
    }

    /// @notice Allows the owner to set a new Uniswap v3 Pool Slippage Numerator
    /// @param uniswapV3PoolSlippageNumerator_ The new Uniswap v3 Pool Slippage Numerator
    function setUniswapV3PoolSlippageNumerator(uint24 uniswapV3PoolSlippageNumerator_) external override onlyOwner {
        _setUniswapV3PoolSlippageNumerator(uniswapV3PoolSlippageNumerator_);
    }

    /// @notice Allows the owner to set a new Desired Tick Range
    /// @param desiredTickRange_ The new Desired Tick Range
    function setDesiredTickRange(uint24 desiredTickRange_) external override onlyOwner {
        _setDesiredTickRange(desiredTickRange_);
    }

    /* ========================================================================================= */
    /*                                    Private Functions                                      */
    /* ========================================================================================= */

    /// @notice Transfers token0 and token1 amounts from user to this contract
    /// @param token0Amount The amount of token0 to transfer from the user to this contract
    /// @param token1Amount The amount of token1 to transfer from the user to this contract
    function _transferTokensFromUser(uint256 token0Amount, uint256 token1Amount) private {
        if(token0Amount > 0) {
            IERC20Upgradeable(token0).safeTransferFrom(msg.sender, address(this), token0Amount);
        }

        if(token1Amount > 0) {
            IERC20Upgradeable(token1).safeTransferFrom(msg.sender, address(this), token1Amount);
        }
    }

    /// @notice Sets a new Gandalf Pool Fee Numerator
    /// @param gandalfPoolFeeNumerator_ The new Gandalf Pool Fee Numerator
    function _setGandalfPoolFeeNumerator(uint24 gandalfPoolFeeNumerator_) private {
        require(gandalfPoolFeeNumerator_ != gandalfPoolFeeNumerator, 
            "Gandalf Pool Fee Numerator must be set to a new value");
        require(gandalfPoolFeeNumerator_ <= FEE_DENOMINATOR, 
            "Gandalf Pool Fee Numerator must be less than FEE_DENOMINATOR");

        gandalfPoolFeeNumerator = gandalfPoolFeeNumerator_;
    }

    /// @notice Sets a new Uniswap v3 Pool Slippage Numerator
    /// @param uniswapV3PoolSlippageNumerator_ The new Uniswap v3 Pool Slippage Numerator
    function _setUniswapV3PoolSlippageNumerator(uint24 uniswapV3PoolSlippageNumerator_) private {
        require(uniswapV3PoolSlippageNumerator_ != uniswapV3PoolSlippageNumerator, 
            "Uniswap v3 Pool Slippage Numerator must be set to a new value");
        require(uniswapV3PoolSlippageNumerator_ <= SLIPPAGE_DENOMINATOR, 
            "uniswapV3PoolSlippageNumerator must be less than or equal to SLIPPAGE_DENOMINATOR");

        uniswapV3PoolSlippageNumerator = uniswapV3PoolSlippageNumerator_;
    }

    /// @notice Sets a new Desired Tick Range
    /// @param desiredTickRange_ The new Desired Tick Range
    function _setDesiredTickRange(uint24 desiredTickRange_) private {
        require(desiredTickRange_ != desiredTickRange, 
            "Desired Tick Range must be set to a new value");
        require(getIsTickRangeValid(desiredTickRange_), "Tick range is not valid");

        desiredTickRange = desiredTickRange_;
        _moveDesiredTicks();
    }   

    /// @notice Calculates the desired amounts of token0 and token1 to add liquidity,
    /// @notice then makes the necessary swaps and adds liquidity or mints a new position
    function _makeSwapsAndAddLiquidity() private {
        uint256 actualToken0Amount = IERC20Upgradeable(token0).balanceOf(address(this));
        uint256 actualToken1Amount = IERC20Upgradeable(token1).balanceOf(address(this));

        (uint256 desiredToken0Amount, uint256 desiredToken1Amount) = getDesiredReserveAmounts();

        if(desiredToken0Amount > actualToken0Amount && desiredToken1Amount < actualToken1Amount) {
            // Swap token1 for token0
            _swapExactInput(token1, token0, actualToken1Amount.sub(desiredToken1Amount));
        } else if (desiredToken0Amount < actualToken0Amount && desiredToken1Amount > actualToken1Amount) {
            // Swap token0 for token1
            _swapExactInput(token0, token1, actualToken0Amount.sub(desiredToken0Amount));
        }

        if(liquidityPositionTokenId > 0) {
            _increaseLiquidityPosition();
        } else {
            _mintLiquidityPosition();
        }
    }

    /// @notice Mints a new liquidity position
    function _mintLiquidityPosition() private {
        INonfungiblePositionManager.MintParams memory mintParams;

        mintParams.token0 = token0;
        mintParams.token1 = token1;
        mintParams.fee = uniswapV3PoolFee;
        mintParams.tickLower = desiredTickLower;
        mintParams.tickUpper = desiredTickUpper;
        mintParams.amount0Desired = IERC20Upgradeable(token0).balanceOf(address(this));
        mintParams.amount1Desired = IERC20Upgradeable(token1).balanceOf(address(this));
        mintParams.amount0Min = 0;
        mintParams.amount1Min = 0;
        mintParams.recipient = address(this);
        mintParams.deadline = block.timestamp;

        (liquidityPositionTokenId,,,) = INonfungiblePositionManager(uniswapV3PositionManagerAddress).mint(mintParams);
    }

    /// @notice Increases liquidity on an existing liquidity position
    function _increaseLiquidityPosition() private {
        INonfungiblePositionManager.IncreaseLiquidityParams memory increaseLiquidityParams;

        increaseLiquidityParams.tokenId = liquidityPositionTokenId;
        increaseLiquidityParams.amount0Desired = IERC20Upgradeable(token0).balanceOf(address(this));
        increaseLiquidityParams.amount1Desired = IERC20Upgradeable(token1).balanceOf(address(this));
        increaseLiquidityParams.amount0Min = 0;
        increaseLiquidityParams.amount1Min = 0;
        increaseLiquidityParams.deadline = block.timestamp;

        INonfungiblePositionManager(uniswapV3PositionManagerAddress).increaseLiquidity(increaseLiquidityParams);
    }

    /// @notice Decreases liquidity on an existing liquidity position
    /// @param liquidityAmount The amount of liquidity to decrease the position by
    function _decreaseLiquidityPosition(uint128 liquidityAmount) private {  
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams;

        decreaseLiquidityParams.tokenId = liquidityPositionTokenId;
        decreaseLiquidityParams.liquidity = liquidityAmount;
        decreaseLiquidityParams.amount0Min = 0;
        decreaseLiquidityParams.amount1Min = 0;
        decreaseLiquidityParams.deadline = block.timestamp; 

        INonfungiblePositionManager(uniswapV3PositionManagerAddress).decreaseLiquidity(decreaseLiquidityParams);
    }

    /// @notice Collects fees that have been earned from liquidity position
    function _collect() private {
        INonfungiblePositionManager.CollectParams memory collectParams;

        collectParams.tokenId = liquidityPositionTokenId;
        collectParams.recipient = address(this);
        collectParams.amount0Max = type(uint128).max;
        collectParams.amount1Max = type(uint128).max;

        INonfungiblePositionManager(uniswapV3PositionManagerAddress).collect(collectParams);
    }

    /// @notice Swaps an exact amount of tokenIn for tokenOut
    /// @param tokenIn The address of the token being swapped
    /// @param tokenOut The address of the token being swapped ford
    /// @param amountIn The amount of tokenIn being swapped
    function _swapExactInput(address tokenIn,address tokenOut, uint256 amountIn) private {
        uint256 amountOutMinimum = getAmountOutMinimum(tokenIn, tokenOut, amountIn);

        ISwapRouter.ExactInputSingleParams memory exactInputSingleParams;

        exactInputSingleParams.tokenIn = tokenIn;
        exactInputSingleParams.tokenOut = tokenOut;
        exactInputSingleParams.fee = uniswapV3PoolFee;
        exactInputSingleParams.recipient = address(this);
        exactInputSingleParams.deadline = block.timestamp;
        exactInputSingleParams.amountIn = amountIn;
        exactInputSingleParams.amountOutMinimum = amountOutMinimum;
        exactInputSingleParams.sqrtPriceLimitX96 = 0;

        ISwapRouter(uniswapV3SwapRouterAddress).exactInputSingle(exactInputSingleParams);
    }

    /// @notice Rebalances the liquidity position by collecting fees, moving desired liquidity range ticks if needed,
    /// @notice Making swaps between token0 and token1 if needed, and adding to liquidity position if funds are available
    function _rebalance() private {
        if(liquidityPositionTokenId > 0) {
            _collect();

            if(getIfLiquidityPositionNeedsUpdate()) {
                _closeLiquidityPosition();
                _moveDesiredTicks();
            }
        } else {
            if(!getPriceInDesiredLiquidityRange()) {
                _moveDesiredTicks();
            }
        }

        if(IERC20Upgradeable(token0).balanceOf(address(this)) > 0 || IERC20Upgradeable(token1).balanceOf(address(this)) > 0) {
            _makeSwapsAndAddLiquidity();
        }
    }

    /// @notice Closes a liquidity position and collects all of token0 and token1 received,
    /// @notice Then sets the liquidity position token ID back to zero
    function _closeLiquidityPosition() private {
        _decreaseLiquidityPosition(getLiquidityPositionLiquidityAmount());
        _collect();
        liquidityPositionTokenId = 0;
    }

    /// @notice Moves the desired ticks based upon the current price and the desired tick range
    function _moveDesiredTicks() private {
        (desiredTickLower, desiredTickUpper) = getNewDesiredTicks();
    }

    /* ========================================================================================= */
    /*                             Public View & Public Pure Functions                           */
    /* ========================================================================================= */

    /// @notice Gets the estimated amount of token0 or token1 user will receive when selling
    /// @notice the specified amount of Gandalf Token
    /// @param gandalfTokenAmountSold The amount of Gandalf Token being sold
    /// @param receiveInToken0 Boolean indicating whether the user wants to receive token0 or token1
    /// @return maxTokenAmountToReceive The max amount of the token the user could receive from sell
    function getTokenAmountToReceiveFromSell(uint256 gandalfTokenAmountSold, bool receiveInToken0) public view override returns (uint256 maxTokenAmountToReceive) {
        if(receiveInToken0) {
            maxTokenAmountToReceive = getTotalValueInToken0().mul(gandalfTokenAmountSold).div(totalSupply());
        } else {
            maxTokenAmountToReceive = getTotalValueInToken1().mul(gandalfTokenAmountSold).div(totalSupply());
        }
    }

    /// @notice Returns the current price of the Uniswap pool represented as a tick
    /// @return The tick of the current price
    function getCurrentPriceTick() public view override returns (int24) {
        return TickMath.getTickAtSqrtRatio(getSqrtPriceX96());
    }

    /// @notice Gets the current price represented as a tick, rounded according to the tick spacing
    /// @return The current price tick rounded
    function getCurrentPriceTickRounded() public view override returns (int24) {
        int24 currentPriceTick = getCurrentPriceTick();
        return currentPriceTick - (currentPriceTick % getTickSpacing());
    }

    /// @notice Gets the tick spacing of the Uniswap pool
    /// @return The pool tick spacing
    function getTickSpacing() public view override returns (int24) {
        return IUniswapV3Factory(uniswapV3FactoryAddress).feeAmountTickSpacing(uniswapV3PoolFee);
    }

    /// @notice Gets the desired tickLower and tickUpper based on the current price and the desiredTickRange
    /// @return newDesiredTickLower The new tick lower desired for the liquidity position
    /// @return newDesiredTickUpper The new tick upper desired for the liquidity position
    function getNewDesiredTicks() public view override returns (int24 newDesiredTickLower, int24 newDesiredTickUpper) {
        int24 currentPriceTickRounded = getCurrentPriceTickRounded();

        newDesiredTickLower = currentPriceTickRounded - int24(desiredTickRange / 2);
        newDesiredTickUpper = currentPriceTickRounded + int24(desiredTickRange / 2);

        require(newDesiredTickLower >= TickMath.MIN_TICK, "Tick lower is below MIN_TICK");
        require(newDesiredTickUpper <= TickMath.MAX_TICK, "Tick upper is above MAX_TICK");
    }

    /// @notice Returns whether the liquidity position needs an update
    /// @notice This can return true when the price has moved outside of the current liquidity position range,
    /// @notice or when the desired tick range has been updated by the owner
    /// @return bool Indicates whether the liquidity position needs to be updated
    function getIfLiquidityPositionNeedsUpdate() public view override returns (bool) {
        return((!getPriceInActualLiquidityRange()) || (desiredTickLower != getActualTickLower()) || (desiredTickUpper != getActualTickUpper()));
    }

    /// @notice Returns whether the current Uniswap pool price is within the liquidity position range
    /// @return priceInLiquidityRange Returns true if the current price is within the liquidity position range
    function getPriceInActualLiquidityRange() public view override returns (bool priceInLiquidityRange) {
        int24 currentPriceTick = TickMath.getTickAtSqrtRatio(getSqrtPriceX96());

        if(getActualTickLower() <= currentPriceTick && currentPriceTick <= getActualTickUpper()) {
            priceInLiquidityRange = true;
        } else {
            priceInLiquidityRange = false;
        }
    }

    /// @notice Returns whether the current Uniswap pool price within the desired liquidity position range
    /// @return priceInLiquidityRange Returns true if the current price within the desired liquidity position range
    function getPriceInDesiredLiquidityRange() public view override returns (bool priceInLiquidityRange) {
        int24 currentPriceTick = TickMath.getTickAtSqrtRatio(getSqrtPriceX96());

        if(desiredTickLower <= currentPriceTick && currentPriceTick <= desiredTickUpper) {
            priceInLiquidityRange = true;
        } else {
            priceInLiquidityRange = false;
        }
    }

    /// @notice Returns the current sqrtPriceX96 of the Uniswap pool
    /// @return sqrtPriceX96 The current price of the Uniswap pool
    function getSqrtPriceX96() public view override returns (uint160 sqrtPriceX96) {
        (sqrtPriceX96,,,,,,) = IUniswapV3Pool(uniswapV3PoolAddress).slot0();
    }

    /// @notice Gets the estimated token amount out from a swap. This calculation takes into account
    /// @notice the pool fee, but assumes that no slippage occurs
    /// @param tokenIn The address of the token being swapped
    /// @param tokenOut The address of the token being swapped for
    /// @param amountIn The amount of tokenIn being swapped
    /// @param fee The fee to apply to the estimated swap
    /// @return amountOut The estimated amount of tokenOut that will be received from the swap
    function getEstimatedTokenOut(address tokenIn, address tokenOut, uint256 amountIn, uint24 fee) public view override returns (uint256 amountOut) {
        uint256 sqrtPriceX96 = getSqrtPriceX96();

        if(tokenIn < tokenOut) {
            amountOut = FullMath.mulDiv(FullMath.mulDiv(amountIn, sqrtPriceX96, 2**96), sqrtPriceX96, 2**96) 
                .mul(FEE_DENOMINATOR - fee).div(FEE_DENOMINATOR);
        } else {
            amountOut = FullMath.mulDiv(FullMath.mulDiv(amountIn, 2**96, sqrtPriceX96), 2**96, sqrtPriceX96)
                .mul(FEE_DENOMINATOR - fee).div(FEE_DENOMINATOR);
        }
    }

    /// @notice Gets the amount out minimum to use for a swap, according to the configured allowable slippage numerator
    /// @param tokenIn The address of the token being swapped
    /// @param tokenOut The address of the token being swapped for
    /// @param amountIn The amount of tokenIn being swapped
    /// @return amountOutMinimum The minimum amount of tokenOut to use for the swap
    function getAmountOutMinimum(address tokenIn, address tokenOut, uint256 amountIn) public view override returns (uint256 amountOutMinimum) {
        uint256 estimatedAmountOut = getEstimatedTokenOut(tokenIn, tokenOut, amountIn, uniswapV3PoolFee);

        amountOutMinimum = estimatedAmountOut.mul(SLIPPAGE_DENOMINATOR - uniswapV3PoolSlippageNumerator).div(SLIPPAGE_DENOMINATOR);
    }

    /// @notice Gets the value of token0 and token1 held by this contract in terms of token0 value
    /// @return The reserve value relative to token0
    function getReserveValueInToken0() public view override returns (uint256) {
        uint256 token0Balance = IERC20Upgradeable(token0).balanceOf(address(this));
        uint256 token1Balance = IERC20Upgradeable(token1).balanceOf(address(this));

        return token0Balance.add(getEstimatedTokenOut(token1, token0, token1Balance, uniswapV3PoolFee));
    }

    /// @notice Gets the value of token0 and token1 held by the liquidity position in terms of token0 value
    /// @return The liquidity position value relative to token0    
    function getLiquidityPositionValueInToken0() public view override returns (uint256) {
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            getSqrtPriceX96(),
            TickMath.getSqrtRatioAtTick(desiredTickLower),
            TickMath.getSqrtRatioAtTick(desiredTickUpper),
            getLiquidityPositionLiquidityAmount()
        );

        return amount0.add(getEstimatedTokenOut(token1, token0, amount1, 0));
    }

    /// @notice Gets the total value (reserves + liquidity position) in terms of token 0 value
    /// @return The total value relative to token0
    function getTotalValueInToken0() public view override returns (uint256) {
        return getReserveValueInToken0().add(getLiquidityPositionValueInToken0());
    }

    /// @notice Gets the total value (reserves + liquidity position) in terms of token 0 value
    /// @return The total value relative to token0
    function getTotalValueInToken1() public view override returns (uint256) {
        return getEstimatedTokenOut(token0, token1, getTotalValueInToken0(), 0);
    }

    /// @notice Returns the total liquidity amount held by the current liquidity position
    /// @return liquidityAmount The liquidity amount of the current liquidity position
    function getLiquidityPositionLiquidityAmount() public view override returns (uint128 liquidityAmount) {
        if(liquidityPositionTokenId > 0) {
            ( , , , , , , , liquidityAmount, , , ,) = INonfungiblePositionManager(uniswapV3PositionManagerAddress)
                .positions(liquidityPositionTokenId);
        } else {
            liquidityAmount = 0;
        }
    }

    /// @notice Returns the desired reserve amounts of token0 and token1 that are needed
    /// @notice to add the maximum amount of liquidity to the current liquidity position
    /// @param token0Amount The desired amount of token0
    /// @param token1Amount The desired amount of token1
    function getDesiredReserveAmounts() public view override returns (uint256 token0Amount, uint256 token1Amount) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(desiredTickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(desiredTickUpper);

        uint128 liquidityAmount = LiquidityAmounts.getLiquidityForAmount0(
            sqrtRatioAX96,
            sqrtRatioBX96,
            getReserveValueInToken0()
        );

        (token0Amount, token1Amount) = LiquidityAmounts.getAmountsForLiquidity(
            getSqrtPriceX96(),
            sqrtRatioAX96,
            sqrtRatioBX96,
            liquidityAmount
        );
    }

    /// @notice Returns whether the specified tick range is valid. For the tick range to be valid, it needs to be evenly
    /// @notice divisible by the tick spacing, and be greater than or equal to (tickSpacing * 2)
    function getIsTickRangeValid(uint24 tickRange) public view override returns (bool) {
        uint24 tickSpacing = uint24(IUniswapV3Factory(uniswapV3FactoryAddress).feeAmountTickSpacing(uniswapV3PoolFee));

        return(tickRange % tickSpacing == 0 && tickRange >= 2 * tickSpacing);
    }

    /// @notice Returns the pool fee of the Uniswap pool liquidity is being provided to
    /// @return The Uniswap pool fee
    function getUniswapV3PoolFee() public view override returns (uint24) {
        return uniswapV3PoolFee;
    }

    /// @notice Returns the Gandalf pool fee numerator, that gets divided by FEE_DENOMINATOR
    /// @notice to calculate the fee percentage
    /// @return The Gandalf Pool Fee Numerator
    function getGandalfPoolFeeNumerator() public view override returns (uint24) {
        return gandalfPoolFeeNumerator;
    }

    /// @notice Returns the Gandalf pool fee numerator, that gets divided by SLIPPAGE_DENOMINATOR
    /// @notice to calculate the slippage percentage
    /// @return The Uniswap Pool Slippage Numerator   
    function getUniswapV3PoolSlippageNumerator() public view override returns (uint24) {
        return uniswapV3PoolSlippageNumerator;
    }

    /// @notice Returns the desired tick range
    /// @return The desired tick range
    function getDesiredTickRange() public view override returns (uint24) {
        return desiredTickRange;
    }

    /// @notice Returns the desired tick lower
    /// @return The desired tick lower
    function getDesiredTickLower() public view override returns (int24) {
        return desiredTickLower;
    }

    /// @notice Returns the desired tick upper
    /// @return The desired tick upper
    function getDesiredTickUpper() public view override returns (int24) {
        return desiredTickUpper;
    }

    /// @notice Returns the actual tick lower of the current liquidity position
    /// @return actualTickLower The actual tick lower of the current liquidity position
    function getActualTickLower() public view override liquidityPositionMinted returns (int24 actualTickLower) {
        (,,,,, actualTickLower,,,,,,) = INonfungiblePositionManager(uniswapV3PositionManagerAddress)
            .positions(liquidityPositionTokenId);
    }

    /// @notice Returns the actual tick upper of the current liquidity position
    /// @return actualTickUpper The actual tick upper of the current liquidity position
    function getActualTickUpper() public view override liquidityPositionMinted returns (int24 actualTickUpper) {
        (,,,,,, actualTickUpper,,,,,) = INonfungiblePositionManager(uniswapV3PositionManagerAddress)
            .positions(liquidityPositionTokenId);
    }

    /// @notice Returns the token ID of the current liquidity position
    /// @return The token ID of the current liquidity position
    function getLiquidityPositionTokenId() public view override liquidityPositionMinted returns (uint256) {
        return liquidityPositionTokenId;
    }

    /// @notice Returns the address of the Uniswap v3 Factory Address
    /// @return The Uniswap v3 Factory Address
    function getUniswapV3FactoryAddress() public view override returns (address) {
        return uniswapV3FactoryAddress;
    }

    /// @notice Returns the Uniswap v3 Swap Router Address
    /// @return The Uniswap v3 Swap Router Address
    function getUniswapV3SwapRouterAddress() public view override returns (address) {
        return uniswapV3SwapRouterAddress;
    }

    /// @notice Returns the Uniswap v3 Position Manager Address
    /// @return The Uniswap v3 Position Manager Address
    function getUniswapV3PositionManagerAddress() public view override returns (address) {
        return uniswapV3PositionManagerAddress;
    }

    /// @notice Returns the Uniswap v3 Pool Address
    /// @return The Uniswap v3 Pool Address
    function getUniswapV3PoolAddress() public view override returns (address) {
        return uniswapV3PoolAddress;
    }

    /// @notice Returns the address of token 0 of the Uniswap pool
    /// @return The token 0 address
    function getToken0() public view override returns (address) {
        return token0;
    }

    /// @notice Returns the address of token 1 of the Uniswap pool
    /// @return The token 1 address
    function getToken1() public view override returns (address) {
        return token1;
    }

    /// @notice Returns the price of the Gandalf token relative to token 0 scaled by 10^18
    /// @return The price in token 0 scaled by 10^18
    function getGandalfTokenPriceInToken0() public view override nonZeroSupply returns (uint256) {
        return getTotalValueInToken0().mul(10 ** decimals()).div(totalSupply());
    }

    /// @notice Returns the price of the Gandalf token relative to token 1 scaled by 10^18
    /// @return The price in token 1 scaled by 10^18
    function getGandalfTokenPriceInToken1() public view override nonZeroSupply returns (uint256) {
        return getTotalValueInToken1().mul(10 ** decimals()).div(totalSupply());
    }

    /// @notice Returns the fee denominator constant
    /// @return The fee denominator constant
    function getFeeDenominator() public pure override returns (uint24) {
        return FEE_DENOMINATOR;
    }

    /// @notice Takes the address of two unsorted tokens and returns the tokens sorted for use with Uniswap v3
    /// @param tokenA The address of the first unsorted token
    /// @param tokenB The address of the second unsorted token
    /// @return token0_ The address of the sorted token 0
    /// @return token1_ The address of the sorted token 1
    function getTokensSorted(address tokenA, address tokenB) public pure override returns (address token0_, address token1_) {
        (token0_, token1_) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /// @notice Returns the slippage denominator used for calculating the allowable slippage percentage
    /// @return The slippage denominator
    function getSlippageDenominator() public pure override returns (uint24) {
        return SLIPPAGE_DENOMINATOR;
    }
}