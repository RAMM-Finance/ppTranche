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
        if(priceLimit==0) {
            if(toJunior)
                priceLimit = vars.amm.getCurPrice().mulWadDown(precision + 1e17); 
            else priceLimit = vars.amm.getCurPrice().mulWadDown(precision - 1e17); 
        }
        // Make a trade first so that price after the trade can be used
        (amountIn,  amountOut) =
            vars.amm.takerTrade(msg.sender, toJunior, amount, priceLimit, data);

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

            return(vars.amountOut, // 6.7
                vars.amountOut.mulWadDown(vars.multiplier), //6.7*3/7
                amount-vars.amountIn - vars.amountOut.mulWadDown(vars.multiplier)// 10-6.7
            ); 
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

    /// @notice uses the queued dVault positions to redeem, need to loop from current 
    /// pjs till all amount is filled 
    function fillQueue(
        bool fromJunior, 
        uint256 amount, 
        uint priceLimit, 
        uint vaultId, 
        bytes calldata data
        ) public returns(uint256 amountIn, uint256 amountOut){
        // SwapLocalvars memory vars; 
        // setUpLocalSwapVars(vaultId, vars);

        // redeemByDebtVault()
    }

    function swapFromTranche() external{}
    function swapFromInstrument() external {}

    /// @notice when a new tranche is initiated, and trader want senior or junior, can place bids/asks searching for
    /// a counterparty
    function freshTrancheNewOrder() external{}

    /// @notice atomic leverage swap from junior to senior or senior to junior
    /// If senior to junior, need to use junior as collateral and borrow more senior to get more junio
    /// and vice versa
    function leverageSwap() external {}

    /// @notice executes arb by pair redeeming
    /// It will fetch appropriate junior amounts from the debt pool =
    /// param senior is true if arbitrageur has senior and want junior to pair
    function arbByPairRedeem(bool senior, uint amount) external {
        // if(senior) fetchFromDebtPool(junior )
    }

    function assertApproxEqual(uint256 a, uint256 b, uint256 roundlimit) internal pure returns(bool){

        return ( a <= b+roundlimit || a>= b-roundlimit); 
    }

    function getTrancheTokens(uint256 vaultId) public view returns(address, address){
        TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
        return Splitter(contracts.splitter).getTrancheTokens();
    }

}













    /// @notice if is ask, selling junior for senior . if !isAsk, buying junior from senior 
    /// assumes approval is already set (for now)
    // function doMakerTrade(
    //     uint256 vaultId,
    //     uint256 amount, 
    //     uint256 isAsk, 
    //     uint16 point) public{
    //     TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId);
    //     (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 

    //     if(isAsk){
    //         ERC20(junior)
    //         ERC20(junior).approve(contracts.amm, )
    //         SpotPool(contracts.amm).makerTrade(false, amount, point ); 
    //         function doLimitSpecifiedPoint(uint256 amountInToBid, bool limitBelow, uint16 point) public {
    //     }
    //     if(!limitBelow){
    //     TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
    //     (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
    //     ERC20(junior).approve(contracts.amm, type(uint256).max); 
    //     SpotPool(contracts.amm).makerTrade( false, amountInToBid, point); 
    //     }
    //     else{
    //     TrancheFactory.Contracts memory contracts = tFactory.getContracts(0);
    //     (address junior, address senior) = Splitter(contracts.splitter).getTrancheTokens(); 
    //     ERC20(senior).approve(contracts.amm, type(uint256).max); 
    //     SpotPool(contracts.amm).makerTrade( true, amountInToBid, point); 
    //     }
    // }
    // }


    // /// @notice adds liquidity to pool with vaultId
    // /// @dev amount is denominated in want of the tVault, so want-> mint tVault-> split -> provide 
    // function addLiquidity(
    //     address provider,
    //      uint amount, 
    //      uint vaultId) external returns(uint){  
    //     TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
    //     ERC20 want = ERC20(contracts.param._want); 
    //     tVault vault = tVault(contracts.vault); 
    //     StableSwap amm = StableSwap(contracts.amm); 
    //     Splitter splitter = Splitter(contracts.splitter); 

    //     //Mint tVault
    //     want.transferFrom(provider, address(this), amount); 
    //     want.approve(address(vault), amount ); 
    //     uint shares = vault.convertToShares(amount);
    //     vault.mint(shares, address(this)); 

    //     //Split 
    //     vault.approve(address(splitter), shares);
    //     (uint ja, uint sa) = splitter.split(vault, shares); 

    //     //provide(same amount to get a balanced pool)
    //     uint lpshares = separatAndProvide(ja, sa, splitter, amm); 
    //     // uint[2] memory amounts; 
    //     // amounts[0] = ja; 
    //     // amounts[1] = ja; 
    //     // address[] memory tranches = splitter.getTrancheTokens(); 
    //     // ERC20(tranches[0]).approve(address(amm), sa);
    //     // ERC20(tranches[1]).approve(address(amm), ja); 
    //     // uint lpshares = amm.addLiquidity(amounts, 0); 

    //     //Transfer
    //     tFactory.increaseLPTokenBalance(provider, vaultId, lpshares);

    //     return lpshares; 

    // }

    // function separatAndProvide(uint ja, uint sa, Splitter splitter, StableSwap amm) internal returns(uint){
    //     uint[2] memory amounts; 
    //     amounts[0] = ja; 
    //     amounts[1] = ja; 
    //     address[] memory tranches = splitter.getTrancheTokens(); 
    //     ERC20(tranches[0]).approve(address(amm), sa);
    //     ERC20(tranches[1]).approve(address(amm), ja); 
    //     uint lpshares = amm.addLiquidity(amounts, 0); 
    //     return lpshares; 
    // }

    // /// @notice remove liquidity from the pool, and gives back merged token
    // function removeLiquidity(
    //     address taker, 
    //     uint shares, 
    //     uint vaultId) external {
    //     TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
    //     ERC20 want = ERC20(contracts.param._want); 
    //     tVault vault = tVault(contracts.vault); 
    //     StableSwap amm = StableSwap(contracts.amm); 
    //     Splitter splitter = Splitter(contracts.splitter); 

    //     //Transfer
    //     tFactory.decreaseLPTokenBalance(taker, vaultId, shares); 

    //     //Remove
    //     uint[2] memory minAmounts;
    //     minAmounts[0] =0;
    //     minAmounts[1] =0;
    //     uint[2] memory amountsOut = amm.removeLiquidity(shares,minAmounts);
    //     uint junioramount = amountsOut[1]; 

    //     //Merge-> junior and senior in, tVault out to this address
    //     uint merged_token_amount = splitter.merge(vault, junioramount); 

    //     //Redeem vault 
    //     vault.redeem(merged_token_amount, taker, address(this)); 

    // }



    // /// @notice buy tranche token in one tx from underlying tVault collatera; 
    // /// @param amount is collateral in 
    // /// @dev 1.Mints vault token
    // /// 2. Splits Vault token from splitter 
    // /// 3. Swap unwanted tToken to wanted tToken
    // /// 4. Transfer wanted tToken to user 
    // function buy_tranche(
    //     uint vaultId, 
    //     uint amount, 
    //     bool wantSenior
    //     ) external returns(uint)
    // {
    //     TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
    //     ERC20 want = ERC20(contracts.param._want); 
    //     tVault vault = tVault(contracts.vault); 
    //     StableSwap amm = StableSwap(contracts.amm); 
    //     Splitter splitter = Splitter(contracts.splitter); 

    //     //1.Mint
    //     want.transferFrom(msg.sender, address(this), amount); 
    //     want.approve(address(vault), amount); 
    //     uint shares = vault.convertToShares(amount); 
    //     vault.mint(shares, address(this));

    //     //2. Split
    //     vault.approve(address(splitter), shares); 
    //     (uint ja, uint sa) = splitter.split(vault, shares); //junior and senior now minted to this address 

    //     //Senior tokens are indexed at 0 in each amm 
    //     uint tokenIn = wantSenior? 1 : 0;
    //     uint tokenOut = 1-tokenIn; 
    //     uint tokenInAmount = wantSenior? ja: sa; 
    //     address[] memory tranches = splitter.getTrancheTokens(); 

    //     //3. Swap 
    //     ERC20(tranches[tokenIn]).approve(address(amm), tokenInAmount); 
    //     uint tokenOutAmount = amm.swap(tokenIn, tokenOut, tokenInAmount, 0); //this will give this contract tokenOut

    //     //4. Transfer 
    //     uint transferamount = wantSenior? sa: ja; 
    //     ERC20(tranches[tokenOut]).transfer(msg.sender, transferamount + tokenOutAmount); 
    //     return transferamount + tokenOutAmount; 

    // }

    // /// @notice sell tranche token for collateral in one tx
    // /// 1. Transfer tToken 
    // /// 2. Swap tTokens to get in correct ratio
    // function sell_tranche(
    //     uint vaultId, 
    //     uint amount, 
    //     bool isSenior 
    //     ) external 
    // {
    //     TrancheFactory.Contracts memory contracts = tFactory.getContracts(vaultId); 
    //     ERC20 want = ERC20(contracts.param._want); 
    //     tVault vault = tVault(contracts.vault); 
    //     StableSwap amm = StableSwap(contracts.amm); 
    //     Splitter splitter = Splitter(contracts.splitter); 

    //     //1. Transfer tToken to this contract
    //     address[] memory tranches = splitter.getTrancheTokens(); 
    //     uint tokenIn = isSenior? 0:1; 
    //     ERC20(tranches[tokenIn]).transfer(msg.sender, amount); 

    //     //2. Swap to get correct ratio, if intoken is senior then need junior, 
    //     (uint pairTokenAmount, uint swappedTokenAmount) = swapToRatio(amount, !isSenior, tranches, vault, amm); 
    //     uint amountAfterSwap =  amount - swappedTokenAmount; 
    //     //amountAfterSwap, pairTokenAmount should be the amount of tranche tokens in ratio 

    //     //3.Merge the tokens (merged tVault token will be directed to this contract)
    //     uint junior_amount = isSenior? pairTokenAmount: swappedTokenAmount;  
    //     uint totalAmountMerged = splitter.merge(vault, junior_amount); 

    //     //4.Redeem merged token in tVault  
    //     vault.redeem(totalAmountMerged, msg.sender, address(this)); 


    // }

    // /// @notice swap portion of tToken to another to get the correct ratio
    // /// e.x 100 junior-> 30 senior, 70 junior, when ratio is 3:7
    // function swapToRatio(
    //     uint tokenInAmount, 
    //     bool needSenior,
    //     address[] memory tranches,
    //     tVault vault, 
    //     StableSwap amm) internal returns(uint, uint){
    
    //     //get swapping Token index; if senior is needed swap junior
    //     uint tokenInIndex = needSenior? 1:0;
    //     uint tokenOutIndex = 1- tokenInIndex; 
    //     address neededToken = tranches[tokenOutIndex]; 
    //     address swappingToken = tranches[tokenInIndex]; 
    //     uint junior_weight = vault.getJuniorWeight();
    //     uint PRICE_PRECISION = vault.PRICE_PRECISION();   
        
    //     //ex. 100j -> 30j, 70s (determined by ratio)
    //     // need x amount of juniors for 70s 
    //     uint neededTokenOutAmount; 
    //     if (needSenior)  neededTokenOutAmount = (PRICE_PRECISION - junior_weight) * tokenInAmount; 
    //     else  neededTokenOutAmount = junior_weight * tokenInAmount; 

    //     //Get how much tokenInAmount I need to get needed tokenoutAmount 
    //     uint neededTokenInAmount = amm.getDx(neededTokenOutAmount, tokenInIndex); 
    //     uint TokenOutAmount = amm.swap(tokenInIndex, tokenOutIndex, neededTokenInAmount,0 ); 
    //     //Now this contract has the neededTokenAmountOut tokens

    //     return (TokenOutAmount, neededTokenInAmount);
    // }


// library Debt{

//     struct dVaultPosition{
//         // amount of minted dVault 
//         uint256 dVaultAmount; 

//         // amount of tranche token that was used to mint dVault, using this pTv can be inferred
//         uint256 trancheAmount; 
//     }

//     struct DebtData{
//         // d or c stands for debt Or credit 
//         uint256 juniorDorc; 
//         uint256 seniorDorc; 
//     }

//     function add(
//         mapping(bytes32=> uint256) storage self, 
//         uint256 vaultId, 
//         address creator,
//         bool isSenior, 
//         uint256 pjs, 
//         uint256 dVaultAmount
//         ) internal{
//         self[keccak256(abi.encodePacked(vaultId, creator,isSenior, pjs))] = dVaultAmount; 
//     }

//     function get(
//         mapping(bytes32=> uint256) storage self, 
//         uint256 vaultId, 
//         address creator, 
//         bool isSenior, 
//         uint256 pjs
//         ) internal view returns(uint256){
//         return self[keccak256(abi.encodePacked(vaultId, creator, isSenior, pjs))]; 
//     }
// }
// library Queues{

//    function addDelta(uint128 x, int128 y) internal pure returns (uint128 z) {
//         if (y < 0) {
//             require((z = x - uint128(-y)) < x, 'LS');
//         } else {
//             require((z = x + uint128(y)) >= x, 'LA');
//         }
//     }

//     // Data for single queue slot 
//     struct QueueSlot{
//         uint128 startQueueAmount; 
//         uint128 remainingQueueAmount;
//     }

//     // Manages an array of queueSlots
//     struct Queue{
//         uint128 first; 
//         uint128 last; 
//     }

//     function enqueue(
//         mapping(uint128 => Queues.QueueSlot) storage self, 
//         Queue storage queue, 
//         QueueSlot memory data) public {
//         queue.last += 1;

//         self[queue.last] = data;
//     }

//     function dequeue(
//         mapping(uint128 => Queues.QueueSlot) storage self,
//         Queue storage queue
//         ) public {
//         Queue memory _queue = queue; 
//         assert(_queue.last >= _queue.first + 1);  // non-empty queue
//         delete self[_queue.first];
//         queue.first += 1;
//     }

//     /// @notice gets address indexed queueslot
//     function get(
//         mapping(bytes32=> Queues.QueueSlot) storage self, 
//         address maker, 
//         bool isSenior 
//         ) internal returns(QueueSlot storage){
//         return self[keccak256(abi.encodePacked(maker, isSenior))]; 
//     }

//     function update(
//         QueueSlot storage self,
//         int128 amount) internal {
//         self.remainingQueueAmount = addDelta(self.remainingQueueAmount, amount); 
//     }

//     function len(Queue storage self) internal view returns(uint256){
//         Queue memory _queue = self; 
//         assert(_queue.last >= _queue.first + 1);  // non-empty queue
//         unchecked { return uint256(_queue.last- (_queue.first + 1)); }
//     }



//    using Queues for mapping(bytes32=> Queues.QueueSlot); 
//     using Queues for mapping(uint128 => Queues.QueueSlot); 
//     using Queues for Queues.Queue; 
//     using Queues for Queues.QueueSlot; 

//     struct QueueData{
//         mapping(bytes32=> Queues.QueueSlot) positions; //queueslots indexed by address
//         mapping(uint128 => Queues.QueueSlot) map;// queueslots indexed by numbers
//         Queues.Queue indexData; 
//     }

//     mapping(uint256=> QueueData) public JuniorQueue; //per vault
//     mapping(uint256=> QueueData) public SeniorQueue; //per vault
//     uint256 constant MAXSIZE = 100; 

//     /// @notice create queue bids to be filled 
//     function addNewQueue(
//         uint256 vaultId, 
//         bool isSenior, 
//         uint256 amount
//         ) external {
//         QueueData storage data = isSenior? SeniorQueue[vaultId] : JuniorQueue[vaultId]; 

//         Queues.QueueSlot storage queueSlot 
//                 = data.positions.get(msg.sender, isSenior); 

//         queueSlot.remainingQueueAmount = uint128(amount); //TODO safecast 
//         queueSlot.startQueueAmount = uint128(amount); 

//         // Push new slot to front 
//         data.map.enqueue(queueSlot, data.indexData); 
        
//         // Get rid of oldest slot  
//         if(data.indexData.last >= MAXSIZE) 
//             data.map.dequeue(data.indexData); 

//         // Escrow funds 
//         Splitter splitter = tFactory.getContracts(vaultId).splitter; 
//         if(isSenior) ERC20(splitter.getTrancheTokens()[0]).transferFrom(msg.sender,address(this), amount); 
//         else ERC20(splitter.getTrancheTokens()[1]).transferFrom(msg.sender,address(this), amount);
//     }

//     struct Fillvars{
//         uint256 len; 
//         uint256 junior_weight; 
//         uint256 multiplier; 
//         uint256 amountRemaining; 
//         uint256 filled;

//         uint256 pTv; //price of tranche/vault
//         uint256 pju;
//         uint256 psu; 
//         uint256 pjs;  

//         address senior;
//         address junior; 

//         uint128 i; 

//         uint256 totalRedeemed; 
//         uint256 fillerShare;
//         uint256 filleeShare; 
//         uint256 arbitrageProfit
//     }

//     /// @notice fill queues and do arb
//     /// ifSenior, the queuelist is junior, and the filler is senior specified in amouunt 
//     function fillQueue(
//         uint256 vaultId, 
//         bool isSenior, 
//         uint256 amount,
//         uint256 markPrice
//         ) external {
//         QueueData storage data = isSenior? JuniorQueue[vaultId] : SeniorQueue[vaultId]; 
//         Fillvars memory vars; 
//         Splitter splitter = tFactory.getContracts(vaultId).splitter; 

//         vars.junior_weight = splitter.junior_weight();
//         vars.len = data.indexData.len();
//         vars.i = data.indexData.first; 
//         vars.amountRemaining = amount; 
//         vars.multiplier = isSenior ? junior_weight.divWadDown(precision - junior_weight)
//                                   : (precision - junior_weight).divWadDown(junior_weight);
        
//         while (vars.amountRemaining != 0 || vars.i < vars.len){

//             vars.amountRemaining -= fillQueueSlot(data.map[vars.i],
//                  vars.amountRemaining.mulWadDown(vars.multiplier));
//             vars.i++;
//         }

//         // amount of isSenior filled 
//         vars.filled = amount - vars.amountRemaining; 

//         (vars.senior, vars.junior) = splitter.getTrancheTokens();

//         // Merge, this will spit back vault here 
//         if(isSenior) {
//             uint256 junior_amount = vars.filled.mulWadDown(vars.multiplier); 
//             ERC20(vars.senior).approve(address(splitter), vars.filled); 
//             ERC20(vars.junior).approve(address(splitter), junior_amount); 
//             splitter.merge(junior_amount);
//         }

//         // convert senior amount to junior amount
//         else {
//             ERC20(vars.junior).approve(address(splitter), vars.filled); 
//             ERC20(vars.senior).approve(address(splitter), vars.filled.mulWadDown(vars.multiplier)); 
//             splitter.merge(vars.filled); 
//         }

//         // get pjv(and psv), the exchange rate of junior/vault which is pju/pvu 
//         (vars.pju, vars.psu, vars.pjs) = splitter.computeValuePrices();
//         vars.pvu  = splitter.underlying().queryExchangeRateOracle(); 
//         vars.pTv = isSenior? vars.psu.divWadDown(vars.pvu) : vars.pju.divWadDown(vars.pvu);

//         // isSenior, 106 seniors are filling a queue of 45 juniors 
//         vars.totalRedeemed = vars.filled + vars.filled.mulWadDown(vars.multiplier); 
//         vars.fillerShare = vars.pTv.mulWadDown(vars.filled); // 1 senior/junior is worth pTv of vault  
//         vars.filleeShare = totalRedeemed - fillerShare; 

//         // get arbitrage profit for filler, from markPrice vs Pjs
//             {
//                 uint256 tranchePurchased = vars.filled.divWadDown(precision 
//                     + vars.multiplier.mulWadDown(markPrice));
//                 uint256 trancheFromValue = tranchePurchased.mulWadDown(
//                     precision + vars.multiplier.mulWadDown(vars.pTv)); 

//                 // Arbitrage profit denominated in trancheToken  
//                 vars.arbitrageProfit = vars.filled - trancheFromValue; 
//             } 

//         // return to filler/fillee his share of vault 
//         vars.fillerShare -= vars.arbitrageProfit.mulWadDown(precision - _getFillerShare(vaultId)); 
//         vars.filleeShare += vars.arbitrageProfit.mulWadDown(precision - _getFillerShare(vaultId)); 

//     }

//     /// @notice fill single queue, so amount stored in queue should decrease by param amount
//     function fillQueueSlot(
//         Queues.QueueSlot storage queue, 
//         uint256 amount
//         ) internal returns(uint256 filledAmount){
//         if (queue.queueAmount >= amount) {
//             queue.update(-int128(amount)); 
//             filledAmount = amount; 
//         }   
//         else {
//             queue.update(-int128(queue.queueAmount)); 
//             removeQueue(queue); 
//             filledAmount = queue.queueAmount; 
//         } 
//     }

//     function removeQueue(Queues.QueueSlot memory queue ) external{
//         delete queueSlots[queue.idx]; 
//     }

//     function modifyQueue() external{}

//     function setFillerShare(uint256 vaultId, uint256 newFillerShare) external {
//         fillerShareDelta[vaultId] = newFillerShare; 
//     }
//     function setDefaultFillerShare(uint256 newDefaultFillerShare) external{
//         defaultFillerShare = newDefaultFillerShare; 
//     }
//     function _getFillerShare(uint256 vaultId) internal {
//         defaultFillerShare + fillerShareDelta[vaultId]; 
//     }


//     mapping(uint256=>uint256) public fillerShareDelta; 
//     uint256 defaultFillerShare; 


// }
    // mapping(uint256=> mapping(bytes32=> Queues.QueueSlot)) public QueuePositions; //vaultId=> address indexed queueslot
    // mapping(uint256=> mapping(uint128 => Queues.QueueSlot)) public QueueMap; //vaultId=> queue
    // mapping(uint256=> Queues.Queue) public Queue; 

