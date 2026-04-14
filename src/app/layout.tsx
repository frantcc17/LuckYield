import type { Metadata } from "next";
import "./globals.css";
import { Web3Provider } from "./providers";

export const metadata: Metadata = {
  title:       "YieldWin — No-Loss Lottery",
  description: "Win prizes. Never lose principal. Powered by Ondo Finance & Chainlink VRF.",
  icons: {
    icon: "/favicon.ico",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <Web3Provider>
          {children}
        </Web3Provider>
      </body>
    </html>
  );
}
