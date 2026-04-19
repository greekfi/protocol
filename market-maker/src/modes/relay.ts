// modes/relay.ts
import { BebopRelay } from "../bebop/relay";
import { createWsRelay } from "../servers/wsRelay";

export async function startRelayMode() {
  const chains = (process.env.BEBOP_CHAINS || "ethereum").split(",");
  const name = process.env.BEBOP_MARKETMAKER || "market-maker";
  const authorization = process.env.BEBOP_AUTHORIZATION || "";

  // Connect to Bebop pricing feeds
  const relay = new BebopRelay({
    chains,
    name,
    authorization
  });
  await relay.start();

  // Start local WebSocket server
  const wsServer = createWsRelay(relay);
  const port = parseInt(process.env.RELAY_WS_PORT || process.env.PORT || "3004");

  // The server already starts listening in the constructor
  console.log(`Bebop relay listening on port ${port}`);
}
