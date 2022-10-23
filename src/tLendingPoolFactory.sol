pragma solidity ^0.8.4;

import "forge-std/console.sol";
import "./compound/Comptroller.sol"; 
import "./compound/CErc20.sol"; 
import {LeverageModule} from "./LeverageModule.sol"; 

contract tLendingPoolDeployer {

    function deployNewPool() public returns(address newPoolAd){
        uint _salt = 10; //random 

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

    }

    function deployNewCTokens( ) public returns(address cSenior, address cJunior){
        uint _salt = 10; //random 

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

    }

}





















