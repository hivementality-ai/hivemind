/**
 * Hivemind Connector — WhatsApp Bridge
 *
 * Connects to WhatsApp Web via Baileys, forwards messages to the
 * Hivemind Rails app webhook, and exposes a REST API for sending replies.
 *
 * Environment variables:
 *   HIVEMIND_URL     — Rails app URL (default: http://app:3000)
 *   CONNECTOR_PORT   — Port for the REST API (default: 3002)
 *   AUTH_STORE_PATH  — Where to store WhatsApp auth state (default: ./auth)
 */

const {
  default: makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
  makeCacheableSignalKeyStore,
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

      logger.info(
        { statusCode, shouldReconnect },
        "Connection closed"
      );

      connectionStatus = "disconnected";
      if (shouldReconnect) {
        connectionStatus = "connecting";
        setTimeout(startWhatsApp, 3000);
      } else {
        logger.info("Logged out — delete auth/ folder and restart to re-pair");
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
      // Skip messages we sent (bot replies) — but allow user self-messages
      if (msg.key.fromMe && sentMessageIds.has(msg.key.id)) continue;
      if (msg.key.fromMe && !msg.key.remoteJid?.includes(sock?.user?.id?.split(":")[0])) continue;

      const text =
        msg.message?.conversation ||
        msg.message?.extendedTextMessage?.text ||
        "";

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
                    type: "text",
                    timestamp: message.timestamp,
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

function normalizeJid(input) {
  // Strip non-digits, add @s.whatsapp.net if needed
  const cleaned = input.replace(/[^0-9@.]/g, "");
  if (cleaned.includes("@")) return cleaned;
  return `${cleaned}@s.whatsapp.net`;
}

// ─── Start ────────────────────────────────────────────────────────────

startWhatsApp().catch((err) => {
  logger.error({ err }, "Failed to start WhatsApp connection");
  process.exit(1);
});
