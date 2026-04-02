/**
 * Trading Simulator - Web Configuration
 * ======================================
 * Web-specific settings and utilities for the HTML5 export.
 * This file is loaded before the Godot engine to configure
 * Firebase, API endpoints, and platform detection.
 */

const TradingWebConfig = (function () {
    'use strict';

    // ================================================================
    // Firebase Configuration (replace with real values before deploy)
    // ================================================================
    const FIREBASE_CONFIG = {
        apiKey: 'YOUR_API_KEY',
        authDomain: 'YOUR_PROJECT.firebaseapp.com',
        projectId: 'YOUR_PROJECT_ID',
        storageBucket: 'YOUR_PROJECT.appspot.com',
        messagingSenderId: 'YOUR_SENDER_ID',
        appId: 'YOUR_APP_ID',
        measurementId: 'YOUR_MEASUREMENT_ID',   // optional
        databaseURL: 'https://YOUR_PROJECT-default-rtdb.firebaseio.com' // optional, if using RTDB
    };

    // ================================================================
    // API Endpoints
    // ================================================================
    const API_ENDPOINTS = {
        // Backend REST API base URL (update per environment)
        BASE_URL: 'https://api.tradingsimulator.example.com',

        // Authentication
        AUTH: {
            LOGIN: '/auth/login',
            REGISTER: '/auth/register',
            REFRESH: '/auth/refresh',
            LOGOUT: '/auth/logout',
            PASSWORD_RESET: '/auth/password-reset'
        },

        // Market Data
        MARKET: {
            TICKER: '/market/ticker',
            HISTORY: '/market/history',
            ORDERBOOK: '/market/orderbook',
            STATS: '/market/stats',
            SEARCH: '/market/search'
        },

        // Trading
        TRADE: {
            PORTFOLIO: '/trade/portfolio',
            EXECUTE: '/trade/execute',
            HISTORY: '/trade/history',
            OPEN_ORDERS: '/trade/orders/open',
            CANCEL: '/trade/orders/cancel'
        },

        // Social / Multiplayer
        SOCIAL: {
            LEADERBOARD: '/social/leaderboard',
            FRIENDS: '/social/friends',
            FORUM_POSTS: '/social/forum/posts',
            FORUM_COMMENTS: '/social/forum/comments',
            CHALLENGES: '/social/challenges'
        },

        // User Profile
        USER: {
            PROFILE: '/user/profile',
            SETTINGS: '/user/settings',
            STATS: '/user/stats',
            ACHIEVEMENTS: '/user/achievements'
        }
    };

    // ================================================================
    // Sync & Timing Configuration
    // ================================================================
    const SYNC_SETTINGS = {
        // How often to pull market data (ms)
        MARKET_DATA_INTERVAL: 5000,

        // How often to sync portfolio (ms)
        PORTFOLIO_SYNC_INTERVAL: 10000,

        // How often to check for notifications (ms)
        NOTIFICATION_CHECK_INTERVAL: 15000,

        // WebSocket reconnection base delay (ms) — exponential backoff
        WS_RECONNECT_BASE_DELAY: 1000,

        // Maximum WebSocket reconnection delay (ms)
        WS_RECONNECT_MAX_DELAY: 30000,

        // Idle timeout before reducing sync frequency (ms)
        IDLE_THRESHOLD: 300000,

        // Reduced sync interval when idle (ms)
        IDLE_SYNC_INTERVAL: 60000,

        // Timeout for HTTP requests (ms)
        HTTP_REQUEST_TIMEOUT: 15000
    };

    // ================================================================
    // Feature Flags
    // ================================================================
    const FEATURES = {
        FIREBASE_AUTH: true,
        FIREBASE_FIRESTORE: true,
        WEBSOCKET_MARKET_DATA: true,
        PWA_INSTALL_PROMPT: true,
        OFFLINE_MODE: true,
        ANALYTICS: true,
        SOCIAL_FEATURES: true,
        BACKTESTING: true
    };

    // ================================================================
    // Platform Detection
    // ================================================================
    const Platform = {
        /**
         * Detects if the game is running in a web browser (HTML5 export).
         * In Godot, OS.has_feature('web') is the canonical check from GDScript.
         * This JS utility complements that for any web-only logic.
         */
        isWeb: function () {
            // If the Godot Engine object exists, we're definitely in web export
            if (typeof Godot !== 'undefined') return true;
            // Fallback: check if running in a browser with DOM
            return typeof window !== 'undefined' && typeof document !== 'undefined';
        },

        isMobile: function () {
            if (!this.isWeb()) return false;
            var ua = navigator.userAgent || navigator.vendor || '';
            return /android|webos|iphone|ipad|ipod|blackberry|iemobile|opera mini/i.test(ua.toLowerCase());
        },

        isIOS: function () {
            if (!this.isWeb()) return false;
            var ua = navigator.userAgent || '';
            return /iphone|ipad|ipod/i.test(ua.toLowerCase());
        },

        isAndroid: function () {
            if (!this.isWeb()) return false;
            var ua = navigator.userAgent || '';
            return /android/i.test(ua.toLowerCase());
        },

        isStandalone: function () {
            // Check if running as a PWA (installed app)
            return window.matchMedia && window.matchMedia('(display-mode: standalone)').matches
                || navigator.standalone === true;
        },

        isSecureContext: function () {
            return window.isSecureContext;
        },

        supportsServiceWorker: function () {
            return 'serviceWorker' in navigator;
        },

        supportsWebGL: function () {
            try {
                var canvas = document.createElement('canvas');
                return !!(window.WebGLRenderingContext &&
                    (canvas.getContext('webgl') || canvas.getContext('experimental-webgl')));
            } catch (e) {
                return false;
            }
        },

        getScreenSize: function () {
            return {
                width: window.innerWidth || screen.width,
                height: window.innerHeight || screen.height,
                pixelRatio: window.devicePixelRatio || 1
            };
        },

        getBrowserInfo: function () {
            var ua = navigator.userAgent;
            var browserName = 'Unknown';
            var browserVersion = '0';

            if (ua.indexOf('Firefox') > -1) {
                browserName = 'Firefox';
                browserVersion = ua.match(/Firefox\/([\d.]+)/)[1];
            } else if (ua.indexOf('Edg') > -1) {
                browserName = 'Edge';
                browserVersion = ua.match(/Edg\/([\d.]+)/)[1];
            } else if (ua.indexOf('Chrome') > -1) {
                browserName = 'Chrome';
                browserVersion = ua.match(/Chrome\/([\d.]+)/)[1];
            } else if (ua.indexOf('Safari') > -1) {
                browserName = 'Safari';
                browserVersion = ua.match(/Version\/([\d.]+)/)[1];
            }

            return {
                name: browserName,
                version: browserVersion,
                userAgent: ua,
                language: navigator.language || 'en',
                cookiesEnabled: navigator.cookieEnabled,
                onLine: navigator.onLine
            };
        }
    };

    // ================================================================
    // Utility Helpers
    // ================================================================

    /**
     * Build a full API URL from a path object and params.
     * Example: buildApiUrl(API_ENDPOINTS.MARKET.HISTORY, { symbol: 'AAPL', timeframe: '1D' })
     */
    function buildApiUrl(path, params) {
        var url = API_ENDPOINTS.BASE_URL + path;
        if (params) {
            var qs = Object.keys(params)
                .map(function (k) { return encodeURIComponent(k) + '=' + encodeURIComponent(params[k]); })
                .join('&');
            if (qs) url += '?' + qs;
        }
        return url;
    }

    /**
     * Simple fetch wrapper with timeout and error handling.
     */
    function apiFetch(path, options) {
        options = options || {};
        var url = buildApiUrl(path, options.params);
        var controller = new AbortController();
        var timeout = setTimeout(function () { controller.abort(); }, SYNC_SETTINGS.HTTP_REQUEST_TIMEOUT);

        var headers = Object.assign({
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        }, options.headers || {});

        // Attach auth token if available
        if (typeof firebase !== 'undefined' && firebase.auth) {
            var user = firebase.auth().currentUser;
            if (user) {
                return user.getIdToken().then(function (token) {
                    headers['Authorization'] = 'Bearer ' + token;
                    return doFetch();
                });
            }
        }

        return doFetch();

        function doFetch() {
            return fetch(url, {
                method: options.method || 'GET',
                headers: headers,
                body: options.body ? JSON.stringify(options.body) : undefined,
                signal: controller.signal
            })
            .then(function (response) {
                clearTimeout(timeout);
                if (!response.ok) {
                    return response.json().then(function (err) {
                        throw new Error(err.message || 'HTTP ' + response.status);
                    }).catch(function () {
                        throw new Error('HTTP ' + response.status);
                    });
                }
                return response.json();
            })
            .catch(function (err) {
                clearTimeout(timeout);
                if (err.name === 'AbortError') {
                    throw new Error('Request timed out');
                }
                throw err;
            });
        }
    }

    // ================================================================
    // Public API
    // ================================================================
    return {
        FIREBASE_CONFIG: FIREBASE_CONFIG,
        API_ENDPOINTS: API_ENDPOINTS,
        SYNC_SETTINGS: SYNC_SETTINGS,
        FEATURES: FEATURES,
        Platform: Platform,
        buildApiUrl: buildApiUrl,
        apiFetch: apiFetch
    };

})();

// Expose globally so Godot's JavaScript bridge can access it
if (typeof window !== 'undefined') {
    window.TradingWebConfig = TradingWebConfig;
}
