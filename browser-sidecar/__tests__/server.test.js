// Jest tests for browser-sidecar server routes
// We test the HTTP layer by mocking playwright — no real browser needed.

import { jest } from "@jest/globals";

// --- Playwright mock ---
const mockPage = {
  goto: jest.fn().mockResolvedValue(undefined),
  title: jest.fn().mockResolvedValue("Test Page"),
  url: jest.fn().mockReturnValue("https://example.com"),
  evaluate: jest.fn().mockResolvedValue("Page body text content"),
  screenshot: jest.fn().mockResolvedValue(undefined),
};

const mockBrowser = {
  newPage: jest.fn().mockResolvedValue(mockPage),
  close: jest.fn().mockResolvedValue(undefined),
};

jest.unstable_mockModule("playwright", () => ({
  chromium: {
    launch: jest.fn().mockResolvedValue(mockBrowser),
  },
}));

// Dynamically import after mock is set up
const { default: request } = await import("supertest");
const { app } = await import("../server.js");

beforeEach(() => {
  jest.clearAllMocks();
  mockPage.goto.mockResolvedValue(undefined);
  mockPage.title.mockResolvedValue("Test Page");
  mockPage.url.mockReturnValue("https://example.com");
  mockPage.evaluate.mockResolvedValue("Page body text content");
  mockPage.screenshot.mockResolvedValue(undefined);
  mockBrowser.newPage.mockResolvedValue(mockPage);
  mockBrowser.close.mockResolvedValue(undefined);
});

describe("GET /health", () => {
  it("returns ok status", async () => {
    const res = await request(app).get("/health");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: "ok", service: "browser-sidecar" });
  });
});

describe("POST /navigate", () => {
  it("returns page content on success", async () => {
    const res = await request(app)
      .post("/navigate")
      .send({ url: "https://example.com" });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.title).toBe("Test Page");
    expect(res.body.url).toBe("https://example.com");
    expect(res.body.content).toBe("Page body text content");
  });

  it("returns 400 when url is missing", async () => {
    const res = await request(app).post("/navigate").send({});
    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toBe("url is required");
  });

  it("closes browser even on navigation error", async () => {
    mockPage.goto.mockRejectedValueOnce(new Error("Navigation timeout"));

    const res = await request(app)
      .post("/navigate")
      .send({ url: "https://slow.example.com" });

    expect(res.body.success).toBe(false);
    expect(res.body.error).toBe("Navigation timeout");
    expect(mockBrowser.close).toHaveBeenCalledTimes(1);
  });

  it("closes browser even when title throws", async () => {
    mockPage.title.mockRejectedValueOnce(new Error("Page crashed"));

    const res = await request(app)
      .post("/navigate")
      .send({ url: "https://example.com" });

    expect(res.body.success).toBe(false);
    expect(mockBrowser.close).toHaveBeenCalledTimes(1);
  });

  it("truncates content to MAX_CONTENT characters", async () => {
    const longContent = "a".repeat(40_000);
    mockPage.evaluate.mockResolvedValueOnce(longContent);

    const res = await request(app)
      .post("/navigate")
      .send({ url: "https://example.com" });

    expect(res.body.success).toBe(true);
    expect(res.body.content.length).toBe(30_000);
  });

  it("handles page with no body gracefully", async () => {
    mockPage.evaluate.mockResolvedValueOnce("");

    const res = await request(app)
      .post("/navigate")
      .send({ url: "https://example.com" });

    expect(res.body.success).toBe(true);
    expect(res.body.content).toBe("");
  });
});

describe("POST /screenshot", () => {
  it("returns screenshot path on success", async () => {
    const res = await request(app)
      .post("/screenshot")
      .send({ url: "https://example.com" });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.title).toBe("Test Page");
    expect(res.body.url).toBe("https://example.com");
    expect(res.body.path).toMatch(/^\/tmp\/screenshot_\d+\.png$/);
  });

  it("returns 400 when url is missing", async () => {
    const res = await request(app).post("/screenshot").send({});
    expect(res.status).toBe(400);
    expect(res.body.success).toBe(false);
    expect(res.body.error).toBe("url is required");
  });

  it("closes browser on screenshot error", async () => {
    mockPage.screenshot.mockRejectedValueOnce(new Error("Screenshot failed"));

    const res = await request(app)
      .post("/screenshot")
      .send({ url: "https://example.com" });

    expect(res.body.success).toBe(false);
    expect(res.body.error).toBe("Screenshot failed");
    expect(mockBrowser.close).toHaveBeenCalledTimes(1);
  });

  it("closes browser on navigation error", async () => {
    mockPage.goto.mockRejectedValueOnce(new Error("Net::ERR_NAME_NOT_RESOLVED"));

    const res = await request(app)
      .post("/screenshot")
      .send({ url: "https://no-such-host.invalid" });

    expect(res.body.success).toBe(false);
    expect(mockBrowser.close).toHaveBeenCalledTimes(1);
  });
});
