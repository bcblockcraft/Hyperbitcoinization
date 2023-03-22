import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { BigNumber, BigNumberish } from "ethers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  ERC20,
  Hyperbitcoinization,
  Hyperbitcoinization__factory,
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
      await WBTC.connect(main).transfer(user.address, e8(100));
      await USDC.connect(main).transfer(user.address, e6(10000000));
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
      const usdcBalance = await WBTC.balanceOf(user.address);

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
    it("should reject wbtc deposit", async () => {
      const tx = HB.connect(users[0]).depositBtc(e8(1));
      await expect(tx).to.be.revertedWithCustomError(HB, "CapExceeded");
    });

    it("should not be able to claim", async () => {
      const tx = HB.connect(users[0]).claim(users[0].address);
      await expect(tx).to.be.revertedWithCustomError(HB, "NotFinished");
    });

    it("should deposit usdc", async () => {
      const amount = e6(1000000);
      await HB.connect(users[0]).depositUsdc(amount);
      const balance = await HB.usdcBalance(users[0].address);
      const totalUsdc = await HB.usdcTotalDeposits();
      const accUsdc = await HB.usdcAccBalance(0);
      const accDeposit = await HB.accDeposit(users[0].address, 0);

      expect(balance).eq(amount);
      expect(totalUsdc).eq(amount);
      expect(accUsdc).eq(amount);

      expect(accDeposit.userAcc).eq(amount);
      expect(accDeposit.globalAcc).eq(amount);
      expect(accDeposit.deposit).eq(amount);
    });

    it("should make second deposit", async () => {
      const amount = e6(1000000);
      await HB.connect(users[0]).depositUsdc(amount);
      const balance = await HB.usdcBalance(users[0].address);
      const totalUsdc = await HB.usdcTotalDeposits();
      // const accUsdc = await HB.usdcAccBalance(1);
      const accDeposit = await HB.accDeposit(users[0].address, 1);

      expect(balance).eq(amount.mul(2));
      expect(totalUsdc).eq(amount.mul(2));
      // expect(accUsdc).eq(amount.mul(2));

      expect(accDeposit.userAcc).eq(amount.mul(2));
      expect(accDeposit.globalAcc).eq(amount.mul(2));
      expect(accDeposit.deposit).eq(amount);
    });
    it("should reject more than 2 btc deposits", async () => {
      const tx = HB.connect(users[1]).depositBtc(e8(10));
      await expect(tx).to.be.revertedWithCustomError(HB, "CapExceeded");
    });
    it("should return 0 used in bet", async () => {
      const inBet = await HB.usdcInBet(users[0].address);
      expect(inBet).eq(0);
    });
    it("should be able to deposit 1 btc", async () => {
      const amount = e8(1);
      await HB.connect(users[1]).depositBtc(amount);
      const balance = await HB.btcBalance(users[1].address);
      const totalWbtc = await HB.btcTotalDeposits();

      expect(balance).eq(amount);
      expect(totalWbtc).eq(amount);
    });
    it("should have 1m in bet", async () => {
      const inBet = await HB.usdcInBet(users[0].address);
      expect(inBet).eq(e6(1000000));
    });

    it("should finish the bet", async () => {
      await time.increase(DURATION);
      await oracle.mock.decimals.returns(8);
      await oracle.mock.latestAnswer.returns(e8(1000000 - 1));
      await HB.setWinnerToken();
    });

    it("should let user 1 get 1 WBTC and 1m USDC", async () => {
      const beforeWBTC = await WBTC.balanceOf(users[1].address);
      const beforeUSDC = await USDC.balanceOf(users[1].address);

      await HB.connect(users[1]).claim(users[1].address);

      const afterWBTC = await WBTC.balanceOf(users[1].address);
      const afterUSDC = await USDC.balanceOf(users[1].address);

      expect(afterUSDC.sub(beforeUSDC)).eq(e6(1000000));
      expect(afterWBTC.sub(beforeWBTC)).eq(e8(1));
    });

    it("should let user 0 withdraw their remaining funds", async () => {
      const beforeWBTC = await WBTC.balanceOf(users[0].address);
      const beforeUSDC = await USDC.balanceOf(users[0].address);

      await HB.connect(users[0]).claim(users[0].address);

      const afterWBTC = await WBTC.balanceOf(users[0].address);
      const afterUSDC = await USDC.balanceOf(users[0].address);

      expect(afterUSDC.sub(beforeUSDC)).eq(e6(1000000));
      expect(afterWBTC.sub(beforeWBTC)).eq(0);
    });
  });

  describe("S 2", async () => {
    before(async () => {
      await setup();
    });
    it("should setup", async () => {
      await testSetup();
    });
    it("should reject wbtc deposit", async () => {
      const tx = HB.connect(users[0]).depositBtc(e8(1));
      await expect(tx).to.be.revertedWithCustomError(HB, "CapExceeded");
    });

    it("should not be able to claim", async () => {
      const tx = HB.connect(users[0]).claim(users[0].address);
      await expect(tx).to.be.revertedWithCustomError(HB, "NotFinished");
    });

    it("should deposit usdc", async () => {
      const amount = e6(100000);
      await HB.connect(users[0]).depositUsdc(amount);
      const balance = await HB.usdcBalance(users[0].address);
      const totalUsdc = await HB.usdcTotalDeposits();
      const accUsdc = await HB.usdcAccBalance(0);
      const accDeposit = await HB.accDeposit(users[0].address, 0);

      expect(balance).eq(amount);
      expect(totalUsdc).eq(amount);
      expect(accUsdc).eq(amount);

      expect(accDeposit.userAcc).eq(amount);
      expect(accDeposit.globalAcc).eq(amount);
      expect(accDeposit.deposit).eq(amount);
    });

    it("should make second deposit", async () => {
      const amount = e6(1000000);
      await HB.connect(users[5]).depositUsdc(e6(10000));
      await HB.connect(users[0]).depositUsdc(amount);
    });
    it("should reject more than 2 btc deposits", async () => {
      const tx = HB.connect(users[1]).depositBtc(e8(10));
      await expect(tx).to.be.revertedWithCustomError(HB, "CapExceeded");
    });
    it("should return 0 used in bet", async () => {
      const inBet = await HB.usdcInBet(users[0].address);
      expect(inBet).eq(0);
    });
    it("should be able to deposit 1 btc", async () => {
      const amount = e6(50);
      await HB.connect(users[1]).depositBtc(amount);
      const balance = await HB.btcBalance(users[1].address);
      const totalWbtc = await HB.btcTotalDeposits();

      expect(balance).eq(amount);
      expect(totalWbtc).eq(amount);
    });
    it("should have 1m in bet", async () => {
      const inBet = await HB.usdcInBet(users[0].address);
      expect(inBet).eq(e6(490000));
    });

    it("should finish the bet", async () => {
      await time.increase(DURATION);
      await oracle.mock.decimals.returns(8);
      await oracle.mock.latestAnswer.returns(e8(1000000 - 1));
      await HB.setWinnerToken();
    });

    it("should let user 0 get 1 WBTC and 1m USDC", async () => {
      const beforeWBTC = await WBTC.balanceOf(users[1].address);
      const beforeUSDC = await USDC.balanceOf(users[1].address);

      await HB.connect(users[1]).claim(users[1].address);

      const afterWBTC = await WBTC.balanceOf(users[1].address);
      const afterUSDC = await USDC.balanceOf(users[1].address);

      expect(afterUSDC.sub(beforeUSDC)).eq(e6(500000));
      expect(afterWBTC.sub(beforeWBTC)).eq(e6(50));
    });

    it("should should not let user 1 withdraw anything", async () => {
      const beforeWBTC = await WBTC.balanceOf(users[0].address);
      const beforeUSDC = await USDC.balanceOf(users[0].address);

      await HB.connect(users[0]).claim(users[0].address);

      const afterWBTC = await WBTC.balanceOf(users[0].address);
      const afterUSDC = await USDC.balanceOf(users[0].address);

      expect(afterUSDC.sub(beforeUSDC)).eq(e6(610000));
      expect(afterWBTC.sub(beforeWBTC)).eq(0);
    });
  });
});
