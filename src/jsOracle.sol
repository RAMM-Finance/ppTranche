// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import  "./compound/PriceOracle.sol"; 
import {CToken} from "./compound/CToken.sol"; 

/// @notice oracle for the junior-senior pair in the amm 
contract PJSOracle is PriceOracle{

	function getUnderlyingPrice(CToken token) override external view returns(uint){		
		return 1e18; 
	}
}


