import { useCallback, useState, useEffect } from "react";
import { Address } from "viem";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { useOptionFactoryContract, useFactoryAddress } from "./useContracts";
import type { TransactionStep } from "./types";

type CreateOptionStep = Extract<TransactionStep, "idle" | "executing" | "waiting-execution" | "success" | "error">;

/** Parameters for creating a single option */
export interface CreateOptionParams {
  collateral: Address;
  consideration: Address;
  expiration: number; // Unix timestamp in seconds
  strike: bigint; // 18 decimal encoding
  isPut: boolean;
}

/** Parameters matching the Solidity OptionParameter struct */
interface OptionParameterStruct {
  collateral_: Address;
  consideration_: Address;
  expiration: bigint;
  strike: bigint;
  isPut: boolean;
}

interface UseCreateOptionReturn {
  /** Create a single option */
  createOption: (params: CreateOptionParams) => Promise<void>;
  /** Create multiple options in one transaction */
  createOptions: (params: CreateOptionParams[]) => Promise<void>;
  /** Current step */
  step: CreateOptionStep;
  /** Whether creation is in progress */
  isLoading: boolean;
  /** Whether creation succeeded */
  isSuccess: boolean;
  /** Error if any */
  error: Error | null;
  /** Transaction hash */
  txHash: `0x${string}` | null;
  /** Reset state */
  reset: () => void;
}

/**
 * Hook to create new option pairs via the OptionFactory
 *
 * No approval is needed for creating options - the factory just deploys contracts.
 * After successful creation, the options list is automatically refetched.
 */
export function useCreateOption(): UseCreateOptionReturn {
  const [step, setStep] = useState<CreateOptionStep>("idle");
  const [error, setError] = useState<Error | null>(null);
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);

  const factoryAddress = useFactoryAddress();
  const factoryContract = useOptionFactoryContract();
  const queryClient = useQueryClient();

  const { writeContractAsync } = useWriteContract();

  // Wait for transaction receipt
  const {
    isSuccess: txConfirmed,
    isError: txFailed,
    error: txError,
  } = useWaitForTransactionReceipt({
    hash: txHash ?? undefined,
    query: {
      enabled: Boolean(txHash),
    },
  });

  // Handle transaction confirmation
  useEffect(() => {
    if (txConfirmed && step === "waiting-execution") {
      console.log("Transaction confirmed! Invalidating queries.");
      // Invalidate options query to refetch the list
      queryClient.invalidateQueries({
        queryKey: ["optionCreatedEvents"],
      });
    }
  }, [txConfirmed, step, queryClient]);

  const createOption = useCallback(
    async (params: CreateOptionParams) => {
      if (!factoryAddress || !factoryContract?.abi) {
        const err = new Error("Factory contract not available");
        setError(err);
        setStep("error");
        return;
      }

      try {
        setError(null);
        setStep("executing");

        const hash = await writeContractAsync({
          address: factoryAddress,
          abi: factoryContract.abi as readonly unknown[],
          functionName: "createOption",
          args: [
            params.collateral,
            params.consideration,
            BigInt(params.expiration),
            params.strike,
            params.isPut,
          ],
        });

        setTxHash(hash);
        setStep("waiting-execution");
      } catch (err) {
        setError(err as Error);
        setStep("error");
      }
    },
    [factoryAddress, factoryContract, writeContractAsync]
  );

  const createOptions = useCallback(
    async (params: CreateOptionParams[]) => {
      if (!factoryAddress || !factoryContract?.abi) {
        const err = new Error("Factory contract not available");
        setError(err);
        setStep("error");
        return;
      }

      if (params.length === 0) {
        const err = new Error("No options to create");
        setError(err);
        setStep("error");
        return;
      }

      try {
        setError(null);
        setStep("executing");

        // Convert to struct format expected by contract
        // Note: Solidity expects uint40 for expiration and uint96 for strike
        const optionParams: OptionParameterStruct[] = params.map((p) => ({
          collateral_: p.collateral,
          consideration_: p.consideration,
          expiration: BigInt(p.expiration),
          strike: p.strike,
          isPut: p.isPut,
        }));

        console.log("Creating options with params:", optionParams);
        console.log("Factory address:", factoryAddress);
        console.log("Number of options:", optionParams.length);

        // Validate params before sending
        for (const param of optionParams) {
          if (param.strike === 0n) {
            throw new Error("Strike price cannot be 0");
          }
          const expirationSeconds = Number(param.expiration);
          if (expirationSeconds < Math.floor(Date.now() / 1000)) {
            throw new Error(`Expiration date ${new Date(expirationSeconds * 1000).toISOString()} is in the past`);
          }
        }

        const hash = await writeContractAsync({
          address: factoryAddress,
          abi: factoryContract.abi as readonly unknown[],
          functionName: "createOptions",
          args: [optionParams],
        });

        console.log("Transaction sent, hash:", hash);
        setTxHash(hash);
        setStep("waiting-execution");
      } catch (err) {
        console.error("Error creating options:", err);
        setError(err as Error);
        setStep("error");
      }
    },
    [factoryAddress, factoryContract, writeContractAsync]
  );

  const reset = useCallback(() => {
    setStep("idle");
    setError(null);
    setTxHash(null);
  }, []);

  // Derive the actual step based on transaction status
  const actualStep: CreateOptionStep = (() => {
    if (step === "waiting-execution") {
      if (txConfirmed) return "success";
      if (txFailed) return "error";
      return "waiting-execution";
    }
    return step;
  })();

  // Derive error from transaction error if in failed state
  const actualError = actualStep === "error" && txError ? txError : error;

  return {
    createOption,
    createOptions,
    step: actualStep,
    isLoading: actualStep === "executing" || actualStep === "waiting-execution",
    isSuccess: actualStep === "success",
    error: actualError,
    txHash,
    reset,
  };
}

export default useCreateOption;
