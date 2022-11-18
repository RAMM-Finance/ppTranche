import { ethers } from "hardhat";

async function main() {

  const ETHCPI = await ethers.getContractFactory("ETHCPIOracle"); 
  const ethcpi = await ETHCPI.deploy(); 
  await ethcpi.deployed(); 
  console.log('ethcpi', ethcpi.address ); 
 
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
