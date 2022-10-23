pragma solidity ^0.8.4;
import {Auth} from "./vaults/auth/Auth.sol";
import {ERC4626} from "./vaults/mixins/ERC4626.sol";

import {SafeCastLib} from "./vaults/utils/SafeCastLib.sol";
import {SafeTransferLib} from "./vaults/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./vaults/utils/FixedPointMathLib.sol";

import {IERC3156FlashBorrower} from "./vaults/tokens/ERC1155.sol"; 
import {ERC20} from "./vaults/tokens/ERC20.sol";
import {tVault} from "./tVault.sol"; 
import {TrancheMaster} from "./tranchemaster.sol"; 
import "forge-std/console.sol";


/// @notice tokens for junior/senior tranches 
contract tToken is ERC20{

  modifier onlySplitter() {
    require(msg.sender == splitter, "!Splitter");
     _;
  }

  address splitter; 
  ERC20 asset; 

  /// @notice asset is the tVault  
  constructor(
      ERC20 _asset, 
      string memory _name,
      string memory _symbol, 
      address _splitter
  ) ERC20(_name, _symbol, _asset.decimals()) {
      asset = _asset;
      splitter = _splitter; 
  }

  function mint(address to, uint256 amount) external onlySplitter{
    _mint(to, amount); 
  }

  function burn(address from, uint256 amount) external onlySplitter{
    _burn(from, amount);
  }

  function flashMint(
     IERC3156FlashBorrower receiver,
     address token, 
     uint256 amount, 
     bytes calldata data
     ) external returns(bool){
    //require(amount <= max);
    _mint(address(receiver), amount); 
    require(
      receiver.onFlashLoan(msg.sender, address(this), amount, 0, data) 
        == keccak256("ERC3156FlashBorrower.onFlashLoan"), "callback failed"
    ); 
    _burn(address(receiver), amount); 
  }

}

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

  constructor(
    tVault _underlying, //underlying vault token to split 
    uint256 _vaultId, 
    address _trancheMasterAd
    ){
    underlying = _underlying; 

    senior = new tToken(_underlying, 
      "senior", 
      string(abi.encodePacked("se_", _underlying.symbol())), 
      address(this) 
      );

    junior = new tToken(_underlying,
      "junior", 
      string(abi.encodePacked("ju_", _underlying.symbol())), 
      address(this) 
      );

    junior_weight = underlying.getJuniorWeight(); 
    promised_return = underlying.getPromisedReturn(); 
    inceptionPrice = underlying.inceptionPrice(); 
    vaultId = _vaultId; 
    trancheMasterAd = _trancheMasterAd; 

    //Give approval to trancheMaster
    underlying.approve(trancheMasterAd, type(uint256).max); 
    senior.approve(trancheMasterAd, type(uint256).max); 
    junior.approve(trancheMasterAd, type(uint256).max); 
  }

  /// @notice in seconds/minutes/hours/days/weeks passed from inception
  /// as specified during construction default is hours and compounded hourly. 
  /// @dev in discrete representations, so 1 means 1 hour 
  uint256 public elapsedTime; 
  uint256 inceptionPrice; 

  /// @notice computes current value of senior/junior denominated in underlying 
  /// which is the value that one would currently get by redeeming one senior token
  function computeValuePrices() public view returns(uint256 psu, uint256 pju, uint256 pjs){

    // Get senior redemption price that increments per unit time as usual 
    uint256 srpPlusOne = inceptionPrice.mulWadDown(promised_return.rpow(elapsedTime, precision));
    uint256 totalAssetsHeld = underlying.totalAssets(); // TODO care for manipulation 
    uint256 seniorSupply = senior.totalSupply(); 
    uint256 juniorSupply = junior.totalSupply(); 
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

    pjs = pju.divWadDown(psu); //1.01,1.04, 1.03 
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
    uint256 senior_amount = (precision-junior_weight)
                            .mulWadDown(junior_weight).mulWadDown(junior_amount); 
    require(senior.balanceOf(msg.sender) >= senior_amount, "Not enough senior tokens"); 

    junior.burn(msg.sender, junior_amount);
    senior.burn(msg.sender, senior_amount);
    underlying.transfer(msg.sender, junior_amount+senior_amount); 
    return junior_amount + senior_amount; 
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

  function setMaster() public {}

}







  // function getValuePrices() public view returns(uint256, uint256){
  //   return(psu, pju); 
  // }

////DEPrecated



  // /// @notice only can called after set maturity by tranche token holders
  // function redeem_after_maturity(tToken _tToken, uint256 amount) external {
  //   require(address(_tToken) == address(senior) 
  //     || address(_tToken) == address(junior), "Wrong Tranche Token");

  //   bool isSenior = (address(_tToken) == address(senior)) ? true : false; 
  //   uint redemption_price = isSenior? s_r: j_r; 
  //   uint token_redeem_amount = (redemption_price * amount)/PRICE_PRECISION; 

  //   _tToken.trustedburn(msg.sender, amount); 
  //   underlying.transfer(msg.sender, token_redeem_amount); 
      
  // }
  // function getRedemptionPrices() public view returns(uint, uint){
  //     return (s_r, j_r); 
  // }

  // /// @notice calculate and store redemption Price for post maturity 
  // /// @dev should be only called once right after tToken matures, as totalSupply changes when redeeming 
  // /// also should be called by a keeper bot at maturity 
  // function calcRedemptionPrice() public {
  //   require(underlying.isMatured(), "Vault not matured"); 
  //   uint promised_return = underlying.getPromisedReturn(); //in 1e6 decimals i.e 5000 is 0.05

  //   uint real_return = underlying.getCurrentRealReturn(); 

  //   uint _s_r = ((PRICE_PRECISION + promised_return)* PRICE_PRECISION/(PRICE_PRECISION+real_return)); 

  //   uint max_s_r = (PRICE_PRECISION*PRICE_PRECISION/(PRICE_PRECISION - junior_weight));  

  //   s_r = min(_s_r, max_s_r);

  //   uint num = underlying.totalSupply() - senior.totalSupply().mulDivDown(s_r, PRICE_PRECISION); 

  //   j_r = num.mulDivDown(PRICE_PRECISION, junior.totalSupply()); 
  // }









  // constructor(
  //     ERC20 _asset, 
  //     string memory _name,
  //     string memory _symbol, 
  //     address _splitter
  // ) ERC20(_name, _symbol, _asset.decimals()) {
  //     asset = _asset;
  //     splitter = _splitter; 
  // }

  /// @notice tokens for junior/senior tranches, no funds 
/// are stored in this contract, but are all escrowed to 
// /// the splitter contract, only to be redeemed at maturity. 
// contract tToken is ERC4626{

//     modifier onlySplitter() {
//     require(msg.sender == splitter, "!Splitter");
//      _;
//   }

//   Splitter splitter; 
//   ERC20 asset; 
//   bool isSenior; 
//   uint256 immutable vaultId; 
//   address tMaster; 

//   /// @notice asset is the tVault  
//   constructor(
//       ERC20 _asset, 
//       string memory _name,
//       string memory _symbol, 
//       address _splitter, 
//       bool _isSenior,  //internal senior or junior 
//       uint256 _vaultId, //internal vaultId 
//     ) ERC4626(
//         _asset.want(), //the underlying of the vault, i.e wETH, usdc, etc
//         _name,
//         _symbol
//     )  {
//         asset = _asset;
//         splitter = Splitter(_splitter); 
//         vaultId = _vaultId; 
//         tMaster = splitter.trancheMasterAd(); 
//   }

//   function trustedMint(address receiver, uint256 amount) public onlySplitter {
//     _mint(receiver, amount); 
//   }

//   function trustedBurn(address receiver, uint256 amount) public onlySplitter {
//     _burn(receiver, amount); 
//   }

//   function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
//     // Check for rounding error since we round down in previewDeposit.
//     require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

//     // Need to transfer before minting or ERC777s could reenter.
//     asset.safeTransferFrom(msg.sender, address(this), assets);

//     _mint(receiver, shares);

//     emit Deposit(msg.sender, receiver, assets, shares);

//     afterDeposit(assets, shares, receiver);
//   }

//   function withdraw(
//       uint256 assets,
//       address receiver,
//       address owner
//   ) public virtual returns (uint256 shares) {
//     shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

//     if (msg.sender != owner) {
//         uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

//         if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
//     }

//     beforeWithdraw(assets, shares);

//     _burn(owner, shares);

//     emit Withdraw(msg.sender, receiver, owner, assets, shares);

//     asset.safeTransfer(receiver, assets);
//   }

//   /// @notice need to get total assets denominated in the want token, 
//   /// but since this contract is not holding any funds, instead calculate it 
//   /// implicitly by supply * P_ju or P_su 
//   function totalAssets() public view override returns(uint256){
//     uint price = !isSenior? splitter.getPju() : splitter.getPsu(); 
//     return totalSupply.mulDivDown(price, splitter.PRICE_PRECISION()); 
//   } 

//   /// @notice contains key logic for investing into this tranche from the underlying of its parent
//   /// vault, which involves minting the parent vault, splitting and swapping 
//   /// @dev assets is denominated in want, 
//   function afterDeposit(uint256 assets, uint256 shares, address receiver) internal override {

//     asset.approve(tMaster, assets); 

//     // Buying will transfer assets back to the splitter, and mint this token to this address 
//     // so need to transfer the minted tokens back to the tVault, 
//     transfer(
//       receiver,
//       TrancheMaster(tMaster).buy_tranche(vaultId, assets, isSenior) 
//       ); 
//   }

//   function beforeWithdraw(uint256 assets, uint256 shares) internal override{

//   }


// }