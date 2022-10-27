import { ethers } from "hardhat";
import {TrancheMaster__factory} from "../typechain-types/factories/tranchemaster.sol"; 

async function main() {
  console.log('hey'); 

  const tLens = await ethers.getContractFactory("tLens"); 
  const tlens = await tLens.deploy(); 
  await tlens.deployed(); 
  console.log('tlens deployed to', tlens.address ); 
  // console.log(TrancheMaster__factory.connect()); 
  // const currentTimestampInSeconds = Math.round(Date.now() / 1000);
  // const ONE_YEAR_IN_SECS = 365 * 24 * 60 * 60;
  // const unlockTime = currentTimestampInSeconds + ONE_YEAR_IN_SECS;

  // const lockedAmount = ethers.utils.parseEther("1");

  // const Lock = await ethers.getContractFactory("Lock");
  // const lock = await Lock.deploy(unlockTime, { value: lockedAmount });

  // await lock.deployed();

  // console.log(`Lock with 1 ETH and unlock timestamp ${unlockTime} deployed to ${lock.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
