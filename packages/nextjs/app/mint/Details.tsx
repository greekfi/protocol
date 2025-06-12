import LongOptionABI from "./abi/LongOption_metadata.json";
import erc20abi from "./erc20.json";
import { Address } from "viem";
import { useAccount, useReadContract } from "wagmi";

const longAbi = LongOptionABI.output.abi;

const ContractDetails = ({
  optionAddress,
  setShortAddress,
  setCollateralAddress,
  setConsiderationAddress,
  setCollateralDecimals,
  setConsiderationDecimals,
  setIsExpired,
}: {
  optionAddress: Address;
  setShortAddress: (address: Address) => void;
  setCollateralAddress: (address: Address) => void;
  setConsiderationAddress: (address: Address) => void;
  setCollateralDecimals: (decimals: number) => void;
  setConsiderationDecimals: (decimals: number) => void;
  setIsExpired: (isExpired: boolean) => void;
}) => {
  const { address } = useAccount();

  const { data: balance } = useReadContract({
    address: optionAddress,
    functionName: "balanceOf",
    args: [address],
  });

  const { data: collateralAddress } = useReadContract({
    address: optionAddress,
    abi: longAbi,
    functionName: "collateral",
    query: {
      enabled: !!optionAddress,
    },
  });

  const { data: considerationAddress } = useReadContract({
    address: optionAddress as `0x${string}`,
    abi: longAbi,
    functionName: "consideration",
    query: {
      enabled: !!optionAddress,
    },
  });

  const { data: collateralDecimals } = useReadContract({
    address: collateralAddress as `0x${string}`,
    abi: erc20abi,
    functionName: "decimals",
    query: {
      enabled: !!collateralAddress,
    },
  });

  const { data: considerationDecimals } = useReadContract({
    address: considerationAddress as `0x${string}`,
    abi: erc20abi,
    functionName: "decimals",
    query: {
      enabled: !!considerationAddress,
    },
  });

  const { data: expirationDate } = useReadContract({
    address: optionAddress,
    abi: longAbi,
    functionName: "expirationDate",
    query: {
      enabled: !!optionAddress,
    },
  });

  const { data: shortAddress } = useReadContract({
    address: optionAddress,
    abi: longAbi,
    functionName: "shortOption",
    query: {
      enabled: !!optionAddress,
    },
  });

  // Update parent state with contract data
  if (collateralAddress) setCollateralAddress(collateralAddress as Address);
  if (considerationAddress) setConsiderationAddress(considerationAddress as Address);
  if (collateralDecimals) setCollateralDecimals(collateralDecimals as number);
  if (considerationDecimals) setConsiderationDecimals(considerationDecimals as number);
  if (expirationDate) setIsExpired(Date.now() / 1000 > (expirationDate as number));
  if (shortAddress) setShortAddress(shortAddress as Address);

  return (
    <div className="text-blue-300">
      <div>Balance: {balance?.toString()}</div>
      <div>Collateral Address: {(collateralAddress as Address)?.toString()}</div>
      <div>Consideration Address: {(considerationAddress as Address)?.toString()}</div>
      <div>Collateral Decimals: {(collateralDecimals as number)?.toString()}</div>
      <div>Consideration Decimals: {(considerationDecimals as number)?.toString()}</div>
      <div>Short Address: {(shortAddress as Address)?.toString()}</div>
      <div>Expired: {expirationDate ? (Date.now() / 1000 > (expirationDate as number) ? "Yes" : "No") : "No"}</div>
    </div>
  );
};

export default ContractDetails;
