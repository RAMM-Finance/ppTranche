// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/splitter.sol";
import "../src/tranchemaster.sol";
import "../src/tVault.sol";
import "../src/vaults/tokens/ERC20.sol";
import "../src/vaults/mixins/ERC4626.sol";
import "../src/tLendingPoolFactory.sol"; 
import "../src/compound/Comptroller.sol"; 
import {SpotPool} from "../src/amm.sol"; 

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
}


function almostEqual(
    uint256 x,
    uint256 y,
    uint256 p
) view {
    uint256 diff = x > y ? x - y : y - x;
    if (diff / p != 0) {
        console.log(x);
        console.log("is not almost equal to");
        console.log(y);
        console.log("with p of:");
        console.log(p);
        revert();
    }
}

contract TVaultTest is Test {
    using stdStorage for StdStorage; 

    Splitter public splitter;
    TrancheFactory public tFactory; 
    testErc want; 
    TrancheMaster tmaster;
    uint256 constant precision = 1e18;  
    tLendingPoolDeployer lendingPoolFactory; 
    function setUp() public {
        SplitterFactory splitterFactory = new SplitterFactory(); 
        TrancheAMMFactory ammFactory = new TrancheAMMFactory(); 
        lendingPoolFactory = new tLendingPoolDeployer(); 

        tFactory = new TrancheFactory(
            address(this), 
            address(ammFactory), 
            address(splitterFactory), 
            address(lendingPoolFactory)
        ); 

        want = new testErc(); 
        tmaster = new TrancheMaster(tFactory); 

        want.mint(address(this), precision*100000); 
        createVault(); 

        mintAndSplit(10); 

    }

    function createVault() public {
        address[] memory instruments = new address[](2); 
        instruments[0] =  address( new testVault( want)); 
        instruments[1] =  address( new testVault( want )); 

        uint256[] memory ratios = new uint256[](2); 
        ratios[0] = (precision*5)/10; 
        ratios[1] = (precision*5)/10 ;

        string[] memory names = new string[](2); 
        names[0] = "n"; 
        names[1] = "nn"; 

        tFactory.setTrancheMaster(address(tmaster)); 
        tFactory.createVault(
            tFactory.createParams(address(want), instruments,ratios,(precision * 3)/10, 
                1e18 + 1e16,100,
            1, precision), 
            names, "d" );  
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

    function doApproval() public{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);

        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        ERC20(junior).approve(contracts.amm, type(uint256).max); 
        ERC20(senior).approve(contracts.amm, type(uint256).max); 
        ERC20(junior).approve(address(tmaster), type(uint256).max); 
        ERC20(senior).approve(address(tmaster), type(uint256).max); 
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

    function doPrintDorc(uint pjs) public{
        {
            (uint a, uint b, uint c, uint d) = tmaster.getDorc( pjs); 
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

    function testMintingSplitting() public {
        //mintAndSplit(); 
    }

    function testPriceCompute() public {

        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        stdstore
            .target(contracts.splitter)
            .sig(Splitter(contracts.splitter).elapsedTime.selector)
            .checked_write(2); 
        (uint psu, uint pju, uint pjs) = Splitter(contracts.splitter).computeValuePrices(); 

        assertApproxEqAbs((pju * precision)/psu, pjs, 10); 
    }


    function testSwapFromTranche() public {
        doLimit(); 
        doApproval(); 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        // contracts.
        bytes memory data; 

        (uint amountIn, uint amountOut) = tmaster._swapFromTranche(true, -int256(precision), 0, 0, data); 
        assertApproxEqAbs(amountOut, precision, 10);
                console.log('curprice', SpotPool(contracts.amm).getCurPrice()); 

    }

    function testSwapFromInstrument() public {
        doLimit(); 
        doMintVaultApproval(); 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);

        bytes memory data; 
        // need vault, 
        bool up = true; 
        (uint amountIn, uint amountOut) 
            = tmaster._swapFromInstrument(up, precision, (precision*11)/10, 0, data); 

        // amountin is senior->junior so senior 
        if (up) assertApproxEqAbs(precision * 7/10, amountIn, 10); 
                console.log('curprice', SpotPool(contracts.amm).getCurPrice()); 
    }

    struct testVar{

        uint psu; 
        uint pju; 
        uint pjs_;
        uint seniorBal;
        uint j;
        uint s; 

        uint jdj; 
        uint jds; 
        uint sdj;
        uint sds;

        uint vaultbal; 

        address senior; 
        address junior;

        uint ptv; 
        uint ptvPrime;  
    }

    function testRedeemToDebtVault() public{
        doLimit(); 
        doApproval(); 
        testVar memory vars; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 

        // first let somebody buy up more than curprice (buy junior from senior)
        bytes memory data; 
        uint pricebefore =  SpotPool(contracts.amm).getCurPrice(); 
        (uint amountIn, uint amountOut) = tmaster._swapFromTranche(true, -int256(precision/2), 0, 0, data); 
        assertApproxEqAbs(amountOut, precision/2, 10);
        (,, uint pjs) = Splitter(contracts.splitter).computeValuePrices(); 
        assert(pricebefore < SpotPool(contracts.amm).getCurPrice() &&
               SpotPool(contracts.amm).getCurPrice() > pjs); 
        
        // mint new pair, split it, and sell it to senior 
        // doSetElaspedTime( 1); 
        
        (vars.psu, vars.pju, vars.pjs_) = Splitter(contracts.splitter).computeValuePrices();
        // assert(psu >= pju); 
        
        // now junior is overpriced, so need to sell junior to senior and convert senior to debtvault, arbitraary price
        vars.seniorBal = ERC20(senior).balanceOf(address(this)); 
        (vars.j, vars.s) = mintAndSplit(1); 
        (amountIn, amountOut) = tmaster._swapFromTranche(false, int256(vars.j), 0, 0, data); 
        assertApproxEqAbs(amountIn, vars.j, 10);
        assertEq(vars.seniorBal + vars.s+ amountOut, ERC20(senior).balanceOf(address(this))); 
        assert(amountOut + vars.s > precision); 

        // now redeem senior
        uint vaultAmount = tmaster.redeemToDebtVault(
            vars.s+ amountOut, 
            true, 0); 
        assertEq(ERC20(senior).balanceOf(address(tmaster)), vars.s+ amountOut); 
        assertEq(tmaster.getdVaultBal( 0, address(this), true, vars.pjs_), vaultAmount);

        doPrintDorc(vars.pjs_); 

        //TODO test arbitrage profit 
    }

    function testNaiveRedeemFromDebtVaultsShouldBeZero() public {
        doLimit(); 
        doApproval();
        testVar memory vars; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);

        (vars.j, vars.s) = mintAndSplit(1); 

        uint vaultAmount = tmaster.redeemToDebtVault(
            vars.s, 
            true, 0); 
        (vars.psu, vars.pju, vars.pjs_) = Splitter(contracts.splitter).computeValuePrices();
        doPrintDorc(vars.pjs_); 

        // try to redeem 
        uint canberedeemed = tmaster.redeemFromDebtVault(
         vaultAmount,
        vars.pjs_,0,true 
        ); 
        assertEq(canberedeemed, 0); 
    }

    function testRedeemFromDebtVaultAndByDebtVault() public {
        doLimit(); 
        doApproval();
        testVar memory vars; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);

        (vars.j, vars.s) = mintAndSplit(1); 

        uint vaultAmount = tmaster.redeemToDebtVault(
            vars.s, 
            true, 0); 
        (vars.psu, vars.pju, vars.pjs_) = Splitter(contracts.splitter).computeValuePrices();
        doPrintDorc(vars.pjs_); 
        (vars.jdj, vars.jds, vars.sdj, vars.sds) = tmaster.getDorc(vars.pjs_); 
        doPrintSupplys(); 

        // now let junior redeem 
        uint splitterbal = tVault(contracts.vault).balanceOf(contracts.splitter); 
        tmaster.redeemByDebtVault(
        vars.j,
        vars.pjs_ , 
        false, 
        0); 
        (uint jdj, uint jds, uint sdj, uint sds) = tmaster.getDorc(vars.pjs_); 
        assertApproxEqAbs(vars.jdj - jdj, vars.j , 10 ); 
        assertEq(vars.jds, jds); 
        doPrintDorc(vars.pjs_); 

        // now should be redeemable 
        vars.vaultbal = tVault(contracts.vault).balanceOf(address(this)); 
        uint canberedeemed = tmaster.redeemFromDebtVault(
         vaultAmount,
        vars.pjs_,0,true 
        ); 
        doPrintDorc(vars.pjs_); 
        ( jdj,  jds,  sdj,  sds) = tmaster.getDorc(vars.pjs_); 
        assertEq(jdj,0);
        assertEq(jds,0); 
        assertApproxEqAbs(splitterbal - tVault(contracts.vault).balanceOf(contracts.splitter) ,
            vars.j + vars.s, 10); 
        assertApproxEqAbs(tVault(contracts.vault).balanceOf(address(this)) - vars.vaultbal, vaultAmount, 10 );
        doPrintSupplys();
    }

    function testUnredeemVault() public{
        doLimit(); 
        doApproval();
        testVar memory vars; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        (vars.junior, vars.senior) = Splitter(contracts.splitter).getTrancheTokens(); 

        (vars.j, vars.s) = mintAndSplit(1); 

        // first redeem to debt vault 
        uint seniorbalbefore = ERC20(vars.senior).balanceOf(address(this));
        uint vaultAmount = tmaster.redeemToDebtVault(
            vars.s, 
            true, 0); 
        (vars.psu, vars.pju, vars.pjs_) = Splitter(contracts.splitter).computeValuePrices();
        doPrintDorc(vars.pjs_); 
        (vars.jdj, vars.jds, vars.sdj, vars.sds) = tmaster.getDorc(vars.pjs_); 
        doPrintSupplys(); 
        assertApproxEqAbs(seniorbalbefore -ERC20(vars.senior).balanceOf(address(this)), vars.s, 10 ); 

        // then unredeem 
        tmaster.unRedeemDebtVault(
            vaultAmount, vars.pjs_, true, 0); 
        (uint jdj, uint jds, uint sdj, uint sds) = tmaster.getDorc(vars.pjs_); 
        assertApproxEqAbs(jdj,0,1);
        assertApproxEqAbs(jds,0,1);
        assertEq(sdj,0);
        assertEq(sds,0);
        assertApproxEqAbs(seniorbalbefore, ERC20(vars.senior).balanceOf(address(this)), 10); 
        doPrintDorc(vars.pjs_); 
    }

    function testArbitrageProfitHigherPriceSenior() public{
        // arb cycle is higher price than pjs, mint/swap senior to junior, redeem it 
        doLimit(); 
        doApproval(); 
        testVar memory vars; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 

        // first let somebody buy up more than curprice (buy junior from senior)
        bytes memory data; 
        uint pricebefore =  SpotPool(contracts.amm).getCurPrice(); 
        (uint amountIn, uint amountOut) = tmaster._swapFromTranche(true, -int256(precision/2), 0, 0, data); 
        assertApproxEqAbs(amountOut, precision/2, 10);
        (,, uint pjs) = Splitter(contracts.splitter).computeValuePrices(); 
        assert(pricebefore < SpotPool(contracts.amm).getCurPrice() &&
               SpotPool(contracts.amm).getCurPrice() > pjs); 
        
        // mint new pair, split it, and sell it to senior 
        // doSetElaspedTime( 1); 
        
        (vars.psu, vars.pju, vars.pjs_) = Splitter(contracts.splitter).computeValuePrices();
        // assert(psu >= pju); 
        vars.ptv = tmaster.getPTV( vars.pjs_, true, Splitter(contracts.splitter).junior_weight()); 
        vars.ptvPrime = tmaster.getPTV(doGetPrice(), true, Splitter(contracts.splitter).junior_weight());
        assert(vars.ptv > vars.ptvPrime); 


        // now junior is overpriced, so need to sell junior to senior and convert senior to debtvault, arbitraary price
        vars.seniorBal = ERC20(senior).balanceOf(address(this));
        // ok, so this is the vault used 
        (vars.j, vars.s) = mintAndSplit(1); 

        (amountIn, amountOut) = tmaster._swapFromTranche(false, int256(vars.j), 0, 0, data); 
        assertApproxEqAbs(amountIn, vars.j, 10);
        assertEq(vars.seniorBal + vars.s+ amountOut, ERC20(senior).balanceOf(address(this))); 
        assert(amountOut + vars.s > precision); 
        console.log('curprice,pjs', doGetPrice(), vars.pjs_); 
        // now redeem senior
        uint vaultAmount = tmaster.redeemToDebtVault(
            vars.s+ amountOut, 
            true, 0); 
        assertEq(ERC20(senior).balanceOf(address(tmaster)), vars.s+ amountOut); 
        assertEq(tmaster.getdVaultBal( 0, address(this), true, vars.pjs_), vaultAmount);
        console.log('vaultOut, vaultIn', vaultAmount, precision); 
        doPrintDorc(vars.pjs_);

    }

    // function simulateLongTermProfitAllJunior() public{
    //     doLimit(); 
    //     doApproval();
    //     testVar memory vars; 
    //     TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
    //     (vars.junior, vars.senior) = Splitter(contracts.splitter).getTrancheTokens(); 

    //     // 0.3 j, 0.7 s, swap to all junior 
    //     (vars.j, vars.s) = mintAndSplit(1); 
    //     bytes memory data; 
    //     (uint amountIn, uint amountOut) = tmaster._swapFromTranche(true, int256(vars.s), 0, 0, data); 
    //     ERC20(vars.junior).balanceOf(address(this)); 

    function testDeployNewLendingPool() public {
        // address ad = lendingPoolFactory.deployNewPool(); 
        // console.log(Comptroller(ad). mintAllowed(address(this), address(this), 0));  
    }

    // }
//Tests todo:
    //TODO do above with opposite, differing prices, differing fixed rate,differing elasped time, under different states
    // oracles test, tvault test
    //function testSwapFromUnderlying
    //
   // function testArbitrageProfitWithVaryingElapsedTime() public {}
   // function testInitialLiquidityProvision() public {}
//TODO more tests, tvault+oracle add, add tranchemaster, kaishi, 



    
}
