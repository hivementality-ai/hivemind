const CACHE_VERSION = "hivemind-v1";
const APP_SHELL_CACHE = `shell-${CACHE_VERSION}`;
const DYNAMIC_CACHE = `dynamic-${CACHE_VERSION}`;

// App shell resources to cache on install
const APP_SHELL_RESOURCES = [
  "/m/",
  "/icon.png"
];

// Install: cache app shell
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(APP_SHELL_CACHE).then((cache) => {
      return cache.addAll(APP_SHELL_RESOURCES);
    })
  );
  self.skipWaiting();
});

// Activate: clean old caches
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys
          .filter((key) => key !== APP_SHELL_CACHE && key !== DYNAMIC_CACHE)
          .map((key) => caches.delete(key))
      );
    })
  );
  self.clients.claim();
});

// Fetch: routing strategies
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // Skip non-GET requests
  if (event.request.method !== "GET") return;

  // Skip ActionCable, API, and webhook requests
  if (url.pathname.startsWith("/cable") ||
      url.pathname.startsWith("/api/") ||
      url.pathname.startsWith("/webhooks/") ||
      url.pathname.startsWith("/internal/")) {
    return;
  }

  // Images and avatars: cache-first
  if (event.request.destination === "image" ||
      url.pathname.match(/\.(png|jpg|jpeg|gif|svg|webp|ico)$/)) {
    event.respondWith(cacheFirst(event.request, DYNAMIC_CACHE));
    return;
  }

  // CSS, JS, fonts: cache-first (app shell)
  if (event.request.destination === "style" ||
      event.request.destination === "script" ||
      event.request.destination === "font" ||
      url.pathname.match(/\.(css|js|woff2?)$/)) {
    event.respondWith(cacheFirst(event.request, APP_SHELL_CACHE));
    return;
  }

  // Agent list: stale-while-revalidate
  if (url.pathname === "/m/agents") {
    event.respondWith(staleWhileRevalidate(event.request, DYNAMIC_CACHE));
    return;
  }

  // Chat history (session show pages): network-first, fallback to cache
  if (url.pathname.match(/^\/m\/sessions\/\d+$/) ||
      url.pathname.match(/^\/m\/team_chats\/\d+$/)) {
    event.respondWith(networkFirst(event.request, DYNAMIC_CACHE));
    return;
  }

  // Activity feed: network-only (real-time data)
  if (url.pathname === "/m/activity") {
    return;
  }

  // All other mobile pages: network-first
  if (url.pathname.startsWith("/m")) {
    event.respondWith(networkFirst(event.request, DYNAMIC_CACHE));
    return;
  }
});

// Cache-first strategy
async function cacheFirst(request, cacheName) {
  const cached = await caches.match(request);
  if (cached) return cached;

  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(cacheName);
      cache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    return new Response("", { status: 503, statusText: "Offline" });
  }
}

// Network-first strategy
async function networkFirst(request, cacheName) {
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(cacheName);
      cache.put(request, response.clone());
    }
    return response;
  } catch (error) {
    const cached = await caches.match(request);
    if (cached) return cached;

    // Return offline page for navigation requests
    if (request.mode === "navigate") {
      return new Response(offlineHTML(), {
        headers: { "Content-Type": "text/html" }
      });
    }
    return new Response("", { status: 503, statusText: "Offline" });
  }
}

// Stale-while-revalidate strategy
async function staleWhileRevalidate(request, cacheName) {
  const cache = await caches.open(cacheName);
  const cached = await cache.match(request);

  const fetchPromise = fetch(request).then((response) => {
    if (response.ok) {
      cache.put(request, response.clone());
    }
    return response;
  }).catch(() => cached);

  return cached || fetchPromise;
}

// Push notification handler
self.addEventListener("push", async (event) => {
  if (!event.data) return;

  const data = event.data.json();
  const title = data.title || "Hivemind";
  const options = {
    body: data.body || "",
    icon: "/icon.png",
    badge: "/icon.png",
    data: { url: data.url || "/m/" },
    tag: data.tag || "hivemind-notification",
    renotify: true,
    requireInteraction: data.requireInteraction || false
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// Notification click handler
self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  const url = event.notification.data?.url || "/m/";

  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      // Focus existing window if open
      for (const client of clientList) {
        const clientUrl = new URL(client.url);
        if (clientUrl.pathname === url && "focus" in client) {
          return client.focus();
        }
      }
      // Open new window
      if (clients.openWindow) {
        return clients.openWindow(url);
      }
    })
  );
});

// Background sync for offline message queue
self.addEventListener("sync", (event) => {
  if (event.tag === "send-message") {
    event.waitUntil(sendQueuedMessages());
  }
});

async function sendQueuedMessages() {
  // Messages are queued in IndexedDB by the mobile_chat_controller
  // This handler sends them when connectivity returns
  try {
    const db = await openDB();
    const tx = db.transaction("outbox", "readonly");
    const store = tx.objectStore("outbox");
    const messages = await getAllFromStore(store);

    for (const msg of messages) {
      try {
        const response = await fetch(msg.url, {
          method: "POST",
          headers: msg.headers,
          body: msg.body
        });

        if (response.ok) {
          const deleteTx = db.transaction("outbox", "readwrite");
          deleteTx.objectStore("outbox").delete(msg.id);
        }
      } catch (e) {
        // Will retry on next sync
      }
    }
  } catch (e) {
    // IndexedDB not available
  }
}

function openDB() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open("hivemind-offline", 1);
    request.onupgradeneeded = (event) => {
      const db = event.target.result;
      if (!db.objectStoreNames.contains("outbox")) {
        db.createObjectStore("outbox", { keyPath: "id", autoIncrement: true });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function getAllFromStore(store) {
  return new Promise((resolve, reject) => {
    const request = store.getAll();
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

function offlineHTML() {
  return `<!DOCTYPE html>
<html class="h-full bg-[#0A0A0F]">
<head>
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Hivemind - Offline</title>
  <style>
    body { font-family: Inter, sans-serif; color: #fff; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; background: #0A0A0F; }
    .container { text-align: center; padding: 2rem; }
    h1 { font-size: 1.5rem; margin-bottom: 0.5rem; }
    p { color: #6b7280; margin-bottom: 1.5rem; }
    button { background: #F59E0B; color: #fff; border: none; padding: 0.75rem 1.5rem; border-radius: 0.75rem; font-weight: 600; cursor: pointer; }
  </style>
</head>
<body>
  <div class="container">
    <h1>You're offline</h1>
    <p>Messages will send when you reconnect.</p>
    <button onclick="location.reload()">Retry</button>
  </div>
</body>
</html>`;
}
