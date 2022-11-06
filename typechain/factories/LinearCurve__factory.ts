/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Signer, Contract, ContractFactory, Overrides } from "ethers";
import { Provider, TransactionRequest } from "@ethersproject/providers";

import type { LinearCurve } from "../LinearCurve";

export class LinearCurve__factory extends ContractFactory {
  constructor(signer?: Signer) {
    super(_abi, _bytecode, signer);
  }

  deploy(
    overrides?: Overrides & { from?: string | Promise<string> }
  ): Promise<LinearCurve> {
    return super.deploy(overrides || {}) as Promise<LinearCurve>;
  }
  getDeployTransaction(
    overrides?: Overrides & { from?: string | Promise<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  attach(address: string): LinearCurve {
    return super.attach(address) as LinearCurve;
  }
  connect(signer: Signer): LinearCurve__factory {
    return super.connect(signer) as LinearCurve__factory;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): LinearCurve {
    return new Contract(address, _abi, signerOrProvider) as LinearCurve;
  }
}

const _abi = [
  {
    inputs: [],
    name: "PRECISION",
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
];

const _bytecode =
  "0x608e610038600b82828239805160001a607314602b57634e487b7160e01b600052600060045260246000fd5b30600052607381538281f3fe730000000000000000000000000000000000000000301460806040526004361060335760003560e01c8063aaf5eb68146038575b600080fd5b6046670de0b6b3a764000081565b60405190815260200160405180910390f3fea26469706673582212209ab5947626171edd95f060d1b57f0d511daeae5d036e600187444e3c2108579f64736f6c634300080a0033";