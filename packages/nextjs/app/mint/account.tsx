import Image from "next/image";
import { useAccount, useDisconnect, useEnsAvatar, useEnsName } from "wagmi";

export function Account() {
  const { address } = useAccount();
  const { disconnect } = useDisconnect();
  const { data: ensName } = useEnsName({ address });
  const { data: ensAvatar } = useEnsAvatar({ name: ensName! });

  return (
    <div className="max-w-2xl mx-auto p-6 bg-gray-800 rounded-lg shadow-md">
      {ensAvatar && <Image alt="ENS Avatar" src={ensAvatar} className="w-16 h-16 rounded-full mx-auto mb-4" />}
      {address && (
        <div className="p-4 mb-4 bg-black rounded-lg">
          <p className="text-gray-100 text-center break-all">{ensName ? `${ensName} (${address})` : address}</p>
        </div>
      )}
      <button
        onClick={() => disconnect()}
        className="w-full py-2 px-4 bg-white  border border-gray-700 hover:bg-gray-200 text-black font-medium rounded-lg transition-colors"
      >
        Disconnect
      </button>
    </div>
  );
}
