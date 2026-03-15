/**
 * Hivemind Connector — Telegram Bot Long Polling Bridge
 *
 * Connects to Telegram Bot API via long polling, forwards messages to the
 * Hivemind Rails app webhook, and exposes send/react endpoints.
 *
 * Environment variables:
 *   TELEGRAM_BOT_TOKEN — Telegram Bot Token from @BotFather
 *   HIVEMIND_URL       — Rails app URL (default: http://app:3000)
 */

const pino = require("pino");
const logger = pino({ level: "info" });

class TelegramBridge {
  constructor({ botToken, hivemindUrl, channelId }) {
    this.botToken = botToken;
    this.hivemindUrl = hivemindUrl || "http://app:3000";
    this.channelId = channelId;
    this.baseUrl = `https://api.telegram.org/bot${this.botToken}`;
    this.offset = 0;
    this.polling = false;
    this.botInfo = null;
  }

  async start() {
    try {
      const me = await this.apiCall("getMe");
      this.botInfo = me.result;
      logger.info(
        { botId: this.botInfo.id, username: this.botInfo.username },
        "Telegram bot authenticated"
      );
    } catch (err) {
      logger.error({ err }, "Failed to authenticate with Telegram");
      throw err;
    }

    this.polling = true;
    this.poll();
    logger.info("Telegram bridge started");
  }

  async stop() {
    this.polling = false;
    logger.info("Telegram bridge stopped");
  }

  async poll() {
    while (this.polling) {
      try {
        const data = await this.apiCall("getUpdates", {
          offset: this.offset,
          timeout: 30,
          allowed_updates: ["message", "edited_message"],
        });

        if (data.ok && data.result.length > 0) {
          for (const update of data.result) {
            this.offset = update.update_id + 1;
            await this.handleUpdate(update);
          }
        }
      } catch (err) {
        if (err.name !== "AbortError") {
          logger.error({ err }, "Telegram polling error");
          // Back off on error
          await new Promise((r) => setTimeout(r, 5000));
        }
      }
    }
  }

  async handleUpdate(update) {
    const msg = update.message || update.edited_message;
    if (!msg) return;

    // Skip messages from bots (including ourselves)
    if (msg.from?.is_bot) return;

    const text = msg.text || msg.caption || "";
    if (!text.trim()) return;

    logger.info(
      {
        from: msg.from?.id,
        chat: msg.chat?.id,
        text: text.substring(0, 100),
      },
      "Telegram message received"
    );

    try {
      await this.forwardToHivemind(update);
    } catch (err) {
      logger.error(
        { err, from: msg.from?.id },
        "Failed to forward to Hivemind"
      );
    }
  }

  async forwardToHivemind(update) {
    const url = `${this.hivemindUrl}/webhooks/telegram`;

    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(update),
    });

    if (!response.ok) {
      throw new Error(`Hivemind webhook returned ${response.status}`);
    }

    logger.info(
      { from: (update.message || update.edited_message)?.from?.id },
      "Forwarded to Hivemind"
    );
  }

  async sendMessage({ chatId, text, replyToMessageId, parseMode }) {
    const body = {
      chat_id: chatId,
      text,
      parse_mode: parseMode || "Markdown",
    };
    if (replyToMessageId) body.reply_to_message_id = replyToMessageId;

    const result = await this.apiCall("sendMessage", body);
    logger.info({ chatId, messageId: result.result?.message_id }, "Telegram message sent");
    return result;
  }

  async sendPhoto({ chatId, photo, caption, replyToMessageId }) {
    const body = { chat_id: chatId, photo };
    if (caption) body.caption = caption;
    if (replyToMessageId) body.reply_to_message_id = replyToMessageId;

    const result = await this.apiCall("sendPhoto", body);
    logger.info({ chatId, messageId: result.result?.message_id }, "Telegram photo sent");
    return result;
  }

  async setReaction({ chatId, messageId, emoji }) {
    const body = {
      chat_id: chatId,
      message_id: messageId,
      reaction: [{ type: "emoji", emoji }],
    };

    const result = await this.apiCall("setMessageReaction", body);
    return result;
  }

  async apiCall(method, body = null) {
    const url = `${this.baseUrl}/${method}`;
    const options = {
      method: body ? "POST" : "GET",
      headers: { "Content-Type": "application/json" },
    };
    if (body) options.body = JSON.stringify(body);

    const response = await fetch(url, options);
    const data = await response.json();

    if (!data.ok) {
      throw new Error(`Telegram API error: ${data.description}`);
    }

    return data;
  }

  get status() {
    return {
      polling: this.polling,
      botId: this.botInfo?.id || null,
      botUsername: this.botInfo?.username || null,
    };
  }
}

module.exports = { TelegramBridge };
