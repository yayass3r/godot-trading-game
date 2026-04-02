## ============================================
## TradingManager.gd - محرك التداول الرئيسي
## يربط PortfolioManager بـ ProfileManager لفتح وإغلاق الصفقات
## يدعم الرافعة المالية حتى 100x مع حساب دقيق للتصفية
## ============================================
extends Node

const TradeClass = preload("res://scripts/data_models/trade.gd")

## ---- إشارات (Signals) ----
signal trade_opened(trade)
signal trade_closed(trade, pnl: float, reason: String)
signal trade_liquidated(trade, loss: float)
signal error_occurred(message: String)

## ---- مراجع الأنظمة ----
var profile_manager: Node
var portfolio_manager: Node
var data_manager: Node  ## DataManager لجلب الأسعار الحية

## ---- ثوابت التداول ----
const MIN_TRADE_SIZE: float = 0.001     ## أدنى حجم صفقة
const MIN_NOTIONAL_VALUE: float = 10.0  ## أدنى قيمة إجمالية للصفقة $10

## ---- أدوات متاحة للتداول ----
var available_symbols: Dictionary = {
        ## العملات الرقمية
        "BTCUSDT": {"name": "Bitcoin", "type": "crypto", "min_size": 0.0001, "price": 0.0},
        "ETHUSDT": {"name": "Ethereum", "type": "crypto", "min_size": 0.001, "price": 0.0},
        "BNBUSDT": {"name": "BNB", "type": "crypto", "min_size": 0.01, "price": 0.0},
        "SOLUSDT": {"name": "Solana", "type": "crypto", "min_size": 0.1, "price": 0.0},
        "XRPUSDT": {"name": "Ripple", "type": "crypto", "min_size": 1.0, "price": 0.0},
        "ADAUSDT": {"name": "Cardano", "type": "crypto", "min_size": 1.0, "price": 0.0},
        "DOGEUSDT": {"name": "Dogecoin", "type": "crypto", "min_size": 10.0, "price": 0.0},
        ## الأسهم
        "AAPL": {"name": "Apple", "type": "stock", "min_size": 0.01, "price": 0.0},
        "TSLA": {"name": "Tesla", "type": "stock", "min_size": 0.01, "price": 0.0},
        "GOOGL": {"name": "Google", "type": "stock", "min_size": 0.01, "price": 0.0},
        "AMZN": {"name": "Amazon", "type": "stock", "min_size": 0.01, "price": 0.0},
        "MSFT": {"name": "Microsoft", "type": "stock", "min_size": 0.01, "price": 0.0},
}

## ============================================
## _ready() - تهيئة المدير والاتصال بالأنظمة الأخرى
## ============================================
func _ready() -> void:
        ## البحث عن الأنظمة الأساسية
        profile_manager = get_node_or_null("/root/ProfileManager")
        portfolio_manager = get_node_or_null("/root/PortfolioManager")
        data_manager = get_node_or_null("/root/DataManager")
        
        if profile_manager == null:
                push_error("[TradingManager] ❌ ProfileManager غير موجود!")
        if portfolio_manager == null:
                push_error("[TradingManager] ❌ PortfolioManager غير موجود!")
        if data_manager == null:
                push_warning("[TradingManager] ⚠️ DataManager غير موجود - البيانات الحية متوقفة")
        
        ## ربط إشارات PortfolioManager
        if portfolio_manager:
                portfolio_manager.liquidation_executed.connect(_on_liquidation)
        
        print("[TradingManager] ✅ محرك التداول جاهز | أدوات متاحة: %d" % available_symbols.size())

## ============================================
## فتح صفقة جديدة بالرافعة المالية
## هذه هي الوظيفة الرئيسية التي تربط كل الأنظمة
##
## المعلمات:
##   symbol: رمز الأداة (مثال: "BTCUSDT")
##   trade_type: نوع الصفقة (LONG أو SHORT)
##   position_size: حجم المركز بالوحدة
##   leverage: الرافعة المالية (1 - 100)
##   take_profit: سعر جني الأرباح (اختياري)
##   stop_loss: سعر وقف الخسارة (اختياري)
##
## القيمة المعادة: كائن Trade أو null في حال الفشل
## ============================================
func open_trade(
        symbol: String,
        trade_type: int,
        position_size: float,
        leverage: int,
        take_profit: float = -1.0,
        stop_loss: float = -1.0
):
        ## ===== التحقق من صحة المعطيات =====
        if not available_symbols.has(symbol):
                error_occurred.emit("الأداة غير موجودة: %s" % symbol)
                push_error("[TradingManager] ❌ أداة غير موجودة: %s" % symbol)
                return null
        
        var symbol_data: Dictionary = available_symbols[symbol]
        var current_price: float = symbol_data.get("price", 0.0)
        
        if current_price <= 0.0:
                error_occurred.emit("السعر غير متاح للأداة: %s" % symbol)
                push_error("[TradingManager] ❌ سعر غير متاح: %s" % symbol)
                return null
        
        if position_size < symbol_data.get("min_size", MIN_TRADE_SIZE):
                error_occurred.emit("حجم الصفقة أقل من الحد الأدنى")
                return null
        
        ## ===== التحقق من الرافعة المالية =====
        var max_allowed_leverage: int = profile_manager.get_max_leverage() if profile_manager else 1
        if leverage > max_allowed_leverage:
                error_occurred.emit("رافعة مالية غير متاحة. المستوى %d يسمح حتى %dx" % [profile_manager.level, max_allowed_leverage])
                leverage = max_allowed_leverage
        if leverage < 1:
                leverage = 1
        
        ## ===== حساب المبالغ المالية =====
        var notional_value: float = position_size * current_price          ## القيمة الإجمالية
        var margin_required: float = notional_value / leverage             ## الهامش المطلوب
        var trading_fee: float = notional_value * GameConstants.TRADING_FEE_RATE                ## الرسوم
        
        ## التحقق من الحد الأدنى للقيمة الإجمالية
        if notional_value < MIN_NOTIONAL_VALUE:
                error_occurred.emit("القيمة الإجمالية أقل من الحد الأدنى ($%.2f)" % MIN_NOTIONAL_VALUE)
                return null
        
        ## ===== التحقق من الهامش المتاح =====
        if not portfolio_manager.can_open_trade(margin_required + trading_fee):
                error_occurred.emit("هامش غير كافٍ. مطلوب: $%.2f | متاح: $%.2f" % [
                        margin_required + trading_fee, portfolio_manager.free_margin
                ])
                return null
        
        ## ===== إنشاء كائن الصفقة =====
        var trade := TradeClass.new()
        trade.trade_id = _generate_trade_id()
        trade.symbol = symbol
        trade.trade_type = trade_type
        trade.status = TradeClass.TradeStatus.OPEN
        trade.leverage = leverage
        trade.entry_price = current_price
        trade.current_price = current_price
        trade.position_size = position_size
        trade.margin_used = margin_required
        trade.take_profit = take_profit
        trade.stop_loss = stop_loss
        trade.open_time = Time.get_unix_time_from_system()
        trade.fees_paid = trading_fee
        
        ## ===== حساب سعر التصفية =====
        trade.calculate_liquidation_price()
        
        ## ===== خصم الرسوم من الرصيد =====
        if profile_manager:
                profile_manager.balance -= trading_fee
        
        ## ===== إضافة الصفقة إلى المحفظة =====
        if not portfolio_manager.add_trade(trade):
                ## إرجاع الرسوم في حال فشل الإضافة
                if profile_manager:
                        profile_manager.balance += trading_fee
                error_occurred.emit("فشل إضافة الصفقة إلى المحفظة")
                return null
        
        ## ===== إرسال إشعار =====
        trade_opened.emit(trade)
        
        print("[TradingManager] 📈 صفقة مفتوحة: %s | %s | حجم: %.4f | رافعة: %dx | هامش: $%.2f | تصفية: $%.2f" % [
                symbol,
                "LONG" if trade_type == TradeClass.TradeType.LONG else "SHORT",
                position_size,
                leverage,
                margin_required,
                trade.liquidation_price
        ])
        
        return trade

## ============================================
## إغلاق صفقة يدوياً
## ============================================
func close_trade(trade_id: String, reason: String = "يدوي") -> float:
        ## البحث عن الصفقة في المحفظة
        var trade = null
        for t in portfolio_manager.open_trades:
                if t.trade_id == trade_id:
                        trade = t
                        break
        
        if trade == null:
                error_occurred.emit("الصفقة غير موجودة: %s" % trade_id)
                return 0.0
        
        ## إغلاق الصفقة عبر PortfolioManager
        ## هذا سيقوم تلقائياً بـ:
        ## 1. حساب الربح/الخسارة النهائي
        ## 2. تحديث رصيد اللاعب في ProfileManager
        ## 3. تحديث إحصائيات اللاعب والخبرة
        var pnl: float = portfolio_manager.close_trade(trade, reason)
        
        ## إرسال إشعار
        trade_closed.emit(trade, pnl, reason)
        
        return pnl

## ============================================
## إغلاق كل الصفقات المفتوحة لأداة معينة
## ============================================
func close_all_symbol_trades(symbol: String, reason: String = "إغلاق كلي") -> float:
        var total_pnl := 0.0
        var trades_to_close: Array = []
        
        for trade in portfolio_manager.open_trades:
                if trade.symbol == symbol:
                        trades_to_close.append(trade)
        
        for trade in trades_to_close:
                total_pnl += close_trade(trade.trade_id, reason)
        
        return total_pnl

## ============================================
## إغلاق كل الصفقات المفتوحة (طوارئ)
## ============================================
func close_all_trades(reason: String = "طوارئ") -> float:
        var total_pnl := 0.0
        var trades_to_close: Array = []
        trades_to_close.assign(portfolio_manager.open_trades)
        
        for trade in trades_to_close:
                total_pnl += close_trade(trade.trade_id, reason)
        
        return total_pnl

## ============================================
## تعديل أمر جني الأرباح / وقف الخسارة
## ============================================
func modify_trade(trade_id: String, take_profit: float = -1.0, stop_loss: float = -1.0) -> bool:
        for trade in portfolio_manager.open_trades:
                if trade.trade_id == trade_id:
                        if take_profit > 0.0:
                                trade.take_profit = take_profit
                        if stop_loss > 0.0:
                                trade.stop_loss = stop_loss
                        print("[TradingManager] ✏️ تعديل صفقة %s | TP: $%.2f | SL: $%.2f" % [
                                trade.symbol, trade.take_profit, trade.stop_loss
                        ])
                        return true
        return false

## ============================================
## تحديث سعر (يُستدعى من DataManager)
## ============================================
func update_market_price(symbol: String, new_price: float) -> void:
        if available_symbols.has(symbol):
                available_symbols[symbol]["price"] = new_price
                if portfolio_manager:
                        portfolio_manager.update_price(symbol, new_price)

## ============================================
## حساب الهامش المطلوب مسبقاً (للعرض في UI)
## ============================================
func estimate_margin(position_size: float, symbol: String, leverage: int) -> Dictionary:
        if not available_symbols.has(symbol):
                return {"error": "رمز غير موجود"}
        
        var price: float = available_symbols[symbol].get("price", 0.0)
        if price <= 0.0:
                return {"error": "السعر غير متاح"}
        
        var notional_value := position_size * price
        var margin := notional_value / leverage
        var fee := notional_value * GameConstants.TRADING_FEE_RATE
        var liquidation_pct := (1.0 / leverage) * 100.0
        
        return {
                "notional_value": notional_value,
                "margin_required": margin,
                "trading_fee": fee,
                "total_cost": margin + fee,
                "liquidation_distance_pct": liquidation_pct,
                "max_profit_potential": notional_value * 0.10,  ## افتراضي 10% حركة
                "max_loss_potential": margin  ## أسوأ حالة = خسارة كل الهامش
        }

## ============================================
## الحصول على ملخص صفقات مفتوحة لأداة معينة
## ============================================
func get_symbol_exposure(symbol: String) -> Dictionary:
        var long_count := 0
        var short_count := 0
        var long_margin := 0.0
        var short_margin := 0.0
        var long_pnl := 0.0
        var short_pnl := 0.0
        
        for trade in portfolio_manager.open_trades:
                if trade.symbol == symbol:
                        match trade.trade_type:
                                TradeClass.TradeType.LONG:
                                        long_count += 1
                                        long_margin += trade.margin_used
                                        long_pnl += trade.calculate_unrealized_pnl()
                                TradeClass.TradeType.SHORT:
                                        short_count += 1
                                        short_margin += trade.margin_used
                                        short_pnl += trade.calculate_unrealized_pnl()
        
        return {
                "symbol": symbol,
                "long_count": long_count,
                "short_count": short_count,
                "long_margin": long_margin,
                "short_margin": short_margin,
                "net_exposure": long_margin - short_margin,
                "total_pnl": long_pnl + short_pnl
        }

## ============================================
## إنشاء معرّف فريد للصفقة
## ============================================
func _generate_trade_id() -> String:
        return "%s_%d_%d" % [
                Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace(" ", ""),
                Time.get_ticks_msec(),
                randi() % 10000
        ]

## ============================================
## معالجة التصفية
## ============================================
func _on_liquidation(trade, loss_amount: float) -> void:
        trade_liquidated.emit(trade, loss_amount)
        print("[TradingManager] 💥 تصفية صفقة: %s | الخسارة: $%.2f" % [trade.symbol, loss_amount])
