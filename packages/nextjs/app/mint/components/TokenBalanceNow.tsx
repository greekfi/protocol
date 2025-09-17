import { formatUnits } from "viem";

interface TokenBalanceProps {
  symbol: string | "" | undefined;
  balance: bigint | 0n | undefined;
  decimals: number | undefined;
  label: string;
}

const TokenBalance = ({ symbol, balance, decimals, label }: TokenBalanceProps) => {
  const formattedBalance = formatUnits((balance as bigint) ?? 0n, decimals ?? 18);

  return (
    <div className="text-sm text-gray-400 mb-2">
      <div>{label}</div>
      <div className="text-gray-500">{symbol}</div>
      <div className="text-blue-300">{formattedBalance}</div>
    </div>
  );
};

export default TokenBalance;
