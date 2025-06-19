import { permit2Abi } from "./permit2abi";
import { Address } from "viem";
import { useAccount, useReadContract } from "wagmi";

const PERMIT2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3";

export const useGetNonce = (token: Address, spender: Address) => {
  const userAccount = useAccount();
  const { data: allowanceData } = useReadContract({
    address: PERMIT2_ADDRESS,
    abi: permit2Abi,
    functionName: "allowance",
    args: [userAccount.address as Address, token, spender],
    query: {
      enabled: !!userAccount.address && !!token && !!spender,
    },
  });

  // Extract just the nonce from the allowance tuple [amount, expiration, nonce]
  const nonce = allowanceData ? allowanceData[2] : undefined;

  return nonce;
};
