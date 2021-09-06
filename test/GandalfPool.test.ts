import { ethers, network, deployments } from "hardhat"
import { expect } from "chai"
import { Signer, BigNumberish } from "ethers"
import { GandalfPool, IERC20Upgradeable } from "../typechain"

describe("Gandalf Pool", () => {
    let gandalfPool: GandalfPool, weth: IERC20Upgradeable, dai: IERC20Upgradeable;
    let deployer: Signer, owner: Signer, user1: Signer, wethWhale: Signer;

    const wethWhaleAddress: string = "0x56178a0d5F301bAf6CF3e1Cd53d9863437345Bf9";
    const wethAddress: string = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
    const daiAddress: string = "0x6B175474E89094C44Da98b954EedeAC495271d0F";

    beforeEach(async () => {
        [deployer, owner, user1] = await ethers.getSigners();

        await network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [wethWhaleAddress]
        });
        wethWhale = ethers.provider.getSigner(wethWhaleAddress);

        await deployments.fixture();
        
        gandalfPool = await ethers.getContract("GandalfPool");

        weth = await ethers.getContractAt("IERC20Upgradeable", wethAddress);
        dai = await ethers.getContractAt("IERC20Upgradeable", daiAddress);
    });

    describe("After deployment", () => {
        it("Allows the owner to set the Gandalf pool fee numerator", async function () {
            await gandalfPool.connect(owner).setGandalfPoolFeeNumerator(3500);
            expect(await gandalfPool.getGandalfPoolFeeNumerator()).to.equal(3500);
        });

        it("Does not allow the deployer to set the Gandalf pool fee numerator", async function () {
            await expect(gandalfPool.connect(deployer).setGandalfPoolFeeNumerator(3500)).to.be.revertedWith("Ownable: caller is not the owner")
        });

        it("Does not allow a random user to set the Gandalf pool fee numerator", async function () {
            await expect(gandalfPool.connect(user1).setGandalfPoolFeeNumerator(3500)).to.be.revertedWith("Ownable: caller is not the owner")
        });

        it("Allows the owner to set the UniswapV3 Pool Slippage Numerator", async function () {
            await gandalfPool.connect(owner).setUniswapV3PoolSlippageNumerator(2500);
            expect(await gandalfPool.getUniswapV3PoolSlippageNumerator()).to.equal(2500);
        });

        it("Does not allow the deployer to set the UniswapV3 Pool Slippage Numerator", async function () {
            await expect(gandalfPool.connect(deployer).setUniswapV3PoolSlippageNumerator(2500)).to.be.revertedWith("Ownable: caller is not the owner")
        });

        it("Does not allow a random user to set the UniswapV3 Pool Slippage Numerator", async function () {
            await expect(gandalfPool.connect(user1).setUniswapV3PoolSlippageNumerator(2500)).to.be.revertedWith("Ownable: caller is not the owner")
        });

        it("Allows the owner to set the desired tick range", async function () {
            await gandalfPool.connect(owner).setDesiredTickRange(1200);
            expect(await gandalfPool.getDesiredTickRange()).to.equal(1200);
        });

        it("Does not allow the owner to set the desired tick range to an invalid range", async function () {
            await expect(gandalfPool.connect(owner).setDesiredTickRange(0)).to.be.revertedWith("Tick range is not valid")
            await expect(gandalfPool.connect(owner).setDesiredTickRange(60)).to.be.revertedWith("Tick range is not valid")
            await expect(gandalfPool.connect(owner).setDesiredTickRange(121)).to.be.revertedWith("Tick range is not valid")
        });

        it("Does not allow the deployer to set the desired tick range", async function () {
            await expect(gandalfPool.connect(deployer).setDesiredTickRange(1200)).to.be.revertedWith("Ownable: caller is not the owner")
        });

        it("Does not allow a random user to set the desired tick range", async function () {
            await expect(gandalfPool.connect(user1).setDesiredTickRange(1200)).to.be.revertedWith("Ownable: caller is not the owner")
        });

        it("Gets the current price tick", async function () {
            expect(await gandalfPool.getCurrentPriceTick()).to.equal(-82763);
        });
        
        it("Gets token0 address", async function () {
            expect(await gandalfPool.getToken0()).to.equal(daiAddress);
        });

        it("Gets token1 address", async function () {
            expect(await gandalfPool.getToken1()).to.equal(wethAddress);
        });

        it("Gets desired tick lower", async function () {
            expect(await gandalfPool.getDesiredTickLower()).to.equal(-83040);
        });

        it("Gets desired tick upper", async function () {
            expect(await gandalfPool.getDesiredTickUpper()).to.equal(-82440);
        });

        it("Gets total value in token 0", async function () {
            expect(await gandalfPool.getTotalValueInToken0()).to.equal(0);
        });

        it("Gets total value in token 1", async function () {
            expect(await gandalfPool.getTotalValueInToken1()).to.equal(0);
        });

        it("Gets whether various tick ranges are valid", async function () {
            // Tick spacing of the pool is 60 so valid tick ranges are evenly
            // divisible by 60, and greater than or equal to (2 * 60)
            expect(await gandalfPool.getIsTickRangeValid(120)).to.equal(true);
            expect(await gandalfPool.getIsTickRangeValid(180)).to.equal(true);
            expect(await gandalfPool.getIsTickRangeValid(240)).to.equal(true);
            expect(await gandalfPool.getIsTickRangeValid(300)).to.equal(true);
            expect(await gandalfPool.getIsTickRangeValid(360)).to.equal(true);

            expect(await gandalfPool.getIsTickRangeValid(0)).to.equal(false);
            expect(await gandalfPool.getIsTickRangeValid(30)).to.equal(false);
            expect(await gandalfPool.getIsTickRangeValid(60)).to.equal(false);
            expect(await gandalfPool.getIsTickRangeValid(121)).to.equal(false);
            expect(await gandalfPool.getIsTickRangeValid(160)).to.equal(false);
        });
    });

    describe("After the first user buys gandalf tokens", () => {
        beforeEach(async () => {
            const wethAmount: BigNumberish = ethers.utils.parseUnits("1", 18);
            await weth.connect(wethWhale).approve(gandalfPool.address, wethAmount);
            await gandalfPool.connect(wethWhale).buyGandalfToken(0, wethAmount, 0, 100000000000);
        });

        it("Sent the user 1,000,000 gandalf tokens", async function () {
            expect(await gandalfPool.balanceOf(wethWhaleAddress)).to.equal(ethers.utils.parseUnits("1000000", 18));
        });

        it("Gets the liquidity position token ID", async function () {
            expect(await gandalfPool.getLiquidityPositionTokenId()).to.be.gt(0);
        });

        it("Gets the liquidity positions liquidity amount", async function () {
            expect(await gandalfPool.getLiquidityPositionLiquidityAmount()).to.be.gt(0);
        });

        it("Gets actual tick lower", async function () {
            expect(await gandalfPool.getActualTickLower()).to.equal(-83040);
        });

        it("Gets actual tick upper", async function () {
            expect(await gandalfPool.getActualTickUpper()).to.equal(-82440);
        });

        it("Gets total value in token 0", async function () {
            expect(await gandalfPool.getTotalValueInToken0()).to.be.gt(0);
        });

        it("Gets total value in token 1", async function () {
            expect(await gandalfPool.getTotalValueInToken1()).to.be.gt(0);
        });

        it("Gets gandalf token price in token 0", async function () {
            expect(await gandalfPool.getGandalfTokenPriceInToken0()).to.be.gt(0);
        });

        it("Gets gandalf token price in token 1", async function () {
            expect(await gandalfPool.getGandalfTokenPriceInToken1()).to.be.gt(0);
        });

        it("Allows the user to sell gandalf tokens for token 0 (DAI)", async function () {
            const gandalfTokenSellAmount: BigNumberish = ethers.utils.parseUnits("1000000", 18);
            const totalValueInToken0 = await gandalfPool.getTotalValueInToken0();

            const wethWhaleGandalfTokenBalanceBefore = await gandalfPool.balanceOf(wethWhaleAddress);
            const wethWhaleDaiBalanceBefore = await dai.balanceOf(wethWhaleAddress);
            const wethWhaleWethBalanceBefore = await weth.balanceOf(wethWhaleAddress);

            await gandalfPool.connect(wethWhale).sellGandalfToken(gandalfTokenSellAmount, 0, true, 2000000000);

            const wethWhaleGandalfTokenBalanceAfter = await gandalfPool.balanceOf(wethWhaleAddress);
            const wethWhaleDaiBalanceAfter = await dai.balanceOf(wethWhaleAddress);
            const wethWhaleWethBalanceAfter = await weth.balanceOf(wethWhaleAddress);

            // WETH whale should no longer have the amount of gandalf token sold
            expect(wethWhaleGandalfTokenBalanceBefore.sub(gandalfTokenSellAmount)).to.equal(wethWhaleGandalfTokenBalanceAfter);

            // Check that WETH whale received greater than 99.5% of the total value of token0 (DAI), 
            // since some slippage losses occur from swaps
            expect(wethWhaleDaiBalanceAfter.sub(wethWhaleDaiBalanceBefore)).to.be.gt(totalValueInToken0.mul(995).div(1000));

            // WETH whale token 1 (WETH) balance should remain unchanged
            expect(wethWhaleWethBalanceBefore).to.equal(wethWhaleWethBalanceAfter);
        });

        it("Allows the user to sell gandalf tokens for token 1 (WETH)", async function () {
            const gandalfTokenSellAmount: BigNumberish = ethers.utils.parseUnits("1000000", 18);
            const totalValueInToken1 = await gandalfPool.getTotalValueInToken1();

            const wethWhaleGandalfTokenBalanceBefore = await gandalfPool.balanceOf(wethWhaleAddress);
            const wethWhaleDaiBalanceBefore = await dai.balanceOf(wethWhaleAddress);
            const wethWhaleWethBalanceBefore = await weth.balanceOf(wethWhaleAddress);

            await gandalfPool.connect(wethWhale).sellGandalfToken(gandalfTokenSellAmount, 0, false, 2000000000);

            const wethWhaleGandalfTokenBalanceAfter = await gandalfPool.balanceOf(wethWhaleAddress);
            const wethWhaleDaiBalanceAfter = await dai.balanceOf(wethWhaleAddress);
            const wethWhaleWethBalanceAfter = await weth.balanceOf(wethWhaleAddress);

            // WETH whale should no longer have the amount of gandalf token sold
            expect(wethWhaleGandalfTokenBalanceBefore.sub(gandalfTokenSellAmount)).to.equal(wethWhaleGandalfTokenBalanceAfter);

            // WETH whale token 0 (DAI) balance should remain unchanged
            expect(wethWhaleDaiBalanceBefore).to.equal(wethWhaleDaiBalanceAfter);

            // Check that WETH whale received greater than 99.5% of the total value of token 1 (WETH), 
            // since some slippage losses occur from swaps
            expect(wethWhaleWethBalanceAfter.sub(wethWhaleWethBalanceBefore)).to.be.gt(totalValueInToken1.mul(995).div(1000));
        });

        it("Mints a new liquidity position with updated ticks when desired tick range is changed", async function () {
            expect(await gandalfPool.getActualTickLower()).to.equal(-83040);
            expect(await gandalfPool.getActualTickUpper()).to.equal(-82440);
            expect(await gandalfPool.getIfLiquidityPositionNeedsUpdate()).to.equal(false);

            await gandalfPool.connect(owner).setDesiredTickRange(1200);
            expect(await gandalfPool.getIfLiquidityPositionNeedsUpdate()).to.equal(true);

            await gandalfPool.connect(user1).rebalance();
            expect(await gandalfPool.getIfLiquidityPositionNeedsUpdate()).to.equal(false);

            expect(await gandalfPool.getDesiredTickRange()).to.equal(1200);
            expect(await gandalfPool.getActualTickLower()).to.equal(-83340);
            expect(await gandalfPool.getActualTickUpper()).to.equal(-82140);
        });
    });
});