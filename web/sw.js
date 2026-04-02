/**
 * Trading Simulator - Service Worker
 * ===================================
 * Provides offline caching for the web deployment.
 * Uses a cache-first strategy for static assets and
 * network-first for API calls.
 */

const CACHE_NAME = 'trading-simulator-v1';

// Static assets to pre-cache on install
const PRECACHE_ASSETS = [
    './',
    './index.html',
    './manifest.json',
    './icons/icon-192x192.png',
    './icons/icon-512x512.png'
];

// Cacheable file extensions for runtime caching
const CACHEABLE_EXTENSIONS = [
    '.html', '.css', '.js', '.json', '.png', '.jpg', '.jpeg',
    '.gif', '.svg', '.ico', '.woff', '.woff2', '.ttf', '.eot',
    '.wasm', '.pck', '.js.map'
];

// ============================================================
// Install: Pre-cache essential static assets
// ============================================================
self.addEventListener('install', (event) => {
    console.log('[SW] Installing service worker...');
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then((cache) => {
                console.log('[SW] Pre-caching static assets');
                return cache.addAll(PRECACHE_ASSETS);
            })
            .then(() => self.skipWaiting())
            .catch((err) => {
                console.warn('[SW] Pre-cache failed (some assets may not exist yet):', err.message);
                // Still skip waiting so the SW activates
                return self.skipWaiting();
            })
    );
});

// ============================================================
// Activate: Clean up old caches
// ============================================================
self.addEventListener('activate', (event) => {
    console.log('[SW] Activating service worker...');
    event.waitUntil(
        caches.keys()
            .then((cacheNames) => {
                return Promise.all(
                    cacheNames
                        .filter((name) => name !== CACHE_NAME)
                        .map((name) => {
                            console.log('[SW] Deleting old cache:', name);
                            return caches.delete(name);
                        })
                );
            })
            .then(() => self.clients.claim())
    );
});

// ============================================================
// Fetch: Routing strategy
// ============================================================
self.addEventListener('fetch', (event) => {
    const { request } = event;
    const url = new URL(request.url);

    // Skip non-GET requests
    if (request.method !== 'GET') return;

    // Skip cross-origin requests (except CDN resources we want to cache)
    if (url.origin !== self.location.origin) {
        // Cache CDN resources (Firebase SDK, fonts, etc.)
        if (isCacheableCDN(url)) {
            event.respondWith(cacheFirst(request));
        }
        return;
    }

    // API requests: Network first
    if (url.pathname.startsWith('/api/') || url.pathname.includes('firebaseio.com')) {
        event.respondWith(networkFirst(request, 5000));
        return;
    }

    // Static assets: Cache first
    if (isStaticAsset(url)) {
        event.respondWith(cacheFirst(request));
        return;
    }

    // Navigation requests: Network first, fallback to cached index
    if (request.mode === 'navigate') {
        event.respondWith(networkFirst(request, 3000));
        return;
    }

    // Default: Stale-while-revalidate
    event.respondWith(staleWhileRevalidate(request));
});

// ============================================================
// Caching Strategies
// ============================================================

/**
 * Cache-first strategy: Serve from cache, fetch and update on miss.
 */
async function cacheFirst(request) {
    const cached = await caches.match(request);
    if (cached) return cached;

    try {
        const response = await fetch(request);
        if (response.ok) {
            const cache = await caches.open(CACHE_NAME);
            cache.put(request, response.clone());
        }
        return response;
    } catch (err) {
        // Return offline fallback for HTML requests
        if (request.headers.get('Accept') && request.headers.get('Accept').includes('text/html')) {
            const fallback = await caches.match('./index.html');
            if (fallback) return fallback;
        }
        return new Response('Offline', { status: 503, statusText: 'Service Unavailable' });
    }
}

/**
 * Network-first strategy: Try network, fall back to cache.
 */
async function networkFirst(request, timeoutMs) {
    const cache = await caches.open(CACHE_NAME);

    try {
        const response = await Promise.race([
            fetch(request),
            new Promise((_, reject) => setTimeout(() => reject(new Error('timeout')), timeoutMs))
        ]);

        if (response.ok) {
            cache.put(request, response.clone());
        }
        return response;
    } catch (err) {
        const cached = await cache.match(request);
        if (cached) return cached;

        if (request.mode === 'navigate') {
            const indexPage = await cache.match('./index.html');
            if (indexPage) return indexPage;
        }

        return new Response('Offline', { status: 503, statusText: 'Service Unavailable' });
    }
}

/**
 * Stale-while-revalidate: Serve from cache immediately, update in background.
 */
async function staleWhileRevalidate(request) {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(request);

    const fetchPromise = fetch(request)
        .then((response) => {
            if (response.ok) {
                cache.put(request, response.clone());
            }
            return response;
        })
        .catch(() => cached); // silently fail

    return cached || fetchPromise;
}

// ============================================================
// Helpers
// ============================================================

function isStaticAsset(url) {
    return CACHEABLE_EXTENSIONS.some((ext) => url.pathname.endsWith(ext));
}

function isCacheableCDN(url) {
    const cacheableHosts = [
        'gstatic.com',
        'firebaseapp.com',
        'firebaseio.com',
        'googleapis.com',
        'fonts.googleapis.com',
        'fonts.gstatic.com'
    ];
    return cacheableHosts.some((host) => url.hostname.includes(host));
}

// ============================================================
// Background Sync (for future use with offline actions)
// ============================================================
self.addEventListener('sync', (event) => {
    if (event.tag === 'sync-trades') {
        console.log('[SW] Syncing offline trade data...');
        // TODO: Implement trade sync logic
    }

    if (event.tag === 'sync-portfolio') {
        console.log('[SW] Syncing portfolio data...');
        // TODO: Implement portfolio sync logic
    }
});

// ============================================================
// Push Notifications (for future use)
// ============================================================
self.addEventListener('push', (event) => {
    if (!event.data) return;

    const data = event.data.json();
    const options = {
        body: data.body || 'New update available',
        icon: './icons/icon-192x192.png',
        badge: './icons/icon-72x72.png',
        vibrate: [100, 50, 100],
        data: {
            url: data.url || './'
        },
        actions: data.actions || []
    };

    event.waitUntil(
        self.registration.showNotification(data.title || 'Trading Simulator', options)
    );
});

self.addEventListener('notificationclick', (event) => {
    event.notification.close();
    event.waitUntil(
        self.clients.openWindow(event.notification.data.url || './')
    );
});
