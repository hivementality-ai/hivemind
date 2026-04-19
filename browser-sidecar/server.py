"""
Hivemind Browser Sidecar — headless browser automation via HTTP.

Exposes individual browser actions as endpoints. Hivemind's agent loop
handles the decision-making; this sidecar handles the browser.

Sessions persist across requests so agents can do multi-step interactions.
"""

import asyncio
import base64
import logging
import os
import time
import uuid
from contextlib import asynccontextmanager
from typing import Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from playwright.async_api import async_playwright, Browser, BrowserContext, Page

logger = logging.getLogger("hivemind.browser")
logging.basicConfig(level=logging.INFO)

# --- Session Store ---

MAX_SESSIONS = 5
SESSION_TTL = 300  # 5 min inactivity timeout


class BrowserSessionState:
    def __init__(self, context: BrowserContext, page: Page):
        self.context = context
        self.page = page
        self.last_used = time.time()
        self.elements_map: dict[int, dict] = {}  # index -> element selector info

    async def close(self):
        try:
            await self.context.close()
        except Exception:
            pass


sessions: dict[str, BrowserSessionState] = {}


async def cleanup_expired():
    """Remove sessions that haven't been used recently."""
    now = time.time()
    expired = [sid for sid, s in sessions.items() if now - s.last_used > SESSION_TTL]
    for sid in expired:
        await sessions.pop(sid).close()
        logger.info(f"Cleaned up expired session {sid}")


# --- Request/Response Models ---


class CreateSessionRequest(BaseModel):
    viewport_width: int = 1280
    viewport_height: int = 720


class NavigateRequest(BaseModel):
    url: str
    wait_until: str = "domcontentloaded"
    timeout: int = 30


class ClickRequest(BaseModel):
    index: int = Field(ge=1, description="Element index from state response")


class TypeRequest(BaseModel):
    index: int = Field(ge=0, description="Element index from state response")
    text: str
    clear: bool = True


class ScrollRequest(BaseModel):
    direction: str = Field(default="down", description="up or down")
    pages: float = Field(default=1.0, description="Number of pages to scroll")


class KeysRequest(BaseModel):
    keys: str = Field(description="Key or shortcut, e.g. Enter, Escape, Control+a")


class ElementInfo(BaseModel):
    index: int
    tag: str
    type: Optional[str] = None
    name: Optional[str] = None
    text: Optional[str] = None
    placeholder: Optional[str] = None
    href: Optional[str] = None
    value: Optional[str] = None
    role: Optional[str] = None
    aria_label: Optional[str] = None


class PageState(BaseModel):
    url: str
    title: str
    elements: list[ElementInfo]
    text_summary: str
    scroll_y: int = 0
    page_height: int = 0
    viewport_height: int = 720


class ActionResponse(BaseModel):
    success: bool
    message: Optional[str] = None
    state: Optional[PageState] = None
    error: Optional[str] = None


# --- App ---


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.playwright = await async_playwright().start()
    app.state.browser = await app.state.playwright.chromium.launch(
        headless=True,
        args=["--no-sandbox", "--disable-setuid-sandbox", "--disable-dev-shm-usage"],
    )
    logger.info("Browser sidecar ready")

    # Periodic cleanup task
    async def cleanup_loop():
        while True:
            await asyncio.sleep(60)
            await cleanup_expired()

    task = asyncio.create_task(cleanup_loop())
    yield
    task.cancel()

    # Cleanup all sessions
    for sid, session in list(sessions.items()):
        await session.close()
    sessions.clear()

    await app.state.browser.close()
    await app.state.playwright.stop()


app = FastAPI(title="Hivemind Browser Sidecar", lifespan=lifespan)


def get_session(session_id: str) -> BrowserSessionState:
    if session_id not in sessions:
        raise HTTPException(
            status_code=404,
            detail=f"Session {session_id} not found. Create one first.",
        )
    session = sessions[session_id]
    session.last_used = time.time()
    return session


# --- Endpoints ---


@app.get("/health")
async def health():
    return {"status": "ok", "active_sessions": len(sessions)}


@app.post("/session/create")
async def create_session(req: CreateSessionRequest):
    await cleanup_expired()

    if len(sessions) >= MAX_SESSIONS:
        # Close oldest session
        oldest_id = min(sessions, key=lambda s: sessions[s].last_used)
        await sessions.pop(oldest_id).close()

    session_id = uuid.uuid4().hex[:12]
    context = await app.state.browser.new_context(
        viewport={"width": req.viewport_width, "height": req.viewport_height},
        user_agent=(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) "
            "Chrome/131.0.0.0 Safari/537.36"
        ),
    )
    page = await context.new_page()
    sessions[session_id] = BrowserSessionState(context, page)

    return {"session_id": session_id}


@app.delete("/session/{session_id}")
async def close_session(session_id: str):
    if session_id in sessions:
        await sessions.pop(session_id).close()
    return {"success": True}


@app.post("/session/{session_id}/navigate", response_model=ActionResponse)
async def navigate(session_id: str, req: NavigateRequest):
    session = get_session(session_id)
    try:
        await session.page.goto(
            req.url,
            wait_until=req.wait_until,
            timeout=req.timeout * 1000,
        )
        state = await _get_page_state(session)
        return ActionResponse(success=True, state=state)
    except Exception as e:
        return ActionResponse(success=False, error=str(e))


@app.post("/session/{session_id}/state", response_model=ActionResponse)
async def get_state(session_id: str):
    session = get_session(session_id)
    try:
        state = await _get_page_state(session)
        return ActionResponse(success=True, state=state)
    except Exception as e:
        return ActionResponse(success=False, error=str(e))


@app.post("/session/{session_id}/click", response_model=ActionResponse)
async def click(session_id: str, req: ClickRequest):
    session = get_session(session_id)
    try:
        element_info = session.elements_map.get(req.index)
        if not element_info:
            return ActionResponse(
                success=False,
                error=f"Element index {req.index} not found. Get /state first.",
            )

        selector = element_info["selector"]
        await session.page.locator(selector).first.click(timeout=5000)
        await session.page.wait_for_load_state("domcontentloaded", timeout=5000)
        await asyncio.sleep(0.3)  # Brief settle

        state = await _get_page_state(session)
        return ActionResponse(success=True, message=f"Clicked element {req.index}", state=state)
    except Exception as e:
        return ActionResponse(success=False, error=f"Click failed: {str(e)}")


@app.post("/session/{session_id}/type", response_model=ActionResponse)
async def type_text(session_id: str, req: TypeRequest):
    session = get_session(session_id)
    try:
        element_info = session.elements_map.get(req.index)
        if not element_info:
            return ActionResponse(
                success=False,
                error=f"Element index {req.index} not found.",
            )

        selector = element_info["selector"]
        locator = session.page.locator(selector).first

        if req.clear:
            await locator.fill("")

        await locator.type(req.text, delay=20)

        state = await _get_page_state(session)
        return ActionResponse(success=True, message=f"Typed into element {req.index}", state=state)
    except Exception as e:
        return ActionResponse(success=False, error=f"Type failed: {str(e)}")


@app.post("/session/{session_id}/scroll", response_model=ActionResponse)
async def scroll(session_id: str, req: ScrollRequest):
    session = get_session(session_id)
    try:
        direction = -1 if req.direction == "up" else 1
        pixels = int(req.pages * 720)  # viewport height approx
        await session.page.evaluate(f"window.scrollBy(0, {direction * pixels})")
        await asyncio.sleep(0.3)

        state = await _get_page_state(session)
        return ActionResponse(success=True, state=state)
    except Exception as e:
        return ActionResponse(success=False, error=f"Scroll failed: {str(e)}")


@app.post("/session/{session_id}/keys", response_model=ActionResponse)
async def send_keys(session_id: str, req: KeysRequest):
    session = get_session(session_id)
    try:
        await session.page.keyboard.press(req.keys)
        await asyncio.sleep(0.3)

        state = await _get_page_state(session)
        return ActionResponse(success=True, message=f"Sent keys: {req.keys}", state=state)
    except Exception as e:
        return ActionResponse(success=False, error=f"Keys failed: {str(e)}")


@app.post("/session/{session_id}/screenshot")
async def screenshot(session_id: str):
    session = get_session(session_id)
    try:
        img_bytes = await session.page.screenshot(full_page=False)
        return {
            "success": True,
            "screenshot_base64": base64.b64encode(img_bytes).decode("utf-8"),
            "url": session.page.url,
            "title": await session.page.title(),
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


@app.post("/session/{session_id}/extract")
async def extract(session_id: str):
    session = get_session(session_id)
    try:
        text = await session.page.evaluate("() => document.body.innerText")
        return {
            "success": True,
            "content": (text or "")[:50000],
            "url": session.page.url,
            "title": await session.page.title(),
        }
    except Exception as e:
        return {"success": False, "error": str(e)}


# --- DOM State Extraction ---


async def _get_page_state(session: BrowserSessionState) -> PageState:
    """
    Extract interactive elements from the page.

    Returns a compact indexed list of clickable/typeable elements
    that the LLM agent can reference by index number.
    """
    page = session.page
    title = await page.title()
    url = page.url

    scroll_y = await page.evaluate("window.scrollY")
    page_height = await page.evaluate("document.documentElement.scrollHeight")
    viewport_height = await page.evaluate("window.innerHeight")

    # Extract interactive elements via JS
    raw_elements = await page.evaluate(
        """
    () => {
        const interactive = [];
        const seen = new Set();

        // Selectors for interactive elements
        const selectors = [
            'a[href]',
            'button',
            'input',
            'textarea',
            'select',
            '[role="button"]',
            '[role="link"]',
            '[role="tab"]',
            '[role="menuitem"]',
            '[role="checkbox"]',
            '[role="radio"]',
            '[onclick]',
            '[tabindex]:not([tabindex="-1"])',
            'summary',
            'details',
            'label[for]',
        ];

        const allElements = document.querySelectorAll(selectors.join(','));

        for (const el of allElements) {
            // Skip hidden elements
            const style = window.getComputedStyle(el);
            if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') continue;
            const rect = el.getBoundingClientRect();
            if (rect.width === 0 && rect.height === 0) continue;

            // Build unique selector
            let selector = '';
            if (el.id) {
                selector = '#' + CSS.escape(el.id);
            } else if (el.name && el.tagName !== 'A') {
                selector = el.tagName.toLowerCase() + '[name="' + el.name + '"]';
            } else {
                // Use nth-child path
                const path = [];
                let current = el;
                while (current && current !== document.body) {
                    let nth = 1;
                    let sibling = current.previousElementSibling;
                    while (sibling) {
                        if (sibling.tagName === current.tagName) nth++;
                        sibling = sibling.previousElementSibling;
                    }
                    path.unshift(current.tagName.toLowerCase() + ':nth-of-type(' + nth + ')');
                    current = current.parentElement;
                }
                selector = path.join(' > ');
            }

            // Dedupe
            const key = selector + '|' + el.textContent?.trim().substring(0, 50);
            if (seen.has(key)) continue;
            seen.add(key);

            const info = {
                tag: el.tagName.toLowerCase(),
                selector: selector,
            };

            // Attributes
            if (el.type) info.type = el.type;
            if (el.name) info.name = el.name;
            if (el.placeholder) info.placeholder = el.placeholder;
            if (el.value && el.tagName === 'INPUT') info.value = el.value.substring(0, 100);
            if (el.href) info.href = el.href;
            if (el.getAttribute('role')) info.role = el.getAttribute('role');
            if (el.getAttribute('aria-label')) info.aria_label = el.getAttribute('aria-label');

            // Text content (trimmed)
            const text = el.textContent?.trim().substring(0, 200);
            if (text && el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA') {
                info.text = text;
            }

            interactive.push(info);
        }

        return interactive;
    }
    """
    )

    # Build indexed elements map
    elements = []
    session.elements_map = {}

    for i, raw in enumerate(raw_elements, start=1):
        session.elements_map[i] = {"selector": raw.pop("selector")}
        elements.append(
            ElementInfo(
                index=i,
                **{k: v for k, v in raw.items() if v is not None},
            )
        )

    # Brief text summary (first 500 chars of visible text)
    text_summary = await page.evaluate(
        """
    () => {
        const text = document.body.innerText || '';
        return text.substring(0, 500).trim();
    }
    """
    )

    return PageState(
        url=url,
        title=title,
        elements=elements,
        text_summary=text_summary or "",
        scroll_y=int(scroll_y or 0),
        page_height=int(page_height or 0),
        viewport_height=int(viewport_height or 720),
    )
