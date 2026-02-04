import { useCallback, useEffect, useState } from "react";
import type { TransactionStep } from "./types";
import { useContracts } from "./useContracts";
import { useQueryClient } from "@tanstack/react-query";
import { Address } from "viem";
import { useWaitForTransactionReceipt, useWriteContract } from "wagmi";

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

  const contracts = useContracts();
  const factoryAddress = contracts?.OptionFactory?.address;
  const factoryContract = contracts?.OptionFactory;
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
          args: [params.collateral, params.consideration, BigInt(params.expiration), params.strike, params.isPut],
        });

        setTxHash(hash);
        setStep("waiting-execution");
      } catch (err) {
        setError(err as Error);
        setStep("error");
      }
    },
    [factoryAddress, factoryContract, writeContractAsync],
  );

  const createOptions = useCallback(
    async (params: CreateOptionParams[]) => {
      console.log("=== useCreateOption.createOptions START ===");
      console.log("factoryAddress:", factoryAddress);
      console.log("factoryContract available:", !!factoryContract);
      console.log("params received:", params);

      if (!factoryAddress || !factoryContract?.abi) {
        const err = new Error("Factory contract not available");
        console.error("Factory not available:", { factoryAddress, hasAbi: !!factoryContract?.abi });
        setError(err);
        setStep("error");
        return;
      }

      if (params.length === 0) {
        const err = new Error("No options to create");
        console.error("No options to create");
        setError(err);
        setStep("error");
        return;
      }

      try {
        setError(null);
        setStep("executing");

        // Convert to struct format expected by contract
        // Note: Solidity expects uint40 for expiration and uint96 for strike
        const optionParams: OptionParameterStruct[] = params.map(p => ({
          collateral_: p.collateral,
          consideration_: p.consideration,
          expiration: BigInt(p.expiration),
          strike: p.strike,
          isPut: p.isPut,
        }));

        console.log("=== Converted params to struct format ===");
        optionParams.forEach((p, idx) => {
          console.log(`Option ${idx}:`, {
            collateral: p.collateral_,
            consideration: p.consideration_,
            expiration: p.expiration.toString(),
            expirationDate: new Date(Number(p.expiration) * 1000).toISOString(),
            strike: p.strike.toString(),
            strikeHex: "0x" + p.strike.toString(16),
            isPut: p.isPut,
          });
        });

        console.log("Factory address:", factoryAddress);
        console.log("Number of options:", optionParams.length);

        // Validate params before sending
        console.log("=== Validating params ===");
        for (const param of optionParams) {
          if (param.strike === 0n) {
            throw new Error("Strike price cannot be 0");
          }
          const expirationSeconds = Number(param.expiration);
          const now = Math.floor(Date.now() / 1000);
          console.log(`Expiration validation: ${expirationSeconds} vs now ${now}`);
          if (expirationSeconds < now) {
            throw new Error(`Expiration date ${new Date(expirationSeconds * 1000).toISOString()} is in the past`);
          }
        }

        console.log("=== Calling writeContractAsync ===");
        console.log("Contract call details:", {
          address: factoryAddress,
          functionName: "createOptions",
          argsCount: optionParams.length,
        });

        const hash = await writeContractAsync({
          address: factoryAddress,
          abi: factoryContract.abi as readonly unknown[],
          functionName: "createOptions",
          args: [optionParams],
        });

        console.log("=== Transaction sent successfully ===");
        console.log("Transaction hash:", hash);
        setTxHash(hash);
        setStep("waiting-execution");
      } catch (err) {
        console.error("=== Error in createOptions ===");
        console.error("Error type:", typeof err);
        console.error("Error:", err);
        console.error("Error details:", {
          message: (err as any)?.message,
          code: (err as any)?.code,
          data: (err as any)?.data,
          cause: (err as any)?.cause,
          stack: (err as any)?.stack,
        });
        setError(err as Error);
        setStep("error");
      }
    },
    [factoryAddress, factoryContract, writeContractAsync],
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
