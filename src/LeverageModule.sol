pragma solidity ^0.8.9;
import {FixedPointMathLib} from "./vaults/utils/FixedPointMathLib.sol";

import "forge-std/console.sol";
import "./compound/Comptroller.sol"; 
import "./compound/CErc20.sol"; 
import {TrancheMaster} from "./tranchemaster.sol"; 
import {TrancheFactory} from "./tranchemaster.sol"; 
import {IERC3156FlashBorrower} from "./vaults/tokens/ERC1155.sol"; 
import {tToken} from "./splitter.sol"; 
import {CErc20Behalf} from "./CErc20Behalf.sol"; 

/// @notice handles leverage trading for junior<->senior trades 
/// @dev admin is set as the tranchemaster contract  
contract LeverageModule is CErc20Behalf{
    using FixedPointMathLib for uint256;
    TrancheMaster master;
    CErc20Behalf pair;  
    bool amISenior; 
    uint256 public constant precision = 1e18;  

    constructor(){
        //TODO vulnerabilities 
        // CErc20(underlying).approve(address(this), type(uint256).max); 
    }
    function setPair(address _pair) external{
        require(msg.sender == admin ); 
        pair = CErc20Behalf(_pair); 
    }

    function setTrancheMaster(address _master, bool isSenior) external{
        require(msg.sender == admin, "authERR"); 
        master = TrancheMaster(_master); 
        amISenior = isSenior; 
    }

    struct FlashVars{
        bool isUnSwap; 
        uint256 leverage; 
        uint256 priceLimit;
        uint256 vaultId; 
        address sender; 
        address amm; 

        uint256 amountToSwap; 
        uint256 amountIn;
        uint256 amountOut; 
        uint256 startBalance; 
        uint256 startBorrow; 
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
        FlashVars memory vars;

        (vars.isUnSwap, vars.leverage, vars.priceLimit, vars.vaultId, vars.sender, vars.amm)
            = abi.decode(data, (bool, uint256, uint256, uint256, address, address)); 

        vars.startBalance = pair.balanceOfUnderlying(vars.sender); 
        vars.startBorrow = borrowBalanceStored(vars.sender); 

        if(!vars.isUnSwap){
            // amount to buy is borrowedamount + trader's fund 
            vars.amountToSwap = amount + amount.divWadDown(vars.leverage - precision); 

            // Swap junior(senior)-> senior(junior)
            CErc20(underlying).approve(vars.amm, vars.amountToSwap); 
            (vars.amountIn, vars.amountOut) = master._swapFromTranche(
                    amISenior, int256(vars.amountToSwap), vars.priceLimit ,vars.vaultId, data
                ); 

            // Option 1: send senior(junior) to sender, supply senior(junior) and borrow on behalf
            // trader need to have approved pair.underlying to pair token contract 
            CErc20(pair.underlying()).transfer(vars.sender, vars.amountOut); 
            pair.mintInternalBehalf(vars.sender, vars.amountOut); 

            // then borrow junior(senior) with senior(junior) as collateral, which
            // will be burned by the flashMint function. Trader need to have approved 
            // junior for amount to this 
            borrowInternalBehalf(vars.sender, amount); 
            CErc20(underlying).transferFrom(vars.sender, address(this), amount); 

            require(pair.balanceOfUnderlying(vars.sender) - vars.startBalance == vars.amountOut, "LeverageSwap Unsuccessful");
            require(borrowBalanceStored(vars.sender)-vars.startBorrow == amount, "Borrow Err"); 
        }

        else{
            address pairUnderlying = pair.underlying(); 

            // now have borrowed junior to this contract, repay onbehalf 
            this.repayBorrowBehalf(vars.sender, amount);

            // redeem senior(junior) submitted as collateral, need to have approved  
            pair.redeemInternalBehalf(vars.sender, pair.balanceOf(vars.sender)); 

            // Swap senior(junior)-> junior(senior), trader need to have approved 
            // senior(junior) to this address 
            uint256 amountToSwap = CErc20(pairUnderlying).balanceOf(vars.sender); 
            CErc20(pairUnderlying).transferFrom(vars.sender, address(this), amountToSwap); 
            CErc20(pairUnderlying).approve(vars.amm, vars.amountToSwap); 
            (vars.amountIn, vars.amountOut) = master._swapFromTranche(
                    !amISenior, int256(amountToSwap), vars.priceLimit ,vars.vaultId, data
                ); 

            //TODO what if swapped can't cover debt? Will revert TODO do change instead 
            require(pair.balanceOfUnderlying(vars.sender) == 0, "LeverageSwap Failed"); 
            require(borrowBalanceStored(vars.sender) == 0, "Repay Err"); 
        }


        return keccak256("ERC3156FlashBorrower.onFlashLoan"); 

    }


    /// @notice allows trader to leverage swap, junior to senior if this cToken is 
    /// junior, and vice versa
    /// @dev performs a recursive borrow until the leverage is satisfied 
    /// At completion, trader will have 
    function swapWithLeverage(
        uint256 startAmount, 
        uint256 leverage,
        uint256 priceLimit, 
        uint256 vaultId,
        address amm, 
        bytes calldata data) public {

        // Escrow
        CErc20(underlying).transferFrom(msg.sender,address(this), startAmount); 
        CErc20(underlying).approve(address(master), startAmount); 

        // need to (flash)mint excess junior and sell it to senior
        bytes memory data = abi.encode(false, leverage, priceLimit, vaultId, msg.sender, amm); 
        uint256 borrowAmount = leverage.mulWadDown(startAmount) - startAmount; 

        tToken(underlying).flashMint(
            IERC3156FlashBorrower(address(this)), 
            address(underlying), 
            borrowAmount, 
            data
        ); 
    }

    /// @notice allows trader to unwind their leverage swap position 
    /// only closes position in full amount, todo partial 
    function rewindFullLeverage(
        uint256 priceLimit, 
        uint256 vaultId, 
        address amm
        ) external{
        // repay debt by flashminting junior(senior) 
        bytes memory data = abi.encode(true, 0, priceLimit, vaultId,msg.sender, amm ); 
        
        uint256 balBefore = tToken(underlying).balanceOf(address(this)); 
        tToken(underlying).flashMint(
            IERC3156FlashBorrower(address(this)), 
            address(underlying), 
            borrowBalanceStored(msg.sender), 
            data
        ); 
        // Pay remainder after repaying flash loan
        tToken(underlying).transfer(
            msg.sender, 
            tToken(underlying).balanceOf(address(this)) - balBefore 
        ); 
    }
 
}
