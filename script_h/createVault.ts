import { ethers } from "hardhat";


import {BigNumber, utils} from "ethers"

async function main() {
 const testVault1Address = "0xdc2Cc9719FE2Da9d5B16475595C77DF049CD7b1F"; 
 const testVault2Address = "0xA9729DC13825b3d4400353B6BF1F9e6F5338cb25"; 
    const [owner, addr1, addr2] = await ethers.getSigners();
    console.log('owners', owner.address, addr1.address, addr2.address); 
// const owner ="0xFD84b7AC1E646580db8c77f1f05F47977fAda692";
interface InitParams{
  _want: string; 
  _instruments: string[]; 
  _ratios: BigNumber[];
  _junior_weight: BigNumber;
  _promisedReturn: BigNumber;
  _time_to_maturity: BigNumber; 
  vaultId: BigNumber; 
  inceptionPrice: BigNumber; 
}const pp_ = BigNumber.from(10).pow(6);

 const params = {} as InitParams; 
  params._want = "0x9aAc9198409Dd630c0754494BC86b7D90268BC5E"; 
    params._instruments =  [testVault1Address, testVault2Address]; 
    params._ratios = [pp_.mul(7).div(10), pp_.mul(3).div(10)]; 
    params._junior_weight = pp_.mul(3).div(10); 
    params._promisedReturn = pp_.mul(1).div(10);
    params._time_to_maturity = pp_.mul(0);
    params.vaultId = pp_.mul(0);   // const _want = collateral_address; 
    params.inceptionPrice = pp_; 



  const SplitterFactory = await ethers.getContractFactory("SplitterFactory");
  const splitterFactory = await SplitterFactory.deploy(); 
  await splitterFactory.deployed(); 
  console.log("splitterFactory ", splitterFactory.address);

  const TrancheAMMFactory = await ethers.getContractFactory("TrancheAMMFactory");
  const ammFactory = await TrancheAMMFactory.deploy(); 
  await ammFactory.deployed(); 
  console.log("ammFactory ", ammFactory.address);

  const tLendingPoolDeployer = await ethers.getContractFactory("tLendingPoolDeployer");
  const lendingPoolFactory = await tLendingPoolDeployer.deploy( );
  await lendingPoolFactory.deployed(); 
  console.log("lendingPoolFactory ", lendingPoolFactory.address);

  const tLendTokenDeployer = await ethers.getContractFactory("tLendTokenDeployer"); 
  const lendTokenFactory = await tLendTokenDeployer.deploy(); 
  await lendTokenFactory.deployed(); 
  console.log("lendTokenFactory", lendTokenFactory.address); 

  const TrancheFactory = await ethers.getContractFactory("TrancheFactory");
  const tFactory = await TrancheFactory.connect(owner).deploy(owner.address, 
    ammFactory.address, //amm
    splitterFactory.address, //splitter
    lendingPoolFactory.address, //lendingpool
    lendTokenFactory.address); //lendtoken
  await tFactory.deployed(); 
  // console.log("tFactory ", tFactory.address);

  const TrancheMaster = await ethers.getContractFactory("TrancheMaster");
  const tMaster = await TrancheMaster.connect(owner).deploy(tFactory.address); 
  await tMaster.deployed(); 
  console.log("tMaster ", tMaster.address);

  await tFactory.connect(owner).setTrancheMaster(tMaster.address); 
    await tFactory.connect(owner).createVault(params,["d","d"], "description"); 
  const contracts = await tFactory.getContracts(0); 
  console.log('contrcats', contracts); 

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
