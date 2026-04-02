## ============================================
## WebSocketManager.gd - اتصال أسعار لحظي عبر WebSocket
## أسرع 100x من REST API — أسعار فورية
## ============================================
extends Node
class_name WebSocketManager

## ---- إشارات ----
signal connected()
signal disconnected()
signal message_received(symbol: String, price: float, timestamp: int)
signal connection_error(error: String)

## ---- إعدادات Binance WebSocket ----
const BINANCE_WS_URL: String = "wss://stream.binance.com:9443/ws"
const BINANCE_COMBINED_URL: String = "wss://stream.binance.com:9443/stream?streams="

## ---- حالة الاتصال ----
var _socket: WebSocketPeer = WebSocketPeer.new()
var _is_connected: bool = false
var _subscribed_symbols: Array[String] = []
var _reconnect_timer: Timer
var _ping_timer: Timer
var _retry_count: int = 0
const MAX_RETRIES: int = 5
const RECONNECT_DELAY: float = 3.0

## ============================================
## التهيئة
## ============================================
func _ready() -> void:
	## مؤقت إعادة الاتصال
	_reconnect_timer = Timer.new()
	_reconnect_timer.wait_time = RECONNECT_DELAY
	_reconnect_timer.autostart = false
	_reconnect_timer.one_shot = true
	_reconnect_timer.timeout.connect(_attempt_reconnect)
	add_child(_reconnect_timer)
	
	## مؤقت Ping (للحفاظ على الاتصال حياً)
	_ping_timer = Timer.new()
	_ping_timer.wait_time = 30.0
	_ping_timer.autostart = false
	_ping_timer.timeout.connect(_send_ping)
	add_child(_ping_timer)

## ============================================
## الاتصال والاشتراك في رموز
## ============================================
func connect_and_subscribe(symbols: Array[String]) -> void:
	_subscribed_symbols = symbols
	
	## بناء رابط الاشتراك المتعدد
	var streams: Array[String] = []
	for symbol in symbols:
		streams.append("%s@ticker" % symbol.to_lower())
	
	var stream_str := "/".join(streams)
	var url := BINANCE_COMBINED_URL + stream_str
	
	print("[WebSocket] 🔗 جاري الاتصال بـ Binance WebSocket...")
	var err := _socket.connect_to_url(url)
	if err != OK:
		connection_error.emit("فشل الاتصال: %d" % err)
		_schedule_reconnect()

## ============================================
## إعادة الاتصال
## ============================================
func _attempt_reconnect() -> void:
	if _retry_count >= MAX_RETRIES:
		connection_error.emit("تم بلوغ الحد الأقصى لإعادة الاتصال")
		return
	
	_retry_count += 1
	print("[WebSocket] 🔄 إعادة الاتصال (محاولة %d/%d)..." % [_retry_count, MAX_RETRIES])
	
	if not _subscribed_symbols.is_empty():
		connect_and_subscribe(_subscribed_symbols)

func _schedule_reconnect() -> void:
	_reconnect_timer.start(RECONNECT_DELAY * _retry_count)

## ============================================
## _process - معالجة أحداث WebSocket
## ============================================
func _process(delta: float) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.poll()
		
		## قراءة الرسائل المتاحة
		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			_parse_message(packet.get_string_from_utf8())
	
	elif _socket.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		_socket.poll()
	
	elif _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if _is_connected:
			_is_connected = false
			disconnected.emit()
			print("[WebSocket] ❌ تم قطع الاتصال")
			_schedule_reconnect()

## ============================================
## تحليل رسالة WebSocket
## ============================================
func _parse_message(raw_data: String) -> void:
	var json := JSON.new()
	if json.parse(raw_data) != OK:
		return
	
	var data = json.data
	if not data is Dictionary:
		return
	
	## رسائل Binance Combined Stream تأتي مغلفة
	if data.has("stream") and data.has("data"):
		data = data["data"]
	
	##Ticker data
	if data.has("c"):  ## 'c' = latest price in Binance ticker
		var symbol: String = data.get("s", "")
		var price: float = float(data.get("c", "0"))
		var timestamp: int = int(data.get("E", "0"))
		
		if not symbol.is_empty() and price > 0.0:
			message_received.emit(symbol, price, timestamp)

## ============================================
## إرسال Ping
## ============================================
func _send_ping() -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text("{\"method\":\"ping\"}")

## ============================================
## قطع الاتصال
## ============================================
func disconnect() -> void:
	_ping_timer.stop()
	_reconnect_timer.stop()
	_is_connected = false
	_socket.close()
	disconnected.emit()
	print("[WebSocket] 🔌 تم قطع الاتصال")

## ============================================
## الحالة الحالية
## ============================================
func is_connected() -> bool:
	return _is_connected
