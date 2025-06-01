import LongOptionABI from "./abi/LongOption_metadata.json";
import erc20abi from "./erc20.abi.json";
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
  console.log("collateralAddress", collateralAddress);
  setCollateralAddress(collateralAddress as Address);

  const { data: considerationAddress } = useReadContract({
    address: optionAddress as `0x${string}`,
    abi: longAbi,
    functionName: "consideration",
    query: {
      enabled: !!optionAddress,
    },
  });
  console.log("consideration", considerationAddress);
  setConsiderationAddress(considerationAddress as Address);

  const { data: collateralDecimals } = useReadContract({
    address: collateralAddress as `0x${string}`,
    abi: erc20abi,
    functionName: "decimals",
    query: {
      enabled: !!collateralAddress,
    },
  });
  console.log("collateralDecimals", collateralDecimals);
  setCollateralDecimals(collateralDecimals as number);

  const { data: considerationDecimals } = useReadContract({
    address: considerationAddress as `0x${string}`,
    abi: erc20abi,
    functionName: "decimals",
    query: {
      enabled: !!considerationAddress,
    },
  });
  console.log("considerationDecimals", considerationDecimals);
  setConsiderationDecimals(considerationDecimals as number);

  const { data: expirationDate } = useReadContract({
    address: optionAddress,
    abi: longAbi,
    functionName: "expirationDate",
    query: {
      enabled: !!optionAddress,
    },
  });

  const isExpired = expirationDate ? Date.now() / 1000 > (expirationDate as number) : false;
  setIsExpired(isExpired);

  const { data: shortAddress } = useReadContract({
    address: optionAddress,
    abi: longAbi,
    functionName: "shortOption",
    query: {
      enabled: !!optionAddress,
    },
  });
  console.log("shortAddress", shortAddress);
  setShortAddress(shortAddress as Address);

  console.log("balance");
  console.log(balance);
  return <div className="text-blue-300">{balance?.toString()}</div>;
};

export default ContractDetails;
