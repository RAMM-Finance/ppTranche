pragma solidity ^0.8.9;

import "forge-std/console.sol";
import "./compound/Comptroller.sol"; 
import "./compound/CErc20.sol"; 

import {LeverageModule} from "./LeverageModule.sol"; 
import {WhitePaperInterestRateModel} from "./compound/WhitePaperInterestRateModel.sol"; 

import {ERC20} from "./vaults/tokens/ERC20.sol";
import {Splitter} from "./splitter.sol";
import {tVault} from "./tVault.sol";
import {SpotPool} from "./amm.sol"; 
import {PJSOracle} from "./oracles/jsOracle.sol"; 


/// @notice contract that stores the contracts and liquidity for each tranches 
contract TrancheFactory{

    uint256 public numVaults; 
    address owner; 
    address tMasterAd; 
    uint public id; 

    tLendTokenDeployer lendTokenFactory; 
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

    mapping(uint256=>Contracts) public vaultContracts;
    mapping(uint256=>mapping(address=>uint256)) lp_holdings;  //vaultId-> LP holdings for providrers
    mapping(uint256=> bool) public vaultCreated; 

    constructor(
        address _owner, 
        address ammFactory_address, 
        address splitterFactory_address, 
        address lendingPoolFactory_address,
        address lendTokenFactory_address
    ) public {
        owner = _owner;
        ammFactory = TrancheAMMFactory(ammFactory_address); 
        splitterFactory = SplitterFactory(splitterFactory_address); 
        lendingPoolFactory = tLendingPoolDeployer(lendingPoolFactory_address); 
        lendTokenFactory = tLendTokenDeployer(lendTokenFactory_address); 

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
    mapping(bytes32=>uint256) public vaultIds; 

    // step1
    function createVault(
        InitParams memory params, 
        string[] calldata names, 
        string calldata _description) public returns(uint256){
        require(tMasterAd != address(0), "trancheMaster not set"); 
        uint vaultId = id; 
        params.vaultId = vaultId; 
        // setupContracts(vaultId, params); 
        vaultCreated[vaultId] = true; 
        id++ ; 

        tVault newvault = new tVault(params); 
        Contracts storage contracts = vaultContracts[vaultId]; 
        contracts.vault = address(newvault); 
        contracts.param = params;
        vaultIds[keccak256(abi.encodePacked(params._want, params._junior_weight, params._promisedReturn  ))]
            = vaultId; 

        contracts.lendingPool = lendingPoolFactory.deployNewPool(); 
        return vaultId; 
    }   

    // step2
    function createSplitterAndPool(uint256 vaultId) external{
        Contracts storage contracts = vaultContracts[vaultId]; 

        address splitter = splitterFactory.newSplitter(tVault(contracts.vault), vaultId, tMasterAd); 

        (address junior, address senior) = Splitter(splitter).getTrancheTokens(); 
        address amm = ammFactory.newPool(senior, junior); 

        // set initial price to 1, liq to 0 
        SpotPool(amm).setPriceAndPoint(uint256(1e18)); 
        SpotPool(amm).setLiquidity0(); 

        contracts.splitter = splitter;
        contracts.amm = amm; 
    }

    // step 3
    function createLendingPools(uint256 vaultId) external{
        (address cSenior, address cJunior) = lendTokenFactory.deployNewCTokens(); 
        Contracts storage contracts = vaultContracts[vaultId]; 
        contracts.cSenior = cSenior; 
        contracts.cJunior = cJunior; 
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 

        PJSOracle newOracle = new PJSOracle(contracts.amm); 
        setUpCTokens(cSenior, cJunior, senior, junior, contracts.lendingPool );
        Comptroller(contracts.lendingPool)._setPriceOracle(newOracle); 
        Comptroller(contracts.lendingPool)._setCollateralFactor(CToken(cSenior), 1e18*8/10) ;       
        Comptroller(contracts.lendingPool)._setCollateralFactor(CToken(cJunior),  1e18*8/10);  
    }

    function setUpCTokens(
        address cSenior, 
        address cJunior, 
        address senior,
        address junior, 
        address comptroller) internal{
        CErc20(cSenior).init_(
            senior,
            comptroller, 
            interestRateModel, 
            1e18, 
            "cSenior",
            "cSenior",
            18); 
        require(Comptroller(comptroller)._supportMarket(CErc20(cSenior))
                ==0, "NewMarketERR");
        LeverageModule(cSenior).setTrancheMaster(tMasterAd, true); 
        // Comptroller(comptroller).markets(cToken).isListed
        CErc20(cJunior).init_(
            junior,
            comptroller, 
            interestRateModel, 
            1e18, 
            "cJunior",
            "cJunior",
            18); 

        require(Comptroller(comptroller)._supportMarket(CErc20(cJunior))
            == 0 , "NewMarketERR");

        LeverageModule(cJunior).setTrancheMaster(tMasterAd, false); 

        LeverageModule(cSenior).setPair(cJunior); 
        LeverageModule(cJunior).setPair(cSenior); 
    }

  
    /// @notice called right after deployed 
    function setTrancheMaster(address _tMasterAd) external {
        require(msg.sender == owner); 
        tMasterAd = _tMasterAd; 
    }
    function getParams(uint256 vaultId) public view returns(InitParams memory) {
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
        require(vaultCreated[vaultId], "Vault doesn't exist"); 
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


contract TrancheAMMFactory{

    address base_factory;
    mapping(address=>bool) _isPool; 
    constructor(){
        base_factory = msg.sender; 
    }

    function newPool(address baseToken, address tradeToken) external returns(address){
        SpotPool newAMM= new SpotPool( baseToken, tradeToken);
        _isPool[address(newAMM)] = true; 
        return address(newAMM); 
    }

    function isPool(address pooladd) public view returns(bool){
        return _isPool[pooladd]; 
    }
} 

contract SplitterFactory{

    function newSplitter(tVault newvault, uint vaultId, address tMasterAd) external returns(address){
        Splitter splitter = new Splitter(newvault, vaultId, tMasterAd); 
        return address(splitter); 
    }

}


contract tLendingPoolDeployer {
    uint salt; 

    function deployNewPool() public returns(address newPoolAd){
        uint _salt = salt; //random 

        bytes memory _creationCode = type(Comptroller).creationCode; 

        assembly{
            newPoolAd := create2(
                0, 
                add(_creationCode, 0x20), 
                mload(_creationCode), 
                _salt
            )
        }
        require(newPoolAd!=address(0), "Deploy failed"); 
        Comptroller(newPoolAd).setAdmin(msg.sender); 
        _salt++; 
        salt = _salt; 
    }

}

contract tLendTokenDeployer{
    uint salt; 
    function deployNewCTokens( ) public returns(address cSenior, address cJunior){
        uint _salt = salt; //random 

        bytes memory _creationCode = type(LeverageModule).creationCode; 

        assembly{
            cSenior := create2(
                0, 
                add(_creationCode, 0x20), 
                mload(_creationCode), 
                _salt
            )
        }
        _salt++; 

        require(cSenior != address(0), "cSenior deploy failed"); 
        LeverageModule(cSenior).setInitialAdmin(msg.sender); 
        // LeverageModule(cSenior).setTrancheMaster(master); 

        assembly{
            cJunior := create2(
                0, 
                add(_creationCode, 0x20), 
                mload(_creationCode), 
                _salt
            )
        }
        require(cJunior != address(0), "cJunior deploy failed"); 
        LeverageModule(cJunior).setInitialAdmin(msg.sender); 
        // LeverageModule(cJunior).setTrancheMaster(master); 
        _salt++; 
        salt = _salt; 
    }

}




















