// modes/direct.ts
import { Pricer } from "../pricing/pricer";
import { createHttpApi } from "../servers/httpApi";
import { createWsStream } from "../servers/wsStream";

export async function startDirectMode(pricer: Pricer) {
  const httpPort = parseInt(process.env.HTTP_PORT || "3010");
  const wsPort = parseInt(process.env.WS_PORT || "3011");

  // Start HTTP API
  const httpServer = createHttpApi(pricer);
  httpServer.listen(httpPort);
  console.log(`HTTP API listening on port ${httpPort}`);

  // Start WebSocket broadcast
  const wsServer = createWsStream(pricer);
  wsServer.listen(wsPort);
  console.log(`WebSocket stream on port ${wsPort}`);
}
