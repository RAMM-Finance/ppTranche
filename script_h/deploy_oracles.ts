import { ethers } from "hardhat";

async function main() {

  // const ETHCPI = await ethers.getContractFactory("ETHCPIOracle"); 
  // const ethcpi = await ETHCPI.deploy(); 
  // await ethcpi.deployed(); 
  // console.log('ethcpi', ethcpi.address ); 

  const NEARUSD = await ethers.getContractFactory("NEARUSD_Oracle"); 
  const nearusd = await NEARUSD.deploy(); 
  await nearusd.deployed(); 
  console.log('nearusd',nearusd.address); 
 
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
