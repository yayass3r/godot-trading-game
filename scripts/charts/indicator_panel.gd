## ============================================
## IndicatorPanel.gd - لوحة المؤشرات الفنية المنفصلة
## يرسم RSI و MACD في مربعات منفصلة أسفل الشارت الرئيسي
## ============================================
extends Control

## ---- ألوان ----
var COLOR_BG: Color = Color(0.06, 0.06, 0.12, 1.0)
var COLOR_GRID: Color = Color(0.15, 0.15, 0.22, 0.4)
var COLOR_AXIS_TEXT: Color = Color(0.55, 0.55, 0.65, 1.0)
var COLOR_RSI_LINE: Color = Color(0.84, 0.34, 0.93, 1.0)         ## بنفسجي
var COLOR_RSI_OVERBOUGHT: Color = Color(0.9, 0.3, 0.27, 0.3)     ## أحمر شفاف
var COLOR_RSI_OVERSOLD: Color = Color(0.14, 0.83, 0.44, 0.3)     ## أخضر شفاف
var COLOR_MACD_LINE: Color = Color(0.24, 0.71, 0.92, 1.0)        ## أزرق
var COLOR_MACD_SIGNAL: Color = Color(1.0, 0.55, 0.0, 1.0)        ## برتقالي
var COLOR_MACD_HIST_POS: Color = Color(0.14, 0.83, 0.44, 0.7)    ## أخضر
var COLOR_MACD_HIST_NEG: Color = Color(0.9, 0.31, 0.27, 0.7)     ## أحمر

## ---- مراجع ----
var chart_manager: Node

## ---- إعدادات ----
var PADDING_RIGHT: float = 70.0
var PADDING_LEFT: float = 5.0
var PADDING_TOP: float = 8.0
var PADDING_BOTTOM: float = 20.0

## ---- أنواع المؤشر ----
enum IndicatorType { RSI, MACD }
var indicator_type: IndicatorType = IndicatorType.RSI

## ---- حالة ----
var _candles: Array[Dictionary] = []

## ============================================
## _ready()
## ============================================
func _ready() -> void:
	chart_manager = get_node_or_null("/root/ChartManager")
	clip_contents = true

## ============================================
## تحديث البيانات
## ============================================
func update_candles(candles: Array[Dictionary]) -> void:
	_candles = candles
	queue_redraw()

## ============================================
## _draw()
## ============================================
func _draw() -> void:
	var rect := get_rect()
	if rect.size.x < 50 or rect.size.y < 30:
		return

	draw_rect(rect, COLOR_BG)

	if _candles.is_empty():
		return

	var chart_rect := Rect2(
		PADDING_LEFT, PADDING_TOP,
		rect.size.x - PADDING_RIGHT - PADDING_LEFT,
		rect.size.y - PADDING_BOTTOM - PADDING_TOP
	)

	if chart_rect.size.x < 10 or chart_rect.size.y < 10:
		return

	match indicator_type:
		IndicatorType.RSI:
			_draw_rsi(chart_rect)
		IndicatorType.MACD:
			_draw_macd(chart_rect)

## ============================================
## رسم RSI
## ============================================
func _draw_rsi(chart_rect: Rect2) -> void:
	if not chart_manager:
		return

	var rsi: Array = chart_manager.rsi_data.get("14", [])
	if rsi.size() != _candles.size():
		return

	var num := _candles.size()

	## رسم مناطق التشبع
	## منطقة التشبع الشراء (فوق 70)
	var overbought_y := _rsi_to_y(70.0, chart_rect)
	var oversold_y := _rsi_to_y(30.0, chart_rect)
	var mid_y := _rsi_to_y(50.0, chart_rect)

	## منطقة تشبع الشراء
	var ob_rect := Rect2(chart_rect.position.x, chart_rect.position.y, chart_rect.size.x, overbought_y - chart_rect.position.y)
	draw_rect(ob_rect, COLOR_RSI_OVERBOUGHT)

	## منطقة تشبع البيع
	var os_rect := Rect2(chart_rect.position.x, oversold_y, chart_rect.size.x, chart_rect.position.y + chart_rect.size.y - oversold_y)
	draw_rect(os_rect, COLOR_RSI_OVERSOLD)

	## خطوط مرجعية
	draw_dashed_line(Vector2(chart_rect.position.x, overbought_y), Vector2(chart_rect.position.x + chart_rect.size.x, overbought_y), COLOR_GRID, 1.0, 4.0)
	draw_dashed_line(Vector2(chart_rect.position.x, mid_y), Vector2(chart_rect.position.x + chart_rect.size.x, mid_y), COLOR_GRID, 0.5, 6.0)
	draw_dashed_line(Vector2(chart_rect.position.x, oversold_y), Vector2(chart_rect.position.x + chart_rect.size.x, oversold_y), COLOR_GRID, 1.0, 4.0)

	## تسميات
	_draw_y_label("70", overbought_y, chart_rect)
	_draw_y_label("50", mid_y, chart_rect)
	_draw_y_label("30", oversold_y, chart_rect)

	## رسم خط RSI
	var points := PackedVector2Array()
	for i in range(num):
		var val: float = rsi[i]
		if val <= 0:
			continue
		var x := _index_to_x(i, chart_rect)
		var y := _rsi_to_y(val, chart_rect)
		points.append(Vector2(x, y))

	if points.size() >= 2:
		draw_polyline(points, COLOR_RSI_LINE, 1.5, false)

	## عنوان المؤشر
	_draw_indicator_title("RSI(14)", chart_rect, COLOR_RSI_LINE)

## ============================================
## رسم MACD
## ============================================
func _draw_macd(chart_rect: Rect2) -> void:
	if not chart_manager:
		return

	var macd_dict: Dictionary = chart_manager.macd_data
	if macd_dict.is_empty():
		return

	var macd_line: Array = macd_dict.get("macd", [])
	var signal_line: Array = macd_dict.get("signal", [])
	var histogram: Array = macd_dict.get("histogram", [])

	if macd_line.is_empty():
		return

	## حساب النطاق
	var max_val := 0.0
	for val in macd_line:
		max_val = maxf(max_val, absf(val))
	for val in signal_line:
		max_val = maxf(max_val, absf(val))
	for val in histogram:
		max_val = maxf(max_val, absf(val))

	if max_val <= 0:
		max_val = 1.0

	max_val *= 1.2  ## هامش

	var zero_y := _macd_to_y(0.0, max_val, chart_rect)
	draw_line(
		Vector2(chart_rect.position.x, zero_y),
		Vector2(chart_rect.position.x + chart_rect.size.x, zero_y),
		COLOR_GRID, 0.5
	)
	_draw_y_label("0", zero_y, chart_rect)

	## رسم أعمدة الهيستوجرام
	var num_histo := histogram.size()
	var candle_width := chart_rect.size.x / num_histo
	var bar_width := candle_width * 0.6

	for i in range(num_histo):
		var val: float = histogram[i]
		var x := _index_to_x(i, chart_rect)
		var bar_y := _macd_to_y(val, max_val, chart_rect)
		var bar_height := absf(bar_y - zero_y)
		bar_height = maxf(bar_height, 1.0)

		var bar_color := COLOR_MACD_HIST_POS if val >= 0 else COLOR_MACD_HIST_NEG
		var bar_rect := Rect2(x - bar_width / 2.0, minf(bar_y, zero_y), bar_width, bar_height)
		draw_rect(bar_rect, bar_color)

	## رسم خط MACD
	if macd_line.size() == _candles.size():
		var points := PackedVector2Array()
		for i in range(macd_line.size()):
			var x := _index_to_x(i, chart_rect)
			var y := _macd_to_y(macd_line[i], max_val, chart_rect)
			points.append(Vector2(x, y))
		if points.size() >= 2:
			draw_polyline(points, COLOR_MACD_LINE, 1.5, false)

	## رسم خط Signal
	if signal_line.size() > 0:
		var offset := macd_line.size() - signal_line.size()
		var points := PackedVector2Array()
		for i in range(signal_line.size()):
			var candle_i := i + offset
			if candle_i >= _candles.size():
				break
			var x := _index_to_x(candle_i, chart_rect)
			var y := _macd_to_y(signal_line[i], max_val, chart_rect)
			points.append(Vector2(x, y))
		if points.size() >= 2:
			draw_polyline(points, COLOR_MACD_SIGNAL, 1.5, false)

	## عنوان المؤشر
	_draw_indicator_title("MACD(12,26,9)", chart_rect, COLOR_MACD_LINE)

## ============================================
## تحويلات
## ============================================
func _rsi_to_y(rsi_val: float, chart_rect: Rect2) -> float:
	var ratio := rsi_val / 100.0
	return chart_rect.position.y + chart_rect.size.y * (1.0 - ratio)

func _macd_to_y(val: float, max_val: float, chart_rect: Rect2) -> float:
	var ratio := val / max_val
	return chart_rect.position.y + chart_rect.size.y * (1.0 - ratio) / 2.0 + chart_rect.size.y * 0.25

func _index_to_x(index: int, chart_rect: Rect2) -> float:
	var num := _candles.size()
	if num == 0:
		return chart_rect.position.x
	var width := chart_rect.size.x / num
	return chart_rect.position.x + (index + 0.5) * width

## ============================================
## أدوات رسم مساعدة
## ============================================
func _draw_y_label(text: String, y: float, chart_rect: Rect2) -> void:
	draw_string(
		ThemeDB.fallback_font,
		Vector2(chart_rect.position.x + chart_rect.size.x + 5, y + 4),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		PADDING_RIGHT - 5,
		10,
		COLOR_AXIS_TEXT
	)

func _draw_indicator_title(title: String, chart_rect: Rect2, color: Color) -> void:
	draw_string(
		ThemeDB.fallback_font,
		Vector2(chart_rect.position.x + 5, chart_rect.position.y + 12),
		title,
		HORIZONTAL_ALIGNMENT_LEFT,
		100,
		11,
		color
	)
