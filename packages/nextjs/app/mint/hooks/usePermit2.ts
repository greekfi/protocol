import { useGetNonce } from "./useGetNonce";
import { Address } from "viem";
import { useChainId, useSignTypedData } from "wagmi";

const PERMIT2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3";

export const usePermit2 = (token: Address, spender: Address) => {
  const { signTypedDataAsync } = useSignTypedData();
  const chainId = useChainId();
  const nonce = useGetNonce(token, spender);

  const getPermitSignature = async (amount: bigint) => {
    const deadline = Math.floor(Date.now() / 1000) + 3600; // 1 hour from now

    const permitDetails = {
      details: {
        token,
        amount,
        expiration: deadline,
        nonce,
      },
      spender,
      sigDeadline: deadline,
    };

    const domain = {
      name: "Permit2",
      chainId,
      verifyingContract: PERMIT2_ADDRESS,
      version: "1",
    };

    const types = {
      PermitDetails: [
        { name: "token", type: "address" },
        { name: "amount", type: "uint160" },
        { name: "expiration", type: "uint48" },
        { name: "nonce", type: "uint48" },
      ],
      PermitSingle: [
        { name: "details", type: "PermitDetails" },
        { name: "spender", type: "address" },
        { name: "sigDeadline", type: "uint256" },
      ],
    };

    const signature = await signTypedDataAsync({
      domain,
      types,
      primaryType: "PermitSingle",
      message: permitDetails,
    });

    return { permitDetails, signature };
  };

  return { getPermitSignature };
};
