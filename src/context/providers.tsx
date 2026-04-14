"use client";

import { WagmiConfig, createConfig } from "wagmi";
import { arbitrumSepolia }           from "wagmi/chains";
import { ConnectKitProvider, getDefaultConfig } from "connectkit";

const config = createConfig(
  getDefaultConfig({
    // Target chain: Arbitrum Sepolia testnet
    chains: [arbitrumSepolia],

    // WalletConnect project ID (required for WC wallets)
    walletConnectProjectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID ?? "",

    appName:        "YieldWin",
    appDescription: "No-Loss Lottery powered by Ondo Finance & Chainlink VRF",
    appUrl:         "https://yieldwin.xyz",
    appIcon:        "https://yieldwin.xyz/icon.png",
  })
);

export function Web3Provider({ children }: { children: React.ReactNode }) {
  return (
    <WagmiConfig config={config}>
      <ConnectKitProvider
        theme="midnight"
        options={{
          hideNoWalletCTA:    false,
          walletConnectName:  "Other wallets",
          enforceSupportedChains: true,
        }}
        customTheme={{
          "--ck-connectbutton-background":        "var(--gold-primary)",
          "--ck-connectbutton-color":             "#000000",
          "--ck-connectbutton-hover-background":  "#f0c060",
          "--ck-connectbutton-border-radius":     "8px",
          "--ck-font-family":                     "Syne, sans-serif",
        }}
      >
        {children}
      </ConnectKitProvider>
    </WagmiConfig>
  );
}
