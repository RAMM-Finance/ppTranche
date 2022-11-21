# ppTranche
Perpetual Permisionless Tranching

## Contracts
New tranches are deployed via _TrancheFactory_ in _factories.sol_. 
Tranche minters, traders and arbitraguers interact  _TrancheMaster.sol_, which redirects to either _oracleAMM.sol_ 
  or _amm.sol_, which is a path independent, uni-v3 style amm with limit orders, custom curves
  
_Splitter_ will take in an asset and split it into two _tTokens_ instances, _senior_ and _junior_, and will receive 
pricing data from oracles to compute value prices for these tranches denominated in underlying, which will be used by the AMMs. 

_LeverageModule.sol_ allows one to use senior as collateral to borrow junior and swap it back to senior to leverage speculate on 
price of junior/senior(and vice versa). Implemented via the flash mint capabilities of _tTokens_. (A compound lending pool is initiated for 
each tranche pair)


To run written tests, clone repo, install and initiate foundry and run
```
forge test
```

Whitepaper draft found here https://github.com/Debita-Protocol/docs/blob/main/Supertranche.pdf


This project is licensed under the terms of the BSD 3-Clause license and uses a subsection of Compound Protocol codebase. 
