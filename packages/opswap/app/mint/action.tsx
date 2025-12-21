import { useState } from "react";
import TokenBalanceNow from "./components/TokenBalanceNow";
import TooltipButton from "./components/TooltipButton";
import { useContract } from "./hooks/useContract";
import type { OptionDetails } from "./hooks/types";
import { Abi, Address, erc20Abi, parseUnits } from "viem";
import { useWriteContract } from "wagmi";
import { useFactoryAddress } from "./hooks/useContracts";

const STRIKE_DECIMALS = 10n ** 18n;
const MAX_UINT256 = 2n ** 256n - 1n;

const toConsideration = (amount: bigint, details: OptionDetails): bigint => {
  const { strike, collateral, consideration } = details;
  const collDecimals = collateral.decimals;
  const consDecimals = consideration.decimals;
  return (amount * strike * 10n ** BigInt(consDecimals)) / (STRIKE_DECIMALS * 10n ** BigInt(collDecimals));
};

interface ActionInterfaceProps {
  details: OptionDetails | null;
  action: "redeem" | "exercise";
}

const Action = ({ details, action }: ActionInterfaceProps) => {
  const [amount, setAmount] = useState<number>(0);
  const { writeContract, isPending } = useWriteContract();
  const optionAbi = useContract()?.Option?.abi;
  const factoryAddress = useFactoryAddress();
  // Option tokens have same decimals as collateral (standard ERC20 18 decimals)
  const amountWei = parseUnits(amount.toString(), 18);

  const redeem = async () => {
    if (!details) return;
    const redeemConfig = {
      address: details.isExpired ? details.redemption : details.option,
      abi: optionAbi,
      functionName: "redeem",
      args: [amountWei],
    };
    writeContract(redeemConfig as any);
  };

  const exercise = async () => {
    if (!amount || !details || !factoryAddress) return;

    const considerationWei = toConsideration(amountWei, details);

    // NOTE: This is the OLD approval system. Should use new two-layer approval from useApproval hook
    // This is kept for backward compatibility until Phase 2 refactor
    writeContract({
      address: details.consideration.address as Address,
      abi: erc20Abi,
      functionName: "approve",
      args: [factoryAddress, MAX_UINT256],
    } as any);

    writeContract({
      address: details.option as Address,
      abi: optionAbi as Abi,
      functionName: "exercise",
      args: [amountWei],
    });
  };

  const handleAction = async () => {
    if (action === "redeem") {
      await redeem();
    } else if (action === "exercise") {
      await exercise();
    }
  };

  const title = {
    redeem: "Redeem Options",
    exercise: "Exercise Options",
  }[action];
  const tooltipText = {
    redeem: "Redeem your options (before or after expiry)",
    exercise: "Exercise your options to receive the underlying asset",
  }[action];

  const buttonColor = { notAllowed: "bg-blue-300 cursor-not-allowed", allowed: "bg-blue-500 hover:bg-blue-600" };
  const buttonClass = `px-4 py-2 rounded-lg text-black transition-transform hover:scale-105 ${
    !amount || isPending ? buttonColor.notAllowed : buttonColor.allowed
  }`;

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg max-w-sm">
      <div className="flex justify-between items-center mb-6">
        <h2 className="text-xl font-light text-blue-300">
          <div className="flex items-center gap-2">
            {title}
            <TooltipButton tooltipText={tooltipText} title={tooltipText} />
          </div>
        </h2>
      </div>

      <div className="space-y-2 mb-4">
        {action === "redeem" && (
          <>
            <TokenBalanceNow
              symbol="OPT"
              balance={details?.balances?.option}
              decimals={18}
              label="Long Option Balance"
            />
            <TokenBalanceNow
              symbol="RED"
              balance={details?.balances?.redemption}
              decimals={18}
              label="Short Option Balance"
            />
          </>
        )}
        {action === "exercise" && (
          <>
            <TokenBalanceNow
              symbol={details?.consideration.symbol}
              balance={details?.balances?.consideration}
              decimals={details?.consideration.decimals}
              label="Consideration Balance"
            />
            <TokenBalanceNow
              symbol="OPT"
              balance={details?.balances?.option}
              decimals={18}
              label="Long Option Balance"
            />
          </>
        )}
      </div>

      <div className="flex flex-col gap-4 w-full">
        <input
          type="number"
          className="w-1/2 p-2 rounded-lg border border-gray-800 bg-black/60 text-blue-300"
          placeholder={`Amount to ${action}`}
          value={amount || ""}
          onChange={e => {
            const val = e.target.value;
            if (val === "") {
              setAmount(0);
            } else {
              setAmount(Number(val));
            }
          }}
          min={0}
          step=".1"
        />

        <div className="flex gap-4">
          <button
            className={buttonClass}
            onClick={handleAction}
            disabled={!amount || isPending}
            title={details?.isExpired ? "Option is expired" : ""}
          >
            {isPending ? "Processing..." : title}
          </button>
        </div>
      </div>
    </div>
  );
};

export default Action;
