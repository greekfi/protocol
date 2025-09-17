// Import ABIs and addresses
import { useContract } from "./useContract";
import { Address } from "viem";
import { useAccount, useReadContract } from "wagmi";

export const useOptionDetails = (longAddress: Address) => {
  const userAccount = useAccount();
  const abi = useContract()?.LongOption?.abi;
  // Fetch details for selected option

  const { data } = useReadContract({
    address: longAddress as Address,
    functionName: "details",
    abi,
    query: {
      enabled: !!longAddress,
    },
  });

  const { data: balances } = useReadContract({
    address: longAddress as Address,
    functionName: "balancesOf",
    abi,
    args: [userAccount.address as Address],
    query: {
      enabled: !!longAddress,
    },
  });

  const isExpired = data?.expirationDate ? Date.now() / 1000 > Number(data.expirationDate) : false;

  console.log("data", data);

  // Format option name for display
  const formatOptionName = (name: string) => {
    const parts = name.split("-");
    if (parts.length < 5) return name;

    const optionType = parts[0].endsWith("P") ? "PUT" : "CALL";
    const collateral = parts[1];
    const consideration = parts[2];
    const dateStr = parts[3];
    const strike = parseFloat(parts[4]);

    // Format date from YYYYMMDD to ISO
    const year = dateStr.substring(0, 4);
    const month = dateStr.substring(4, 6);
    const day = dateStr.substring(6, 8);
    const formattedDate = `${year}-${month}-${day}`;

    if (optionType === "PUT") {
      return `${formattedDate} ${optionType}  : swap 1 ${consideration} for  ${strike} ${collateral} `;
    } else {
      return `${formattedDate} ${optionType}: swap ${strike} ${consideration} for 1 ${collateral} `;
    }
  };

  if (!data) return null;
  return {
    ...data,
    formatOptionName: formatOptionName(data.name || ""),
    isExpired,
    balanceCollateral: balances ? balances[0] : 0n,
    balanceConsideration: balances ? balances[1] : 0n,
    balanceLong: balances ? balances[2] : 0n,
    balanceShort: balances ? balances[3] : 0n,
  };
};

export default useOptionDetails;
