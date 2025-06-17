import { useState } from "react";
import TokenBalance from "./components/TokenBalance";
import { usePermit2 } from "./hooks/usePermit2";
import { Address, parseUnits } from "viem";
import { useChainId, useWriteContract } from "wagmi";
import deployedContracts from "~~/contracts/deployedContracts";

const MintInterface = ({
  optionAddress,
  shortAddress,
  collateralAddress,
  collateralDecimals,
  isExpired,
}: {
  optionAddress: Address;
  shortAddress: Address;
  collateralAddress: Address;
  collateralDecimals: number;
  isExpired: boolean;
}) => {
  const [amount, setAmount] = useState<number>(0);
  const { writeContract, isPending } = useWriteContract();
  const { getPermitSignature } = usePermit2();
  const chainId = useChainId();
  const contract = deployedContracts[chainId as keyof typeof deployedContracts];
  const longAbi = contract.LongOption.abi;
  const handleAction = async () => {
    const { permitDetails, signature } = await getPermitSignature(
      collateralAddress,
      parseUnits(amount.toString(), Number(collateralDecimals)),
      shortAddress,
    );

    const actionConfig = {
      address: optionAddress,
      abi: longAbi,
      functionName: "mint2",
      args: [parseUnits(amount.toString(), Number(collateralDecimals)), permitDetails, signature],
    };

    writeContract(actionConfig as any);
  };

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg max-w-sm">
      <div className="flex justify-between items-center mb-6">
        <h2 className="text-xl font-light text-blue-300">
          <div className="flex items-center gap-2">
            Mint Options
            <button
              type="button"
              className="text-sm text-blue-200 hover:text-blue-300 flex items-center gap-1"
              title="Mint new options by providing collateral"
              onClick={e => {
                const tooltip = document.createElement("div");
                tooltip.className = "absolute bg-gray-900 text-sm text-gray-200 p-2 rounded shadow-lg -mt-8 -ml-2";
                tooltip.textContent = "Mint new options by providing collateral";

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

      <TokenBalance tokenAddress={collateralAddress} decimals={collateralDecimals} label="Collateral Balance" />

      <div className="flex flex-col gap-4 w-full">
        <input
          type="number"
          className="w-1/2 p-2 rounded-lg border border-gray-800 bg-black/60 text-blue-300"
          placeholder="Amount to mint"
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
            {isPending ? "Processing..." : "Mint Options"}
          </button>
        </div>
      </div>
    </div>
  );
};

export default MintInterface;
