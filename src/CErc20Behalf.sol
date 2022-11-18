pragma solidity ^0.8.9;

import "forge-std/console.sol";
import "./compound/Comptroller.sol"; 
import "./compound/CErc20.sol"; 

contract CErc20Behalf is CErc20{

    address public pairAddress; 

    /// @param mintAmount The amount of the underlying asset to supply
    function mintInternalBehalf(address minter, uint mintAmount) 
        public 
        nonReentrant {   
        require(msg.sender == pairAddress, "Only Pair");
        accrueInterest();
        // mintFresh emits the actual Mint event if successful and logs on errors, so we don't need to
        mintFresh(minter, mintAmount);
    }
    /// @param borrowAmount The amount of the underlying asset to borrow 
    function borrowInternalBehalf(address borrower, uint borrowAmount)
        public
        nonReentrant {
        accrueInterest();
        // borrowFresh emits borrow-specific logs on errors, so we don't need to
        borrowFresh(payable(borrower), borrowAmount);
    }

    function redeemInternalBehalf(address redeemer, uint redeemAmount) 
        public
        nonReentrant {
        require(msg.sender == pairAddress, "Only Pair");

        accrueInterest(); 
        redeemFresh(payable(redeemer), redeemAmount, 0);

    }
}

