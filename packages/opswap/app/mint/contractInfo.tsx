// packages/nextjs/app/mint/components/ChainAbis.tsx
import { ReactNode } from "react";
import { useChainId } from "wagmi";
import deployedContracts from "~~/contracts/deployedContracts";

type ChainAbisProps = {
  children: (params: { chainId: number; abis: any }) => ReactNode;
};

export function ChainAbis({ children }: ChainAbisProps) {
  const chainId = useChainId();
  const abis = deployedContracts[chainId as keyof typeof deployedContracts];
  return <>{children({ chainId, abis })}</>;
}
