// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import  "./compound/PriceOracle.sol"; 
import {CToken} from "./compound/CToken.sol"; 
import {SpotPool} from "./amm.sol"; 

/// @notice oracle for the junior-senior pair in the amm 
contract PJSOracle is PriceOracle{
	//TODO do medeanize + delay

	// address owner; 
	// SpotPool pool_; 
	
	// constructor(){
	// 	owner = msg.sender;
	// }

	// function setPool(address pool_) external{
	// 	pool = SpotPool(pool_); 
	// } 
	function getUnderlyingPrice(CToken token) override external view returns(uint){	
		 	
		return 1e18; 
	}
}

contract ChainlinkPriceOracle {
    AggregatorV3Interface internal priceFeed;

    constructor() {
        // ETH / USD
        priceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    }
//	0x0715A7794a1dc8e42615F059dD6e406A6594651A
    function getLatestPrice() public view returns (int) {
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        // for ETH / USD price is scaled up by 10 ** 8
        return price / 1e8;
    }
}

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int answer,
            uint startedAt,
            uint updatedAt,
            uint80 answeredInRound
        );
}
