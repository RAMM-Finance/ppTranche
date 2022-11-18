// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import  "../compound/PriceOracle.sol"; 
import {CToken} from "../compound/CToken.sol"; 
import {SpotPool} from "../amm.sol"; 

/// @notice oracle for the junior-senior pair in the amm 
contract PJSOracle is PriceOracle{

	address owner; 
	SpotPool pool; 
	
	constructor(address pool_){
		owner = msg.sender;
        pool = SpotPool(pool_);
	}

    /// @notice Trades outside boundary will revert, so safe to  get instantaneous price 
	function getUnderlyingPrice(CToken token) override external view returns(uint){	
		return pool.getCurPrice(); 
	}
}

