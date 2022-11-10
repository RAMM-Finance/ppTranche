pragma solidity ^0.8.9;
import {SafeCastLib} from "./vaults/utils/SafeCastLib.sol";
import {SafeTransferLib} from "./vaults/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./vaults/utils/FixedPointMathLib.sol";

import {ERC20} from "./vaults/tokens/ERC20.sol";
import {Splitter} from "./splitter.sol";
import {tVault} from "./tVault.sol";
import {SpotPool} from "./amm.sol"; 

import {tLendingPoolDeployer, TrancheAMMFactory, TrancheFactory, SplitterFactory} from "./factories.sol";

import "forge-std/console.sol";

// TOOD transfer instead of burn, include vaultID 
/// @notice handles all trading related stuff 
/// Ideas for pricing: queue system, funding rates, fees, 
contract TrancheMaster{
    using FixedPointMathLib for uint256;
    uint256 constant precision = 1e18; 

    uint256 constant feeThreshold = 1e16; 
    uint256 constant kpi = 0; 
    bool feePenaltySet; 
    TrancheFactory tFactory;
    bool boundRevert; 
    uint256 maxDelta; 
    constructor(TrancheFactory _tFactory){
        tFactory = _tFactory; 
        SLIPPAGETOLERANCE = 5e16; //5percent
    }

    mapping(uint256=> DebtData) juniorDebts; //Price space=> debt
    mapping(uint256=> DebtData) seniorDebts; 
    mapping(bytes32=>uint256) dVaultPositions; 
    mapping (bytes32 => uint256) freedVault; 

    struct DebtData{
        // d or c stands for debt Or credit 
        uint256 juniorDorc; 
        uint256 seniorDorc; 
    }

    struct RedeemLocalvars{
        SpotPool amm;  
        Splitter splitter; 
        tVault vault; 

        uint256 multiplier; 
        address senior;
        address junior; 
        uint256 junior_weight; 

        uint256 pTv; //price of tranche/vault
        uint256 pjs; 

        uint256 vaultAmount; 
        uint256 dVaultPosition; 

        uint256 freeTranche; 
        uint256 trancheToBeFreed; 
        uint256 vaultCanBeFreed; 

        uint256 pairAmount; 
        uint256 totalAmount; 
        uint256 redeemVaultAmount; 

        uint256 dvaultPos; 
        uint256 freeVault; 
        uint256 seniorSupply;
        uint256 juniorSupply; 
    }

    /// @notice setup local variables to be used 
    function setUpLocalRedeemVars(uint256 vaultId, bool isSenior, RedeemLocalvars memory vars) internal{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        vars.amm = SpotPool(contracts.amm);
        vars.vault = tVault(contracts.vault); 
        vars.splitter = Splitter(contracts.splitter); 
        vars.junior_weight = vars.splitter.junior_weight(); 
        vars.multiplier = isSenior ? vars.junior_weight.divWadDown(precision - vars.junior_weight)
                                  : (precision - vars.junior_weight).divWadDown(vars.junior_weight);
        (vars.junior, vars.senior) = vars.splitter.getTrancheTokens();
    } 

    /// @notice redeems for debt vault to do arbitrage or slippage exit  
    /// such that a complete senior and junior pair need not be available 
    /// @param amount is amount of senior/junior wishing to redeem 
    /// @dev uses the current prices to store 
    function redeemToDebtVault(
        uint256 amount, 
        bool isSenior, 
        uint256 vaultId
        ) external returns(uint256, uint256){
        RedeemLocalvars memory vars; 
        setUpLocalRedeemVars(vaultId, isSenior, vars); 

        // Get pTv, the price of tranche/vault  
        (,, vars.pjs) = vars.splitter.computeValuePrices();
        vars.pTv = getPTV(vars.pjs, isSenior, vars.junior_weight); 

        // redeem amount of junior or senior -> get how much vault is it worth given pTv
        vars.vaultAmount = vars.pTv.mulWadDown(amount); 

        // Record new debtVault position 
        dVaultPositions[keccak256(abi.encodePacked(vaultId, msg.sender,isSenior, vars.pjs))] += vars.vaultAmount; 

        // Record Dorc and Escrow 
        if(isSenior) {
            juniorDebts[cantorPair(vaultId, vars.pjs)].juniorDorc += vars.multiplier.mulWadUp(amount); 
            juniorDebts[cantorPair(vaultId, vars.pjs)].seniorDorc += amount;
            ERC20(vars.senior).transferFrom(msg.sender,address(vars.splitter), amount); 
        }
        else {
            seniorDebts[cantorPair(vaultId, vars.pjs)].seniorDorc += vars.multiplier.mulWadUp(amount); 
            seniorDebts[cantorPair(vaultId, vars.pjs)].juniorDorc += amount; 
            ERC20(vars.junior).transferFrom(msg.sender,address(vars.splitter), amount); 
        }
        
        return (vars.vaultAmount, vars.pjs); 
    }

    /// @notice redeems debtVault to real Vault. 
    /// claims redeemable(where pair debt has been paid) dVault, first in first out basis 
    function redeemFromDebtVault(
        uint256 dVaultAmount,
        uint256 pjs,  
        uint256 vaultId, 
        bool isSenior
        ) external returns(uint256){
        RedeemLocalvars memory vars; 
        setUpLocalRedeemVars(vaultId, isSenior, vars); 
        vars.dvaultPos = dVaultPositions[keccak256(abi.encodePacked(vaultId, msg.sender,isSenior, pjs))]; 
        (vars.seniorSupply, vars.juniorSupply) = (ERC20(vars.senior).totalSupply(), ERC20(vars.junior).totalSupply());

        // Check if enough balance
        require(vars.dvaultPos >= dVaultAmount, "balERR"); 
        DebtData memory debtData = isSenior ? juniorDebts[cantorPair(vaultId, pjs)]
                                            : seniorDebts[cantorPair(vaultId, pjs)]; 

        if(isSenior && debtData.seniorDorc > 0){
            // Find how much did the pair tranche redeem at given pjs, to compute the available tranche to be freed
            vars.freeTranche = debtData.seniorDorc.mulWadUp(vars.multiplier) - debtData.juniorDorc; 
            vars.trancheToBeFreed = vars.freeTranche.divWadDown(vars.multiplier); 

            // find how much vault does this free tranche translate to
            vars.pTv = getPTV(pjs, isSenior, vars.junior_weight); 
            vars.vaultCanBeFreed = min(vars.trancheToBeFreed.mulWadDown(vars.pTv),  dVaultAmount); 
            vars.trancheToBeFreed = vars.vaultCanBeFreed.divWadDown(vars.pTv); 

            // If tranchedTobefreed greater than seniorDorc, means that somebody already consumed this liq
            if (debtData.seniorDorc < vars.trancheToBeFreed)
                revert("liqERR"); 

            // decrease redeemer's credit and global debt. Underflow conditions checked already
            unchecked{
                juniorDebts[cantorPair(vaultId, pjs)].seniorDorc -= vars.vaultCanBeFreed.divWadDown(vars.pTv); 
                dVaultPositions[keccak256(abi.encodePacked(vaultId, msg.sender,isSenior, pjs))] -= vars.vaultCanBeFreed;
            }

            // Burn both pairs by the appropriate ratio, and transfer 
            vars.splitter.trustedBurn(false, address(vars.splitter), 
                vars.vaultCanBeFreed.divWadDown(vars.pTv).mulWadDown(vars.multiplier)); 
            vars.splitter.trustedBurn(true, address(vars.splitter), vars.vaultCanBeFreed.divWadDown(vars.pTv)); 
            vars.vault.transferFrom(address(vars.splitter), msg.sender, vars.vaultCanBeFreed);

            // Invariant 1: Senior:Junior supply ratio always hold 
            assertApproxEqual(vars.seniorSupply.mulWadDown(vars.multiplier), vars.juniorSupply, 10 ); 
        }   
        else if(!isSenior && debtData.juniorDorc >0){
            vars.freeTranche = debtData.juniorDorc.mulWadDown(vars.multiplier) - debtData.seniorDorc; 
            vars.trancheToBeFreed = vars.freeTranche.divWadDown(vars.multiplier);

            vars.pTv = getPTV(pjs, isSenior, vars.junior_weight); 
            vars.vaultCanBeFreed = min(vars.trancheToBeFreed.mulWadDown(vars.pTv) ,  dVaultAmount); 
            vars.trancheToBeFreed = vars.vaultCanBeFreed.divWadDown(vars.pTv); 

            if(debtData.juniorDorc < vars.trancheToBeFreed)
                revert("liqERR");

            unchecked{
                seniorDebts[cantorPair(vaultId, pjs)].juniorDorc -= vars.vaultCanBeFreed.divWadDown(vars.pTv); 
                dVaultPositions[keccak256(abi.encodePacked(vaultId, msg.sender,isSenior, pjs))] -= vars.vaultCanBeFreed; 
            } 

            vars.splitter.trustedBurn(true, address(vars.splitter), 
                vars.vaultCanBeFreed.divWadDown(vars.pTv).mulWadDown(vars.multiplier)); 
            vars.splitter.trustedBurn(false, address(vars.splitter), vars.vaultCanBeFreed.divWadDown(vars.pTv)); 
            vars.vault.transferFrom(address(vars.splitter), msg.sender, vars.vaultCanBeFreed); 
            assertApproxEqual(vars.juniorSupply.mulWadDown(vars.multiplier), vars.seniorSupply, 10 ); 
        }

        // check how much can be redeemed from swaps from vault, and how much can be redeemed by msg.sender
        vars.freeVault = freedVault[keccak256(abi.encodePacked(isSenior, pjs, vaultId))]; 
        if(vars.freeVault > 0 && vars.dvaultPos >0){
            // give msg sender freedvault first in first out basis 
            freedVault[keccak256(abi.encodePacked(isSenior, pjs, vaultId))] -= min(
                vars.dvaultPos,vars.freeVault);
            dVaultPositions[keccak256(abi.encodePacked(vaultId, msg.sender,isSenior, pjs))] -= min(
                vars.dvaultPos,vars.freeVault); 

            //TODO burn escrowed senior tokens  

            vars.vault.transferFrom(address(vars.splitter), msg.sender,min(vars.dvaultPos,vars.freeVault)); 

            return min(vars.dvaultPos,vars.freeVault) + vars.vaultCanBeFreed;
        }

        // Invariant 2: all vault should be redeemable from splitter 
        assertApproxEqual(vars.splitter.escrowedVault(), vars.seniorSupply + vars.juniorSupply, 10); 

        return vars.vaultCanBeFreed; 
    }

    /// @notice traders who wish to use the queue built up to redeem their
    /// vault tokens without slippage at specific pjs 
    /// @param amount: amount to be redeemed. For example if want to redeem amount = 30 junior, 
    /// it will find 30* multiplier worth of senior to pair with from the debtVault minters
    function redeemByDebtVault(
        uint256 amount,
        uint256 pjs, 
        bool isSenior, 
        uint256 vaultId) external returns(uint256){
        RedeemLocalvars memory vars; 
        setUpLocalRedeemVars(vaultId, isSenior, vars); 
        vars.pTv = getPTV(pjs, isSenior, vars.junior_weight); 

        // how much vault will the redeemer get
        vars.redeemVaultAmount = amount.mulWadDown(vars.pTv);
        if(!isSenior) {
            // reduce repayed debt and transfer, revert if not possible 
            require(juniorDebts[cantorPair(vaultId, pjs)].juniorDorc >= amount, "liqERR");   
            unchecked {juniorDebts[cantorPair(vaultId, pjs)].juniorDorc -= amount;} 

            // Escrow tranche to splitter and spit back vault 
            ERC20(vars.junior).transferFrom(msg.sender, address(vars.splitter), amount); 
            vars.vault.transferFrom(address(vars.splitter), msg.sender, vars.redeemVaultAmount);  
        }

        else{
            require(seniorDebts[cantorPair(vaultId, pjs)].seniorDorc >= amount, "liqERR"); 
            unchecked {seniorDebts[cantorPair(vaultId, pjs)].seniorDorc -= amount; }

            ERC20(vars.senior).transferFrom(msg.sender, address(vars.splitter), amount); 
            vars.vault.transferFrom(address(vars.splitter), msg.sender, vars.redeemVaultAmount);
        }

        return vars.redeemVaultAmount; 
    }

    /// @notice for traders who want to unredeem their debt vault back to the initial position 
    /// @param amount is amount of dVault wishing to redeem back to the tranche
    function unRedeemDebtVault(
        uint256 amount,
        uint256 pjs, 
        bool isSenior, 
        uint256 vaultId) external{
        RedeemLocalvars memory vars; 
        setUpLocalRedeemVars(vaultId, isSenior, vars); 

        // get how much vault does the amount translate to, given pjs. 
        vars.pTv = getPTV(pjs, isSenior, vars.junior_weight);
        vars.freeTranche = amount.divWadDown(vars.pTv); 

        if(isSenior){
            // underflow if can't be unredeemed 
            juniorDebts[cantorPair(vaultId, pjs)].juniorDorc -= vars.multiplier.mulWadDown(vars.freeTranche); 
            juniorDebts[cantorPair(vaultId, pjs)].seniorDorc -= vars.freeTranche; 
            dVaultPositions[keccak256(abi.encodePacked(vaultId, msg.sender,isSenior, pjs))] -= amount; 

            ERC20(vars.senior).transferFrom(address(vars.splitter), msg.sender, vars.freeTranche); 
        }

        else{
            seniorDebts[cantorPair(vaultId, pjs)].seniorDorc -= vars.multiplier.mulWadDown(vars.freeTranche);
            seniorDebts[cantorPair(vaultId, pjs)].juniorDorc -= vars.freeTranche; 
            dVaultPositions[keccak256(abi.encodePacked(vaultId, msg.sender,isSenior, pjs))] -= amount; 

            ERC20(vars.junior).transferFrom(address(vars.splitter), msg.sender, vars.freeTranche); 
        }
    }

    /// @notice use the dVault liquidity that was created to creat dVaults
    //  to perform slippage free trades, and free up dvaults for redemption 
    function swapFromDebtVault(        
        uint256 amount,//amount is in v
        uint256 pjs, 
        bool isSenior, // if isSenior, want to buy senior
        uint256 vaultId) external returns(uint256){
        RedeemLocalvars memory vars; 
        setUpLocalRedeemVars(vaultId, isSenior, vars); 
        vars.pTv = getPTV(pjs, isSenior, vars.junior_weight); 

        // want senior, then take in junior and pay junior debt
        if (isSenior){
            // underflow if not enough liq.
            juniorDebts[cantorPair(vaultId, pjs)].seniorDorc -= amount.divWadDown(vars.pTv); 
            juniorDebts[cantorPair(vaultId, pjs)].juniorDorc -= amount.divWadDown(vars.pTv).mulWadDown(vars.multiplier); 
            ERC20(vars.senior).transferFrom(address(vars.splitter), msg.sender, amount.divWadDown(vars.pTv));
        }
        else{
            seniorDebts[cantorPair(vaultId, pjs)].juniorDorc -= amount.divWadDown(vars.pTv); 
            seniorDebts[cantorPair(vaultId, pjs)].seniorDorc -= amount.divWadDown(vars.pTv).mulWadDown(vars.multiplier); 
            ERC20(vars.junior).transferFrom(address(vars.splitter), msg.sender, amount.divWadDown(vars.pTv));
        }

        // record how much vault has been freed, so  
        freedVault[keccak256(abi.encodePacked(isSenior, pjs, vaultId))] += amount; 

        // escrow from buyer  
        vars.vault.transferFrom(msg.sender, address(vars.splitter), amount);
    } 



    struct SwapLocalvars{    
        SpotPool amm; 
        ERC20 want; 
        tVault vault; 
        Splitter splitter; 

        address senior;
        address junior; 

        uint256 amountIn;
        uint256 amountOut; 

        uint256 juniorAmount; 
        uint256 seniorAmount; 
        // uint256 multiplier; 
        uint256 junior_weight;
        uint256 pTv; 
        uint256 requiredPair;
        uint256 markpjs; 
        uint256 multiplier; 
        uint256 seniorSupply;
        uint256 juniorSupply; 
    }

    function setUpLocalSwapVars(uint256 vaultId, SwapLocalvars memory vars) internal{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        vars.amm = SpotPool(contracts.amm);
        vars.splitter = Splitter(contracts.splitter); 
        vars.vault = tVault(contracts.vault); 
        (vars.junior, vars.senior) = vars.splitter.getTrancheTokens();
        vars.junior_weight = vars.splitter.junior_weight(); 
    }

    /// @notice function for swapping from junior->senior and vice versa
    /// @dev positive amount for junior is denominated in junior, negavtive amount in senior, vice versa
    function _swapFromTranche(
        bool toJunior, 
        int256 amount, 
        uint256 priceLimit, 
        uint256 vaultId, 
        bytes calldata data
        ) public returns(uint256 amountIn, uint256 amountOut){
        SwapLocalvars memory vars; 
        setUpLocalSwapVars(vaultId, vars); 

        // Set up automatic price limits 
        if(priceLimit==0) {
            if(toJunior)
                priceLimit = vars.amm.getCurPrice().mulWadDown(precision + 1e17); 
            else priceLimit = vars.amm.getCurPrice().mulWadDown(precision - 1e17); 
        }
        
        // Make a trade first so that price after the trade can be used
        (amountIn,  amountOut) =
            vars.amm.takerTrade(msg.sender, toJunior, amount, priceLimit, data);

        checkBoundRevert(vars); 

        if(feePenaltySet){
            (uint indexPsu, uint indexPju,  ) = vars.splitter.computeValuePrices(); 
            (uint markPsu, uint markPju) = vars.splitter.computeImpliedPrices(
                vars.amm.getCurPrice() // TODO!! ez manipulation cache it somehow
                );
                
            // fee is always denominated in amountOut 
            if(toJunior && markPju+feeThreshold < indexPju){
                uint fee = getFee(indexPju, markPju); 
                ERC20(vars.junior).transferFrom(msg.sender,address(vars.splitter), fee);
            }
            else if(!toJunior && markPju > indexPju + feeThreshold){
                uint fee = getFee(indexPsu, markPsu); 
                ERC20(vars.senior).transferFrom(msg.sender, address(vars.splitter), fee);
            }
        }
    }

    /// @notice buy tranche token from vault. 
    /// @dev Split the vault and swap unwanted to wanted tranche
    /// @param amount is amount of vault to split 
    function _swapFromInstrument(
        bool toJunior, 
        uint256 amount, 
        uint priceLimit, 
        uint vaultId, 
        bytes calldata data) public returns(uint256 amountIn, uint256 amountOut){
        SwapLocalvars memory vars; 
        setUpLocalSwapVars(vaultId, vars);
        (vars.seniorSupply, vars.juniorSupply) 
            = (ERC20(vars.senior).totalSupply(), ERC20(vars.junior).totalSupply());
        if(priceLimit==0) {
            if(toJunior)
                priceLimit = vars.amm.getCurPrice().mulWadDown(precision + 1e17); 
            else priceLimit = vars.amm.getCurPrice().mulWadDown(precision - 1e17); 
        }
        // Escrow and split to this address
        vars.vault.transferFrom(msg.sender, address(this), amount); 
        vars.vault.approve(address(vars.splitter), amount); 
        (vars.juniorAmount,  vars.seniorAmount) = vars.splitter.split(amount); 
        vars.amountIn = toJunior ? vars.seniorAmount : vars.juniorAmount; 

        if (toJunior) ERC20(vars.senior).approve(address(vars.amm), vars.amountIn); 
        else ERC20(vars.junior).approve(address(vars.amm), vars.amountIn);
        (amountIn, amountOut) 
            = vars.amm.takerTrade(address(this), toJunior, int256(vars.amountIn), priceLimit, data); 

        checkBoundRevert(vars); 

        if(!toJunior) ERC20(vars.senior).transfer(msg.sender, amountOut + vars.seniorAmount );
        else ERC20(vars.junior).transfer(msg.sender, amountOut + vars.juniorAmount);  

        assertApproxEqual(vars.splitter.escrowedVault(), vars.seniorSupply + vars.juniorSupply, 10); 
    }

    /// @notice two ways to buy junior/senior from underlying 
    /// first is minting vault, splitting, and trading unwanted to wanted(either by taker or maker)
    /// This function is for taker swapping 
    /// @dev I param wantSenior of param amount
    /// param price limit is the max price of junior/senior. Ideally transaction should 
    /// fail if priceLimit != current price, which should be pjs
    function swapFromUnderlying(
        bool wantSenior, 
        uint amount,
        uint vaultId,
        uint priceLimit,
        bytes calldata data) 
        public {
        SwapLocalvars memory vars; 
        setUpLocalSwapVars(vaultId, vars);

        // Mint to this addres
        vars.want.transferFrom(msg.sender, address(this), amount); 
        vars.want.approve(address(vars.vault), amount); 
        uint shares = vars.vault.convertToShares(amount); 
        vars.vault.mint(shares, address(this));

        // Split to this address and swap 
        vars.vault.approve(address(vars.splitter), shares); 
        (uint juniorAmount, uint seniorAmount) = vars.splitter.split( shares); //junior and senior now minted to this address 
        uint amountIn = wantSenior? juniorAmount : seniorAmount; 
        (, uint poolamountOut) = vars.amm.takerTrade(address(this), !wantSenior, 
                int256(amountIn), priceLimit, data); 

        checkBoundRevert(vars); 

        if(wantSenior) ERC20(vars.senior).transfer(msg.sender, poolamountOut + seniorAmount );
        else ERC20(vars.junior).transfer(msg.sender, poolamountOut + juniorAmount);  
    }  

    /// @notice use the AMM to swap tranche back to vault
    function _swapToInstrument(
        bool fromJunior, 
        uint256 amount, 
        uint priceLimit, 
        uint vaultId, 
        bytes calldata data
        ) public returns(uint256 amountIn, uint256 amountOut){
        SwapLocalvars memory vars; 
        setUpLocalSwapVars(vaultId, vars);

        // swap to ratio first 
        (vars.amountIn, vars.amountOut, ) = _swapToRatio(fromJunior, amount, 
            priceLimit,vaultId, data, vars ); 

        // give them back vault 
        if(!fromJunior) vars.splitter.merge(vars.amountIn); 
        else vars.splitter.merge(vars.amountOut); 
        
    }

    uint256 public immutable SLIPPAGETOLERANCE; 

    /// @notice given a tranche, swaps it back to the ratio for  
    /// returns (pair1, pair2), remainder 
    function _swapToRatio(
        bool fromJunior, 
        uint256 amount, 
        uint priceLimit, 
        uint vaultId, 
        bytes calldata data, 
        SwapLocalvars memory vars) public returns(uint256, uint256, uint256 ) {

        vars.markpjs = vars.amm.getCurPrice(); 
        vars.multiplier = !fromJunior ? vars.junior_weight.divWadDown(precision - vars.junior_weight)
                                  : (precision - vars.junior_weight).divWadDown(vars.junior_weight);
        // Senior-> Junior                          
        if(!fromJunior){
            //How much senior to swap for given pjs 
            vars.amountIn = (amount.mulWadDown( vars.multiplier )).divWadDown(vars.markpjs+ vars.multiplier);

            // This is amountout with slippage, so it will be less(or equal) to markpjs * amount 
            (vars.amountIn, vars.amountOut) = vars.amm.takerTrade(address(this), 
            !fromJunior, int256(vars.amountIn), priceLimit, data);  

            checkBoundRevert(vars); 

            // New amountIn should account for 
            return(vars.amountOut ,  //2.8
            vars.amountOut.mulWadDown(vars.multiplier), // 6.4
            amount - vars.amountIn - vars.amountOut.mulWadDown(vars.multiplier)); // 10-3-6.4 remainder 
        }
        else{// 10junior-> 7senior 3 junior 
            vars.amountIn = (amount.mulWadDown( vars.multiplier )).divWadDown( 
                precision.divWadDown(vars.markpjs)+ vars.multiplier); //7 junior

            (vars.amountIn, vars.amountOut) = vars.amm.takerTrade(address(this), 
                !fromJunior, int256(vars.amountIn), priceLimit, data); 

            checkBoundRevert(vars); 

            return(vars.amountOut, // 6.7
                vars.amountOut.mulWadDown(vars.multiplier), //6.7*3/7
                amount-vars.amountIn - vars.amountOut.mulWadDown(vars.multiplier)// 10-6.7
            ); 
        }
    }

    /// @notice reverts trade when price outside boundary 
    function checkBoundRevert(SwapLocalvars memory vars) internal {
        if(boundRevert){
            (,,uint256 pjs) = vars.splitter.getStoredValuePrices(); 
            uint256 curPrice = vars.amm.getCurPrice(); 
            if (pjs.mulWadDown(precision + maxDelta) < curPrice 
            || pjs.mulWadDown(precision -maxDelta) > curPrice) 
                revert("Trade out bound"); 
        }
    }

    /// @notice amount is in want, not tVault 
    function mintTVault(
        uint256 vaultId, 
        uint256 amount) public{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        ERC20(contracts.param._want).transferFrom(msg.sender, address(this), amount); 
        ERC20(contracts.param._want).approve(contracts.vault, amount ); 

        uint256 shares = tVault(contracts.vault).previewDeposit(amount); 
        tVault(contracts.vault).mint(shares,msg.sender); 
    }

    function redeemTVault(
        uint256 vaultId, 
        uint256 amount) public{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        tVault(contracts.vault).redeem(amount, msg.sender, msg.sender); 
    }

    /// @notice amount is in tVault
    function splitTVault(
        uint256 vaultId,
        uint256 amount
        ) public {
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        tVault(contracts.vault).transferFrom(msg.sender, address(this), amount); 
        tVault(contracts.vault).approve(contracts.splitter, type(uint256).max);
        (uint ja, uint sa) = Splitter(contracts.splitter).split(amount); 
        (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens();

        ERC20(senior).transfer(msg.sender, sa); 
        ERC20(junior).transfer(msg.sender, ja); 
    }

    function mergeTVault(
        uint256 vaultId, 
        uint256 junior_amount 
        ) public {
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        (, address senior) = Splitter(contracts.splitter).getTrancheTokens();

        uint256 junior_weight = Splitter(contracts.splitter).junior_weight(); 
        uint256 senior_amount = (precision-junior_weight)
            .mulWadDown(junior_weight).mulWadDown(junior_amount); 
        require(ERC20(senior).balanceOf(msg.sender) >= senior_amount, "Not enough senior tokens"); 

        Splitter(contracts.splitter).mergeFromMaster( junior_amount, senior_amount, msg.sender);
    }

    /// @notice amount is in want, not tVault 
    function mintAndSplit(uint256 vaultId, uint256 amount) public returns(uint, uint){
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        ERC20(contracts.param._want).transferFrom(msg.sender, address(this), amount); 
        ERC20(contracts.param._want).approve(contracts.vault, amount ); 

        uint256 shares = tVault(contracts.vault).previewDeposit(amount); 
        tVault(contracts.vault).mint(shares,msg.sender); 
        tVault(contracts.vault).approve(contracts.splitter, shares);
        return Splitter(contracts.splitter).split(shares);
    }

    function mergeAndRedeem(uint256 vaultId, uint256 junior_amount) public{
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        uint256 junior_weight = Splitter(contracts.splitter).junior_weight(); 
        uint256 senior_amount = (precision-junior_weight)
            .mulWadDown(junior_weight).mulWadDown(junior_amount); 
        (,address senior) = Splitter(contracts.splitter).getTrancheTokens();

        require(ERC20(senior).balanceOf(msg.sender) >= senior_amount, "Not enough senior tokens"); 

        Splitter(contracts.splitter).mergeFromMaster( junior_amount, senior_amount, msg.sender);
        tVault(contracts.vault).redeem(junior_amount + senior_amount, msg.sender, msg.sender); 
    }

    function getAMM(uint256 vaultId) public view returns(address){
        return tFactory.getContracts(vaultId).amm; 
    }

    function getdVaultBal(uint256 vaultId, address who, bool isSenior, uint256 pjs) public view returns(uint256){
        return dVaultPositions[keccak256(abi.encodePacked(vaultId,who,isSenior, pjs))];
    }

    /// @notice returns how much can be swapped without slippage at price pjs 
    function getAvailableDVaultLiq(uint256 vaultId, uint256 pjs, bool isSenior) public view returns(uint256){
        return isSenior? juniorDebts[cantorPair(vaultId, pjs)].seniorDorc 
            : seniorDebts[cantorPair(vaultId, pjs)].juniorDorc;  
    }
    
    function getFreedVault(uint256 vaultId, uint256 pjs, bool isSenior) public view returns(uint256){
        return freedVault[keccak256(abi.encodePacked(isSenior, pjs, vaultId))]; 
    } 

    function getDorc(uint256 vaultId, uint256 pjs) public view returns(uint256, uint256,uint256, uint256){
        return( juniorDebts[cantorPair(vaultId, pjs)].juniorDorc , 
                juniorDebts[cantorPair(vaultId, pjs)].seniorDorc , 
                seniorDebts[cantorPair(vaultId, pjs)].juniorDorc ,
                seniorDebts[cantorPair(vaultId, pjs)].seniorDorc);
    }

    function getPTV(uint256 pjs, bool isSenior, uint256 junior_weight) public pure returns(uint256 pTv){
        uint256 multiplier = isSenior ? junior_weight.divWadDown(precision - junior_weight)
                             : (precision - junior_weight).divWadDown(junior_weight);

        pTv = isSenior ? (multiplier + precision).divWadDown(multiplier.mulWadDown(pjs)+ precision)
                       : (multiplier + precision).divWadDown(multiplier.divWadDown(pjs)+ precision); 
    }

    function cantorPair(uint256 x, uint256 y) internal pure returns(uint256){
        return ( (x+y) * (x+y+1) + y ); 
    }

    /// @notice calculates trading fee when current price is offset from value price
    /// by feeThreshold param
    function getFee(uint256 p1, uint256 p2) public view returns(uint256){
        return kpi*(p1-p2); 
    }
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    function assertApproxEqual(uint256 a, uint256 b, uint256 roundlimit) internal pure returns(bool){

        return ( a <= b+roundlimit || a>= b-roundlimit); 
    }

    function getTrancheTokens(uint256 vaultId) public view returns(address, address){
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        return Splitter(contracts.splitter).getTrancheTokens();
    }

}









