import erc20abi from "../erc20.abi.json";
import { Address, formatUnits } from "viem";
import { useReadContract } from "wagmi";
import { useAccount } from "wagmi";

interface TokenBalanceProps {
  tokenAddress: Address;
  decimals: number;
  label: string;
}

const TokenBalance = ({ tokenAddress, decimals, label }: TokenBalanceProps) => {
  const { address: userAddress } = useAccount();

  const { data: balance = 0n } = useReadContract({
    address: tokenAddress,
    abi: erc20abi,
    functionName: "balanceOf",
    args: [userAddress as `0x${string}`],
    query: {
      enabled: !!tokenAddress && !!userAddress,
    },
  });

  const { data: symbol } = useReadContract({
    address: tokenAddress,
    abi: erc20abi,
    functionName: "symbol",
    query: {
      enabled: !!tokenAddress,
    },
  }) as { data: string };

  const formattedBalance = formatUnits(balance as bigint, decimals);

  return (
    <div className="text-sm text-gray-400 mb-2">
      <div>{label}</div>
      <div className="text-gray-500">{symbol}</div>
      <div className="text-blue-300">{formattedBalance}</div>
    </div>
  );
};

export default TokenBalance;
