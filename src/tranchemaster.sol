pragma solidity ^0.8.4;

import {ERC4626} from "./vaults/mixins/ERC4626.sol";

import {SafeCastLib} from "./vaults/utils/SafeCastLib.sol";
import {SafeTransferLib} from "./vaults/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./vaults/utils/FixedPointMathLib.sol";

import {ERC20} from "./vaults/tokens/ERC20.sol";
import {Splitter} from "./splitter.sol";
import {tVault} from "./tVault.sol";
import {SpotPool} from "./amm.sol"; 
import {tLendingPoolDeployer} from "./tLendingPoolFactory.sol";
import {CErc20} from "./compound/CErc20.sol"; 
import {WhitePaperInterestRateModel} from "./compound/WhitePaperInterestRateModel.sol"; 
import {Comptroller} from "./compound/Comptroller.sol"; 
import {LeverageModule} from "./LeverageModule.sol"; 

import "forge-std/console.sol";

contract TrancheAMMFactory{

    address base_factory;
    mapping(address=>bool) _isPool; 
    constructor(){
        base_factory = msg.sender; 
    }

    function newPool(address baseToken, address tradeToken) external returns(SpotPool){
        SpotPool newAMM= new SpotPool( baseToken, tradeToken);
        _isPool[address(newAMM)] = true; 
        return newAMM; 
    }

    function isPool(address pooladd) public view returns(bool){
        return _isPool[pooladd]; 
    }
} 

contract SplitterFactory{

    function newSplitter(tVault newvault, uint vaultId, address tMasterAd) external returns(Splitter){
        return new Splitter(newvault, vaultId, tMasterAd); 
    }

}

/// @notice contract that stores the contracts and liquidity for each tranches 
contract TrancheFactory{

    uint256 numVaults; 
    address owner; 
    address tMasterAd; 
    uint id; 

    tLendingPoolDeployer lendingPoolFactory; 
    TrancheAMMFactory ammFactory; 
    SplitterFactory splitterFactory; 
    WhitePaperInterestRateModel interestRateModel; 

    /// @notice initialization parameters for the vault
    struct InitParams{
        address _want; 
        address[]  _instruments;
        uint256[]  _ratios;
        uint256 _junior_weight; 
        uint256 _promisedReturn; //per time 
        uint256 _time_to_maturity;
        uint256 vaultId; 
        uint256 inceptionPrice; 
    }

    struct Contracts{
        address vault; 
        address splitter; 
        address amm; 
        address lendingPool; 
        address cSenior; 
        address cJunior; 
        InitParams param;
    }

    mapping(uint256=>Contracts) vaultContracts;
    mapping(uint256=>mapping(address=>uint256)) lp_holdings;  //vaultId-> LP holdings for providrers

    constructor(
        address _owner, 
        address ammFactory_address, 
        address splitterFactory_address, 
        address lendingPoolFactory_address
    ) public {
        owner = _owner;
        ammFactory = TrancheAMMFactory(ammFactory_address); 
        splitterFactory = SplitterFactory(splitterFactory_address); 
        lendingPoolFactory = tLendingPoolDeployer(lendingPoolFactory_address); 

        interestRateModel = new WhitePaperInterestRateModel(
            1e18,1e18); 
    }


    /// @notice adds vaults, spllitters, and amms when tranche bids are filled 
    /// Bidders have to specify the 
    /// param want: underlying token for all the vaults e.g(usdc,eth)
    /// param instruments: addresses of all vaults for the want they want exposure to
    /// param ratios: how much they want to split between the instruments 
    /// param junior weight: how much the juniors are allocated; lower means higher leverage for juniors but lower safety for seniors
    /// param promisedReturn: how much fixed income seniors are getting paid primarily, 
    /// param timetomaturity: when the tVault matures and tranche token holders can redeem their tranche for tVault 
    /// @dev a bid is filled when liquidity provider agrees to provide initial liq for senior/junior or vice versa.  
    /// so initial liq should be provided nonetheless 
    function createParams(
        address _want,
        address[] calldata _instruments,
        uint256[] calldata _ratios,
        uint256 _junior_weight, 
        uint256 _promisedReturn, //per time 
        uint256 _time_to_maturity,
        uint256 vaultId,
        uint256 inceptionPrice
        ) public returns(InitParams memory){
        return InitParams(
         _want,
         _instruments,
         _ratios,
         _junior_weight, 
         _promisedReturn, //per time 
         _time_to_maturity,
         vaultId,
         inceptionPrice
            );
    }

    function createVault(
        InitParams memory params, 
        string[] calldata names, 
        string calldata _description) public {
    
        uint vaultId = id;//marketFactory.createMarket(msg.sender, _description, names, param._ratios); 
        params.vaultId = vaultId; 
        setupContracts(vaultId, params); 
        id++ ; 
    }   

    function setupContracts(
        uint vaultId, 
        InitParams memory param) internal{
        require(tMasterAd != address(0), "trancheMaster not set"); 

        tVault newvault = new tVault(param); 
        Splitter splitter = splitterFactory.newSplitter(newvault, vaultId, tMasterAd); 
        (address junior, address senior) = splitter.getTrancheTokens(); 
        SpotPool amm = ammFactory.newPool(senior, junior); 

        // set cTokens
        (address cSenior, address cJunior) = lendingPoolFactory.deployNewCTokens(); 

        // set initial price to 1 
        amm.setPriceAndPoint(splitter.precision()); 

        Contracts storage contracts = vaultContracts[vaultId]; 
        contracts.vault = address(newvault); 
        contracts.splitter = address(splitter);
        contracts.amm = address(amm); 
        contracts.lendingPool = lendingPoolFactory.deployNewPool(); 
        contracts.param = param;
        contracts.cSenior = cSenior; 
        contracts.cJunior = cJunior; 

        setUpCTokens(cSenior, cJunior, address(newvault.want()), contracts.lendingPool );
    }

    function setUpCTokens(
        address cSenior, 
        address cJunior, 
        address underlying,
        address comptroller) internal{
        CErc20(cSenior).init_(
            underlying,
            comptroller, 
            interestRateModel, 
            1e18, 
            "cSenior",
            "cSenior",
            18); 
        Comptroller(comptroller)._supportMarket(CErc20(cSenior));
        LeverageModule(cSenior).setTrancheMaster(tMasterAd, true); 

        CErc20(cJunior).init_(
            underlying,
            comptroller, 
            interestRateModel, 
            1e18, 
            "cJunior",
            "cJunior",
            18); 

        Comptroller(comptroller)._supportMarket(CErc20(cJunior));
        LeverageModule(cJunior).setTrancheMaster(tMasterAd, false); 

        LeverageModule(cSenior).setPair(cJunior); 
        LeverageModule(cJunior).setPair(cSenior); 
    }

    /// @notice called right after deployed 
    function setTrancheMaster(address _tMasterAd) external {
        require(msg.sender == owner); 
        tMasterAd = _tMasterAd; 
    }
    function getParams(uint256 vaultId) public returns(InitParams memory) {
        return vaultContracts[vaultId].param; 
    }
    /// @notice lp token balance is stored in this contract
    function increaseLPTokenBalance(address to, uint vaultId, uint lpshares) external{
        lp_holdings[vaultId][to] += lpshares; 
    }
    function decreaseLPTokenBalance(address to, uint vaultId, uint lpshares) external{
        lp_holdings[vaultId][to] -= lpshares; 
    }

    function getContracts(uint vaultId) external view returns(Contracts memory){
        return vaultContracts[vaultId]; 
    }

    function getLPTokenBalance(address to, uint vaultId) external view returns(uint256){
        return lp_holdings[vaultId][to]; 
    }

    function getSuperVault(uint vaultId) external view returns(tVault){
        return tVault(vaultContracts[vaultId].vault); 
    }
    function getSplitter(uint vaultId) external view returns(Splitter){
        return Splitter(vaultContracts[vaultId].splitter); 
    }
    function getAmm(uint vaultId) external view returns(SpotPool){
        return SpotPool(vaultContracts[vaultId].amm); 
    }
    function getCSenior(uint vaultId) external view returns(CErc20){
        return CErc20(vaultContracts[vaultId].cSenior); 
    }
    function getCJunior(uint vaultId) external view returns(CErc20){
        return CErc20(vaultContracts[vaultId].cJunior); 
    }
}


/// @notice handles all trading related stuff 
/// Ideas for pricing: queue system, funding rates, fees, 
contract TrancheMaster{
    using FixedPointMathLib for uint256;
    uint256 constant precision = 1e18; 

    TrancheFactory tFactory;

    constructor(TrancheFactory _tFactory){
        tFactory = _tFactory; 
    }

    mapping(uint256=> DebtData) juniorDebts; //Price space=> debt
    mapping(uint256=> DebtData) seniorDebts; 
    mapping(bytes32=>uint256) dVaultPositions; 


    struct DebtData{
        // d or c stands for debt Or credit 
        uint256 juniorDorc; 
        uint256 seniorDorc; 
    }

    struct RedeemLocalvars{
        SpotPool amm;  
        Splitter splitter; 
        tVault vault; 

        uint256 multiplier; 
        address senior;
        address junior; 
        uint256 junior_weight; 

        uint256 pTv; //price of tranche/vault
        uint256 pju;
        uint256 psu; 
        uint256 pjs; 
        uint256 pvu; 

        uint256 vaultAmount; 
        uint256 dVaultPosition; 

        uint256 freeTranche; 
        uint256 trancheToBeFreed; 
        uint256 vaultCanBeFreed; 

        uint256 pairAmount; 
        uint256 totalAmount; 
        uint256 redeemVaultAmount; 
    }

    /// @notice redeems for debt vault to do arbitrage or slippage exit  
    /// such that a complete senior and junior pair need not be available 
    /// @param amount is amount of senior/junior wishing to redeem 
    function redeemToDebtVault(
        uint256 amount, 
        bool isSenior, 
        uint256 vaultId
        ) external returns(uint256){
        RedeemLocalvars memory vars; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        vars.amm = SpotPool(contracts.amm);
        vars.splitter = Splitter(contracts.splitter); 
        vars.junior_weight = vars.splitter.junior_weight(); 
        vars.multiplier = isSenior ? vars.junior_weight.divWadDown(precision - vars.junior_weight)
                                  : (precision - vars.junior_weight).divWadDown(vars.junior_weight);
        (vars.junior, vars.senior) = vars.splitter.getTrancheTokens();

        (vars.pju, vars.psu, vars.pjs) = vars.splitter.computeValuePrices();
        vars.pvu  = vars.splitter.underlying().queryExchangeRateOracle(); 
        vars.pTv = isSenior? vars.psu.divWadDown(vars.pvu) : vars.pju.divWadDown(vars.pvu);

        // redeem amount of junior or senior -> get how much vault is it worth
        vars.vaultAmount = vars.pTv.mulWadDown(amount); // pTv is one tranche worth pTv amount of vault 

        dVaultPositions[keccak256(abi.encodePacked(vaultId, msg.sender,isSenior, vars.pjs))] = vars.vaultAmount; 

        if(isSenior) {
            juniorDebts[vars.pjs].juniorDorc += vars.multiplier.mulWadUp(amount); 
            juniorDebts[vars.pjs].seniorDorc += amount; 
            ERC20(vars.senior).transferFrom(msg.sender,address(this), amount); 
        }
        else {
            seniorDebts[vars.pjs].seniorDorc += vars.multiplier.mulWadUp(amount); 
            seniorDebts[vars.pjs].juniorDorc += amount; 
            ERC20(vars.junior).transferFrom(msg.sender,address(this), amount); 
        }
        return vars.vaultAmount; 
    }

    /// @notice redeems debtVault to real Vault. 
    /// claims redeemable(where pair debt has been paid) dVault first in first out basis 
    function redeemFromDebtVault(
        uint256 dVaultAmount,
        uint256 pjs,  
        uint256 vaultId, 
        bool isSenior
        ) external returns(uint256){
        RedeemLocalvars memory vars; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        vars.splitter = Splitter(contracts.splitter); 
        vars.junior_weight = vars.splitter.junior_weight(); 
        vars.multiplier = isSenior ? vars.junior_weight.divWadDown(precision - vars.junior_weight)
                                  : (precision - vars.junior_weight).divWadDown(vars.junior_weight);
        vars.vault = tVault(contracts.vault); 

        // check how much debtVault can be redeemed 
        if(isSenior){
            // How much did the pair tranche redeem at given pjs 
            DebtData memory debtData = juniorDebts[pjs]; 
            vars.freeTranche = debtData.seniorDorc.mulWadUp(vars.multiplier) - debtData.juniorDorc; 
            vars.trancheToBeFreed = vars.freeTranche.divWadDown(vars.multiplier); 

            // get how much vault does this tranche translate to
            vars.totalAmount =  precision + vars.multiplier.mulWadDown(precision); 
            vars.pTv = vars.totalAmount.divWadDown(precision + precision.mulWadDown(vars.multiplier).mulWadDown(pjs));
            vars.vaultCanBeFreed = min(vars.trancheToBeFreed.mulWadDown(vars.pTv) ,  dVaultAmount); 

            // decrease global,redeemr's credit and transfer redeemable vault. revert if not enough
            juniorDebts[pjs].seniorDorc -= vars.vaultCanBeFreed.divWadDown(vars.pTv); 
            dVaultPositions[keccak256(abi.encodePacked(vaultId, msg.sender,isSenior, pjs))] -= vars.vaultCanBeFreed;
            vars.splitter.trustedBurn(true, address(this), vars.vaultCanBeFreed.divWadDown(vars.pTv)); 
            vars.vault.transferFrom(address(vars.splitter), msg.sender, vars.vaultCanBeFreed); 
        }

        else{
            DebtData memory debtData = seniorDebts[pjs]; 
            vars.freeTranche = debtData.juniorDorc.mulWadDown(vars.multiplier) - debtData.seniorDorc; 
            vars.trancheToBeFreed = vars.freeTranche.divWadDown(vars.multiplier);

            vars.totalAmount =  precision + vars.multiplier.mulWadDown(precision); 
            vars.pTv = vars.totalAmount.divWadDown(precision + precision.mulWadDown(vars.multiplier).divWadDown(pjs)); 
            vars.vaultCanBeFreed = min(vars.trancheToBeFreed.mulWadDown(vars.pTv) ,  dVaultAmount); 

            seniorDebts[pjs].juniorDorc -= vars.vaultCanBeFreed.divWadDown(vars.pTv); 
            dVaultPositions[keccak256(abi.encodePacked(vaultId, msg.sender,isSenior, pjs))] -= vars.vaultCanBeFreed; 
            vars.splitter.trustedBurn(false, address(this), vars.vaultCanBeFreed.divWadDown(vars.pTv)); 
            vars.vault.transferFrom(address(vars.splitter), msg.sender, vars.vaultCanBeFreed); 
        }
        return vars.vaultCanBeFreed; 
    }

    /// @notice traders who wish to use the queue built up to redeem their
    /// vault tokens without slippage at specific pjs 
    /// @param amount: amount to be redeemed. For example if want to redeem amount = 30 junior, 
    /// it will find 30* multiplier worth of senior to pair with from the debtVault minters
    function redeemByDebtVault(
        uint256 amount,
        uint256 pjs, 
        bool isSenior, 
        uint256 vaultId) external returns(uint256){

        RedeemLocalvars memory vars; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        vars.splitter = Splitter(contracts.splitter); 
        vars.vault = tVault(contracts.vault); 
        vars.junior_weight = vars.splitter.junior_weight(); 
        vars.multiplier = isSenior ? vars.junior_weight.divWadDown(precision - vars.junior_weight)
                                  : (precision - vars.junior_weight).divWadDown(vars.junior_weight);
        if(!isSenior) {
            // get total vault to be redeemed 
            vars.pairAmount = amount.mulWadDown(vars.multiplier); 
            vars.totalAmount = (amount + vars.pairAmount); 

            // compute price of junior/vault given pjs and totalamount 
            vars.pTv = vars.totalAmount.divWadDown(amount + vars.pairAmount.divWadDown(pjs)); 

            // how much vault will the redeemer get
            vars.redeemVaultAmount = amount.mulWadDown(vars.pTv);

            // reduce repayed debt and transfer, revert if not possible 
            require(juniorDebts[pjs].juniorDorc >= amount, "liqERR");   
            unchecked {juniorDebts[pjs].juniorDorc -= amount;} 
            vars.splitter.trustedBurn(false, msg.sender,  amount); 
            vars.vault.transferFrom(address(vars.splitter), msg.sender, vars.redeemVaultAmount);  
        }

        else{
            vars.pairAmount = amount.mulWadDown(vars.multiplier); 
            vars.totalAmount = (amount + vars.pairAmount); 

            vars.pTv = vars.totalAmount.divWadDown(amount + vars.pairAmount.mulWadDown(pjs));

            vars.redeemVaultAmount = amount.mulWadDown(vars.pTv); 

            require(seniorDebts[pjs].seniorDorc >= amount, "liqERR"); 
            unchecked {seniorDebts[pjs].seniorDorc -= amount; }
            vars.splitter.trustedBurn(true, msg.sender, amount); 
            vars.vault.transferFrom(address(vars.splitter), msg.sender, vars.redeemVaultAmount);
        }
        return vars.redeemVaultAmount; 
    }

    /// @notice for traders who want to unredeem their debt vault back to the initial position 
    /// @param amount is amount of dVault wishing to redeem back to the tranche
    function unRedeemDebtVault(
        uint256 amount,
        uint256 pjs, 
        bool isSenior, 
        uint256 vaultId) external{
        RedeemLocalvars memory vars; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        vars.splitter = Splitter(contracts.splitter); 
        vars.junior_weight = vars.splitter.junior_weight(); 
        vars.multiplier = isSenior ? vars.junior_weight.divWadDown(precision - vars.junior_weight)
                                  : (precision - vars.junior_weight).divWadDown(vars.junior_weight);

        (vars.junior, vars.senior) = vars.splitter.getTrancheTokens();

        if(isSenior){
            // get how much vault does the amount translate to, given pjs. 
            vars.totalAmount =  precision + vars.multiplier.mulWadDown(precision); 
            vars.pTv = vars.totalAmount.divWadDown(precision + precision.mulWadDown(vars.multiplier).mulWadDown(pjs));
            vars.freeTranche = amount.divWadDown(vars.pTv); 

            // Revert by underflow if can't be unredeemed 
            juniorDebts[pjs].juniorDorc -= vars.multiplier.mulWadDown(vars.freeTranche); 
            juniorDebts[pjs].seniorDorc -= amount.divWadDown(vars.pTv); 
            dVaultPositions[keccak256(abi.encodePacked(vaultId, msg.sender,isSenior, pjs))] -= amount; 

            ERC20(vars.senior).transfer(msg.sender, vars.freeTranche); 
        }

        else{
            vars.totalAmount =  precision + vars.multiplier.mulWadDown(precision); 
            vars.pTv = vars.totalAmount.divWadDown(precision + precision.mulWadDown(vars.multiplier).divWadDown(pjs)); 
            vars.freeTranche = amount.divWadDown(vars.pTv); 

            seniorDebts[pjs].seniorDorc -= vars.multiplier.mulWadDown(vars.freeTranche);
            seniorDebts[pjs].juniorDorc -= amount.divWadDown(vars.pTv); 
            dVaultPositions[keccak256(abi.encodePacked(vaultId, msg.sender,isSenior, pjs))] -= amount; 

            ERC20(vars.junior).transfer(msg.sender, vars.freeTranche); 
        }
    }


    struct SwapLocalvars{    
        SpotPool amm; 
        ERC20 want; 
        tVault vault; 
        Splitter splitter; 

        address senior;
        address junior; 

        uint256 amountIn;
        uint256 amountOut; 

        uint256 juniorAmount; 
        uint256 seniorAmount; 

    }

    /// @notice function for swapping from junior->senior and vice versa
    /// @dev positive amount for junior is denominated in junior, negavtive amount in senior, vice versa
    function _swapFromTranche(
        bool toJunior, 
        int256 amount, 
        uint256 priceLimit, 
        uint256 vaultId, 
        bytes calldata data
        ) public returns(uint256 amountIn, uint256 amountOut){
        SwapLocalvars memory vars; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        vars.amm = SpotPool(contracts.amm);
        vars.splitter = Splitter(contracts.splitter); 
        (vars.junior, vars.senior) = vars.splitter.getTrancheTokens();

        // Make a trade first so that price after the trade can be used
        (amountIn,  amountOut) =
            vars.amm.takerTrade(msg.sender, toJunior, amount, priceLimit, data);

        // get mark/index price 
        (uint indexPsu, uint indexPju,  ) = vars.splitter.computeValuePrices(); 
        (uint markPsu, uint markPju) = vars.splitter.computeImpliedPrices(
            vars.amm.getCurPrice() // TODO!! ez manipulation cache it somehow
            );
            
        // fee is always denominated in amountOut 
        if(toJunior && markPju+feeThreshold < indexPju){
            uint fee = getFee(indexPju, markPju); 
            ERC20(vars.junior).transferFrom(msg.sender,address(vars.splitter), fee);
        }
        else if(!toJunior && markPju > indexPju + feeThreshold){
            uint fee = getFee(indexPsu, markPsu); 
            ERC20(vars.senior).transferFrom(msg.sender, address(vars.splitter), fee);
        }
    }

    /// @notice buy tranche token from vault. 
    /// @dev Split the vault and swap unwanted to wanted tranche
    /// @param amount is amount of vault to split 
    function _swapFromInstrument(
        bool toJunior, 
        uint256 amount, 
        uint priceLimit, 
        uint vaultId, 
        bytes calldata data) public returns(uint256 amountIn, uint256 amountOut){

        SwapLocalvars memory vars; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        vars.amm = SpotPool(contracts.amm);
        vars.splitter = Splitter(contracts.splitter); 
        vars.vault = tVault(contracts.vault); 
        (vars.junior, vars.senior) = vars.splitter.getTrancheTokens();

        vars.vault.transferFrom(msg.sender, address(this), amount); 
        vars.vault.approve(address(vars.splitter), amount); 
        (vars.juniorAmount,  vars.seniorAmount) = vars.splitter.split(amount); //junior and senior now minted to this address 
        vars.amountIn = toJunior ? vars.seniorAmount : vars.juniorAmount; 

        if (toJunior) ERC20(vars.senior).approve(address(vars.amm), vars.amountIn); 
        else ERC20(vars.junior).approve(address(vars.amm), vars.amountIn);
        (amountIn, amountOut) 
            = vars.amm.takerTrade(address(this), toJunior, int256(vars.amountIn), priceLimit, data); 

        if(!toJunior) ERC20(vars.senior).transfer(msg.sender, amountOut + vars.seniorAmount );
        else ERC20(vars.junior).transfer(msg.sender, amountOut + vars.juniorAmount);  
    }

    /// @notice two ways to buy junior/senior from underlying 
    /// first is minting vault, splitting, and trading unwanted to wanted(either by taker or maker)
    /// This function is for taker swapping 
    /// @dev I param wantSenior of param amount
    /// param price limit is the max price of junior/senior. Ideally transaction should 
    /// fail if priceLimit != current price, which should be pjs
    function swapFromUnderlying(
        bool wantSenior, 
        uint amount,
        uint vaultId,
        uint priceLimit) 
        public {
        SwapLocalvars memory vars; 
        bytes memory data; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        vars.amm = SpotPool(contracts.amm);
        vars.vault = tVault(contracts.vault); 
        vars.splitter = Splitter(contracts.splitter); 
        vars.want = ERC20(contracts.param._want); 
        (vars.junior, vars.senior) = vars.splitter.getTrancheTokens();

        // Mint to this addres
        vars.want.transferFrom(msg.sender, address(this), amount); 
        vars.want.approve(address(vars.vault), amount); 
        uint shares = vars.vault.convertToShares(amount); 
        vars.vault.mint(shares, address(this));

        // Split to this address and swap 
        vars.vault.approve(address(vars.splitter), shares); 
        (uint juniorAmount, uint seniorAmount) = vars.splitter.split( shares); //junior and senior now minted to this address 
        uint amountIn = wantSenior? juniorAmount : seniorAmount; 
        (, uint poolamountOut) = vars.amm.takerTrade(address(this), !wantSenior, int256(amountIn), priceLimit, data); 

        if(wantSenior) ERC20(vars.senior).transfer(msg.sender, poolamountOut + seniorAmount );
        else ERC20(vars.junior).transfer(msg.sender, poolamountOut + juniorAmount);  
  
    }   

    /// @notice people can lend their Junior/senior tokens to earn more yield,
    /// where the lent out tokens will be used for leverage   
    function supplyToLendingPool(uint256 vaultId, bool isSenior, uint256 amount) external {
        // TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        // CErc20(contracts.cSenior).mint()

    }

    function lendFromLendingPool(uint256 vaultId, bool isSenior, uint256 amount) external{
        // if(isSenior) 
        //     CErc20(contracts.cSenior).b(address payable borrower, uint borrowAmount)
    }

    uint256 constant feeThreshold = 1e16; 
    uint256 constant kpi = 0; 

    /// @notice calculates trading fee when current price is offset from value price
    /// by feeThreshold param
    function getFee(uint256 p1, uint256 p2) public view returns(uint256){
        return kpi*(p1-p2); 
    }
    function swapToUnderlying() public{}
    function swapFromTranche() external{}
    function swapFromInstrument() external {}
    function swapToRatio() external{}

    /// @notice when a new tranche is initiated, and trader want senior or junior, can place bids/asks searching for
    /// a counterparty
    function freshTrancheNewOrder() external{}

    /// @notice atomic leverage swap from junior to senior or senior to junior
    /// If senior to junior, need to use junior as collateral and borrow more senior to get more junio
    /// and vice versa
    function leverageSwap() external {}

    /// @notice executes arb by pair redeeming
    /// It will fetch appropriate junior amounts from the debt pool =
    /// param senior is true if arbitrageur has senior and want junior to pair
    function arbByPairRedeem(bool senior, uint amount) external {
        // if(senior) fetchFromDebtPool(junior )
    }

    /// @notice route optimal redeem path for given pjs
    function redeemOptimal() public {}


    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    function getdVaultBal(uint256 vaultId, address who, bool isSenior, uint256 pjs) public view returns(uint256){
        return dVaultPositions[keccak256(abi.encodePacked(vaultId,who,isSenior, pjs))];
    }

    function getDorc(uint256 pjs) public view returns(uint256, uint256,uint256, uint256){
        return( juniorDebts[pjs].juniorDorc , 
                juniorDebts[pjs].seniorDorc , 
                seniorDebts[pjs].juniorDorc ,
                seniorDebts[pjs].juniorDorc);
    }

    function getPTV(uint256 pjs, bool isSenior, uint256 junior_weight) public view returns(uint256 pTv){
        uint256 multiplier = isSenior ? junior_weight.divWadDown(precision - junior_weight)
                             : (precision - junior_weight).divWadDown(junior_weight);
        uint256 totalAmount =  precision + multiplier.mulWadDown(precision); 
        pTv = isSenior ? totalAmount.divWadDown(precision + precision.mulWadDown(multiplier).mulWadDown(pjs))
                       : totalAmount.divWadDown(precision + precision.mulWadDown(multiplier).divWadDown(pjs)); 

    }

}















    // /// @notice adds liquidity to pool with vaultId
    // /// @dev amount is denominated in want of the tVault, so want-> mint tVault-> split -> provide 
    // function addLiquidity(
    //     address provider,
    //      uint amount, 
    //      uint vaultId) external returns(uint){  
    //     TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
    //     ERC20 want = ERC20(contracts.param._want); 
    //     tVault vault = tVault(contracts.vault); 
    //     StableSwap amm = StableSwap(contracts.amm); 
    //     Splitter splitter = Splitter(contracts.splitter); 

    //     //Mint tVault
    //     want.transferFrom(provider, address(this), amount); 
    //     want.approve(address(vault), amount ); 
    //     uint shares = vault.convertToShares(amount);
    //     vault.mint(shares, address(this)); 

    //     //Split 
    //     vault.approve(address(splitter), shares);
    //     (uint ja, uint sa) = splitter.split(vault, shares); 

    //     //provide(same amount to get a balanced pool)
    //     uint lpshares = separatAndProvide(ja, sa, splitter, amm); 
    //     // uint[2] memory amounts; 
    //     // amounts[0] = ja; 
    //     // amounts[1] = ja; 
    //     // address[] memory tranches = splitter.getTrancheTokens(); 
    //     // ERC20(tranches[0]).approve(address(amm), sa);
    //     // ERC20(tranches[1]).approve(address(amm), ja); 
    //     // uint lpshares = amm.addLiquidity(amounts, 0); 

    //     //Transfer
    //     tFactory.increaseLPTokenBalance(provider, vaultId, lpshares);

    //     return lpshares; 

    // }

    // function separatAndProvide(uint ja, uint sa, Splitter splitter, StableSwap amm) internal returns(uint){
    //     uint[2] memory amounts; 
    //     amounts[0] = ja; 
    //     amounts[1] = ja; 
    //     address[] memory tranches = splitter.getTrancheTokens(); 
    //     ERC20(tranches[0]).approve(address(amm), sa);
    //     ERC20(tranches[1]).approve(address(amm), ja); 
    //     uint lpshares = amm.addLiquidity(amounts, 0); 
    //     return lpshares; 
    // }

    // /// @notice remove liquidity from the pool, and gives back merged token
    // function removeLiquidity(
    //     address taker, 
    //     uint shares, 
    //     uint vaultId) external {
    //     TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
    //     ERC20 want = ERC20(contracts.param._want); 
    //     tVault vault = tVault(contracts.vault); 
    //     StableSwap amm = StableSwap(contracts.amm); 
    //     Splitter splitter = Splitter(contracts.splitter); 

    //     //Transfer
    //     tFactory.decreaseLPTokenBalance(taker, vaultId, shares); 

    //     //Remove
    //     uint[2] memory minAmounts;
    //     minAmounts[0] =0;
    //     minAmounts[1] =0;
    //     uint[2] memory amountsOut = amm.removeLiquidity(shares,minAmounts);
    //     uint junioramount = amountsOut[1]; 

    //     //Merge-> junior and senior in, tVault out to this address
    //     uint merged_token_amount = splitter.merge(vault, junioramount); 

    //     //Redeem vault 
    //     vault.redeem(merged_token_amount, taker, address(this)); 

    // }



    // /// @notice buy tranche token in one tx from underlying tVault collatera; 
    // /// @param amount is collateral in 
    // /// @dev 1.Mints vault token
    // /// 2. Splits Vault token from splitter 
    // /// 3. Swap unwanted tToken to wanted tToken
    // /// 4. Transfer wanted tToken to user 
    // function buy_tranche(
    //     uint vaultId, 
    //     uint amount, 
    //     bool wantSenior
    //     ) external returns(uint)
    // {
    //     TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
    //     ERC20 want = ERC20(contracts.param._want); 
    //     tVault vault = tVault(contracts.vault); 
    //     StableSwap amm = StableSwap(contracts.amm); 
    //     Splitter splitter = Splitter(contracts.splitter); 

    //     //1.Mint
    //     want.transferFrom(msg.sender, address(this), amount); 
    //     want.approve(address(vault), amount); 
    //     uint shares = vault.convertToShares(amount); 
    //     vault.mint(shares, address(this));

    //     //2. Split
    //     vault.approve(address(splitter), shares); 
    //     (uint ja, uint sa) = splitter.split(vault, shares); //junior and senior now minted to this address 

    //     //Senior tokens are indexed at 0 in each amm 
    //     uint tokenIn = wantSenior? 1 : 0;
    //     uint tokenOut = 1-tokenIn; 
    //     uint tokenInAmount = wantSenior? ja: sa; 
    //     address[] memory tranches = splitter.getTrancheTokens(); 

    //     //3. Swap 
    //     ERC20(tranches[tokenIn]).approve(address(amm), tokenInAmount); 
    //     uint tokenOutAmount = amm.swap(tokenIn, tokenOut, tokenInAmount, 0); //this will give this contract tokenOut

    //     //4. Transfer 
    //     uint transferamount = wantSenior? sa: ja; 
    //     ERC20(tranches[tokenOut]).transfer(msg.sender, transferamount + tokenOutAmount); 
    //     return transferamount + tokenOutAmount; 

    // }

    // /// @notice sell tranche token for collateral in one tx
    // /// 1. Transfer tToken 
    // /// 2. Swap tTokens to get in correct ratio
    // function sell_tranche(
    //     uint vaultId, 
    //     uint amount, 
    //     bool isSenior 
    //     ) external 
    // {
    //     TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
    //     ERC20 want = ERC20(contracts.param._want); 
    //     tVault vault = tVault(contracts.vault); 
    //     StableSwap amm = StableSwap(contracts.amm); 
    //     Splitter splitter = Splitter(contracts.splitter); 

    //     //1. Transfer tToken to this contract
    //     address[] memory tranches = splitter.getTrancheTokens(); 
    //     uint tokenIn = isSenior? 0:1; 
    //     ERC20(tranches[tokenIn]).transfer(msg.sender, amount); 

    //     //2. Swap to get correct ratio, if intoken is senior then need junior, 
    //     (uint pairTokenAmount, uint swappedTokenAmount) = swapToRatio(amount, !isSenior, tranches, vault, amm); 
    //     uint amountAfterSwap =  amount - swappedTokenAmount; 
    //     //amountAfterSwap, pairTokenAmount should be the amount of tranche tokens in ratio 

    //     //3.Merge the tokens (merged tVault token will be directed to this contract)
    //     uint junior_amount = isSenior? pairTokenAmount: swappedTokenAmount;  
    //     uint totalAmountMerged = splitter.merge(vault, junior_amount); 

    //     //4.Redeem merged token in tVault  
    //     vault.redeem(totalAmountMerged, msg.sender, address(this)); 


    // }

    // /// @notice swap portion of tToken to another to get the correct ratio
    // /// e.x 100 junior-> 30 senior, 70 junior, when ratio is 3:7
    // function swapToRatio(
    //     uint tokenInAmount, 
    //     bool needSenior,
    //     address[] memory tranches,
    //     tVault vault, 
    //     StableSwap amm) internal returns(uint, uint){
    
    //     //get swapping Token index; if senior is needed swap junior
    //     uint tokenInIndex = needSenior? 1:0;
    //     uint tokenOutIndex = 1- tokenInIndex; 
    //     address neededToken = tranches[tokenOutIndex]; 
    //     address swappingToken = tranches[tokenInIndex]; 
    //     uint junior_weight = vault.getJuniorWeight();
    //     uint PRICE_PRECISION = vault.PRICE_PRECISION();   
        
    //     //ex. 100j -> 30j, 70s (determined by ratio)
    //     // need x amount of juniors for 70s 
    //     uint neededTokenOutAmount; 
    //     if (needSenior)  neededTokenOutAmount = (PRICE_PRECISION - junior_weight) * tokenInAmount; 
    //     else  neededTokenOutAmount = junior_weight * tokenInAmount; 

    //     //Get how much tokenInAmount I need to get needed tokenoutAmount 
    //     uint neededTokenInAmount = amm.getDx(neededTokenOutAmount, tokenInIndex); 
    //     uint TokenOutAmount = amm.swap(tokenInIndex, tokenOutIndex, neededTokenInAmount,0 ); 
    //     //Now this contract has the neededTokenAmountOut tokens

    //     return (TokenOutAmount, neededTokenInAmount);
    // }


// library Debt{

//     struct dVaultPosition{
//         // amount of minted dVault 
//         uint256 dVaultAmount; 

//         // amount of tranche token that was used to mint dVault, using this pTv can be inferred
//         uint256 trancheAmount; 
//     }

//     struct DebtData{
//         // d or c stands for debt Or credit 
//         uint256 juniorDorc; 
//         uint256 seniorDorc; 
//     }

//     function add(
//         mapping(bytes32=> uint256) storage self, 
//         uint256 vaultId, 
//         address creator,
//         bool isSenior, 
//         uint256 pjs, 
//         uint256 dVaultAmount
//         ) internal{
//         self[keccak256(abi.encodePacked(vaultId, creator,isSenior, pjs))] = dVaultAmount; 
//     }

//     function get(
//         mapping(bytes32=> uint256) storage self, 
//         uint256 vaultId, 
//         address creator, 
//         bool isSenior, 
//         uint256 pjs
//         ) internal view returns(uint256){
//         return self[keccak256(abi.encodePacked(vaultId, creator, isSenior, pjs))]; 
//     }
// }
// library Queues{

//    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
//         if (y < 0) {
//             require((z = x - uint128(-y)) < x, 'LS');
//         } else {
//             require((z = x + uint128(y)) >= x, 'LA');
//         }
//     }

//     // Data for single queue slot 
//     struct QueueSlot{
//         uint128 startQueueAmount; 
//         uint128 remainingQueueAmount;
//     }

//     // Manages an array of queueSlots
//     struct Queue{
//         uint128 first; 
//         uint128 last; 
//     }

//     function enqueue(
//         mapping(uint128 => Queues.QueueSlot) storage self, 
//         Queue storage queue, 
//         QueueSlot memory data) public {
//         queue.last += 1;

//         self[queue.last] = data;
//     }

//     function dequeue(
//         mapping(uint128 => Queues.QueueSlot) storage self,
//         Queue storage queue
//         ) public {
//         Queue memory _queue = queue; 
//         assert(_queue.last >= _queue.first + 1);  // non-empty queue
//         delete self[_queue.first];
//         queue.first += 1;
//     }

//     /// @notice gets address indexed queueslot
//     function get(
//         mapping(bytes32=> Queues.QueueSlot) storage self, 
//         address maker, 
//         bool isSenior 
//         ) internal returns(QueueSlot storage){
//         return self[keccak256(abi.encodePacked(maker, isSenior))]; 
//     }

//     function update(
//         QueueSlot storage self,
//         int128 amount) internal {
//         self.remainingQueueAmount = addDelta(self.remainingQueueAmount, amount); 
//     }

//     function len(Queue storage self) internal view returns(uint256){
//         Queue memory _queue = self; 
//         assert(_queue.last >= _queue.first + 1);  // non-empty queue
//         unchecked { return uint256(_queue.last- (_queue.first + 1)); }
//     }



//    using Queues for mapping(bytes32=> Queues.QueueSlot); 
//     using Queues for mapping(uint128 => Queues.QueueSlot); 
//     using Queues for Queues.Queue; 
//     using Queues for Queues.QueueSlot; 

//     struct QueueData{
//         mapping(bytes32=> Queues.QueueSlot) positions; //queueslots indexed by address
//         mapping(uint128 => Queues.QueueSlot) map;// queueslots indexed by numbers
//         Queues.Queue indexData; 
//     }

//     mapping(uint256=> QueueData) public JuniorQueue; //per vault
//     mapping(uint256=> QueueData) public SeniorQueue; //per vault
//     uint256 constant MAXSIZE = 100; 

//     /// @notice create queue bids to be filled 
//     function addNewQueue(
//         uint256 vaultId, 
//         bool isSenior, 
//         uint256 amount
//         ) external {
//         QueueData storage data = isSenior? SeniorQueue[vaultId] : JuniorQueue[vaultId]; 

//         Queues.QueueSlot storage queueSlot 
//                 = data.positions.get(msg.sender, isSenior); 

//         queueSlot.remainingQueueAmount = uint128(amount); //TODO safecast 
//         queueSlot.startQueueAmount = uint128(amount); 

//         // Push new slot to front 
//         data.map.enqueue(queueSlot, data.indexData); 
        
//         // Get rid of oldest slot  
//         if(data.indexData.last >= MAXSIZE) 
//             data.map.dequeue(data.indexData); 

//         // Escrow funds 
//         Splitter splitter = tFactory.getContracts(vaultId).splitter; 
//         if(isSenior) ERC20(splitter.getTrancheTokens()[0]).transferFrom(msg.sender,address(this), amount); 
//         else ERC20(splitter.getTrancheTokens()[1]).transferFrom(msg.sender,address(this), amount);
//     }

//     struct Fillvars{
//         uint256 len; 
//         uint256 junior_weight; 
//         uint256 multiplier; 
//         uint256 amountRemaining; 
//         uint256 filled;

//         uint256 pTv; //price of tranche/vault
//         uint256 pju;
//         uint256 psu; 
//         uint256 pjs;  

//         address senior;
//         address junior; 

//         uint128 i; 

//         uint256 totalRedeemed; 
//         uint256 fillerShare;
//         uint256 filleeShare; 
//         uint256 arbitrageProfit
//     }

//     /// @notice fill queues and do arb
//     /// ifSenior, the queuelist is junior, and the filler is senior specified in amouunt 
//     function fillQueue(
//         uint256 vaultId, 
//         bool isSenior, 
//         uint256 amount,
//         uint256 markPrice
//         ) external {
//         QueueData storage data = isSenior? JuniorQueue[vaultId] : SeniorQueue[vaultId]; 
//         Fillvars memory vars; 
//         Splitter splitter = tFactory.getContracts(vaultId).splitter; 

//         vars.junior_weight = splitter.junior_weight();
//         vars.len = data.indexData.len();
//         vars.i = data.indexData.first; 
//         vars.amountRemaining = amount; 
//         vars.multiplier = isSenior ? junior_weight.divWadDown(precision - junior_weight)
//                                   : (precision - junior_weight).divWadDown(junior_weight);
        
//         while (vars.amountRemaining != 0 || vars.i < vars.len){

//             vars.amountRemaining -= fillQueueSlot(data.map[vars.i],
//                  vars.amountRemaining.mulWadDown(vars.multiplier));
//             vars.i++;
//         }

//         // amount of isSenior filled 
//         vars.filled = amount - vars.amountRemaining; 

//         (vars.senior, vars.junior) = splitter.getTrancheTokens();

//         // Merge, this will spit back vault here 
//         if(isSenior) {
//             uint256 junior_amount = vars.filled.mulWadDown(vars.multiplier); 
//             ERC20(vars.senior).approve(address(splitter), vars.filled); 
//             ERC20(vars.junior).approve(address(splitter), junior_amount); 
//             splitter.merge(junior_amount);
//         }

//         // convert senior amount to junior amount
//         else {
//             ERC20(vars.junior).approve(address(splitter), vars.filled); 
//             ERC20(vars.senior).approve(address(splitter), vars.filled.mulWadDown(vars.multiplier)); 
//             splitter.merge(vars.filled); 
//         }

//         // get pjv(and psv), the exchange rate of junior/vault which is pju/pvu 
//         (vars.pju, vars.psu, vars.pjs) = splitter.computeValuePrices();
//         vars.pvu  = splitter.underlying().queryExchangeRateOracle(); 
//         vars.pTv = isSenior? vars.psu.divWadDown(vars.pvu) : vars.pju.divWadDown(vars.pvu);

//         // isSenior, 106 seniors are filling a queue of 45 juniors 
//         vars.totalRedeemed = vars.filled + vars.filled.mulWadDown(vars.multiplier); 
//         vars.fillerShare = vars.pTv.mulWadDown(vars.filled); // 1 senior/junior is worth pTv of vault  
//         vars.filleeShare = totalRedeemed - fillerShare; 

//         // get arbitrage profit for filler, from markPrice vs Pjs
//             {
//                 uint256 tranchePurchased = vars.filled.divWadDown(precision 
//                     + vars.multiplier.mulWadDown(markPrice));
//                 uint256 trancheFromValue = tranchePurchased.mulWadDown(
//                     precision + vars.multiplier.mulWadDown(vars.pTv)); 

//                 // Arbitrage profit denominated in trancheToken  
//                 vars.arbitrageProfit = vars.filled - trancheFromValue; 
//             } 

//         // return to filler/fillee his share of vault 
//         vars.fillerShare -= vars.arbitrageProfit.mulWadDown(precision - _getFillerShare(vaultId)); 
//         vars.filleeShare += vars.arbitrageProfit.mulWadDown(precision - _getFillerShare(vaultId)); 

//     }

//     /// @notice fill single queue, so amount stored in queue should decrease by param amount
//     function fillQueueSlot(
//         Queues.QueueSlot storage queue, 
//         uint256 amount
//         ) internal returns(uint256 filledAmount){
//         if (queue.queueAmount >= amount) {
//             queue.update(-int128(amount)); 
//             filledAmount = amount; 
//         }   
//         else {
//             queue.update(-int128(queue.queueAmount)); 
//             removeQueue(queue); 
//             filledAmount = queue.queueAmount; 
//         } 
//     }

//     function removeQueue(Queues.QueueSlot memory queue ) external{
//         delete queueSlots[queue.idx]; 
//     }

//     function modifyQueue() external{}

//     function setFillerShare(uint256 vaultId, uint256 newFillerShare) external {
//         fillerShareDelta[vaultId] = newFillerShare; 
//     }
//     function setDefaultFillerShare(uint256 newDefaultFillerShare) external{
//         defaultFillerShare = newDefaultFillerShare; 
//     }
//     function _getFillerShare(uint256 vaultId) internal {
//         defaultFillerShare + fillerShareDelta[vaultId]; 
//     }


//     mapping(uint256=>uint256) public fillerShareDelta; 
//     uint256 defaultFillerShare; 


// }
    // mapping(uint256=> mapping(bytes32=> Queues.QueueSlot)) public QueuePositions; //vaultId=> address indexed queueslot
    // mapping(uint256=> mapping(uint128 => Queues.QueueSlot)) public QueueMap; //vaultId=> queue
    // mapping(uint256=> Queues.Queue) public Queue; 

