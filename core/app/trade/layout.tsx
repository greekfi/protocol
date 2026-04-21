import { PricingProvider } from "../contexts/PricingContext";

export const metadata = {
  title: "Trade Options - Greek.fi",
  description: "Trade options on secondary markets via Bebop",
};

// Gate on NEXT_PUBLIC_ENABLE_PRICING_STREAM to avoid noisy ws://:3004 reconnect
// spam when no relay is running. Default off until we migrate to HTTP polling.
const pricingEnabled = process.env.NEXT_PUBLIC_ENABLE_PRICING_STREAM === "true";

export default function TradeLayout({ children }: { children: React.ReactNode }) {
  return <PricingProvider enabled={pricingEnabled}>{children}</PricingProvider>;
}
