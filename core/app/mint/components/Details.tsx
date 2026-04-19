import type { OptionDetails } from "../hooks/types";

/**
 * Format token balance with proper decimals
 */
function formatBalance(balance: bigint | undefined, decimals: number): string {
  if (!balance) return "0";
  const divisor = BigInt(10 ** decimals);
  const whole = balance / divisor;
  const fraction = balance % divisor;

  // Pad fraction with leading zeros
  const fractionStr = fraction.toString().padStart(decimals, "0");
  // Remove trailing zeros
  const trimmedFraction = fractionStr.replace(/0+$/, "");

  if (trimmedFraction === "") {
    return whole.toString();
  }
  return `${whole}.${trimmedFraction}`;
}

const ContractDetails = ({ details }: { details: OptionDetails | null }) => {
  const isValidOptionAddress = Boolean(details?.option && details.option !== "0x0");

  if (!details || !isValidOptionAddress) {
    return <div className="text-blue-300">No option selected</div>;
  }

  // Option/Redemption tokens use collateral decimals
  const optionDecimals = details.collateral.decimals;

  return (
    <details className="text-blue-300">
      <summary className="cursor-pointer">Show Contract Details</summary>
      <div className="mt-2">
        <div>Option Name: {details?.formattedName}</div>
        <div>Option Address: {details.option}</div>
        <div>
          Balance Long: {formatBalance(details.balances?.option, optionDecimals)} {details.collateral.symbol}
        </div>
        <div>Redemption Address: {details.redemption}</div>
        <div>
          Balance Redemption: {formatBalance(details.balances?.redemption, optionDecimals)} {details.collateral.symbol}
        </div>
        <div>Collateral Name: {details.collateral.name}</div>
        <div>Collateral Address: {details.collateral.address_}</div>
        <div>Collateral Symbol: {details.collateral.symbol}</div>
        <div>Collateral Decimals: {details.collateral.decimals}</div>
        <div>
          Balance Collateral: {formatBalance(details.balances?.collateral, details.collateral.decimals)}{" "}
          {details.collateral.symbol}
        </div>
        <div>Consideration Name: {details.consideration.name}</div>
        <div>Consideration Address: {details.consideration.address_}</div>
        <div>Consideration Symbol: {details.consideration.symbol}</div>
        <div>Consideration Decimals: {details.consideration.decimals}</div>
        <div>
          Balance Consideration: {formatBalance(details.balances?.consideration, details.consideration.decimals)}{" "}
          {details.consideration.symbol}
        </div>
        <div>Expired: {details.isExpired ? "Yes" : "No"}</div>
        <div>
          Expiration Date: {details.expiration ? new Date(Number(details.expiration) * 1000).toUTCString() : "N/A"}
        </div>
      </div>
    </details>
  );
};

export default ContractDetails;
