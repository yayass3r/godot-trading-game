## ============================================
## WebInit.gd - Web-specific initialization script
## Loaded only on web platform to handle:
## - Firebase JS SDK initialization via JavaScript bridge
## - Service worker setup for offline support
## - PWA install prompt handling
## - Screen orientation lock (portrait on mobile)
## - Viewport management
## - Web environment detection
## ============================================
extends Node

## ---- Signals ----
signal firebase_js_ready()
signal firebase_js_failed(error: String)
signal service_worker_registered()
signal service_worker_failed(error: String)
signal pwa_install_available()
signal pwa_install_completed()
signal pwa_install_dismissed()
signal online_status_changed(is_online: bool)
signal viewport_changed(size: Vector2i)
signal orientation_changed(orientation: String)

## ---- State ----
var is_web_platform: bool = false
var is_mobile_web: bool = false
var is_pwa: bool = false
var is_standalone: bool = false
var is_cross_origin_isolated: bool = false
var firebase_js_initialized: bool = false
var sw_registered: bool = false
var current_orientation: String = ""
var viewport_size: Vector2i = Vector2i.ZERO

## ---- PWA deferred prompt reference ----
var _deferred_prompt: bool = false
var _has_pwa_prompt: bool = false

## ---- Firebase JS config (injected at export time or loaded from page) ----
var firebase_js_config: Dictionary = {}

## ---- Timer for periodic web checks ----
var _check_timer: Timer

## ============================================
## _ready() - Only runs on web platform
## ============================================
func _ready() -> void:
	is_web_platform = OS.get_name() == "Web"

	if not is_web_platform:
		print("[WebInit] Not on web platform — skipping initialization")
		return

	print("[WebInit] Initializing web environment...")

	## Detect environment
	_detect_environment()
	_setup_viewport()

	## Setup timers
	_check_timer = Timer.new()
	_check_timer.wait_time = 5.0
	_check_timer.autostart = true
	_check_timer.timeout.connect(_periodic_check)
	add_child(_check_timer)

	## Initialize Firebase JS SDK
	_init_firebase_js()

	## Register service worker
	_register_service_worker()

	## Setup PWA install prompt
	_setup_pwa_prompt()

	## Listen for online/offline events
	_setup_connectivity_listeners()

	## Lock orientation for mobile web
	if is_mobile_web:
		_lock_screen_orientation()

	print("[WebInit] Web initialization complete")
	print("  Platform: Web (mobile=%s, PWA=%s, standalone=%s)" % [str(is_mobile_web), str(is_pwa), str(is_standalone)])
	print("  COOP isolated: %s" % str(is_cross_origin_isolated))


## ============================================
## ===== Environment Detection =====
## ============================================

## Detect web environment details
func _detect_environment() -> void:
	## Check if mobile
	var user_agent_result = JavaScriptBridge.eval("navigator.userAgent")
	if user_agent_result != null:
		var ua: String = str(user_agent_result).to_lower()
		is_mobile_web = (
			ua.find("android") >= 0 or
			ua.find("iphone") >= 0 or
			ua.find("ipad") >= 0 or
			ua.find("ipod") >= 0 or
			ua.find("mobile") >= 0
		)

	## Check if running as PWA / standalone
	var display_mode = JavaScriptBridge.eval("window.matchMedia('(display-mode: standalone)').matches")
	if display_mode != null:
		is_standalone = bool(display_mode)
		is_pwa = is_standalone

	## Also check via navigator.standalone (iOS Safari)
	if not is_standalone:
		var ios_standalone = JavaScriptBridge.eval("navigator.standalone === true")
		if ios_standalone == true:
			is_standalone = true
			is_pwa = true

	## Check cross-origin isolation
	var coi_result = JavaScriptBridge.eval("typeof crossOriginIsolated !== 'undefined' && crossOriginIsolated")
	is_cross_origin_isolated = coi_result == true

	## Get current orientation
	_detect_orientation()


## Detect current screen orientation
func _detect_orientation() -> void:
	var result = JavaScriptBridge.eval("(screen.orientation && screen.orientation.type) || 'unknown'")
	if result != null:
		current_orientation = str(result)
	else:
		## Fallback: infer from aspect ratio
		var w = DisplayServer.screen_get_size().x
		var h = DisplayServer.screen_get_size().y
		current_orientation = "portrait-primary" if h > w else "landscape-primary"


## ============================================
## ===== Firebase JS SDK Initialization =====
## ============================================

## Initialize Firebase JavaScript SDK via GDScript's JavaScript bridge
func _init_firebase_js() -> void:
	print("[WebInit] Initializing Firebase JS SDK...")

	## Step 1: Inject the Firebase JS SDK scripts if not already loaded
	_inject_firebase_scripts()

	## Step 2: Configure Firebase after scripts load
	await get_tree().create_timer(1.0).timeout  ## Give scripts time to load

	## Try to read config from window.__FIREBASE_CONFIG__ (set in index.html)
	var config_json = JavaScriptBridge.eval("JSON.stringify(window.__FIREBASE_CONFIG__ || null)")
	if config_json != null and config_json != "null":
		var json := JSON.new()
		if json.parse(str(config_json)) == OK and json.data is Dictionary:
			firebase_js_config = json.data

	## If config is empty, skip JS SDK init (REST API will be used instead)
	if firebase_js_config.is_empty():
		print("[WebInit] No Firebase JS config found — using REST API only")
		firebase_js_failed.emit("No Firebase JS config available. REST API will be used.")
		return

	## Step 3: Initialize Firebase app via JS bridge
	var init_code := """
	(function() {
		try {
			if (typeof firebase === 'undefined') {
				return JSON.stringify({error: 'Firebase SDK not loaded'});
			}
			var config = window.__FIREBASE_CONFIG__;
			if (!config) {
				return JSON.stringify({error: 'No Firebase config'});
			}
			if (firebase.apps.length > 0) {
				firebase.app().delete().then(function() {
					firebase.initializeApp(config);
				});
			} else {
				firebase.initializeApp(config);
			}
			return JSON.stringify({success: true, appName: firebase.app().name});
		} catch(e) {
			return JSON.stringify({error: e.message || String(e)});
		}
	})()
	"""

	var result = JavaScriptBridge.eval(init_code)
	if result != null:
		var json := JSON.new()
		if json.parse(str(result)) == OK and json.data is Dictionary:
			var data: Dictionary = json.data
			if data.get("success", false):
				firebase_js_initialized = true
				firebase_js_ready.emit()
				print("[WebInit] Firebase JS SDK initialized: %s" % data.get("appName", "default"))
			else:
				var err = data.get("error", "Unknown error")
				print("[WebInit] Firebase JS init failed: %s" % err)
				firebase_js_failed.emit(err)
	else:
		firebase_js_failed.emit("JavaScript eval returned null")
		print("[WebInit] Firebase JS init: eval returned null")


## Inject Firebase SDK script tags into the page
func _inject_firebase_scripts() -> void:
	## Check if Firebase is already loaded
	var already_loaded = JavaScriptBridge.eval("typeof firebase !== 'undefined'")
	if already_loaded == true:
		print("[WebInit] Firebase SDK already loaded")
		return

	## Load Firebase compat SDK (modular SDK requires ES modules which are harder with eval)
	## Using the compat version for simplicity with JavaScriptBridge.eval()
	var inject_code := """
	(function() {
		if (typeof firebase !== 'undefined') return;
		var scripts = [
			'https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js',
			'https://www.gstatic.com/firebasejs/10.12.0/firebase-auth-compat.js',
			'https://www.gstatic.com/firebasejs/10.12.0/firebase-firestore-compat.js',
			'https://www.gstatic.com/firebasejs/10.12.0/firebase-database-compat.js'
		];
		var loaded = 0;
		var total = scripts.length;
		function onAllLoaded() {
			window.__FIREBASE_SDK_LOADED__ = true;
			console.log('[WebInit] All Firebase scripts loaded');
		}
		scripts.forEach(function(src) {
			if (document.querySelector('script[src="' + src + '"]')) {
				loaded++;
				if (loaded === total) onAllLoaded();
				return;
			}
			var s = document.createElement('script');
			s.src = src;
			s.async = false;
			s.onload = function() {
				loaded++;
				if (loaded === total) onAllLoaded();
			};
			s.onerror = function() {
				loaded++;
				console.error('[WebInit] Failed to load: ' + src);
				if (loaded === total) onAllLoaded();
			};
			document.head.appendChild(s);
		});
	})()
	"""
	JavaScriptBridge.eval(inject_code)
	print("[WebInit] Firebase SDK injection started")


## Check if Firebase JS SDK is available
func is_firebase_js_available() -> bool:
	if not is_web_platform:
		return false
	var result = JavaScriptBridge.eval("typeof firebase !== 'undefined' && typeof firebase.apps !== 'undefined'")
	return result == true


## ============================================
## ===== Service Worker Setup =====
## ============================================

## Register a service worker for offline caching
func _register_service_worker() -> void:
	var register_code := """
	(function() {
		if ('serviceWorker' in navigator) {
			navigator.serviceWorker.register('/sw.js')
				.then(function(reg) {
					console.log('[WebInit] Service Worker registered:', reg.scope);
					return JSON.stringify({success: true, scope: reg.scope});
				})
				.catch(function(err) {
					console.error('[WebInit] SW registration failed:', err);
					return JSON.stringify({success: false, error: err.message});
				});
		} else {
			return JSON.stringify({success: false, error: 'Service workers not supported'});
		}
	})()
	"""

	var result = JavaScriptBridge.eval(register_code)
	## Note: serviceWorker.register returns a Promise, so eval gets the stringified promise
	## We use a callback approach instead
	_setup_sw_callback()
	print("[WebInit] Service worker registration initiated")


## Setup callback for service worker registration result
func _setup_sw_callback() -> void:
	var callback_code := """
	(function() {
		if ('serviceWorker' in navigator) {
			navigator.serviceWorker.ready.then(function(reg) {
				window.__SW_REGISTERED__ = true;
				window.__SW_SCOPE__ = reg.scope;
			});
			navigator.serviceWorker.addEventListener('controllerchange', function() {
				console.log('[WebInit] Service worker controller changed');
			});
		}
	})()
	"""
	JavaScriptBridge.eval(callback_code)


## Check service worker status
func get_sw_status() -> Dictionary:
	if not is_web_platform:
		return {"supported": false, "registered": false}

	var supported = JavaScriptBridge.eval("'serviceWorker' in navigator") == true
	var registered = JavaScriptBridge.eval("window.__SW_REGISTERED__ === true") == true
	var scope = JavaScriptBridge.eval("window.__SW_SCOPE__ || ''")

	return {
		"supported": supported,
		"registered": registered,
		"scope": str(scope) if scope != null else ""
	}


## ============================================
## ===== PWA Install Prompt =====
## ============================================

## Setup the beforeinstallprompt event listener
func _setup_pwa_prompt() -> void:
	var code := """
	(function() {
		window.__PWA_DEFERRED_PROMPT__ = null;
		window.__PWA_CAN_INSTALL__ = false;
		window.addEventListener('beforeinstallprompt', function(e) {
			e.preventDefault();
			window.__PWA_DEFERRED_PROMPT__ = e;
			window.__PWA_CAN_INSTALL__ = true;
			console.log('[WebInit] PWA install prompt captured');
		});
		window.addEventListener('appinstalled', function(e) {
			window.__PWA_CAN_INSTALL__ = false;
			window.__PWA_DEFERRED_PROMPT__ = null;
			console.log('[WebInit] PWA installed');
		});
	})()
	"""
	JavaScriptBridge.eval(code)


## Check if PWA install is available
func can_install_pwa() -> bool:
	if not is_web_platform:
		return false
	var result = JavaScriptBridge.eval("window.__PWA_CAN_INSTALL__ === true")
	return result == true


## Trigger the PWA install prompt (call from GDScript)
func trigger_pwa_install() -> void:
	if not can_install_pwa():
		print("[WebInit] PWA install not available")
		return

	var code = """
	(function() {
		var promptEvent = window.__PWA_DEFERRED_PROMPT__;
		if (!promptEvent) return JSON.stringify({success: false, error: 'No prompt'});

		promptEvent.prompt();
		return promptEvent.userChoice.then(function(choiceResult) {
			window.__PWA_DEFERRED_PROMPT__ = null;
			window.__PWA_CAN_INSTALL__ = false;
			return JSON.stringify({
				success: true,
				outcome: choiceResult.outcome  // 'accepted' or 'dismissed'
			});
		});
	})()
	"""

	## The above returns a Promise, so we use a callback approach
	var callback_code = """
	(function() {
		var promptEvent = window.__PWA_DEFERRED_PROMPT__;
		if (!promptEvent) {
			window.__PWA_INSTALL_RESULT__ = {success: false, error: 'No prompt'};
			return;
		}
		promptEvent.prompt();
		promptEvent.userChoice.then(function(choiceResult) {
			window.__PWA_INSTALL_RESULT__ = {
				success: true,
				outcome: choiceResult.outcome
			};
			window.__PWA_DEFERRED_PROMPT__ = null;
			window.__PWA_CAN_INSTALL__ = false;
		});
	})()
	"""
	JavaScriptBridge.eval(callback_code)

	## Check result after a delay
	await get_tree().create_timer(3.0).timeout

	var result = JavaScriptBridge.eval("JSON.stringify(window.__PWA_INSTALL_RESULT__ || null)")
	if result != null and result != "null":
		var json := JSON.new()
		if json.parse(str(result)) == OK and json.data is Dictionary:
			var data: Dictionary = json.data
			if data.get("success", false):
				var outcome: String = data.get("outcome", "dismissed")
				if outcome == "accepted":
					pwa_install_completed.emit()
					print("[WebInit] PWA install accepted")
				else:
					pwa_install_dismissed.emit()
					print("[WebInit] PWA install dismissed")
			else:
				print("[WebInit] PWA install failed: %s" % data.get("error", "unknown"))


## ============================================
## ===== Screen Orientation =====
## ============================================

## Lock screen orientation for mobile web
func _lock_screen_orientation() -> void:
	if not is_mobile_web:
		return

	## Lock to portrait on mobile web (better UX for trading app)
	var lock_code = """
	(function() {
		try {
			var lock = screen.orientation.lock('portrait');
			if (lock && lock.catch) {
				lock.catch(function(err) {
					console.log('[WebInit] Orientation lock not supported:', err.message);
				});
			}
			return true;
		} catch(e) {
			console.log('[WebInit] Orientation lock failed:', e.message);
			return false;
		}
	})()
	"""
	var result = JavaScriptBridge.eval(lock_code)
	if result == true:
		print("[WebInit] Screen orientation locked to portrait")
	else:
		print("[WebInit] Screen orientation lock not available")


## Lock to a specific orientation
func lock_orientation(mode: String) -> void:
	if not is_web_platform:
		return

	var valid_modes := ["portrait", "landscape", "portrait-primary", "portrait-secondary",
		"landscape-primary", "landscape-secondary", "any", "natural"]
	if mode not in valid_modes:
		print("[WebInit] Invalid orientation mode: %s" % mode)
		return

	var code = "screen.orientation.lock('%s').catch(function(){})" % mode
	JavaScriptBridge.eval(code)


## Unlock orientation
func unlock_orientation() -> void:
	if not is_web_platform:
		return
	JavaScriptBridge.eval("screen.orientation.unlock()")


## Add orientation change listener
func _setup_orientation_listener() -> void:
	var code = """
	(function() {
		screen.orientation.addEventListener('change', function() {
			window.__CURRENT_ORIENTATION__ = screen.orientation.type;
		});
		window.__CURRENT_ORIENTATION__ = screen.orientation.type || 'unknown';
	})()
	"""
	JavaScriptBridge.eval(code)


## Get current orientation
func get_orientation() -> String:
	if not is_web_platform:
		return "unknown"
	var result = JavaScriptBridge.eval("window.__CURRENT_ORIENTATION__ || screen.orientation.type || 'unknown'")
	if result != null:
		current_orientation = str(result)
		orientation_changed.emit(current_orientation)
	return current_orientation


## ============================================
## ===== Viewport Management =====
## ============================================

## Setup proper viewport meta tag for mobile
func _setup_viewport() -> void:
	if not is_web_platform:
		return

	## Ensure viewport meta tag exists with proper settings
	var viewport_code = """
	(function() {
		var meta = document.querySelector('meta[name="viewport"]');
		if (!meta) {
			meta = document.createElement('meta');
			meta.name = 'viewport';
			document.head.appendChild(meta);
		}
		meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';

		## Prevent pinch-to-zoom
		document.addEventListener('gesturestart', function(e) { e.preventDefault(); });
		document.addEventListener('gesturechange', function(e) { e.preventDefault(); });

		## Prevent double-tap zoom
		var lastTouchEnd = 0;
		document.addEventListener('touchend', function(e) {
			var now = Date.now();
			if (now - lastTouchEnd <= 300) { e.preventDefault(); }
			lastTouchEnd = now;
		}, false);

		## Set theme-color meta tag
		var themeMeta = document.querySelector('meta[name="theme-color"]');
		if (!themeMeta) {
			themeMeta = document.createElement('meta');
			themeMeta.name = 'theme-color';
			document.head.appendChild(themeMeta);
		}
		themeMeta.content = '#1a1a2e';

		## Set apple-mobile-web-app-capable for iOS
		var appleMeta = document.querySelector('meta[name="apple-mobile-web-app-capable"]');
		if (!appleMeta) {
			appleMeta = document.createElement('meta');
			appleMeta.name = 'apple-mobile-web-app-capable';
			document.head.appendChild(appleMeta);
		}
		appleMeta.content = 'yes';

		## Safe area insets
		var safeTop = getComputedStyle(document.documentElement).getPropertyValue('env(safe-area-inset-top)');
		var safeBottom = getComputedStyle(document.documentElement).getPropertyValue('env(safe-area-inset-bottom)');
		window.__SAFE_AREA__ = {
			top: parseInt(safeTop) || 0,
			bottom: parseInt(safeBottom) || 0
		};

		return JSON.stringify(window.__SAFE_AREA__);
	})()
	"""
	var result = JavaScriptBridge.eval(viewport_code)
	if result != null:
		print("[WebInit] Viewport configured")
		viewport_size = DisplayServer.screen_get_size()
		viewport_changed.emit(viewport_size)


## Get safe area insets (for notch/gesture bar)
func get_safe_area() -> Dictionary:
	if not is_web_platform:
		return {"top": 0, "bottom": 0, "left": 0, "right": 0}

	var result = JavaScriptBridge.eval("JSON.stringify(window.__SAFE_AREA__ || {top:0, bottom:0})")
	if result != null and result != "null":
		var json := JSON.new()
		if json.parse(str(result)) == OK and json.data is Dictionary:
			var data: Dictionary = json.data
			return {
				"top": int(data.get("top", 0)),
				"bottom": int(data.get("bottom", 0)),
				"left": 0,
				"right": 0
			}
	return {"top": 0, "bottom": 0, "left": 0, "right": 0}


## Prevent scrolling / bouncing on iOS Safari
func prevent_page_scroll() -> void:
	if not is_web_platform:
		return

	var code = """
	(function() {
		document.body.style.overflow = 'hidden';
		document.body.style.position = 'fixed';
		document.body.style.width = '100%';
		document.body.style.height = '100%';
		document.documentElement.style.overflow = 'hidden';
		document.documentElement.style.position = 'fixed';
		document.documentElement.style.width = '100%';
		document.documentElement.style.height = '100%';
	})()
	"""
	JavaScriptBridge.eval(code)


## ============================================
## ===== Connectivity Listeners =====
## ============================================

## Setup online/offline event listeners via JS
func _setup_connectivity_listeners() -> void:
	var code = """
	(function() {
		window.__IS_ONLINE__ = navigator.onLine;

		window.addEventListener('online', function() {
			window.__IS_ONLINE__ = true;
			console.log('[WebInit] Back online');
		});

		window.addEventListener('offline', function() {
			window.__IS_ONLINE__ = false;
			console.log('[WebInit] Went offline');
		});

		return navigator.onLine;
	})()
	"""
	var result = JavaScriptBridge.eval(code)
	if result != null:
		var initial_online := bool(result)
		online_status_changed.emit(initial_online)
		print("[WebInit] Initial online status: %s" % str(initial_online))


## Check current online status
func is_online() -> bool:
	if not is_web_platform:
		return true  ## Assume online for non-web
	var result = JavaScriptBridge.eval("window.__IS_ONLINE__ !== false && navigator.onLine")
	return result != false


## ============================================
## ===== Periodic Checks =====
## ============================================

## Periodic web environment checks
func _periodic_check() -> void:
	if not is_web_platform:
		return

	## Check online status
	var online_now := is_online()
	online_status_changed.emit(online_now)

	## Check orientation
	if is_mobile_web:
		get_orientation()

	## Check viewport size
	var new_size := DisplayServer.screen_get_size()
	if new_size != viewport_size:
		viewport_size = new_size
		viewport_changed.emit(viewport_size)


## ============================================
## ===== Utility Functions =====
## ============================================

## Get browser/user agent info
func get_browser_info() -> Dictionary:
	if not is_web_platform:
		return {"browser": "unknown", "os": "unknown"}

	var ua = JavaScriptBridge.eval("navigator.userAgent")
	if ua == null:
		return {"browser": "unknown", "os": "unknown"}

	var ua_str: String = str(ua)
	var browser := "unknown"
	var os := "unknown"

	## Detect browser
	if ua_str.find("Firefox/") >= 0:
		browser = "Firefox"
	elif ua_str.find("Edg/") >= 0:
		browser = "Edge"
	elif ua_str.find("Chrome/") >= 0:
		browser = "Chrome"
	elif ua_str.find("Safari/") >= 0:
		browser = "Safari"

	## Detect OS
	if ua_str.find("Windows") >= 0:
		os = "Windows"
	elif ua_str.find("Mac OS") >= 0:
		os = "macOS"
	elif ua_str.find("Android") >= 0:
		os = "Android"
	elif ua_str.find("iPhone") >= 0 or ua_str.find("iPad") >= 0:
		os = "iOS"
	elif ua_str.find("Linux") >= 0:
		os = "Linux"

	return {
		"browser": browser,
		"os": os,
		"user_agent": ua_str,
		"language": str(JavaScriptBridge.eval("navigator.language || 'en'")),
		"screen_resolution": "%dx%d" % [viewport_size.x, viewport_size.y],
		"device_pixel_ratio": str(JavaScriptBridge.eval("window.devicePixelRatio || 1")),
		"is_mobile_web": is_mobile_web,
		"is_pwa": is_pwa,
		"is_standalone": is_standalone
	}


## Get full web environment status
func get_web_status() -> Dictionary:
	return {
		"is_web": is_web_platform,
		"is_mobile": is_mobile_web,
		"is_pwa": is_pwa,
		"is_standalone": is_standalone,
		"cross_origin_isolated": is_cross_origin_isolated,
		"firebase_js_ready": firebase_js_initialized,
		"firebase_js_available": is_firebase_js_available(),
		"service_worker_registered": sw_registered,
		"sw_status": get_sw_status(),
		"can_install_pwa": can_install_pwa(),
		"online": is_online(),
		"orientation": current_orientation,
		"viewport": Vector2i(viewport_size),
		"safe_area": get_safe_area(),
		"browser_info": get_browser_info()
	}


## Show a JavaScript alert (useful for debugging on web)
func js_alert(message: String) -> void:
	if not is_web_platform:
		return
	var safe_msg = message.replace("'", "\\'").replace("\n", "\\n")
	JavaScriptBridge.eval("alert('%s')" % safe_msg)


## Execute arbitrary JavaScript and return result
func eval_js(code: String) -> Variant:
	if not is_web_platform:
		return null
	return JavaScriptBridge.eval(code)


## ============================================
## ===== Cleanup =====
## ============================================

func _exit_tree() -> void:
	if _check_timer:
		_check_timer.stop()
	print("[WebInit] Cleaned up")
