// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/splitter.sol";
import {TrancheMaster} from "../src/tranchemaster.sol";
import "../src/tVault.sol";
import "../src/vaults/tokens/ERC20.sol";
import "../src/vaults/mixins/ERC4626.sol";
import "../src/factories.sol"; 
import "../src/compound/Comptroller.sol"; 
import {SpotPool} from "../src/amm.sol"; 
import {LeverageModule} from "../src/LeverageModule.sol"; 
contract testVault is ERC4626{
    constructor(ERC20 want)ERC4626( want,"a","a" ){

    }
    function totalAssets() public view override returns(uint256){
     return totalFloat();
    }

    function totalFloat() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}

contract testErc is ERC20{
    constructor()ERC20("n", "n", 18){}
    function mint(address to, uint256 amount) public {
        _mint(to, amount); 
    }
    function faucet(uint256 amount) public{
        _mint(msg.sender, amount); 
    }
}

contract base is Test{
    using stdStorage for StdStorage; 

    Splitter public splitter;
    TrancheFactory public tFactory; 
    testErc want; 
    TrancheMaster tmaster;
    uint256 constant precision = 1e18;  
    tLendingPoolDeployer lendingPoolFactory; 
    tLendTokenDeployer lendTokenFactory; 
    address jonna;
    address jott; 
    address gatdang;
    address sybal; 
    address chris; 
    address miku;
    address tyson; 
    address yoku;
    address toku; 
    address goku; 
    function setUpPeople() public{
        jonna = address(0xbabe);
        vm.label(jonna, "jonna"); 
        jott = address(0xbabe2); 
        vm.label(jott, "jott");  
        gatdang = address(0xbabe3); 
        vm.label(gatdang, "gatdang"); 
        sybal = address(0xbabe4);
        vm.label(sybal, "sybal");
        chris=address(0xbabe5);
        vm.label(chris, "chris");
        miku = address(0xbabe6);
        vm.label(miku, "miku"); 
        goku = address(0xbabe7); 
        vm.label(goku, "goku"); 
        toku = address(0xbabe8);
        vm.label(toku, "toku"); 

        vm.prank(jonna); 
        want.faucet(100000*precision);
        vm.prank(jott); 
        want.faucet(100000*precision);
        vm.prank(gatdang); 
        want.faucet(100000*precision); 
        vm.prank(sybal); 
        want.faucet(100000*precision); 
        vm.prank(chris); 
        want.faucet(100000*precision); 
        vm.prank(miku); 
        want.faucet(100000*precision); 
        vm.prank(goku);
        want.faucet(100000*precision); 
        vm.prank(toku);
        want.faucet(100000*precision);
    }
    function setUp() public {
        SplitterFactory splitterFactory = new SplitterFactory(); 
        TrancheAMMFactory ammFactory = new TrancheAMMFactory(); 
        lendingPoolFactory = new tLendingPoolDeployer(); 
        lendTokenFactory = new tLendTokenDeployer(); 

        tFactory = new TrancheFactory(
            address(this), 
            address(ammFactory), 
            address(splitterFactory), 
            address(lendingPoolFactory), 
            address(lendTokenFactory)
        ); 

        want = new testErc(); 
        tmaster = new TrancheMaster(tFactory); 

        want.mint(address(this), precision*100000); 
        createVault(); 

        mintAndSplit(20); 

        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0); 

        stdstore
            .target(contracts.amm)
            .sig(SpotPool(contracts.amm).liquidity.selector)
            .checked_write(uint128(0)); 
        setUpPeople();
        // vm.warp(block.timestamp+0); 

    }

    function manipulateTimeAndAssetsAndSupply(
        uint256 warpTo, 
        uint256 totalAssetsDelta, 
        uint256 totalSupplyDelta) public {
        vm.warp(block.timestamp+warpTo); 

    }
    function createVault() public {
        address[] memory instruments = new address[](2); 
        instruments[0] =  address( new testVault( want)); 
        instruments[1] =  address( new testVault( want )); 

        uint256[] memory ratios = new uint256[](2); 
        ratios[0] = (precision*7)/10; 
        ratios[1] = (precision*3)/10 ;

        string[] memory names = new string[](2); 
        names[0] = "n"; 
        names[1] = "nn"; 

        tFactory.setTrancheMaster(address(tmaster)); 
        uint vaultId = tFactory.createVault(
            tFactory.createParams(address(want), instruments,ratios,(precision * 3)/10, 
                1e18 + 1e16,100,
            1, precision), 
            names, "d" );  
        tFactory.createSplitterAndPool( vaultId) ;
        tFactory.createLendingPools( vaultId);
    }

    function mintAndSplit(uint256 shares) public returns(uint256, uint256){
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0); 
        want.approve(contracts.vault, type(uint256).max); 
        shares = shares*precision; 
        tVault(contracts.vault).mint(shares, address(this)); 
        tVault(contracts.vault).approve(contracts.splitter, type(uint256).max);
        return Splitter(contracts.splitter).split(shares); 
    }

    function doLimit() public {
        uint256 amountInToBid = 1*precision; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        ERC20(junior).approve(contracts.amm, type(uint256).max); 
        SpotPool(contracts.amm).makerTrade( false, amountInToBid, 101); 
    }
    function doLimitSpecified(uint256 amountInToBid, bool limitBelow) public {
        if(!limitBelow){
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        ERC20(junior).approve(contracts.amm, type(uint256).max); 
        SpotPool(contracts.amm).makerTrade( false, amountInToBid, 101); 
        }
        else{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        ERC20(senior).approve(contracts.amm, type(uint256).max); 
        SpotPool(contracts.amm).makerTrade( true, amountInToBid, 99); 
        }
    }

    function doApproval() public{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);

        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        ERC20(junior).approve(contracts.amm, type(uint256).max); 
        ERC20(senior).approve(contracts.amm, type(uint256).max); 
        ERC20(junior).approve(address(tmaster), type(uint256).max); 
        ERC20(senior).approve(address(tmaster), type(uint256).max); 
        tVault(contracts.vault).approve(address(tmaster), type(uint256).max); 
        tVault(contracts.vault).approve(contracts.splitter, type(uint256).max);

    }

    function doMintVaultApproval() public {
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        tVault(contracts.vault).mint(10*precision, address(this)); 
        tVault(contracts.vault).approve(address(tmaster), type(uint256).max); 
    }

    function doSetElaspedTime(uint256 time) public{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        stdstore
            .target(contracts.splitter)
            .sig(Splitter(contracts.splitter).elapsedTime.selector)
            .checked_write(time); 
    }

    function doPrintDorc(uint vaultId, uint pjs) public{
        {
            (uint a, uint b, uint c, uint d) = tmaster.getDorc(vaultId, pjs); 
            console.log('dorc', a,b); 
            console.log(c,d); 
        }
    }
    function doPrintSupplys() public{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        console.log(
            'supplies',
            ERC20(junior).totalSupply(), 
            ERC20(senior).totalSupply()
            ); 
    }
    function doGetPrice() public returns(uint256){
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        return SpotPool(contracts.amm).getCurPrice(); 
    }   
    function doLimitSpecifiedPoint(uint256 amountInToBid, bool limitBelow, uint16 point) public {
        if(!limitBelow){
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        ERC20(junior).approve(contracts.amm, type(uint256).max); 
        SpotPool(contracts.amm).makerTrade( false, amountInToBid, point); 
        }
        else{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        ERC20(senior).approve(contracts.amm, type(uint256).max); 
        SpotPool(contracts.amm).makerTrade( true, amountInToBid, point); 
        }
    }

}