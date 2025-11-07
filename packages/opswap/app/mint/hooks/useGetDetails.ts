// Import ABIs and addresses
import { useContract } from "./useContract";
import { Address } from "viem";
import { useAccount, useReadContract } from "wagmi";

export const useOptionDetails = (longAddress: Address) => {
  const userAccount = useAccount();
  const abi = useContract()?.Option?.abi;
  // Fetch details for selected option

  const { data: details } = useReadContract({
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
    query: {
      enabled: !!userAccount.address && !!longAddress,
    },
    args: [userAccount.address as Address],
  });

  const isExpired = details?.expiration ? Date.now() / 1000 > Number(details.expiration) : false;

  console.log("balanceLong", balances);
  console.log("details", details);
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

  return {
    formatOptionName: formatOptionName(details?.option.name || ""),
    ...details,
    isExpired,
    balances,
  };
};

export default useOptionDetails;
