import { useCallback, useState } from "react";
import { toStrikePrice } from "../hooks/constants";
import { CreateOptionParams, useCreateOption } from "../hooks/useCreateOption";
import { Token, useTokenMap } from "../hooks/useTokenMap";
import ActionHeader from "./ActionHeader";
import { Address } from "viem";
import { useAccount } from "wagmi";

// import { getStepLabel } from "../hooks/useTransactionFlow";

/**
 * Helper to get a human-readable label for a transaction step
 */
export function getStepLabel(step: any): string {
  switch (step) {
    case "idle":
      return "Ready";
    case "checking-allowance":
      return "Checking allowances...";
    case "approving-erc20":
      return "Approving token...";
    case "waiting-erc20":
      return "Confirming token approval...";
    case "approving-factory":
      return "Approving factory...";
    case "waiting-factory":
      return "Confirming factory approval...";
    case "executing":
      return "Executing...";
    case "waiting-execution":
      return "Confirming transaction...";
    case "success":
      return "Success!";
    case "error":
      return "Error";
    default:
      return step;
  }
}

interface TokenSelectProps {
  label: string;
  value: Token | undefined;
  onChange: (token: Token) => void;
  tokensMap: Record<string, Token>;
}

const TokenSelect = ({ label, value, onChange, tokensMap }: TokenSelectProps) => (
  <div className="flex-1">
    {label && <label className="block text-sm font-medium text-gray-700 mb-1">{label}</label>}
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

const Create = () => {
  const { isConnected } = useAccount();
  const { allTokensMap } = useTokenMap();

  // Use the new create option hook
  const { createOptions, step, isLoading, isSuccess, error, txHash, reset } = useCreateOption();

  // Form state
  const [collateralToken, setCollateralToken] = useState<Token | undefined>(undefined);
  const [considerationToken, setConsiderationToken] = useState<Token | undefined>(undefined);
  const [strikePrices, setStrikePrices] = useState<number[]>([]);
  const [isPut, setIsPut] = useState(false);
  const [expirationDates, setExpirationDates] = useState<Date[]>([new Date()]);

  const addExpirationDate = useCallback(() => {
    setExpirationDates(prev => [...prev, new Date()]);
  }, []);

  const removeExpirationDate = useCallback((index: number) => {
    setExpirationDates(prev => (prev.length > 1 ? prev.filter((_, i) => i !== index) : prev));
  }, []);

  const updateExpirationDate = useCallback((index: number, date: Date) => {
    setExpirationDates(prev => {
      const newDates = [...prev];
      newDates[index] = date;
      return newDates;
    });
  }, []);

  const handleStrikePricesChange = useCallback((value: string) => {
    const strikes = value
      .split(/[\n,]+/)
      .map(s => s.trim())
      .filter(Boolean)
      .map(Number)
      .filter(n => !isNaN(n) && n > 0);
    setStrikePrices(strikes);
  }, []);

  const calculateStrike = useCallback(
    (price: number): bigint => {
      if (isPut && price > 0) {
        // For PUT: invert the strike price
        return toStrikePrice(1 / price);
      }
      return toStrikePrice(price);
    },
    [isPut],
  );

  const handleCreateOption = useCallback(async () => {
    console.log("=== handleCreateOption START ===");
    console.log("collateralToken:", collateralToken);
    console.log("considerationToken:", considerationToken);
    console.log("strikePrices:", strikePrices);
    console.log("expirationDates:", expirationDates);
    console.log("isPut:", isPut);

    if (!collateralToken || !considerationToken || strikePrices.length === 0 || expirationDates.length === 0) {
      console.error("Missing required fields");
      return;
    }

    // Build all option params
    const allParams: CreateOptionParams[] = [];

    for (const expirationDate of expirationDates) {
      const expTimestamp = Math.floor(new Date(expirationDate).getTime() / 1000);

      for (const price of strikePrices) {
        const strikeValue = calculateStrike(price);
        console.log(`Building option param for price ${price}:`, {
          collateral: collateralToken.address,
          consideration: considerationToken.address,
          expiration: expTimestamp,
          expirationDate: new Date(expTimestamp * 1000).toISOString(),
          strike: strikeValue.toString(),
          strikeHex: "0x" + strikeValue.toString(16),
          isPut,
        });

        allParams.push({
          collateral: collateralToken.address as Address,
          consideration: considerationToken.address as Address,
          expiration: expTimestamp,
          strike: strikeValue,
          isPut,
        });
      }
    }

    console.log("Final allParams:", allParams);
    console.log("Calling createOptions with", allParams.length, "options");

    try {
      await createOptions(allParams);
      console.log("createOptions completed successfully");
    } catch (err) {
      console.error("createOptions failed:", err);
    }
  }, [collateralToken, considerationToken, strikePrices, expirationDates, isPut, calculateStrike, createOptions]);

  const isFormValid =
    isConnected && collateralToken && considerationToken && strikePrices.length > 0 && expirationDates.length > 0;

  const getButtonText = () => {
    if (isLoading) return getStepLabel(step);
    if (isSuccess) return "Created!";
    return "Create Option";
  };

  return (
    <div className="max-w-2xl mx-auto bg-black/80 border border-gray-800 rounded-lg shadow-lg p-6 text-lg">
      <div className="flex flex-col space-y-6">
        <ActionHeader />

        {/* Main Layout */}
        <div className="flex gap-8">
          {/* Left Side - Controls */}
          <div className="flex flex-col space-y-6 w-1/2">
            {/* Option Type Selector */}
            <div className="flex flex-col space-y-2">
              <label className="text-blue-100">Option Type:</label>
              <div className="flex space-x-2">
                <button
                  type="button"
                  onClick={() => setIsPut(false)}
                  className={`px-4 py-2 rounded-lg transition-colors ${
                    !isPut ? "bg-blue-500 text-white" : "bg-gray-700 text-gray-300 hover:bg-gray-600"
                  }`}
                >
                  CALL
                </button>
                <button
                  type="button"
                  onClick={() => setIsPut(true)}
                  className={`px-4 py-2 rounded-lg transition-colors ${
                    isPut ? "bg-blue-500 text-white" : "bg-gray-700 text-gray-300 hover:bg-gray-600"
                  }`}
                >
                  PUT
                </button>
              </div>
            </div>

            {/* Expiration Dates */}
            <div className="flex flex-col space-y-2">
              <div className="flex items-center justify-between">
                <label className="text-blue-100">Expiration Dates:</label>
                <button
                  type="button"
                  onClick={addExpirationDate}
                  className="px-2 py-1 bg-green-600 text-white rounded text-sm hover:bg-green-700 transition-colors"
                >
                  +
                </button>
              </div>
              <div className="flex flex-col space-y-2">
                {expirationDates.map((date, index) => (
                  <div key={index} className="flex items-center space-x-2">
                    <input
                      type="date"
                      className="flex-1 rounded-lg border border-gray-800 bg-black/60 text-blue-300 p-2"
                      value={date.toISOString().split("T")[0]}
                      onChange={e => updateExpirationDate(index, new Date(e.target.value))}
                    />
                    {expirationDates.length > 1 && (
                      <button
                        type="button"
                        onClick={() => removeExpirationDate(index)}
                        className="px-2 py-1 bg-red-600 text-white rounded text-sm hover:bg-red-700 transition-colors"
                      >
                        -
                      </button>
                    )}
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* Right Side - Swap Inputs and Button */}
          <div className="flex flex-col space-y-4 w-1/2">
            {isPut ? (
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
                      value={considerationToken}
                      onChange={setConsiderationToken}
                      tokensMap={allTokensMap}
                    />
                  </div>
                </div>

                <div className="flex items-center space-x-4">
                  <span className="text-blue-100">and receives</span>
                </div>
                <div className="flex items-center space-x-4">
                  <textarea
                    className="w-full rounded-lg border border-gray-200 bg-black/60 text-blue-300 p-2 resize-none"
                    rows={3}
                    onChange={e => handleStrikePricesChange(e.target.value)}
                    placeholder="e.g. 100, 200, 300"
                  />
                  <div className="w-32">
                    <TokenSelect
                      label=""
                      value={collateralToken}
                      onChange={setCollateralToken}
                      tokensMap={allTokensMap}
                    />
                  </div>
                </div>
              </>
            ) : (
              // Call Option Layout
              <>
                <div className="flex flex-col space-y-2 w-64">
                  <div className="flex items-center">
                    <span className="text-blue-100">Call Option Holder swaps</span>
                  </div>

                  <div className="flex flex-col space-y-2 w-64">
                    <label className="text-blue-100 text-sm mb-1">Strike Prices (comma or newline separated)</label>
                    <textarea
                      className="w-full rounded-lg border border-gray-200 bg-black/60 text-blue-300 p-2 resize-none"
                      rows={3}
                      onChange={e => handleStrikePricesChange(e.target.value)}
                      placeholder="e.g. 100, 200, 300"
                    />
                  </div>

                  <div className="w-32">
                    <TokenSelect
                      label=""
                      value={considerationToken}
                      onChange={setConsiderationToken}
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
                      value={collateralToken}
                      onChange={setCollateralToken}
                      tokensMap={allTokensMap}
                    />
                  </div>
                </div>
              </>
            )}

            <button
              type="button"
              className={`px-4 py-2 rounded-lg text-black transition-transform hover:scale-105 ${
                !isFormValid || isLoading ? "bg-blue-300 cursor-not-allowed" : "bg-blue-500 hover:bg-blue-600"
              }`}
              onClick={isSuccess ? reset : handleCreateOption}
              disabled={!isFormValid || isLoading}
            >
              {getButtonText()}
            </button>
          </div>
        </div>

        {/* Status messages */}
        {error && <div className="text-red-500 text-sm">Error: {error.message}</div>}
        {isSuccess && txHash && (
          <div className="text-green-500 text-sm">
            Option creation successful!
            <br />
            <span className="text-gray-400 text-xs">Tx: {txHash}</span>
          </div>
        )}
      </div>
    </div>
  );
};

export default Create;
