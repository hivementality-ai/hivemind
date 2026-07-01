/**
 * Hivemind Connector — Multi-Platform Messaging Bridge
 *
 * Connects to WhatsApp (Baileys) and Slack (Socket Mode), forwards messages
 * to the Hivemind Rails app webhook, and exposes a REST API for sending replies.
 *
 * Environment variables:
 *   HIVEMIND_URL          — Rails app URL (default: http://app:3000)
 *   CONNECTOR_PORT        — Port for the REST API (default: 3002)
 *   AUTH_STORE_PATH       — Where to store WhatsApp auth state (default: ./auth)
 *   SLACK_APP_TOKEN       — Slack App-Level Token (xapp-...) for Socket Mode
 *   SLACK_BOT_TOKEN       — Slack Bot User OAuth Token (xoxb-...)
 *   TELEGRAM_BOT_TOKEN    — Telegram Bot Token from @BotFather
 *   SIGNAL_PHONE_NUMBER   — Phone number registered with signal-cli
 *   SIGNAL_API_URL        — signal-cli REST API URL (default: http://signal-cli:8080)
 */

const {
  default: makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
  makeCacheableSignalKeyStore,
  downloadMediaMessage,
} = require("@whiskeysockets/baileys");
const express = require("express");
const pino = require("pino");
const qrcode = require("qrcode-terminal");
const QRCode = require("qrcode");
const fs = require("fs");
const path = require("path");

const HIVEMIND_URL = process.env.HIVEMIND_URL || "http://app:3000";
const PORT = parseInt(process.env.CONNECTOR_PORT || "3002", 10);
const AUTH_PATH = process.env.AUTH_STORE_PATH || "./auth";

const logger = pino({ level: "info" });
let sock = null;
let currentQR = null; // Raw QR string for generating images
let connectionStatus = "disconnected"; // disconnected, qr_ready, connecting, connected
const sentMessageIds = new Set(); // Track messages we sent to avoid echo loops

// ─── Express API (for Hivemind to send outbound messages) ─────────────

const app = express();
app.use(express.json());

// CORS for Hivemind UI
app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Headers", "Content-Type");
  res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  if (req.method === "OPTIONS") return res.sendStatus(200);
  next();
});

// Health + status
app.get("/health", (req, res) => {
  res.json({
    status: connectionStatus,
    user: sock?.user?.id || null,
    userName: sock?.user?.name || null,
    hasQR: !!currentQR,
  });
});

// Get QR code as base64 PNG data URL
app.get("/qr", async (req, res) => {
  if (!currentQR) {
    return res.json({ status: connectionStatus, qr: null });
  }

  try {
    const dataUrl = await QRCode.toDataURL(currentQR, {
      width: 300,
      margin: 2,
      color: { dark: "#000000", light: "#ffffff" },
    });
    res.json({ status: "qr_ready", qr: dataUrl });
  } catch (err) {
    res.status(500).json({ error: "Failed to generate QR" });
  }
});

// Get QR code as PNG image directly
app.get("/qr.png", async (req, res) => {
  if (!currentQR) {
    return res.status(404).send("No QR code available");
  }

  try {
    res.type("png");
    await QRCode.toFileStream(res, currentQR, { width: 400, margin: 2 });
  } catch (err) {
    res.status(500).send("Failed to generate QR");
  }
});

// Send a message
app.post("/send", async (req, res) => {
  try {
    const { to, message, type = "text" } = req.body;
    if (!to || !message) {
      return res.status(400).json({ error: "to and message required" });
    }

    // Normalize phone number to WhatsApp JID
    const jid = normalizeJid(to);

    let sentMsg;
    if (type === "text") {
      sentMsg = await sock.sendMessage(jid, { text: message });
    }

    // Track sent message ID to prevent echo loops
    if (sentMsg?.key?.id) {
      sentMessageIds.add(sentMsg.key.id);
      // Clean up after 60 seconds
      setTimeout(() => sentMessageIds.delete(sentMsg.key.id), 60000);
    }

    logger.info({ to: jid }, "Message sent");
    res.json({ status: "sent", to: jid });
  } catch (err) {
    logger.error({ err }, "Failed to send message");
    res.status(500).json({ error: err.message });
  }
});

// React to a message
app.post("/react", async (req, res) => {
  try {
    const { to, messageId, emoji } = req.body;
    if (!to || !messageId || !emoji) {
      return res.status(400).json({ error: "to, messageId, and emoji required" });
    }

    const jid = normalizeJid(to);
    await sock.sendMessage(jid, {
      react: { text: emoji, key: { remoteJid: jid, id: messageId } },
    });

    res.json({ status: "reacted" });
  } catch (err) {
    logger.error({ err }, "Failed to react");
    res.status(500).json({ error: err.message });
  }
});

// Start WhatsApp connection (for initial pairing via UI)
app.post("/connect", async (req, res) => {
  if (connectionStatus === "connected") {
    return res.json({ status: "already_connected", user: sock?.user?.id });
  }
  if (connectionStatus === "qr_ready" || connectionStatus === "connecting") {
    return res.json({ status: connectionStatus, hasQR: !!currentQR });
  }

  try {
    startWhatsApp();
    res.json({ status: "connecting", message: "WhatsApp connecting — scan QR at /qr" });
  } catch (err) {
    logger.error({ err }, "Failed to start WhatsApp");
    res.status(500).json({ error: err.message });
  }
});

// Logout and force new QR code
app.post("/logout", async (req, res) => {
  try {
    // Close the socket first to release file handles
    if (sock) {
      sock.ev.removeAllListeners();
      sock.end(undefined);
      sock = null;
    }

    // Small delay to let file handles release
    await new Promise(r => setTimeout(r, 500));

    // Wipe auth state to force fresh QR
    if (fs.existsSync(AUTH_PATH)) {
      // Remove files inside auth dir individually to avoid EBUSY on dir
      const files = fs.readdirSync(AUTH_PATH);
      for (const file of files) {
        fs.unlinkSync(`${AUTH_PATH}/${file}`);
      }
      fs.rmdirSync(AUTH_PATH);
    }

    currentQR = null;
    connectionStatus = "disconnected";
    logger.info("Logged out and wiped auth state");

    // Restart connection to generate new QR
    setTimeout(() => startWhatsApp(), 1500);

    res.json({ status: "logged_out", message: "Auth wiped. New QR code will be generated." });
  } catch (err) {
    logger.error({ err }, "Failed to logout");
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => {
  logger.info({ port: PORT }, "Connector API listening");
});

// ─── WhatsApp Connection ──────────────────────────────────────────────

async function startWhatsApp() {
  // Ensure auth directory exists
  if (!fs.existsSync(AUTH_PATH)) {
    fs.mkdirSync(AUTH_PATH, { recursive: true });
  }

  const { state, saveCreds } = await useMultiFileAuthState(AUTH_PATH);
  const { version } = await fetchLatestBaileysVersion();

  sock = makeWASocket({
    version,
    auth: {
      creds: state.creds,
      keys: makeCacheableSignalKeyStore(state.keys, logger),
    },
    logger: pino({ level: "silent" }),
    printQRInTerminal: false,
    generateHighQualityLinkPreview: false,
  });

  // QR code for pairing
  sock.ev.on("connection.update", async (update) => {
    const { connection, lastDisconnect, qr } = update;

    if (qr) {
      currentQR = qr;
      connectionStatus = "qr_ready";
      logger.info("QR code ready — scan via UI at /qr or see below:");
      qrcode.generate(qr, { small: true });
    }

    if (connection === "close") {
      currentQR = null;
      const statusCode =
        lastDisconnect?.error?.output?.statusCode;
      const shouldReconnect = statusCode !== DisconnectReason.loggedOut;

      // Only auto-reconnect if we have auth state (previously paired).
      // Without auth state, reconnecting just generates QR codes endlessly.
      const hasAuthState = fs.existsSync(AUTH_PATH) &&
        fs.readdirSync(AUTH_PATH).some(f => f.startsWith("creds"));

      logger.info(
        { statusCode, shouldReconnect, hasAuthState },
        "Connection closed"
      );

      connectionStatus = "disconnected";
      if (shouldReconnect && hasAuthState) {
        connectionStatus = "connecting";
        setTimeout(startWhatsApp, 3000);
      } else if (!hasAuthState) {
        logger.info("No auth state — waiting for pairing via POST /connect");
      } else {
        logger.info("Logged out — use POST /connect to re-pair");
      }
    }

    if (connection === "open") {
      currentQR = null;
      connectionStatus = "connected";
      logger.info({ user: sock.user?.id }, "WhatsApp connected!");
    }
  });

  // Save credentials on update
  sock.ev.on("creds.update", saveCreds);

  // Handle incoming messages
  sock.ev.on("messages.upsert", async ({ messages }) => {
    for (const msg of messages) {
      // Skip status broadcasts
      if (msg.key.remoteJid === "status@broadcast") continue;
      // Skip ALL messages sent by us (fromMe) to prevent echo loops
      if (msg.key.fromMe) continue;

      // Check for voice/audio messages
      const isAudio = !!(msg.message?.audioMessage);
      let text = "";
      let audioFilePath = null;

      if (isAudio) {
        try {
          audioFilePath = await downloadVoiceMessage(msg);
          text = "[Voice Message]";
        } catch (err) {
          logger.error({ err }, "Failed to download voice message");
          continue;
        }
      } else {
        text =
          msg.message?.conversation ||
          msg.message?.extendedTextMessage?.text ||
          "";
      }

      if (!text) continue;

      const sender = msg.key.remoteJid;
      const senderName =
        msg.pushName || sender.replace(/@.*/, "");

      logger.info(
        { sender, senderName, text: text.substring(0, 100) },
        "Incoming message"
      );

      // Forward to Hivemind webhook
      try {
        await forwardToHivemind({
          id: msg.key.id,
          from: sender,
          fromName: senderName,
          text,
          timestamp: msg.messageTimestamp,
          isGroup: sender.endsWith("@g.us"),
        });
      } catch (err) {
        logger.error({ err, sender }, "Failed to forward to Hivemind");
      }
    }
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────

async function forwardToHivemind(message) {
  const url = `${HIVEMIND_URL}/webhooks/whatsapp`;

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      entry: [
        {
          changes: [
            {
              value: {
                messages: [
                  {
                    id: message.id,
                    from: message.from,
                    text: { body: message.text },
                    type: message.isAudio ? "audio" : "text",
                    timestamp: message.timestamp,
                    ...(message.audioFilePath ? { audio: { file_path: message.audioFilePath } } : {}),
                  },
                ],
                metadata: {
                  phone_number_id: sock?.user?.id || "connector",
                  display_phone_number: sock?.user?.id || "connector",
                },
                contacts: [
                  {
                    profile: { name: message.fromName },
                    wa_id: message.from,
                  },
                ],
              },
            },
          ],
        },
      ],
    }),
  });

  if (!response.ok) {
    throw new Error(`Hivemind webhook returned ${response.status}`);
  }

  logger.info({ from: message.from }, "Forwarded to Hivemind");
}


async function downloadVoiceMessage(msg) {
  const buffer = await downloadMediaMessage(msg, "buffer", {});
  const voiceDir = path.join(AUTH_PATH, "..", "voice_messages");
  if (!fs.existsSync(voiceDir)) {
    fs.mkdirSync(voiceDir, { recursive: true });
  }
  const ext = msg.message?.audioMessage?.mimetype?.includes("ogg") ? "ogg" : "mp4";
  const filePath = path.join(voiceDir, `${msg.key.id}.${ext}`);
  fs.writeFileSync(filePath, buffer);
  logger.info({ filePath }, "Voice message downloaded");
  return filePath;
}

function normalizeJid(input) {
  // Strip non-digits, add @s.whatsapp.net if needed
  const cleaned = input.replace(/[^0-9@.]/g, "");
  if (cleaned.includes("@")) return cleaned;
  return `${cleaned}@s.whatsapp.net`;
}

// ─── Slack Socket Mode ────────────────────────────────────────────────

const { SlackBridge } = require("./slack");
let slackBridge = null;

// Slack API endpoints
app.get("/slack/health", (req, res) => {
  if (!slackBridge) {
    return res.json({ status: "not_configured" });
  }
  res.json({ status: "connected", ...slackBridge.status });
});

app.post("/slack/send", async (req, res) => {
  try {
    if (!slackBridge) {
      return res.status(400).json({ error: "Slack not configured" });
    }
    const { channel, text, thread_ts } = req.body;
    if (!channel || !text) {
      return res.status(400).json({ error: "channel and text required" });
    }
    const result = await slackBridge.sendMessage({ channel, text, threadTs: thread_ts });
    res.json({ status: "sent", ts: result.ts });
  } catch (err) {
    logger.error({ err }, "Failed to send Slack message");
    res.status(500).json({ error: err.message });
  }
});

app.post("/slack/react", async (req, res) => {
  try {
    if (!slackBridge) {
      return res.status(400).json({ error: "Slack not configured" });
    }
    const { channel, timestamp, emoji } = req.body;
    if (!channel || !timestamp || !emoji) {
      return res.status(400).json({ error: "channel, timestamp, and emoji required" });
    }
    await slackBridge.addReaction({ channel, timestamp, emoji });
    res.json({ status: "reacted" });
  } catch (err) {
    logger.error({ err }, "Failed to react on Slack");
    res.status(500).json({ error: err.message });
  }
});

// Configure Slack via API (so Rails can pass tokens from vault)
app.post("/slack/configure", async (req, res) => {
  try {
    const { app_token, bot_token, channel_id } = req.body;
    if (!app_token || !bot_token) {
      return res.status(400).json({ error: "app_token and bot_token required" });
    }

    // Stop existing bridge if running
    if (slackBridge) {
      await slackBridge.stop();
      slackBridge = null;
    }

    slackBridge = new SlackBridge({
      appToken: app_token,
      botToken: bot_token,
      hivemindUrl: HIVEMIND_URL,
      channelId: channel_id,
    });

    await slackBridge.start();
    res.json({ status: "connected", ...slackBridge.status });
  } catch (err) {
    logger.error({ err }, "Failed to configure Slack");
    res.status(500).json({ error: err.message });
  }
});

// ─── Telegram Bot Long Polling ─────────────────────────────────────────

const { TelegramBridge } = require("./telegram");
let telegramBridge = null;

app.get("/telegram/health", (req, res) => {
  if (!telegramBridge) {
    return res.json({ status: "not_configured" });
  }
  res.json({ status: "connected", ...telegramBridge.status });
});

app.post("/telegram/send", async (req, res) => {
  try {
    if (!telegramBridge) {
      return res.status(400).json({ error: "Telegram not configured" });
    }
    const { chat_id, text, reply_to_message_id, parse_mode } = req.body;
    if (!chat_id || !text) {
      return res.status(400).json({ error: "chat_id and text required" });
    }
    const result = await telegramBridge.sendMessage({
      chatId: chat_id,
      text,
      replyToMessageId: reply_to_message_id,
      parseMode: parse_mode,
    });
    res.json({ status: "sent", message_id: result.result?.message_id });
  } catch (err) {
    logger.error({ err }, "Failed to send Telegram message");
    res.status(500).json({ error: err.message });
  }
});

app.post("/telegram/react", async (req, res) => {
  try {
    if (!telegramBridge) {
      return res.status(400).json({ error: "Telegram not configured" });
    }
    const { chat_id, message_id, emoji } = req.body;
    if (!chat_id || !message_id || !emoji) {
      return res.status(400).json({ error: "chat_id, message_id, and emoji required" });
    }
    await telegramBridge.setReaction({ chatId: chat_id, messageId: message_id, emoji });
    res.json({ status: "reacted" });
  } catch (err) {
    logger.error({ err }, "Failed to react on Telegram");
    res.status(500).json({ error: err.message });
  }
});

app.post("/telegram/configure", async (req, res) => {
  try {
    const { bot_token, channel_id } = req.body;
    if (!bot_token) {
      return res.status(400).json({ error: "bot_token required" });
    }

    if (telegramBridge) {
      await telegramBridge.stop();
      telegramBridge = null;
    }

    telegramBridge = new TelegramBridge({
      botToken: bot_token,
      hivemindUrl: HIVEMIND_URL,
      channelId: channel_id,
    });

    await telegramBridge.start();
    res.json({ status: "connected", ...telegramBridge.status });
  } catch (err) {
    logger.error({ err }, "Failed to configure Telegram");
    res.status(500).json({ error: err.message });
  }
});

// ─── Signal CLI Bridge ─────────────────────────────────────────────────

const { SignalBridge } = require("./signal");
let signalBridge = null;

app.get("/signal/health", (req, res) => {
  if (!signalBridge) {
    return res.json({ status: "not_configured" });
  }
  // status already includes connection status, hasQR, registered, etc.
  res.json({ ...signalBridge.status });
});

// Return the current Signal device-linking QR as a PNG data URL.
app.get("/signal/qr", async (req, res) => {
  if (!signalBridge) {
    return res.json({ status: "not_configured", qr: null });
  }
  if (signalBridge.qr) {
    return res.json({ status: signalBridge.status.status, qr: signalBridge.qr });
  }
  // No QR cached yet — try to generate one if we're not already linked.
  if (!signalBridge.registered) {
    try {
      await signalBridge.fetchLinkQR();
      signalBridge.watchForLink();
      return res.json({ status: "qr_ready", qr: signalBridge.qr });
    } catch (err) {
      return res.status(503).json({ status: "error", error: err.message });
    }
  }
  res.json({ status: signalBridge.status.status, qr: null });
});

// Kick off (or refresh) Signal device linking and return a fresh QR.
app.post("/signal/connect", async (req, res) => {
  try {
    if (!signalBridge) {
      return res.status(400).json({ error: "Signal not configured" });
    }
    const result = await signalBridge.relink();
    res.json({ ...result, ...signalBridge.status });
  } catch (err) {
    logger.error({ err }, "Failed to start Signal linking");
    res.status(500).json({ error: err.message });
  }
});

// Logout/reconnect — regenerate a linking QR.
app.post("/signal/logout", async (req, res) => {
  try {
    if (!signalBridge) {
      return res.status(400).json({ error: "Signal not configured" });
    }
    await signalBridge.relink();
    res.json({ status: "logged_out", ...signalBridge.status });
  } catch (err) {
    logger.error({ err }, "Failed to relink Signal");
    res.status(500).json({ error: err.message });
  }
});

app.post("/signal/send", async (req, res) => {
  try {
    if (!signalBridge) {
      return res.status(400).json({ error: "Signal not configured" });
    }
    const { to, text } = req.body;
    if (!to || !text) {
      return res.status(400).json({ error: "to and text required" });
    }
    const result = await signalBridge.sendMessage({ to, text });
    res.json(result);
  } catch (err) {
    logger.error({ err }, "Failed to send Signal message");
    res.status(500).json({ error: err.message });
  }
});

app.post("/signal/configure", async (req, res) => {
  try {
    const { phone_number, api_url, channel_id, device_name } = req.body;

    if (signalBridge) {
      await signalBridge.stop();
      signalBridge = null;
    }

    signalBridge = new SignalBridge({
      phoneNumber: phone_number,
      apiUrl: api_url,
      hivemindUrl: HIVEMIND_URL,
      channelId: channel_id,
      deviceName: device_name,
    });

    // start() connects if already linked, otherwise enters linking mode and
    // generates a QR — it no longer throws when the account isn't registered.
    await signalBridge.start();
    res.json({ ...signalBridge.status });
  } catch (err) {
    logger.error({ err }, "Failed to configure Signal");
    res.status(500).json({ error: err.message });
  }
});

// ─── Start ────────────────────────────────────────────────────────────

// Only auto-start WhatsApp if auth state exists (previously paired).
// Otherwise, wait for user to initiate pairing via POST /connect.
if (fs.existsSync(AUTH_PATH) && fs.readdirSync(AUTH_PATH).length > 0) {
  startWhatsApp().catch((err) => {
    logger.error({ err }, "Failed to start WhatsApp connection");
  });
} else {
  logger.info("No WhatsApp auth state found — waiting for pairing via POST /connect");
}

// Auto-start Slack if env vars are set
if (process.env.SLACK_APP_TOKEN && process.env.SLACK_BOT_TOKEN) {
  slackBridge = new SlackBridge({
    appToken: process.env.SLACK_APP_TOKEN,
    botToken: process.env.SLACK_BOT_TOKEN,
    hivemindUrl: HIVEMIND_URL,
  });
  slackBridge.start().catch((err) => {
    logger.error({ err }, "Failed to start Slack bridge");
  });
}

// Auto-start Telegram if env var is set
if (process.env.TELEGRAM_BOT_TOKEN) {
  telegramBridge = new TelegramBridge({
    botToken: process.env.TELEGRAM_BOT_TOKEN,
    hivemindUrl: HIVEMIND_URL,
  });
  telegramBridge.start().catch((err) => {
    logger.error({ err }, "Failed to start Telegram bridge");
  });
}

// Auto-start Signal if env vars are set
if (process.env.SIGNAL_PHONE_NUMBER) {
  signalBridge = new SignalBridge({
    phoneNumber: process.env.SIGNAL_PHONE_NUMBER,
    apiUrl: process.env.SIGNAL_API_URL || "http://signal-cli:8080",
    hivemindUrl: HIVEMIND_URL,
  });
  signalBridge.start().catch((err) => {
    logger.error({ err }, "Failed to start Signal bridge");
  });
}
