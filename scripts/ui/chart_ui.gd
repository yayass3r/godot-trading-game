## ============================================
## ChartUI.gd - واجهة الرسوم البيانية
## تعرض شموع التداول مع مؤشرات فنية
## ============================================
extends Control

## ---- Node References ----
@onready var back_button: Button = $BackButton
@onready var symbol_label: Label = $VBoxContainer/TopBar/SymbolLabel
@onready var price_label: Label = $VBoxContainer/PriceInfo/PriceRow/CurrentPrice
@onready var change_label: Label = $VBoxContainer/PriceInfo/PriceRow/PriceChange
@onready var chart_panel: Control = $VBoxContainer/ChartPanel/ChartArea/CandlestickChart
@onready var interval_1m: Button = $VBoxContainer/TimeframeRow/TF1m
@onready var interval_5m: Button = $VBoxContainer/TimeframeRow/TF5m
@onready var interval_15m: Button = $VBoxContainer/TimeframeRow/TF15m
@onready var interval_1h: Button = $VBoxContainer/TimeframeRow/TF1h
@onready var interval_4h: Button = $VBoxContainer/TimeframeRow/TF4h
@onready var interval_1d: Button = $VBoxContainer/TimeframeRow/TF1d

## ---- Manager References ----
@onready var chart_manager: Node = get_node_or_null("/root/ChartManager")
@onready var data_manager: Node = get_node_or_null("/root/DataManager")

## ---- State ----
var current_symbol: String = "BTCUSDT"
var current_interval: String = "1h"

## ============================================
## _ready() - Initialize UI and connect signals
## ============================================
func _ready() -> void:
        if back_button:
                back_button.pressed.connect(_on_back_pressed)

        _connect_manager_signals()
        _connect_timeframe_buttons()

        ## Load initial chart
        _load_chart()

func _connect_manager_signals() -> void:
        if chart_manager:
                chart_manager.chart_updated.connect(_on_chart_updated)
                chart_manager.timeframe_changed.connect(_on_timeframe_changed)
        if data_manager:
                data_manager.price_updated.connect(_on_price_updated)

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

## ============================================
## Load chart via ChartManager
## ============================================
func _load_chart() -> void:
        if chart_manager and chart_manager.has_method("load_chart"):
                chart_manager.load_chart(current_symbol, current_interval)

## ============================================
## Timeframe button pressed
## ============================================
func _on_timeframe_pressed(interval: String) -> void:
        current_interval = interval
        if chart_manager and chart_manager.has_method("load_chart"):
                chart_manager.load_chart(current_symbol, current_interval)

## ============================================
## Chart data received from ChartManager
## ============================================
func _on_chart_updated(symbol: String, interval: String, candle_count: int) -> void:
        if symbol != current_symbol or interval != current_interval:
                return

        ## Update price header
        if chart_manager:
                var change_data: Dictionary = chart_manager.get_price_change_percentage() if chart_manager.has_method("get_price_change_percentage") else {}
                if price_label and change_data.has("latest"):
                        price_label.text = "$%.2f" % change_data["latest"]
                if change_label and change_data.has("change_pct"):
                        var pct: float = change_data["change_pct"]
                        var sign := "+" if pct >= 0 else ""
                        change_label.text = "%s%.2f%%" % [sign, pct]
                        change_label.add_theme_color_override(
                                "font_color",
                                Color.GREEN if pct >= 0 else Color.RED
                        )

        ## Draw candles on chart panel
        if chart_panel:
                var visible_candles: Array = []
                if chart_manager and chart_manager.has_method("get_visible_candles"):
                        visible_candles = chart_manager.get_visible_candles()
                _draw_candlestick_chart(visible_candles)

## ============================================
## Live price updates from DataManager
## ============================================
func _on_price_updated(symbol: String, price: float, _timestamp: int) -> void:
        if symbol == current_symbol and price_label:
                price_label.text = "$%.2f" % price

## ============================================
## Timeframe changed (from ChartManager signal)
## ============================================
func _on_timeframe_changed(new_interval: String) -> void:
        current_interval = new_interval

## ============================================
## Draw candlestick chart on the panel
## ============================================
func _draw_candlestick_chart(candles: Array) -> void:
        if not chart_panel:
                return

        ## Clear previous drawing
        for child in chart_panel.get_children():
                child.queue_free()

        if candles.is_empty():
                var empty_lbl := Label.new()
                empty_lbl.text = "Loading chart data..."
                empty_lbl.position = Vector2(10, 10)
                chart_panel.add_child(empty_lbl)
                return

        ## Display info label (placeholder — full chart rendering would use _draw())
        var info := Label.new()
        info.text = "%d candles | %s %s" % [candles.size(), current_symbol, current_interval]
        info.position = Vector2(10, 10)
        chart_panel.add_child(info)

        var price_lbl := Label.new()
        if candles.size() > 0:
                price_lbl.text = "O: %.2f  H: %.2f  L: %.2f  C: %.2f" % [
                        candles[-1].get("open", 0.0),
                        candles[-1].get("high", 0.0),
                        candles[-1].get("low", 0.0),
                        candles[-1].get("close", 0.0)
                ]
        price_lbl.position = Vector2(10, 30)
        chart_panel.add_child(price_lbl)

## ============================================
## Back to main menu
## ============================================
func _on_back_pressed() -> void:
        get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
