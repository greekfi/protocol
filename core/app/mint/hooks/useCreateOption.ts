import { useCallback, useEffect, useState } from "react";
import type { TransactionStep } from "./types";
import { useContracts } from "./useContracts";
import { useQueryClient } from "@tanstack/react-query";
import { Address } from "viem";
import { useWaitForTransactionReceipt } from "wagmi";
import { useWriteFactoryCreateOptions } from "~~/generated";

type CreateOptionStep = Extract<TransactionStep, "idle" | "executing" | "waiting-execution" | "success" | "error">;

/** Parameters for creating a single option */
export interface CreateOptionParams {
  collateral: Address;
  consideration: Address;
  expiration: number; // Unix timestamp in seconds
  strike: bigint; // 18 decimal encoding
  isPut: boolean;
  isEuro?: boolean;
  windowSeconds?: number;
}

interface UseCreateOptionReturn {
  createOptions: (params: CreateOptionParams[]) => Promise<void>;
  step: CreateOptionStep;
  /** True only while the wallet is being prompted (pre-broadcast). */
  isPending: boolean;
  /** True after broadcast, while waiting for the receipt. */
  isConfirming: boolean;
  isSuccess: boolean;
  error: Error | null;
  txHash: `0x${string}` | null;
  reset: () => void;
}

/**
 * Hook to create new option pairs via the Factory.
 * No approval is needed for creating options — the factory just deploys clones.
 */
export function useCreateOption(): UseCreateOptionReturn {
  const [step, setStep] = useState<CreateOptionStep>("idle");
  const [error, setError] = useState<Error | null>(null);
  const [txHash, setTxHash] = useState<`0x${string}` | null>(null);

  const factoryAddress = useContracts()?.Factory?.address as Address | undefined;
  const queryClient = useQueryClient();

  const batchWrite = useWriteFactoryCreateOptions();

  const {
    isSuccess: txConfirmed,
    isError: txFailed,
    error: txError,
  } = useWaitForTransactionReceipt({
    hash: txHash ?? undefined,
    query: { enabled: Boolean(txHash) },
  });

  useEffect(() => {
    if (txConfirmed && step === "waiting-execution") {
      queryClient.invalidateQueries({ queryKey: ["optionCreatedEvents"] });
    }
  }, [txConfirmed, step, queryClient]);

  const createOptions = useCallback(
    async (params: CreateOptionParams[]) => {
      if (!factoryAddress) {
        setError(new Error("Factory contract not available"));
        setStep("error");
        return;
      }
      if (params.length === 0) {
        setError(new Error("No options to create"));
        setStep("error");
        return;
      }
      try {
        setError(null);
        setStep("executing");

        const now = Math.floor(Date.now() / 1000);
        const optionParams = params.map(p => {
          if (p.strike === 0n) throw new Error("Strike price cannot be 0");
          if (p.expiration < now) {
            throw new Error(`Expiration date ${new Date(p.expiration * 1000).toISOString()} is in the past`);
          }
          return {
            collateral: p.collateral,
            consideration: p.consideration,
            expirationDate: p.expiration,
            strike: p.strike,
            isPut: p.isPut,
            isEuro: p.isEuro ?? false,
            windowSeconds: p.windowSeconds ?? 0,
          };
        });

        const hash = await batchWrite.writeContractAsync({
          address: factoryAddress,
          args: [optionParams],
        });
        setTxHash(hash);
        setStep("waiting-execution");
      } catch (err) {
        setError(err as Error);
        setStep("error");
      }
    },
    [factoryAddress, batchWrite],
  );

  const reset = useCallback(() => {
    setStep("idle");
    setError(null);
    setTxHash(null);
  }, []);

  const actualStep: CreateOptionStep = (() => {
    if (step === "waiting-execution") {
      if (txConfirmed) return "success";
      if (txFailed) return "error";
      return "waiting-execution";
    }
    return step;
  })();

  const actualError = actualStep === "error" && txError ? txError : error;

  return {
    createOptions,
    step: actualStep,
    // Pending = wallet is being asked to sign. Once broadcast lands and we move to
    // waiting-execution, the UI shouldn't keep blocking — the user is free to
    // navigate away while the receipt confirms.
    isPending: actualStep === "executing",
    isConfirming: actualStep === "waiting-execution",
    isSuccess: actualStep === "success",
    error: actualError,
    txHash,
    reset,
  };
}

export default useCreateOption;
