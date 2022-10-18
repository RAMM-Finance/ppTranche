pragma solidity ^0.8.4;
import {Auth} from "./vaults/auth/Auth.sol";
import {ERC4626} from "./vaults/mixins/ERC4626.sol";

import {SafeCastLib} from "./vaults/utils/SafeCastLib.sol";
import {SafeTransferLib} from "./vaults/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./vaults/utils/FixedPointMathLib.sol";

import {ERC20} from "./vaults/tokens/ERC20.sol";
import {TrancheFactory} from "./tranchemaster.sol"; 
import "forge-std/console.sol";

/// @notice super vault that accepts any combinations of ERC4626 instruments at initialization, and will
/// automatically invest/divest when minting/redeeming 
/// @dev instance is generated for every splitter
contract tVault is ERC4626{
  using SafeCastLib for uint256; 
  using SafeTransferLib for ERC20;
  using FixedPointMathLib for uint256;

  uint256 num_instrument; 
  uint256[] ratios; 
  address[] instruments; 
  uint256 init_time; 
  uint256 junior_weight; 
  uint256 promisedReturn; 
  uint256 time_to_maturity;
  uint256 public inceptionPrice; 
  ERC20 public want; 

  mapping(address=>uint256) addressToIndex; 
  uint256[] initial_exchange_rates; 
  uint256 public PRICE_PRECISION; 
  uint256 public constant oracle_freq = 1; //set default as 1 which is just getting last block's exchange rate (only prevents atomic tx attacks)
  uint256 lastBlock; 
  mapping(uint256=>uint256[oracle_freq]) stored_exchange_rates; //instrument index-> exchange rates 
  mapping(address=>address) priceOracles; 

  /// @notice when intialized, will take in a few ERC4626 instruments (address) as base instruments
  /// param _want is the base assets for all the instruments e.g usdc
  /// param _instruments are ERC4626 addresses that will comprise this super vault
  /// param _ratios are the weight of value invested for each instruments, should sum to 1 
  /// param _junior_weight is the allocation between junior/senior tranche (senior is 1-junior)
  /// param _time_to_maturity is time until the tranche tokens redemption price will be determined
  /// and tranche tokens can be redeemed separately 
  /// param _promisedReturn is the promised senior return gauranteed by junior holders 
  constructor(
    TrancheFactory.InitParams memory param
    )
    ERC4626(
        ERC20(param._want),
        string(abi.encodePacked("super ", ERC20(param._want).name(), " Vault")),
        string(abi.encodePacked("t", ERC20(param._want).symbol()))
    )  
  {
    want = ERC20(param._want); 
    instruments = param._instruments; 
    num_instrument = param._instruments.length; 
    ratios = param._ratios; 
    junior_weight = param._junior_weight; 
    promisedReturn = param._promisedReturn; 
    time_to_maturity = param._time_to_maturity; 
    inceptionPrice = param.inceptionPrice; 
    init_time = block.timestamp;

    initial_exchange_rates = new uint[](num_instrument); 
    PRICE_PRECISION = 10**want.decimals(); 

    //need to get initial exchange rate between the instruments and want 
    for (uint i=0; i< num_instrument; i++){
        addressToIndex[instruments[i]] = i; 
        initial_exchange_rates[i] = get_exchange_rate(instruments[i]); 
    }

    lastBlock = block.number; 
  }

  /// @notice implement typical oracle based attacks preventions: medianize+delay 
  /// @dev automatically checkpoints the accumulator value every time
  /// the pool/amm/vault is touched the first time in a block, cycling through 
  /// an array where if full the old one is replaced. 
  function store_exchange_rate() public returns(uint256){

    address ins;
    // store current block number to ensure that the redemption price is 
    // calculated at least 1 block after last store
    lastBlock = block.number; 

    // Store exchange rates internally for all instruments 
    for (uint j = 0; j< num_instrument; j++) {
      ins = instruments[j]; 

      uint[oracle_freq] storage exchange_rate = stored_exchange_rates[addressToIndex[ins]]; 

      if (exchange_rate.length > 1){
        for (uint i = 0; i < exchange_rate.length-1; i++){
          exchange_rate[i] = exchange_rate[i+1]; 
        }
        exchange_rate[exchange_rate.length-1] = get_fresh_exchange_rate(j);
      }
      else{
        exchange_rate[0] = get_fresh_exchange_rate(j); 
      }
    }

  }

  /// @notice function that checks whether function caller can 
  /// update the exchange rate
  function exchange_rate_hook() public{
    if(lastBlock < block.number){
      store_exchange_rate(); 
    }
    return; 
  }

  /// @notice get the amount of shares for the instrument one would obtain
  /// by depositing one want token.
  /// @dev care needs to be taken when implementing this to prevent oracle-based attacks
  function get_fresh_exchange_rate(uint256 instrument_id) internal view returns(uint256){
    // check if default oracle or not
    address instrument = instruments[instrument_id]; 
    if (priceOracles[instrument] == address(0)) 
     return ERC4626(instrument).previewDeposit(PRICE_PRECISION); 

    else{
     // priceOracles[instrument].call(data)
    }
  }

  /// @notice get the amount of shares for the instrument one would obtain
  /// by depositing one want token.
  /// @dev care needs to be taken when implementing this to prevent oracle-based attacks
  function get_exchange_rate(address instrument) internal view returns(uint256){
    require(block.number >= lastBlock+1, "Non atomic");

    // if oracle_freq == 1
    return stored_exchange_rates[addressToIndex[instrument]][oracle_freq-1]; 
  }

  /// @notice will automatically invest into the ERC4626 instruments and give out 
  /// vault tokens as share
  function mint(uint256 shares, address receiver) public override returns(uint assets)  {
    assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

    asset.safeTransferFrom(msg.sender, address(this), assets);
    console.log('assets', assets, shares); 
    invest(shares); 

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
    if (msg.sender != owner) {
        uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
    }

    // Check for rounding error since we round down in previewRedeem.
    require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");
    divest(assets); 

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
                            
      require(num_asset_for_this <= instrument_.maxDeposit(address(this)), "Mint Limit"); 
 
      asset.safeApprove(instruments[i], num_asset_for_this); 

      require(instrument_.deposit(num_asset_for_this, address(this))>=0, "Failed Deposit"); //will mint the instrument to this contract
    }
  }

  /// @notice will divest from current instruments, which is equivalent to redeeming erc4626
  /// @param assets are denominated in underlying token
  function divest(uint256 assets) internal{
    uint num_assets_for_this; 
    for (uint i=0; i< num_instrument; i++){
      num_assets_for_this = (assets* ratios[i]/PRICE_PRECISION); 
      ERC4626(instruments[i]).withdraw(num_assets_for_this, address(this), address(this)); 
    }
  }

  /// @notice get average real returns collected by the vault in this supervault until now  
  /// real return is computed by (final_value_of_vault/initial_value_of_vault) - 1
  /// @dev exchange rate is stored in previous blocks
  function getCurrentRealReturn() public view returns(uint256){
    uint[] memory real_returns = new uint256[](num_instrument); 
    uint sum_return; 
    for (uint i=0; i< num_instrument; i++){
      real_returns[i] = get_exchange_rate(instruments[i])
                        .mulDivDown(PRICE_PRECISION, initial_exchange_rates[i]); 

      sum_return += real_returns[i] - PRICE_PRECISION; 
   }
   return (sum_return/num_instrument); 
  
  }

  /// @notice sums over all assets in want tokens 
  /// need to get the shares this vault has for each instrument 
  /// and convert that to assets 
  function totalAssets() public view override returns (uint256){
    uint sumAssets; 
    uint shares; 
    for (uint i=0; i< num_instrument; i++){
        // sumAssets += ERC4626(instruments[i]).totalAssets(); 
        shares = ERC4626(instruments[i]).balanceOf(address(this));
        sumAssets += ERC4626(instruments[i]).convertToAssets(shares); 
    }
    return sumAssets; 
  }

  /// @notice returns real time or delayed exchange rate for this vault and its underlying
  /// oracle can be customized, or set default  
  /// returns Pvu 
  function queryExchangeRateOracle() public view  returns(uint256){
    // if default oracle 
    return previewMint(PRICE_PRECISION); //for 1 vault, how much underlying? 
    //return PRICE_PRECISION.divWadDown(previewDeposit(PRICE_PRECISION)); 
  }

  function isMatured() public view returns(bool){
    return true; 
    //return (block.timestamp - init_time) > time_to_maturity; 
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
  function getInitialExchangeRates() public view returns(uint[] memory){
      return initial_exchange_rates; 
  }
}
