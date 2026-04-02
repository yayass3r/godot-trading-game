## ============================================
## TradingUI.gd - واجهة التداول الرئيسية
## تتحكم في عرض الأسعار وفتح/إغلاق الصفقات
## ============================================
extends Control

const TradeClass = preload("res://scripts/data_models/trade.gd")
const NP = preload("res://scripts/enums/notification_priority.gd")

## ---- Node References (Flat Scene Structure) ----
@onready var back_button: Button = $BackButton
@onready var symbol_label: Label = $VBoxContainer/Header/SymbolLabel
@onready var price_label: Label = $VBoxContainer/Header/PriceLabel
@onready var change_label: Label = $VBoxContainer/Header/ChangeLabel
@onready var balance_label: Label = $VBoxContainer/PortfolioInfo/PortfolioVBox/BalanceLabel
@onready var equity_label: Label = $VBoxContainer/PortfolioInfo/PortfolioVBox/EquityLabel
@onready var margin_label: Label = $VBoxContainer/PortfolioInfo/PortfolioVBox/MarginLabel
@onready var symbol_option: OptionButton = $VBoxContainer/TradePanel/TradeContent/SymbolOption
@onready var leverage_slider: HSlider = $VBoxContainer/TradePanel/TradeContent/LeverageSlider
@onready var leverage_display: Label = $VBoxContainer/TradePanel/TradeContent/LeverageLabel
@onready var amount_input: LineEdit = $VBoxContainer/TradePanel/TradeContent/AmountInput
@onready var margin_preview: Label = $VBoxContainer/TradePanel/TradeContent/MarginPreview
@onready var liquidation_label: Label = $VBoxContainer/TradePanel/TradeContent/LiquidationLabel
@onready var buy_button: Button = $VBoxContainer/TradePanel/TradeContent/ButtonRow/BuyButton
@onready var sell_button: Button = $VBoxContainer/TradePanel/TradeContent/ButtonRow/SellButton
@onready var open_trades_list: ItemList = $VBoxContainer/OpenTradesList

## ---- Manager References ----
@onready var trading_manager: Node = get_node_or_null("/root/TradingManager")
@onready var portfolio_manager: Node = get_node_or_null("/root/PortfolioManager")
@onready var profile_manager: Node = get_node_or_null("/root/ProfileManager")
@onready var data_manager: Node = get_node_or_null("/root/DataManager")

## ---- State ----
var current_symbol: String = "BTCUSDT"

## ============================================
## _ready() - Initialize UI and connect signals
## ============================================
func _ready() -> void:
        _connect_manager_signals()
        _connect_ui_signals()
        _populate_symbol_options()
        _refresh_ui()

func _connect_manager_signals() -> void:
        if data_manager:
                data_manager.price_updated.connect(_on_price_updated)
        if trading_manager:
                trading_manager.trade_opened.connect(_on_trade_opened)
                trading_manager.trade_closed.connect(_on_trade_closed)
        if portfolio_manager:
                portfolio_manager.portfolio_updated.connect(_on_portfolio_updated)
                portfolio_manager.margin_call_triggered.connect(_on_margin_call)

func _connect_ui_signals() -> void:
        if back_button:
                back_button.pressed.connect(_on_back_pressed)
        if buy_button:
                buy_button.pressed.connect(_on_buy_pressed)
        if sell_button:
                sell_button.pressed.connect(_on_sell_pressed)
        if leverage_slider:
                leverage_slider.min_value = 1
                leverage_slider.max_value = profile_manager.get_max_leverage() if profile_manager else 1
                leverage_slider.step = 1
                leverage_slider.value = 1
                leverage_slider.value_changed.connect(_on_leverage_changed)
        if amount_input:
                amount_input.text_changed.connect(_on_amount_changed)
        if symbol_option:
                symbol_option.item_selected.connect(_on_symbol_selected)

## ============================================
## Populate symbol dropdown from TradingManager
## ============================================
func _populate_symbol_options() -> void:
        if not symbol_option or not trading_manager:
                return
        for sym in trading_manager.available_symbols:
                symbol_option.add_item("%s (%s)" % [sym, trading_manager.available_symbols[sym]["name"]])

func _on_symbol_selected(index: int) -> void:
        if trading_manager and symbol_option:
                var symbols: Array = trading_manager.available_symbols.keys()
                if index >= 0 and index < symbols.size():
                        current_symbol = symbols[index]
                        if symbol_label:
                                symbol_label.text = "%s / USDT" % current_symbol

## ============================================
## Price updates from DataManager
## ============================================
func _on_price_updated(symbol: String, price: float, _timestamp: int) -> void:
        if symbol == current_symbol and price_label:
                price_label.text = "$%.2f" % price

## ============================================
## Portfolio updates from PortfolioManager
## ============================================
func _on_portfolio_updated(summary: Dictionary) -> void:
        if balance_label:
                balance_label.text = "Balance: $%.2f" % summary.get("balance", 0.0)
        if equity_label:
                equity_label.text = "Equity: $%.2f" % summary.get("equity", 0.0)
        if margin_label:
                var pct: float = float(summary.get("margin_usage_pct", 0.0))
                margin_label.text = "Margin Used: %.1f%% ($%.2f)" % [pct, summary.get("margin_used", 0.0)]

## ============================================
## Trade opened — add to list
## ============================================
func _on_trade_opened(trade) -> void:
        if open_trades_list:
                var dir := "LONG" if trade.trade_type == TradeClass.TradeType.LONG else "SHORT"
                open_trades_list.add_item(
                        "%s %s | Size: %.4f | %dx | Margin: $%.2f" % [
                                dir, trade.symbol, trade.position_size, trade.leverage, trade.margin_used
                        ]
                )
        _refresh_ui()

## ============================================
## Trade closed — remove from list
## ============================================
func _on_trade_closed(trade, pnl: float, _reason: String) -> void:
        if open_trades_list:
                for i in range(open_trades_list.item_count):
                        if trade.symbol in open_trades_list.get_item_text(i) and trade.trade_id in open_trades_list.get_item_text(i):
                                open_trades_list.remove_item(i)
                                break
        _refresh_ui()

## ============================================
## Margin call warning
## ============================================
func _on_margin_call(_trade, free_margin: float) -> void:
        NotificationManager.send_notification(
                "Margin Call!",
                "Free margin: $%.2f" % free_margin,
                NP.HIGH
        )

## ============================================
## Leverage slider changed
## ============================================
func _on_leverage_changed(value: float) -> void:
        if leverage_display:
                leverage_display.text = "Leverage: %.0fx" % value
        _update_margin_preview()

## ============================================
## Amount input changed
## ============================================
func _on_amount_changed(_new_text: String) -> void:
        _update_margin_preview()

## ============================================
## Update margin preview using TradingManager.estimate_margin()
## ============================================
func _update_margin_preview() -> void:
        if not trading_manager or not amount_input:
                return

        var amount := float(amount_input.text) if amount_input.text.is_valid_float() else 0.0
        var leverage := int(leverage_slider.value) if leverage_slider else 1

        if amount <= 0.0:
                if margin_preview:
                        margin_preview.text = "Required Margin: $0.00"
                if liquidation_label:
                        liquidation_label.text = ""
                return

        if trading_manager.has_method("estimate_margin"):
                var est: Dictionary = trading_manager.estimate_margin(amount, current_symbol, leverage)
                if margin_preview:
                        margin_preview.text = "Required Margin: $%.2f" % est.get("margin_required", 0.0)
                if liquidation_label:
                        liquidation_label.text = "Liq. Distance: %.1f%%" % est.get("liquidation_distance_pct", 0.0)
        else:
                ## Fallback: simple calculation
                var price: float = trading_manager.available_symbols.get(current_symbol, {}).get("price", 0.0)
                if price > 0.0 and leverage > 0:
                        var notional := amount * price
                        var margin := notional / leverage
                        var liq_pct := (1.0 / leverage) * 100.0
                        if margin_preview:
                                margin_preview.text = "Required Margin: $%.2f" % margin
                        if liquidation_label:
                                liquidation_label.text = "Liq. Distance: %.1f%%" % liq_pct

## ============================================
## Buy (LONG) button pressed
## ============================================
func _on_buy_pressed() -> void:
        if not trading_manager:
                return

        var amount: float = float(amount_input.text) if amount_input and amount_input.text.is_valid_float() else 0.0
        var leverage: int = int(leverage_slider.value) if leverage_slider else 1

        if amount <= 0.0:
                NotificationManager.send_notification(
                        "Invalid Amount",
                        "Enter a valid trade size",
                        NP.WARNING
                )
                return

        var trade = trading_manager.open_trade(
                current_symbol,
                TradeClass.TradeType.LONG,
                amount,
                leverage
        )

        if trade == null:
                NotificationManager.send_notification(
                        "Trade Failed",
                        "Could not open LONG trade — check margin",
                        NP.WARNING
                )

## ============================================
## Sell (SHORT) button pressed
## ============================================
func _on_sell_pressed() -> void:
        if not trading_manager:
                return

        var amount: float = float(amount_input.text) if amount_input and amount_input.text.is_valid_float() else 0.0
        var leverage: int = int(leverage_slider.value) if leverage_slider else 1

        if amount <= 0.0:
                NotificationManager.send_notification(
                        "Invalid Amount",
                        "Enter a valid trade size",
                        NP.WARNING
                )
                return

        var trade = trading_manager.open_trade(
                current_symbol,
                TradeClass.TradeType.SHORT,
                amount,
                leverage
        )

        if trade == null:
                NotificationManager.send_notification(
                        "Trade Failed",
                        "Could not open SHORT trade — check margin",
                        NP.WARNING
                )

## ============================================
## Full UI refresh
## ============================================
func _refresh_ui() -> void:
        _update_margin_preview()
        if portfolio_manager and portfolio_manager.has_method("get_portfolio_summary"):
                _on_portfolio_updated(portfolio_manager.get_portfolio_summary())

## ============================================
## Back to main menu
## ============================================
func _on_back_pressed() -> void:
        get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
