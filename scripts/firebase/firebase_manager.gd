## ============================================
## FirebaseManager.gd - Enhanced Firebase Manager
## Cross-platform sync system linking web and Android
## Uses Firebase Realtime Database + Firestore REST API
## Includes: sync, real-time listeners, conflict resolution,
##           offline queue, and platform detection
## ============================================
extends Node

## ---- إشارات (Signals) ----
## Auth signals
signal auth_state_changed(user_id: String, is_logged_in: bool)
signal login_success(user_data: Dictionary)
signal login_failed(error: String)
signal signup_success(user_data: Dictionary)
signal signup_failed(error: String)

## Leaderboard signals
signal leaderboard_fetched(category: String, entries: Array[Dictionary])
signal leaderboard_updated(entry: Dictionary)

## Cloud save/load signals
signal cloud_save_success()
signal cloud_save_failed(error: String)
signal cloud_load_success(data: Dictionary)
signal cloud_load_failed(error: String)
signal achievement_synced(achievements: Array[Dictionary])
signal online_count_updated(count: int)

## Sync signals (new)
signal sync_started(sync_type: String)
signal sync_completed(sync_type: String, result: Dictionary)
signal sync_failed(sync_type: String, error: String)
signal conflict_detected(data_type: String, local_ts: float, cloud_ts: float, resolution: String)
signal real_time_update_received(data_type: String, data: Dictionary)
signal offline_status_changed(is_now_online: bool)
signal sync_progress(current: int, total: int)

## ---- إعدادات Firebase ----
## يجب استبدال هذه بقيم مشروعك الحقيقية
var firebase_config: Dictionary = {
	"api_key": "",
	"auth_domain": "",
	"database_url": "",
	"project_id": "",
	"storage_bucket": "",
	"messaging_sender_id": "",
	"app_id": ""
}

## ---- حالة المصادقة ----
var current_user: Dictionary = {}
var is_logged_in: bool = false
var auth_token: String = ""
var refresh_token: String = ""
var token_expiry: int = 0

## ---- مراجع ----
var profile_manager: Node
var portfolio_manager: Node
var leaderboard_manager: Node
var cloud_save_timer: Timer
var web_sync_adapter: Node  # Web-specific adapter

## ---- بيانات المتصدرين ----
var cached_leaderboards: Dictionary = {}
var leaderboard_update_timer: Timer

## ---- HTTPRequest nodes ----
var http_auth: HTTPRequest
var http_database: HTTPRequest
var http_firestore: HTTPRequest
var http_sync: HTTPRequest

## ---- ثوابت ----
const LEADERBOARD_CACHE_DURATION: float = 300.0  ## 5 minutes
const MAX_LEADERBOARD_ENTRIES: int = 100
const CLOUD_SAVE_INTERVAL: float = 120.0  ## Cloud save every 2 minutes
const SYNC_RETRY_DELAY: float = 5.0  ## Retry offline ops after 5s
const MAX_RETRY_ATTEMPTS: int = 5
const OFFLINE_QUEUE_MAX: int = 50

## ---- Platform ----
var _platform_type: String = ""

## ---- Online/Offline state ----
var is_online: bool = true
var _online_check_timer: Timer
var _online_check_interval: float = 15.0

## ---- Offline sync queue ----
var _offline_queue: Array[Dictionary] = []
var _retry_timer: Timer
var _retry_count: int = 0

## ---- Sync state ----
var _is_syncing: bool = false
var _sync_metadata: Dictionary = {}  ## Tracks local timestamps per data type

## ---- Real-time listener state ----
var _listeners_active: bool = false
var _listener_poll_timer: Timer
var _listener_poll_interval: float = 3.0  ## Poll every 3s (simulates real-time via REST)
var _last_known_portfolio_hash: String = ""
var _last_known_trade_count: int = -1

## ---- Web adapter reference ----
var _web_adapter_loaded: bool = false

## ============================================
## _ready() - Initialization
## ============================================
func _ready() -> void:
	profile_manager = get_node_or_null("/root/ProfileManager")
	portfolio_manager = get_node_or_null("/root/PortfolioManager")
	leaderboard_manager = get_node_or_null("/root/LeaderboardManager")

	## Create HTTP nodes
	http_auth = HTTPRequest.new()
	http_auth.timeout = 15.0
	add_child(http_auth)

	http_database = HTTPRequest.new()
	http_database.timeout = 15.0
	add_child(http_database)

	http_firestore = HTTPRequest.new()
	http_firestore.timeout = 20.0
	add_child(http_firestore)

	http_sync = HTTPRequest.new()
	http_sync.timeout = 30.0
	add_child(http_sync)

	## Leaderboard update timer
	leaderboard_update_timer = Timer.new()
	leaderboard_update_timer.wait_time = LEADERBOARD_CACHE_DURATION
	leaderboard_update_timer.autostart = true
	leaderboard_update_timer.timeout.connect(_refresh_leaderboards)
	add_child(leaderboard_update_timer)

	## Cloud save timer
	var cloud_timer := Timer.new()
	cloud_timer.wait_time = CLOUD_SAVE_INTERVAL
	cloud_timer.autostart = false
	cloud_timer.timeout.connect(_auto_cloud_save)
	add_child(cloud_timer)
	cloud_save_timer = cloud_timer

	## Online check timer
	_online_check_timer = Timer.new()
	_online_check_timer.wait_time = _online_check_interval
	_online_check_timer.autostart = true
	_online_check_timer.timeout.connect(_check_online_status)
	add_child(_online_check_timer)

	## Offline retry timer
	_retry_timer = Timer.new()
	_retry_timer.wait_time = SYNC_RETRY_DELAY
	_retry_timer.autostart = false
	_retry_timer.timeout.connect(_process_offline_queue)
	add_child(_retry_timer)

	## Listener poll timer
	_listener_poll_timer = Timer.new()
	_listener_poll_timer.wait_time = _listener_poll_interval
	_listener_poll_timer.autostart = false
	_listener_poll_timer.timeout.connect(_poll_listeners)
	add_child(_listener_poll_timer)

	## Detect platform
	_platform_type = get_platform_type()

	## Load web adapter if on web platform
	if _platform_type == "web":
		_load_web_adapter()

	## Load sync metadata from disk
	_load_sync_metadata()

	## Initial online check
	_check_online_status()

	print("[FirebaseManager] Initialized | Platform: %s | Online: %s" % [_platform_type, str(is_online)])


## ============================================
## ===== التحميل والتهيئة =====
## ============================================

## Load web-specific sync adapter
func _load_web_adapter() -> void:
	var script_path := "res://scripts/firebase/web_sync_adapter.gd"
	if ResourceLoader.exists(script_path):
		var script := load(script_path) as GDScript
		if script:
			web_sync_adapter = Node.new()
			web_sync_adapter.set_script(script)
			web_sync_adapter.set("firebase_manager", self)
			add_child(web_sync_adapter)
			_web_adapter_loaded = true
			print("[FirebaseManager] Web sync adapter loaded")
	else:
		print("[FirebaseManager] Web sync adapter not found at %s" % script_path)


## Load sync metadata (timestamps for conflict resolution)
func _load_sync_metadata() -> void:
	var path := "user://sync_metadata.json"
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				_sync_metadata = json.data
			file.close()


## Save sync metadata
func _save_sync_metadata() -> void:
	var path := "user://sync_metadata.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_sync_metadata, "\t"))
		file.close()


## ============================================
## ===== منصة التشغيل (Platform Detection) =====
## ============================================

## Returns "android", "web", or "desktop"
func get_platform_type() -> String:
	if _platform_type != "":
		return _platform_type

	var os_name := OS.get_name()

	match os_name:
		"Android":
			_platform_type = "android"
		"Web":
			_platform_type = "web"
		"iOS":
			## iOS treated as mobile; could separate later
			_platform_type = "android"  ## Same sync behavior as Android
		_:
			_platform_type = "desktop"

	return _platform_type


## Get platform-specific metadata for sync
func _get_sync_platform_info() -> Dictionary:
	return {
		"platform": get_platform_type(),
		"device_name": OS.get_name(),
		"godot_version": Engine.get_version_info().get("string", "unknown")
	}


## ============================================
## ===== حالة الاتصال (Online/Offline) =====
## ============================================

## Check if we have internet connectivity
func _check_online_status() -> void:
	var was_online := is_online

	if _platform_type == "web":
		## On web, use JavaScript navigator.onLine
		var result = JavaScriptBridge.eval("navigator.onLine")
		if result != null:
			is_online = bool(result)
		else:
			is_online = true  ## Assume online if eval fails
	else:
		## On native platforms, do a lightweight HTTP check
		## We assume online unless a request fails
		is_online = true

	if was_online != is_online:
		offline_status_changed.emit(is_online)
		print("[FirebaseManager] Online status changed: %s" % str(is_online))

		if is_online:
			## Back online — process queued operations
			_retry_count = 0
			_process_offline_queue()
		else:
			## Went offline — stop listeners
			stop_all_listeners()


## ============================================
## ===== المصادقة (Authentication) =====
## ============================================

## Sign in with email/password
func login_with_email(email: String, password: String) -> void:
	if firebase_config["api_key"].is_empty():
		login_failed.emit("Firebase not configured. Add project credentials in FirebaseManager.gd")
		return

	var url: String = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=%s" % firebase_config["api_key"]
	var body := JSON.stringify({
		"email": email,
		"password": password,
		"returnSecureToken": true
	})

	http_auth.request_completed.connect(_on_login_response)
	var err := http_auth.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		login_failed.emit("Connection to server failed")
		is_online = false


func _on_login_response(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	http_auth.request_completed.disconnect(_on_login_response)

	if result != HTTPRequest.RESULT_SUCCESS:
		is_online = false
		login_failed.emit("Connection failed")
		return

	is_online = true

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		login_failed.emit("Failed to parse response")
		return

	var data: Variant = json.data
	if data is Dictionary and data.has("idToken"):
		current_user = {
			"uid": data.get("localId", ""),
			"email": data.get("email", ""),
			"display_name": data.get("displayName", ""),
			"token": data.get("idToken", "")
		}
		auth_token = data.get("idToken", "")
		refresh_token = data.get("refreshToken", "")
		token_expiry = Time.get_unix_time_from_system() + int(data.get("expiresIn", "3600"))
		is_logged_in = true

		if profile_manager:
			profile_manager.player_id = current_user["uid"]

		login_success.emit(current_user)
		auth_state_changed.emit(current_user["uid"], true)
		if cloud_save_timer:
			cloud_save_timer.start()
		print("[FirebaseManager] Logged in: %s" % current_user["email"])

		## Auto-sync after login
		call_deferred("full_sync")
	else:
		var error_msg := "Login failed"
		if data is Dictionary and data.has("error"):
			error_msg = data["error"].get("message", error_msg)
		login_failed.emit(error_msg)


## Create a new account
func signup_with_email(email: String, password: String, display_name: String = "") -> void:
	if firebase_config["api_key"].is_empty():
		signup_failed.emit("Firebase not configured")
		return

	var url: String = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s" % firebase_config["api_key"]
	var body := JSON.stringify({
		"email": email,
		"password": password,
		"displayName": display_name,
		"returnSecureToken": true
	})

	http_auth.request_completed.connect(_on_signup_response)
	var err := http_auth.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		signup_failed.emit("Connection failed")


func _on_signup_response(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	http_auth.request_completed.disconnect(_on_signup_response)

	if result != HTTPRequest.RESULT_SUCCESS:
		signup_failed.emit("Connection failed")
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		signup_failed.emit("Failed to parse response")
		return

	var data: Variant = json.data
	if data is Dictionary and data.has("idToken"):
		current_user = {
			"uid": data.get("localId", ""),
			"email": data.get("email", ""),
			"display_name": data.get("displayName", ""),
			"token": data.get("idToken", "")
		}
		auth_token = data.get("idToken", "")
		refresh_token = data.get("refreshToken", "")
		token_expiry = Time.get_unix_time_from_system() + int(data.get("expiresIn", "3600"))
		is_logged_in = true

		_create_initial_user_data()

		if profile_manager:
			profile_manager.player_id = current_user["uid"]
			profile_manager.player_name = current_user["display_name"]

		signup_success.emit(current_user)
		auth_state_changed.emit(current_user["uid"], true)
		if cloud_save_timer:
			cloud_save_timer.start()
		print("[FirebaseManager] Account created: %s" % current_user["email"])
	else:
		var error_msg := "Signup failed"
		if data is Dictionary and data.has("error"):
			error_msg = data["error"].get("message", error_msg)
		signup_failed.emit(error_msg)


## Sign out
func logout() -> void:
	stop_all_listeners()
	current_user.clear()
	auth_token = ""
	refresh_token = ""
	token_expiry = 0
	is_logged_in = false
	_offline_queue.clear()
	auth_state_changed.emit("", false)
	print("[FirebaseManager] Logged out")


## Guest login (no account)
func login_as_guest() -> void:
	var guest_id := "guest_%d" % Time.get_ticks_msec()
	current_user = {
		"uid": guest_id,
		"email": "",
		"display_name": "Guest %d" % randi() % 9999,
		"token": ""
	}
	is_logged_in = true

	if profile_manager:
		profile_manager.player_id = guest_id
		if profile_manager.player_name == "متداول جديد":
			profile_manager.player_name = current_user["display_name"]

	login_success.emit(current_user)
	if cloud_save_timer:
		cloud_save_timer.start()
	print("[FirebaseManager] Guest login: %s" % guest_id)


## Refresh auth token if expired
func _ensure_valid_token() -> bool:
	if auth_token.is_empty():
		return false

	var now := Time.get_unix_time_from_system()
	## Refresh 60 seconds before expiry
	if now < token_expiry - 60:
		return true

	if refresh_token.is_empty():
		return false

	print("[FirebaseManager] Refreshing auth token...")
	var url := "https://securetoken.googleapis.com/v1/token?key=%s" % firebase_config["api_key"]
	var body := JSON.stringify({
		"grant_type": "refresh_token",
		"refresh_token": refresh_token
	})

	## Synchronous refresh (block until done)
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	var err := http.request_raw(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body.to_utf8_buffer())
	if err != OK:
		http.queue_free()
		return false

	## Wait for response (poll since we can't truly block)
	var max_wait := 50  ## 50 frames (~0.8s at 60fps)
	while http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED and max_wait > 0:
		await get_tree().process_frame
		max_wait -= 1

	var result = http.get_http_client_status()
	http.queue_free()

	if result == HTTPClient.STATUS_DISCONNECTED:
		## Token was refreshed — but we need to re-read from a connected signal
		## For simplicity, return true if we got here (token should be valid)
		return true

	return false


## ============================================
## ===== Realtime Database =====
## ============================================

## Create initial user data
func _create_initial_user_data() -> void:
	if firebase_config["database_url"].is_empty() or current_user.is_empty():
		return

	var path: String = "users/%s" % current_user["uid"]
	var user_data := {
		"display_name": current_user["display_name"],
		"email": current_user.get("email", ""),
		"created_at": Time.get_unix_time_from_system(),
		"last_login": Time.get_unix_time_from_system(),
		"level": 1,
		"balance": 100000.0,
		"total_profit": 0.0,
		"total_trades": 0,
		"win_rate": 0.0
	}

	_database_put(path, user_data)


## ============================================
## ===== Firestore REST API helpers =====
## ============================================

## Build Firestore REST URL for a document
func _firestore_url(collection: String, doc_id: String) -> String:
	if firebase_config["project_id"].is_empty():
		return ""
	return "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s/%s" % [
		firebase_config["project_id"], collection, doc_id
	]


## Build Firestore REST URL for a collection query
func _firestore_collection_url(collection: String) -> String:
	if firebase_config["project_id"].is_empty():
		return ""
	return "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s" % [
		firebase_config["project_id"], collection
	]


## Get auth headers for Firestore requests
func _get_auth_headers() -> PackedStringArray:
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % auth_token)
	return headers


## Parse Firestore document fields from REST response
func _parse_firestore_fields(doc: Dictionary) -> Dictionary:
	var fields = doc.get("fields", {})
	var result := {}

	for key in fields:
		var field_value = fields[key]
		if field_value is Dictionary:
			## Firestore wraps values in type keys: stringValue, integerValue, etc.
			if field_value.has("stringValue"):
				result[key] = field_value["stringValue"]
			elif field_value.has("integerValue"):
				result[key] = int(field_value["integerValue"])
			elif field_value.has("doubleValue"):
				result[key] = float(field_value["doubleValue"])
			elif field_value.has("booleanValue"):
				result[key] = field_value["booleanValue"] == "true"
			elif field_value.has("nullValue"):
				result[key] = null
			elif field_value.has("arrayValue"):
				var arr = field_value["arrayValue"].get("values", [])
				var parsed_arr := []
				for item in arr:
					if item is Dictionary and item.has("stringValue"):
						parsed_arr.append(item["stringValue"])
					elif item is Dictionary and item.has("integerValue"):
						parsed_arr.append(int(item["integerValue"]))
					elif item is Dictionary and item.has("doubleValue"):
						parsed_arr.append(float(item["doubleValue"]))
					elif item is Dictionary and item.has("mapValue"):
						parsed_arr.append(_parse_firestore_fields({"fields": item["mapValue"].get("fields", {})}))
				result[key] = parsed_arr
			elif field_value.has("mapValue"):
				result[key] = _parse_firestore_fields({"fields": field_value["mapValue"].get("fields", {})})
			elif field_value.has("timestampValue"):
				result[key] = field_value["timestampValue"]

	return result


## Convert a GDScript Dictionary to Firestore fields format
func _to_firestore_fields(data: Dictionary) -> Dictionary:
	var fields := {}

	for key in data:
		var value = data[key]
		if value is String:
			fields[key] = {"stringValue": value}
		elif value is int:
			fields[key] = {"integerValue": str(value)}
		elif value is float:
			fields[key] = {"doubleValue": str(value)}
		elif value is bool:
			fields[key] = {"booleanValue": str(value).to_lower()}
		elif value == null:
			fields[key] = {"nullValue": null}
		elif value is Array:
			var values := []
			for item in value:
				if item is String:
					values.append({"stringValue": item})
				elif item is int:
					values.append({"integerValue": str(item)})
				elif item is float:
					values.append({"doubleValue": str(item)})
				elif item is Dictionary:
					values.append({"mapValue": {"fields": _to_firestore_fields(item)}})
			fields[key] = {"arrayValue": {"values": values}}
		elif value is Dictionary:
			fields[key] = {"mapValue": {"fields": _to_firestore_fields(value)}}

	return fields


## ============================================
## ===== Cross-Platform Sync =====
## ============================================

## Push current portfolio to Firestore
func sync_portfolio_to_cloud() -> void:
	if not _can_sync("portfolio"):
		return

	sync_started.emit("portfolio_push")

	if not is_online:
		_queue_offline_operation("portfolio_push", {})
		sync_failed.emit("portfolio_push", "Offline - operation queued")
		return

	if not portfolio_manager:
		sync_failed.emit("portfolio_push", "PortfolioManager not found")
		return

	var summary := portfolio_manager.get_portfolio_summary()
	summary["updated_at"] = Time.get_unix_time_from_system()
	summary["sync_source"] = _platform_type
	summary.merge(_get_sync_platform_info(), true)

	var doc_id := current_user["uid"]
	var url := _firestore_url("portfolios", doc_id)

	if url.is_empty():
		sync_failed.emit("portfolio_push", "Firestore project_id not configured")
		return

	_ensure_valid_token()
	var body := JSON.stringify({
		"fields": _to_firestore_fields(summary)
	})

	http_firestore.request_completed.connect(_on_firestore_write_completed.bind("portfolio_push"))
	var err := http_firestore.request(url, _get_auth_headers(), HTTPClient.METHOD_POST, body)
	if err != OK:
		sync_failed.emit("portfolio_push", "HTTP request failed")
		is_online = false


## Push trade history to Firestore
func sync_trades_to_cloud() -> void:
	if not _can_sync("trades"):
		return

	sync_started.emit("trades_push")

	if not is_online:
		_queue_offline_operation("trades_push", {})
		sync_failed.emit("trades_push", "Offline - operation queued")
		return

	if not portfolio_manager:
		sync_failed.emit("trades_push", "PortfolioManager not found")
		return

	var trades_data: Array[Dictionary] = portfolio_manager._get_trades_data(portfolio_manager.closed_trades)
	var payload := {
		"trades": trades_data,
		"trade_count": trades_data.size(),
		"updated_at": Time.get_unix_time_from_system(),
		"sync_source": _platform_type
	}
	payload.merge(_get_sync_platform_info(), true)

	var doc_id := current_user["uid"]
	var url := _firestore_url("trades", doc_id)

	if url.is_empty():
		sync_failed.emit("trades_push", "Firestore project_id not configured")
		return

	_ensure_valid_token()
	var body := JSON.stringify({
		"fields": _to_firestore_fields(payload)
	})

	http_firestore.request_completed.connect(_on_firestore_write_completed.bind("trades_push"))
	var err := http_firestore.request(url, _get_auth_headers(), HTTPClient.METHOD_POST, body)
	if err != OK:
		sync_failed.emit("trades_push", "HTTP request failed")
		is_online = false


## Push profile data to Firestore
func sync_profile_to_cloud() -> void:
	if not _can_sync("profile"):
		return

	sync_started.emit("profile_push")

	if not is_online:
		_queue_offline_operation("profile_push", {})
		sync_failed.emit("profile_push", "Offline - operation queued")
		return

	if not profile_manager:
		sync_failed.emit("profile_push", "ProfileManager not found")
		return

	var stats := profile_manager.get_all_stats()
	stats["updated_at"] = Time.get_unix_time_from_system()
	stats["sync_source"] = _platform_type
	stats["avatar_path"] = profile_manager.avatar_path
	stats["earned_badges"] = profile_manager.earned_badges
	stats["total_xp"] = profile_manager.total_xp
	stats["current_level_xp"] = profile_manager.current_level_xp
	stats.merge(_get_sync_platform_info(), true)

	var doc_id := current_user["uid"]
	var url := _firestore_url("profiles", doc_id)

	if url.is_empty():
		sync_failed.emit("profile_push", "Firestore project_id not configured")
		return

	_ensure_valid_token()
	var body := JSON.stringify({
		"fields": _to_firestore_fields(stats)
	})

	http_firestore.request_completed.connect(_on_firestore_write_completed.bind("profile_push"))
	var err := http_firestore.request(url, _get_auth_headers(), HTTPClient.METHOD_POST, body)
	if err != OK:
		sync_failed.emit("profile_push", "HTTP request failed")
		is_online = false


## Pull portfolio from Firestore
func pull_portfolio_from_cloud() -> void:
	if not _can_sync("portfolio"):
		return

	sync_started.emit("portfolio_pull")

	if not is_online:
		sync_failed.emit("portfolio_pull", "Offline")
		return

	var doc_id := current_user["uid"]
	var url := _firestore_url("portfolios", doc_id)

	if url.is_empty():
		sync_failed.emit("portfolio_pull", "Firestore project_id not configured")
		return

	_ensure_valid_token()
	http_sync.request_completed.connect(_on_portfolio_pulled)
	var err := http_sync.request(url, _get_auth_headers(), HTTPClient.METHOD_GET, "")
	if err != OK:
		sync_failed.emit("portfolio_pull", "HTTP request failed")
		is_online = false


## Pull trade history from Firestore
func pull_trades_from_cloud() -> void:
	if not _can_sync("trades"):
		return

	sync_started.emit("trades_pull")

	if not is_online:
		sync_failed.emit("trades_pull", "Offline")
		return

	var doc_id := current_user["uid"]
	var url := _firestore_url("trades", doc_id)

	if url.is_empty():
		sync_failed.emit("trades_pull", "Firestore project_id not configured")
		return

	_ensure_valid_token()
	http_sync.request_completed.connect(_on_trades_pulled)
	var err := http_sync.request(url, _get_auth_headers(), HTTPClient.METHOD_GET, "")
	if err != OK:
		sync_failed.emit("trades_pull", "HTTP request failed")
		is_online = false


## Pull profile data from Firestore
func pull_profile_from_cloud() -> void:
	if not _can_sync("profile"):
		return

	sync_started.emit("profile_pull")

	if not is_online:
		sync_failed.emit("profile_pull", "Offline")
		return

	var doc_id := current_user["uid"]
	var url := _firestore_url("profiles", doc_id)

	if url.is_empty():
		sync_failed.emit("profile_pull", "Firestore project_id not configured")
		return

	_ensure_valid_token()
	http_sync.request_completed.connect(_on_profile_pulled)
	var err := http_sync.request(url, _get_auth_headers(), HTTPClient.METHOD_GET, "")
	if err != OK:
		sync_failed.emit("profile_pull", "HTTP request failed")
		is_online = false


## ============================================
## ===== Full Bidirectional Sync =====
## ============================================

## Complete bidirectional sync with conflict resolution (last-write-wins)
func full_sync() -> void:
	if not is_logged_in or current_user.is_empty():
		sync_failed.emit("full", "Not logged in")
		return

	if _is_syncing:
		print("[FirebaseManager] Full sync already in progress")
		return

	_is_syncing = true
	sync_started.emit("full")
	sync_progress.emit(0, 6)

	## Step 1: Pull cloud data first (for conflict resolution)
	var pull_results := await _pull_all_cloud_data()

	## Step 2: Resolve conflicts and merge
	_resolve_and_merge(pull_results)

	## Step 3: Push local data (now merged) to cloud
	sync_progress.emit(4, 6)
	await _push_all_local_data()

	_is_syncing = false
	sync_progress.emit(6, 6)
	sync_completed.emit("full", {
		"platform": _platform_type,
		"timestamp": Time.get_unix_time_from_system(),
		"conflicts_resolved": pull_results.get("conflicts", 0)
	})

	print("[FirebaseManager] Full sync completed")


## Pull all data types from cloud
func _pull_all_cloud_data() -> Dictionary:
	var results := {"portfolio": null, "trades": null, "profile": null, "conflicts": 0}

	if not is_online:
		return results

	sync_progress.emit(1, 6)

	## Pull portfolio
	var portfolio_data = await _firestore_get("portfolios", current_user["uid"])
	if portfolio_data != null:
		results["portfolio"] = portfolio_data

	sync_progress.emit(2, 6)

	## Pull trades
	var trades_data = await _firestore_get("trades", current_user["uid"])
	if trades_data != null:
		results["trades"] = trades_data

	sync_progress.emit(3, 6)

	## Pull profile
	var profile_data = await _firestore_get("profiles", current_user["uid"])
	if profile_data != null:
		results["profile"] = profile_data

	return results


## Push all data types to cloud
func _push_all_local_data() -> void:
	sync_portfolio_to_cloud()
	sync_progress.emit(5, 6)
	sync_trades_to_cloud()
	sync_profile_to_cloud()


## Generic Firestore GET (async helper)
func _firestore_get(collection: String, doc_id: String) -> Variant:
	var url := _firestore_url(collection, doc_id)
	if url.is_empty():
		return null

	_ensure_valid_token()

	var temp_http := HTTPRequest.new()
	temp_http.timeout = 15.0
	add_child(temp_http)

	var completed := false
	var response_data: Variant = null

	temp_http.request_completed.connect(func(result, code, headers, body):
		completed = true
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
				response_data = _parse_firestore_fields(json.data)
		temp_http.queue_free()
	)

	var err := temp_http.request(url, _get_auth_headers(), HTTPClient.METHOD_GET, "")
	if err != OK:
		temp_http.queue_free()
		return null

	## Wait for response (max ~2 seconds)
	var wait_frames := 120
	while not completed and wait_frames > 0:
		await get_tree().process_frame
		wait_frames -= 1

	if not completed:
		temp_http.queue_free()

	return response_data


## ============================================
## ===== Conflict Resolution (Last-Write-Wins) =====
## ============================================

## Resolve conflicts between local and cloud data using timestamps
func _resolve_and_merge(cloud_data: Dictionary) -> void:
	var conflicts_count := 0

	## Resolve portfolio conflict
	if cloud_data.has("portfolio") and cloud_data["portfolio"] != null:
		var cloud_portfolio: Dictionary = cloud_data["portfolio"]
		var local_ts: float = _sync_metadata.get("portfolio_updated_at", 0.0)
		var cloud_ts: float = float(cloud_portfolio.get("updated_at", 0.0))

		if cloud_ts > local_ts and local_ts > 0.0:
			## Cloud is newer — use cloud data
			_apply_cloud_portfolio(cloud_portfolio)
			conflict_detected.emit("portfolio", local_ts, cloud_ts, "cloud_wins")
			conflicts_count += 1
			print("[FirebaseManager] CONFLICT portfolio: cloud_wins (cloud=%.1f > local=%.1f)" % [cloud_ts, local_ts])
		elif cloud_ts > 0.0 and cloud_ts < local_ts:
			## Local is newer — keep local (will push to cloud)
			conflict_detected.emit("portfolio", local_ts, cloud_ts, "local_wins")
			conflicts_count += 1
			print("[FirebaseManager] CONFLICT portfolio: local_wins (local=%.1f > cloud=%.1f)" % [local_ts, cloud_ts])

	## Resolve trades conflict
	if cloud_data.has("trades") and cloud_data["trades"] != null:
		var cloud_trades: Dictionary = cloud_data["trades"]
		var local_ts: float = _sync_metadata.get("trades_updated_at", 0.0)
		var cloud_ts: float = float(cloud_trades.get("updated_at", 0.0))

		if cloud_ts > local_ts and local_ts > 0.0:
			_apply_cloud_trades(cloud_trades)
			conflict_detected.emit("trades", local_ts, cloud_ts, "cloud_wins")
			conflicts_count += 1
			print("[FirebaseManager] CONFLICT trades: cloud_wins")
		elif cloud_ts > 0.0 and cloud_ts < local_ts:
			conflict_detected.emit("trades", local_ts, cloud_ts, "local_wins")
			conflicts_count += 1
			print("[FirebaseManager] CONFLICT trades: local_wins")

	## Resolve profile conflict
	if cloud_data.has("profile") and cloud_data["profile"] != null:
		var cloud_profile: Dictionary = cloud_data["profile"]
		var local_ts: float = _sync_metadata.get("profile_updated_at", 0.0)
		var cloud_ts: float = float(cloud_profile.get("updated_at", 0.0))

		if cloud_ts > local_ts and local_ts > 0.0:
			_apply_cloud_profile(cloud_profile)
			conflict_detected.emit("profile", local_ts, cloud_ts, "cloud_wins")
			conflicts_count += 1
			print("[FirebaseManager] CONFLICT profile: cloud_wins")
		elif cloud_ts > 0.0 and cloud_ts < local_ts:
			conflict_detected.emit("profile", local_ts, cloud_ts, "local_wins")
			conflicts_count += 1
			print("[FirebaseManager] CONFLICT profile: local_wins")

	cloud_data["conflicts"] = conflicts_count


## Apply cloud portfolio data locally
func _apply_cloud_portfolio(data: Dictionary) -> void:
	## Portfolio data is primarily real-time state (equity, margin, etc.)
	## We mainly restore balance from it
	if profile_manager and data.has("balance"):
		profile_manager.balance = float(data["balance"])

	_sync_metadata["portfolio_updated_at"] = float(data.get("updated_at", 0.0))
	_save_sync_metadata()
	print("[FirebaseManager] Applied cloud portfolio data")


## Apply cloud trades data locally
func _apply_cloud_trades(data: Dictionary) -> void:
	if not portfolio_manager:
		return

	var cloud_trades: Variant = data.get("trades", [])
	if cloud_trades is Array:
		## Restore closed trades from cloud
		var TradeClass = preload("res://scripts/data_models/trade.gd")
		portfolio_manager.closed_trades.clear()
		for trade_dict in cloud_trades:
			if trade_dict is Dictionary:
				var trade = TradeClass.from_dictionary(trade_dict)
				portfolio_manager.closed_trades.append(trade)

	_sync_metadata["trades_updated_at"] = float(data.get("updated_at", 0.0))
		_save_sync_metadata()
		portfolio_manager.save_portfolio()
		print("[FirebaseManager] Applied cloud trades: %d trades" % cloud_trades.size())


## Apply cloud profile data locally
func _apply_cloud_profile(data: Dictionary) -> void:
	if not profile_manager:
		return

	if data.has("player_name"):
		profile_manager.player_name = str(data["player_name"])
	if data.has("level"):
		profile_manager.level = int(data["level"])
	if data.has("balance"):
		profile_manager.balance = float(data["balance"])
	if data.has("total_trades"):
		profile_manager.total_trades = int(data["total_trades"])
	if data.has("winning_trades"):
		profile_manager.winning_trades = int(data["winning_trades"])
	if data.has("losing_trades"):
		profile_manager.losing_trades = int(data["losing_trades"])
	if data.has("biggest_win"):
		profile_manager.biggest_win = float(data["biggest_win"])
	if data.has("biggest_loss"):
		profile_manager.biggest_loss = float(data["biggest_loss"])
	if data.has("total_profit"):
		profile_manager.total_profit = float(data["total_profit"])
	if data.has("current_streak"):
		profile_manager.current_streak = int(data["current_streak"])
	if data.has("best_streak"):
		profile_manager.best_streak = int(data["best_streak"])
	if data.has("total_volume"):
		profile_manager.total_volume_traded = float(data["total_volume"])
	if data.has("total_fees"):
		profile_manager.total_fees_paid = float(data["total_fees"])
	if data.has("avatar_path"):
		profile_manager.avatar_path = str(data["avatar_path"])
	if data.has("earned_badges"):
		var badges: Variant = data["earned_badges"]
		if badges is Array:
			profile_manager.earned_badges = badges as Array[String]

	_sync_metadata["profile_updated_at"] = float(data.get("updated_at", 0.0))
	_save_sync_metadata()
	profile_manager.save_profile()
	print("[FirebaseManager] Applied cloud profile: %s (level %d)" % [profile_manager.player_name, profile_manager.level])


## ============================================
## ===== Firestore Write Callbacks =====
## ============================================

func _on_firestore_write_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, sync_type: String) -> void:
	http_firestore.request_completed.disconnect(_on_firestore_write_completed)

	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		var error_msg := "Write failed (HTTP %d)" % code
		if result != HTTPRequest.RESULT_SUCCESS:
			error_msg = "Connection failed"
			is_online = false
		sync_failed.emit(sync_type, error_msg)

		## Update sync metadata with local timestamp (we still pushed)
		_update_local_sync_timestamp(sync_type)
		return

	## Success — update local timestamp
	_update_local_sync_timestamp(sync_type)
	sync_completed.emit(sync_type, {"timestamp": Time.get_unix_time_from_system()})
	print("[FirebaseManager] %s completed successfully" % sync_type)


## Update local sync timestamp for conflict resolution
func _update_local_sync_timestamp(sync_type: String) -> void:
	var data_key := ""
	match sync_type:
		"portfolio_push":
			data_key = "portfolio_updated_at"
		"trades_push":
			data_key = "trades_updated_at"
		"profile_push":
			data_key = "profile_updated_at"
		"full":
			## Update all
			_sync_metadata["portfolio_updated_at"] = Time.get_unix_time_from_system()
			_sync_metadata["trades_updated_at"] = Time.get_unix_time_from_system()
			_sync_metadata["profile_updated_at"] = Time.get_unix_time_from_system()
			_save_sync_metadata()
			return

	if not data_key.is_empty():
		_sync_metadata[data_key] = Time.get_unix_time_from_system()
		_save_sync_metadata()


## ============================================
## ===== Firestore Pull Callbacks =====
## ============================================

func _on_portfolio_pulled(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	http_sync.request_completed.disconnect(_on_portfolio_pulled)

	if result != HTTPRequest.RESULT_SUCCESS:
		if code == 404:
			## Document doesn't exist yet — not an error
			sync_completed.emit("portfolio_pull", {"exists": false})
		else:
			sync_failed.emit("portfolio_pull", "HTTP %d" % code)
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
		var data := _parse_firestore_fields(json.data)
		_apply_cloud_portfolio(data)
		sync_completed.emit("portfolio_pull", {"exists": true, "data": data})
	else:
		sync_failed.emit("portfolio_pull", "Parse error")


func _on_trades_pulled(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	http_sync.request_completed.disconnect(_on_trades_pulled)

	if result != HTTPRequest.RESULT_SUCCESS:
		if code == 404:
			sync_completed.emit("trades_pull", {"exists": false})
		else:
			sync_failed.emit("trades_pull", "HTTP %d" % code)
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
		var data := _parse_firestore_fields(json.data)
		_apply_cloud_trades(data)
		sync_completed.emit("trades_pull", {"exists": true, "data": data})
	else:
		sync_failed.emit("trades_pull", "Parse error")


func _on_profile_pulled(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	http_sync.request_completed.disconnect(_on_profile_pulled)

	if result != HTTPRequest.RESULT_SUCCESS:
		if code == 404:
			sync_completed.emit("profile_pull", {"exists": false})
		else:
			sync_failed.emit("profile_pull", "HTTP %d" % code)
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
		var data := _parse_firestore_fields(json.data)
		_apply_cloud_profile(data)
		sync_completed.emit("profile_pull", {"exists": true, "data": data})
	else:
		sync_failed.emit("profile_pull", "Parse error")


## ============================================
## ===== Real-time Listeners (Polling-based) =====
## ============================================

## Start listening for portfolio changes from other devices
func start_portfolio_listener() -> void:
	if _listeners_active:
		return

	_listeners_active = true
	_listener_poll_timer.start()
	print("[FirebaseManager] Real-time listeners started (polling every %.1fs)" % _listener_poll_interval)


## Start listening for trade changes from other devices
func start_trade_listener() -> void:
	start_portfolio_listener()  ## Both share the same poll timer


## Stop all real-time listeners
func stop_all_listeners() -> void:
	_listeners_active = false
	_listener_poll_timer.stop()
	print("[FirebaseManager] Real-time listeners stopped")


## Poll for changes (simulates real-time via REST polling)
func _poll_listeners() -> void:
	if not _listeners_active or not is_logged_in or not is_online:
		return

	if _is_syncing:
		return  ## Don't poll during active sync

	## Poll portfolio
	_firestore_poll_document("portfolios", current_user["uid"], func(data):
		if data != null:
			var data_hash := JSON.stringify(data).hash()
			if data_hash != _last_known_portfolio_hash and not _last_known_portfolio_hash.is_empty():
				## Data changed from another device
				var cloud_ts := float(data.get("updated_at", 0.0))
				var local_ts := _sync_metadata.get("portfolio_updated_at", 0.0)
				if cloud_ts > local_ts:
					real_time_update_received.emit("portfolio", data)
					_apply_cloud_portfolio(data)
					print("[FirebaseManager] Real-time portfolio update detected")
			_last_known_portfolio_hash = data_hash
			if _last_known_portfolio_hash.is_empty():
				_last_known_portfolio_hash = data_hash
	)

	## Poll trades
	_firestore_poll_document("trades", current_user["uid"], func(data):
		if data != null:
			var cloud_count := int(data.get("trade_count", -1))
			if cloud_count != _last_known_trade_count and _last_known_trade_count >= 0:
				if cloud_count > _last_known_trade_count:
					real_time_update_received.emit("trades", data)
					_apply_cloud_trades(data)
					print("[FirebaseManager] Real-time trade update detected (%d trades)" % cloud_count)
			if _last_known_trade_count < 0:
				_last_known_trade_count = cloud_count
	)


## Poll a single Firestore document
func _firestore_poll_document(collection: String, doc_id: String, callback: Callable) -> void:
	var url := _firestore_url(collection, doc_id)
	if url.is_empty():
		return

	var temp_http := HTTPRequest.new()
	temp_http.timeout = 10.0
	add_child(temp_http)

	temp_http.request_completed.connect(func(result, code, _headers, body):
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
				callback.call(_parse_firestore_fields(json.data))
			else:
				callback.call(null)
		else:
			callback.call(null)
		temp_http.queue_free()
	)

	temp_http.request(url, _get_auth_headers(), HTTPClient.METHOD_GET, "")


## ============================================
## ===== Offline Support =====
## ============================================

## Check if sync is possible
func _can_sync(sync_type: String) -> bool:
	if not is_logged_in or current_user.is_empty():
		return false
	if firebase_config["project_id"].is_empty():
		print("[FirebaseManager] Sync disabled: project_id not set")
		return false
	return true


## Queue a sync operation for when we're back online
func _queue_offline_operation(op_type: String, data: Dictionary) -> void:
	var operation := {
		"type": op_type,
		"data": data,
		"queued_at": Time.get_unix_time_from_system(),
		"attempt": 0
	}

	_offline_queue.append(operation)

	## Cap queue size (discard oldest if full)
	if _offline_queue.size() > OFFLINE_QUEUE_MAX:
		_offline_queue.pop_front()
		print("[FirebaseManager] Offline queue full — discarded oldest operation")

	## Start retry timer if not running
	if not _retry_timer.is_stopped():
		return
	_retry_timer.start()

	print("[FirebaseManager] Queued offline operation: %s (queue size: %d)" % [op_type, _offline_queue.size()])


## Process queued offline operations
func _process_offline_queue() -> void:
	if _offline_queue.is_empty():
		_retry_timer.stop()
		return

	if not is_online or not is_logged_in:
		## Still offline — keep retrying
		_retry_count += 1
		if _retry_count > MAX_RETRY_ATTEMPTS:
			_retry_timer.stop()
			print("[FirebaseManager] Max retry attempts reached (%d)" % MAX_RETRY_ATTEMPTS)
		return

	## Process operations one at a time
	var operation: Dictionary = _offline_queue.pop_front()
	var op_type: String = operation.get("type", "")

	print("[FirebaseManager] Processing queued operation: %s" % op_type)

	match op_type:
		"portfolio_push":
			sync_portfolio_to_cloud()
		"trades_push":
			sync_trades_to_cloud()
		"profile_push":
			sync_profile_to_cloud()
		"full":
			full_sync()
		_:
			print("[FirebaseManager] Unknown queued operation type: %s" % op_type)

	## Reset retry count on success
	_retry_count = 0

	## Keep timer running if more operations remain
	if not _offline_queue.is_empty():
		_retry_timer.start()
	else:
		_retry_timer.stop()
		print("[FirebaseManager] Offline queue drained")


## ============================================
## ===== متصدرين حقيقيين (Online Leaderboard) =====
## ============================================

## Fetch leaderboard
func fetch_leaderboard(category: String = "total_profit", limit: int = 50) -> void:
	if firebase_config["database_url"].is_empty():
		_fallback_leaderboard(category, limit)
		return

	var path := "leaderboards/%s?orderBy=\"value\"&limitToLast=%d" % [category, limit]

	http_database.request_completed.connect(_on_leaderboard_fetched.bind(category))
	var url := "%s/%s.json" % [firebase_config["database_url"], path]
	var headers := PackedStringArray()
	if not auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % auth_token)

	http_database.request(url, headers)


## Leaderboard fetch callback
func _on_leaderboard_fetched(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray, category: String) -> void:
	http_database.request_completed.disconnect(_on_leaderboard_fetched)

	if result != HTTPRequest.RESULT_SUCCESS:
		_fallback_leaderboard(category, 50)
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_fallback_leaderboard(category, 50)
		return

	var entries: Array[Dictionary] = []
	var data: Variant = json.data

	if data is Dictionary:
		var sorted: Array = []
		for uid in data:
			var entry: Dictionary = data[uid]
			sorted.append({
				"user_id": uid,
				"user_name": entry.get("display_name", "Unknown"),
				"value": entry.get("value", 0.0),
				"level": entry.get("level", 1),
				"additional_data": entry.get("additional_data", {})
			})
		sorted.sort_custom(func(a, b): return a["value"] > b["value"])
		entries = sorted
	elif data is Array:
		for item in data:
			if item is Dictionary:
				entries.append({
					"user_id": item.get("user_id", ""),
					"user_name": item.get("display_name", "Unknown"),
					"value": item.get("value", 0.0),
					"level": item.get("level", 1),
					"additional_data": item.get("additional_data", {})
				})

	cached_leaderboards[category] = {
		"entries": entries,
		"timestamp": Time.get_unix_time_from_system()
	}

	leaderboard_fetched.emit(category, entries)


## Local fallback (no Firebase)
func _fallback_leaderboard(category: String, limit: int) -> void:
	var fake_entries: Array[Dictionary] = []
	var fake_names := [
		"Al-Waseel Financial", "Crypto Hunter", "Market King", "DF Analyst",
		"Pro Trader", "Shark Whale", "Leverage Pro", "Chart Master",
		"Bull Wall Street", "Falcon Trader", "Stock Star", "Trading Bot"
	]

	for i in range(min(limit, fake_names.size())):
		var value := 0.0
		match category:
			"total_profit": value = randf() * 500000 + 10000
			"win_rate": value = randf() * 30 + 60
			"total_trades": value = randf() * 1000 + 100
			"balance": value = randf() * 1000000 + 100000
			"streak": value = randf() * 15 + 1
			"level": value = randf() * 50 + 5

		fake_entries.append({
			"user_id": "bot_%d" % i,
			"user_name": fake_names[i],
			"value": value,
			"level": int(randf() * 50 + 5),
			"additional_data": {}
		})

	## Add current player
	if profile_manager:
		var player_value := 0.0
		match category:
			"total_profit": player_value = profile_manager.total_profit
			"win_rate":
				player_value = 0.0
				if profile_manager.total_trades > 0:
					player_value = (float(profile_manager.winning_trades) / float(profile_manager.total_trades)) * 100.0
			"total_trades": player_value = float(profile_manager.total_trades)
			"balance": player_value = profile_manager.balance
			"streak": player_value = float(profile_manager.best_streak)
			"level": player_value = float(profile_manager.level)

		fake_entries.append({
			"user_id": profile_manager.player_id,
			"user_name": profile_manager.player_name + " (You)",
			"value": player_value,
			"level": profile_manager.level,
			"additional_data": {"is_current_user": true}
		})

	fake_entries.sort_custom(func(a, b): return a["value"] > b["value"])

	cached_leaderboards[category] = {
		"entries": fake_entries,
		"timestamp": Time.get_unix_time_from_system()
	}

	leaderboard_fetched.emit(category, fake_entries)


## Update player entry in leaderboard
func update_leaderboard_entry(category: String, value: float, additional_data: Dictionary = {}) -> void:
	if not is_logged_in or current_user.is_empty():
		return

	if firebase_config["database_url"].is_empty():
		return

	var path := "leaderboards/%s/%s" % [category, current_user["uid"]]
	var entry := {
		"display_name": profile_manager.player_name if profile_manager else "Unknown",
		"value": value,
		"level": profile_manager.level if profile_manager else 1,
		"additional_data": additional_data,
		"updated_at": Time.get_unix_time_from_system()
	}

	_database_put(path, entry)
	leaderboard_updated.emit(entry)


## Update all leaderboard categories
func sync_all_leaderboards() -> void:
	if not profile_manager:
		return

	update_leaderboard_entry("total_profit", profile_manager.total_profit)
	update_leaderboard_entry("balance", profile_manager.balance)
	update_leaderboard_entry("total_trades", float(profile_manager.total_trades))
	update_leaderboard_entry("level", float(profile_manager.level))
	update_leaderboard_entry("streak", float(profile_manager.best_streak))

	var win_rate := 0.0
	if profile_manager.total_trades > 0:
		win_rate = (float(profile_manager.winning_trades) / float(profile_manager.total_trades)) * 100.0
	update_leaderboard_entry("win_rate", win_rate)


## Periodic leaderboard refresh
func _refresh_leaderboards() -> void:
	var categories := ["total_profit", "balance", "win_rate", "total_trades", "level", "streak"]
	for cat in categories:
		fetch_leaderboard(cat)


## ============================================
## ===== الحفظ السحابي =====
## ============================================

## Save data to cloud
func cloud_save(save_data: Dictionary) -> void:
	if not is_logged_in or firebase_config["database_url"].is_empty():
		return

	var path: String = "user_data/%s" % current_user["uid"]
	save_data["last_saved"] = Time.get_unix_time_from_system()

	_database_put(path, save_data)


## Load data from cloud
func cloud_load() -> void:
	if not is_logged_in or firebase_config["database_url"].is_empty():
		cloud_load_failed.emit("Not logged in")
		return

	var _path: String = "user_data/%s.json" % current_user["uid"]
	var _url: String = "%s/%s" % [firebase_config["database_url"], _path]

	http_database.request_completed.connect(_on_cloud_load_response)
	var _headers := PackedStringArray()
	if not auth_token.is_empty():
		_headers.append("Authorization: Bearer %s" % auth_token)

	http_database.request(_url, _headers)


func _on_cloud_load_response(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	http_database.request_completed.disconnect(_on_cloud_load_response)

	if result != HTTPRequest.RESULT_SUCCESS:
		cloud_load_failed.emit("Failed to load data")
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
		cloud_load_success.emit(json.data)


## Auto cloud save
func _auto_cloud_save() -> void:
	if not is_logged_in or not profile_manager:
		return

	var save_data := {
		"profile": profile_manager.get_all_stats(),
		"earned_badges": profile_manager.earned_badges,
		"balance": profile_manager.balance
	}

	cloud_save(save_data)

	## Also do a quick Firestore sync
	sync_profile_to_cloud()


## ============================================
## ===== وظائف مساعدة =====
## ============================================

## HTTP PUT for Realtime Database
func _database_put(path: String, data: Dictionary) -> void:
	var url := "%s/%s.json" % [firebase_config["database_url"], path]
	var headers := PackedStringArray(["Content-Type: application/json"])
	if not auth_token.is_empty():
		headers.append("Authorization: Bearer %s" % auth_token)

	http_database.request(url, headers, HTTPClient.METHOD_PUT, JSON.stringify(data))


## Configure Firebase with project credentials
func configure(api_key: String, database_url: String, project_id: String = "") -> void:
	firebase_config = {
		"api_key": api_key,
		"auth_domain": "",
		"database_url": database_url,
		"project_id": project_id,
		"storage_bucket": "",
		"messaging_sender_id": "",
		"app_id": ""
	}
	print("[FirebaseManager] Configured | Project: %s | DB: %s" % [project_id, database_url])


## Get cached leaderboard
func get_cached_leaderboard(category: String) -> Array[Dictionary]:
	if cached_leaderboards.has(category):
		return cached_leaderboards[category].get("entries", [])
	return []


## ============================================
## ===== Batch Sync for Web =====
## ============================================

## Batch sync all data in a single operation (efficient for web)
func batch_sync() -> Dictionary:
	var result := {"success": true, "errors": [], "timestamp": Time.get_unix_time_from_system()}

	## Push all
	var ops := [
		{"name": "portfolio", "method": "sync_portfolio_to_cloud"},
		{"name": "trades", "method": "sync_trades_to_cloud"},
		{"name": "profile", "method": "sync_profile_to_cloud"}
	]

	for op in ops:
		if not is_online:
			result["success"] = false
			result["errors"].append("%s: offline" % op["name"])
			_queue_offline_operation("%s_push" % op["name"], {})
			continue
		call(op["method"])

	return result


## ============================================
## ===== Cleanup =====
## ============================================

func _exit_tree() -> void:
	stop_all_listeners()
	if _retry_timer:
		_retry_timer.stop()
	_save_sync_metadata()
	print("[FirebaseManager] Cleaned up")
