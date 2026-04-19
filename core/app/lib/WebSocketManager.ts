/**
 * WebSocketManager - Generic WebSocket connection manager
 *
 * Base class for WebSocket connections with automatic reconnection,
 * ping/pong keepalive, and lifecycle management.
 *
 * No React dependencies - pure JavaScript class.
 */
export abstract class WebSocketManager<TMessage = any> {
  protected ws: WebSocket | null = null;
  private enabled: boolean = false;
  private reconnectAttempts = 0;
  private reconnectTimeout: NodeJS.Timeout | null = null;
  private pingInterval: NodeJS.Timeout | null = null;
  private readonly maxReconnectAttempts = 10;
  private readonly pingIntervalMs = 30000;

  constructor(
    protected wsUrl: string,
    protected onConnectionChange: (connected: boolean) => void,
    protected onError: (error: string | null) => void
  ) {}

  /**
   * Enable the connection and start connecting
   */
  enable() {
    if (this.enabled) return;
    this.enabled = true;
    this.connect();
  }

  /**
   * Disable the connection and clean up
   */
  disable() {
    this.enabled = false;
    this.disconnect();
  }

  /**
   * Check if WebSocket is connected
   */
  isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  /**
   * Clean up all resources
   */
  destroy() {
    this.enabled = false;
    this.disconnect();
  }

  /**
   * Send message to server
   */
  protected send(message: object) {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  /**
   * Subclasses implement this to handle connection open
   */
  protected abstract onOpen(): void;

  /**
   * Subclasses implement this to handle incoming messages
   */
  protected abstract handleMessage(message: TMessage): void;

  /**
   * Establish WebSocket connection
   */
  private connect() {
    if (!this.enabled || !this.wsUrl) return;

    // Clean up existing connection
    if (this.ws) {
      this.ws.close();
    }

    try {
      this.ws = new WebSocket(this.wsUrl);

      this.ws.onopen = () => {
        console.log(`📡 Connected to ${this.wsUrl}`);
        this.onConnectionChange(true);
        this.onError(null);
        this.reconnectAttempts = 0;

        // Call subclass hook
        this.onOpen();

        // Start ping interval
        this.startPing();
      };

      this.ws.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data);
          this.handleMessage(message);
        } catch (err) {
          console.error("Failed to parse WebSocket message:", err);
        }
      };

      this.ws.onclose = (event) => {
        console.log(`📡 Disconnected: ${event.code}`);
        this.onConnectionChange(false);
        this.ws = null;
        this.stopPing();

        // Schedule reconnection with exponential backoff
        if (this.enabled && this.reconnectAttempts < this.maxReconnectAttempts) {
          this.scheduleReconnect();
        }
      };

      this.ws.onerror = (event) => {
        console.error("📡 WebSocket error:", event);
        this.onError("WebSocket connection error");
      };
    } catch (err) {
      console.error("Failed to connect:", err);
      this.onError(`Failed to connect: ${(err as Error).message}`);
    }
  }

  /**
   * Disconnect and clean up
   */
  private disconnect() {
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }
    this.stopPing();
    if (this.ws) {
      // Only close if connection is established or failed
      if (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CLOSED) {
        this.ws.close();
      } else if (this.ws.readyState === WebSocket.CONNECTING) {
        // If still connecting, wait for it to finish before closing
        const ws = this.ws;
        const closeAfterConnect = () => {
          ws.close();
          ws.removeEventListener('open', closeAfterConnect);
          ws.removeEventListener('error', closeAfterConnect);
        };
        ws.addEventListener('open', closeAfterConnect);
        ws.addEventListener('error', closeAfterConnect);
      }
      this.ws = null;
    }
  }

  /**
   * Schedule reconnection with exponential backoff
   */
  private scheduleReconnect() {
    const delay = Math.min(1000 * Math.pow(2, this.reconnectAttempts), 30000);
    console.log(`📡 Reconnecting in ${delay}ms (attempt ${this.reconnectAttempts + 1})`);

    this.reconnectTimeout = setTimeout(() => {
      this.reconnectAttempts++;
      this.connect();
    }, delay);
  }

  /**
   * Start ping interval to keep connection alive
   */
  private startPing() {
    this.stopPing();

    this.pingInterval = setInterval(() => {
      this.send({ type: "ping" });
    }, this.pingIntervalMs);
  }

  /**
   * Stop ping interval
   */
  private stopPing() {
    if (this.pingInterval) {
      clearInterval(this.pingInterval);
      this.pingInterval = null;
    }
  }
}
