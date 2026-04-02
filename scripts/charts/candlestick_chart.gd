## ============================================
## CandlestickChart.gd - رسم الشموع اليابانية الاحترافي
## يستخدم _draw() لرسم شموع حقيقية بأجسام وخيوط ملونة
## يشمل: محاور، شبكة، كروسهاير، مؤشرات فنية متداخلة
## ============================================
extends Control

## ---- ألوان الثيم الداكن (Binance-style) ----
var COLOR_BG: Color = Color(0.06, 0.06, 0.12, 1.0)
var COLOR_GRID: Color = Color(0.15, 0.15, 0.22, 0.5)
var COLOR_AXIS_TEXT: Color = Color(0.55, 0.55, 0.65, 1.0)
var COLOR_CROSSHAIR: Color = Color(0.6, 0.6, 0.7, 0.6)
var COLOR_BULLISH: Color = Color(0.14, 0.83, 0.44, 1.0)   ## أخضر #0ED42B
var COLOR_BEARISH: Color = Color(0.90, 0.31, 0.27, 1.0)    ## أحمر #E54F45
var COLOR_BULLISH_WICK: Color = Color(0.14, 0.83, 0.44, 1.0)
var COLOR_BEARISH_WICK: Color = Color(0.90, 0.31, 0.27, 1.0)
var COLOR_VOLUME_BULL: Color = Color(0.14, 0.83, 0.44, 0.25)
var COLOR_VOLUME_BEAR: Color = Color(0.90, 0.31, 0.27, 0.25)
var COLOR_SMA_9: Color = Color(1.0, 0.84, 0.0, 1.0)        ## أصفر
var COLOR_SMA_21: Color = Color(0.0, 0.71, 0.85, 1.0)       ## سماوي
var COLOR_SMA_50: Color = Color(0.91, 0.29, 0.51, 1.0)      ## وردي
var COLOR_EMA_12: Color = Color(1.0, 0.55, 0.0, 1.0)        ## برتقالي
var COLOR_EMA_26: Color = Color(0.59, 0.36, 0.94, 1.0)      ## بنفسجي
var COLOR_BB_FILL: Color = Color(0.36, 0.55, 0.95, 0.08)    ## أزرق شفاف
var COLOR_BB_LINE: Color = Color(0.36, 0.55, 0.95, 0.5)     ## أزرق خط

## ---- هامش الرسم ----
var PADDING_RIGHT: float = 70.0    ## مسافة لمحور Y
var PADDING_LEFT: float = 5.0
var PADDING_TOP: float = 10.0
var PADDING_BOTTOM: float = 25.0   ## مسافة لمحور X
var VOLUME_HEIGHT_RATIO: float = 0.15  ## نسبة ارتفاع الحجم من إجمالي الرسم

## ---- مراجع ----
var chart_manager: Node

## ---- حالة الرسم ----
var _candles: Array[Dictionary] = []
var _price_range: Dictionary = {}
var _mouse_pos: Vector2 = Vector2(-1, -1)
var _hovered_candle_idx: int = -1
var _visible_start: int = 0
var _visible_count: int = 60

## ---- مؤشرات نشطة ----
var show_sma_9: bool = false
var show_sma_21: bool = false
var show_sma_50: bool = false
var show_ema_12: bool = false
var show_ema_26: bool = false
var show_bollinger: bool = false

## ---- تحويلات سلسة ----
var _display_candles: Array[Dictionary] = []  ## الشموع المعروضة حالياً (للتحويل السلس)
var _target_candles: Array[Dictionary] = []   ## الشموع المستهدفة
var _transition_progress: float = 1.0

## ---- إشارات ----
signal candle_hovered(candle: Dictionary, index: int)
signal candle_clicked(candle: Dictionary, index: int)

## ============================================
## _ready() - التهيئة
## ============================================
func _ready() -> void:
	chart_manager = get_node_or_null("/root/ChartManager")
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

## ============================================
## تحديث بيانات الشموع
## ============================================
func update_candles(candles: Array[Dictionary]) -> void:
	_target_candles = candles
	_transition_progress = 0.0
	if _display_candles.size() != candles.size():
		_display_candles = candles.duplicate(true)
		_candles = candles
	queue_redraw()

## ============================================
## _process() - تحديث التحويلات السلسة
## ============================================
func _process(_delta: float) -> void:
	if _transition_progress < 1.0:
		_transition_progress = minf(_transition_progress + _delta * 4.0, 1.0)
		queue_redraw()

## ============================================
## _draw() - الرسم الرئيسي
## ============================================
func _draw() -> void:
	var rect := get_rect()
	if rect.size.x < 50 or rect.size.y < 50:
		return

	if _candles.is_empty():
		_draw_empty_state(rect)
		return

	var chart_rect := Rect2(
		PADDING_LEFT, PADDING_TOP,
		rect.size.x - PADDING_RIGHT - PADDING_LEFT,
		rect.size.y - PADDING_BOTTOM - PADDING_TOP
	)

	if chart_rect.size.x < 10 or chart_rect.size.y < 10:
		return

	## حساب نطاق الأسعار
	_price_range = _get_price_range()
	if _price_range["range"] <= 0:
		return

	## رسم الخلفية
	_draw_background(rect)

	## رسم الشبكة والمحاور
	_draw_grid(chart_rect)
	_draw_price_axis(chart_rect)
	_draw_time_axis(chart_rect)

	## حساب مناطق الرسم
	var volume_area_height := chart_rect.size.y * VOLUME_HEIGHT_RATIO
	var candle_area := Rect2(
		chart_rect.position.x,
		chart_rect.position.y,
		chart_rect.size.x,
		chart_rect.size.y - volume_area_height
	)
	var volume_area := Rect2(
		chart_rect.position.x,
		chart_rect.position.y + candle_area.size.y,
		chart_rect.size.x,
		volume_area_height
	)

	## رسم أوامر الحد على الشارت (خطوط أفقية)
	_draw_limit_orders_on_chart(candle_area)

	## رسم خطوط TP/SL للصفقات المفتوحة
	_draw_tp_sl_lines(candle_area)

	## رسم بولينجر باند (خلفية)
	if show_bollinger:
		_draw_bollinger_bands(candle_area)

	## رسم أعمدة الحجم
	_draw_volume_bars(volume_area)

	## رسم الشموع
	_draw_candles(candle_area)

	## رسم خطوط المتوسطات المتحركة (فوق الشموع)
	_draw_moving_averages(candle_area)

	## رسم الكروسهاير
	_draw_crosshair(chart_rect)

## ============================================
## رسم خلفية
## ============================================
func _draw_background(rect: Rect2) -> void:
	draw_rect(rect, COLOR_BG)

## ============================================
## رسم حالة فارغة
## ============================================
func _draw_empty_state(rect: Rect2) -> void:
	draw_rect(rect, COLOR_BG)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(rect.size.x / 2.0 - 80, rect.size.y / 2.0),
		"Loading chart...",
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		16,
		COLOR_AXIS_TEXT
	)

## ============================================
## رسم الشبكة
## ============================================
func _draw_grid(chart_rect: Rect2) -> void:
	var high := _price_range["high"]
	var low := _price_range["low"]
	var range_val := _price_range["range"]

	## خطوط أفقية (أسعار) - 5 خطوط
	var num_h_lines := 5
	var step := range_val / num_h_lines
	var price_step := _nice_number(step)

	var price := ceili(low / price_step) * price_step
	while price <= high:
		var y := _price_to_y(price, chart_rect)
		draw_line(
			Vector2(chart_rect.position.x, y),
			Vector2(chart_rect.position.x + chart_rect.size.x, y),
			COLOR_GRID, 0.5, true
		)
		price += price_step

	## خطوط عمودية (زمن) - كل 10 شموع
	var num_candles := _candles.size()
	var candle_step := max(1, num_candles / 8)
	for i in range(0, num_candles, candle_step):
		var x := _candle_index_to_x(i, chart_rect)
		draw_line(
			Vector2(x, chart_rect.position.y),
			Vector2(x, chart_rect.position.y + chart_rect.size.y),
			COLOR_GRID, 0.5, true
		)

## ============================================
## رسم محور Y (الأسعار)
## ============================================
func _draw_price_axis(chart_rect: Rect2) -> void:
	var high := _price_range["high"]
	var low := _price_range["low"]
	var range_val := _price_range["range"]

	var step := range_val / 5.0
	var price_step := _nice_number(step)

	var price := ceili(low / price_step) * price_step
	while price <= high:
		var y := _price_to_y(price, chart_rect)
		var label := _format_price(price)
		var text_width := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 12).x
		draw_string(
			ThemeDB.fallback_font,
			Vector2(chart_rect.position.x + chart_rect.size.x + 5, y + 4),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			PADDING_RIGHT - 5,
			12,
			COLOR_AXIS_TEXT
		)
		price += price_step

## ============================================
## رسم محور X (الزمن)
## ============================================
func _draw_time_axis(chart_rect: Rect2) -> void:
	var num_candles := _candles.size()
	if num_candles == 0:
		return

	var interval_name := ""
	if chart_manager:
		interval_name = chart_manager.current_interval

	var candle_step := max(1, num_candles / 6)
	for i in range(0, num_candles, candle_step):
		if i >= _candles.size():
			break
		var candle := _candles[i]
		var x := _candle_index_to_x(i, chart_rect)
		var time_dict := Time.get_datetime_dict_from_unix_time(int(candle.get("open_time", 0)))
		var label := ""
		match interval_name:
			"1m", "5m", "15m":
				label = "%02d:%02d" % [time_dict.get("hour", 0), time_dict.get("minute", 0)]
			"1h", "4h":
				label = "%02d:%02d" % [time_dict.get("hour", 0), time_dict.get("minute", 0)]
			"1d":
				label = "%02d/%02d" % [time_dict.get("month", 0), time_dict.get("day", 0)]
			"1w":
				label = "%02d/%02d" % [time_dict.get("month", 0), time_dict.get("day", 0)]
			_:
				label = "%02d:%02d" % [time_dict.get("hour", 0), time_dict.get("minute", 0)]

		draw_string(
			ThemeDB.fallback_font,
			Vector2(x - 20, chart_rect.position.y + chart_rect.size.y + PADDING_BOTTOM - 5),
			label,
			HORIZONTAL_ALIGNMENT_CENTER,
			40,
			10,
			COLOR_AXIS_TEXT
		)

## ============================================
## رسم الشموع اليابانية
## ============================================
func _draw_candles(chart_rect: Rect2) -> void:
	var num_candles := _candles.size()
	if num_candles == 0:
		return

	var candle_width := chart_rect.size.x / num_candles
	var body_width := candle_width * 0.65
	var half_body := body_width / 2.0

	for i in range(num_candles):
		var candle := _candles[i]
		var is_bullish: bool = candle["close"] >= candle["open"]

		var x := _candle_index_to_x(i, chart_rect)
		var wick_x := x

		var high_y := _price_to_y(candle["high"], chart_rect)
		var low_y := _price_to_y(candle["low"], chart_rect)
		var open_y := _price_to_y(candle["open"], chart_rect)
		var close_y := _price_to_y(candle["close"], chart_rect)

		## لون الشمعة
		var body_color := COLOR_BULLISH if is_bullish else COLOR_BEARISH
		var wick_color := COLOR_BULLISH_WICK if is_bullish else COLOR_BEARISH_WICK

		## رسم الخيط (Wick)
		draw_line(
			Vector2(wick_x, high_y),
			Vector2(wick_x, low_y),
			wick_color, max(1.0, candle_width * 0.08)
		)

		## رسم الجسم (Body)
		var body_top := minf(open_y, close_y)
		var body_bottom := maxf(open_y, close_y)
		var body_height := body_bottom - body_top

		if body_height < 1.0:
			body_height = 1.0
			body_top = close_y - 0.5

		var body_rect := Rect2(x - half_body, body_top, body_width, body_height)
		draw_rect(body_rect, body_color)

		## إذا كانت الشمعة صاعدة، نرسم حافة
		if is_bullish:
			draw_rect(body_rect, body_color)
		else:
			draw_rect(body_rect, body_color)

## ============================================
## رسم أعمدة الحجم
## ============================================
func _draw_volume_bars(volume_area: Rect2) -> void:
	var num_candles := _candles.size()
	if num_candles == 0:
		return

	## حساب أعلى حجم
	var max_volume := 0.0
	for candle in _candles:
		if candle["volume"] > max_volume:
			max_volume = candle["volume"]

	if max_volume <= 0:
		return

	var candle_width := volume_area.size.x / num_candles
	var bar_width := candle_width * 0.65

	for i in range(num_candles):
		var candle := _candles[i]
		var is_bullish: bool = candle["close"] >= candle["open"]
		var x := _candle_index_to_x(i, volume_area)
		var bar_height := (candle["volume"] / max_volume) * volume_area.size.y
		bar_height = maxf(bar_height, 1.0)

		var bar_color := COLOR_VOLUME_BULL if is_bullish else COLOR_VOLUME_BEAR
		var bar_rect := Rect2(
			x - bar_width / 2.0,
			volume_area.position.y + volume_area.size.y - bar_height,
			bar_width,
			bar_height
		)
		draw_rect(bar_rect, bar_color)

## ============================================
## رسم المتوسطات المتحركة (SMA / EMA)
## ============================================
func _draw_moving_averages(chart_rect: Rect2) -> void:
	if not chart_manager:
		return

	var num_candles := _candles.size()
	if num_candles == 0:
		return

	## رسم SMA
	_draw_ma_line("SMA_9", chart_rect, COLOR_SMA_9, show_sma_9)
	_draw_ma_line("SMA_21", chart_rect, COLOR_SMA_21, show_sma_21)
	_draw_ma_line("SMA_50", chart_rect, COLOR_SMA_50, show_sma_50)
	_draw_ma_line("EMA_12", chart_rect, COLOR_EMA_12, show_ema_12)
	_draw_ma_line("EMA_26", chart_rect, COLOR_EMA_26, show_ema_26)

## ============================================
## رسم خط متوسط متحرك واحد
## ============================================
func _draw_ma_line(key: String, chart_rect: Rect2, color: Color, visible: bool) -> void:
	if not visible:
		return

	var data: Array = chart_manager.active_indicators.get(key, [])
	if data.size() != _candles.size():
		return

	var points := PackedVector2Array()
	for i in range(_candles.size()):
		var val: float = data[i]
		if val <= 0:
			continue
		var x := _candle_index_to_x(i, chart_rect)
		var y := _price_to_y(val, chart_rect)
		points.append(Vector2(x, y))

	if points.size() >= 2:
		draw_polyline(points, color, 1.5, false)

## ============================================
## رسم بولينجر باند
## ============================================
func _draw_bollinger_bands(chart_rect: Rect2) -> void:
	if not chart_manager:
		return

	var bb: Dictionary = chart_manager.bollinger_data
	if bb.is_empty():
		return

	var upper: Array = bb.get("upper", [])
	var lower: Array = bb.get("lower", [])
	if upper.size() != _candles.size() or lower.size() != _candles.size():
		return

	## رسم المنطقة المملوءة
	var points := PackedVector2Array()
	var num := _candles.size()

	## النقاط العلوية (من اليسار لليمين)
	for i in range(num):
		var val: float = upper[i]
		if val <= 0:
			continue
		points.append(Vector2(_candle_index_to_x(i, chart_rect), _price_to_y(val, chart_rect)))

	## النقاط السفلية (من اليمين لليسار) لإغلاق الشكل
	for i in range(num - 1, -1, -1):
		var val: float = lower[i]
		if val <= 0:
			continue
		points.append(Vector2(_candle_index_to_x(i, chart_rect), _price_to_y(val, chart_rect)))

	if points.size() >= 3:
		draw_colored_polygon(points, COLOR_BB_FILL)

	## رسم خطوط BB العلوية والسفلية
	var upper_points := PackedVector2Array()
	var lower_points := PackedVector2Array()
	for i in range(num):
		if upper[i] > 0:
			upper_points.append(Vector2(_candle_index_to_x(i, chart_rect), _price_to_y(upper[i], chart_rect)))
		if lower[i] > 0:
			lower_points.append(Vector2(_candle_index_to_x(i, chart_rect), _price_to_y(lower[i], chart_rect)))

	if upper_points.size() >= 2:
		draw_polyline(upper_points, COLOR_BB_LINE, 1.0, false)
	if lower_points.size() >= 2:
		draw_polyline(lower_points, COLOR_BB_LINE, 1.0, false)

## ============================================
## رسم خطوط أوامر الحد المعلقة
## ============================================
func _draw_limit_orders_on_chart(chart_rect: Rect2) -> void:
	var order_manager: Node = get_node_or_null("/root/OrderManager")
	if not order_manager:
		return

	var pending := order_manager.get_pending_orders_for_symbol(_get_current_symbol())
	for order in pending:
		var price: float = order.get("price", 0.0)
		if price <= 0:
			continue
		var y := _price_to_y(price, chart_rect)
		var is_buy: bool = order.get("side", "") == "BUY"
		var line_color := Color(COLOR_BULLISH.r, COLOR_BULLISH.g, COLOR_BULLISH.b, 0.6) if is_buy else Color(COLOR_BEARISH.r, COLOR_BEARISH.g, COLOR_BEARISH.b, 0.6)
		draw_dashed_line(
			Vector2(chart_rect.position.x, y),
			Vector2(chart_rect.position.x + chart_rect.size.x, y),
			line_color, 1.0, 6.0
		)
		## نص السعر
		var label := _format_price(price)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(chart_rect.position.x + chart_rect.size.x + 5, y + 4),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			PADDING_RIGHT - 5,
			11,
			line_color
		)

## ============================================
## رسم خطوط TP/SL للصفقات المفتوحة
## ============================================
func _draw_tp_sl_lines(chart_rect: Rect2) -> void:
	var portfolio_manager: Node = get_node_or_null("/root/PortfolioManager")
	if not portfolio_manager:
		return

	for trade in portfolio_manager.open_trades:
		if trade.symbol != _get_current_symbol():
			continue

		## خط جني الأرباح
		if trade.take_profit > 0:
			var y := _price_to_y(trade.take_profit, chart_rect)
			draw_dashed_line(
				Vector2(chart_rect.position.x, y),
				Vector2(chart_rect.position.x + chart_rect.size.x, y),
				Color(COLOR_BULLISH.r, COLOR_BULLISH.g, COLOR_BULLISH.b, 0.4),
				1.0, 4.0
			)

		## خط وقف الخسارة
		if trade.stop_loss > 0:
			var y := _price_to_y(trade.stop_loss, chart_rect)
			draw_dashed_line(
				Vector2(chart_rect.position.x, y),
				Vector2(chart_rect.position.x + chart_rect.size.x, y),
				Color(COLOR_BEARISH.r, COLOR_BEARISH.g, COLOR_BEARISH.b, 0.4),
				1.0, 4.0
			)

## ============================================
## رسم الكروسهاير + معلومات الشمعة
## ============================================
func _draw_crosshair(chart_rect: Rect2) -> void:
	if _mouse_pos.x < 0 or _mouse_pos.y < 0:
		return

	if not chart_rect.has_point(_mouse_pos):
		_hovered_candle_idx = -1
		return

	## خط أفقي
	draw_line(
		Vector2(chart_rect.position.x, _mouse_pos.y),
		Vector2(chart_rect.position.x + chart_rect.size.x, _mouse_pos.y),
		COLOR_CROSSHAIR, 0.5
	)

	## خط عمودي
	draw_line(
		Vector2(_mouse_pos.x, chart_rect.position.y),
		Vector2(_mouse_pos.x, chart_rect.position.y + chart_rect.size.y),
		COLOR_CROSSHAIR, 0.5
	)

	## تسمية السعر على المحور
	var price := _y_to_price(_mouse_pos.y, chart_rect)
	if price > 0:
		var label := _format_price(price)
		var tw := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 11).x
		var tag_rect := Rect2(
			chart_rect.position.x + chart_rect.size.x + 2,
			_mouse_pos.y - 8,
			tw + 8,
			16
		)
		draw_rect(tag_rect, Color(0.2, 0.2, 0.35, 0.9))
		draw_string(
			ThemeDB.fallback_font,
			Vector2(tag_rect.position.x + 4, tag_rect.position.y + 12),
			label,
			HORIZONTAL_ALIGNMENT_LEFT,
			tw,
			11,
			Color.WHITE
		)

	## إيجاد الشمعة المقربة
	var num_candles := _candles.size()
	var candle_width := chart_rect.size.x / num_candles
	var local_x := _mouse_pos.x - chart_rect.position.x
	var candle_idx := int(local_x / candle_width)
	candle_idx = clampi(candle_idx, 0, num_candles - 1)

	if candle_idx != _hovered_candle_idx:
		_hovered_candle_idx = candle_idx
		if candle_idx < _candles.size():
			candle_hovered.emit(_candles[candle_idx], candle_idx)

## ============================================
## أحداث الماوس
## ============================================
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_pos = event.position
		queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _hovered_candle_idx >= 0 and _hovered_candle_idx < _candles.size():
				candle_clicked.emit(_candles[_hovered_candle_idx], _hovered_candle_idx)
		## التكبير/التصغير
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if chart_manager:
				chart_manager.zoom_in()
				_refresh_visible_candles()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if chart_manager:
				chart_manager.zoom_out()
				_refresh_visible_candles()
	elif event is InputEventScreenDrag:
		## سحب للتمرير (موبايل)
		_mouse_pos = event.position
		queue_redraw()

func _refresh_visible_candles() -> void:
	if chart_manager and chart_manager.has_method("get_visible_candles"):
		update_candles(chart_manager.get_visible_candles())

## ============================================
## تحويلات الإحداثيات
## ============================================
func _price_to_y(price: float, chart_rect: Rect2) -> float:
	if _price_range["range"] <= 0:
		return chart_rect.position.y
	var ratio := (price - _price_range["low"]) / _price_range["range"]
	return chart_rect.position.y + chart_rect.size.y - ratio * chart_rect.size.y

func _y_to_price(y: float, chart_rect: Rect2) -> float:
	var ratio := (chart_rect.position.y + chart_rect.size.y - y) / chart_rect.size.y
	return _price_range["low"] + ratio * _price_range["range"]

func _candle_index_to_x(index: int, chart_rect: Rect2) -> float:
	if _candles.size() == 0:
		return chart_rect.position.x
	var candle_width := chart_rect.size.x / _candles.size()
	return chart_rect.position.x + (index + 0.5) * candle_width

## ============================================
## أدوات مساعدة
## ============================================
func _get_price_range() -> Dictionary:
	if _candles.is_empty():
		return {"high": 0.0, "low": 0.0, "range": 0.0}
	var high := -INF
	var low := INF
	for c in _candles:
		if c["high"] > high:
			high = c["high"]
		if c["low"] < low:
			low = c["low"]
	var range_val := high - low
	if range_val <= 0:
		range_val = high * 0.01  ## هامش 1%
		high += range_val / 2.0
		low -= range_val / 2.0
		range_val = high - low
	return {"high": high, "low": low, "range": range_val}

func _nice_number(value: float) -> float:
	if value <= 0:
		return 1.0
	var exponent := floor(log(value) / log(10.0))
	var fraction := value / pow(10.0, exponent)
	var nice_frac := 1.0
	if fraction <= 1.5:
		nice_frac = 1.0
	elif fraction <= 3.0:
		nice_frac = 2.0
	elif fraction <= 7.0:
		nice_frac = 5.0
	else:
		nice_frac = 10.0
	return nice_frac * pow(10.0, exponent)

func _format_price(price: float) -> String:
	if price >= 10000:
		return "%.1f" % price
	elif price >= 100:
		return "%.2f" % price
	elif price >= 1:
		return "%.3f" % price
	else:
		return "%.5f" % price

func _get_current_symbol() -> String:
	if chart_manager:
		return chart_manager.current_symbol
	return ""
