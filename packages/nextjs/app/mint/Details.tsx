import { useOptionDetails } from "./hooks/useGetOption";

const ContractDetails = ({ details }: { details: ReturnType<typeof useOptionDetails> }) => {
  const isValidOptionAddress = Boolean(details?.longOption && details.longOption !== "0x0");

  const {
    formatOptionName,
    balanceLong,
    balanceShort,
    collName,
    collateral,
    collDecimals,
    balanceCollateral,
    consName,
    consideration,
    consDecimals,
    balanceConsideration,
    shortOption,
    expirationDate,
  } = details || {};

  if (!details || !isValidOptionAddress) {
    return <div className="text-blue-300">No option selected</div>;
  }
  return (
    <details className="text-blue-300">
      <summary className="cursor-pointer">Show Contract Details</summary>
      <div className="mt-2">
        <div>Option Name: {formatOptionName}</div>
        <div>Option Address: {details.longOption}</div>
        <div>Option Symbol: {details.symbol}</div>
        <div>Balance Long: {balanceLong}</div>
        <div>Short Address: {shortOption}</div>
        <div>Balance Short: {balanceShort}</div>
        <div>Collateral Name: {collName}</div>
        <div>Collateral Address: {collateral}</div>
        <div>Collateral Decimals: {collDecimals}</div>
        <div>Balance Collateral: {balanceCollateral}</div>
        <div>Consideration Name: {consName}</div>
        <div>Consideration Address: {consideration}</div>
        <div>Consideration Decimals: {consDecimals}</div>
        <div>Balance Consideration: {balanceConsideration}</div>
        <div>
          Expired: {expirationDate ? (Date.now() / 1000 > (expirationDate as unknown as number) ? "Yes" : "No") : "No"}
        </div>
        <div>Expiration Date: {expirationDate ? new Date(Number(expirationDate) * 1000).toUTCString() : "N/A"}</div>
      </div>
    </details>
  );
};

export default ContractDetails;
