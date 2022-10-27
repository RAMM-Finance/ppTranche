/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { PromiseOrValue } from "../common";
import type { TLens, TLensInterface } from "../TLens";

const _abi = [
  {
    inputs: [],
    name: "fetchContracts",
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
  "0x6080604052348015600f57600080fd5b50607780601d6000396000f3fe6080604052348015600f57600080fd5b506004361060285760003560e01c80633a00ec1c14602d575b600080fd5b602060405190815260200160405180910390f3fea26469706673582212200413653dd2d5bb68d18993334fba8b13857b330fba3cd3ccfe6349c9b7b319fe64736f6c634300080a0033";

type TLensConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: TLensConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class TLens__factory extends ContractFactory {
  constructor(...args: TLensConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<TLens> {
    return super.deploy(overrides || {}) as Promise<TLens>;
  }
  override getDeployTransaction(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  override attach(address: string): TLens {
    return super.attach(address) as TLens;
  }
  override connect(signer: Signer): TLens__factory {
    return super.connect(signer) as TLens__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): TLensInterface {
    return new utils.Interface(_abi) as TLensInterface;
  }
  static connect(address: string, signerOrProvider: Signer | Provider): TLens {
    return new Contract(address, _abi, signerOrProvider) as TLens;
  }
}