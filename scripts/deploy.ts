import { ethers, run } from "hardhat";

async function deploy() {
  const Factory = await ethers.getContractFactory("Hyperbitcoinization");
  const args = [
    "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599",
    "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
    "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c",
    1686853852,
    10000,
  ];

  //@ts-ignore
  const hpb = await Factory.deploy(...args);

  await hpb.deployed();

  console.log("Deployed to: ", hpb.address);

  await run("verify:verify", {
    address: hpb.address,
    constructorArguments: args,
  });
}

deploy().then().catch(console.log);
