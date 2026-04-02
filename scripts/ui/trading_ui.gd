## ============================================
## TradingUI.gd - واجهة تداول رئيسية
## تتحكم في عرض الأسعار وفتح/إغلاق الصفقات
## ============================================
extends Control

## ---- عقد الواجهة (Node References) ----
@onready var symbol_label: Label = $VBoxContainer/Header/SymbolLabel
@onready var price_label: Label = $VBoxContainer/Header/PriceLabel
@onready var change_label: Label = $VBoxContainer/Header/ChangeLabel
@onready var portfolio_panel: Panel = $VBoxContainer/PortfolioInfo
@onready var balance_label: Label = $PortfolioInfo/BalanceLabel
@onready var equity_label: Label = $PortfolioInfo/EquityLabel
@onready var margin_label: Label = $PortfolioInfo/MarginLabel
@onready var open_trades_list: ItemList = $VBoxContainer/OpenTrades
@onready var trade_panel: Panel = $VBoxContainer/TradePanel
@onready var buy_button: Button = $TradePanel/BuyButton
@onready var sell_button: Button = $TradePanel/SellButton
@onready var leverage_slider: HSlider = $TradePanel/LeverageSlider
@onready var leverage_label: Label = $TradePanel/LeverageLabel
@onready var amount_input: LineEdit = $TradePanel/AmountInput
@onready var margin_preview: Label = $TradePanel/MarginPreview
@onready var liquidation_label: Label = $TradePanel/LiquidationLabel

## ---- حالة الواجهة ----
var current_symbol: String = "BTCUSDT"
var trading_manager: Node
var portfolio_manager: Node
var profile_manager: Node
var data_manager: Node

## ============================================
## التهيئة
## ============================================
func _ready() -> void:
        ## ربط الأنظمة
        trading_manager = get_node_or_null("/root/GameManager/TradingManager")
        portfolio_manager = get_node_or_null("/root/GameManager/PortfolioManager")
        profile_manager = get_node_or_null("/root/GameManager/ProfileManager")
        data_manager = get_node_or_null("/root/GameManager/DataManager")
        
        ## ربط الإشارات
        if trading_manager:
                trading_manager.trade_opened.connect(_on_trade_opened)
                trading_manager.trade_closed.connect(_on_trade_closed)
        if portfolio_manager:
                portfolio_manager.portfolio_updated.connect(_on_portfolio_updated)
                portfolio_manager.margin_call_triggered.connect(_on_margin_call)
        if data_manager:
                data_manager.price_updated.connect(_on_price_updated)
        
        ## ربط أزرار التداول
        if buy_button:
                buy_button.pressed.connect(_on_buy_pressed)
        if sell_button:
                sell_button.pressed.connect(_on_sell_pressed)
        
        ## ربط شريط الرافعة
        if leverage_slider:
                leverage_slider.min_value = 1
                leverage_slider.max_value = profile_manager.get_max_leverage() if profile_manager else 1
                leverage_slider.step = 1
                leverage_slider.value = 1
                leverage_slider.value_changed.connect(_on_leverage_changed)
        
        ## تحديث أولي
        _refresh_ui()

## ============================================
## تحديث واجهة الأسعار
## ============================================
func _on_price_updated(symbol: String, price: float, _timestamp: int) -> void:
        if symbol == current_symbol:
                if price_label:
                        price_label.text = "$%.2f" % price

## ============================================
## تحديث معلومات المحفظة
## ============================================
func _on_portfolio_updated(summary: Dictionary) -> void:
        if balance_label:
                balance_label.text = "💰 الرصيد: $%.2f" % summary.get("balance", 0.0)
        if equity_label:
                equity_label.text = "📊 رأس المال: $%.2f" % summary.get("equity", 0.0)
        if margin_label:
                var margin_pct: float = float(summary.get("margin_usage_pct", 0.0))
                var color := "🟢" if margin_pct < 50 else ("🟡" if margin_pct < 80 else "🔴")
                margin_label.text = "%s الهامش المستخدم: %.1f%%" % [color, margin_pct]

## ============================================
## عند فتح صفقة
## ============================================
func _on_trade_opened(trade: Trade) -> void:
        if open_trades_list:
                var direction := "🟢 BUY" if trade.trade_type == Trade.TradeType.LONG else "🔴 SELL"
                open_trades_list.add_item("%s %s | %.4f @ %dx | $%.2f" % [
                        direction, trade.symbol, trade.position_size, trade.leverage, trade.margin_used
                ])
        _refresh_ui()

## ============================================
## عند إغلاق صفقة
## ============================================
func _on_trade_closed(trade: Trade, pnl: float, reason: String) -> void:
        ## إزالة من القائمة
        if open_trades_list:
                for i in range(open_trades_list.item_count):
                        if trade.symbol in open_trades_list.get_item_text(i):
                                open_trades_list.remove_item(i)
                                break
        
        var emoji := "✅" if pnl > 0 else "❌"
        NotificationManager.send_notification(
                "%s صفقة مُغلقة" % emoji,
                "%s | %s | $%.2f" % [trade.symbol, reason, pnl],
                NotificationPriority.SUCCESS if pnl > 0 else NotificationPriority.WARNING
        )
        _refresh_ui()

## ============================================
## عند نداء الهامش
## ============================================
func _on_margin_call(trade: Trade, free_margin: float) -> void:
        ## هز الهاتف + تنبيه بصري بصري
        NotificationManager.send_notification(
                "🚨 نداء هامش!",
                "صفقة %s | الهامش الحر: $%.2f" % [trade.symbol, free_margin],
                NotificationPriority.HIGH
        )
        
        ## وميض على زر الإغلاق
        if trade_panel:
                var tween := create_tween()
                tween.set_loops(5)
                tween.tween_property(trade_panel, "modulate", Color.RED, 0.3)
                tween.tween_property(trade_panel, "modulate", Color.WHITE, 0.3)

## ============================================
## زر الشراء (LONG)
## ============================================
func _on_buy_pressed() -> void:
        var amount: float = float(amount_input.text) if amount_input.text != "" else 0.0
        var leverage := int(leverage_slider.value) if leverage_slider else 1
        
        if amount <= 0:
                NotificationManager.send_notification(
                        "⚠️ خطأ",
                        "أدخل مبلغاً صحيحاً للتداول",
                        NotificationPriority.WARNING
                )
                return
        
        var trade = trading_manager.open_trade(
                current_symbol,
                Trade.TradeType.LONG,
                amount,
                leverage
        )
        
        if trade == null:
                NotificationManager.send_notification(
                        "❌ فشل",
                        "لم يتم فتح الصفقة - تحقق من الهامش",
                        NotificationPriority.WARNING
                )

## ============================================
## زر البيع (SHORT)
## ============================================
func _on_sell_pressed() -> void:
        var amount: float = float(amount_input.text) if amount_input.text != "" else 0.0
        var leverage := int(leverage_slider.value) if leverage_slider else 1
        
        if amount <= 0:
                return
        
        var trade = trading_manager.open_trade(
                current_symbol,
                Trade.TradeType.SHORT,
                amount,
                leverage
        )

## ============================================
## عند تغيير الرافعة
## ============================================
func _on_leverage_changed(value: float) -> void:
        if leverage_label:
                leverage_label.text = "%dx ⚡" % int(value)
        _update_margin_preview()

## ============================================
## تحديث معاينة الهامش
## ============================================
func _update_margin_preview() -> void:
        if not trading_manager or not amount_input or not margin_preview:
                return
        
        var amount := float(amount_input.text) if not amount_input.text.is_empty() else 0.0
        var leverage := int(leverage_slider.value) if leverage_slider else 1
        
        if amount <= 0:
                margin_preview.text = ""
                liquidation_label.text = ""
                return
        
        var estimate = trading_manager.estimate_margin(amount, current_symbol, leverage)
        margin_preview.text = "هامش مطلوب: $%.2f" % estimate.get("margin_required", 0.0)
        liquidation_label.text = "مسافة التصفية: %.1f%%" % estimate.get("liquidation_distance_pct", 0.0)

## ============================================
## تحديث شامل للواجهة
## ============================================
func _refresh_ui() -> void:
        _update_margin_preview()
        if portfolio_manager:
                _on_portfolio_updated(portfolio_manager.get_portfolio_summary())
