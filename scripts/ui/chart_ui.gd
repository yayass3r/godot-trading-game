## ============================================
## ChartUI.gd - واجهة الرسوم البيانية المحسّنة
## تعرض شموع التداول الاحترافية مع مؤشرات فنية
## تشمل: شموع يابانية، محاور، شبكة، كروسهاير، RSI، MACD
## ============================================
extends Control

## ---- Node References ----
@onready var back_button: Button = $BackButton
@onready var symbol_label: Label = $VBoxContainer/TopBar/SymbolLabel
@onready var price_label: Label = $VBoxContainer/PriceInfo/PriceRow/CurrentPrice
@onready var change_label: Label = $VBoxContainer/PriceInfo/PriceRow/PriceChange

## ---- الشارت الرئيسي (CandlestickChart) ----
@onready var candlestick_chart: Control = $VBoxContainer/ChartPanel/ChartArea/CandlestickChart

## ---- لوحة الحجم ----
@onready var volume_panel: Control = $VBoxContainer/ChartPanel/ChartArea/VolumeChart

## ---- لوحة RSI ----
@onready var rsi_panel: Control = $VBoxContainer/ChartPanel/ChartArea/RSIPanel

## ---- لوحة MACD ----
@onready var macd_panel: Control = $VBoxContainer/ChartPanel/ChartArea/MACDPanel

## ---- أزرار الإطار الزمني ----
@onready var interval_1m: Button = $VBoxContainer/TimeframeRow/TF1m
@onready var interval_5m: Button = $VBoxContainer/TimeframeRow/TF5m
@onready var interval_15m: Button = $VBoxContainer/TimeframeRow/TF15m
@onready var interval_1h: Button = $VBoxContainer/TimeframeRow/TF1h
@onready var interval_4h: Button = $VBoxContainer/TimeframeRow/TF4h
@onready var interval_1d: Button = $VBoxContainer/TimeframeRow/TF1d

## ---- أزرار المؤشرات ----
@onready var sma9_toggle: CheckButton = $VBoxContainer/IndicatorsRow/SMA9Toggle
@onready var sma21_toggle: CheckButton = $VBoxContainer/IndicatorsRow/SMA21Toggle
@onready var sma50_toggle: CheckButton = $VBoxContainer/IndicatorsRow/SMA50Toggle
@onready var bb_toggle: CheckButton = $VBoxContainer/IndicatorsRow/BBToggle
@onready var rsi_toggle: CheckButton = $VBoxContainer/IndicatorsRow/RSIToggle
@onready var macd_toggle: CheckButton = $VBoxContainer/IndicatorsRow/MACDToggle

## ---- معلومات الكروسهاير ----
@onready var crosshair_info: Label = $VBoxContainer/CrosshairInfo

## ---- Manager References ----
@onready var chart_manager: Node = get_node_or_null("/root/ChartManager")
@onready var data_manager: Node = get_node_or_null("/root/DataManager")

## ---- State ----
var current_symbol: String = "BTCUSDT"
var current_interval: String = "1h"
var _active_timeframe_btn: Button = null

## ---- تحويلات سلسة ----
var _price_tween: SceneTreeTween = null
var _last_price: float = 0.0

## ============================================
## _ready()
## ============================================
func _ready() -> void:
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

	_connect_manager_signals()
	_connect_timeframe_buttons()
	_connect_indicator_buttons()

	## تحميل الشارت الافتراضي
	_load_chart()

func _connect_manager_signals() -> void:
	if chart_manager:
		chart_manager.chart_updated.connect(_on_chart_updated)
		chart_manager.timeframe_changed.connect(_on_timeframe_changed)
	if data_manager:
		data_manager.price_updated.connect(_on_price_updated)

## ============================================
## ربط أزرار الإطار الزمني
## ============================================
func _connect_timeframe_buttons() -> void:
	var buttons := {
		"1m": interval_1m,
		"5m": interval_5m,
		"15m": interval_15m,
		"1h": interval_1h,
		"4h": interval_4h,
		"1d": interval_1d,
	}
	for interval in buttons:
		var btn: Button = buttons[interval]
		if btn:
			btn.pressed.connect(_on_timeframe_pressed.bind(interval))

	## تحديد الافتراضي
	_active_timeframe_btn = interval_1h
	_update_timeframe_buttons("1h")

## ============================================
## ربط أزرار المؤشرات
## ============================================
func _connect_indicator_buttons() -> void:
	if sma9_toggle:
		sma9_toggle.toggled.connect(func(on: bool): _set_indicator("sma_9", on))
	if sma21_toggle:
		sma21_toggle.toggled.connect(func(on: bool): _set_indicator("sma_21", on))
	if sma50_toggle:
		sma50_toggle.toggled.connect(func(on: bool): _set_indicator("sma_50", on))
	if bb_toggle:
		bb_toggle.toggled.connect(func(on: bool): _set_indicator("bollinger", on))
	if rsi_toggle:
		rsi_toggle.toggled.connect(func(on: bool): _toggle_sub_panel("rsi", on))
	if macd_toggle:
		macd_toggle.toggled.connect(func(on: bool): _toggle_sub_panel("macd", on))

	## ربط إشارة الكروسهاير
	if candlestick_chart and candlestick_chart.has_signal("candle_hovered"):
		candlestick_chart.candle_hovered.connect(_on_candle_hovered)

## ============================================
## تفعيل/تعطيل مؤشرات الشارت
## ============================================
func _set_indicator(name: String, enabled: bool) -> void:
	if not candlestick_chart:
		return

	match name:
		"sma_9":
			candlestick_chart.show_sma_9 = enabled
		"sma_21":
			candlestick_chart.show_sma_21 = enabled
		"sma_50":
			candlestick_chart.show_sma_50 = enabled
		"bollinger":
			candlestick_chart.show_bollinger = enabled

	candlestick_chart.queue_redraw()

## ============================================
## إظهار/إخفاء لوحات المؤشرات الفرعية
## ============================================
func _toggle_sub_panel(name: String, visible: bool) -> void:
	match name:
		"rsi":
			if rsi_panel:
				rsi_panel.visible = visible
		"macd":
			if macd_panel:
				macd_panel.visible = visible

## ============================================
## Load chart
## ============================================
func _load_chart() -> void:
	if chart_manager and chart_manager.has_method("load_chart"):
		chart_manager.load_chart(current_symbol, current_interval)

## ============================================
## Timeframe button pressed
## ============================================
func _on_timeframe_pressed(interval: String) -> void:
	current_interval = interval
	_update_timeframe_buttons(interval)
	if chart_manager and chart_manager.has_method("load_chart"):
		chart_manager.load_chart(current_symbol, current_interval)

func _update_timeframe_buttons(interval: String) -> void:
	var buttons := {
		"1m": interval_1m,
		"5m": interval_5m,
		"15m": interval_15m,
		"1h": interval_1h,
		"4h": interval_4h,
		"1d": interval_1d,
	}
	for tf in buttons:
		var btn: Button = buttons[tf]
		if btn:
			if tf == interval:
				btn.add_theme_color_override("font_color", Color.WHITE)
				btn.add_theme_color_override("self_modulate", Color(0.2, 0.4, 0.8, 0.5))
			else:
				btn.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
				btn.add_theme_color_override("self_modulate", Color.WHITE)

## ============================================
## Chart data received
## ============================================
func _on_chart_updated(symbol: String, interval: String, candle_count: int) -> void:
	if symbol != current_symbol or interval != current_interval:
		return

	## تحديث رأس السعر
	if chart_manager:
		var change_data: Dictionary = chart_manager.get_price_change_percentage() if chart_manager.has_method("get_price_change_percentage") else {}
		if price_label and change_data.has("latest"):
			_animate_price_label(float(price_label.text.replace("$", "").replace(",", "")), change_data["latest"])
		if change_label and change_data.has("change_pct"):
			var pct: float = change_data["change_pct"]
			var sign := "+" if pct >= 0 else ""
			change_label.text = "%s%.2f%%" % [sign, pct]
			change_label.add_theme_color_override(
				"font_color",
				Color.GREEN if pct >= 0 else Color.RED
			)

	## تحديث الشموع على الشارت
	if candlestick_chart and chart_manager.has_method("get_visible_candles"):
		candlestick_chart.update_candles(chart_manager.get_visible_candles())

	## تحديث لوحات المؤشرات الفرعية
	if rsi_panel and rsi_panel.visible and chart_manager.has_method("get_visible_candles"):
		if rsi_panel.has_method("update_candles"):
			rsi_panel.update_candles(chart_manager.get_visible_candles())
	if macd_panel and macd_panel.visible and chart_manager.has_method("get_visible_candles"):
		if macd_panel.has_method("update_candles"):
			macd_panel.update_candles(chart_manager.get_visible_candles())

## ============================================
## Live price update مع تحويل سلس
## ============================================
func _on_price_updated(symbol: String, price: float, _timestamp: int) -> void:
	if symbol == current_symbol and price_label:
		_animate_price_label(_last_price, price)

func _animate_price_label(old_val: float, new_val: float) -> void:
	if not price_label:
		return

	price_label.text = "$%.2f" % new_val

	if _price_tween and _price_tween.is_running():
		_price_tween.kill()

	var change_color := Color.WHITE
	if old_val > 0:
		change_color = Color(0.14, 0.83, 0.44) if new_val >= old_val else Color(0.9, 0.31, 0.27)

	price_label.add_theme_color_override("font_color", change_color)

	_price_tween = create_tween()
	_price_tween.set_ease(Tween.EASE_OUT)
	_price_tween.set_trans(Tween.TRANS_SINE)
	_price_tween.tween_property(price_label, "self_modulate", Color.WHITE, 1.0)

	_last_price = new_val

## ============================================
## Timeframe changed
## ============================================
func _on_timeframe_changed(new_interval: String) -> void:
	current_interval = new_interval
	_update_timeframe_buttons(new_interval)

## ============================================
## كروسهاير - تمرير فوق شمعة
## ============================================
func _on_candle_hovered(candle: Dictionary, _index: int) -> void:
	if crosshair_info:
		crosshair_info.text = "O: %.2f  H: %.2f  L: %.2f  C: %.2f  V: %.0f" % [
			candle.get("open", 0.0),
			candle.get("high", 0.0),
			candle.get("low", 0.0),
			candle.get("close", 0.0),
			candle.get("volume", 0.0)
		]

## ============================================
## Back
## ============================================
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
