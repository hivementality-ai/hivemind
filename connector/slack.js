/**
 * Hivemind Connector — Slack Socket Mode Bridge
 *
 * Connects to Slack via Socket Mode (WebSocket), forwards messages to the
 * Hivemind Rails app webhook, and exposes send/react endpoints.
 *
 * Environment variables:
 *   SLACK_APP_TOKEN  — Slack App-Level Token (xapp-...)
 *   SLACK_BOT_TOKEN  — Slack Bot User OAuth Token (xoxb-...)
 *   HIVEMIND_URL     — Rails app URL (default: http://app:3000)
 */

const { SocketModeClient } = require("@slack/socket-mode");
const { WebClient } = require("@slack/web-api");
const pino = require("pino");

const logger = pino({ level: "info" });

class SlackBridge {
  constructor({ appToken, botToken, hivemindUrl, channelId }) {
    this.appToken = appToken;
    this.botToken = botToken;
    this.hivemindUrl = hivemindUrl || "http://app:3000";
    this.channelId = channelId; // Hivemind channel ID for webhook routing
    this.botUserId = null;

    this.socketClient = new SocketModeClient({ appToken: this.appToken });
    this.webClient = new WebClient(this.botToken);
  }

  async start() {
    // Get our bot user ID so we can ignore our own messages
    try {
      const auth = await this.webClient.auth.test();
      this.botUserId = auth.user_id;
      logger.info({ botUserId: this.botUserId, team: auth.team }, "Slack authenticated");
    } catch (err) {
      logger.error({ err }, "Failed to authenticate with Slack");
      throw err;
    }

    // Listen for message events
    this.socketClient.on("message", async ({ event, ack }) => {
      await ack();

      // Skip bot messages (including our own)
      if (event.bot_id || event.subtype === "bot_message") return;
      if (event.user === this.botUserId) return;

      // Skip message subtypes we don't care about
      if (event.subtype && event.subtype !== "thread_broadcast") return;

      const text = event.text || "";
      if (!text.trim()) return;

      logger.info(
        { user: event.user, channel: event.channel, text: text.substring(0, 100) },
        "Slack message received"
      );

      try {
        await this.forwardToHivemind({
          id: event.client_msg_id || event.ts,
          from: event.user,
          fromName: event.user, // Will be resolved by adapter
          text,
          channel: event.channel,
          threadTs: event.thread_ts || null,
          timestamp: event.ts,
        });
      } catch (err) {
        logger.error({ err, user: event.user }, "Failed to forward to Hivemind");
      }
    });

    // Listen for app_mention events
    this.socketClient.on("app_mention", async ({ event, ack }) => {
      await ack();

      if (event.user === this.botUserId) return;

      const text = event.text || "";
      if (!text.trim()) return;

      logger.info(
        { user: event.user, channel: event.channel, text: text.substring(0, 100) },
        "Slack app_mention received"
      );

      try {
        await this.forwardToHivemind({
          id: event.client_msg_id || event.ts,
          from: event.user,
          fromName: event.user,
          text,
          channel: event.channel,
          threadTs: event.thread_ts || null,
          timestamp: event.ts,
        });
      } catch (err) {
        logger.error({ err, user: event.user }, "Failed to forward to Hivemind");
      }
    });

    // Catch-all for debugging
    this.socketClient.on("slack_event", ({ ack, body }) => {
      logger.info({ type: body?.event?.type, user: body?.event?.user }, "Slack raw event");
    });

    // Connection lifecycle
    this.socketClient.on("connected", () => {
      logger.info("Slack Socket Mode connected");
    });

    this.socketClient.on("disconnected", () => {
      logger.warn("Slack Socket Mode disconnected");
    });

    await this.socketClient.start();
    logger.info("Slack bridge started");
  }

  async stop() {
    await this.socketClient.disconnect();
  }

  async sendMessage({ channel, text, threadTs }) {
    const opts = { channel, text };
    if (threadTs) opts.thread_ts = threadTs;

    const result = await this.webClient.chat.postMessage(opts);
    logger.info({ channel, ts: result.ts }, "Slack message sent");
    return result;
  }

  async addReaction({ channel, timestamp, emoji }) {
    await this.webClient.reactions.add({
      channel,
      timestamp,
      name: emoji.replace(/:/g, ""),
    });
  }

  async forwardToHivemind(message) {
    const url = `${this.hivemindUrl}/webhooks/slack`;

    const payload = {
      type: "event_callback",
      event: {
        type: "message",
        user: message.from,
        text: message.text,
        channel: message.channel,
        ts: message.timestamp,
        thread_ts: message.threadTs,
        client_msg_id: message.id,
      },
      // Include channel routing info
      hivemind_channel_id: this.channelId,
    };

    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      throw new Error(`Hivemind webhook returned ${response.status}`);
    }

    logger.info({ from: message.from, channel: message.channel }, "Forwarded to Hivemind");
  }

  get status() {
    return {
      connected: this.socketClient.connected || false,
      botUserId: this.botUserId,
    };
  }
}

module.exports = { SlackBridge };
