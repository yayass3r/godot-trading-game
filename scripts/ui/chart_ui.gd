extends Control

var current_symbol: String = "BTCUSDT"
var current_interval: String = "1h"

func _ready():
	_connect_signals()
	_load_candlestick_data()

func _connect_signals():
	if ChartManager:
		ChartManager.chart_data_updated.connect(_on_chart_data_updated)
	if DataManager:
		DataManager.price_updated.connect(_on_price_updated)

func _load_candlestick_data():
	if ChartManager:
		ChartManager.request_candlestick_data(current_symbol, current_interval)

func _on_chart_data_updated(symbol: String, interval: String, candles: Array):
	if symbol == current_symbol and interval == current_interval:
		_draw_candlestick_chart(candles)
		if ChartManager.volume_data.has(symbol):
			_draw_volume_chart(ChartManager.volume_data[symbol])

func _on_price_updated(symbol: String, price: float):
	if symbol == current_symbol:
		$VBoxContainer/PriceHeader/PriceLabel.text = "$%.2f" % price

func _draw_candlestick_chart(candles: Array):
	var chart_panel = $VBoxContainer/ChartPanel/CandlestickChart
	if chart_panel and chart_panel is Control:
		for child in chart_panel.get_children():
			child.queue_free()
		var label = Label.new()
		label.text = "%d candles loaded" % candles.size()
		label.position = Vector2(10, 10)
		chart_panel.add_child(label)

func _draw_volume_chart(volume_data: Array):
	pass

func _on_timeframe_pressed(interval: String):
	current_interval = interval
	_load_candlestick_data()

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
