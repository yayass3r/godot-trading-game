## ============================================
## WebSyncAdapter.gd - Web-specific Firebase operations
## Handles Firestore REST API calls for the web platform,
## including token management, batch operations,
## and cross-origin isolation requirements.
## ============================================
extends Node

## ---- Reference to FirebaseManager ----
var firebase_manager: Node  ## Set by FirebaseManager on load

## ---- Signals ----
signal batch_sync_completed(results: Array[Dictionary])
signal batch_sync_failed(error: String)
signal token_refreshed(new_token: String)
signal token_refresh_failed(error: String)

## ---- Token management ----
var _id_token: String = ""
var _refresh_token: String = ""
var _token_expiry_time: int = 0
var _is_refreshing_token: bool = false

## ---- Firestore config ----
var _firestore_base_url: String = ""
var _project_id: String = ""

## ---- Batch write state ----
var _batch_operations: Array[Dictionary] = []
var _batch_max_size: int = 20  ## Firestore allows max 500 writes per batch; we use 20 for safety

## ---- HTTPRequest pool ----
var _http_pool: Array[HTTPRequest] = []
var _pool_size: int = 5
var _available_indices: Array[int] = []

## ---- Cross-origin / CORS ----
var _cors_headers: PackedStringArray = [
	"Content-Type: application/json",
	"Accept: application/json"
]

## ============================================
## _ready() - Initialize the web adapter
## ============================================
func _ready() -> void:
	## Initialize HTTP request pool for concurrent requests
	for i in range(_pool_size):
		var http := HTTPRequest.new()
		http.timeout = 20.0
		add_child(http)
		_http_pool.append(http)
		_available_indices.append(i)

	print("[WebSyncAdapter] Initialized with %d HTTP connections" % _pool_size)


## ============================================
## ===== Configuration =====
## ============================================

## Configure with Firebase project details
func configure(project_id: String, api_key: String = "") -> void:
	_project_id = project_id
	_firestore_base_url = "https://firestore.googleapis.com/v1/projects/%s/databases/(default)" % project_id
	print("[WebSyncAdapter] Configured for project: %s" % project_id)


## Sync config from FirebaseManager
func _sync_config_from_manager() -> void:
	if firebase_manager == null:
		return
	if not _project_id.is_empty():
		return  ## Already configured
	configure(firebase_manager.firebase_config.get("project_id", ""))
	_id_token = firebase_manager.auth_token
	_refresh_token = firebase_manager.refresh_token
	_token_expiry_time = firebase_manager.token_expiry


## ============================================
## ===== HTTP Pool Management =====
## ============================================

## Get an available HTTPRequest from the pool
func _acquire_http() -> HTTPRequest:
	if _available_indices.is_empty():
		## All busy — create a temporary one
		var http := HTTPRequest.new()
		http.timeout = 20.0
		add_child(http)
		return http

	var idx := _available_indices.pop_back() as int
	return _http_pool[idx]


## Release an HTTPRequest back to the pool
func _release_http(http: HTTPRequest) -> void:
	var idx := _http_pool.find(http)
	if idx >= 0 and idx not in _available_indices:
		_available_indices.append(idx)
	else:
		## Temporary one — clean up
		http.queue_free()


## ============================================
## ===== Token Management =====
## ============================================

## Get current valid token (refreshes if needed)
func get_valid_token() -> String:
	_sync_config_from_manager()

	if _id_token.is_empty() and firebase_manager:
		_id_token = firebase_manager.auth_token
		_refresh_token = firebase_manager.refresh_token
		_token_expiry_time = firebase_manager.token_expiry

	if not _id_token.is_empty():
		var now := Time.get_unix_time_from_system()
		if now < _token_expiry_time - 60:
			return _id_token

		## Token expired — try refresh
		refresh_token_async()

	return _id_token


## Refresh the auth token using the refresh token
func refresh_token_async() -> void:
	if _is_refreshing_token:
		return
	if _refresh_token.is_empty():
		print("[WebSyncAdapter] No refresh token available")
		return

	_is_refreshing_token = true
	var api_key := firebase_manager.firebase_config.get("api_key", "") if firebase_manager else ""
	if api_key.is_empty():
		_is_refreshing_token = false
		return

	var url := "https://securetoken.googleapis.com/v1/token?key=%s" % api_key
	var body := JSON.stringify({
		"grant_type": "refresh_token",
		"refresh_token": _refresh_token
	})

	var http := _acquire_http()
	http.request_completed.connect(_on_token_refreshed)
	var err := http.request(url, _cors_headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		http.request_completed.disconnect(_on_token_refreshed)
		_release_http(http)
		_is_refreshing_token = false
		token_refresh_failed.emit("HTTP request failed")


func _on_token_refreshed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	## Find and release the HTTP node
	var http: HTTPRequest = null
	for child in get_children():
		if child is HTTPRequest and child.is_connected("request_completed", _on_token_refreshed):
			http = child as HTTPRequest
			break

	_is_refreshing_token = false

	if http == null:
		return

	http.request_completed.disconnect(_on_token_refreshed)
	_release_http(http)

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		token_refresh_failed.emit("Token refresh failed (HTTP %d)" % code)
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		token_refresh_failed.emit("Failed to parse token response")
		return

	var data: Variant = json.data
	if data is Dictionary and data.has("id_token"):
		_id_token = data["id_token"]
		_refresh_token = data.get("refresh_token", _refresh_token)
		## expires_in is in seconds
		_token_expiry_time = Time.get_unix_time_from_system() + int(data.get("expires_in", "3600"))

		## Update FirebaseManager's token
		if firebase_manager:
			firebase_manager.auth_token = _id_token
			firebase_manager.refresh_token = _refresh_token
			firebase_manager.token_expiry = _token_expiry_time

		token_refreshed.emit(_id_token)
		print("[WebSyncAdapter] Token refreshed successfully")
	else:
		token_refresh_failed.emit("No id_token in response")


## ============================================
## ===== Firestore REST API Operations =====
## ============================================

## Write (create or overwrite) a Firestore document
func firestore_write(collection: String, doc_id: String, data: Dictionary) -> void:
	_sync_config_from_manager()

	var url := "%s/documents/%s/%s" % [_firestore_base_url, collection, doc_id]
	if url.begins_with("https://"):
		## Full URL already
		pass
	else:
		url = "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s/%s" % [_project_id, collection, doc_id]

	var token := get_valid_token()
	var headers := PackedStringArray(_cors_headers)
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)

	## Add cross-origin headers for web
	headers.append("X-Goog-Api-Client: gdcl/%s" % Engine.get_version_info().get("string", "1.0"))

	var body := JSON.stringify({
		"fields": _to_firestore_fields(data)
	})

	var http := _acquire_http()
	http.request(url, headers, HTTPClient.METHOD_POST, body)

	## Auto-release after a delay (we don't need the response for fire-and-forget)
	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(func():
		if is_instance_valid(http):
			_release_http(http)
	)


## Merge (partial update) a Firestore document
func firestore_merge(collection: String, doc_id: String, data: Dictionary) -> void:
	_sync_config_from_manager()

	var base := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s/%s" % [_project_id, collection, doc_id]
	var url := "%s?updateMask.fieldPaths=%s" % [base, "&updateMask.fieldPaths=".join(data.keys())]

	var token := get_valid_token()
	var headers := PackedStringArray(_cors_headers)
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)

	var body := JSON.stringify({
		"fields": _to_firestore_fields(data)
	})

	var http := _acquire_http()
	http.request(url, headers, HTTPClient.METHOD_PATCH, body)

	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(func():
		if is_instance_valid(http):
			_release_http(http)
	)


## Read a Firestore document (returns parsed Dictionary or null)
func firestore_read(collection: String, doc_id: String) -> Dictionary:
	_sync_config_from_manager()

	var url := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s/%s" % [_project_id, collection, doc_id]

	var token := get_valid_token()
	var headers := PackedStringArray(_cors_headers)
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)

	var http := _acquire_http()
	var completed := false
	var parsed_data: Dictionary = {}

	http.request_completed.connect(func(result, code, _hdrs, body):
		completed = true
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
				parsed_data = _parse_firestore_fields(json.data)
		_release_http(http)
	)

	http.request(url, headers, HTTPClient.METHOD_GET, "")

	## Wait for completion
	var wait_frames := 120  ## ~2 seconds max
	while not completed and wait_frames > 0:
		await get_tree().process_frame
		wait_frames -= 1

	return parsed_data


## Delete a Firestore document
func firestore_delete(collection: String, doc_id: String) -> bool:
	_sync_config_from_manager()

	var url := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents/%s/%s" % [_project_id, collection, doc_id]

	var token := get_valid_token()
	var headers := PackedStringArray(_cors_headers)
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)

	var http := _acquire_http()
	var success := false

	http.request_completed.connect(func(result, code, _hdrs, _body):
		success = (result == HTTPRequest.RESULT_SUCCESS and code == 200)
		_release_http(http)
	)

	http.request(url, headers, HTTPClient.METHOD_DELETE, "")

	var wait_frames := 120
	while http.is_connected("request_completed", func(result, code, hdrs, body): pass) and wait_frames > 0:
		await get_tree().process_frame
		wait_frames -= 1

	return success


## Query Firestore collection (simple filter)
func firestore_query(collection: String, field: String, operator_str: String, value: Variant) -> Array[Dictionary]:
	_sync_config_from_manager()

	## Build a structured query via REST
	## Note: Firestore REST API requires structured query JSON for filtering
	var filter_op := "EQUAL"  ## Default
	match operator_str:
		"<": filter_op = "LESS_THAN"
		"<=": filter_op = "LESS_THAN_OR_EQUAL"
		">": filter_op = "GREATER_THAN"
		">=": filter_op = "GREATER_THAN_OR_EQUAL"
		"==": filter_op = "EQUAL"
		"!=": filter_op = "NOT_EQUAL"

	var query_body := {
		"structuredQuery": {
			"from": [{"collectionId": collection}],
			"where": {
				"fieldFilter": {
					"field": {"fieldPath": field},
					"op": filter_op,
					"value": _gdscript_to_firestore_value(value)
				}
			}
		}
	}

	var url := "https://firestore.googleapis.com/v1/projects/%s/databases/(default)/documents:runQuery" % _project_id

	var token := get_valid_token()
	var headers := PackedStringArray(_cors_headers)
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)

	var http := _acquire_http()
	var results: Array[Dictionary] = []
	var completed := false

	http.request_completed.connect(func(result, code, _hdrs, body):
		completed = true
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var json := JSON.new()
			if json.parse(body.get_string_from_utf8()) == OK:
				var response = json.data
				if response is Array:
					for doc in response:
						if doc is Dictionary and doc.has("document"):
							results.append(_parse_firestore_fields(doc["document"]))
		_release_http(http)
	)

	http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(query_body))

	## Wait
	var wait_frames := 180  ## ~3 seconds max
	while not completed and wait_frames > 0:
		await get_tree().process_frame
		wait_frames -= 1

	return results


## ============================================
## ===== Batch Write Operations =====
## ============================================

## Add an operation to the batch queue
func add_to_batch(collection: String, doc_id: String, data: Dictionary, merge: bool = false) -> bool:
	if _batch_operations.size() >= _batch_max_size:
		print("[WebSyncAdapter] Batch full (%d/%d). Execute first." % [_batch_operations.size(), _batch_max_size])
		return false

	_batch_operations.append({
		"collection": collection,
		"doc_id": doc_id,
		"data": data,
		"merge": merge
	})

	return true


## Execute all batched operations
func execute_batch() -> void:
	if _batch_operations.is_empty():
		return

	var operations_copy := _batch_operations.duplicate(true)
	_batch_operations.clear()

	var total := operations_copy.size()
	var results: Array[Dictionary] = []
	var completed := 0

	for op in operations_copy:
		var op_result := {"collection": op["collection"], "doc_id": op["doc_id"], "success": false, "error": ""}

		try:
			if op["merge"]:
				firestore_merge(op["collection"], op["doc_id"], op["data"])
			else:
				firestore_write(op["collection"], op["doc_id"], op["data"])
			op_result["success"] = true
		except e:
			op_result["error"] = str(e)

		results.append(op_result)
		completed += 1

		## Small delay between operations to avoid rate limiting
		if completed < total:
			await get_tree().create_timer(0.1).timeout

	batch_sync_completed.emit(results)
	print("[WebSyncAdapter] Batch executed: %d/%d successful" % [
		results.filter(func(r): return r["success"]).size(), total
	])


## Batch sync all game data at once (efficient web operation)
func batch_sync_all_game_data() -> void:
	_sync_config_from_manager()

	if firebase_manager == null or not firebase_manager.is_logged_in:
		batch_sync_failed.emit("Not logged in")
		return

	var uid: String = firebase_manager.current_user.get("uid", "")
	if uid.is_empty():
		batch_sync_failed.emit("No user ID")
		return

	var now := Time.get_unix_time_from_system()
	var platform_info := firebase_manager._get_sync_platform_info()

	## Profile data
	if firebase_manager.profile_manager:
		var stats := firebase_manager.profile_manager.get_all_stats()
		stats["updated_at"] = now
		stats["sync_source"] = "web"
		stats.merge(platform_info, true)
		add_to_batch("profiles", uid, stats)

	## Portfolio data
	if firebase_manager.portfolio_manager:
		var summary := firebase_manager.portfolio_manager.get_portfolio_summary()
		summary["updated_at"] = now
		summary["sync_source"] = "web"
		summary.merge(platform_info, true)
		add_to_batch("portfolios", uid, summary)

	## Trades data
	if firebase_manager.portfolio_manager:
		var trades_data: Array[Dictionary] = firebase_manager.portfolio_manager._get_trades_data(
			firebase_manager.portfolio_manager.closed_trades
		)
		var payload := {
			"trades": trades_data,
			"trade_count": trades_data.size(),
			"updated_at": now,
			"sync_source": "web"
		}
		payload.merge(platform_info, true)
		add_to_batch("trades", uid, payload)

	## Execute all at once
	await execute_batch()


## ============================================
## ===== Cross-Origin / Web-Specific Handling =====
## ============================================

## Get enhanced headers for web platform (CORS-friendly)
func get_web_headers(extra_headers: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var headers := PackedStringArray(_cors_headers)
	var token := get_valid_token()
	if not token.is_empty():
		headers.append("Authorization: Bearer %s" % token)

	## Add CORS-friendly headers
	headers.append("Access-Control-Allow-Origin: *")
	headers.append("X-Requested-With: XMLHttpRequest")

	## Append any extra headers
	for h in extra_headers:
		headers.append(h)

	return headers


## Check if the web environment supports SharedArrayBuffer
## (required for some Firebase features in cross-origin isolated contexts)
func is_cross_origin_isolated() -> bool:
	if OS.get_name() != "Web":
		return false

	var result = JavaScriptBridge.eval("typeof crossOriginIsolated !== 'undefined' && crossOriginIsolated")
	return result == true


## Setup cross-origin isolation headers (via meta tags injected at build time)
## This is informational — actual COOP/COEP headers must be set by the web server
func get_cross_origin_isolation_headers() -> Dictionary:
	return {
		"Cross-Origin-Opener-Policy": "same-origin",
		"Cross-Origin-Embedder-Policy": "require-corp",
		"Cross-Origin-Resource-Policy": "cross-origin"
	}


## ============================================
## ===== Firestore Field Conversion =====
## ============================================

## Convert GDScript Dictionary to Firestore fields format
func _to_firestore_fields(data: Dictionary) -> Dictionary:
	var fields := {}

	for key in data:
		var value = data[key]
		fields[key] = _gdscript_to_firestore_value(value)

	return fields


## Convert a single GDScript value to Firestore value wrapper
func _gdscript_to_firestore_value(value: Variant) -> Dictionary:
	if value is String:
		return {"stringValue": value}
	elif value is int:
		return {"integerValue": str(value)}
	elif value is float:
		return {"doubleValue": str(value)}
	elif value is bool:
		return {"booleanValue": str(value).to_lower()}
	elif value == null:
		return {"nullValue": null}
	elif value is Array:
		var values := []
		for item in value:
			values.append(_gdscript_to_firestore_value(item))
		return {"arrayValue": {"values": values}}
	elif value is Dictionary:
		return {"mapValue": {"fields": _to_firestore_fields(value)}}
	else:
		## Fallback to string
		return {"stringValue": str(value)}


## Parse Firestore document fields from REST response
func _parse_firestore_fields(doc: Dictionary) -> Dictionary:
	var fields = doc.get("fields", {})
	var result := {}

	for key in fields:
		var field_value = fields[key]
		if field_value is Dictionary:
			result[key] = _firestore_value_to_gdscript(field_value)

	return result


## Convert a single Firestore value wrapper back to GDScript
func _firestore_value_to_gdscript(field_value: Dictionary) -> Variant:
	if field_value.has("stringValue"):
		return field_value["stringValue"]
	elif field_value.has("integerValue"):
		return int(field_value["integerValue"])
	elif field_value.has("doubleValue"):
		return float(field_value["doubleValue"])
	elif field_value.has("booleanValue"):
		return field_value["booleanValue"] == "true"
	elif field_value.has("nullValue"):
		return null
	elif field_value.has("arrayValue"):
		var arr = field_value["arrayValue"].get("values", [])
		var parsed_arr := []
		for item in arr:
			if item is Dictionary:
				parsed_arr.append(_firestore_value_to_gdscript(item))
		return parsed_arr
	elif field_value.has("mapValue"):
		return _parse_firestore_fields({"fields": field_value["mapValue"].get("fields", {})})
	elif field_value.has("timestampValue"):
		return field_value["timestampValue"]
	elif field_value.has("referenceValue"):
		return field_value["referenceValue"]
	return null


## ============================================
## ===== Utility =====
## ============================================

## Check if web adapter is ready for operations
func is_ready() -> bool:
	return not _project_id.is_empty()


## Get current batch size
func get_batch_size() -> int:
	return _batch_operations.size()


## Clear batch without executing
func clear_batch() -> void:
	_batch_operations.clear()


## Get adapter status summary
func get_status() -> Dictionary:
	return {
		"configured": is_ready(),
		"project_id": _project_id,
		"token_valid": not _id_token.is_empty() and Time.get_unix_time_from_system() < _token_expiry_time - 60,
		"batch_size": _batch_operations.size(),
		"http_pool_available": _available_indices.size(),
		"cross_origin_isolated": is_cross_origin_isolated()
	}


func _exit_tree() -> void:
	_batch_operations.clear()
	print("[WebSyncAdapter] Cleaned up")
