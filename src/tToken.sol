pragma solidity ^0.8.9;
import {Auth} from "./vaults/auth/Auth.sol";
import {ERC4626} from "./vaults/mixins/ERC4626.sol";

import {SafeCastLib} from "./vaults/utils/SafeCastLib.sol";
import {SafeTransferLib} from "./vaults/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./vaults/utils/FixedPointMathLib.sol";

import {IERC3156FlashBorrower} from "./vaults/tokens/ERC1155.sol"; 
import {ERC20} from "./vaults/tokens/ERC20.sol";
import {tVault} from "./tVault.sol"; 
import {TrancheMaster} from "./tranchemaster.sol"; 
import "forge-std/console.sol";


/// @notice tokens for junior/senior tranches 
contract tToken is ERC20{

  modifier onlySplitter() {
    require(msg.sender == splitter, "!Splitter");
     _;
  }

  address splitter; 
  ERC20 asset; 

  /// @notice asset is the tVault  
  constructor(
      ERC20 _asset, 
      string memory _name,
      string memory _symbol, 
      address _splitter
  ) ERC20(_name, _symbol, _asset.decimals()) {
      asset = _asset;
      splitter = _splitter; 
  }

  function mint(address to, uint256 amount) external onlySplitter{
    _mint(to, amount); 
  }

  function burn(address from, uint256 amount) external onlySplitter{
    _burn(from, amount);
  }

  function flashMint(
     IERC3156FlashBorrower receiver,
     address token, 
     uint256 amount, 
     bytes calldata data
     ) external returns(bool){
    //require(amount <= max);
    _mint(address(receiver), amount); 
    require(
      receiver.onFlashLoan(msg.sender, address(this), amount, 0, data) 
        == keccak256("ERC3156FlashBorrower.onFlashLoan"), "callback failed"
    ); 
    _burn(address(receiver), amount); 
  }

}





