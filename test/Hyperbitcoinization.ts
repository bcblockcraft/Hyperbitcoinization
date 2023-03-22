import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { BigNumber, BigNumberish } from "ethers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ERC20, Hyperbitcoinization } from "../typechain-types";

describe("HB", async () => {
  let WBTC: ERC20;
  let USDC: ERC20;
  let HB: Hyperbitcoinization;

  const DURATION: number = time.duration.days(90);
  let END_TIMESTAMP: BigNumber;

  const WBTC_MAX_CAP = BigNumber.from(e8(3));
  const USDC_MAX_CAP = BigNumber.from(e6(3000000)); // 3M
  const CONVERSION_RATE = BigNumber.from(10000); // 1M USDC per WBTC (1M * 10^6 / 10^8)

  function e6(amount: BigNumberish): BigNumber {
    return BigNumber.from(amount).mul(BigNumber.from(10).pow(6));
  }

  function e8(amount: BigNumberish): BigNumber {
    return BigNumber.from(amount).mul(BigNumber.from(10).pow(8));
  }

  async function deployWBTCAndUSDC() {
    const DERC20Factory = await ethers.getContractFactory("DERC20");
    WBTC = await DERC20Factory.deploy(8);
    await WBTC.deployed();
    USDC = await DERC20Factory.deploy(6);
    await USDC.deployed();
  }

  async function deployHB() {
    const Factory = await ethers.getContractFactory("Hyperbitcoinization");
    HB = await Factory.deploy(
      WBTC.address,
      USDC.address,
      USDC_MAX_CAP,
      END_TIMESTAMP,
      CONVERSION_RATE
    );
    await HB.deployed();
  }

  before(async () => {
    END_TIMESTAMP = BigNumber.from(DURATION + (await time.latest())); // 90 days from now
    await deployWBTCAndUSDC();
    await deployHB();
  });

  it("should have correctly setup HB", async () => {
    const usdc = await HB.USDC();
    const wbtc = await HB.WBTC();
    const usdcMaxCap = await HB.USDC_MAX_CAP();
    const wbtcMaxCap = await HB.WBTC_MAX_CAP();
    const conversionRate = await HB.CONVERSION_RATE();
    const endTimestamp = await HB.END_TIMESTAMP();
    const isLocked = await HB.isLocked();

    expect(usdc).eq(USDC.address);
    expect(wbtc).eq(WBTC.address);
    expect(usdcMaxCap).eq(USDC_MAX_CAP);
    expect(wbtcMaxCap).eq(WBTC_MAX_CAP);
    expect(conversionRate).eq(CONVERSION_RATE);
    expect(endTimestamp).eq(END_TIMESTAMP);
    expect(isLocked).to.be.false;
  });
});
