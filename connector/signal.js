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
  constructor({ phoneNumber, apiUrl, hivemindUrl, channelId }) {
    this.phoneNumber = phoneNumber;
    this.apiUrl = apiUrl || "http://signal-cli:8080";
    this.hivemindUrl = hivemindUrl || "http://app:3000";
    this.channelId = channelId;
    this.polling = false;
    this.registered = false;
  }

  async start() {
    try {
      const ok = await this.checkRegistration();
      if (!ok) {
        logger.error("Signal: phone number not registered with signal-cli");
        throw new Error("Phone number not registered");
      }
      this.registered = true;
      logger.info(
        { phoneNumber: this.phoneNumber, apiUrl: this.apiUrl },
        "Signal bridge authenticated"
      );
    } catch (err) {
      logger.error({ err }, "Failed to connect to Signal CLI");
      throw err;
    }

    this.polling = true;
    this.poll();
    logger.info("Signal bridge started");
  }

  async stop() {
    this.polling = false;
    logger.info("Signal bridge stopped");
  }

  async checkRegistration() {
    try {
      const response = await fetch(
        `${this.apiUrl}/v1/accounts/${encodeURIComponent(this.phoneNumber)}`
      );
      return response.ok;
    } catch {
      return false;
    }
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
      polling: this.polling,
      registered: this.registered,
      phoneNumber: this.phoneNumber,
      apiUrl: this.apiUrl,
    };
  }
}

module.exports = { SignalBridge };
