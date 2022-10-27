pragma solidity ^0.8.9;
import {FixedPointMathLib} from "./vaults/utils/FixedPointMathLib.sol";

import {IERC3156FlashBorrower} from "./vaults/tokens/ERC1155.sol"; 
import {ERC20} from "./vaults/tokens/ERC20.sol";
import {tVault} from "./tVault.sol"; 
import {TrancheMaster} from "./tranchemaster.sol"; 

import "forge-std/console.sol";

contract tLens{
  // inception price
  // value prices, real prices 
  // num vaults 

  // uint256 num_instrument; 
  // uint256[] ratios; 
  // address[] instruments; 
  // uint256 init_time; 
  // uint256 public junior_weight; 
  // uint256 promisedReturn; 
  // uint256 time_to_maturity;
  // uint256 public inceptionPrice; 
  // ERC20 public want; 

  // uint256[] initial_exchange_rates; 

  // address public totalAssetOracle; 
  // uint256 public constant maxOracleEntries = 100; 
  // uint256 public constant minEntries = 10;

  // tVault public underlying; 
  // tToken public senior;
  // tToken public junior;  

  // uint256 public promised_return; 
  // uint256 immutable vaultId; 

  // address public immutable trancheMasterAd;

  // uint256 public elapsedTime; // in hours, not in wad 
  // uint256 inceptionPrice; 
  // bool delayedOracle;
  // uint256 public constant pastNBlock = 10; 
  // uint256 internalPsu;
  // uint256 internalPju; 
  // uint256 internalPjs; 


  function fetchContracts() public view returns(uint256){
    return 32; 
  }
}



