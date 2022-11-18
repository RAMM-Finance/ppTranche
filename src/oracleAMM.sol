// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {SafeCast, FixedPointMath} from "./libraries.sol"; 
import {ERC20} from "./vaults/tokens/ERC20.sol"; 
import {ERC4626} from "./vaults/mixins/ERC4626.sol"; 
import {SafeTransferLib} from "./vaults/utils/SafeTransferLib.sol";
import "forge-std/console.sol";
import {Splitter} from "./splitter.sol"; 
import {tVault} from "./tVault.sol";

/// @notice AMM where price is set by an oracle, not reserves
/// splitted asset(tranches) are always summed to be denominated in asset
/// by price of asset/tranche. 
contract OracleJSPool is ERC4626 {
    using FixedPointMath for uint256 ;
    using SafeTransferLib for ERC20;

    ERC20 BaseToken; //junior
    ERC20 TradeToken; //senior 

    Splitter splitter;
    tVault vault;  

    uint256 public fees; 
    uint256 public constant precision = 1e18; 

    uint256 juniorfeeAccumulated; 
    uint256 seniorfeeAccumulated; 
    uint256 withdrawalFee; 
    uint256 public constant dust = 1; 

    /// @notice asset is the volatile asset to split 
    constructor(
        address _baseToken, 
        address _tradeToken, 
        address asset_address, 
        address splitter_address, 
        address vault_address
        )ERC4626(
        ERC20(asset_address),
        string(abi.encodePacked(ERC20(asset_address).name(), " tVault")),
        string(abi.encodePacked(ERC20(asset_address).name(), " tVault"))
        )
    {
        BaseToken = ERC20(_baseToken); 
        TradeToken = ERC20(_tradeToken); 
        splitter = Splitter(splitter_address); 
        vault = tVault(vault_address); 

        vault.approve(splitter_address, type(uint256).max); 
    }

    /// @notice fees are in WAD, 1e17 means 10 percent 
    function setFees(uint256 _fees, uint256 _withdrawalFee) external {
        fees = _fees; 
        withdrawalFee = _withdrawalFee; 
    }

    function getCurPrice() external returns(uint256){
        (, , uint256 pjs) =  splitter.computeValuePricesView(); 
        return pjs; 
    }

    function handleBuys(address recipient, uint256 amountOut, uint256 amountIn, bool up) internal {

        if(up){
            require(TradeToken.balanceOf(address(this))>= amountOut, "Not enough Liq"); 
            require(BaseToken.balanceOf(recipient)>= amountIn, "Not enough balance"); 

            unchecked{TradeToken.transfer(recipient, amountOut);}
            BaseToken.transferFrom(recipient, address(this), amountIn);
        }
        else{
            require(BaseToken.balanceOf(address(this))>= amountOut, "Not enough Liq");
            require(TradeToken.balanceOf(recipient)>= amountIn, "Not enough balance"); 

            unchecked{BaseToken.transfer(recipient, amountOut);}
            TradeToken.transferFrom(recipient, address(this), amountIn);
        }
    }

    /// @notice get price from oracle and trade with infinite liquidity 
    function takerTrade(
        address recipient, 
        bool toJunior, 
        uint256 amountIn
        ) external returns(uint256 amountOut){

        (,,uint256 pjs) = splitter.computeValuePricesView(); 
        require(pjs != 0, "0 price");

        // Get penalized/subsidized prices to balance pool 
        pjs = getAdjustedPrices(pjs); 

        uint256 frontrunPenalty = getPenalty(amountIn); 
        amountOut  = toJunior? amountIn.divWadDown(pjs) : pjs.mulWadDown(amountIn); 
        amountOut = amountOut.mulWadDown(precision - fees-frontrunPenalty); 

        handleBuys(recipient, amountOut, amountIn, toJunior);
    }

    /// @notice gets prices that takes into account the balance of the pool
    /// since it needs to incentivize there always be some liquidity on both sides  
    function getAdjustedPrices(uint256 pjs) public view returns(uint256){
        return pjs; //TODO
    }

    /// @notice oracle frontrun penalty TODO
    function getPenalty(uint256 amountIn) public view returns(uint256){
        return 0; 
    }

    /// @notice let splitter split to this address 
    function afterDeposit(uint256 assets, uint256 shares) internal override {
        
        // Mint tvault to be splitted 
        asset.approve(address(vault), assets); 
        vault.deposit(assets, address(this)); 

        // split to this address to be used for liq
        splitter.split(assets); 
    }
 
    /// @notice due to non-homogeneity withdraws in tranche tokens instead of asset 
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

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        (uint256 seniorBal, uint256 juniorBal) = computeAssetsReturned(assets); 
        (uint256 jfee, uint256 sfee) = (juniorBal.mulWadDown(withdrawalFee), seniorBal.mulWadDown(withdrawalFee)); 

        juniorfeeAccumulated += jfee;
        seniorfeeAccumulated += sfee; 

        TradeToken.safeTransfer(receiver, juniorBal); 
        BaseToken.safeTransfer(receiver, seniorBal); 
    }

    /// @notice due to non-homogeneity redeems in tranche tokens instead of asset 
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.

        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        (uint256 seniorBal, uint256 juniorBal) = computeAssetsReturned(assets); 
        (uint256 jfee, uint256 sfee) = (juniorBal.mulWadDown(withdrawalFee), seniorBal.mulWadDown(withdrawalFee)); 

        juniorfeeAccumulated += jfee;
        seniorfeeAccumulated += sfee; 

        TradeToken.safeTransfer(receiver, juniorBal-jfee-dust); 
        BaseToken.safeTransfer(receiver, seniorBal- sfee-dust);  
    }

    struct LocalVars{
        uint256 seniorBal; 
        uint256 juniorBal; 
        uint256 junior_weight; 
        uint256 multiplier; 
        bool missing;
        uint256 assetsByRatio; 
        uint256 leftOverTranche; 
        uint256 pjs; 
        uint256 pTv; 
        uint256 leftOverAsset; 
        uint256 pJv; 
        uint256 pSv; 
        uint256 ratio; 
    }
    bool computeFromLeftOver; 


    /// @notice gets the reserves values denominated in asset 
    function totalAssets() public view override returns(uint256){
        // If nobody has split the asset, then totalasset is 0 
        if(splitter.senior().totalSupply() == 0) return 0; 

        LocalVars memory vars; 
        (vars.seniorBal, vars.juniorBal) 
            = (BaseToken.balanceOf(address(this)), TradeToken.balanceOf(address(this))); 
        vars.junior_weight = splitter.junior_weight(); 
        vars.multiplier = vars.junior_weight.divWadDown(precision - vars.junior_weight); //3/7
        (,,vars.pjs) = splitter.computeValuePricesView(); 

        if(computeFromLeftOver){
            // get how much assets can be generated from reserves by ratio 
            vars.missing = vars.multiplier.mulWadDown(vars.seniorBal)< vars.juniorBal; //400> 800 from 100,800
            vars.assetsByRatio = vars.missing
                    ? vars.seniorBal + vars.seniorBal.mulWadDown(vars.multiplier)
                    : vars.juniorBal + vars.juniorBal.divWadDown(vars.multiplier); 

            vars.leftOverTranche = vars.missing
                        ? vars.juniorBal - vars.multiplier.mulWadDown(vars.seniorBal)  //missing junior 
                        : vars.seniorBal - vars.juniorBal.divWadDown(vars.multiplier); //missing senior

      
            // Convert how much the leftover tranche translates to asset 
            vars.pTv = getPTV(vars.pjs, !vars.missing, vars.junior_weight );
            vars.leftOverAsset = vars.pTv.mulWadDown(vars.leftOverTranche); 

            return (vars.leftOverAsset + vars.assetsByRatio); 
        }

        vars.pSv = getPTV(vars.pjs, true, vars.junior_weight); 
        vars.pJv = getPTV(vars.pjs, false, vars.junior_weight); 

        return vars.pSv.mulWadDown(vars.seniorBal) + vars.pJv.mulWadDown(vars.juniorBal ); 
    }

    /// @notice given asset and current pjs, solve for the equation
    /// bal * psv + reserveratio * bal* pjv = asset,
    /// where bal and bal* reserveratio are senior and junior quantities 
    /// for the given qty of assets such that everyone can redeem prorata 
    function computeAssetsReturned(uint256 assets) public view returns(uint256, uint256){
        LocalVars memory vars; 
        vars.junior_weight = splitter.junior_weight(); 
        vars.ratio = getCurrentReserveRatio(); 
        (,,vars.pjs) = splitter.computeValuePricesView(); 

        vars.pSv = getPTV(vars.pjs, true, vars.junior_weight); 
        vars.pJv = getPTV(vars.pjs, false, vars.junior_weight); 

        vars.seniorBal = assets.divWadDown(vars.pSv + vars.ratio.mulWadUp(vars.pJv)); 
        vars.juniorBal = vars.seniorBal.mulWadDown(vars.ratio); 

        return (vars.seniorBal, vars.juniorBal);  
    }

    /// @notice return the ratio of junior/senior reserves 
    function getCurrentReserveRatio() public view returns(uint256){
        return TradeToken.balanceOf(address(this)).divWadDown(BaseToken.balanceOf(address(this))); 
    }

    function getPTV(uint256 pjs, bool isSenior, uint256 junior_weight) public pure returns(uint256 pTv){
        uint256 multiplier = isSenior ? junior_weight.divWadDown(precision - junior_weight)
                             : (precision - junior_weight).divWadDown(junior_weight);

        pTv = isSenior ? (multiplier + precision).divWadDown(multiplier.mulWadDown(pjs)+ precision)
                       : (multiplier + precision).divWadDown(multiplier.divWadDown(pjs)+ precision); 
    }

    /// @notice get who's tranches amount denominated in asset 
    function denomintateInAsset(address who) public view returns(uint256){
        LocalVars memory vars; 
        vars.junior_weight = splitter.junior_weight();
        (vars.seniorBal, vars.juniorBal) 
            = (BaseToken.balanceOf(who), TradeToken.balanceOf(who)); 
        (,,vars.pjs) = splitter.computeValuePricesView(); 

        vars.pSv = getPTV(vars.pjs, true, vars.junior_weight); 
        vars.pJv = getPTV(vars.pjs, false, vars.junior_weight); 

        return vars.pSv.mulWadDown(vars.seniorBal) + vars.pJv.mulWadDown(vars.juniorBal ); 
    }

}



