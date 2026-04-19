import "../../styles/globals.css";
import { Providers } from "../providers";
import "@rainbow-me/rainbowkit/styles.css";
import { GeistMono } from "geist/font/mono";
import { GeistSans } from "geist/font/sans";
import { ThemeProvider } from "next-themes";
import { PricingProvider } from "../contexts/PricingContext";

export const metadata = {
  title: "Trade Options - Greek.fi",
  description: "Trade options on secondary markets via Bebop",
};

export default function TradeLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${GeistSans.variable} ${GeistMono.variable}`} suppressHydrationWarning>
      <body>
        <ThemeProvider attribute="class" defaultTheme="dark" enableSystem>
          <Providers>
            <PricingProvider enabled={true}>
              <div className="min-h-screen">{children}</div>
            </PricingProvider>
          </Providers>
        </ThemeProvider>
      </body>
    </html>
  );
}
