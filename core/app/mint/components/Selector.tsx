// Import ABIs and addresses
import { OptionListItem } from "../hooks/types";
import { Address } from "viem";

const SelectOptionAddress = ({
  setOptionAddress,
  optionList,
}: {
  setOptionAddress: (address: Address) => void;
  optionList: OptionListItem[];
}) => {
  console.log("optionList", optionList);

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
      <h2 className="text-xl font-light text-blue-300 mb-4">Select Option</h2>
      <div className="flex flex-col gap-4 w-full">
        <div className="flex justify-center w-full">
          <select
            className=" p-2 text-center rounded-lg border border-gray-800 bg-black/60 text-blue-300 w-64"
            onChange={e => setOptionAddress(e.target.value as Address)}
          >
            <option value="">Select an option</option>
            {optionList.map(option => (
              <option key={option.address} value={option.address || ""}>
                {(() => {
                  const name = String(option.name || "");
                  const parts = name.split("-");
                  if (parts.length < 5) return name;

                  const optionType = option.isPut ? "PUT" : "CALL";
                  const collateral = parts[1];
                  const consideration = parts[2];
                  const dateStr = parts[3];
                  const strike = option.isPut ? BigInt(1e18) / option.strike : option.strike / BigInt(1e18);

                  // Format date from YYYYMMDD to ISO
                  const year = dateStr.substring(0, 4);
                  const month = dateStr.substring(4, 6);
                  const day = dateStr.substring(6, 8);

                  const formattedDate = new Date(Number(option.expiration) * 1000).toISOString().split("T")[0]; // convert  from epoch to ISO date

                  if (option.isPut) {
                    return ` ${optionType} ${strike} ${collateral} ${consideration} ${formattedDate}  : swap 1 ${consideration} receive  ${strike} ${collateral} `;
                  } else {
                    return ` ${optionType} ${strike} ${collateral} ${consideration} ${formattedDate} : swap ${strike} ${consideration} receive  1 ${collateral} `;
                  }
                })()}
              </option>
            ))}
          </select>
        </div>
      </div>
    </div>
  );
};

export default SelectOptionAddress;
