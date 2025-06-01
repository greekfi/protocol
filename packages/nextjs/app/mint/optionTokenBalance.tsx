import erc20abi from "./erc20.abi.json";
// import { Statistic } from 'antd';
import { Address, formatUnits } from "viem";
import { useReadContract } from "wagmi";

const TokenBalance = ({
  userAddress,
  tokenAddress,
  label,
  decimals,
}: {
  userAddress: `0x${string}`;
  tokenAddress: `0x${string}`;
  decimals: number;
  label: string;
  watch?: boolean;
}) => {
  const { data: balance = 0n } = useReadContract({
    address: tokenAddress as Address,
    abi: erc20abi,
    functionName: "balanceOf",
    args: [userAddress],
  });

  const { data: decimals_ } = useReadContract({
    address: tokenAddress as Address,
    abi: erc20abi,
    functionName: "decimals",
  });
  if (!decimals) {
    decimals = decimals_ as number;
  }
  // console.log("decimals", decimals);

  const { data: name = "" } = useReadContract({
    address: tokenAddress as Address,
    abi: erc20abi,
    functionName: "name",
  });

  return (
    <div className="flex flex-col">
      <div className="flex flex-col text-sm text-gray-600">
        <div>{label}</div>
        <div>{name as string}</div>
      </div>
      <div className="text-2xl font-semibold">
        {Number(formatUnits(balance as bigint, decimals)).toFixed(
          Number(formatUnits(balance as bigint, decimals)) % 1 === 0 ? 0 : 3,
        )}
      </div>
    </div>
  );
};
export default TokenBalance;
