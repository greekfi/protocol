// @ts-nocheck
import "../../styles/globals.css";
import { Providers } from "../providers";
import "@rainbow-me/rainbowkit/styles.css";
import { GeistMono } from "geist/font/mono";
import { GeistSans } from "geist/font/sans";
import { ThemeProvider } from "next-themes";

export const metadata = {
  title: "OpSwap - Options Trading",
  description: "Decentralized options trading powered by Uniswap V4",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${GeistSans.variable} ${GeistMono.variable}`} suppressHydrationWarning>
      <body>
        <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
          <Providers>
            <div className="min-h-screen">{children}</div>
          </Providers>
        </ThemeProvider>
      </body>
    </html>
  );
}
