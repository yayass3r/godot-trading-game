extends Control

func _ready():
	_connect_signals()

func _connect_signals():
	if BacktestingEngine:
		BacktestingEngine.backtest_completed.connect(_on_backtest_completed)
		BacktestingEngine.progress_updated.connect(_on_progress_updated)

func _on_run_pressed():
	var strategy_idx = $VBoxContainer/ConfigPanel/StrategyList.selected
	var symbol = "BTCUSDT"
	var leverage = 10
	var balance = 10000.0
	if BacktestingEngine:
		BacktestingEngine.run_backtest(strategy_idx, symbol, leverage, balance)

func _on_backtest_completed(results: Dictionary):
	$VBoxContainer/ResultsPanel/RatingLabel.text = "Rating: %s" % results.get("rating", "N/A")
	$VBoxContainer/ResultsPanel/ReturnLabel.text = "Return: %.2f%%" % results.get("total_return", 0.0)
	$VBoxContainer/ResultsPanel/WinRateLabel.text = "Win Rate: %.1f%%" % results.get("win_rate", 0.0)
	$VBoxContainer/ResultsPanel/ProfitFactorLabel.text = "Profit Factor: %.2f" % results.get("profit_factor", 0.0)
	$VBoxContainer/ResultsPanel/MaxDDLabel.text = "Max Drawdown: %.2f%%" % results.get("max_drawdown", 0.0)
	$VBoxContainer/ResultsPanel/SharpeLabel.text = "Sharpe: %.2f" % results.get("sharpe_ratio", 0.0)

func _on_progress_updated(progress: float):
	$VBoxContainer/ProgressPanel/ProgressBar.value = progress * 100.0

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
