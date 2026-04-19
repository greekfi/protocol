// @ts-nocheck
import { UNIVERSAL_ROUTER_ABI } from "./abi";
import permit2Abi from "./permit2.json";
import { useAddress } from "./useAddress";
import { useContract } from "./useContract";
import { CommandType, RoutePlanner } from "@uniswap/universal-router-sdk";
import { Actions, SwapExactInSingle, V4Planner } from "@uniswap/v4-sdk";
import { parseUnits } from "viem";
import { useWriteContract } from "wagmi";

export const useBuyOption = () => {
  const contract = useContract();
  const { writeContract } = useWriteContract();
  const address = useAddress();

  return (amount: number, optionAddress: string) => {
    const zeroForOne = address.tokens.usdc.address < optionAddress;
    const currency0 = zeroForOne ? address.tokens.usdc.address : optionAddress;
    const currency1 = zeroForOne ? optionAddress : address.tokens.usdc.address;
    const currentConfig: SwapExactInSingle = {
      poolKey: {
        currency0: currency0,
        currency1: currency1,
        fee: 0,
        tickSpacing: 32767,
        hooks: contract?.OpHook.address as `0x${string}`,
      },
      zeroForOne: zeroForOne, // The direction of swap is USDC to ETH. Change it to 'false' for the reverse direction
      amountIn: parseUnits(amount.toString(), address.tokens.usdc.decimals).toString(),
      amountOutMinimum: "0", // Change according to the slippage desired
      hookData: "0x",
    };

    const planner = new V4Planner();
    const routePlanner = new RoutePlanner();
    // Set deadline (1 hour from now)
    const deadline = Math.floor(Date.now() / 1000) + 3600;

    const currencyTake = zeroForOne ? currentConfig.poolKey.currency1 : currentConfig.poolKey.currency0;
    const currencySettle = zeroForOne ? currentConfig.poolKey.currency0 : currentConfig.poolKey.currency1;

    planner.addAction(Actions.SWAP_EXACT_IN_SINGLE, [currentConfig]);
    planner.addAction(Actions.SETTLE_ALL, [currencySettle, currentConfig.amountIn]);
    planner.addAction(Actions.TAKE_ALL, [currencyTake, currentConfig.amountOutMinimum]);

    const encodedActions = planner.finalize();
    routePlanner.addCommand(CommandType.V4_SWAP, [planner.actions, planner.params]);
    const approveAbi = [
      {
        constant: false,
        inputs: [
          {
            name: "_spender",
            type: "address",
          },
          {
            name: "_value",
            type: "uint256",
          },
        ],
        name: "approve",
        outputs: [
          {
            name: "",
            type: "bool",
          },
        ],
        payable: false,
        stateMutability: "nonpayable",
        type: "function",
      },
    ];
    const expiry = Math.floor(Date.now() / 1000) + 36000;
    writeContract({
      address: address.tokens.usdc.address,
      abi: approveAbi,
      functionName: "approve",
      args: [address.contracts.permit2, currentConfig.amountIn],
    });
    writeContract({
      address: address.contracts.permit2,
      abi: permit2Abi,
      functionName: "approve",
      args: [address.tokens.usdc.address, address.contracts.universalRouter, currentConfig.amountIn, expiry], // expiration is uint48
    });
    writeContract({
      address: address.contracts.universalRouter,
      functionName: "execute",
      abi: UNIVERSAL_ROUTER_ABI,
      args: [routePlanner.commands, [encodedActions], deadline],
    });
  };
};
