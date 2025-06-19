import { useOptionDetails } from "./hooks/useGetDetails";

const ContractDetails = ({ details }: { details: ReturnType<typeof useOptionDetails> }) => {
  const isValidOptionAddress = Boolean(details.longAddress && details.longAddress !== "0x0");

  const {
    collateralAddress,
    considerationAddress,
    collateralDecimals,
    considerationDecimals,
    expirationDate,
    formatOptionName,
    balanceShort,
    balanceLong,
    collateralBalance,
    considerationBalance,
    collateralName,
    considerationName,
    shortAddress,
  } = details;

  if (!isValidOptionAddress) {
    return <div className="text-blue-300">No option selected</div>;
  }
  return (
    <div className="text-blue-300">
      <div>Option Name: {formatOptionName}</div>
      <div>Balance Long: {balanceLong}</div>
      <div>Balance Short: {balanceShort}</div>
      <div>Collateral Name: {collateralName}</div>
      <div>Collateral Address: {collateralAddress}</div>
      <div>Collateral Decimals: {collateralDecimals}</div>
      <div>Balance Collateral: {collateralBalance}</div>
      <div>Consideration Name: {considerationName}</div>
      <div>Consideration Address: {considerationAddress}</div>
      <div>Consideration Decimals: {considerationDecimals}</div>
      <div>Balance Consideration: {considerationBalance}</div>
      <div>Short Address: {shortAddress}</div>
      <div>
        Expired: {expirationDate ? (Date.now() / 1000 > (expirationDate as unknown as number) ? "Yes" : "No") : "No"}
      </div>
      <div>Expiration Date: {expirationDate ? new Date(Number(expirationDate) * 1000).toUTCString() : "N/A"}</div>
    </div>
  );
};

export default ContractDetails;
