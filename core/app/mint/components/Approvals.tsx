"use client";

import { useEffect, useState } from "react";
import { MAX_UINT256 } from "../hooks/constants";
import { useApproveERC20 } from "../hooks/transactions/useApproveERC20";
import { useAllowances } from "../hooks/useAllowances";
import { useContracts } from "../hooks/useContracts";
import { useOption } from "../hooks/useOption";
import { useTokenMap } from "../hooks/useTokenMap";
import { Address, isAddress } from "viem";
import { useAccount, useWaitForTransactionReceipt } from "wagmi";
import {
  useReadFactoryApprovedOperator,
  useReadFactoryAutoMintRedeem,
  useWriteFactoryApprove,
  useWriteFactoryApproveOperator,
  useWriteFactoryEnableAutoMintRedeem,
} from "~~/generated";

interface ApprovalsProps {
  optionAddress: Address | undefined;
}

type RowStatus = "approved" | "pending" | "working" | "unavailable";

/** Presets for the operator dropdown. Source: foundry/test/YieldVault.t.sol. */
const KNOWN_OPERATORS: { label: string; address: Address }[] = [
  { label: "Bebop Blend", address: "0xbbbbbBB520d69a9775E85b458C58c648259FAD5F" },
  { label: "Bebop JAM Settlement", address: "0xbeb0b0623f66bE8cE162EbDfA2ec543A522F4ea6" },
];

export function Approvals({ optionAddress }: ApprovalsProps) {
  const { address: userAddress } = useAccount();
  const factoryAddress = useContracts()?.Factory?.address as Address | undefined;
  const { data: option } = useOption(optionAddress);
  const { allTokensMap } = useTokenMap();
  const tokenOptions = Object.values(allTokensMap);

  // Two independent token slots for the two Factory Allowance rows.
  // Default to the selected option's collateral/consideration once available.
  const [token1, setToken1] = useState<Address | undefined>(undefined);
  const [token2, setToken2] = useState<Address | undefined>(undefined);

  useEffect(() => {
    // Normalize to lowercase so the <select>'s string-equality value match works
    // regardless of the checksum casing used by the token list vs. the contract.
    if (option?.collateral.address_ && !token1) {
      setToken1(option.collateral.address_.toLowerCase() as Address);
    }
    if (option?.consideration.address_ && !token2) {
      setToken2(option.consideration.address_.toLowerCase() as Address);
    }
  }, [option?.collateral.address_, option?.consideration.address_, token1, token2]);

  const { data: autoMintRedeem, refetch: refetchAutoMint } = useReadFactoryAutoMintRedeem({
    address: factoryAddress,
    args: userAddress ? [userAddress] : undefined,
    query: { enabled: Boolean(factoryAddress && userAddress) },
  });

  const [operator, setOperatorInput] = useState("");
  const operatorValid = isAddress(operator);
  const { data: isOperatorApproved, refetch: refetchOperator } = useReadFactoryApprovedOperator({
    address: factoryAddress,
    args: userAddress && operatorValid ? [userAddress, operator as Address] : undefined,
    query: { enabled: Boolean(factoryAddress && userAddress && operatorValid) },
  });

  const erc20 = useApproveERC20();
  const { writeContractAsync: factoryApprove } = useWriteFactoryApprove();
  const { writeContractAsync: setAutoMint } = useWriteFactoryEnableAutoMintRedeem();
  const { writeContractAsync: approveOperator } = useWriteFactoryApproveOperator();

  const [working, setWorking] = useState<string | null>(null);
  const [pendingHash, setPendingHash] = useState<`0x${string}` | null>(null);
  const { isSuccess: txConfirmed } = useWaitForTransactionReceipt({
    hash: pendingHash ?? undefined,
    query: { enabled: Boolean(pendingHash) },
  });

  const allow1 = useAllowances(token1, MAX_UINT256);
  const allow2 = useAllowances(token2, MAX_UINT256);

  if (pendingHash && txConfirmed) {
    setPendingHash(null);
    setWorking(null);
    allow1.refetch();
    allow2.refetch();
    refetchAutoMint();
    refetchOperator();
  }

  const runWith = async (key: string, fn: () => Promise<void>) => {
    try {
      setWorking(key);
      await fn();
    } finally {
      if (!pendingHash) setWorking(null);
    }
  };


  const approveToken = (slot: "t1" | "t2", tokenAddr: Address | undefined, allow: typeof allow1) =>
    runWith(slot, async () => {
      if (!tokenAddr || !factoryAddress) return;
      // First missing layer fires, then the user clicks again for the next.
      if (allow.needsErc20Approval) {
        const h = await erc20.approve(tokenAddr, factoryAddress);
        setPendingHash(h);
        return;
      }
      if (allow.needsFactoryApproval) {
        const h = await factoryApprove({ address: factoryAddress, args: [tokenAddr, MAX_UINT256] });
        setPendingHash(h);
      }
    });

  const statusOf = (slot: "t1" | "t2", tokenAddr: Address | undefined, allow: typeof allow1): RowStatus => {
    if (!tokenAddr) return "unavailable";
    if (working === slot) return "working";
    if (!allow.needsErc20Approval && !allow.needsFactoryApproval) return "approved";
    return "pending";
  };

  const g1Status = statusOf("t1", token1, allow1);
  const g2Status = statusOf("t2", token2, allow2);

  const g3Status: RowStatus = working === "auto" ? "working" : autoMintRedeem ? "approved" : "pending";

  const toggleAutoMint = () =>
    runWith("auto", async () => {
      if (!factoryAddress) return;
      const h = await setAutoMint({ address: factoryAddress, args: [!autoMintRedeem] });
      setPendingHash(h);
    });

  const g4Status: RowStatus = working === "op" ? "working" : isOperatorApproved ? "approved" : "pending";

  const toggleOperator = () =>
    runWith("op", async () => {
      if (!factoryAddress || !operatorValid) return;
      const h = await approveOperator({
        address: factoryAddress,
        args: [operator as Address, !isOperatorApproved],
      });
      setPendingHash(h);
    });

  return (
    <div className="p-4 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
      <h2 className="text-sm font-medium text-blue-300 mb-3">Approvals</h2>

      <TokenApprovalRow
        status={g1Status}
        token={token1}
        setToken={setToken1}
        tokenOptions={tokenOptions}
        onClick={() => approveToken("t1", token1, allow1)}
        disabled={!userAddress || !factoryAddress}
        needsErc20={allow1.needsErc20Approval}
      />
      <TokenApprovalRow
        status={g2Status}
        token={token2}
        setToken={setToken2}
        tokenOptions={tokenOptions}
        onClick={() => approveToken("t2", token2, allow2)}
        disabled={!userAddress || !factoryAddress}
        needsErc20={allow2.needsErc20Approval}
      />

      <ToggleRow
        title="Auto-Mint/Redeem"
        status={g3Status}
        onClick={toggleAutoMint}
        disabled={!factoryAddress || !userAddress}
        on={Boolean(autoMintRedeem)}
      />

      {/* Operator — free-form input with datalist of known contracts */}
      <div className="py-2 border-t border-gray-800">
        <div className="flex items-center justify-between gap-2 mb-2">
          <span className="text-xs text-blue-200">Operator</span>
          <Dot status={g4Status} />
        </div>
        <div className="flex gap-2">
          <input
            type="text"
            list="known-operators"
            value={operator}
            onChange={e => setOperatorInput(e.target.value.trim())}
            placeholder="0x… or pick a preset"
            className="flex-1 min-w-0 p-1.5 rounded border border-gray-700 bg-black/60 text-blue-300 font-mono text-xs"
          />
          <datalist id="known-operators">
            {KNOWN_OPERATORS.map(o => (
              <option key={o.address} value={o.address}>
                {o.label}
              </option>
            ))}
          </datalist>
          <button
            onClick={toggleOperator}
            disabled={!operatorValid || !factoryAddress || !userAddress || g4Status === "working"}
            className={`px-2 py-1 rounded text-xs font-medium transition-colors ${
              !operatorValid || g4Status === "working" || !userAddress
                ? "bg-gray-700 cursor-not-allowed text-gray-400"
                : isOperatorApproved
                  ? "bg-red-600 hover:bg-red-700 text-white"
                  : "bg-blue-500 hover:bg-blue-600 text-white"
            }`}
          >
            {g4Status === "working" ? "…" : isOperatorApproved ? "Revoke" : "Approve"}
          </button>
        </div>
      </div>
    </div>
  );
}

interface TokenApprovalRowProps {
  status: RowStatus;
  token: Address | undefined;
  setToken: (addr: Address) => void;
  tokenOptions: { address: string; symbol: string; decimals: number }[];
  onClick: () => void;
  disabled: boolean;
  needsErc20: boolean;
}

// Per-token row — user picks the token, we approve both layers (ERC20 + factory).
const TokenApprovalRow = ({
  status,
  token,
  setToken,
  tokenOptions,
  onClick,
  disabled,
  needsErc20,
}: TokenApprovalRowProps) => {
  const unavailable = !token;
  const blocked = disabled || unavailable || status === "approved" || status === "working";
  const label = status === "working"
    ? "…"
    : status === "approved"
      ? "Approved ✓"
      : unavailable
        ? "Choose token"
        : needsErc20
          ? "Approve ERC20"
          : "Approve Factory";

  return (
    <div className="py-2 border-t border-gray-800 first:border-t-0 flex items-center justify-between gap-2">
      <div className="flex items-center gap-2 min-w-0 flex-1">
        <Dot status={status} />
        <select
          value={(token ?? "").toLowerCase()}
          onChange={e => setToken(e.target.value.toLowerCase() as Address)}
          className="p-1 rounded border border-gray-700 bg-black/60 text-blue-300 text-xs min-w-[4.5rem]"
        >
          <option value="">Token…</option>
          {tokenOptions.map(t => (
            <option key={t.address} value={t.address.toLowerCase()}>
              {t.symbol}
            </option>
          ))}
        </select>
        <span className="text-xs text-blue-200 truncate">Factory Allowance</span>
      </div>
      <button
        onClick={onClick}
        disabled={blocked}
        className={`px-2 py-1 rounded text-xs font-medium transition-colors whitespace-nowrap shrink-0 ${
          blocked ? "bg-gray-700 cursor-not-allowed text-gray-400" : "bg-blue-500 hover:bg-blue-600 text-white"
        }`}
      >
        {label}
      </button>
    </div>
  );
};

interface ToggleRowProps {
  title: string;
  status: RowStatus;
  onClick: () => void;
  disabled: boolean;
  on: boolean;
}

const ToggleRow = ({ title, status, onClick, disabled, on }: ToggleRowProps) => {
  const blocked = disabled || status === "working";
  const label = status === "working" ? "…" : on ? "Disable" : "Enable";
  return (
    <div className="py-2 border-t border-gray-800 flex items-center justify-between gap-2">
      <div className="flex items-center gap-2 min-w-0">
        <Dot status={status} />
        <span className="text-xs text-blue-200 truncate">{title}</span>
      </div>
      <button
        onClick={onClick}
        disabled={blocked}
        className={`px-2 py-1 rounded text-xs font-medium transition-colors whitespace-nowrap ${
          blocked
            ? "bg-gray-700 cursor-not-allowed text-gray-400"
            : on
              ? "bg-red-600 hover:bg-red-700 text-white"
              : "bg-blue-500 hover:bg-blue-600 text-white"
        }`}
      >
        {label}
      </button>
    </div>
  );
};

const Dot = ({ status }: { status: RowStatus }) => {
  const color =
    status === "approved"
      ? "bg-green-400"
      : status === "working"
        ? "bg-yellow-400"
        : status === "unavailable"
          ? "bg-gray-600"
          : "bg-orange-400";
  return <span className={`inline-block w-2 h-2 rounded-full ${color} shrink-0`} title={status} />;
};

export default Approvals;
