import { PricingProvider } from "../contexts/PricingContext";

export const metadata = {
  title: "Trade Options - Greek.fi",
  description: "Trade options on secondary markets via Bebop",
};

export default function TradeLayout({ children }: { children: React.ReactNode }) {
  return <PricingProvider enabled={true}>{children}</PricingProvider>;
}
