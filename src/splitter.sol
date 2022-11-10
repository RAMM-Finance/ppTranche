pragma solidity ^0.8.9;
import {SafeCastLib} from "./vaults/utils/SafeCastLib.sol";
import {SafeTransferLib} from "./vaults/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./vaults/utils/FixedPointMathLib.sol";

import {ERC20} from "./vaults/tokens/ERC20.sol";
import {tVault} from "./tVault.sol"; 
import {TrancheMaster} from "./tranchemaster.sol"; 
import {tToken} from "./tToken.sol"; 
import "forge-std/console.sol";


/// @notice Accepts ERC20 and splits them into senior/junior tokens
/// Will hold the ERC20 token in this contract
/// Before maturity, redemption only allowed for a pair, 
/// After maturity, redemption allowed for individual tranche tokens, with the determined conversion rate
/// @dev new instance is generated for each vault
contract Splitter{
  using SafeCastLib for uint256; 
  using SafeTransferLib for ERC20;
  using FixedPointMathLib for uint256;

  tVault public underlying; 
  tToken public senior;
  tToken public junior;  

  uint256 public junior_weight; 
  uint256 public constant precision = 1e18; 
  uint256 public promised_return; 
  uint256 immutable vaultId; 

  address public immutable trancheMasterAd;

  /// @notice in seconds/minutes/hours/days/weeks passed from inception
  /// as specified during construction default is hours and compounded hourly. 
  /// @dev in discrete representations, so 1 means 1 hour 
  uint256 public elapsedTime; 
  uint256 public lastRecordTime; 
  uint256 inceptionPrice; 
  bool delayedOracle;
  uint256 public constant pastNBlock = 10; 
  uint256 internalPsu;
  uint256 internalPju; 
  uint256 internalPjs; 
  uint256 public escrowedVault; 
  uint256 baseR_f; 

  mapping(uint256=>mapping(address=>bool)) claimed; 
  mapping(uint256=> uint256) mintAmounts; 
  uint256 snapshotId; 

  constructor(
    tVault _underlying, //underlying vault token to split 
    uint256 _vaultId, 
    address _trancheMasterAd
    ){
    underlying = _underlying; 

    junior_weight = underlying.getJuniorWeight(); 
    promised_return = underlying.getPromisedReturn(); 
    inceptionPrice = underlying.inceptionPrice(); 
    vaultId = _vaultId; 
    trancheMasterAd = _trancheMasterAd; 

    underlying.approve(trancheMasterAd, type(uint256).max); 
    lastRecordTime = block.timestamp; 

    setTokens(); 
  } 

  function setTokens() internal {
    senior = new tToken(underlying, 
      "senior", 
      string(abi.encodePacked("se_", underlying.symbol())), 
      address(this) 
      );

    junior = new tToken(underlying,
      "junior", 
      string(abi.encodePacked("ju_", underlying.symbol())), 
      address(this) 
      );
    senior.approve(trancheMasterAd, type(uint256).max); 
    junior.approve(trancheMasterAd, type(uint256).max); 
  }

  /// @notice take snapshot for dynamic adjustment 
  function doSnapshot(bool up, uint256 mintAmount) public{
    junior._snapshot(); 
    snapshotId =  senior._snapshot(); 
    lowerValueAndIncreaseBalance(up, mintAmount); 
    mintAmounts[snapshotId] = mintAmount; 
  }

  /// @notice 
  function claim(uint256 snapshotId, bool claimSenior) public {
    require(!claimed[snapshotId][msg.sender], "Double Claim"); 
    claimed[snapshotId][msg.sender] = true; 
    tToken token = claimSenior? junior: senior; 

    uint256 bal = token.balanceOfAt(msg.sender, snapshotId); 
    uint256 supplySnapshot = token.totalSupplyAt( snapshotId); 
    uint256 claimedAmount = bal.mulWadDown(mintAmounts[snapshotId].divWadDown(supplySnapshot));

    token.transfer(msg.sender, claimedAmount); 
  }

  /// @notice logic for dynamic adjustment 
  function lowerValueAndIncreaseBalance(bool up, uint256 mintAmount) internal {

    // if up, mint more seniors to be claimed by pre snapshot junior holders 
    if(up){
      senior.mint(address(this), mintAmount); 

      // set new ratio by the current supplies 
      uint256 juniorSupply = junior.totalSupply(); 
      junior_weight = juniorSupply.divWadDown(senior.totalSupply() + juniorSupply); 
    }

    // Else, mint more juniors to be claimed by pre snapshot senior holders 
    else{
      junior.mint(address(this), mintAmount); 

      (, uint256 pju, ) = computeValuePricesView(); 
      uint256 juniorSupply = junior.totalSupply(); 

      // Artificially change the senior price and reset elapsed time  
      inceptionPrice = underlying.totalAssets() - (juniorSupply + mintAmount).mulWadDown(pju);
      elapsedTime = 0; 

      junior_weight = juniorSupply.divWadDown(senior.totalSupply() + juniorSupply); 
    }
  }

  /// @notice computes current value of senior/junior denominated in underlying 
  /// which is the value that one would currently get by redeeming one senior token
  function computeValuePricesView() public view returns(uint256 psu, uint256 pju, uint256 pjs){

    // Get senior redemption price that increments per unit time as usual 
    uint256 srpPlusOne = inceptionPrice.mulWadDown((promised_return+baseR_f).rpow(elapsedTime, precision));
    uint256 totalAssetsHeld; 
    uint256 seniorSupply ;
    uint256 juniorSupply ; 

    // Instantaneous data, subject to manipulations 
    if (!delayedOracle){
      seniorSupply = senior.totalSupply(); 
      juniorSupply = junior.totalSupply(); 

      uint256 underlyingSupply = underlying.totalSupply();

      // Assets held by senior and junior supply  
      totalAssetsHeld = underlyingSupply==0? 0 : underlying.totalAssets()
        .mulDivDown(seniorSupply+juniorSupply, underlying.totalSupply()+1); 
    }
    // Use data from pastNBlock instead
    else{
      (uint256 totalSupply, uint256 totalAssetsHeld_, ) = underlying.getStoredReturnData(pastNBlock); 
      juniorSupply = totalSupply.mulWadDown(underlying.junior_weight()); 
      seniorSupply = totalSupply - juniorSupply; 
      totalAssetsHeld = totalAssetsHeld_; 
    }

    bool belowThreshold; 

    if (seniorSupply == 0) return(0,0,0); 
    
    // Check if all seniors can redeem
    if (totalAssetsHeld >= srpPlusOne.mulWadDown(seniorSupply))
      psu = srpPlusOne; 
    else{
      psu = totalAssetsHeld.divWadDown(seniorSupply);
      belowThreshold = true;  
    }

    // should be 0 otherwise 
    if(!belowThreshold) pju = (totalAssetsHeld -
        srpPlusOne.mulWadDown(seniorSupply)).divWadDown(juniorSupply); 

    pjs = pju.divWadDown(psu); 
  }

  function computeValuePrices() public  returns(uint256, uint256, uint256){
    elapsedTime += (block.timestamp - lastRecordTime);
    lastRecordTime = block.timestamp; 
    underlying.storeExchangeRate(); 
    (internalPsu, internalPju, internalPjs) = computeValuePricesView(); 
    return (internalPsu, internalPju, internalPjs); 
  }

  /// @notice computes implied price of senior/underlying or junior/underlying
  /// given the market price of js and supply and assets 
  function computeImpliedPrices(uint markPjs) public view returns(uint psu, uint pju){

    psu = underlying.totalAssets().divWadDown(senior.totalSupply() 
          + markPjs.mulWadDown(junior.totalSupply()));
    pju = psu.mulWadDown(markPjs); 
  }
   
  /// @notice accepts token_to_split and mints s,j tokens
  /// ex. 1 vault token-> 0.3 junior and 0.7 senior for weight of 0.3, 0.7
  function split(uint256 amount) external returns(uint, uint) {
    require(underlying.balanceOf(msg.sender)>= amount, "bal"); 
    underlying.transferFrom(msg.sender, address(this), amount); 
    escrowedVault += amount; 

    uint256 junior_token_mint_amount = amount.mulWadDown(junior_weight);
    uint256 senior_token_mint_amount = amount - junior_token_mint_amount; 

    junior.mint(msg.sender, junior_token_mint_amount); 
    senior.mint(msg.sender, senior_token_mint_amount);

    return (junior_token_mint_amount, senior_token_mint_amount); 
  }

  /// @notice aceepts junior and senior token and gives back token_to_merge(tVault tokens)
  /// Function to call when redeeming before maturity
  /// @param junior_amount is amount of junior tokens user want to redeem
  /// @dev senior amount is automiatically computed when given junior amount 
  function merge(uint256 junior_amount) external returns(uint){
    uint256 _junior_weight = junior_weight; 
    uint256 senior_amount = (precision-_junior_weight)
                            .mulWadDown(_junior_weight).mulWadDown(junior_amount); 
    require(senior.balanceOf(msg.sender) >= senior_amount, "Not enough senior tokens"); 
    escrowedVault -= (junior_amount+senior_amount); 

    junior.burn(msg.sender, junior_amount);
    senior.burn(msg.sender, senior_amount);

    underlying.transfer(msg.sender, junior_amount+senior_amount); 

    return junior_amount + senior_amount; 
  }

  function mergeFromMaster(
    uint256 junior_amount, 
    uint256 senior_amount, 
    address recipient) external{
    require(msg.sender == trancheMasterAd, "not master"); 

    escrowedVault -= (junior_amount+senior_amount); 

    junior.burn(recipient, junior_amount);
    senior.burn(recipient, senior_amount);

    underlying.transfer(recipient, junior_amount+senior_amount); 
  }

  /// @dev need to return in list format to index it easily 
  /// 0 is always senior 
  function getTrancheTokens() public view returns(address, address){
    return (address(junior), address(senior));  
  }

  function trustedBurn(bool isSenior, address who, uint256 amount) external {
    require(msg.sender == trancheMasterAd, "entryERR");
    if(isSenior) senior.burn(who, amount); 
    else junior.burn(who, amount); 
  }

  function getStoredValuePrices() public view returns(uint256,uint256, uint256){
    return (internalPsu, internalPju, internalPjs); 
  }
  function getSRP(uint256 time) public view returns(uint256){
    return inceptionPrice.mulWadDown(promised_return.rpow(time, precision)); 
  }

  //// Previleged Functions 

  function toggleDelayOracle() external{
    delayedOracle = delayedOracle? false : true;  
  }

  function setBasePromisedReturn(uint256 newR_f) external{
    baseR_f = newR_f; 
  }

}





