/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import {
  Signer,
  BigNumberish,
  Contract,
  ContractFactory,
  Overrides,
} from "ethers";
import { Provider, TransactionRequest } from "@ethersproject/providers";

import type { Splitter } from "../Splitter";

export class Splitter__factory extends ContractFactory {
  constructor(signer?: Signer) {
    super(_abi, _bytecode, signer);
  }

  deploy(
    _underlying: string,
    _vaultId: BigNumberish,
    _trancheMasterAd: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<Splitter> {
    return super.deploy(
      _underlying,
      _vaultId,
      _trancheMasterAd,
      overrides || {}
    ) as Promise<Splitter>;
  }
  getDeployTransaction(
    _underlying: string,
    _vaultId: BigNumberish,
    _trancheMasterAd: string,
    overrides?: Overrides & { from?: string | Promise<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(
      _underlying,
      _vaultId,
      _trancheMasterAd,
      overrides || {}
    );
  }
  attach(address: string): Splitter {
    return super.attach(address) as Splitter;
  }
  connect(signer: Signer): Splitter__factory {
    return super.connect(signer) as Splitter__factory;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): Splitter {
    return new Contract(address, _abi, signerOrProvider) as Splitter;
  }
}

const _abi = [
  {
    inputs: [
      {
        internalType: "contract tVault",
        name: "_underlying",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_vaultId",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "_trancheMasterAd",
        type: "address",
      },
    ],
    stateMutability: "nonpayable",
    type: "constructor",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "markPjs",
        type: "uint256",
      },
    ],
    name: "computeImpliedPrices",
    outputs: [
      {
        internalType: "uint256",
        name: "psu",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "pju",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "computeValuePrices",
    outputs: [
      {
        internalType: "uint256",
        name: "psu",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "pju",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "pjs",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "computeValuePricesView",
    outputs: [
      {
        internalType: "uint256",
        name: "psu",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "pju",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "pjs",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "elapsedTime",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "escrowedVault",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "time",
        type: "uint256",
      },
    ],
    name: "getSRP",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getStoredValuePrices",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getTrancheTokens",
    outputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "junior",
    outputs: [
      {
        internalType: "contract tToken",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "junior_weight",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "lastRecordTime",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "junior_amount",
        type: "uint256",
      },
    ],
    name: "merge",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "junior_amount",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "senior_amount",
        type: "uint256",
      },
      {
        internalType: "address",
        name: "recipient",
        type: "address",
      },
    ],
    name: "mergeFromMaster",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "pastNBlock",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "precision",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "promised_return",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "senior",
    outputs: [
      {
        internalType: "contract tToken",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "setTokens",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "split",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "storeValuePrices",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "toggleDelayOracle",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "trancheMasterAd",
    outputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "bool",
        name: "isSenior",
        type: "bool",
      },
      {
        internalType: "address",
        name: "who",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "trustedBurn",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "underlying",
    outputs: [
      {
        internalType: "contract tVault",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
];

const _bytecode =
  "0x60c06040523480156200001157600080fd5b50604051620031bc380380620031bc83398101604081905262000034916200024d565b600080546001600160a01b0319166001600160a01b0385169081179091556040805163718fdfd160e11b8152905163e31fbfa2916004808201926020929091908290030181865afa1580156200008e573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190620000b4919062000295565b60035560005460408051631a7e976560e11b815290516001600160a01b03909216916334fd2eca916004808201926020929091908290030181865afa15801562000102573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019062000128919062000295565b600490815560005460408051636bfef7e560e11b815290516001600160a01b039092169263d7fdefca9282820192602092908290030181865afa15801562000174573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906200019a919062000295565b60075560808290526001600160a01b0381811660a081905260005460405163095ea7b360e01b8152600481019290925260001960248301529091169063095ea7b3906044016020604051808303816000875af1158015620001ff573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190620002259190620002af565b50504260065550620002da9050565b6001600160a01b03811681146200024a57600080fd5b50565b6000806000606084860312156200026357600080fd5b8351620002708162000234565b6020850151604086015191945092506200028a8162000234565b809150509250925092565b600060208284031215620002a857600080fd5b5051919050565b600060208284031215620002c257600080fd5b81518015158114620002d357600080fd5b9392505050565b60805160a051612ea362000319600039600081816102a4015281816109c001528181610a5d01528181610b7f0152611381015260005050612ea36000f3fe60806040523480156200001157600080fd5b5060043610620001755760003560e01c80639ea3d19c11620000d3578063dbceb0051162000086578063dbceb00514620002f4578063e4e4a2a3146200030b578063e4ea238e1462000322578063e9c52e58146200032c578063eab77ac91462000353578063f15086e5146200036757600080fd5b80639ea3d19c1462000294578063a5a98b06146200029e578063b9d1f97214620002c6578063c70acd8a14620002d0578063d3b5dc3b14620002da578063d857344614620002ea57600080fd5b80636cd00d5c116200012c5780636cd00d5c14620002075780636f307dc3146200021157806381e9b593146200023e57806386a17ff514620002645780638a206117146200027b5780639a458583146200028557600080fd5b8063026034f3146200017a57806324a47aeb146200019657806327b24c6914620001ad57806351453f9d14620001c45780635235c8bb14620001ce578063559ed33914620001fb575b600080fd5b62000183600a81565b6040519081526020015b60405180910390f35b62000183620001a7366004620016f9565b6200037b565b62000183620001be366004620016f9565b620005fa565b6200018360055481565b620001e5620001df366004620016f9565b6200062a565b604080519283526020830191909152016200018d565b62000205620007d1565b005b6200018360045481565b60005462000225906001600160a01b031681565b6040516001600160a01b0390911681526020016200018d565b6200024862000ad3565b604080519384526020840192909252908201526060016200018d565b62000205620002753660046200173f565b62000b74565b6200018360065481565b600954600a54600b5462000248565b6200020562000c81565b620002257f000000000000000000000000000000000000000000000000000000000000000081565b6200020562000c96565b6200018360035481565b62000183670de0b6b3a764000081565b6200024862000cbf565b620001e562000305366004620016f9565b62001135565b620002056200031c36600462001782565b62001376565b62000183600c5481565b600254600154604080516001600160a01b039384168152929091166020830152016200018d565b60025462000225906001600160a01b031681565b60015462000225906001600160a01b031681565b60035460009081620003a4846200039d848181670de0b6b3a7640000620017d0565b906200155c565b6001546040516370a0823160e01b815233600482015291925082916001600160a01b03909116906370a0823190602401602060405180830381865afa158015620003f2573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190620004189190620017ea565b10156200046c5760405162461bcd60e51b815260206004820152601860248201527f4e6f7420656e6f7567682073656e696f7220746f6b656e73000000000000000060448201526064015b60405180910390fd5b62000478818562001804565b600c60008282546200048b9190620017d0565b9091555050600254604051632770a7eb60e21b81526001600160a01b0390911690639dc29fac90620004c490339088906004016200181f565b600060405180830381600087803b158015620004df57600080fd5b505af1158015620004f4573d6000803e3d6000fd5b5050600154604051632770a7eb60e21b81526001600160a01b039091169250639dc29fac91506200052c90339085906004016200181f565b600060405180830381600087803b1580156200054757600080fd5b505af11580156200055c573d6000803e3d6000fd5b50506000546001600160a01b0316915063a9059cbb90503362000580848862001804565b6040518363ffffffff1660e01b81526004016200059f9291906200181f565b6020604051808303816000875af1158015620005bf573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190620005e5919062001838565b50620005f2818562001804565b949350505050565b60045460009062000624906200061a9084670de0b6b3a76400006200157a565b600754906200155c565b92915050565b600080620007bc620006b7600260009054906101000a90046001600160a01b03166001600160a01b03166318160ddd6040518163ffffffff1660e01b8152600401602060405180830381865afa15801562000689573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190620006af9190620017ea565b85906200155c565b600160009054906101000a90046001600160a01b03166001600160a01b03166318160ddd6040518163ffffffff1660e01b8152600401602060405180830381865afa1580156200070b573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190620007319190620017ea565b6200073d919062001804565b60008054906101000a90046001600160a01b03166001600160a01b03166301e1d1146040518163ffffffff1660e01b8152600401602060405180830381865afa1580156200078f573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190620007b59190620017ea565b9062001646565b9150620007ca82846200155c565b9050915091565b60008054604080516395d89b4160e01b815290516001600160a01b039092169283926395d89b419260048082019392918290030181865afa1580156200081b573d6000803e3d6000fd5b505050506040513d6000823e601f3d908101601f191682016040526200084591908101906200189d565b60405160200162000857919062001956565b604051602081830303815290604052306040516200087590620016eb565b6200088393929190620019b1565b604051809103906000f080158015620008a0573d6000803e3d6000fd5b50600180546001600160a01b0319166001600160a01b0392831617905560008054604080516395d89b4160e01b81529051919093169283926395d89b41926004808401938290030181865afa158015620008fe573d6000803e3d6000fd5b505050506040513d6000823e601f3d908101601f191682016040526200092891908101906200189d565b6040516020016200093a919062001a05565b604051602081830303815290604052306040516200095890620016eb565b620009669392919062001a25565b604051809103906000f08015801562000983573d6000803e3d6000fd5b50600280546001600160a01b0319166001600160a01b0392831617905560015460405163095ea7b360e01b815291169063095ea7b390620009ed907f000000000000000000000000000000000000000000000000000000000000000090600019906004016200181f565b6020604051808303816000875af115801562000a0d573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019062000a33919062001838565b5060025460405163095ea7b360e01b81526001600160a01b039091169063095ea7b39062000a8a907f000000000000000000000000000000000000000000000000000000000000000090600019906004016200181f565b6020604051808303816000875af115801562000aaa573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019062000ad0919062001838565b50565b60008060006006544262000ae89190620017d0565b6005600082825462000afb919062001804565b909155505042600655600080546040805163318b5e1b60e01b815290516001600160a01b039092169263318b5e1b9260048084019382900301818387803b15801562000b4657600080fd5b505af115801562000b5b573d6000803e3d6000fd5b5050505062000b6962000cbf565b925092509250909192565b336001600160a01b037f0000000000000000000000000000000000000000000000000000000000000000161462000bd95760405162461bcd60e51b815260206004820152600860248201526732b73a393ca2a92960c11b604482015260640162000463565b821562000c4d57600154604051632770a7eb60e21b81526001600160a01b0390911690639dc29fac9062000c1490859085906004016200181f565b600060405180830381600087803b15801562000c2f57600080fd5b505af115801562000c44573d6000803e3d6000fd5b50505050505050565b600254604051632770a7eb60e21b81526001600160a01b0390911690639dc29fac9062000c1490859085906004016200181f565b62000c8b62000ad3565b600b55600a55600955565b60085460ff1662000ca957600162000cac565b60005b6008805460ff1916911515919091179055565b60008060008062000cec6200061a600554670de0b6b3a76400006004546200157a9092919063ffffffff16565b6008549091506000908190819060ff1662000e7957600160009054906101000a90046001600160a01b03166001600160a01b03166318160ddd6040518163ffffffff1660e01b8152600401602060405180830381865afa15801562000d55573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019062000d7b9190620017ea565b9150600260009054906101000a90046001600160a01b03166001600160a01b03166318160ddd6040518163ffffffff1660e01b8152600401602060405180830381865afa15801562000dd1573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019062000df79190620017ea565b905060008054906101000a90046001600160a01b03166001600160a01b03166301e1d1146040518163ffffffff1660e01b8152600401602060405180830381865afa15801562000e4b573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019062000e719190620017ea565b925062000f88565b60008054604051634796c54760e01b8152600a600482015282916001600160a01b031690634796c54790602401606060405180830381865afa15801562000ec4573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019062000eea919062001a66565b509150915062000f7360008054906101000a90046001600160a01b03166001600160a01b031663c70acd8a6040518163ffffffff1660e01b8152600401602060405180830381865afa15801562000f45573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019062000f6b9190620017ea565b83906200155c565b925062000f818383620017d0565b9094509250505b60008054906101000a90046001600160a01b03166001600160a01b03166318160ddd6040518163ffffffff1660e01b8152600401602060405180830381865afa15801562000fda573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190620010009190620017ea565b6200100c828462001804565b14620010485760405162461bcd60e51b815260206004820152600a60248201526939bab838363c9022b93960b11b604482015260640162000463565b620010796040518060400160405280600b81526020016a1cdc9c1c1b1d5cdbdb994b60aa1b8152508584846200165d565b620010ae6040518060400160405280600b81526020016a746f74616c41737365747360a81b815250846004546005546200165d565b600082620010c85750600097889750879650945050505050565b620010d485846200155c565b8410620010e457849750620010f7565b620010f0848462001646565b9750600190505b806200111d576200111a826200110e87866200155c565b620007b59087620017d0565b96505b62001129878962001646565b95505050505050909192565b600080546040516370a0823160e01b8152336004820152829184916001600160a01b03909116906370a0823190602401602060405180830381865afa15801562001183573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190620011a99190620017ea565b1015620011df5760405162461bcd60e51b815260206004820152600360248201526218985b60ea1b604482015260640162000463565b6000546040516323b872dd60e01b8152336004820152306024820152604481018590526001600160a01b03909116906323b872dd906064016020604051808303816000875af115801562001237573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906200125d919062001838565b5082600c600082825462001272919062001804565b90915550506003546000906200128a9085906200155c565b905060006200129a8286620017d0565b6002546040516340c10f1960e01b81529192506001600160a01b0316906340c10f1990620012cf90339086906004016200181f565b600060405180830381600087803b158015620012ea57600080fd5b505af1158015620012ff573d6000803e3d6000fd5b50506001546040516340c10f1960e01b81526001600160a01b0390911692506340c10f1991506200133790339085906004016200181f565b600060405180830381600087803b1580156200135257600080fd5b505af115801562001367573d6000803e3d6000fd5b50939792965091945050505050565b336001600160a01b037f00000000000000000000000000000000000000000000000000000000000000001614620013dd5760405162461bcd60e51b815260206004820152600a6024820152693737ba1036b0b9ba32b960b11b604482015260640162000463565b620013e9828462001804565b600c6000828254620013fc9190620017d0565b9091555050600254604051632770a7eb60e21b81526001600160a01b0390911690639dc29fac906200143590849087906004016200181f565b600060405180830381600087803b1580156200145057600080fd5b505af115801562001465573d6000803e3d6000fd5b5050600154604051632770a7eb60e21b81526001600160a01b039091169250639dc29fac91506200149d90849086906004016200181f565b600060405180830381600087803b158015620014b857600080fd5b505af1158015620014cd573d6000803e3d6000fd5b50506000546001600160a01b0316915063a9059cbb905082620014f1858762001804565b6040518363ffffffff1660e01b8152600401620015109291906200181f565b6020604051808303816000875af115801562001530573d6000803e3d6000fd5b505050506040513d601f19601f8201168201806040525081019062001556919062001838565b50505050565b6000620015738383670de0b6b3a7640000620016aa565b9392505050565b6000838015620016265760018416801562001598578592506200159c565b8392505b508260011c8460011c94505b84156200161f578560801c15620015be57600080fd5b85860281810181811015620015d257600080fd5b859004965050600185161562001613578583028387820414620015fb578615620015fb57600080fd5b818101818110156200160c57600080fd5b8590049350505b8460011c9450620015a8565b506200163e565b8380156200163857600092506200163c565b8392505b505b509392505050565b60006200157383670de0b6b3a764000084620016aa565b62001556848484846040516024016200167a949392919062001a95565b60408051601f198184030181529190526020810180516001600160e01b03166304772b3360e11b179052620016ca565b828202811515841585830485141716620016c357600080fd5b0492915050565b80516a636f6e736f6c652e6c6f67602083016000808483855afa5050505050565b6113a78062001ac783390190565b6000602082840312156200170c57600080fd5b5035919050565b801515811462000ad057600080fd5b80356001600160a01b03811681146200173a57600080fd5b919050565b6000806000606084860312156200175557600080fd5b8335620017628162001713565b9250620017726020850162001722565b9150604084013590509250925092565b6000806000606084860312156200179857600080fd5b8335925060208401359150620017b16040850162001722565b90509250925092565b634e487b7160e01b600052601160045260246000fd5b600082821015620017e557620017e5620017ba565b500390565b600060208284031215620017fd57600080fd5b5051919050565b600082198211156200181a576200181a620017ba565b500190565b6001600160a01b03929092168252602082015260400190565b6000602082840312156200184b57600080fd5b8151620015738162001713565b634e487b7160e01b600052604160045260246000fd5b60005b838110156200188b57818101518382015260200162001871565b83811115620015565750506000910152565b600060208284031215620018b057600080fd5b815167ffffffffffffffff80821115620018c957600080fd5b818401915084601f830112620018de57600080fd5b815181811115620018f357620018f362001858565b604051601f8201601f19908116603f011681019083821181831017156200191e576200191e62001858565b816040528281528760208487010111156200193857600080fd5b6200194b8360208301602088016200186e565b979650505050505050565b6273655f60e81b815260008251620019768160038501602087016200186e565b9190910160030192915050565b600081518084526200199d8160208601602086016200186e565b601f01601f19169290920160200192915050565b600060018060a01b03808616835260806020840152600660808401526539b2b734b7b960d11b60a084015260c06040840152620019f260c084018662001983565b9150808416606084015250949350505050565b626a755f60e81b815260008251620019768160038501602087016200186e565b600060018060a01b038086168352608060208401526006608084015265353ab734b7b960d11b60a084015260c06040840152620019f260c084018662001983565b60008060006060848603121562001a7c57600080fd5b8351925060208401519150604084015190509250925092565b60808152600062001aaa608083018762001983565b602083019590955250604081019290925260609091015291905056fe60e06040523480156200001157600080fd5b50604051620013a7380380620013a7833981016040819052620000349162000343565b8282856001600160a01b031663313ce5676040518163ffffffff1660e01b8152600401602060405180830381865afa15801562000075573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906200009b9190620003d7565b8251620000b0906000906020860190620001b7565b508151620000c6906001906020850190620001b7565b5060ff81166080524660a052620000dc6200011b565b60c0525050600780546001600160a01b039687166001600160a01b031991821617909155600680549390961692169190911790935550620004e4915050565b60007f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f60006040516200014f919062000440565b6040805191829003822060208301939093528101919091527fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc660608201524660808201523060a082015260c00160405160208183030381529060405280519060200120905090565b828054620001c59062000403565b90600052602060002090601f016020900481019282620001e9576000855562000234565b82601f106200020457805160ff191683800117855562000234565b8280016001018555821562000234579182015b828111156200023457825182559160200191906001019062000217565b506200024292915062000246565b5090565b5b8082111562000242576000815560010162000247565b6001600160a01b03811681146200027357600080fd5b50565b634e487b7160e01b600052604160045260246000fd5b600082601f8301126200029e57600080fd5b81516001600160401b0380821115620002bb57620002bb62000276565b604051601f8301601f19908116603f01168101908282118183101715620002e657620002e662000276565b816040528381526020925086838588010111156200030357600080fd5b600091505b8382101562000327578582018301518183018401529082019062000308565b83821115620003395760008385830101525b9695505050505050565b600080600080608085870312156200035a57600080fd5b845162000367816200025d565b60208601519094506001600160401b03808211156200038557600080fd5b62000393888389016200028c565b94506040870151915080821115620003aa57600080fd5b50620003b9878288016200028c565b9250506060850151620003cc816200025d565b939692955090935050565b600060208284031215620003ea57600080fd5b815160ff81168114620003fc57600080fd5b9392505050565b600181811c908216806200041857607f821691505b602082108114156200043a57634e487b7160e01b600052602260045260246000fd5b50919050565b600080835481600182811c9150808316806200045d57607f831692505b60208084108214156200047e57634e487b7160e01b86526022600452602486fd5b818015620004955760018114620004a757620004d6565b60ff19861689528489019650620004d6565b60008a81526020902060005b86811015620004ce5781548b820152908501908301620004b3565b505084890196505b509498975050505050505050565b60805160a05160c051610e9362000514600039600061048d015260006104580152600061016a0152610e936000f3fe608060405234801561001057600080fd5b50600436106100f55760003560e01c806340c10f19116100975780639dc29fac116100665780639dc29fac14610216578063a9059cbb14610229578063d505accf1461023c578063dd62ed3e1461024f57600080fd5b806340c10f19146101b957806370a08231146101ce5780637ecebe00146101ee57806395d89b411461020e57600080fd5b806323b872dd116100d357806323b872dd14610152578063313ce567146101655780633644e5151461019e5780633b9d401e146101a657600080fd5b806306fdde03146100fa578063095ea7b31461011857806318160ddd1461013b575b600080fd5b61010261027a565b60405161010f9190610a5f565b60405180910390f35b61012b610126366004610acc565b610308565b604051901515815260200161010f565b61014460025481565b60405190815260200161010f565b61012b610160366004610af8565b610374565b61018c7f000000000000000000000000000000000000000000000000000000000000000081565b60405160ff909116815260200161010f565b610144610454565b61012b6101b4366004610b39565b6104af565b6101cc6101c7366004610acc565b6105ae565b005b6101446101dc366004610bd8565b60036020526000908152604090205481565b6101446101fc366004610bd8565b60056020526000908152604090205481565b610102610602565b6101cc610224366004610acc565b61060f565b61012b610237366004610acc565b61065f565b6101cc61024a366004610bfc565b6106c5565b61014461025d366004610c73565b600460209081526000928352604080842090915290825290205481565b6000805461028790610cac565b80601f01602080910402602001604051908101604052809291908181526020018280546102b390610cac565b80156103005780601f106102d557610100808354040283529160200191610300565b820191906000526020600020905b8154815290600101906020018083116102e357829003601f168201915b505050505081565b3360008181526004602090815260408083206001600160a01b038716808552925280832085905551919290917f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925906103639086815260200190565b60405180910390a350600192915050565b6001600160a01b038316600090815260046020908152604080832033845290915281205460001981146103d0576103ab8382610cfd565b6001600160a01b03861660009081526004602090815260408083203384529091529020555b6001600160a01b038516600090815260036020526040812080548592906103f8908490610cfd565b90915550506001600160a01b0380851660008181526003602052604090819020805487019055519091871690600080516020610e3e833981519152906104419087815260200190565b60405180910390a3506001949350505050565b60007f0000000000000000000000000000000000000000000000000000000000000000461461048a57610485610909565b905090565b507f000000000000000000000000000000000000000000000000000000000000000090565b60006104bb86856109a3565b6040516323e30c8b60e01b81527f439148f0bbc682ca079e46d6e2c2f0c1e3b820f1a291b069d8882abf8cf18dd9906001600160a01b038816906323e30c8b9061051490339030908a906000908b908b90600401610d14565b6020604051808303816000875af1158015610533573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906105579190610d70565b1461059b5760405162461bcd60e51b815260206004820152600f60248201526e18d85b1b189858dac819985a5b1959608a1b60448201526064015b60405180910390fd5b6105a586856109fd565b95945050505050565b6006546001600160a01b031633146105f45760405162461bcd60e51b815260206004820152600960248201526810a9b83634ba3a32b960b91b6044820152606401610592565b6105fe82826109a3565b5050565b6001805461028790610cac565b6006546001600160a01b031633146106555760405162461bcd60e51b815260206004820152600960248201526810a9b83634ba3a32b960b91b6044820152606401610592565b6105fe82826109fd565b33600090815260036020526040812080548391908390610680908490610cfd565b90915550506001600160a01b03831660008181526003602052604090819020805485019055513390600080516020610e3e833981519152906103639086815260200190565b428410156107155760405162461bcd60e51b815260206004820152601760248201527f5045524d49545f444541444c494e455f455850495245440000000000000000006044820152606401610592565b60006001610721610454565b6001600160a01b038a811660008181526005602090815260409182902080546001810190915582517f6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c98184015280840194909452938d166060840152608083018c905260a083019390935260c08083018b90528151808403909101815260e08301909152805192019190912061190160f01b6101008301526101028201929092526101228101919091526101420160408051601f198184030181528282528051602091820120600084529083018083525260ff871690820152606081018590526080810184905260a0016020604051602081039080840390855afa15801561082d573d6000803e3d6000fd5b5050604051601f1901519150506001600160a01b038116158015906108635750876001600160a01b0316816001600160a01b0316145b6108a05760405162461bcd60e51b815260206004820152600e60248201526d24a72b20a624a22fa9a4a3a722a960911b6044820152606401610592565b6001600160a01b0390811660009081526004602090815260408083208a8516808552908352928190208990555188815291928a16917f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925910160405180910390a350505050505050565b60007f8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f600060405161093b9190610d89565b6040805191829003822060208301939093528101919091527fc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc660608201524660808201523060a082015260c00160405160208183030381529060405280519060200120905090565b80600260008282546109b59190610e25565b90915550506001600160a01b038216600081815260036020908152604080832080548601905551848152600080516020610e3e83398151915291015b60405180910390a35050565b6001600160a01b03821660009081526003602052604081208054839290610a25908490610cfd565b90915550506002805482900390556040518181526000906001600160a01b03841690600080516020610e3e833981519152906020016109f1565b600060208083528351808285015260005b81811015610a8c57858101830151858201604001528201610a70565b81811115610a9e576000604083870101525b50601f01601f1916929092016040019392505050565b6001600160a01b0381168114610ac957600080fd5b50565b60008060408385031215610adf57600080fd5b8235610aea81610ab4565b946020939093013593505050565b600080600060608486031215610b0d57600080fd5b8335610b1881610ab4565b92506020840135610b2881610ab4565b929592945050506040919091013590565b600080600080600060808688031215610b5157600080fd5b8535610b5c81610ab4565b94506020860135610b6c81610ab4565b935060408601359250606086013567ffffffffffffffff80821115610b9057600080fd5b818801915088601f830112610ba457600080fd5b813581811115610bb357600080fd5b896020828501011115610bc557600080fd5b9699959850939650602001949392505050565b600060208284031215610bea57600080fd5b8135610bf581610ab4565b9392505050565b600080600080600080600060e0888a031215610c1757600080fd5b8735610c2281610ab4565b96506020880135610c3281610ab4565b95506040880135945060608801359350608088013560ff81168114610c5657600080fd5b9699959850939692959460a0840135945060c09093013592915050565b60008060408385031215610c8657600080fd5b8235610c9181610ab4565b91506020830135610ca181610ab4565b809150509250929050565b600181811c90821680610cc057607f821691505b60208210811415610ce157634e487b7160e01b600052602260045260246000fd5b50919050565b634e487b7160e01b600052601160045260246000fd5b600082821015610d0f57610d0f610ce7565b500390565b6001600160a01b03878116825286166020820152604081018590526060810184905260a06080820181905281018290526000828460c0840137600060c0848401015260c0601f19601f8501168301019050979650505050505050565b600060208284031215610d8257600080fd5b5051919050565b600080835481600182811c915080831680610da557607f831692505b6020808410821415610dc557634e487b7160e01b86526022600452602486fd5b818015610dd95760018114610dea57610e17565b60ff19861689528489019650610e17565b60008a81526020902060005b86811015610e0f5781548b820152908501908301610df6565b505084890196505b509498975050505050505050565b60008219821115610e3857610e38610ce7565b50019056feddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3efa2646970667358221220df35d90c3a6b54624142b30da2e81d2fe7a6b3af46b2d30b3274fd5bcfbaf17364736f6c634300080a0033a2646970667358221220c00d36a618ce720c85c8e4dd37e9291ce0a340ec2e4e476e13f786388f278cfb64736f6c634300080a0033";