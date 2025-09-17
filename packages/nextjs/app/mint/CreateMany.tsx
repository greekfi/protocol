import { useState } from "react";
import DesignHeader from "./components/DesignHeader";
import { useContract } from "./hooks/useContract";
import { Token, useTokenMap } from "./hooks/useTokenMap";
import moment from "moment-timezone";
import { useAccount, useWriteContract } from "wagmi";

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

const Create = ({ refetchOptions }: { refetchOptions: () => void }) => {
  const { isConnected } = useAccount();
  const { writeContract, isPending, isSuccess, data: hash } = useWriteContract();
  const { allTokensMap } = useTokenMap();
  console.log("allTokensMap", allTokensMap);

  const contract = useContract();
  const abi = contract?.OptionFactory?.abi;
  const contractAddress = contract?.OptionFactory?.address;

  // Individual state variables
  const [collateralToken, setCollateralToken] = useState<Token | undefined>(undefined);
  const [considerationToken, setConsiderationToken] = useState<Token | undefined>(undefined);
  const [strikePrices, setStrikePrices] = useState<number[]>([0]);
  const [isPut, setIsPut] = useState(false);
  const [expirationDates, setExpirationDates] = useState<Date[]>([new Date()]);

  const addExpirationDate = () => {
    setExpirationDates([...expirationDates, new Date()]);
  };

  const removeExpirationDate = (index: number) => {
    if (expirationDates.length > 1) {
      setExpirationDates(expirationDates.filter((_, i) => i !== index));
    }
  };

  const updateExpirationDate = (index: number, date: Date) => {
    const newDates = [...expirationDates];
    newDates[index] = date;
    setExpirationDates(newDates);
  };

  const calculateStrikeRatio = (strikePrice: number) => {
    if (!strikePrice || !considerationToken || !collateralToken) return { strikeInteger: BigInt(0) };
    // For PUT mint, we need to invert the strike price in the calculation
    // This is because puts are really just call mint but with the strike price inverted
    if (isPut) {
      // For PUT mint: 1/strikePrice * 10^(18 + considerationDecimals - collateralDecimals)
      const invertedStrike = strikePrice === 0 ? 0 : 1 / strikePrice;
      return {
        strikeInteger: BigInt(Math.floor(invertedStrike * Math.pow(10, 18))),
      };
    }
    return {
      strikeInteger: BigInt(strikePrice * Math.pow(10, 18)),
    };
  };

  const handleCreateOption = async () => {
    // Prevent multiple submissions
    if (isPending) return;

    if (!collateralToken || !considerationToken || !strikePrices || !expirationDates.length) {
      alert("Please fill in all fields");
      return;
    }

    const strikeIntegers = strikePrices.map(strikePrice => calculateStrikeRatio(strikePrice).strikeInteger);
    console.log("strikeIntegers", strikeIntegers);

    // Create options for each expiration date
    const allOptions = [];

    for (const expirationDate of expirationDates) {
      const expTimestamp = Math.floor(new Date(expirationDate).getTime() / 1000);
      // Get the next 10 Fridays after the current date
      const nextFridays = Array.from({ length: 10 }, (_, i) => {
        const today = new Date();
        const day = today.getDay();
        const diff = ((5 - day + 7) % 7) + i * 7;
        const nextFriday = new Date(today);
        nextFriday.setDate(today.getDate() + diff);
        nextFriday.setHours(0, 0, 0, 0);
        return nextFriday.getTime();
      });

      const nextTenFridayTimestamps = nextFridays.map(d => Math.floor(d / 1000));
      console.log("nextTenFridayTimestamps", nextTenFridayTimestamps);
      console.log("expTimestamp", expTimestamp);
      const fmtDate = moment(expirationDate).format("YYYYMMDD");
      console.log("fmtDate", fmtDate);

      const optionType = isPut ? "P" : "C";
      const baseNameSymbol = `OPT${optionType}-${collateralToken.symbol}-${considerationToken.symbol}-${fmtDate}`;
      const longNames = strikeIntegers.map(strikeInteger => `L${baseNameSymbol}-${strikeInteger}`);
      const shortNames = strikeIntegers.map(strikeInteger => `S${baseNameSymbol}-${strikeInteger}`);
      console.log("longNames", longNames);
      console.log("shortNames", shortNames);
      console.log("collateralToken.address", collateralToken.address);
      console.log("considerationToken.address", considerationToken.address);
      console.log("expTimestamp", expTimestamp);
      console.log("strikeIntegers", strikeIntegers);
      console.log("isPut", isPut);

      const options = longNames.map((longName, i) => ({
        longSymbol: longName,
        shortSymbol: shortNames[i],
        collateral: collateralToken.address,
        consideration: considerationToken.address,
        expiration: BigInt(expTimestamp),
        strike: strikeIntegers[i],
        isPut,
      }));

      allOptions.push(...options);
    }

    try {
      writeContract(
        {
          address: contractAddress,
          abi,
          functionName: "createOptions",
          args: [allOptions],
        },
        {
          onSuccess: () => {
            console.log("committed transaction", hash);
            refetchOptions();
          },
        },
      );
    } catch (error) {
      console.error("Error creating option:", error);
      alert("Failed to create option. Check console for details.");
    }
  };

  const handleStrikePricesChange = (value: string) => {
    // Split by comma or newline, filter out empty, and parse to number
    const strikes = value
      .split(/[\n,]+/)
      .map(s => s.trim())
      .filter(Boolean)
      .map(Number)
      .filter(n => !isNaN(n));
    setStrikePrices(strikes);
  };

  moment.tz.setDefault("Europe/London");

  return (
    <div className="max-w-2xl mx-auto bg-black/80 border border-gray-800 rounded-lg shadow-lg p-6 text-lg">
      <div className="flex flex-col space-y-6">
        <DesignHeader />

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
                    <span className="text-blue-100">{isPut ? "Put" : "Call"} Option Holder swaps</span>
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
                !isConnected ||
                !collateralToken ||
                !considerationToken ||
                !strikePrices ||
                !expirationDates ||
                isPending
                  ? "bg-blue-300 cursor-not-allowed"
                  : "bg-blue-500 hover:bg-blue-600"
              }`}
              onClick={handleCreateOption}
              disabled={
                !isConnected ||
                !collateralToken ||
                !considerationToken ||
                !strikePrices ||
                !expirationDates ||
                isPending
              }
            >
              {isPending ? "Creating..." : isSuccess ? "Created!" : "Create Option"}
            </button>
          </div>
        </div>

        {isSuccess && (
          <div className="text-green-500 text-sm">Option creation submitted successfully! Transaction hash: {hash}</div>
        )}
      </div>
    </div>
  );
};

export default Create;
