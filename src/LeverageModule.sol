pragma solidity ^0.8.4;
import {FixedPointMathLib} from "./vaults/utils/FixedPointMathLib.sol";

import "forge-std/console.sol";
import "./compound/Comptroller.sol"; 
import "./compound/CErc20.sol"; 
import {TrancheMaster} from "./tranchemaster.sol"; 
import {TrancheFactory} from "./tranchemaster.sol"; 
import {IERC3156FlashBorrower} from "./vaults/tokens/ERC1155.sol"; 
import {tToken} from "./splitter.sol"; 
contract CErc20Behalf is CErc20{

    /// @param mintAmount The amount of the underlying asset to supply
    function mintInternalBehalf(address minter, uint mintAmount) public 
    //nonReentrant 
    //onlyLeverage 
    {
        accrueInterest();
        // mintFresh emits the actual Mint event if successful and logs on errors, so we don't need to
        mintFresh(minter, mintAmount);
    }
    /// @param borrowAmount The amount of the underlying asset to borrow 
    function borrowInternalBehalf(address borrower, uint borrowAmount) public {
    //nonReentrant 
    //onlyLeverage 
        accrueInterest();
        // borrowFresh emits borrow-specific logs on errors, so we don't need to
        borrowFresh(payable(borrower), borrowAmount);
    }
}

/// @notice handles leverage trading for junior<->senior trades 
/// @dev admin is set as the tranchemaster contract  
contract LeverageModule is CErc20Behalf{
    using FixedPointMathLib for uint256;
    TrancheMaster master;
    CErc20Behalf pair;  
    bool amISenior; 
    uint256 public constant precision = 1e18;  

    function setPair(address _pair) external{
        require(msg.sender == admin ); 
        pair = CErc20Behalf(_pair); 
    }

    function setTrancheMaster(address _master, bool isSenior) external{
        require(msg.sender == admin, "authERR"); 
        master = TrancheMaster(_master); 
        amISenior = isSenior; 
    }


    /// @dev Receive a flash loan.
    /// @param initiator The initiator of the loan.
    /// @param token The loan currency.
    /// @param amount The amount of tokens lent.
    /// @param fee The additional amount of tokens to repay.
    /// @param data Arbitrary data structure, intended to contain user-defined parameters.
    /// @return The keccak256 hash of "ERC3156FlashBorrower.onFlashLoan"
    /// @notice use senior as collateral to borrow junior, or vice versa 
    /// Option 1:  mint and borrow on behalf of the borrower 
    /// Option 2: mint and borrow to this address and give traders note instead 
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32){
        // amount to buy is borrowedamount + trader's fund 
        uint256 amountToSwap = amount + amount.divWadDown(global_leverage - precision); 

        // Swap junior(senior)-> senior(junior)
        CErc20(underlying).approve(address(master), amountToSwap); 
        (uint256 amountIn, uint256 amountOut) = master._swapFromTranche(
                !amISenior, int256(amountToSwap), global_priceLimit ,global_vaultId, data
            ); 

        // Option 1: supply senior(junior) and borrow on behalf
        // trader need to have approved pair.underlying to pair token contract 
        CErc20(pair.underlying()).transfer(global_trader, amountOut); 
        pair.mintInternalBehalf(global_trader, amountOut); 

        // then borrow junior(senior) with senior(junior) as collateral, which
        // will be burned by the flashMint function. Trader need to have approved 
        // junior for amount to this 
        borrowInternalBehalf(global_trader, amount); 
        CErc20(underlying).transferFrom(global_trader, address(this), amount); 

        return keccak256("ERC3156FlashBorrower.onFlashLoan"); 
    }

    uint256 global_leverage;
    uint256 global_priceLimit; 
    address global_trader; 
    uint256 global_vaultId; 

    /// @notice allows trader to leverage swap, junior to senior if this cToken is 
    /// junior, and vice versa
    /// @dev performs a recursive borrow until the leverage is satisfied 
    /// At completion, trader will have 
    function swapWithLeverage(
        uint256 startAmount, 
        uint256 leverage,
        uint256 priceLimit, 
        uint256 vaultId,
        bytes calldata data) external {
        require(global_leverage == 0 && global_priceLimit ==0 
         && global_trader == address(0) && global_vaultId == type(uint256).max, "err");

        global_leverage = leverage; 
        global_priceLimit = priceLimit; 
        global_trader = msg.sender;
        global_vaultId = vaultId; 

        // Escrow
        CErc20(underlying).transferFrom(msg.sender,address(this), startAmount); 
        CErc20(underlying).approve(address(master), startAmount); 

        // need to (flash)mint excess junior and sell it to senior
        bytes memory data; 
        uint256 borrowAmount = leverage.mulWadDown(startAmount) - startAmount; 

        tToken(underlying).flashMint(
            IERC3156FlashBorrower(address(this)), 
            address(underlying), 
            borrowAmount, 
            data); 

        global_leverage = 0; 
        global_priceLimit = 0; 
        global_trader = address(0); 
        global_vaultId = type(uint256).max; 
    }



       
}
