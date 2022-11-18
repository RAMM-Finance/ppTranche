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


contract TVaultTest is base {
    using stdStorage for StdStorage; 


    function testFetchData() public{
        createVault();
        createVault(); 

        // TrancheFactory.Contracts memory contracts = tFactory.getContracts(2); 
        // want.approve(contracts.vault, type(uint256).max); 
        // uint shares = 10*precision; 
        // tVault(contracts.vault).mint(shares, address(this)); 
        // tVault(contracts.vault).approve(contracts.splitter, type(uint256).max);
        // Splitter(contracts.splitter).split(shares); 

        tLens tlens = new tLens(); 
        tLens.TrancheInfo[] memory infos = tlens.getTrancheInfoBatch(address(tFactory)); 
        console.log('ad', infos[2]._want); 
        console.log(infos[2].psu,infos[2].pju,infos[2].pjs); 
        console.log('names/desc', infos[2]._names[0],infos[2]._names[1]); 

        // doLimit(); 
        doLimitSpecifiedPoint(precision, false,  102); 
        doLimitSpecifiedPoint(precision, true,  99); 

        tLens.UserInfo memory info = tlens.getUserInfo(address(tFactory), address(this), 0); 

        console.log( 
            info.limitPositions[0].price, 
            info.limitPositions[0].amount, info.limitPositions[0].claimable); 
        console.log( 
            info.limitPositions[1].price, 
            info.limitPositions[1].amount, info.limitPositions[1].claimable); 
        // console.log( 
        //     info.limitPositions[2].price, 
        //     info.limitPositions[2].amount, info.limitPositions[2].claimable); 
        
        createERC20Vault(); 

         info = tlens.getUserInfo(address(tFactory), address(this), 2); 

         tlens.getTrancheInfo(address(tFactory), 0);
         tlens.getTrancheInfo(address(tFactory), 2);
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(3);

        vm.startPrank(jonna);
                vm.warp(block.timestamp + 10000000); 

        uint256 amount = 5* precision; 
        want.approve(contracts.amm, type(uint256).max); 
        OracleJSPool(contracts.amm).deposit(amount, jonna); 
        vm.stopPrank(); 


         tlens.getTrancheInfoBatch(address(tFactory)); 

         tVault(contracts.vault).storeExchangeRate(); 
         tVault(contracts.vault).storeExchangeRate(); 
         tVault(contracts.vault).storeExchangeRate(); 

         Splitter(contracts.splitter).computeValuePrices(); 
         vm.warp(block.timestamp +100);
         Splitter(contracts.splitter).computeValuePrices(); 
         vm.warp(block.timestamp +100);
         Splitter(contracts.splitter).computeValuePrices(); 
         vm.warp(block.timestamp +100);

    }

    // function testSTETHCPI() public {
    //     // test name, description, vault underlying/asset name, 
    //     // test oracles, get ETH/USD price CPI/USD, STETH/ETH 
    //     createERC20Vault(true); 

    //     address oracle = tFactory.getOracle( 1); 

    //     (uint256 uint_ , )= ETHCPIOracle(oracle).strToUint("7.23323"); 
    //     console.log('price', uint_); 

    //     vm.warp(block.timestamp+100); 
    //     uint256 CPIUSD = ETHCPIOracle(oracle).getCPIUSD(); 

    //     vm.warp(block.timestamp+320); 
    //     uint256 CPIUSD2 = ETHCPIOracle(oracle).getCPIUSD();
    //     // assert(CPIUSD2 > CPIUSD); 
    //     console.log('CPI', CPIUSD, CPIUSD2); 

        

    // }

    // function testSTETHETH() public {

    // }
 

    
}
