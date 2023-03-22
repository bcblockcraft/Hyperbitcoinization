import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { BigNumber, BigNumberish } from "ethers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  ERC20,
  Hyperbitcoinization,
  Oracle__factory,
} from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { deployMockContract, MockContract } from "ethereum-waffle";

describe("HB", async () => {
  let WBTC: ERC20;
  let USDC: ERC20;
  let HB: Hyperbitcoinization;
  let main: SignerWithAddress;
  let users: SignerWithAddress[];
  let oracle: MockContract;

  const DURATION: number = time.duration.days(90);
  let END_TIMESTAMP: BigNumber;

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

    users.forEach(async (user) => {
      await WBTC.connect(main).transfer(user.address, e8(1000000000));
      await USDC.connect(main).transfer(user.address, e6(10000000000000));
    });
  }

  async function deployHB() {
    const Factory = await ethers.getContractFactory("Hyperbitcoinization");
    HB = await Factory.deploy(
      WBTC.address,
      USDC.address,
      oracle.address,
      END_TIMESTAMP,
      CONVERSION_RATE
    );
    await HB.deployed();

    users.forEach(async (user) => {
      const wbtcBalance = await WBTC.balanceOf(user.address);
      const usdcBalance = await USDC.balanceOf(user.address);

      await WBTC.connect(user).approve(HB.address, wbtcBalance);
      await USDC.connect(user).approve(HB.address, usdcBalance);
    });
  }

  async function setup() {
    users = await ethers.getSigners();
    main = users[0];
    END_TIMESTAMP = BigNumber.from(DURATION + (await time.latest())); // 90 days from now
    oracle = await deployMockContract(main, Oracle__factory.abi);
    await deployWBTCAndUSDC();
    await deployHB();
  }

  async function testSetup() {
    const usdc = await HB.usdc();
    const wbtc = await HB.btc();
    const conversionRate = await HB.conversionRate();
    const endTimestamp = await HB.endTimestamp();

    expect(usdc).eq(USDC.address);
    expect(wbtc).eq(WBTC.address);
    expect(conversionRate).eq(CONVERSION_RATE);
    expect(endTimestamp).eq(END_TIMESTAMP);
  }

  describe("S 1", async () => {
    before(async () => {
      await setup();
    });
    it("should setup", async () => {
      await testSetup();
    });
    it("should deposit wbtc", async () => {
      // user 0 -> 1 btc

      await HB.connect(users[0]).depositBtc(e8(1));
      const btcInBet = await HB.btcInBet(users[0].address);

      expect(btcInBet).eq(0);
    });

    it("should not be able to claim", async () => {
      const tx = HB.connect(users[0]).claim(users[0].address);
      await expect(tx).to.be.revertedWithCustomError(HB, "NotFinished");
    });

    it("should deposit usdc", async () => {
      // user 0 -> 1m usdc

      const amount = e6(1000000);
      await HB.connect(users[0]).depositUsdc(amount);
      const balance = await HB.usdcBalance(users[0].address);
      const totalUsdc = await HB.usdcTotalDeposits();
      const accUsdc = await HB.usdcAccumulator(0);
      const accDeposit = await HB.usdcDepositAccumulator(users[0].address, 0);

      expect(balance).eq(amount);
      expect(totalUsdc).eq(amount);
      expect(accUsdc).eq(amount);

      expect(accDeposit.userAcc).eq(amount);
      expect(accDeposit.globalAcc).eq(amount);
      expect(accDeposit.deposit).eq(amount);
    });

    it("user 0 should have 1btc and 1m usdc in bet (against himself)", async () => {
      const usdcInBet = await HB.usdcInBet(users[0].address);
      const btcInBet = await HB.btcInBet(users[0].address);

      expect(usdcInBet).eq(e6(1000000));
      expect(btcInBet).eq(e8(1));
    });

    it("should make second deposit", async () => {
      // user 0 -> +1m usdc (2m usdc total)

      const amount = e6(1000000);
      await HB.connect(users[0]).depositUsdc(amount);
      const balance = await HB.usdcBalance(users[0].address);
      const totalUsdc = await HB.usdcTotalDeposits();
      // const accUsdc = await HB.usdcAccBalance(1);
      const accDeposit = await HB.usdcDepositAccumulator(users[0].address, 1);

      expect(balance).eq(amount.mul(2));
      expect(totalUsdc).eq(amount.mul(2));
      // expect(accUsdc).eq(amount.mul(2));

      expect(accDeposit.userAcc).eq(amount.mul(2));
      expect(accDeposit.globalAcc).eq(amount.mul(2));
      expect(accDeposit.deposit).eq(amount);
    });

    it("user 0 should have 1btc and 1m usdc in bet (against himself) again", async () => {
      const usdcInBet = await HB.usdcInBet(users[0].address);
      const btcInBet = await HB.btcInBet(users[0].address);

      expect(usdcInBet).eq(e6(1000000));
      expect(btcInBet).eq(e8(1));
    });

    it("should allow user 1 to deposit 2btc", async () => {
      // user 1 -> 2btc
      const tx = await HB.connect(users[1]).depositBtc(e8(2));
    });

    it("should get correct in bet", async () => {
      // 3btc(user0: 1, user1: 2) vs $2m (user0: 2)
      const user0usdcInBet = await HB.usdcInBet(users[0].address);
      const user0btcInBet = await HB.btcInBet(users[0].address);

      const user1usdcInBet = await HB.usdcInBet(users[1].address);
      const user1btcInBet = await HB.btcInBet(users[1].address);

      expect(user0usdcInBet).eq(e6(2000000));
      expect(user0btcInBet).eq(e8(1));

      expect(user1usdcInBet).eq(0);
      expect(user1btcInBet).eq(e8(1));
    });

    it("should finish the bet", async () => {
      await time.increase(DURATION);
      await oracle.mock.decimals.returns(8);
      await oracle.mock.latestAnswer.returns(e8(1000000 - 1));
      await HB.setWinnerToken();
    });

    it("should let user 0 keep 1 btc and $1m", async () => {
      // 3btc(user0: 1, user1: 2) vs $2m (user0: 2)

      const beforeWBTC = await WBTC.balanceOf(users[0].address);
      const beforeUSDC = await USDC.balanceOf(users[0].address);

      await HB.connect(users[0]).claim(users[0].address);

      const afterWBTC = await WBTC.balanceOf(users[0].address);
      const afterUSDC = await USDC.balanceOf(users[0].address);

      expect(afterUSDC.sub(beforeUSDC)).eq(e6(1000000));
      expect(afterWBTC.sub(beforeWBTC)).eq(e8(1));
    });
  });

  describe("S 2", async () => {
    before(async () => {
      await setup();
    });
    it("should calculate usdc amount in bet", async () => {
      await HB.connect(users[0]).depositUsdc(e6(10000000));
      await HB.connect(users[1]).depositUsdc(e6(7000000));
      await HB.connect(users[2]).depositUsdc(e6(8000000));
      await HB.connect(users[0]).depositUsdc(e6(5000000));
      await HB.connect(users[3]).depositUsdc(e6(10000000));
      await HB.connect(users[0]).depositUsdc(e6(15000000));
      await HB.connect(users[0]).depositUsdc(e6(5000000));

      await HB.connect(users[4]).depositBtc(e8(7));
      expect(await HB.usdcInBet(users[0].address)).eq(e6(7000000));
      await HB.connect(users[4]).depositBtc(e8(13));
      expect(await HB.usdcInBet(users[0].address)).eq(e6(10000000));
      await HB.connect(users[4]).depositBtc(e8(7));
      expect(await HB.usdcInBet(users[0].address)).eq(e6(12000000));
      await HB.connect(users[4]).depositBtc(e8(3));
      expect(await HB.usdcInBet(users[0].address)).eq(e6(15000000));
      await HB.connect(users[4]).depositBtc(e8(15));
      expect(await HB.usdcInBet(users[0].address)).eq(e6(20000000));
      await HB.connect(users[4]).depositBtc(e8(12));
      expect(await HB.usdcInBet(users[0].address)).eq(e6(32000000));
    });
  });
});
