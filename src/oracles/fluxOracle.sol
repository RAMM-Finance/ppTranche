// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;
import {FixedPointMathLib} from "../vaults/utils/FixedPointMathLib.sol"; 
import "forge-std/console.sol";


interface CLV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function latestAnswer() external view returns (int256);

    function latestTimestamp() external view returns (uint256);

    function latestRound() external view returns (uint256);


}

contract NEARUSD_Oracle{
    CLV3Interface public priceFeed;

    constructor( ) {
        priceFeed = CLV3Interface(0x572fCC6182877b79cb577f1895138D158101d93C);
    }

    /// @notice Fetches the latest price from the price feed
    function getLatestPrice() public view returns (int256) {
        return priceFeed.latestAnswer();
    }

    function getExchangeRate() public view returns(uint256){
        return uint256(getLatestPrice()) * 1e10; 
    }

    /// @notice Changes price feed contract address
    /// @dev Only callable by the owner
    function setPriceFeed(address _priceFeed) public  {
        priceFeed = CLV3Interface(_priceFeed);
    }

}









