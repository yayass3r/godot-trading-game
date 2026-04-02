## ============================================
## TradingUI.gd - واجهة التداول الرئيسية المحسّنة
## تشمل: أوامر السوق + أوامر الحد + TP/SL + أزرار إغلاق + تحويلات سلسة
## ============================================
extends Control

const TradeClass = preload("res://scripts/data_models/trade.gd")
const LimitOrderClass = preload("res://scripts/data_models/limit_order.gd")
const NP = preload("res://scripts/enums/notification_priority.gd")

## ---- Node References ----
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

## ---- TP/SL Inputs ----
@onready var tp_input: LineEdit = $VBoxContainer/TradePanel/TradeContent/TPSLRow/TPInput
@onready var sl_input: LineEdit = $VBoxContainer/TradePanel/TradeContent/TPSLRow/SLInput
@onready var tp_label: Label = $VBoxContainer/TradePanel/TradeContent/TPSLRow/TPLabel
@onready var sl_label: Label = $VBoxContainer/TradePanel/TradeContent/TPSLRow/SLLabel

## ---- Limit Order Inputs ----
@onready var limit_price_input: LineEdit = $VBoxContainer/LimitOrderPanel/LimitContent/LimitPriceInput
@onready var limit_amount_input: LineEdit = $VBoxContainer/LimitOrderPanel/LimitContent/LimitAmountInput
@onready var limit_tp_input: LineEdit = $VBoxContainer/LimitOrderPanel/LimitContent/LimitTPSLRow/LimitTPInput
@onready var limit_sl_input: LineEdit = $VBoxContainer/LimitOrderPanel/LimitContent/LimitTPSLRow/LimitSLInput
@onready var limit_buy_btn: Button = $VBoxContainer/LimitOrderPanel/LimitContent/LimitButtonRow/LimitBuyBtn
@onready var limit_sell_btn: Button = $VBoxContainer/LimitOrderPanel/LimitContent/LimitButtonRow/LimitSellBtn

## ---- Tabs ----
@onready var market_tab: Button = $VBoxContainer/TradePanel/TabRow/MarketTab
@onready var limit_tab: Button = $VBoxContainer/TradePanel/TabRow/LimitTab

## ---- Open Trades Panel ----
@onready var open_trades_container: VBoxContainer = $VBoxContainer/OpenTradesPanel/OpenTradesContainer
@onready var close_all_btn: Button = $VBoxContainer/OpenTradesPanel/CloseAllBtn

## ---- Pending Orders List ----
@onready var pending_orders_container: VBoxContainer = $VBoxContainer/PendingOrdersPanel/PendingOrdersContainer
@onready var cancel_all_orders_btn: Button = $VBoxContainer/PendingOrdersPanel/CancelAllBtn

## ---- Manager References ----
@onready var trading_manager: Node = get_node_or_null("/root/TradingManager")
@onready var portfolio_manager: Node = get_node_or_null("/root/PortfolioManager")
@onready var profile_manager: Node = get_node_or_null("/root/ProfileManager")
@onready var data_manager: Node = get_node_or_null("/root/DataManager")
@onready var order_manager: Node = get_node_or_null("/root/OrderManager")

## ---- State ----
var current_symbol: String = "BTCUSDT"
var _trade_cards: Dictionary = {}  ## {trade_id: Panel}
var _order_cards: Dictionary = {}  ## {order_id: Panel}
var _current_tab: String = "market"  ## "market" or "limit"

## ---- Smooth Transitions ----
var _price_tween: SceneTreeTween = null
var _last_price: float = 0.0
var _refresh_timer: Timer

## ============================================
## _ready()
## ============================================
func _ready() -> void:
	_connect_manager_signals()
	_connect_ui_signals()
	_populate_symbol_options()
	_refresh_ui()
	_switch_tab("market")

	## مؤقت لتحديث الصفقات المفتوحة
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1.0
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_refresh_open_trades_display)
	add_child(_refresh_timer)

func _connect_manager_signals() -> void:
	if data_manager:
		data_manager.price_updated.connect(_on_price_updated)
	if trading_manager:
		trading_manager.trade_opened.connect(_on_trade_opened)
		trading_manager.trade_closed.connect(_on_trade_closed)
	if portfolio_manager:
		portfolio_manager.portfolio_updated.connect(_on_portfolio_updated)
		portfolio_manager.margin_call_triggered.connect(_on_margin_call)
	if order_manager:
		order_manager.orders_updated.connect(_on_orders_updated)
		order_manager.order_filled.connect(_on_order_filled)
		order_manager.order_cancelled.connect(_on_order_cancelled)

func _connect_ui_signals() -> void:
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	if buy_button:
		buy_button.pressed.connect(_on_buy_pressed)
	if sell_button:
		sell_button.pressed.connect(_on_sell_pressed)
	if limit_buy_btn:
		limit_buy_btn.pressed.connect(_on_limit_buy_pressed)
	if limit_sell_btn:
		limit_sell_btn.pressed.connect(_on_limit_sell_pressed)
	if close_all_btn:
		close_all_btn.pressed.connect(_on_close_all_pressed)
	if cancel_all_orders_btn:
		cancel_all_orders_btn.pressed.connect(_on_cancel_all_orders_pressed)
	if market_tab:
		market_tab.pressed.connect(_on_market_tab_pressed)
	if limit_tab:
		limit_tab.pressed.connect(_on_limit_tab_pressed)
	if leverage_slider:
		leverage_slider.min_value = 1
		leverage_slider.max_value = profile_manager.get_max_leverage() if profile_manager else 1
		leverage_slider.step = 1
		leverage_slider.value = 1
		leverage_slider.value_changed.connect(_on_leverage_changed)
	if amount_input:
		amount_input.text_changed.connect(_on_amount_changed)

## ============================================
## تبديل التبويبات (سوق / حد)
## ============================================
func _switch_tab(tab: String) -> void:
	_current_tab = tab

	## إخفاء/إظهار الأقسام
	var limit_panel = get_node_or_null("VBoxContainer/LimitOrderPanel")
	if limit_panel:
		limit_panel.visible = (tab == "limit")

	## تحديث ألوان التبويبات
	if market_tab:
		market_tab.add_theme_color_override("font_color", Color.WHITE if tab == "market" else Color(0.5, 0.5, 0.6))
	if limit_tab:
		limit_tab.add_theme_color_override("font_color", Color.WHITE if tab == "limit" else Color(0.5, 0.5, 0.6))

func _on_market_tab_pressed() -> void:
	_switch_tab("market")

func _on_limit_tab_pressed() -> void:
	_switch_tab("limit")

## ============================================
## Populate symbol dropdown
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
## تحديث الأسعار مع تحويلات سلسة
## ============================================
func _on_price_updated(symbol: String, price: float, _timestamp: int) -> void:
	if symbol != current_symbol or not price_label:
		return

	## تحريك سعر مرئي
	_animate_price_change(price)

func _animate_price_change(new_price: float) -> void:
	if not price_label:
		return

	if _price_tween and _price_tween.is_running():
		_price_tween.kill()

	## تحديد لون التغيير
	var change_color := Color.WHITE
	if _last_price > 0:
		change_color = COLOR_POSITIVE if new_price >= _last_price else COLOR_NEGATIVE

	price_label.text = "$%.2f" % new_price
	price_label.add_theme_color_override("font_color", change_color)

	## Tween لإعادة اللون الأبيض تدريجياً
	_price_tween = create_tween()
	_price_tween.set_ease(Tween.EASE_OUT)
	_price_tween.set_trans(Tween.TRANS_SINE)
	_price_tween.tween_property(price_label, "self_modulate", Color.WHITE, 0.8)

	_last_price = new_price

## ============================================
## Portfolio updates
## ============================================
func _on_portfolio_updated(summary: Dictionary) -> void:
	if balance_label:
		balance_label.text = "💰 Balance: $%.2f" % summary.get("balance", 0.0)
	if equity_label:
		equity_label.text = "📊 Equity: $%.2f" % summary.get("equity", 0.0)
	if margin_label:
		var pct: float = float(summary.get("margin_usage_pct", 0.0))
		var color := "🟢" if pct < 50 else ("🟡" if pct < 80 else "🔴")
		margin_label.text = "%s Margin: %.1f%% ($%.2f)" % [color, pct, summary.get("margin_used", 0.0)]

## ============================================
## Trade opened — create card
## ============================================
func _on_trade_opened(trade) -> void:
	_create_trade_card(trade)
	_refresh_ui()

## ============================================
## Trade closed — remove card
## ============================================
func _on_trade_closed(trade, pnl: float, reason: String) -> void:
	_remove_trade_card(trade)
	_refresh_ui()

	NotificationManager.send_notification(
		"Trade Closed",
		"%s %s | PnL: $%.2f | %s" % [
			trade.symbol,
			"LONG" if trade.trade_type == TradeClass.TradeType.LONG else "SHORT",
			pnl, reason
		],
		NP.SUCCESS if pnl >= 0 else NP.WARNING
	)

## ============================================
## إنشاء بطاقة صفقة مفتوحة
## ============================================
func _create_trade_card(trade) -> void:
	if not open_trades_container:
		return

	var panel := PanelContainer.new()
	panel.name = "TradeCard_%s" % trade.trade_id

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	## صف الأعلى: الرمز + الاتجاه + PnL
	var top_row := HBoxContainer.new()
	var dir_color := "#2ED470" if trade.trade_type == TradeClass.TradeType.LONG else "#E54F45"
	var dir_text := "🟢 LONG" if trade.trade_type == TradeClass.TradeType.LONG else "🔴 SHORT"

	var sym_lbl := Label.new()
	sym_lbl.text = "%s %s | %dx" % [trade.symbol, dir_text, trade.leverage]
	sym_lbl.add_theme_color_override("font_color", Color(dir_color))
	top_row.add_child(sym_lbl)

	var pnl_lbl := Label.new()
	pnl_lbl.name = "PnlLabel"
	pnl_lbl.text = "PnL: $0.00"
	pnl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pnl_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(pnl_lbl)
	vbox.add_child(top_row)

	## صف التفاصيل
	var info_lbl := Label.new()
	info_lbl.name = "InfoLabel"
	info_lbl.text = "Entry: $%.2f | Size: %.4f | Margin: $%.2f" % [
		trade.entry_price, trade.position_size, trade.margin_used
	]
	info_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(info_lbl)

	## صف TP/SL
	var tp_sl_row := HBoxContainer.new()
	var tp_sl_text := ""
	if trade.take_profit > 0:
		tp_sl_text += "TP: $%.2f  " % trade.take_profit
	if trade.stop_loss > 0:
		tp_sl_text += "SL: $%.2f  " % trade.stop_loss
	if trade.liquidation_price > 0:
		tp_sl_text += "Liq: $%.2f" % trade.liquidation_price
	if tp_sl_text == "":
		tp_sl_text = "No TP/SL set"
	var tp_sl_lbl := Label.new()
	tp_sl_lbl.text = tp_sl_text
	tp_sl_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	tp_sl_lbl.add_theme_font_size_override("font_size", 12)
	tp_sl_row.add_child(tp_sl_lbl)

	## زر إغلاق
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(32, 24)
	close_btn.tooltip_text = "Close trade"
	close_btn.pressed.connect(_on_close_trade_pressed.bind(trade.trade_id))
	tp_sl_row.add_child(close_btn)
	vbox.add_child(tp_sl_row)

	## أزرار TP/SL سريعة
	var action_row := HBoxContainer.new()

	var set_tp_btn := Button.new()
	set_tp_btn.text = "Set TP"
	set_tp_btn.pressed.connect(_on_set_tp_for_trade.bind(trade.trade_id))
	action_row.add_child(set_tp_btn)

	var set_sl_btn := Button.new()
	set_sl_btn.text = "Set SL"
	set_sl_btn.pressed.connect(_on_set_sl_for_trade.bind(trade.trade_id))
	action_row.add_child(set_sl_btn)

	vbox.add_child(action_row)

	open_trades_container.add_child(panel)
	_trade_cards[trade.trade_id] = panel

## ============================================
## إزالة بطاقة صفقة
## ============================================
func _remove_trade_card(trade) -> void:
	if _trade_cards.has(trade.trade_id):
		var card = _trade_cards[trade.trade_id]
		if is_instance_valid(card):
			card.queue_free()
		_trade_cards.erase(trade.trade_id)

## ============================================
## تحديث عرض الصفقات المفتوحة (كل ثانية)
## ============================================
func _refresh_open_trades_display() -> void:
	if not portfolio_manager:
		return

	for trade in portfolio_manager.open_trades:
		if not _trade_cards.has(trade.trade_id):
			_create_trade_card(trade)
			continue

		var card: PanelContainer = _trade_cards[trade.trade_id]
		if not is_instance_valid(card):
			continue

		## تحديث PnL
		var pnl = trade.calculate_unrealized_pnl()
		var pnl_lbl = card.get_node_or_null("VBoxContainer/HBoxContainer/PnlLabel")
		if pnl_lbl:
			var sign := "+" if pnl >= 0 else ""
			pnl_lbl.text = "%s$%.2f (%.1f%%)" % [sign, pnl, trade.pnl_percentage]
			pnl_lbl.add_theme_color_override("font_color",
				Color(0.14, 0.83, 0.44) if pnl >= 0 else Color(0.9, 0.31, 0.27)
			)

	## إزالة بطاقات الصفقات غير الموجودة
	var active_ids: Array = []
	for trade in portfolio_manager.open_trades:
		active_ids.append(trade.trade_id)
	for tid in _trade_cards.keys():
		if tid not in active_ids:
			_remove_trade_card_by_id(tid)

func _remove_trade_card_by_id(trade_id: String) -> void:
	if _trade_cards.has(trade_id):
		var card = _trade_cards[trade_id]
		if is_instance_valid(card):
			card.queue_free()
		_trade_cards.erase(trade_id)

## ============================================
## إغلاق صفقة
## ============================================
func _on_close_trade_pressed(trade_id: String) -> void:
	if trading_manager:
		var pnl := trading_manager.close_trade(trade_id, "يدوي")

## ============================================
## تعيين TP لصفقة (يستخدم سعر +5% أو -5% تلقائياً)
## ============================================
func _on_set_tp_for_trade(trade_id: String) -> void:
	if not trading_manager or not portfolio_manager:
		return
	var price: float = 0.0
	for trade in portfolio_manager.open_trades:
		if trade.trade_id == trade_id:
			price = trade.current_price
			if price <= 0:
				price = trade.entry_price
			match trade.trade_type:
				TradeClass.TradeType.LONG:
					trading_manager.modify_trade(trade_id, take_profit = price * 1.05)
				TradeClass.TradeType.SHORT:
					trading_manager.modify_trade(trade_id, take_profit = price * 0.95)
			break

## ============================================
## تعيين SL لصفقة
## ============================================
func _on_set_sl_for_trade(trade_id: String) -> void:
	if not trading_manager or not portfolio_manager:
		return
	var price: float = 0.0
	for trade in portfolio_manager.open_trades:
		if trade.trade_id == trade_id:
			price = trade.current_price
			if price <= 0:
				price = trade.entry_price
			match trade.trade_type:
				TradeClass.TradeType.LONG:
					trading_manager.modify_trade(trade_id, stop_loss = price * 0.95)
				TradeClass.TradeType.SHORT:
					trading_manager.modify_trade(trade_id, stop_loss = price * 1.05)
			break

## ============================================
## إغلاق كل الصفقات
## ============================================
func _on_close_all_pressed() -> void:
	if trading_manager:
		trading_manager.close_all_trades()

## ============================================
## === أوامر الحد (Limit Orders) ===
## ============================================

func _on_limit_buy_pressed() -> void:
	_submit_limit_order(LimitOrderClass.OrderSide.BUY)

func _on_limit_sell_pressed() -> void:
	_submit_limit_order(LimitOrderClass.OrderSide.SELL)

func _submit_limit_order(side: int) -> void:
	if not order_manager:
		return

	var price_str := limit_price_input.text if limit_price_input else ""
	var amount_str := limit_amount_input.text if limit_amount_input else ""
	var tp_str := limit_tp_input.text if limit_tp_input else ""
	var sl_str := limit_sl_input.text if limit_sl_input else ""

	var price := float(price_str) if price_str.is_valid_float() else 0.0
	var amount := float(amount_str) if amount_str.is_valid_float() else 0.0
	var tp := float(tp_str) if tp_str.is_valid_float() else -1.0
	var sl := float(sl_str) if sl_str.is_valid_float() else -1.0

	if price <= 0:
		NotificationManager.send_notification("Invalid Price", "Enter a valid limit price", NP.WARNING)
		return
	if amount <= 0:
		NotificationManager.send_notification("Invalid Amount", "Enter a valid amount", NP.WARNING)
		return

	var leverage := int(leverage_slider.value) if leverage_slider else 1
	var result := order_manager.create_limit_order(
		current_symbol, side, price, amount, leverage, tp, sl
	)

	if not result.get("success", false):
		NotificationManager.send_notification("Order Failed", result.get("error", "Unknown error"), NP.WARNING)
	else:
		var side_str := "Buy Limit" if side == LimitOrderClass.OrderSide.BUY else "Sell Limit"
		NotificationManager.send_notification(
			"Order Created",
			"%s %s @ $%.2f" % [side_str, current_symbol, price],
			NP.SUCCESS
		)

## ============================================
## تحديث عرض الأوامر المعلقة
## ============================================
func _on_orders_updated() -> void:
	_refresh_pending_orders_display()

func _on_order_filled(order, _trade) -> void:
	_refresh_pending_orders_display()
	var side_str := order.to_dictionary().get("side", "?")
	NotificationManager.send_notification(
		"Order Filled",
		"%s %s @ $%.2f" % [side_str, order.symbol, order.filled_price],
		NP.SUCCESS
	)

func _on_order_cancelled(order) -> void:
	_refresh_pending_orders_display()

func _refresh_pending_orders_display() -> void:
	if not pending_orders_container or not order_manager:
		return

	## مسح البطاقات القديمة
	for child in pending_orders_container.get_children():
		child.queue_free()
	_order_cards.clear()

	var pending := order_manager.get_all_pending_orders()
	for order_data in pending:
		_create_order_card(order_data)

func _create_order_card(order_data: Dictionary) -> void:
	if not pending_orders_container:
		return

	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var side_str: String = order_data.get("side", "?")
	var is_buy := side_str == "BUY"
	var type_name: String = order_data.get("type_name", "LIMIT")

	## صف الأعلى
	var top_row := HBoxContainer.new()
	var desc_lbl := Label.new()
	desc_lbl.text = "%s %s %s @ $%.2f" % [type_name, side_str, order_data.get("symbol", ""), order_data.get("trigger_price", 0.0)]
	desc_lbl.add_theme_color_override("font_color", Color(0.14, 0.83, 0.44) if is_buy else Color(0.9, 0.31, 0.27))
	top_row.add_child(desc_lbl)

	## زر إلغاء
	var cancel_btn := Button.new()
	cancel_btn.text = "✕"
	cancel_btn.custom_minimum_size = Vector2(28, 22)
	cancel_btn.pressed.connect(_on_cancel_order_pressed.bind(order_data.get("order_id", "")))
	top_row.add_child(cancel_btn)
	vbox.add_child(top_row)

	## صف التفاصيل
	var detail_lbl := Label.new()
	detail_lbl.text = "Size: %.4f | %dx" % [order_data.get("position_size", 0.0), order_data.get("leverage", 1)]
	detail_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(detail_lbl)

	pending_orders_container.add_child(panel)

func _on_cancel_order_pressed(order_id: String) -> void:
	if order_manager:
		order_manager.cancel_order(order_id)

func _on_cancel_all_orders_pressed() -> void:
	if order_manager:
		var count := order_manager.cancel_all_orders()
		NotificationManager.send_notification("Orders Cancelled", "%d orders cancelled" % count, NP.INFO)

## ============================================
## Margin call warning
## ============================================
func _on_margin_call(_trade, free_margin: float) -> void:
	NotificationManager.send_notification(
		"⚠️ Margin Call!",
		"Free margin: $%.2f" % free_margin,
		NP.HIGH
	)

## ============================================
## Leverage & Amount
## ============================================
func _on_leverage_changed(value: float) -> void:
	if leverage_display:
		leverage_display.text = "Leverage: %.0fx" % value
	_update_margin_preview()

func _on_amount_changed(_new_text: String) -> void:
	_update_margin_preview()

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

## ============================================
## Buy/Sell Market (مع TP/SL)
## ============================================
func _on_buy_pressed() -> void:
	_submit_market_trade(TradeClass.TradeType.LONG)

func _on_sell_pressed() -> void:
	_submit_market_trade(TradeClass.TradeType.SHORT)

func _submit_market_trade(trade_type: int) -> void:
	if not trading_manager:
		return

	var amount: float = float(amount_input.text) if amount_input and amount_input.text.is_valid_float() else 0.0
	var leverage: int = int(leverage_slider.value) if leverage_slider else 1

	if amount <= 0.0:
		NotificationManager.send_notification("Invalid Amount", "Enter a valid trade size", NP.WARNING)
		return

	## قراءة TP/SL
	var tp := -1.0
	var sl := -1.0
	if tp_input and tp_input.text.is_valid_float() and float(tp_input.text) > 0:
		tp = float(tp_input.text)
	if sl_input and sl_input.text.is_valid_float() and float(sl_input.text) > 0:
		sl = float(sl_input.text)

	var trade = trading_manager.open_trade(current_symbol, trade_type, amount, leverage, tp, sl)

	if trade == null:
		NotificationManager.send_notification(
			"Trade Failed",
			"Could not open trade — check margin",
			NP.WARNING
		)
	else:
		var dir := "LONG" if trade_type == TradeClass.TradeType.LONG else "SHORT"
		var msg := "%s %s | %dx | Margin: $%.2f" % [dir, current_symbol, leverage, trade.margin_used]
		if tp > 0:
			msg += " | TP: $%.2f" % tp
		if sl > 0:
			msg += " | SL: $%.2f" % sl
		NotificationManager.send_notification("Trade Opened", msg, NP.SUCCESS)

## ============================================
## Full UI refresh
## ============================================
func _refresh_ui() -> void:
	_update_margin_preview()
	if portfolio_manager and portfolio_manager.has_method("get_portfolio_summary"):
		_on_portfolio_updated(portfolio_manager.get_portfolio_summary())
	_refresh_open_trades_display()
	_refresh_pending_orders_display()

## ============================================
## Back to main menu
## ============================================
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
