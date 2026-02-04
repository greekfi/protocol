import { Address } from "viem";

// ============ Token Types ============

export interface TokenData {
  address_: Address; // Note: Solidity uses address_ (with underscore)
  name: string;
  symbol: string;
  decimals: number;
}

// ============ Option Types ============

export interface OptionInfo {
  option: Address;
  redemption: Address;
  collateral: TokenData;
  consideration: TokenData;
  expiration: bigint;
  strike: bigint;
  isPut: boolean;
}

export interface Balances {
  collateral: bigint;
  consideration: bigint;
  option: bigint;
  redemption: bigint;
}

export interface OptionDetails extends OptionInfo {
  isExpired: boolean;
  balances: Balances | null;
  formattedName: string;
}

export interface OptionListItem {
  address: Address;
  name: string;
  collateral: Address;
  consideration: Address;
  expiration: bigint;
  strike: bigint;
  isPut: boolean;
}

// ============ Allowance Types ============

export interface AllowanceState {
  /** Standard ERC20 allowance: token.allowance(user, factory) */
  erc20Allowance: bigint;
  /** Factory internal allowance: factory.allowance(token, user) */
  factoryAllowance: bigint;
  /** Whether ERC20 approval is needed */
  needsErc20Approval: boolean;
  /** Whether factory approval is needed */
  needsFactoryApproval: boolean;
  /** Whether both approvals are satisfied */
  isFullyApproved: boolean;
}

// ============ Transaction Types ============

export type TransactionStep =
  | "idle"
  | "checking-allowance"
  | "approving-erc20"
  | "waiting-erc20"
  | "approving-factory"
  | "waiting-factory"
  | "executing"
  | "waiting-execution"
  | "success"
  | "error";

export interface TransactionFlowState {
  step: TransactionStep;
  error: Error | null;
  txHash: `0x${string}` | null;
  isLoading: boolean;
  isSuccess: boolean;
  isError: boolean;
}

// ============ Create Option Types ============

export interface CreateOptionParams {
  collateral: Address;
  consideration: Address;
  expiration: number; // Unix timestamp
  strike: bigint;
  isPut: boolean;
}

export interface CreateOptionsParams {
  collateral: Address;
  consideration: Address;
  expirations: number[]; // Unix timestamps
  strikes: bigint[];
  isPut: boolean;
}
