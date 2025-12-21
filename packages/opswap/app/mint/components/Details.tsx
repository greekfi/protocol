import type { OptionDetails } from "../hooks/types";

const ContractDetails = ({ details }: { details: OptionDetails | null }) => {
  const isValidOptionAddress = Boolean(details?.option && details.option !== "0x0");

  if (!details || !isValidOptionAddress) {
    return <div className="text-blue-300">No option selected</div>;
  }
  return (
    <details className="text-blue-300">
      <summary className="cursor-pointer">Show Contract Details</summary>
      <div className="mt-2">
        <div>Option Name: {details?.formattedName}</div>
        <div>Option Address: {details.option}</div>
        <div>Balance Long: {details.balances?.option?.toString()}</div>
        <div>Redemption Address: {details.redemption}</div>
        <div>Balance Redemption: {details.balances?.redemption?.toString()}</div>
        <div>Collateral Name: {details.collateral.name}</div>
        <div>Collateral Address: {details.collateral.address_}</div>
        <div>Collateral Symbol: {details.collateral.symbol}</div>
        <div>Collateral Decimals: {details.collateral.decimals}</div>
        <div>Balance Collateral: {details.balances?.collateral?.toString()}</div>
        <div>Consideration Name: {details.consideration.name}</div>
        <div>Consideration Address: {details.consideration.address_}</div>
        <div>Consideration Symbol: {details.consideration.symbol}</div>
        <div>Consideration Decimals: {details.consideration.decimals}</div>
        <div>Balance Consideration: {details.balances?.consideration?.toString()}</div>
        <div>Expired: {details.isExpired ? "Yes" : "No"}</div>
        <div>
          Expiration Date: {details.expiration ? new Date(Number(details.expiration) * 1000).toUTCString() : "N/A"}
        </div>
      </div>
    </details>
  );
};

export default ContractDetails;
