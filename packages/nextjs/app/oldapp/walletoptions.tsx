import * as React from "react";
import { Connector, useConnect } from "wagmi";

// import { Button, Card, Form, Space } from 'antd'

export function WalletOptions() {
  const { connectors, connect } = useConnect();

  return (
    <div className="max-w-2xl mx-auto p-6 bg-gray-600 rounded-lg shadow-md">
      <div className="flex flex-col space-y-4">
        {connectors.map(connector => (
          <WalletOption key={connector.uid} connector={connector} onClick={() => connect({ connector })} />
        ))}
      </div>
    </div>
  );
}

function WalletOption({ connector, onClick }: { connector: Connector; onClick: () => void }) {
  const [ready, setReady] = React.useState(false);

  React.useEffect(() => {
    (async () => {
      const provider = await connector.getProvider();
      setReady(!!provider);
    })();
  }, [connector]);

  return (
    <button
      className={`w-full py-3 px-4 text-gray-800   bg-white border border-gray-300 rounded-lg font-medium 
        ${!ready ? "opacity-50 cursor-not-allowed" : "hover:bg-gray-50 active:bg-gray-100"}`}
      disabled={!ready}
      onClick={onClick}
    >
      {connector.name}
    </button>
  );
}
