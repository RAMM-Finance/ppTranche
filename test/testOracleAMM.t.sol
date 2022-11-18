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
import {testETH} from "../src/mocks/testTokens.sol"; 
import {MockOracle, ETHCPIOracle} from "../src/oracles/chainlinkOracle.sol"; 
import {OracleJSPool} from "../src/oracleAMM.sol"; 

contract OracleAMMTest is base {
    using stdStorage for StdStorage; 



    function testTotalAsset() public {
        bool multiple = true; 
        createERC20Vault(); 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(1);
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        vm.warp(block.timestamp + 10); 
        vm.startPrank(jonna);
        mintAndSplitVault(10, jonna, 1); 

        (uint256 psu, uint256 pju, uint256 pjs) = Splitter(contracts.splitter).computeValuePricesView(); 
        uint256 totalAssets = OracleJSPool(contracts.amm).totalAssets();
        vm.stopPrank(); 
        assertEq(totalAssets, 0);

        uint256 amount = 2* precision; 
        vm.startPrank(jonna); 
        want.approve(contracts.amm, type(uint256).max); 
        OracleJSPool(contracts.amm).deposit(amount, jonna); 
        totalAssets = OracleJSPool(contracts.amm).totalAssets();
        assertApproxEqAbs(totalAssets, amount, 10); 

        // Since no trade and no price change, should be same to mintamount
        (uint256 seniorAmount, uint256 juniorAmount) = OracleJSPool(contracts.amm).computeAssetsReturned( amount) ; 
        assertApproxEqAbs(seniorAmount+juniorAmount, amount, 10); 
        console.log('sjamounts', seniorAmount , juniorAmount); 

        vm.warp(block.timestamp+10); 
        MockOracle(tFactory.getOracle(1)).setExchangeRate(1e18+1e17+1e17); 
        ( seniorAmount,  juniorAmount) = OracleJSPool(contracts.amm).computeAssetsReturned( amount) ; 
        assertApproxEqAbs(seniorAmount+juniorAmount, amount, 10); 

        if(multiple){
            amount = precision; 
            vm.stopPrank();
            vm.startPrank(jott); 
            want.approve(contracts.amm, type(uint256).max); 
            OracleJSPool(contracts.amm).deposit(amount, jott); 
            uint newtotalAssets = OracleJSPool(contracts.amm).totalAssets();
            assertApproxEqAbs(newtotalAssets - totalAssets, amount, 10); 

            // no one bought, so should 
            vm.warp(block.timestamp + 10) ; 
            OracleJSPool(contracts.amm).redeem(OracleJSPool(contracts.amm).balanceOf(jott), jott, jott); 
            assertApproxEqAbs(ERC20(senior).balanceOf(jott) + ERC20(junior).balanceOf(jott), amount, 10); 
            vm.stopPrank(); 
            vm.startPrank(jonna); 
        }

        // Price change and redeem all shares, should drain the pool 
        vm.warp(block.timestamp + 10) ; 
        OracleJSPool(contracts.amm).redeem(OracleJSPool(contracts.amm).balanceOf(jonna), jonna, jonna); 
        assertApproxEqAbs(ERC20(senior).balanceOf(contracts.amm), 0, 10); 
        assertApproxEqAbs(ERC20(junior).balanceOf(contracts.amm), 0, 10);   
 
    }

    function testSwap() public {
        // first provide liq 
        createERC20Vault(); 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(1);
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        vm.warp(block.timestamp + 10); 
        vm.startPrank(jonna);
        mintAndSplitVault(10, jonna, 1); 

        (,, uint256 pjs) = Splitter(contracts.splitter).computeValuePricesView(); 
        uint256 totalAssets = OracleJSPool(contracts.amm).totalAssets();
        vm.stopPrank(); 
        assertEq(totalAssets, 0);

        uint256 amount = 5* precision; 
        vm.startPrank(jonna); 
        want.approve(contracts.amm, type(uint256).max); 
        OracleJSPool(contracts.amm).deposit(amount, jonna); 
        totalAssets = OracleJSPool(contracts.amm).totalAssets();
        assertApproxEqAbs(totalAssets, amount, 10); 
        vm.stopPrank(); 

        // Swap remaining senior to junior 
        vm.startPrank(jott); 
        mintAndSplitVault(1, jott, 1); 
        (uint seniorbal, uint juniorbal) = (ERC20(senior).balanceOf(jott), ERC20(junior).balanceOf(jott));
        ERC20(senior).approve(contracts.amm, type(uint256).max); 
        uint amountOut = OracleJSPool(contracts.amm).takerTrade(
            jott, true, ERC20(senior).balanceOf(jott)
            ); 
        assertEq( ERC20(senior).balanceOf(jott), 0); 
        assertApproxEqAbs(ERC20(junior).balanceOf(jott)-juniorbal, amountOut, 10); 
        //total asset should stay constant
        assertApproxEqAbs(totalAssets,  OracleJSPool(contracts.amm).totalAssets(), 10); 

        // swap all junior back to senior
        juniorbal = ERC20(junior).balanceOf(jott); 
        ERC20(junior).approve(contracts.amm, type(uint256).max); 
        amountOut = OracleJSPool(contracts.amm).takerTrade(
            jott, false, ERC20(junior).balanceOf(jott)
            ); 
        assertEq(ERC20(junior).balanceOf(jott), 0); 
        assertApproxEqAbs(ERC20(senior).balanceOf(jott), (juniorbal*pjs)/1e18, 10); 

        //Now swap for profit, which should be LP's loss 
        uint networth = OracleJSPool(contracts.amm).denomintateInAsset(jott);  
        uint poolnetworth = OracleJSPool(contracts.amm).denomintateInAsset(contracts.amm); 
        vm.warp(block.timestamp + 10) ; // pjs should go down
        assert(OracleJSPool(contracts.amm).denomintateInAsset(jott) > networth); 
        assert(OracleJSPool(contracts.amm).denomintateInAsset(contracts.amm)< poolnetworth); 
        uint profit = OracleJSPool(contracts.amm).denomintateInAsset(jott) - networth; 
        assertApproxEqAbs(poolnetworth- OracleJSPool(contracts.amm).denomintateInAsset(contracts.amm), profit, 10 ); 
        // swapping should not change networth 
        amountOut = OracleJSPool(contracts.amm).takerTrade(
            jott, true , ERC20(senior).balanceOf(jott)/2
            ); 
        assertApproxEqAbs(OracleJSPool(contracts.amm).denomintateInAsset(jott) - networth, profit, 10); 

    }

    function testmintSwapNewMintRedeemSolvent() public{
        createERC20Vault(); 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(1);
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
        vm.warp(block.timestamp + 10); 
        vm.startPrank(jonna);
        mintAndSplitVault(10, jonna, 1); 

        (,, uint256 pjs) = Splitter(contracts.splitter).computeValuePricesView(); 

        uint256 amount = 5* precision; 
        want.approve(contracts.amm, type(uint256).max); 
        OracleJSPool(contracts.amm).deposit(amount, jonna); 
        uint totalAssets = OracleJSPool(contracts.amm).totalAssets();
        assertApproxEqAbs(totalAssets, amount, 10); 
        vm.stopPrank(); 

        // let swap 
        vm.startPrank(jott); 
        mintAndSplitVault(1, jott, 1); 
        (uint seniorbal, uint juniorbal) = (ERC20(senior).balanceOf(jott), ERC20(junior).balanceOf(jott));
        ERC20(senior).approve(contracts.amm, type(uint256).max); 
        uint amountOut = OracleJSPool(contracts.amm).takerTrade(
            jott, true, ERC20(senior).balanceOf(jott)
            ); 
        assertEq( ERC20(senior).balanceOf(jott), 0); 
        assertApproxEqAbs(ERC20(junior).balanceOf(jott)-juniorbal, amountOut, 10); 
        assertApproxEqAbs(totalAssets,  OracleJSPool(contracts.amm).totalAssets(), 10); 

        vm.stopPrank(); 

        // mint 
        vm.warp(block.timestamp + 10) ;
        totalAssets = OracleJSPool(contracts.amm).totalAssets();
        vm.startPrank(sybal); 
        want.approve(contracts.amm, type(uint256).max); 
        OracleJSPool(contracts.amm).deposit(amount, sybal); 
        uint newtotalAssets = OracleJSPool(contracts.amm).totalAssets();
        assertApproxEqAbs(newtotalAssets- totalAssets, amount, 10); 
        vm.stopPrank(); 

        // all redeem and totalassset is 0 
        vm.startPrank(jonna); 
        (uint jonnabalbefore, uint sybalbalbefore) = (OracleJSPool(contracts.amm).denomintateInAsset(jonna),  
            OracleJSPool(contracts.amm).denomintateInAsset(sybal)
            ); 
        OracleJSPool(contracts.amm).redeem(OracleJSPool(contracts.amm).balanceOf(jonna), jonna, jonna);
        vm.stopPrank(); 
        vm.startPrank(sybal); 
        OracleJSPool(contracts.amm).redeem(OracleJSPool(contracts.amm).balanceOf(sybal), sybal, sybal); 
        assertApproxEqAbs(OracleJSPool(contracts.amm).denomintateInAsset(contracts.amm),0, 10); 
        assert(OracleJSPool(contracts.amm).denomintateInAsset(jonna)-jonnabalbefore>
            OracleJSPool(contracts.amm).denomintateInAsset(sybal)-sybalbalbefore); // jonna should have made money 
        // assertApproxEqAbs(OracleJSPool(contracts.amm).denomintateInAsset(jonna)-amount
        //     , 10); 
    }

    function testSwapFromTrancheMaster() public {
        createERC20Vault(); 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(1);
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 

        vm.startPrank(jonna);
        uint256 amount = 5* precision; 
        want.approve(contracts.amm, type(uint256).max); 
        OracleJSPool(contracts.amm).deposit(amount, jonna); 
        uint totalAssets = OracleJSPool(contracts.amm).totalAssets();
        assertApproxEqAbs(totalAssets, amount, 10); 
        vm.stopPrank(); 


        bytes memory data; 
        vm.startPrank(jott); 
        mintAndSplitVault(1, jott, 1); 
        (uint seniorbal, uint juniorbal) = (ERC20(senior).balanceOf(jott), ERC20(junior).balanceOf(jott));
        ERC20(senior).approve(contracts.amm, type(uint256).max); 
        uint amountOut = OracleJSPool(contracts.amm).takerTrade(
            jott, true, ERC20(senior).balanceOf(jott)
            ); 
        tmaster._swapFromTranche(true, int256( ERC20(senior).balanceOf(jott)), 0, 1, data); 
        assertEq( ERC20(senior).balanceOf(jott), 0); 
        assertApproxEqAbs(ERC20(junior).balanceOf(jott)-juniorbal, amountOut, 10); 
        assertApproxEqAbs(totalAssets,  OracleJSPool(contracts.amm).totalAssets(), 10); 
        vm.stopPrank(); 

        vm.startPrank(sybal); 
        uint shares = 1*precision; 
        want.approve(contracts.vault, shares*2); 
        tVault(contracts.vault).mint(shares,sybal); 
        assert(ERC20(senior).balanceOf(sybal) == 0); 
        tVault(contracts.vault).approve(address(tmaster), type(uint256).max);
        (seniorbal, juniorbal) = (ERC20(senior).balanceOf(jott), ERC20(junior).balanceOf(jott));
        tmaster._swapFromInstrument(
            false, precision, 0, 1, data); 
        assertEq(ERC20(junior).balanceOf(sybal), 0); 
        assert(ERC20(senior).balanceOf(sybal) > 0); 
    }

    function testSwapFromDifferentState() public {
        // mint, split 
        // add liquidity(mint oammVault)
        createERC20Vault(); 
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(1);
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 

        vm.startPrank(jonna);
        vm.warp(block.timestamp + 10); 
        uint256 amount = 5* precision; 
        mintAndSplitVault(5, jonna, 1); 

        // addliq 
        vm.warp(block.timestamp + 10); 
        want.approve(contracts.amm, type(uint256).max); 
        OracleJSPool(contracts.amm).deposit(amount, jonna); 

        // swap 
        vm.warp(block.timestamp + 130); 

        ERC20(senior).approve(contracts.amm, precision); 
         uint amountOut = OracleJSPool(contracts.amm).takerTrade(
            jonna, true, precision
            ); 

        for (uint i=0; i<100; i++){
            vm.warp(block.timestamp + 2); 
             amount = 5* precision; 
            mintAndSplitVault(5, jonna, 1); 

            // addliq 
            vm.warp(block.timestamp + 4); 
            want.approve(contracts.amm, type(uint256).max); 
            OracleJSPool(contracts.amm).deposit(amount, jonna); 

            // swap 
            vm.warp(block.timestamp + 5); 

            ERC20(senior).approve(contracts.amm, precision); 
             amountOut = OracleJSPool(contracts.amm).takerTrade(
                jonna, true, precision
                ); 
            vm.warp(block.timestamp + 23); 
            OracleJSPool(contracts.amm).redeem(amount, jonna, jonna); 


        } 
 
    }

    //function totalAssetsDepositLinear
    //function lpcontinuouslymakelosemoney
    //function testdonatetoPoolAndredeem
    //function testComputeWithdraw
    //funciton testmintswapredeemSolvent
    //function testmintSwapNewMintRedeemSolvent
    //function testFeeProfit
    //function testLiqProvisionProfitOverTime
    //function testSwapProfit() public{}
 

    
}
