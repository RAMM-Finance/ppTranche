pragma solidity ^0.8.9;
import {FixedPointMathLib} from "./vaults/utils/FixedPointMathLib.sol";

import {IERC3156FlashBorrower} from "./vaults/tokens/ERC1155.sol"; 
import {ERC20} from "./vaults/tokens/ERC20.sol";
import {ERC4626} from "./vaults/mixins/ERC4626.sol"; 
import {tVault} from "./tVault.sol"; 
import {SpotPool} from "./amm.sol"; 
import {Position} from "./amm.sol"; 
import {TrancheMaster} from "./tranchemaster.sol"; 
import {TrancheFactory} from "./factories.sol"; 
import {Splitter} from "./splitter.sol";
import {CErc20Behalf} from "./CErc20Behalf.sol";
import "forge-std/console.sol";

contract tLens{
  address owner; 
  TrancheFactory tFactory;  
  TrancheMaster tMaster; 
  constructor(){
    owner = msg.sender; 
  }

  struct TrancheInfo{
    address _want; 
    address[]  _instruments;
    uint256[]  _ratios;
    uint256 _junior_weight; 
    uint256 _promisedReturn; //per time 
    uint256 _time_to_maturity;
    uint256 vaultId; 
    uint256 inceptionPrice; 

    uint256 psu; 
    uint256 pju; 
    uint256 pjs; 
    uint256 curMarkPrice; 
  }


  function setTFactory(address tFactory_ad) external {
    require(msg.sender == owner, "auth"); 
    tFactory = TrancheFactory(tFactory_ad); 
  }

  function setTMaster(address tMaster_ad) external {
    require(msg.sender == owner, "auth"); 
    tMaster = TrancheMaster(tMaster_ad); 
  }

  struct LocalVars{
    uint256 amount; 
    bool claimable; 
    UserLiquidityPositions[]  liqInfos ;
    UserLimitPositions[]  limitInfos; 
  }
  function getPositions(
    address tFactory_ad, 
    uint256 vaultId, 
    address who,
    TrancheFactory.Contracts memory contracts
    ) public view returns(UserLiquidityPositions[] memory, UserLimitPositions[] memory ){
    LocalVars memory vars; 
    SpotPool amm = SpotPool(contracts.amm); 
    // TrancheFactory.Contracts memory contracts = TrancheFactory(tFactory_ad).getContracts(vaultId); 
    SpotPool.LoggedPosition[] memory positions = amm.getLoggedPosition(who); 
    uint16[] memory limitPositions = amm.getLimitLoggedPosition(who); 

    vars.liqInfos = new UserLiquidityPositions[](positions.length); 
    vars.limitInfos = new UserLimitPositions[](limitPositions.length); 
    if (positions.length>0){

      for (uint i=0; i< positions.length; i++){

        vars.liqInfos[i] = UserLiquidityPositions(
            amm.pointToPrice(positions[i].point1), 
            amm.pointToPrice(positions[i].point2), 
            uint256(amm.getPosition(who, positions[i].point1, positions[i].point2).liquidity) 
          ); 
      }
    }

    console.log(limitPositions.length); 
    if(limitPositions.length>0){

      for (uint i=0; i< limitPositions.length; i++){
        (vars.amount, vars.claimable) = amm.getLimitPosition( limitPositions[i], who); 

        vars.limitInfos[i] = UserLimitPositions(
          amm.pointToPrice(limitPositions[i]), 
          vars.amount, vars.claimable
          ); 
      }
    }


    return (vars.liqInfos, vars.limitInfos); 
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

  function getCurrentMarkPrice(
    address tFactory_ad, 
    uint256 vaultId
    ) public view returns(uint256){
    TrancheFactory.Contracts memory contracts = TrancheFactory(tFactory_ad).getContracts(vaultId);
    return SpotPool(contracts.amm).getCurPrice(); 
  }

  function getCurrentValuePrices(
    address tFactory_ad, 
    uint256 vaultId
    ) public view returns(uint256, uint256, uint256){
    TrancheFactory.Contracts memory contracts = TrancheFactory(tFactory_ad).getContracts(vaultId);
    return Splitter(contracts.splitter).computeValuePricesView(); 
  }

  function getTranches(
    address tFactory_ad, 
    uint256 vaultId    
    ) public view returns(address, address){
    TrancheFactory.Contracts memory contracts = TrancheFactory(tFactory_ad).getContracts(vaultId);
    return Splitter(contracts.splitter).getTrancheTokens();   
  }
  
  function getElapsedTime(
    address tFactory_ad, 
    uint256 vaultId
    ) public view returns(uint256){
    TrancheFactory.Contracts memory contracts = TrancheFactory(tFactory_ad).getContracts(vaultId);
    return Splitter(contracts.splitter).elapsedTime(); 
  }


  function getTrancheInfo(
    address tFactory_ad, 
    uint256 vaultId
    ) public view returns(TrancheInfo memory){
    TrancheFactory.InitParams memory params = TrancheFactory(tFactory_ad).getParams(vaultId); 
    (uint256 psu, uint256 pju, uint256 pjs) = getCurrentValuePrices( tFactory_ad, vaultId); 
    uint256 curMarkPrice = getCurrentMarkPrice(tFactory_ad, vaultId); 

    return TrancheInfo(
      params._want, params._instruments, params._ratios, params._junior_weight, 
      params._promisedReturn, params._time_to_maturity, params.vaultId, params.inceptionPrice, 
      psu,pju,pjs, curMarkPrice
      ); 
  }

  // TODO filter out uninteresting markets 
  function getTrancheInfoBatch(
    address tFactory_ad
    ) public view returns(TrancheInfo[] memory){
    uint numVaults = getNumVaults(tFactory_ad); 
    TrancheInfo[] memory infos = new TrancheInfo[](numVaults); 
    TrancheInfo memory cache; 
    uint j; 
    for(uint i=0; i< numVaults; i++ ){
      cache = getTrancheInfo(tFactory_ad, i); 
      if(cache._want!= address(0)){
        infos[j] = cache; 
        j++; 
      }
    }
    return infos; 
  }

  struct UserLiquidityPositions{
    uint256 priceLower; 
    uint256 priceUpper; 
    uint256 liquidity;  // in liquidity 
  }

  struct UserLimitPositions{
    uint256 price; 
    uint256 amount; //bids or ask 
    bool claimable; 
  }

  struct UserInfo{
    uint256 tVaultBal; 
    uint256 seniorBal; 
    uint256 juniorBal; 
    uint256 cSeniorBal; 
    uint256 cJuniorBal; 
    uint256 seniorDebt; 
    uint256 juniorDebt;

    UserLiquidityPositions[] liqPositions; 
    UserLimitPositions[] limitPositions; 

  }
  function getUserInfo(
    address tFactory_ad,
    address account, 
    uint256 vaultId
    ) public view returns(UserInfo memory){
    TrancheFactory.Contracts memory contracts = TrancheFactory(tFactory_ad).getContracts(vaultId);

    UserInfo memory info ; 
    info.tVaultBal = tVault(contracts.vault).balanceOf(account); 

    (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
    info.seniorBal = ERC20(senior).balanceOf(account); 
    info.juniorBal = ERC20(junior).balanceOf(account); 
    info.cSeniorBal = ERC20(contracts.cSenior).balanceOf(account); 
    info.cJuniorBal = ERC20(contracts.cJunior).balanceOf(account); 
    info.seniorDebt = CErc20Behalf(contracts.cSenior).borrowBalanceStored( account); 
    info.juniorDebt = CErc20Behalf(contracts.cJunior).borrowBalanceStored(account); 
    (info.liqPositions,info.limitPositions)  = getPositions(tFactory_ad,vaultId, account, contracts); 
    
    return info; 
  }

  function getNumber() public view returns(uint256){
    return 32; 
  }



}

contract testErc is ERC20{
    constructor()ERC20("testUSDC", "tUSDC", 18){}
    function mint(address to, uint256 amount) public {
        _mint(to, amount); 
    }
    function faucet() public{
      uint256 amount = 1000* 1e18; 
      mint(msg.sender,amount ); 
    }
}

contract testVault is ERC4626{
    constructor(address want)ERC4626( ERC20(want),"a","a" ){

    }
    function totalAssets() public view override returns(uint256){
     return totalFloat();
    }

    function totalFloat() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}

