import { useEffect, useState } from "react";
import TokenBalance from "./components/TokenBalance";
import { usePermit2 } from "./hooks/usePermit2";
import { Abi, Address, parseUnits } from "viem";
import { useChainId, useReadContract, useWriteContract } from "wagmi";
import deployedContracts from "~~/contracts/deployedContracts";

const ExerciseInterface = ({
  optionAddress,
  shortAddress,
  collateralAddress,
  considerationAddress,
  collateralDecimals,
  considerationDecimals,
  isExpired,
}: {
  optionAddress: Address;
  shortAddress: Address;
  collateralAddress: Address;
  considerationAddress: Address;
  collateralDecimals: number;
  considerationDecimals: number;
  isExpired: boolean;
}) => {
  const chainId = useChainId();
  const contract = deployedContracts[chainId as keyof typeof deployedContracts];
  const longAbi = contract.LongOption.abi;
  const [amount, setAmount] = useState<number>(0);
  const [tokenToApprove, setTokenToApprove] = useState<Address>(considerationAddress);
  const [tokenDecimals, setTokenDecimals] = useState<number>(considerationDecimals);
  const { writeContract, isPending } = useWriteContract();
  const { getPermitSignature } = usePermit2();

  // Check if the option is a PUT
  const { data: optionIsPut } = useReadContract({
    address: optionAddress,
    abi: longAbi,
    functionName: "isPut",
    query: {
      enabled: !!optionAddress,
    },
  });

  // Update state when option type is determined
  useEffect(() => {
    if (optionIsPut !== undefined) {
      if (optionIsPut) {
        // For PUT mint, we use collateral tokens
        setTokenToApprove(collateralAddress);
        setTokenDecimals(collateralDecimals);
      } else {
        // For CALL mint, we use consideration tokens
        setTokenToApprove(considerationAddress);
        setTokenDecimals(considerationDecimals);
      }
    }
  }, [optionIsPut, collateralAddress, considerationAddress, collateralDecimals, considerationDecimals]);

  const handleAction = async () => {
    if (!amount) return;

    const amountInWei = parseUnits(amount.toString(), Number(tokenDecimals));

    // Get permit signature
    const { permitDetails, signature } = await getPermitSignature(tokenToApprove, amountInWei, shortAddress);

    const actionConfig = {
      address: optionAddress,
      abi: longAbi as Abi,
      functionName: "exercise",
      args: [amountInWei, permitDetails, signature],
    };

    writeContract(actionConfig);
  };

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg max-w-sm">
      <div className="flex justify-between items-center mb-6">
        <h2 className="text-xl font-light text-blue-300">
          <div className="flex items-center gap-2">
            Exercise Options
            <button
              type="button"
              className="text-sm text-blue-200 hover:text-blue-300 flex items-center gap-1"
              title="Exercise your options to receive the underlying asset"
              onClick={e => {
                const tooltip = document.createElement("div");
                tooltip.className = "absolute bg-gray-900 text-sm text-gray-200 p-2 rounded shadow-lg -mt-8 -ml-2";
                tooltip.textContent = "Exercise your options to receive the underlying asset";

                const button = e.currentTarget;
                button.appendChild(tooltip);

                setTimeout(() => {
                  tooltip.remove();
                }, 2000);
              }}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                strokeWidth={1.5}
                stroke="currentColor"
                className="w-4 h-4"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  d="m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z"
                />
              </svg>
            </button>
          </div>
        </h2>
      </div>

      <TokenBalance
        tokenAddress={considerationAddress}
        decimals={considerationDecimals}
        label="Consideration Balance"
      />

      <div className="flex flex-col gap-4 w-full">
        <input
          type="number"
          className="w-1/2 p-2 rounded-lg border border-gray-800 bg-black/60 text-blue-300"
          placeholder="Amount to exercise"
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
            className={`px-4 py-2 rounded-lg text-black transition-transform hover:scale-105 ${
              !amount || isPending || isExpired ? "bg-blue-300 cursor-not-allowed" : "bg-blue-500 hover:bg-blue-600"
            }`}
            onClick={handleAction}
            disabled={!amount || isPending || isExpired}
            title={isExpired ? "Option is expired" : ""}
          >
            {isPending ? "Processing..." : "Exercise Options"}
          </button>
        </div>
      </div>
    </div>
  );
};

export default ExerciseInterface;
