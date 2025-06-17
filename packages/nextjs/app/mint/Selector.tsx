// Import ABIs and addresses
import { Address, erc20Abi } from "viem";
import { useChainId, useReadContract, useReadContracts } from "wagmi";
import deployedContracts from "~~/contracts/deployedContracts";

const SelectOptionAddress = ({ setOptionAddress }: { setOptionAddress: (address: Address) => void }) => {
  const handleOptionChange = (optionAddress: string) => {
    setOptionAddress(optionAddress as Address);
  };

  const chainId = useChainId();
  const contract = deployedContracts[chainId as keyof typeof deployedContracts];
  const abi = contract.OptionFactory.abi;
  console.log(chainId);

  const { data: createdOptions, error } = useReadContract({
    address: contract.OptionFactory.address,
    abi,
    functionName: "getCreatedOptions",
  });

  console.log("createdOptions", createdOptions);
  console.log("error", error);

  const { data, error: error_ } = useReadContracts({
    contracts: ((createdOptions as Address[]) || [])
      .map((option: Address) =>
        option
          ? {
              address: option,
              abi: erc20Abi,
              functionName: "name",
            }
          : undefined,
      )
      .filter(option => option !== undefined),
    query: {
      enabled: !!createdOptions,
    },
  });
  const optionNames = data || [];
  // combine option names with mint
  const optionList = (optionNames || []).map((option, index) => ({
    name: option.result,
    address: ((createdOptions as Address[]) || [])[index],
  }));

  console.log("error", error_);
  console.log("optionList", optionList);

  return (
    <div className="p-6 bg-black/80 border border-gray-800 rounded-lg shadow-lg">
      <h2 className="text-xl font-light text-blue-300 mb-4">Select Option</h2>
      <div className="flex flex-col gap-4 w-full">
        <div className="flex justify-center w-full">
          <select
            className=" p-2 text-center rounded-lg border border-gray-800 bg-black/60 text-blue-300 w-64"
            onChange={e => handleOptionChange(e.target.value)}
          >
            <option value="">Select an option</option>
            {optionList.map(option => (
              <option key={option.address} value={option.address || ""}>
                {(() => {
                  const name = String(option.name || "");
                  const parts = name.split("-");
                  if (parts.length < 5) return name;

                  const optionType = parts[0].endsWith("P") ? "PUT" : "CALL";
                  const collateral = parts[1];
                  const consideration = parts[2];
                  const dateStr = parts[3];
                  const strike = parseFloat(parts[4]);

                  // Format date from YYYYMMDD to ISO
                  const year = dateStr.substring(0, 4);
                  const month = dateStr.substring(4, 6);
                  const day = dateStr.substring(6, 8);
                  const formattedDate = `${year}-${month}-${day}`;

                  if (optionType === "PUT") {
                    return `${formattedDate} ${optionType}  : swap 1 ${consideration} for  ${strike} ${collateral} `;
                  } else {
                    return `${formattedDate} ${optionType}: swap ${strike} ${consideration} for 1 ${collateral} `;
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
