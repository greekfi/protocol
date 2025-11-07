import { connectorsForWallets } from "@rainbow-me/rainbowkit";
import {
  coinbaseWallet,
  metaMaskWallet,
  rainbowWallet,
  walletConnectWallet,
} from "@rainbow-me/rainbowkit/wallets";
import scaffoldConfig from "~~/scaffold.config";

const wallets = [
  metaMaskWallet,
  walletConnectWallet,
  coinbaseWallet,
  rainbowWallet,
];

/**
 * wagmi connectors for the wagmi context
 */
export const wagmiConnectors = connectorsForWallets(
  [
    {
      groupName: "Supported Wallets",
      wallets,
    },
  ],
  {
    appName: "opswap",
    projectId: scaffoldConfig.walletConnectProjectId,
  },
);
