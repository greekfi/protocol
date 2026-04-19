import "../../styles/globals.css";
import { Providers } from "../providers";
import "@rainbow-me/rainbowkit/styles.css";
import { GeistMono } from "geist/font/mono";
import { GeistSans } from "geist/font/sans";
import { ThemeProvider } from "next-themes";

export const metadata = {
  title: "Options Trading - Greek.fi",
  description: "Trade options with RFQ pricing and on-chain settlement",
};

export default function OptionsLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${GeistSans.variable} ${GeistMono.variable}`} suppressHydrationWarning>
      <body>
        <ThemeProvider attribute="class" defaultTheme="dark" enableSystem>
          <Providers>
            <div className="min-h-screen">{children}</div>
          </Providers>
        </ThemeProvider>
      </body>
    </html>
  );
}
