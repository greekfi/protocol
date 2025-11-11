import { useOptionDetails } from "./hooks/useGetOption";

const ContractDetails = ({ details }: { details: ReturnType<typeof useOptionDetails> }) => {
  const isValidOptionAddress = Boolean(details?.option && details.option.address_ !== "0x0");

  if (!details || !isValidOptionAddress) {
    return <div className="text-blue-300">No option selected</div>;
  }
  return (
    <details className="text-blue-300">
      <summary className="cursor-pointer">Show Contract Details</summary>
      <div className="mt-2">
        <div>Option Name: {details?.formatOptionName}</div>
        <div>Option Address: {details.option.address_}</div>
        <div>Option Symbol: {details.option.symbol}</div>
        <div>Balance Long: {details.balances?.option}</div>
        <div>Redemption Address: {details.redemption.address_}</div>
        <div>Balance Redemption: {details.balances?.redemption}</div>
        <div>Collateral Name: {details.collateral.name}</div>
        <div>Collateral Address: {details.collateral.address_}</div>
        <div>Collateral Decimals: {details.collateral.decimals}</div>
        <div>Balance Collateral: {details.balances?.collateral}</div>
        <div>Consideration Name: {details.consideration.name}</div>
        <div>Consideration Address: {details.consideration.address_}</div>
        <div>Consideration Decimals: {details.consideration.decimals}</div>
        <div>Balance Consideration: {details.balances?.consideration}</div>
        <div>Expired: {details.isExpired ? "Yes" : "No"}</div>
        <div>
          Expiration Date: {details.expiration ? new Date(Number(details.expiration) * 1000).toUTCString() : "N/A"}
        </div>
      </div>
    </details>
  );
};

export default ContractDetails;
