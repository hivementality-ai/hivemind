/**
 * Hivemind Connector — Signal CLI REST API Bridge
 *
 * Polls the signal-cli REST API for incoming messages, forwards them to the
 * Hivemind Rails app webhook, and exposes send endpoints.
 *
 * Requires a running signal-cli-rest-api sidecar (bbernhard/signal-cli-rest-api).
 */

const pino = require("pino");
const logger = pino({ level: "info" });

class SignalBridge {
  constructor({ phoneNumber, apiUrl, hivemindUrl, channelId, deviceName }) {
    this.phoneNumber = phoneNumber;
    this.apiUrl = apiUrl || "http://signal-cli:8080";
    this.hivemindUrl = hivemindUrl || "http://app:3000";
    this.channelId = channelId;
    this.deviceName = deviceName || "hivemind";
    this.polling = false;
    this.registered = false;
    // disconnected | linking | qr_ready | connected
    this.connectionStatus = "disconnected";
    this.currentQR = null; // data URL (PNG) of the device-linking QR
    this.linkWatcher = null;
  }

  async start() {
    const ok = await this.checkRegistration();
    if (ok) {
      this.registered = true;
      this.connectionStatus = "connected";
      this.currentQR = null;
      logger.info(
        { phoneNumber: this.phoneNumber, apiUrl: this.apiUrl },
        "Signal bridge authenticated"
      );
      this.polling = true;
      this.poll();
      logger.info("Signal bridge started");
      return;
    }

    // Not yet registered/linked — enter linking mode and generate a QR so the
    // user can link this device from Signal → Settings → Linked Devices.
    logger.warn(
      "Signal: account not linked yet — entering device-linking mode"
    );
    await this.beginLinking();
  }

  async stop() {
    this.polling = false;
    if (this.linkWatcher) {
      clearTimeout(this.linkWatcher);
      this.linkWatcher = null;
    }
    logger.info("Signal bridge stopped");
  }

  async checkRegistration() {
    try {
      const response = await fetch(
        `${this.apiUrl}/v1/accounts`
      );
      if (!response.ok) return false;
      const accounts = await response.json();
      // /v1/accounts returns an array of registered numbers.
      if (Array.isArray(accounts)) {
        if (this.phoneNumber) {
          return accounts.includes(this.phoneNumber);
        }
        // No number configured yet: linked if any account exists.
        if (accounts.length > 0) {
          this.phoneNumber = this.phoneNumber || accounts[0];
          return true;
        }
        return false;
      }
      return false;
    } catch {
      return false;
    }
  }

  // Fetch a device-linking QR code from signal-cli and cache it as a data URL.
  async fetchLinkQR() {
    const url = `${this.apiUrl}/v1/qrcodelink?device_name=${encodeURIComponent(
      this.deviceName
    )}`;
    const response = await fetch(url);
    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new Error(`qrcodelink failed: ${response.status} ${body}`);
    }
    const contentType = response.headers.get("content-type") || "image/png";
    const buf = Buffer.from(await response.arrayBuffer());
    this.currentQR = `data:${contentType};base64,${buf.toString("base64")}`;
    this.connectionStatus = "qr_ready";
    logger.info("Signal: device-linking QR ready — scan via UI");
    return this.currentQR;
  }

  // Generate a QR and poll until the device finishes linking.
  async beginLinking() {
    this.registered = false;
    this.connectionStatus = "linking";
    try {
      await this.fetchLinkQR();
    } catch (err) {
      logger.error({ err }, "Signal: failed to generate linking QR");
      this.connectionStatus = "disconnected";
      throw err;
    }
    this.watchForLink();
  }

  // Poll registration; once the user scans the QR, signal-cli registers the
  // account and we transition to connected + start the receive loop.
  watchForLink() {
    if (this.linkWatcher) clearTimeout(this.linkWatcher);
    const tick = async () => {
      if (this.connectionStatus === "connected" || this.registered) return;
      const ok = await this.checkRegistration();
      if (ok) {
        this.registered = true;
        this.connectionStatus = "connected";
        this.currentQR = null;
        logger.info("Signal: device linked — starting message polling");
        if (!this.polling) {
          this.polling = true;
          this.poll();
        }
        return;
      }
      this.linkWatcher = setTimeout(tick, 3000);
    };
    this.linkWatcher = setTimeout(tick, 3000);
  }

  // Force a fresh linking QR (used by "reconnect").
  async relink() {
    this.polling = false;
    this.registered = false;
    this.currentQR = null;
    await this.beginLinking();
    return { status: this.connectionStatus };
  }

  async poll() {
    while (this.polling) {
      try {
        const response = await fetch(
          `${this.apiUrl}/v1/receive/${encodeURIComponent(this.phoneNumber)}`
        );

        if (response.ok) {
          const messages = await response.json();
          for (const msg of messages) {
            await this.handleMessage(msg);
          }
        }
      } catch (err) {
        if (err.name !== "AbortError") {
          logger.error({ err }, "Signal polling error");
          await new Promise((r) => setTimeout(r, 5000));
        }
      }

      // Poll interval
      await new Promise((r) => setTimeout(r, 2000));
    }
  }

  async handleMessage(msg) {
    const envelope = msg.envelope;
    if (!envelope) return;

    const dataMessage = envelope.dataMessage;
    if (!dataMessage || !dataMessage.message) return;

    logger.info(
      {
        from: envelope.source,
        text: dataMessage.message.substring(0, 100),
      },
      "Signal message received"
    );

    try {
      await this.forwardToHivemind(msg);
    } catch (err) {
      logger.error(
        { err, from: envelope.source },
        "Failed to forward to Hivemind"
      );
    }
  }

  async forwardToHivemind(msg) {
    const url = `${this.hivemindUrl}/webhooks/signal`;

    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(msg),
    });

    if (!response.ok) {
      throw new Error(`Hivemind webhook returned ${response.status}`);
    }

    logger.info(
      { from: msg.envelope?.source },
      "Forwarded to Hivemind"
    );
  }

  async sendMessage({ to, text }) {
    const body = {
      message: text,
      number: this.phoneNumber,
      recipients: [to],
    };

    const response = await fetch(`${this.apiUrl}/v2/send`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const errBody = await response.text();
      throw new Error(`Signal API error: ${response.status} ${errBody}`);
    }

    logger.info({ to }, "Signal message sent");
    return { status: "sent" };
  }

  get status() {
    return {
      status: this.connectionStatus,
      polling: this.polling,
      registered: this.registered,
      hasQR: !!this.currentQR,
      phoneNumber: this.phoneNumber,
      apiUrl: this.apiUrl,
    };
  }

  get qr() {
    return this.currentQR;
  }
}

module.exports = { SignalBridge };
