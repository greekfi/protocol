import { useState } from "react";
import Factory from "./abi/OptionFactory_metadata.json";
import tokenList from "./tokenList.json";
import moment from "moment-timezone";
import { Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";

const abi = Factory.output.abi;

interface Token {
  address: string;
  symbol: string;
  decimals: number;
}

// Create a map of all tokens for easy lookup
const allTokensMap = tokenList.reduce(
  (acc, token) => {
    acc[token.symbol] = token;
    return acc;
  },
  {} as Record<string, Token>,
);

interface TokenSelectProps {
  label: string;
  value: Token | undefined;
  onChange: (token: Token) => void;
  tokensMap: Record<string, Token>;
}

const TokenSelect = ({ label, value, onChange, tokensMap }: TokenSelectProps) => (
  <div className="flex-1">
    <label className="block text-sm font-medium text-gray-700 mb-1">{label}</label>
    <select
      className="w-full rounded-lg border border-gray-200 bg-black/60 text-blue-300 p-2"
      value={value?.symbol || ""}
      onChange={e => onChange(tokensMap[e.target.value])}
    >
      <option value="">Select token</option>
      {Object.keys(tokensMap).map(symbol => (
        <option key={symbol} value={symbol}>
          {symbol}
        </option>
      ))}
    </select>
  </div>
);

const OptionCreator = ({ baseContractAddress }: { baseContractAddress: Address }) => {
  const { isConnected } = useAccount();
  const { writeContract } = useWriteContract();

  // Consolidated state
  const [formData, setFormData] = useState({
    collateralToken: undefined as Token | undefined,
    considerationToken: undefined as Token | undefined,
    strikePrice: 0,
    isPut: false,
    expirationDate: undefined as Date | undefined,
  });

  const calculateStrikeRatio = () => {
    const { collateralToken, considerationToken, strikePrice, isPut } = formData;
    if (!strikePrice || !considerationToken || !collateralToken) return { strikeInteger: BigInt(0) };
    // For PUT mint, we need to invert the strike price in the calculation
    // This is because puts are really just call mint but with the strike price inverted
    if (isPut) {
      // For PUT mint: 1/strikePrice * 10^(18 + considerationDecimals - collateralDecimals)
      const invertedStrike = strikePrice === 0 ? 0 : 1 / strikePrice;
      return {
        strikeInteger: BigInt(
          Math.floor(invertedStrike * Math.pow(10, 18 + considerationToken.decimals - collateralToken.decimals)),
        ),
      };
    }
    return {
      strikeInteger: BigInt(strikePrice * Math.pow(10, 18 + considerationToken.decimals - collateralToken.decimals)),
    };
  };

  const handleCreateOption = async () => {
    const { collateralToken, considerationToken, strikePrice, expirationDate, isPut } = formData;
    if (!collateralToken || !considerationToken || !strikePrice || !expirationDate) {
      alert("Please fill in all fields");
      return;
    }

    const { strikeInteger } = calculateStrikeRatio();
    const expTimestamp = Math.floor(new Date(expirationDate).getTime() / 1000);
    const fmtDate = moment(expirationDate).format("YYYYMMDD");

    const optionType = isPut ? "P" : "C";
    const baseNameSymbol = `OPT${optionType}-${collateralToken.symbol}-${considerationToken.symbol}-${fmtDate}-${strikePrice}`;
    const longName = `L${baseNameSymbol}`;
    const shortName = `S${baseNameSymbol}`;

    try {
      writeContract({
        address: baseContractAddress,
        abi,
        functionName: "createOption",
        args: [
          longName,
          shortName,
          longName,
          shortName,
          collateralToken.address as Address,
          considerationToken.address as Address,
          BigInt(expTimestamp),
          strikeInteger,
          isPut,
        ],
      });
    } catch (error) {
      console.error("Error creating option:", error);
      alert("Failed to create option. Check console for details.");
    }
  };

  const updateFormData = (field: keyof typeof formData, value: (typeof formData)[keyof typeof formData]) => {
    if (field === "isPut") {
      // When toggling between Call and Put, swap the token values
      setFormData(prev => ({
        ...prev,
        isPut: value as boolean,
        collateralToken: prev.considerationToken,
        considerationToken: prev.collateralToken,
      }));
    } else {
      setFormData(prev => ({ ...prev, [field]: value }));
    }
  };

  moment.tz.setDefault("Europe/London");

  return (
    <div className="max-w-2xl mx-auto bg-black/80 border border-gray-800 rounded-lg shadow-lg p-6 text-lg">
      <form className="flex flex-col space-y-6 ">
        <h2 className="text-lg font-light text-blue-300">
          <div className="flex items-center gap-1">
            Design New Option
            <button
              type="button"
              className="text-sm text-blue-200 hover:text-blue-300 flex items-center gap-1"
              title="Create a new option contract"
              onClick={e => {
                const tooltip = document.createElement("div");
                tooltip.className = "absolute bg-gray-900 text-sm text-gray-200 p-2 rounded shadow-lg -mt-8 -ml-2";
                tooltip.textContent = "Create a new option contract";

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

        {/* Main Layout */}
        <div className="flex gap-8">
          {/* Left Side - Controls */}
          <div className="flex flex-col space-y-6 w-1/2">
            {/* Option Type Selector */}
            <div className="flex flex-col space-y-2">
              <label className=" text-blue-100">Option Type:</label>
              <div className="flex space-x-2">
                <button
                  type="button"
                  onClick={() => updateFormData("isPut", false)}
                  className={`px-4 py-2 rounded-lg transition-colors ${
                    !formData.isPut ? "bg-blue-500 text-white" : "bg-gray-700 text-gray-300 hover:bg-gray-600"
                  }`}
                >
                  CALL
                </button>
                <button
                  type="button"
                  onClick={() => updateFormData("isPut", true)}
                  className={`px-4 py-2 rounded-lg transition-colors ${
                    formData.isPut ? "bg-blue-500 text-white" : "bg-gray-700 text-gray-300 hover:bg-gray-600"
                  }`}
                >
                  PUT
                </button>
              </div>
            </div>

            {/* Expiration */}
            <div className="flex flex-col space-y-2">
              <label className=" text-blue-100">Expiration:</label>
              <input
                type="date"
                className="rounded-lg border border-gray-800 bg-black/60 text-blue-300 p-2 w-48"
                onChange={e => updateFormData("expirationDate", new Date(e.target.value))}
              />
            </div>
          </div>

          {/* Right Side - Swap Inputs and Button */}
          <div className="flex flex-col space-y-4 w-1/2">
            {formData.isPut ? (
              // Put Option Layout
              <>
                <div className="flex items-center">
                  <span className="text-blue-100">Put Option Holder swaps</span>
                </div>
                <div className="flex items-center space-x-4">
                  <div className="w-16 h-10 flex items-center justify-center rounded-lg bg-black text-gray-300 border border-gray-800">
                    1
                  </div>
                  <div className="w-32">
                    <TokenSelect
                      label=""
                      value={formData.considerationToken}
                      onChange={token => updateFormData("considerationToken", token)}
                      tokensMap={allTokensMap}
                    />
                  </div>
                </div>

                <div className="flex items-center space-x-4">
                  <span className="text-blue-100">and receives</span>
                </div>
                <div className="flex items-center space-x-4">
                  <div className="w-16">
                    <input
                      type="number"
                      className="w-full rounded-lg border border-gray-200 bg-black/60 text-blue-300 p-2"
                      value={formData.strikePrice}
                      onChange={e => updateFormData("strikePrice", Number(e.target.value))}
                      placeholder="Strike"
                    />
                  </div>
                  <div className="w-32">
                    <TokenSelect
                      label=""
                      value={formData.collateralToken}
                      onChange={token => updateFormData("collateralToken", token)}
                      tokensMap={allTokensMap}
                    />
                  </div>
                </div>
              </>
            ) : (
              // Call Option Layout
              <>
                <div className="flex items-center">
                  <span className="text-blue-100">Call Option Holder swaps</span>
                </div>

                <div className="flex items-center space-x-4">
                  <div className="w-16 h-11">
                    <input
                      type="number"
                      className="w-full rounded-lg border border-gray-200 bg-black/60 text-blue-300 p-2"
                      value={formData.strikePrice}
                      onChange={e => updateFormData("strikePrice", Number(e.target.value))}
                      placeholder="Strike"
                    />
                  </div>

                  <div className="w-32">
                    <TokenSelect
                      label=""
                      value={formData.considerationToken}
                      onChange={token => updateFormData("considerationToken", token)}
                      tokensMap={allTokensMap}
                    />
                  </div>
                </div>
                <div className="flex items-center space-x-4">
                  <span className="text-blue-100">and receives</span>
                </div>
                <div className="flex items-center space-x-4">
                  <div className="w-16 h-11 flex items-center justify-center rounded-lg bg-black text-gray-300 border border-gray-800">
                    1
                  </div>
                  <div className="w-32">
                    <TokenSelect
                      label=""
                      value={formData.collateralToken}
                      onChange={token => updateFormData("collateralToken", token)}
                      tokensMap={allTokensMap}
                    />
                  </div>
                </div>
              </>
            )}

            <button
              className={`px-4 py-2 rounded-lg text-black transition-transform hover:scale-105 ${
                !isConnected ||
                !formData.collateralToken ||
                !formData.considerationToken ||
                !formData.strikePrice ||
                !formData.expirationDate
                  ? "bg-blue-300 cursor-not-allowed"
                  : "bg-blue-500 hover:bg-blue-600"
              }`}
              onClick={handleCreateOption}
              disabled={
                !isConnected ||
                !formData.collateralToken ||
                !formData.considerationToken ||
                !formData.strikePrice ||
                !formData.expirationDate
              }
            >
              Create Option
            </button>
          </div>
        </div>
      </form>
    </div>
  );
};

export default OptionCreator;
