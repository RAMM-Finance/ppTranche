pragma solidity ^0.8.9;
import {FixedPointMathLib} from "./vaults/utils/FixedPointMathLib.sol";

import {IERC3156FlashBorrower} from "./vaults/tokens/ERC1155.sol"; 
import {ERC20} from "./vaults/tokens/ERC20.sol";
import {tVault} from "./tVault.sol"; 
import {TrancheMaster} from "./tranchemaster.sol"; 
import {TrancheFactory} from "./factories.sol"; 
import {Splitter} from "./splitter.sol";
import "forge-std/console.sol";

contract tLens{
  address owner; 
  TrancheFactory tFactory;  
  TrancheMaster tMaster; 
  constructor(){
    owner = msg.sender; 
  }

  function setTFactory(address tFactory_ad) external {
    require(msg.sender == owner, "auth"); 
    tFactory = TrancheFactory(tFactory_ad); 
  }

  function setTMaster(address tMaster_ad) external {
    require(msg.sender == owner, "auth"); 
    tMaster = TrancheMaster(tMaster_ad); 
  }

  function getContracts(
    address tFactory_ad, 
    uint256 vaultId) public view returns(TrancheFactory.Contracts memory){
    return TrancheFactory(tFactory_ad).getContracts(vaultId); 
  }

  function getVaultParams(
    address tFactory_ad, 
    uint256 vaultId
    ) public view returns(TrancheFactory.InitParams memory){
    return TrancheFactory(tFactory_ad).getParams(vaultId); 
  }

  function getNumVaults(
    address tFactory_ad
    ) public view returns(uint256){
    return TrancheFactory(tFactory_ad).id(); 
  }

  function getPrices(
    address tFactory_ad, 
    uint256 vaultId
    ) public view returns(uint256, uint256, uint256){
    TrancheFactory.Contracts memory contracts = TrancheFactory(tFactory_ad).getContracts(vaultId);
    return Splitter(contracts.splitter).getStoredValuePrices(); 
  }
  
  function getElapsedTime(
    address tFactory_ad, 
    uint256 vaultId
    ) public view returns(uint256){
    TrancheFactory.Contracts memory contracts = TrancheFactory(tFactory_ad).getContracts(vaultId);
    return Splitter(contracts.splitter).elapsedTime(); 
  }

  // function getOracleSetting(

  //   )

}



