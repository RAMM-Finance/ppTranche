// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;
import {FixedPointMathLib} from "../vaults/utils/FixedPointMathLib.sol"; 
import "forge-std/console.sol";

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
interface IERC20 {
 
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

interface iTruflationTester{
    function yoyInflation() external view returns(string memory);
    function requestYoyInflation() external returns (bytes32 requestId); 
}

contract MockOracle{
    uint256 rate; 
    constructor(){
        rate = 1e18+1e17; 
    }
    function setExchangeRate(uint256 newrate) public {
        rate = newrate; 
    }
    function getExchangeRate() public view returns(uint){
        return rate; 
    }
}


contract ETHCPIOracle {
    using FixedPointMathLib for uint256; 

    AggregatorV3Interface public priceFeed;
    iTruflationTester public CPIFeed;

    uint256 lastStoreTimeStamp;  
    uint256 public cumulReturns; 
    uint256 public constant precision = 1e18; 
    uint256 public init_price; 

    address public owner; 
    address public link; 
    constructor(address link_address) {
        // ETH / USD polygon 
        priceFeed = AggregatorV3Interface(0x0715A7794a1dc8e42615F059dD6e406A6594651A);
        CPIFeed = iTruflationTester(0x17dED59fCd940F0a40462D52AAcD11493C6D8073); 
        cumulReturns = precision; 
        lastStoreTimeStamp = block.timestamp; 
        init_price = uint256(getLatestPrice()); 
        link = link_address; 
        owner = msg.sender; 
    }

    /// @notice returns ETHUSD in wad
    function getLatestPrice() public view returns (int) {
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        // for ETH / USD price is scaled up by 10 ** 8
        return price * 1e10; 
    }

    /// @notice queries oracle and returns CPI in wad space, 
    function getCPI() public view returns(uint){
        (uint res, bool err) = strToUint(CPIFeed.yoyInflation());
        if (err) return precision+ res*1e2;  //convert to Wad; 

        // return 1e18+ 1e17; 
    }

    /// @notice gets ETH/CPI price, called by keepers or trader's interactions with protocol contracts
    function refreshExchangeRate() public returns(uint256){
        uint256 ETHUSD = uint256(getLatestPrice()); 
        uint256 CPIUSD = getCPIUSD(); 
        uint256 ETHCPI = ETHUSD.divWadDown(CPIUSD); 

        return ETHCPI.divWadDown(init_price); 
    }

    /// @notice returns ETH/CPI price to be used to price synthetic instruments 
    function getExchangeRate() public view returns(uint256){
        uint256 ETHUSD = uint256(getLatestPrice()); 
        uint256 CPIUSD = cumulReturns; 
        uint256 ETHCPI = ETHUSD.divWadDown(CPIUSD); 

        return ETHCPI.divWadDown(init_price); 
    }   

    /// @notice assumes compounding inflation 
    function getCPIUSD() public returns(uint256){

        uint256 freshInflation = (getCPI() - precision)
                .mulWadDown(toYear(block.timestamp - lastStoreTimeStamp)); 

        cumulReturns=cumulReturns.mulWadDown(freshInflation + precision); 

        lastStoreTimeStamp = block.timestamp; 
        return cumulReturns; 
    }

    function requestCPI() public {
        IERC20(link).transferFrom(msg.sender, address(this), 1e16); 
        IERC20(link).transfer(address(CPIFeed), 1e16); 

        CPIFeed.requestYoyInflation(); 
    }

    function strToUint(string memory _str) public pure returns(uint256 res, bool err) {
        bytes1 comma = bytes1("."); 
        uint sub; 
        for (uint256 i = 0; i < bytes(_str).length; i++) {
            if(bytes(_str)[i] == comma) {
                sub +=1; 
                continue; 
            }

            if ((uint8(bytes(_str)[i]) - 48) < 0 || (uint8(bytes(_str)[i]) - 48) > 9) {
                return (0, false);
            }
            res += (uint8(bytes(_str)[i]) - 48) * 10**(bytes(_str).length+sub - i - 1);
        }
        
        return (res, true);
    }

    function toYear(uint256 sec) public pure returns(uint256){
        return sec*precision/uint256(31536000);
        //return (sec * precision).divWadDown(uint256(31536000)* precision); 
    }



}




