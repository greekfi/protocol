// Import ABIs and addresses
import { useContract } from "./contract";
import { Address, erc20Abi } from "viem";
import { useAccount, useReadContract } from "wagmi";

export const useOptionDetails = (longAddress: Address) => {
  const userAccount = useAccount();
  const abi = useContract()?.LongOption?.abi;
  // Fetch details for selected option

  const { data: shortAddress } = useReadContract({
    address: longAddress as Address,
    functionName: "shortOption",
    abi,
    query: {
      enabled: !!longAddress,
    },
  });

  const { data: collateralAddress } = useReadContract({
    address: longAddress as Address,
    functionName: "collateral",
    abi,
    query: {
      enabled: !!longAddress,
    },
  });

  const { data: considerationAddress } = useReadContract({
    address: longAddress as Address,
    functionName: "consideration",
    abi,
    query: {
      enabled: !!longAddress,
    },
  });

  const { data: longName } = useReadContract({
    address: longAddress as Address,
    functionName: "name",
    abi,
    query: {
      enabled: !!longAddress,
    },
  });
  const { data: collateralName } = useReadContract({
    address: collateralAddress as Address,
    functionName: "name",
    abi: erc20Abi,
    query: {
      enabled: !!collateralAddress,
    },
  });

  const { data: considerationName } = useReadContract({
    address: considerationAddress as Address,
    functionName: "name",
    abi: erc20Abi,
    query: {
      enabled: !!considerationAddress,
    },
  });

  const { data: collateralDecimals } = useReadContract({
    address: collateralAddress as Address,
    functionName: "decimals",
    abi: erc20Abi,
    query: {
      enabled: !!collateralAddress,
    },
  });

  const { data: considerationDecimals } = useReadContract({
    address: considerationAddress as Address,
    functionName: "decimals",
    abi: erc20Abi,
    query: {
      enabled: !!considerationAddress,
    },
  });

  const { data: balanceShort } = useReadContract({
    address: shortAddress as Address,
    functionName: "balanceOf",
    args: [userAccount.address as Address],
    abi,
    query: {
      enabled: !!shortAddress,
    },
  });

  const { data: balanceLong } = useReadContract({
    address: longAddress as Address,
    functionName: "balanceOf",
    args: [userAccount.address as Address],
    abi,
    query: {
      enabled: !!longAddress,
    },
  });

  const { data: balanceCollateral } = useReadContract({
    address: collateralAddress as Address,
    functionName: "balanceOf",
    args: [userAccount.address as Address],
    abi: erc20Abi,
    query: {
      enabled: !!collateralAddress,
    },
  });

  const { data: balanceConsideration } = useReadContract({
    address: considerationAddress as Address,
    functionName: "balanceOf",
    args: [userAccount.address as Address],
    abi: erc20Abi,
    query: {
      enabled: !!considerationAddress,
    },
  });

  const { data: expirationDate } = useReadContract({
    address: longAddress as Address,
    functionName: "expirationDate",
    abi,
    query: {
      enabled: !!longAddress,
    },
  });

  const isExpired = expirationDate ? Date.now() / 1000 > Number(expirationDate) : false;

  console.log("balanceLong", balanceLong);
  console.log("balanceShort", balanceShort);
  console.log("balanceCollateral", balanceCollateral);
  console.log("balanceConsideration", balanceConsideration);
  console.log("expirationDate", expirationDate);
  console.log("isExpired", isExpired);
  console.log("longAddress", longAddress);
  console.log("shortAddress", shortAddress);
  console.log("collateralAddress", collateralAddress);
  console.log("considerationAddress", considerationAddress);
  console.log("collateralName", collateralName);
  console.log("considerationName", considerationName);
  console.log("collateralDecimals", collateralDecimals);
  console.log("longName", longName);

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
    formatOptionName: formatOptionName(longName || ""),
    longAddress: longAddress,
    balanceLong: balanceLong,
    shortAddress: shortAddress,
    balanceShort: balanceShort,
    collateralAddress: collateralAddress,
    collateralName: collateralName,
    collateralDecimals: collateralDecimals,
    collateralBalance: balanceCollateral,
    considerationAddress: considerationAddress,
    considerationName: considerationName,
    considerationDecimals: considerationDecimals,
    considerationBalance: balanceConsideration,
    expirationDate: expirationDate,
    isExpired: isExpired,
  };
};

export default useOptionDetails;
