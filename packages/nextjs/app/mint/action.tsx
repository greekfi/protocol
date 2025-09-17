import { useState } from "react";
import TokenBalanceNow from "./components/TokenBalanceNow";
import TooltipButton from "./components/TooltipButton";
import { useAllowanceCheck } from "./hooks/useAllowanceCheck";
import { useContract } from "./hooks/useContract";
import { useOptionDetails } from "./hooks/useGetOption";
import { usePermit2 } from "./hooks/usePermit2";
import { PERMIT2_ADDRESS } from "@uniswap/permit2-sdk";
import { Abi, Address, erc20Abi, parseUnits } from "viem";
import { useWriteContract } from "wagmi";

const STRIKE_DECIMALS = 10n ** 18n;
const MAX_UINT256 = 2n ** 256n - 1n;

const toConsideration = (amount: bigint, details: any): bigint => {
  const { strike, collDecimals, consDecimals } = details;
  return (amount * strike * 10n ** BigInt(consDecimals)) / (STRIKE_DECIMALS * 10n ** BigInt(collDecimals));
};

interface ActionInterfaceProps {
  details: ReturnType<typeof useOptionDetails>;
  action: "redeem" | "exercise" | "mint";
}

const Action = ({ details, action }: ActionInterfaceProps) => {
  const { collDecimals: collateralDecimals, consDecimals, isExpired } = details || {};

  const [amount, setAmount] = useState<number>(0);
  const { writeContract, isPending } = useWriteContract();
  const longAbi = useContract()?.LongOption?.abi;
  const collateralWei = parseUnits(amount.toString(), Number(details?.collDecimals));
  const amountWei = parseUnits(amount.toString(), Number(details));
  const { getPermitSignature: mintSignature } = usePermit2(
    details?.collateral as Address,
    details?.shortOption as Address,
  );
  const { getPermitSignature: exerciseSignature } = usePermit2(
    details?.consideration as Address,
    details?.shortOption as Address,
  );
  const { considerationAllowance, collateralAllowance } = useAllowanceCheck(
    details?.consideration as Address,
    details?.collateral as Address,
  );

  const redeem = async () => {
    if (!details) return;
    const redeemConfig = {
      address: details.isExpired ? details.shortOption : details.longOption,
      abi: longAbi,
      functionName: "redeem",
      args: [amountWei],
    };
    writeContract(redeemConfig as any);
  };

  const exercise = async () => {
    if (!amount || !details) return;

    const considerationWei = toConsideration(amountWei, details);

    if (!considerationAllowance || considerationAllowance < considerationWei) {
      writeContract({
        address: details.consideration,
        abi: erc20Abi,
        functionName: "approve",
        args: [PERMIT2_ADDRESS, MAX_UINT256],
      } as any);
    }

    const { permit, signature, transferDetails } = await exerciseSignature(considerationWei);
    console.log("permit", permit);
    console.log("signature", signature);
    console.log("transferDetails", transferDetails);
    writeContract({
      address: details.longOption,
      abi: longAbi as Abi,
      functionName: "exercise",
      args: [permit, transferDetails, signature],
    });
  };

  const mint = async () => {
    if (!details) return;

    if (!collateralAllowance || collateralAllowance < collateralWei) {
      writeContract({
        address: details.collateral,
        abi: erc20Abi,
        functionName: "approve",
        args: [PERMIT2_ADDRESS, MAX_UINT256],
      } as any);
    }

    const { permit, signature, transferDetails } = await mintSignature(collateralWei);
    writeContract({
      address: details.longOption,
      abi: longAbi as Abi,
      functionName: "mint",
      args: [permit, transferDetails, signature],
    });
  };

  const handleAction = async () => {
    if (action === "redeem") {
      await redeem();
    } else if (action === "exercise") {
      await exercise();
    } else if (action === "mint") {
      await mint();
    }
  };

  const title = {
    redeem: "Redeem Options",
    exercise: "Exercise Options",
    mint: "Mint Options",
  }[action];
  const tooltipText = {
    redeem: "Redeem your options (before or after expiry)",
    exercise: "Exercise your options to receive the underlying asset",
    mint: "Mint options to receive the underlying asset",
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
              symbol={details?.symbol}
              balance={details?.balanceLong}
              decimals={collateralDecimals}
              label="Long Option Balance"
            />
            <TokenBalanceNow
              symbol={details?.shortSymbol}
              balance={details?.balanceShort}
              decimals={collateralDecimals}
              label="Short Option Balance"
            />
          </>
        )}
        {action === "exercise" && (
          <>
            <TokenBalanceNow
              symbol={details?.consSymbol}
              balance={details?.balanceConsideration}
              decimals={consDecimals}
              label="Consideration Balance"
            />
            <TokenBalanceNow
              symbol={details?.symbol}
              balance={details?.balanceLong}
              decimals={collateralDecimals}
              label="Long Option Balance"
            />
          </>
        )}
        {action === "mint" && (
          <>
            <TokenBalanceNow
              symbol={details?.collSymbol}
              balance={details?.balanceCollateral}
              decimals={collateralDecimals}
              label="Collateral Balance"
            />
            <TokenBalanceNow
              symbol={details?.symbol}
              balance={details?.balanceLong}
              decimals={collateralDecimals}
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
            title={isExpired ? "Option is expired" : ""}
          >
            {isPending ? "Processing..." : title}
          </button>
        </div>
      </div>
    </div>
  );
};

export default Action;
