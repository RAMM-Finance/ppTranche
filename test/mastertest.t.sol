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
import {base} from "./testbase.sol"; 
import {tLens} from "../src/tLens.sol"; 

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

contract TVaultTest is base {
    using stdStorage for StdStorage; 

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

        uint balbefore;
        uint balAfter; 
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

    function testMint() public {
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        uint amount = 1* precision ; 
        uint balbefore = want.balanceOf(jonna); 
        vm.prank(jonna); 
        want.approve(address(tmaster),amount); 
        vm.prank(jonna); 
        tmaster.mintTVault(0, amount); 

        assertEq(tVault(contracts.vault).balanceOf(jonna), 
            tVault(contracts.vault).previewDeposit(amount)); 
        assertEq(balbefore - want.balanceOf(jonna), amount); 
    }

    function testRedeem() public {
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        uint amount = 1* precision ; 
        uint balbefore = want.balanceOf(jonna); 

        vm.prank(jonna); 
        want.approve(address(tmaster),amount); 
        vm.prank(jonna); 
        tmaster.mintTVault(0, amount); 

        assertEq(tVault(contracts.vault).balanceOf(jonna), 
            tVault(contracts.vault).previewDeposit(amount)); 
        assertEq(balbefore - want.balanceOf(jonna), amount); 
        uint bal = tVault(contracts.vault).previewDeposit(amount); 
        vm.prank(jonna);
        tVault(contracts.vault).approve(address(tmaster),type(uint256).max ); 
        vm.prank(jonna); 
        tmaster.redeemTVault(0, bal);
        assertEq(tVault(contracts.vault).balanceOf(jonna), 0); 
        assertEq(balbefore, want.balanceOf(jonna) ); 
    }

    function testSplit() public{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        uint amount = 1* precision ; 
        uint balbefore = want.balanceOf(jonna); 
        vm.prank(jonna); 
        want.approve(address(tmaster),amount); 
        vm.prank(jonna); 
        tmaster.mintTVault(0, amount); 

        assertEq(tVault(contracts.vault).balanceOf(jonna), 
            tVault(contracts.vault).previewDeposit(amount)); 
        assertEq(balbefore - want.balanceOf(jonna), amount); 
        uint bal = tVault(contracts.vault).previewDeposit(amount); 

        vm.prank(jonna); 
        tVault(contracts.vault).approve(address(tmaster),type(uint256).max ); 
        vm.prank(jonna); 
        tmaster.splitTVault(0,bal);
        // (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        // assertApproxEqAbs(ERC20(junior).balanceOf(jonna),
        //     Splitter(contracts.splitter).junior_weight() * precision ) 

    }
    function testMerge() public{}

    function testSwapFromTranche() public {
        // doLimit(); 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        testVar memory vars; 
        (vars.junior, vars.senior) = Splitter(contracts.splitter).getTrancheTokens();
        SpotPool pool = SpotPool(contracts.amm); 
        uint amountInToBid = 12* precision; 
        bool limitBelow = true; 
        uint16 delta = 1; 

        uint16 point = limitBelow? pool.priceToPoint(pool.getCurPrice())- delta
        : pool.priceToPoint(pool.getCurPrice()) + delta; 
        uint256 amountToSwap = amountInToBid/2; 

        doLimitSpecifiedPoint( amountInToBid,  limitBelow,  point);
        doApproval(); 

        bytes memory data; 
        vars.balbefore = limitBelow? ERC20(vars.senior).balanceOf(address(this)) : ERC20(vars.junior).balanceOf(address(this)); 
        (uint amountIn, uint amountOut) = tmaster._swapFromTranche(
            !limitBelow, int256(amountToSwap), 0, 0, data); 
        // assertApproxEqAbs(amountOut, precision, 10);
        vars.balAfter = limitBelow? ERC20(vars.senior).balanceOf(address(this)) : ERC20(vars.junior).balanceOf(address(this)); 

        assertApproxEqAbs(vars.balAfter - vars.balbefore, amountOut, 10); 
    }

    function testFailSwapFromTranche1() public {
        //no bids 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        testVar memory vars; 
        (vars.junior, vars.senior) = Splitter(contracts.splitter).getTrancheTokens();
        SpotPool pool = SpotPool(contracts.amm); 
        uint amountInToBid = 12* precision; 
        bool limitBelow = false; 
        uint16 delta = 1; 

        uint16 point = limitBelow? pool.priceToPoint(pool.getCurPrice())- delta
        : pool.priceToPoint(pool.getCurPrice()) + delta; 
        uint256 amountToSwap = amountInToBid*2; 

        doLimitSpecifiedPoint( amountInToBid,  limitBelow,  point);
        doApproval(); 

        bytes memory data; 
        vars.balbefore = limitBelow? ERC20(vars.senior).balanceOf(address(this)) : ERC20(vars.junior).balanceOf(address(this)); 
        (uint amountIn, uint amountOut) = tmaster._swapFromTranche(
            !limitBelow, int256(amountToSwap), 0, 0, data); 
        // assertApproxEqAbs(amountOut, precision, 10);
        vars.balAfter = limitBelow? ERC20(vars.senior).balanceOf(address(this)) : ERC20(vars.junior).balanceOf(address(this)); 

        assertApproxEqAbs(vars.balAfter - vars.balbefore, amountOut, 10); 
    }

    function testSwapFromInstrument() public {
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        testVar memory vars; 
        (vars.junior, vars.senior) = Splitter(contracts.splitter).getTrancheTokens();
        SpotPool pool = SpotPool(contracts.amm); 
        mintAndSplit(100);
        uint amountInToBid = 12* precision; 
        bool limitBelow = true; 
        uint16 delta = 2; 

        uint16 point = limitBelow? pool.priceToPoint(pool.getCurPrice())- delta
        : pool.priceToPoint(pool.getCurPrice()) + delta; 
        uint256 amountToSwap = amountInToBid/2; 
        
        doApproval(); 
        doLimitSpecifiedPoint( amountInToBid,  limitBelow,  point);
        doMintVaultApproval(); 

        bytes memory data; 
        // need vault, 
        (uint amountIn, uint amountOut) 
            = tmaster._swapFromInstrument(!limitBelow, amountToSwap/2, (precision*11)/10, 0, data); 

        // amountin is senior->junior so senior 
        if (!limitBelow) assertApproxEqAbs(amountToSwap/2 * 7/10, amountIn, 10); 
        else assertApproxEqAbs(amountToSwap/2 * 3/10, amountIn, 10); 
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
        (uint vaultAmount,) = tmaster.redeemToDebtVault(
            vars.s+ amountOut, 
            true, 0); 
        assertEq(ERC20(senior).balanceOf(contracts.splitter), vars.s+ amountOut); 
        assertEq(tmaster.getdVaultBal( 0, address(this), true, vars.pjs_), vaultAmount);

        doPrintDorc(0, vars.pjs_); 

        //TODO test arbitrage profit 
    }

    function testNaiveRedeemFromDebtVaultsShouldBeZero() public {
        doLimit(); 
        doApproval();
        testVar memory vars; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);

        (vars.j, vars.s) = mintAndSplit(1); 

        (uint vaultAmount,) = tmaster.redeemToDebtVault(
            vars.s, 
            true, 0); 
        (vars.psu, vars.pju, vars.pjs_) = Splitter(contracts.splitter).computeValuePrices();
        doPrintDorc(0,vars.pjs_); 

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

        (uint vaultAmount,) = tmaster.redeemToDebtVault(
            vars.s, 
            true, 0); 
        (vars.psu, vars.pju, vars.pjs_) = Splitter(contracts.splitter).computeValuePrices();
        doPrintDorc(0,vars.pjs_); 
        (vars.jdj, vars.jds, vars.sdj, vars.sds) = tmaster.getDorc(0,vars.pjs_); 
        doPrintSupplys(); 

        // now let junior redeem 
        uint splitterbal = tVault(contracts.vault).balanceOf(contracts.splitter); 
        tmaster.redeemByDebtVault(
        vars.j,
        vars.pjs_ , 
        false, 
        0); 
        (uint jdj, uint jds, uint sdj, uint sds) = tmaster.getDorc(0,vars.pjs_); 
        assertApproxEqAbs(vars.jdj - jdj, vars.j , 10 ); 
        assertEq(vars.jds, jds); 
        doPrintDorc(0,vars.pjs_); 

        // now should be redeemable 
        vars.vaultbal = tVault(contracts.vault).balanceOf(address(this)); 
        uint canberedeemed = tmaster.redeemFromDebtVault(
         vaultAmount,
        vars.pjs_,0,true 
        ); 
        doPrintDorc(0,vars.pjs_); 
        ( jdj,  jds,  sdj,  sds) = tmaster.getDorc(0,vars.pjs_); 
        assertApproxEqAbs(jdj,0,1);
        assertApproxEqAbs(jds,0,1); 
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
        (uint vaultAmount,) = tmaster.redeemToDebtVault(
            vars.s, 
            true, 0); 
        (vars.psu, vars.pju, vars.pjs_) = Splitter(contracts.splitter).computeValuePrices();
        doPrintDorc(0,vars.pjs_); 
        (vars.jdj, vars.jds, vars.sdj, vars.sds) = tmaster.getDorc(0,vars.pjs_); 
        doPrintSupplys(); 
        assertApproxEqAbs(seniorbalbefore -ERC20(vars.senior).balanceOf(address(this)), vars.s, 10 ); 

        // then unredeem 
        tmaster.unRedeemDebtVault(
            vaultAmount, vars.pjs_, true, 0); 
        (uint jdj, uint jds, uint sdj, uint sds) = tmaster.getDorc(0,vars.pjs_); 
        assertApproxEqAbs(jdj,0,1);
        assertApproxEqAbs(jds,0,1);
        assertEq(sdj,0);
        assertEq(sds,0);
        assertApproxEqAbs(seniorbalbefore, ERC20(vars.senior).balanceOf(address(this)), 10); 
        doPrintDorc(0,vars.pjs_); 
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
        (uint vaultAmount,) = tmaster.redeemToDebtVault(
            vars.s+ amountOut, 
            true, 0); 
        assertEq(ERC20(senior).balanceOf(contracts.splitter), vars.s+ amountOut); 
        assertEq(tmaster.getdVaultBal( 0, address(this), true, vars.pjs_), vaultAmount);
        console.log('vaultOut, vaultIn', vaultAmount, precision); 
        doPrintDorc(0,vars.pjs_);
    }

    function testLeverageSwap() public{
        // createVault(); 
        doLimitSpecified(4* precision, true); 
        doApproval(); 
        testVar memory vars; 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);

        uint startAmount = 1 * precision; 
        uint leverage = 3*precision; 
        uint priceLimit = precision*102/100;
        bytes memory data; 

        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        ERC20(junior).approve(contracts.cJunior, type(uint256).max); 
        ERC20(senior).approve(contracts.cSenior, type(uint256).max); 

        //Enter market
        address[] memory ctokens = new address[](2); 
        ctokens[0] = contracts.cJunior; 
        ctokens[1] = contracts.cSenior; 

        Comptroller(contracts.lendingPool).enterMarkets(ctokens); 

        // supply to market 
        LeverageModule(contracts.cJunior).mint((leverage-precision)*startAmount/precision  ); 
        
        uint balbefore = ERC20(junior).balanceOf(address(this)); 
        LeverageModule(contracts.cJunior).swapWithLeverage(
            startAmount, leverage, priceLimit, 0,contracts.amm, data); 
        assertEq(balbefore - ERC20(junior).balanceOf(address(this)) , startAmount); 

        // Go back up 
        mintAndSplit(10); 
        doLimitSpecified(4* precision, false); 
        LeverageModule(contracts.cSenior).mint((leverage-precision)*startAmount/precision  ); 
        
        balbefore = ERC20(senior).balanceOf(address(this)); 
        LeverageModule(contracts.cSenior).swapWithLeverage(
            startAmount, leverage, priceLimit, 0,contracts.amm, data); 
        assertEq(balbefore - ERC20(senior).balanceOf(address(this)) , startAmount);

        // TODO Try withdraw 
        // LeverageModule(contracts)

    }

    function testSupplyWithdrawPool() public {
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        uint amount = precision; 
        doApproval(); 
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        ERC20(junior).approve(contracts.cJunior, type(uint256).max); 
        ERC20(senior).approve(contracts.cSenior, type(uint256).max); 

        LeverageModule(contracts.cJunior).mint(amount  ); 
        assertEq(LeverageModule(contracts.cJunior).balanceOf(address(this)), amount); 

        LeverageModule(contracts.cJunior).redeem( amount); 
        assertEq(LeverageModule(contracts.cJunior).balanceOf(address(this)), 0);
    }
  function testFillingAndClaiming() public{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        testVars2 memory vars; 
        uint256 amountInToBid = 5*precision; 
        bool limitBelow = false; 
        uint16 point = 101; 
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        bytes memory data; 
        // first do limit bid  
        mintAndSplit(10); 
        doLimitSpecifiedPoint( amountInToBid,  limitBelow,  point); 

        // for extra buffer
        mintAndSplit(10);
        uint16 nextpoint = limitBelow? point-1: point+1; 
        doLimitSpecifiedPoint(amountInToBid,  limitBelow,  nextpoint); 

        //go down 
        doApproval(); 
        bool up = limitBelow? false : true; 
        (vars.amountIn, vars.amountOut) = tmaster._swapFromTranche(
            up , int256(amountInToBid*3)/2, 0, 0, data
            ); 

        // junior balance should increase by vars.amountIn
        uint balbefore = limitBelow? ERC20(junior).balanceOf(address(this)) 
            :  ERC20(senior).balanceOf(address(this)); 
        SpotPool(contracts.amm).makerClaim(
            point, limitBelow);
        uint balAfter = limitBelow? ERC20(junior).balanceOf(address(this)) 
            :  ERC20(senior).balanceOf(address(this)); 

        assert(balAfter> balbefore); 
        console.log('balafter, balbefore', balAfter, balbefore); 
        // assertApproxEqAbs(balAfter-balbefore, )

        // try removing limit 

        mintAndSplit(10); 
        uint balbefore_ = limitBelow? ERC20(senior).balanceOf(address(this)) 
            :  ERC20(junior).balanceOf(address(this)); 
        doLimitSpecifiedPoint( amountInToBid,  limitBelow,  point+2); 

        balbefore = limitBelow? ERC20(senior).balanceOf(address(this)) 
            :  ERC20(junior).balanceOf(address(this)); 
        SpotPool(contracts.amm).makerReduce(      
        point+2, amountInToBid, !limitBelow); 
        balAfter = limitBelow? ERC20(senior).balanceOf(address(this)) 
            :  ERC20(junior).balanceOf(address(this)); 
        assert(balAfter> balbefore); 
        assertApproxEqAbs(balbefore_, balAfter, 10); 
    }

    function testPartialFilledAndClaiming() public{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        testVars2 memory vars; 
        uint256 amountInToBid = 5*precision; 
        bool limitBelow = false; 
        uint16 point = 101; 
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        bytes memory data; 

        // first do limit bid  
        mintAndSplit(10); 
        doLimitSpecifiedPoint( amountInToBid,  limitBelow,  point);

        doApproval(); 
        bool up = limitBelow? false : true; 
        (vars.amountIn, vars.amountOut) = tmaster._swapFromTranche(
            up , int256(amountInToBid)/2, 0, 0, data
            ); 


        (uint256 baseAmount, uint256 tradeAmount) = SpotPool(contracts.amm).makerPartiallyClaim(
         point, 
         limitBelow
        ); 
        assert(tradeAmount>0&& baseAmount>0 ); 
        if(!limitBelow) assertApproxEqAbs(amountInToBid- tradeAmount , vars.amountOut, 100 ); 

    }


    // function testLeverageUnswap()public{}
    
    struct testVars2{
        uint16 pointLower;
        uint16 pointUpper; 
        uint128 amount; 

        address junior;
        address senior; 

        uint amountIn;
        uint amountOut; 
        uint balbefore; 
        uint diff; 

        uint supply;
        uint assets; 
        uint numentries;
    }



    function testProvideAndConsumeAllLiq() public {
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        testVars2 memory vars; 
        vars.pointLower = 100; //current point
        vars.pointUpper = 102; //current point+2 
        vars.amount = uint128(5*precision); 
        bytes memory data; 

        SpotPool amm = SpotPool(contracts.amm); 
        assertEq(amm.liquidity(), 0); 

        (vars.junior, vars.senior) = Splitter(contracts.splitter).getTrancheTokens(); 


        ERC20(vars.junior).approve(address(amm), type(uint256).max); 
        // ERC20(senior).approve(address(amm), type(uint256).max); 
        vars.balbefore = ERC20(vars.junior).balanceOf(address(this)); 
        amm.provideLiquidity(
            vars.pointLower, vars.pointUpper, vars.amount, data); 
        vars.diff = vars.balbefore - ERC20(vars.junior).balanceOf(address(this)); 

        assert(amm.liquidity()> 0); 
        assert(amm.getCurPrice() == precision);

        // Now swap in this pool, consume all liquidity
        doApproval(); 
        (vars.amountIn, vars.amountOut) = tmaster._swapFromTranche(
            true, -int256(uint256(vars.amount)), precision*103/100, 0, data
            ); 
        assertApproxEqAbs(vars.diff, vars.amountOut, 100 );

        // Remove liquidity
        vars.balbefore = ERC20(vars.senior).balanceOf(address(this)); 
        amm.withdrawLiquidity(vars.pointLower, vars.pointUpper, vars.amount, data); 
        vars.diff = ERC20(vars.senior).balanceOf(address(this)) - vars.balbefore; 
        console.log('amountin', vars.diff, vars.amountIn); 
        assertApproxEqAbs(vars.diff, vars.amountIn, 10000); 
    }

    function testSwapFromDebtAndRedeem() public{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
        testVars2 memory vars; 
        uint amount = 5*precision;
        uint amountToSwap =  5* precision; 
        bool redeemSenior = true;  
        doApproval(); 
        (vars.junior, vars.senior) = Splitter(contracts.splitter).getTrancheTokens(); 

        // Redeem tranche 
        vars.balbefore = ERC20(vars.senior).balanceOf(address(contracts.splitter));
        (uint vaultAmount, uint pjs) = tmaster.redeemToDebtVault(amount, redeemSenior, 0); 
        vars.diff = ERC20(vars.senior).balanceOf(address(contracts.splitter)) - vars.balbefore; 
        assertEq(vars.diff,amount); 
        assertEq(tmaster.getAvailableDVaultLiq(0, pjs, redeemSenior), amountToSwap); 
        uint dvaultBal = tmaster.getdVaultBal(0, address(this), redeemSenior,  pjs); 
        assertEq(dvaultBal, vaultAmount); 

        // Swap using debt vault liq 
        doMintVaultApproval(); 
        tmaster.swapFromDebtVault( vaultAmount, pjs, redeemSenior, 0);  
        assertApproxEqAbs(vars.balbefore, ERC20(vars.senior).balanceOf(address(contracts.splitter)), 10); 
        assertEq(tmaster.getAvailableDVaultLiq(0, pjs, redeemSenior), 0); 
        doPrintDorc(0, pjs); 

        vars.balbefore = tVault(contracts.vault).balanceOf(address(this));
        tmaster.redeemFromDebtVault( dvaultBal, pjs, 0, redeemSenior); 
        assertEq(tmaster.getdVaultBal(0, address(this), redeemSenior,  pjs), 0); 
        assertApproxEqAbs(tVault(contracts.vault).balanceOf(address(this)) - vars.balbefore, dvaultBal, 10); 
        assertEq(tmaster.getFreedVault(0, pjs, redeemSenior), 0); 
    }





    // function testSwapToRatio 
    // function testDynamicAdjustment
    // function testArbitrageProfitWithVaryingElapsedTime() public {}
    // function testtVault() public {}
    // function testCounterPartyProfitSplit() public{}
    // function testPerpLikeTrading() public {}
    // function testProfitForJuniorLongTermEquation(){}
    // function testProgrssionOverTime() public{}
    // function testExpansion() public{}
    // function testStablecoinArb() public{}
    // function testNoLiquidityToTradeArbitrage() public {}//do limit instead? 
    // function testOracles
    // function testOracleBasedComputePrices
    ///AMM stuff
    // function testPartialClaiming(){}
    // function testMakerReduce(){}


    function testFetchData() public{
        createVault();
        createVault(); 

        TrancheFactory.Contracts memory contracts = tFactory.getContracts(2); 
        want.approve(contracts.vault, type(uint256).max); 
        uint shares = 10*precision; 
        tVault(contracts.vault).mint(shares, address(this)); 
        tVault(contracts.vault).approve(contracts.splitter, type(uint256).max);
        Splitter(contracts.splitter).split(shares); 

        tLens tlens = new tLens(); 
        tLens.TrancheInfo[] memory infos = tlens.getTrancheInfoBatch(address(tFactory)); 
        console.log('ad', infos[2]._want); 

        // doLimit(); 
        // doLimitSpecifiedPoint(precision, false,  102); 
        // doLimitSpecifiedPoint(precision, true,  99); 

        tLens.UserInfo memory info = tlens.getUserInfo(address(tFactory), address(this), 0); 

        // console.log( 
        //     info.limitPositions[0].price, 
        //     info.limitPositions[0].amount, info.limitPositions[0].claimable); 
        // console.log( 
        //     info.limitPositions[1].price, 
        //     info.limitPositions[1].amount, info.limitPositions[1].claimable); 
        // console.log( 
        //     info.limitPositions[2].price, 
        //     info.limitPositions[2].amount, info.limitPositions[2].claimable); 
   

    }

    
}
