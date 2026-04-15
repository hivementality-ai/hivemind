import express from "express";
import { chromium } from "playwright";

export const app = express();
app.use(express.json({ limit: "1mb" }));

const PORT = process.env.PORT || 3004;
const NAV_TIMEOUT = 30_000;
const MAX_CONTENT = 30_000;

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: "browser-sidecar" });
});

// Navigate to a URL and extract page content
// POST /navigate  { url: "https://..." }
app.post("/navigate", async (req, res) => {
  const { url } = req.body;
  if (!url) return res.status(400).json({ success: false, error: "url is required" });

  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();

    await page.goto(url, { waitUntil: "domcontentloaded", timeout: NAV_TIMEOUT });

    const title = await page.title();
    const finalUrl = page.url();
    const content = await page.evaluate(() => document.body?.innerText ?? "");

    res.json({
      success: true,
      title,
      url: finalUrl,
      content: content.slice(0, MAX_CONTENT),
    });
  } catch (err) {
    res.json({ success: false, error: err.message });
  } finally {
    await browser?.close();
  }
});

// Take a screenshot of a URL
// POST /screenshot  { url: "https://..." }
app.post("/screenshot", async (req, res) => {
  const { url } = req.body;
  if (!url) return res.status(400).json({ success: false, error: "url is required" });

  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();

    await page.goto(url, { waitUntil: "domcontentloaded", timeout: NAV_TIMEOUT });

    const title = await page.title();
    const finalUrl = page.url();
    const screenshotPath = `/tmp/screenshot_${Date.now()}.png`;
    await page.screenshot({ path: screenshotPath, fullPage: false });

    res.json({ success: true, title, url: finalUrl, path: screenshotPath });
  } catch (err) {
    res.json({ success: false, error: err.message });
  } finally {
    await browser?.close();
  }
});

process.on("uncaughtException", (err) => {
  console.error("[FATAL] Uncaught exception:", err);
});
process.on("unhandledRejection", (err) => {
  console.error("[FATAL] Unhandled rejection:", err);
});

// Only bind the port when run directly (not imported by tests)
if (process.argv[1] === new URL(import.meta.url).pathname) {
  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Browser sidecar listening on port ${PORT}`);
  });
}
