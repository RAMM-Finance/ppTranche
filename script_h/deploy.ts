import { ethers } from "hardhat";

async function main() {
  console.log('hey'); 

//   const tLens = await ethers.getContractFactory("tLens"); 
//   const tlens = await tLens.deploy(); 
//   await tlens.deployed(); 
//   console.log('tlens', tlens.address ); 

//   const oammFactory = await ethers.getContractFactory("OracleAMMFactory"); 
//   const oamm = await oammFactory.deploy(); 
//   await oamm.deployed(); 
//   console.log("ommmfactory", oamm.address); 

//   const SplitterFactory = await ethers.getContractFactory("SplitterFactory");
//   const splitterFactory = await SplitterFactory.deploy(); 
//   await splitterFactory.deployed(); 
//   console.log("splitterFactory ", splitterFactory.address);

//   const TrancheAMMFactory = await ethers.getContractFactory("TrancheAMMFactory");
//   const ammFactory = await TrancheAMMFactory.deploy(); 
//   await ammFactory.deployed(); 
//   console.log("ammFactory ", ammFactory.address);

//   const tLendingPoolDeployer = await ethers.getContractFactory("tLendingPoolDeployer");
//   const lendingPoolFactory = await tLendingPoolDeployer.deploy( );
//   await lendingPoolFactory.deployed(); 
//   console.log("lendingPoolFactory ", lendingPoolFactory.address);

//   const tLendTokenDeployer = await ethers.getContractFactory("tLendTokenDeployer"); 
//   const lendTokenFactory = await tLendTokenDeployer.deploy(); 
//   await lendTokenFactory.deployed(); 
//   console.log("lendTokenFactory", lendTokenFactory.address); 
// // splitterFactory  0xd1C304C4f8897Ab983b437D30401312F50966b4e
// // ammFactory  0x0b2079d69945c4314AE263Fcc211123eBcdb68f0
// // lendingPoolFactory  0xA21F805349e3Ae64122D167c813C5a3CFc30b4b0
// // lendTokenFactory 0x3a5CA040Df0D9bc7b1940E265c7F910DF411B590
//   const TrancheFactory = await ethers.getContractFactory("TrancheFactory");
//   const tFactory = await TrancheFactory.deploy("0xFD84b7AC1E646580db8c77f1f05F47977fAda692", 
//     ammFactory.address, //amm
//     splitterFactory.address, //splitter
//     lendingPoolFactory.address, //lendingpool
//     lendTokenFactory.address, 
//     oamm.address); //lendtoken
//   await tFactory.deployed(); 
//   console.log("tFactory ", tFactory.address);

//   const TrancheMaster = await ethers.getContractFactory("TrancheMaster");
//   const tMaster = await TrancheMaster.deploy(tFactory.address); 
//   await tMaster.deployed(); 
//   console.log("tMaster ", tMaster.address);

  const testErc = await ethers.getContractFactory("testErc"); 
  const testerc = await testErc.deploy(); 
  await testerc.deployed(); 
  console.log("testerc", testerc.address);

  const Test4626_1 = await ethers.getContractFactory("testVault"); 
  const test4626_1 = await Test4626_1.deploy("0x6398A66a1c9e86294c645f264aDec5F2CF7b13cD");
  await test4626_1.deployed();  
  console.log('46261', test4626_1.address); 

  const test4626_2 = await Test4626_1.deploy("0x6398A66a1c9e86294c645f264aDec5F2CF7b13cD");
  await test4626_2.deployed(); 
  console.log('46262', test4626_2.address); 

 
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
