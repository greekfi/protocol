import { useTokenMap } from "../../mint/hooks/useTokenMap";

interface TokenSelectorProps {
  selectedToken: string | null;
  onSelectToken: (tokenAddress: string) => void;
}

export function TokenSelector({ selectedToken, onSelectToken }: TokenSelectorProps) {
  const { allTokensMap } = useTokenMap();

  const tokens = Object.values(allTokensMap);

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
      <h2 className="text-xl font-light text-blue-300 mb-4">Select Underlying Token</h2>
      <select
        value={selectedToken || ""}
        onChange={e => onSelectToken(e.target.value)}
        className="w-full p-3 rounded-lg border border-gray-700 bg-black/60 text-blue-300 focus:outline-none focus:border-blue-500"
      >
        <option value="">-- Select a token --</option>
        {tokens.map(token => (
          <option key={token.address} value={token.address}>
            {token.symbol}
          </option>
        ))}
      </select>
      {selectedToken && (
        <div className="mt-3 text-sm text-gray-400">
          Selected:{" "}
          {allTokensMap[Object.keys(allTokensMap).find(k => allTokensMap[k].address === selectedToken) || ""]?.symbol}
        </div>
      )}
    </div>
  );
}
