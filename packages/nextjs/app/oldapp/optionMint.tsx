import LongOptionABI from "./abi/LongOption_metadata.json";
import OptionInterface from "./components/OptionInterface";
import erc20abi from "./erc20.abi.json";
import { Abi, Address, parseUnits } from "viem";
import { useWriteContract } from "wagmi";

const longAbi = LongOptionABI.output.abi as Abi;

const MintInterface = ({
  optionAddress,
  shortAddress,
  collateralAddress,
  collateralDecimals,
  isExpired,
}: {
  optionAddress: Address;
  shortAddress: Address;
  collateralAddress: Address;
  collateralDecimals: number;
  isExpired: boolean;
}) => {
  const { writeContract } = useWriteContract();

  const handleApprove = async () => {
    const approveToken = {
      address: collateralAddress as `0x${string}`,
      abi: erc20abi,
      functionName: "approve",
      args: [shortAddress, parseUnits("0", Number(collateralDecimals))],
    };
    writeContract(approveToken);
  };

  return (
    <OptionInterface
      title="Mint Options"
      description="Mint new options by providing collateral"
      tokenAddress={collateralAddress}
      tokenDecimals={collateralDecimals}
      tokenLabel="Collateral Balance"
      contractAddress={optionAddress}
      contractAbi={longAbi}
      functionName="mint"
      isExpired={isExpired}
      onApprove={handleApprove}
      showApproveButton={true}
    />
  );
};

export default MintInterface;
