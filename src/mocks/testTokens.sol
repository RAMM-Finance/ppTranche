import {ERC20} from "../vaults/tokens/ERC20.sol";
import {ERC4626} from "../vaults/mixins/ERC4626.sol";

contract testErc is ERC20{
    constructor()ERC20("testUSDC", "tUSDC", 18){}
    function mint(address to, uint256 amount) public {
        _mint(to, amount); 
    }
    function faucet() public{
      uint256 amount = 1000* 1e18; 
      mint(msg.sender,amount ); 
    }
}

contract testETH is ERC20{
    constructor()ERC20("wETH", "wETH", 18){}
    function mint(address to, uint256 amount) public {
        _mint(to, amount); 
    }
    function faucet() public{
      uint256 amount = 1000* 1e18; 
      mint(msg.sender,amount ); 
    }
}

contract testVault is ERC4626{
    constructor(address want)ERC4626( ERC20(want),"a","a" ){

    }
    function totalAssets() public view override returns(uint256){
     return totalFloat();
    }

    function totalFloat() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }
}