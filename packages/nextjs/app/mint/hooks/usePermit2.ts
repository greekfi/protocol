import { Address } from "viem";
import { useSignTypedData } from "wagmi";

const PERMIT2_ADDRESS = "0x000000000022D473030F116dDEE9F6B43aC78BA3";

export const usePermit2 = () => {
  const { signTypedDataAsync } = useSignTypedData();

  const getPermitSignature = async (token: Address, amount: bigint, spender: Address) => {
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600); // 1 hour from now
    const nonce = BigInt(Math.floor(Math.random() * 1000000)); // You might want to get this from the contract

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
      chainId: 1, // You'll need to get this from your wagmi config
      verifyingContract: PERMIT2_ADDRESS,
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
