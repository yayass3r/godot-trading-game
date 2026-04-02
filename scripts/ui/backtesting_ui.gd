extends Control

const STRATEGIES: Array[Dictionary] = [
	{ "name": "SMA Crossover", "type": "sma_crossover", "fast_period": 9, "slow_period": 21 },
	{ "name": "RSI Oversold/Overbought", "type": "rsi", "period": 14, "oversold": 30, "overbought": 70 },
	{ "name": "Bollinger Bounce", "type": "bollinger_bounce", "period": 20, "std_dev": 2.0 },
	{ "name": "MACD Signal", "type": "macd", "fast": 12, "slow": 26, "signal": 9 },
	{ "name": "Volume Spike", "type": "volume_spike", "multiplier": 2.0 },
]

func _ready():
	_connect_signals()

func _connect_signals():
	if BacktestingEngine:
		BacktestingEngine.backtest_completed.connect(_on_backtest_completed)
		BacktestingEngine.progress_updated.connect(_on_progress_updated)

func _on_run_pressed():
	var strategy_idx = $ScrollContainer/MainVBox/StrategyPanel/StrategyContent/StrategyList.get_selected_items()
	if strategy_idx.is_empty():
		return
	var idx: int = strategy_idx[0]
	if idx < 0 or idx >= STRATEGIES.size():
		return
	var strategy: Dictionary = STRATEGIES[idx]
	var symbol = "BTCUSDT"
	var leverage = 10
	var balance = 10000.0
	if BacktestingEngine:
		BacktestingEngine.run_backtest(strategy, symbol, leverage, balance)

func _on_backtest_completed(results: Dictionary):
	$ScrollContainer/MainVBox/ResultsPanel/ResultsContent/ResultsGrid/RatingValue.text = str(results.get("rating", "N/A"))
	$ScrollContainer/MainVBox/ResultsPanel/ResultsContent/ResultsGrid/ReturnPctValue.text = "%.2f%%" % results.get("total_return", 0.0)
	$ScrollContainer/MainVBox/ResultsPanel/ResultsContent/ResultsGrid/WinRateValue.text = "%.1f%%" % results.get("win_rate", 0.0)
	$ScrollContainer/MainVBox/ResultsPanel/ResultsContent/ResultsGrid/ProfitFactorValue.text = "%.2f" % results.get("profit_factor", 0.0)
	$ScrollContainer/MainVBox/ResultsPanel/ResultsContent/ResultsGrid/MaxDDValue.text = "%.2f%%" % results.get("max_drawdown", 0.0)
	$ScrollContainer/MainVBox/ResultsPanel/ResultsContent/ResultsGrid/SharpeValue.text = "%.2f" % results.get("sharpe_ratio", 0.0)

func _on_progress_updated(progress: float):
	$ScrollContainer/MainVBox/ProgressBar.value = progress * 100.0

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
