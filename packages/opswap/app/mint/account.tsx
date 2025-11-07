import * as React from "react";
import Image from "next/image";
import { useAccount, useDisconnect, useEnsAvatar, useEnsName } from "wagmi";

export function Account() {
  const { address } = useAccount();
  const { disconnect } = useDisconnect();
  const { data: ensName } = useEnsName({ address });
  const { data: ensAvatar } = useEnsAvatar({ name: ensName! });
  const [isLoading, setIsLoading] = React.useState(true);

  React.useEffect(() => {
    setIsLoading(false);
  }, []);

  if (isLoading) {
    return (
      <div className="max-w-2xl mx-auto p-6 bg-gray-600 rounded-lg shadow-md">
        <div className="flex flex-col space-y-4">
          <div className="w-full py-3 px-4 bg-gray-500 rounded-lg animate-pulse"></div>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-2xl mx-auto p-6 bg-gray-600 rounded-lg shadow-md">
      {ensAvatar && <Image alt="ENS Avatar" src={ensAvatar} className="w-16 h-16 rounded-full mx-auto mb-4" />}
      {address && (
        <div className="flex flex-col space-y-4">
          <p className="text-gray-100 text-center break-all">{ensName ? `${ensName} (${address})` : address}</p>
        </div>
      )}
      <button
        onClick={() => disconnect()}
        className="w-full py-2 px-4 bg-white border border-gray-700 hover:bg-gray-200 text-black font-medium rounded-lg transition-colors"
      >
        Disconnect
      </button>
    </div>
  );
}
