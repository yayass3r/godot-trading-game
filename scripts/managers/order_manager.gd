## ============================================
## OrderManager.gd - محرك أوامر الحد المعلقة
## يدير أوامر الحد والوقف ويتحقق من تنفيذها عند وصول السعر
## يربط مع TradingManager و DataManager و PortfolioManager
## ============================================
extends Node

const LimitOrderClass = preload("res://scripts/data_models/limit_order.gd")
const TradeClass = preload("res://scripts/data_models/trade.gd")

## ---- إشارات ----
signal order_created(order)
signal order_filled(order, trade)
signal order_cancelled(order)
signal order_expired(order)
signal orders_updated()

## ---- مراجع ----
var trading_manager: Node
var portfolio_manager: Node
var data_manager: Node
var profile_manager: Node

## ---- أوامر الحد المعلقة ----
var pending_orders: Array = []
var filled_orders: Array = []
var cancelled_orders: Array = []

## ---- ثوابت ----
const MAX_PENDING_ORDERS: int = 50
const CHECK_INTERVAL: float = 0.5  ## فحص كل 0.5 ثانية

## ---- مؤقت الفحص ----
var _check_timer: Timer

## ============================================
## _ready() - التهيئة
## ============================================
func _ready() -> void:
	trading_manager = get_node_or_null("/root/TradingManager")
	portfolio_manager = get_node_or_null("/root/PortfolioManager")
	data_manager = get_node_or_null("/root/DataManager")
	profile_manager = get_node_or_null("/root/ProfileManager")

	## ربط إشارة تحديث الأسعار
	if data_manager:
		data_manager.price_updated.connect(_on_price_updated)

	## مؤقت لفحص الأوامر المنتهية الصلاحية
	_check_timer = Timer.new()
	_check_timer.wait_time = CHECK_INTERVAL
	_check_timer.autostart = true
	_check_timer.timeout.connect(_check_expired_orders)
	add_child(_check_timer)

	print("[OrderManager] ✅ محرك أوامر الحد جاهز")

## ============================================
## إنشاء أمر حد جديد
## ============================================
func create_limit_order(
	symbol: String,
	side: int,  ## LimitOrder.OrderSide.BUY or SELL
	price: float,
	position_size: float,
	leverage: int = 1,
	take_profit: float = -1.0,
	stop_loss: float = -1.0,
	expire_seconds: int = 0  ## 0 = بدون انتهاء
) -> Dictionary:
	## التحقق من الحد الأقصى
	if pending_orders.size() >= MAX_PENDING_ORDERS:
		return {"success": false, "error": "تم بلوغ الحد الأقصى لأوامر الحد (%d)" % MAX_PENDING_ORDERS}

	## التحقق من صحة البيانات
	if price <= 0:
		return {"success": false, "error": "سعر غير صالح"}
	if position_size <= 0:
		return {"success": false, "error": "حجم غير صالح"}

	## حساب المبالغ
	var current_price: float = 0.0
	if data_manager:
		current_price = data_manager.get_price(symbol)
	if current_price <= 0:
		current_price = price

	var notional_value := position_size * current_price
	var margin := notional_value / leverage
	var fee := notional_value * GameConstants.TRADING_FEE_RATE

	## التحقق من الهامش
	if profile_manager:
		var available := profile_manager.balance - portfolio_manager.total_margin_used if portfolio_manager else profile_manager.balance
		if margin + fee > available:
			return {"success": false, "error": "هامش غير كافٍ. مطلوب: $%.2f | متاح: $%.2f" % [margin + fee, available]}

	## إنشاء الأمر
	var order := LimitOrderClass.new()
	order.order_id = _generate_order_id()
	order.symbol = symbol
	order.order_type = LimitOrderClass.OrderType.LIMIT
	order.order_side = side
	order.status = LimitOrderClass.OrderStatus.PENDING
	order.trigger_price = price
	order.position_size = position_size
	order.leverage = leverage
	order.take_profit = take_profit
	order.stop_loss = stop_loss
	order.created_time = Time.get_unix_time_from_system()
	order.margin_required = margin
	order.fee = fee

	if expire_seconds > 0:
		order.expire_time = order.created_time + expire_seconds

	pending_orders.append(order)
	order_created.emit(order)
	orders_updated.emit()

	print("[OrderManager] 📋 أمر حد جديد: %s %s @ $%.2f | حجم: %.4f" % [
		"BUY" if side == LimitOrderClass.OrderSide.BUY else "SELL",
		symbol, price, position_size
	])

	return {"success": true, "order": order}

## ============================================
## إنشاء أمر وقف سوق (Stop Market)
## ============================================
func create_stop_market_order(
	symbol: String,
	side: int,
	stop_price: float,
	position_size: float,
	leverage: int = 1
) -> Dictionary:
	var result := create_limit_order(symbol, side, stop_price, position_size, leverage)
	if result["success"]:
		var order: LimitOrderClass = result["order"]
		order.order_type = LimitOrderClass.OrderType.STOP_MARKET
	return result

## ============================================
## إلغاء أمر معلق
## ============================================
func cancel_order(order_id: String) -> bool:
	for i in range(pending_orders.size()):
		if pending_orders[i].order_id == order_id:
			var order = pending_orders[i]
			order.status = LimitOrderClass.OrderStatus.CANCELLED
			pending_orders.remove_at(i)
			cancelled_orders.append(order)

			## إرجاع الهامش المحجوز (إذا كان محجوزاً)
			if profile_manager:
				profile_manager.balance += order.margin_required

			order_cancelled.emit(order)
			orders_updated.emit()
			print("[OrderManager] ❌ أمر مُلغى: %s" % order_id)
			return true
	return false

## ============================================
## إلغاء كل أوامر حد لأداة معينة
## ============================================
func cancel_all_symbol_orders(symbol: String) -> int:
	var count := 0
	var to_cancel: Array = []
	for order in pending_orders:
		if order.symbol == symbol:
			to_cancel.append(order)
	for order in to_cancel:
		if cancel_order(order.order_id):
			count += 1
	return count

## ============================================
## إلغاء كل الأوامر المعلقة
## ============================================
func cancel_all_orders() -> int:
	var to_cancel: Array = []
	to_cancel.assign(pending_orders)
	var count := 0
	for order in to_cancel:
		if cancel_order(order.order_id):
			count += 1
	return count

## ============================================
## استقبال تحديثات الأسعار - فحص الأوامر
## ============================================
func _on_price_updated(symbol: String, price: float, _timestamp: int) -> void:
	if pending_orders.is_empty():
		return

	var orders_to_fill: Array = []

	for order in pending_orders:
		if order.symbol != symbol:
			continue
		if order.should_trigger(price):
			orders_to_fill.append(order)

	for order in orders_to_fill:
		_execute_order(order, price)

## ============================================
## تنفيذ أمر عند وصول السعر
## ============================================
func _execute_order(order, execution_price: float) -> void:
	## إزالة من المعلقة
	var idx := pending_orders.find(order)
	if idx >= 0:
		pending_orders.remove_at(idx)

	## تحديث حالة الأمر
	order.status = LimitOrderClass.OrderStatus.FILLED
	order.filled_price = execution_price
	order.filled_time = Time.get_unix_time_from_system()
	order.filled_size = order.position_size

	## تنفيذ الصفقة عبر TradingManager
	var trade_type := TradeClass.TradeType.LONG if order.order_side == LimitOrderClass.OrderSide.BUY else TradeClass.TradeType.SHORT

	var trade = null
	if trading_manager:
		trade = trading_manager.open_trade(
			order.symbol,
			trade_type,
			order.position_size,
			order.leverage,
			order.take_profit,
			order.stop_loss
		)

	filled_orders.append(order)
	order_filled.emit(order, trade)
	orders_updated.emit()

	var side_str := "BUY" if order.order_side == LimitOrderClass.OrderSide.BUY else "SELL"
	print("[OrderManager] ✅ أمر مُنفذ: %s %s @ $%.2f" % [
		side_str, order.symbol, execution_price
	])

## ============================================
## فحص الأوامر المنتهية الصلاحية
## ============================================
func _check_expired_orders() -> void:
	if pending_orders.is_empty():
		return

	var to_expire: Array = []
	for order in pending_orders:
		if order.is_expired():
			to_expire.append(order)

	for order in to_expire:
		var idx := pending_orders.find(order)
		if idx >= 0:
			pending_orders.remove_at(idx)
			order.status = LimitOrderClass.OrderStatus.EXPIRED
			cancelled_orders.append(order)

			## إرجاع الهامش
			if profile_manager:
				profile_manager.balance += order.margin_required

			order_expired.emit(order)
			orders_updated.emit()
			print("[OrderManager] ⏰ أمر منتهي: %s" % order.order_id)

## ============================================
## الحصول على أوامر معلقة لأداة معينة
## ============================================
func get_pending_orders_for_symbol(symbol: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for order in pending_orders:
		if order.symbol == symbol:
			result.append(order.to_dictionary())
	return result

## ============================================
## الحصول على كل الأوامر المعلقة
## ============================================
func get_all_pending_orders() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for order in pending_orders:
		result.append(order.to_dictionary())
	return result

## ============================================
## عدد الأوامر المعلقة
## ============================================
func get_pending_count() -> int:
	return pending_orders.size()

## ============================================
## معرّف فريد
## ============================================
func _generate_order_id() -> String:
	return "LO_%s_%d" % [
		Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace(" ", ""),
		randi() % 100000
	]

## ============================================
## حفظ الأوامر
## ============================================
func save_orders() -> void:
	var data := {
		"pending": [],
		"filled": [],
		"cancelled": []
	}
	for order in pending_orders:
		data["pending"].append(order.to_dictionary())
	for order in filled_orders:
		data["filled"].append(order.to_dictionary())
	for order in cancelled_orders:
		data["cancelled"].append(order.to_dictionary())

	var save_path := "user://orders_data.json"
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		print("[OrderManager] 💾 تم حفظ الأوامر")
