pragma solidity ^0.8.9;
import {ERC4626} from "./vaults/mixins/ERC4626.sol";

import {SafeCastLib} from "./vaults/utils/SafeCastLib.sol";
import {SafeTransferLib} from "./vaults/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./vaults/utils/FixedPointMathLib.sol";

import {ERC20} from "./vaults/tokens/ERC20.sol";
import {TrancheFactory} from "./factories.sol"; 
import "forge-std/console.sol";

interface iTotalAssetOracle{
  function getExchangeRate() external view returns(uint256); 
}  

/// @notice super vault that accepts any combinations of ERC4626 instruments at initialization, and will
/// automatically invest/divest when minting/redeeming 
/// @dev instance is generated for every splitter
contract tVault is ERC4626{
  using SafeCastLib for uint256; 
  using SafeTransferLib for ERC20;
  using FixedPointMathLib for uint256;

  string public assetName; 
  string public underlyingName; 

  // Underlying asset to denominate totalassets in 
  ERC20 public want; 

  // Params
  uint256 num_instrument; 
  uint256[] public  ratios; 
  address[] public  instruments; 
  uint256 public junior_weight; 
  uint256 public promisedReturn; 
  uint256 public inceptionTime;
  uint256 public inceptionPrice; 
  uint256 public delta; 
  bool assetIsErc20; // false if asset is 4626
  string[] public  names; 
  string public  descriptions; 

  uint256 public immutable PRICE_PRECISION; 

  uint256 lastBlock; 
  address public totalAssetOracle; 
  uint256 public constant maxOracleEntries = 100; 
  uint256 public constant minEntries = 10;
  uint256 nonce; 
  mapping(uint256=> OracleEntry) oracleEntries; 

  struct OracleEntry{
    uint128 exchangeRate; //pvu
    uint128 supply;  
  }

  address public immutable creator; 
  /// @notice when intialized, will take in a few ERC4626 instruments (address) as base instruments
  /// param _want is the base assets for all the instruments e.g usdc
  /// param _instruments are ERC4626 addresses that will comprise this super vault
  /// param _ratios are the weight of value invested for each instruments, should sum to 1 
  /// param _junior_weight is the allocation between junior/senior tranche (senior is 1-junior)
  /// param _time_to_maturity is time until the tranche tokens redemption price will be determined
  /// and tranche tokens can be redeemed separately 
  /// param _promisedReturn is the promised senior return gauranteed by junior holders 
  constructor(
    TrancheFactory.InitParams memory param, 
    address _creator, 
    string[] memory _names, 
    string memory _descriptions
    )
    ERC4626(
        ERC20(param._want),
        string(abi.encodePacked(ERC20(param._want).name(), " tVault")),
        string(abi.encodePacked(ERC20(param._want).name(), " tVault"))
    ) {
      require(param._ratios.length == param._instruments.length, "Incorrect num ratios"); 
      want = ERC20(param._want); 
      instruments = param._instruments; 
      num_instrument = param._instruments.length; 
      ratios = param._ratios; 
      junior_weight = param._junior_weight; 
      promisedReturn = param._promisedReturn; 
      inceptionTime = block.timestamp; 
      inceptionPrice = param.inceptionPrice; 
      names = _names; 
      descriptions = _descriptions; 

      PRICE_PRECISION = 10**18; 

      lastBlock = block.number; 

      creator = _creator; 

      uint256 totalRatio; 
      for (uint i =0; i< ratios.length ; i++){
        totalRatio += ratios[i];
      }
      require(totalRatio == PRICE_PRECISION, "Incorrect ratios"); 
  }

  /// @notice tranche creator can specify oracle
  /// If the creator can set oracle at anytime, he can manipulate markets 
  /// so only set at beginning 
  function setExchangeRateOracle(address newOracle, bool _assetIsErc20) public {
   // require(msg.sender == creator && totalAssetOracle == address(0), 
     //   "only creator can set oracle at inception"); 
    totalAssetOracle = newOracle; 
    assetIsErc20 = _assetIsErc20; 
  }


  /// @notice will automatically invest into the ERC4626 instruments and give out 
  /// vault tokens as share
  function mint(uint256 shares, address receiver) public override returns(uint assets)  {
    storeExchangeRate(); 
    assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

    asset.safeTransferFrom(msg.sender, address(this), assets);

    if(!assetIsErc20) invest(shares); 

    _mint(receiver, shares);
    emit Deposit(msg.sender, receiver, assets, shares);
    afterDeposit(assets, shares);
  }

  function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
    // Check for rounding error since we round down in previewDeposit.
    require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

    // Need to transfer before minting or ERC777s could reenter.
    asset.safeTransferFrom(msg.sender, address(this), assets);

    if(!assetIsErc20) invest(shares); 

    _mint(receiver, shares);

    emit Deposit(msg.sender, receiver, assets, shares);

    afterDeposit(assets, shares);
  }

  /// @notice will automatically divest from the instruments
  function redeem(
    uint256 shares,
    address receiver,
    address owner
    ) public override returns(uint assets){
    storeExchangeRate(); 
    if (msg.sender != owner) {
        uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.
        if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
    }

    // Check for rounding error since we round down in previewRedeem.
    require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

    if(!assetIsErc20) divest(assets); 

    beforeWithdraw(assets, shares);
    _burn(owner, shares);

    emit Withdraw(msg.sender, receiver, owner, assets, shares);
    asset.safeTransfer(receiver, assets);
  }

  function withdraw(
      uint256 assets,
      address receiver,
      address owner
  ) public override returns (uint256 shares) {
    shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

    if (msg.sender != owner) {
        uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
    }

    if(!assetIsErc20) divest(assets); 

    beforeWithdraw(assets, shares);

    _burn(owner, shares);

    emit Withdraw(msg.sender, receiver, owner, assets, shares);

    asset.safeTransfer(receiver, assets);
  }

  /// @notice will invest into the current instruments, which is minting erc4626
  /// @dev reverts if error in deposit in at least one of the instruments 
  /// @param shares are denominated in vault token, in PRICE_PRECISION
  function invest(uint256 shares) internal {
    uint num_asset_for_this; 
    ERC4626 instrument_; 

    for (uint i=0; i< num_instrument; i++){
      instrument_ = ERC4626(instruments[i]); 

      // how much underlying to invest in the instrument 
      num_asset_for_this = instrument_.convertToAssets(shares.mulDivDown(ratios[i], PRICE_PRECISION));                       
      asset.safeApprove(instruments[i], num_asset_for_this); 

      require(num_asset_for_this <= instrument_.maxDeposit(address(this)), "Mint Limit"); 
      require(instrument_.deposit(num_asset_for_this, address(this))>=0, "Failed Deposit"); //will mint the instrument to this contract
    }
  }

  /// @notice will divest from current instruments, which is equivalent to redeeming erc4626
  /// @param assets are denominated in underlying token
  function divest(uint256 assets) internal {
    uint num_assets_for_this; 
    for (uint i=0; i< num_instrument; i++){
      num_assets_for_this = assets.mulWadDown(ratios[i]); 
      ERC4626(instruments[i]).withdraw(num_assets_for_this, address(this), address(this)); 
    }
  }

  /// @notice get average real returns collected by the vault in this supervault until now  
  /// @dev exchange rate is stored in previous blocks. 
  /// TODO medianize + delay instead of mean all previous 
  function getStoredReturnData(uint256 pastNBlock) public view returns(uint256, uint256, uint256){
    // storeExchangeRate() ; 
    //require(nonce>= minEntries, "Not enough entries"); 
    uint256 sumSupply; 
    uint256 sumTotalAssets; 
    uint256 num_records;

    for(uint i = pastNBlock; i>0; --i){
      if (oracleEntries[i].exchangeRate == 0) continue ; 
      
      sumSupply += uint256(oracleEntries[i].supply); 
      sumTotalAssets+= uint256(oracleEntries[i].supply).mulWadDown(uint256(oracleEntries[i].exchangeRate)); 
      num_records++; 
    }

    if (oracleEntries[0].exchangeRate != 0){
      sumSupply += uint256(oracleEntries[0].supply); 
      sumTotalAssets+= uint256(oracleEntries[0].supply).mulWadDown(uint256(oracleEntries[0].exchangeRate)); 
      num_records++; 
    }  

    return (sumSupply/num_records,sumTotalAssets/num_records, num_records); 
  }

  function totalAssetsERC4626() public view returns(uint256){  
    uint256 sumAssets; 
    uint256 shares; 
    for (uint i=0; i< num_instrument; i++){

        shares = ERC4626(instruments[i]).balanceOf(address(this));
        sumAssets += ERC4626(instruments[i]).convertToAssets(shares); 
    }
    // delta to be used for governance set buffers 
    return sumAssets + delta.mulWadDown(sumAssets); 
  }

  /// @notice sums over all assets in want tokens 
  /// need to get the shares this vault has for each instrument 
  /// and convert that to assets 
  function totalAssets() public view override returns (uint256){
    if (!assetIsErc20) return totalAssetsERC4626(); 
    
    else{
      // 1:1 wrapper if erc20 
      return totalSupply; 
    }
  }

  /// @notice totalassets oracle for accounting, 1:1 for ERC20
  function totalAssetsOracle() public view returns(uint256){
    if(!assetIsErc20) return totalAssetsERC4626(); 
    else{
      require(totalAssetOracle != address(0), "No oracle"); 
      return iTotalAssetOracle(totalAssetOracle).getExchangeRate().mulWadDown(totalSupply); 
    }
  }
  
  /// @notice stores oracle entries for totalAssets, which is required to compute exchange rates rates
  function storeExchangeRate() public {
    if (block.number == lastBlock || assetIsErc20) return; 

    if (totalAssetOracle != address(0)){

      oracleEntries[nonce%maxOracleEntries] 
        = OracleEntry(iTotalAssetOracle(totalAssetOracle).getExchangeRate().safeCastTo128(), 
            totalSupply.safeCastTo128()); }

    else oracleEntries[nonce%maxOracleEntries] 
      = OracleEntry(previewMint(PRICE_PRECISION).safeCastTo128()
          , totalSupply.safeCastTo128()); 

    nonce++; 
    lastBlock = block.number; 
  }

  /// @notice returns real time or delayed exchange rate for this vault and its underlying
  /// oracle can be customized, or set default  
  /// returns Pvu 
  function queryExchangeRateOracle() public view  returns(uint256){
    // if default oracle 
    return previewMint(PRICE_PRECISION); //for 1 vault, how much underlying? 
  }

  function getUnderlying() public view returns(address){
    return address(want); 
  }

  function getJuniorWeight() public view returns(uint256){
    return junior_weight; 
  }

  function getPromisedReturn() public view returns(uint256){
    return promisedReturn; 
  }
  function getNames() public view returns(string[] memory){
    return names; 
  }



}
