# ppTranche
Perpetual Permisionless Tranching

## Contracts
New tranches are deployed via _TrancheFactory_ in _factories.sol_. 
Tranche minters, traders and arbitraguers trade via _TrancheMaster.sol_, which redirects to either _oracleAMM.sol_ 
  or _amm.sol_, which is a path independent, uni-v3 style amm with limit orders, custom curves
  
_Splitter_ will take in an asset and split it into two _tTokens_ instances, _senior_ and _junior_, and will receive 
pricing data from oracles to compute value prices for these tranches denominated in underlying, which will be used by the AMMs. 

To run written tests, clone repo, install and initiate foundry and run
```
forge test
```

