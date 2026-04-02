## ============================================
## PortfolioManager.gd - مدير المحفظة والهامش
## يتعقب الرصيد الكلي، الهامش المتاح، والصفقات المفتوحة
## ============================================
extends Node

const TradeClass = preload("res://scripts/data_models/trade.gd")
const NP = preload("res://scripts/enums/notification_priority.gd")

## ---- إشارات (Signals) ----
signal portfolio_updated(summary: Dictionary)
signal margin_warning(free_margin: float, used_margin_pct: float)
signal margin_call_triggered(trade, free_margin: float)
signal liquidation_executed(trade, loss_amount: float)

## ---- ثوابت الهامش ----
const MARGIN_CALL_THRESHOLD: float = 0.50    ## تنبيه عند استخدام 50% من الهامش
const STOP_OUT_THRESHOLD: float = 0.30        ## إيقاف عند استخدام 70% من الهامش
const MAX_PORTFOLIO_RISK: float = 0.80        ## أقصى مخاطرة للمحفظة 80%

## ---- الصفقات المفتوحة والمغلقة ----
var open_trades: Array = []
var closed_trades: Array = []

## ---- مرجع إلى ProfileManager ----
var profile_manager: Node

## ---- متغيرات الهامش ----
var total_margin_used: float = 0.0 :
        get:
                ## إعادة حساب إجمالي الهامش المستخدم من الصفقات المفتوحة
                var total := 0.0
                for trade in open_trades:
                        total += trade.margin_used
                return total

var unrealized_pnl: float = 0.0 :
        get:
                ## إعادة حساب الربح/الخسارة اللحظي لكل الصفقات المفتوحة
                var total := 0.0
                for trade in open_trades:
                        total += trade.calculate_unrealized_pnl()
                return total

var equity: float = 0.0 :
        get:
                ## رأس المال = الرصيد + الأرباح/الخسائر غير المحققة
                return profile_manager.balance + unrealized_pnl if profile_manager else 0.0

var free_margin: float = 0.0 :
        get:
                ## الهامش الحر = رأس المال - الهامش المستخدم
                return equity - total_margin_used

var margin_level: float = 0.0 :
        get:
                ## مستوى الهامش % = (رأس المال / الهامش المستخدم) × 100
                if total_margin_used <= 0.0:
                        return 999.99
                return (equity / total_margin_used) * 100.0

## ============================================
## التهيئة
## ============================================
func _ready() -> void:
        profile_manager = get_node_or_null("/root/ProfileManager")
        if profile_manager == null:
                push_error("[PortfolioManager] ❌ لم يتم العثور على ProfileManager!")

## ============================================
## فتح صفقة جديدة (يُستدعى من TradingManager)
## ============================================
func can_open_trade(margin_required: float) -> bool:
        if profile_manager == null:
                return false
        
        ## التحقق من وجود هامش كافٍ
        if margin_required > free_margin:
                print("[PortfolioManager] ⚠️ هامش غير كافٍ. مطلوب: $%.2f | متاح: $%.2f" % [margin_required, free_margin])
                return false
        
        ## التحقق من عدم تجاوز الحد الأقصى للمخاطرة
        var risk_pct := total_margin_used / equity if equity > 0 else 0.0
        if risk_pct >= MAX_PORTFOLIO_RISK:
                print("[PortfolioManager] ⚠️ تم بلوغ الحد الأقصى للمخاطرة (%.0f%%)" % (MAX_PORTFOLIO_RISK * 100))
                return false
        
        ## التحقق من عدد الصفقات المفتوحة (حد أقصى 20)
        if open_trades.size() >= 20:
                print("[PortfolioManager] ⚠️ الحد الأقصى للصفقات المفتوحة (20)")
                return false
        
        return true

## ============================================
## إضافة صفقة مفتوحة إلى المحفظة
## ============================================
func add_trade(trade) -> bool:
        if not can_open_trade(trade.margin_used):
                return false
        
        open_trades.append(trade)
        _emit_portfolio_update()
        print("[PortfolioManager] 📈 صفقة جديدة مفتوحة: %s | الهامش: $%.2f" % [trade.symbol, trade.margin_used])
        return true

## ============================================
## إزالة صفقة من المحفظة (عند الإغلاق)
## ============================================
func remove_trade(trade) -> void:
        var idx := open_trades.find(trade)
        if idx >= 0:
                open_trades.remove_at(idx)
                closed_trades.append(trade)
                _emit_portfolio_update()
                print("[PortfolioManager] 📉 صفقة مُغلقة: %s | PnL: $%.2f" % [trade.symbol, trade.pnl])

## ============================================
## تحديث سعر أداة معينة لكل الصفقات المفتوحة
## تُستدعى من DataManager عند وصول سعر جديد
## ============================================
func update_price(symbol: String, new_price: float) -> void:
        var needs_check := false
        
        for trade in open_trades:
                if trade.symbol == symbol:
                        trade.current_price = new_price
                        needs_check = true
        
        if needs_check:
                _check_margin_conditions()
                _check_take_profit_stop_loss()
                _emit_portfolio_update()

## ============================================
## فحص شروط الهامش (نداء الهامش والتصفية)
## ============================================
func _check_margin_conditions() -> void:
        if profile_manager == null or open_trades.is_empty():
                return
        
        var current_margin_level := margin_level
        var used_margin_pct := (total_margin_used / equity) if equity > 0 else 0.0
        
        ## تنبيه عند اقتراب الهامش من الحد
        if used_margin_pct >= MARGIN_CALL_THRESHOLD:
                margin_warning.emit(free_margin, used_margin_pct)
                
                ## إرسال إشعار يهز الهاتف
                NotificationManager.send_notification(
                        "⚠️ نداء الهامش",
                        "مستوى الهامش: %.1f%% | الهامش الحر: $%.2f\nاحذر من التصفية!" % [current_margin_level, free_margin],
                        NP.HIGH
                )
        
        ## تنبيه نداء الهامش للصفقات المهددة
        for trade in open_trades:
                if trade.is_near_liquidation(0.25) and trade.status != TradeClass.TradeStatus.MARGIN_CALL:
                        trade.status = TradeClass.TradeStatus.MARGIN_CALL
                        trade.margin_call_time = Time.get_unix_time_from_system()
                        margin_call_triggered.emit(trade, free_margin)
                        print("[PortfolioManager] 🚨 نداء هامش! صفقة %s @ رافعة %dx" % [trade.symbol, trade.leverage])
                
                ## تنفيذ التصفية إذا لزم الأمر
                if trade.is_liquidated():
                        _execute_liquidation(trade)

## ============================================
## فحص أوامر جني الأرباح ووقف الخسارة
## ============================================
func _check_take_profit_stop_loss() -> void:
        var trades_to_close: Array = []
        
        for trade in open_trades:
                var should_close := false
                
                ## جني الأرباح (يُتحقق أولاً - له الأولوية)
                if trade.take_profit > 0.0:
                        match trade.trade_type:
                                TradeClass.TradeType.LONG:
                                        should_close = trade.current_price >= trade.take_profit
                                TradeClass.TradeType.SHORT:
                                        should_close = trade.current_price <= trade.take_profit
                
                ## وقف الخسارة (يُتحقق فقط إذا لم يُثار جني الأرباح)
                if not should_close and trade.stop_loss > 0.0:
                        match trade.trade_type:
                                TradeClass.TradeType.LONG:
                                        should_close = trade.current_price <= trade.stop_loss
                                TradeClass.TradeType.SHORT:
                                        should_close = trade.current_price >= trade.stop_loss
                
                if should_close:
                        trades_to_close.append(trade)
        
        for trade in trades_to_close:
                close_trade(trade, "TP/SL تلقائي")

## ============================================
## إغلاق صفقة يدوياً أو تلقائياً
## ============================================
func close_trade(trade, reason: String = "يدوي") -> float:
        if trade not in open_trades:
                return 0.0
        
        ## حساب الربح/الخسارة النهائي
        trade.current_price = trade.entry_price if trade.current_price <= 0 else trade.current_price
        trade.exit_price = trade.current_price
        trade.calculate_unrealized_pnl()
        
        ## Opening fee was already deducted in TradingManager.open_trade()
        ## Do NOT deduct fees again here — just use raw PnL.
        ## Keep the opening fee record that was stored on the trade at open.
        
        ## تحديث حالة الصفقة
        trade.close_time = Time.get_unix_time_from_system()
        trade.status = TradeClass.TradeStatus.CLOSED
        
        ## تحديث رصيد اللاعب عبر ProfileManager
        ## Return margin + add PnL (opening fee already paid, no double-deduction)
        if profile_manager:
                profile_manager.balance += trade.margin_used + trade.pnl
                profile_manager.update_trade_stats({
                        "pnl": trade.pnl,
                        "fees": trade.fees_paid,
                        "volume": trade.position_size * trade.entry_price * trade.leverage,
                        "leverage": trade.leverage,
                        "symbol": trade.symbol
                })
        
        ## إزالة من الصفقات المفتوحة
        remove_trade(trade)
        
        print("[PortfolioManager] ✅ صفقة مُغلقة [%s]: %s | الربح: $%.2f | السبب: %s" % [
                reason, trade.symbol, trade.pnl, reason
        ])
        
        return trade.pnl

## ============================================
## تنفيذ التصفية (إغلاق قسري بخسارة)
## ============================================
func _execute_liquidation(trade) -> void:
        trade.status = TradeClass.TradeStatus.LIQUIDATED
        trade.close_time = Time.get_unix_time_from_system()
        trade.exit_price = trade.liquidation_price
        
        ## خسارة التصفية = إجمالي الهامش المستخدم
        trade.pnl = -trade.margin_used
        trade.fees_paid = trade.margin_used * 0.05  ## رسوم تصفية إضافية 5%
        trade.pnl -= trade.fees_paid
        
        ## تحديث الرصيد
        if profile_manager:
                profile_manager.balance += trade.pnl
                profile_manager.update_trade_stats({
                        "pnl": trade.pnl,
                        "fees": trade.fees_paid,
                        "volume": trade.position_size * trade.entry_price * trade.leverage,
                        "leverage": trade.leverage,
                        "symbol": trade.symbol
                })
        
        remove_trade(trade)
        liquidation_executed.emit(trade, trade.pnl)
        
        ## إشعار هز الهاتف
        NotificationManager.send_notification(
                "💥 تمت التصفية!",
                "صفقة %s @ رافعة %dx تمت تصفيتها!\nالخسارة: $%.2f" % [trade.symbol, trade.leverage, trade.pnl],
                NP.CRITICAL
        )
        
        print("[PortfolioManager] 💥 تصفية! صفقة %s | الخسارة: $%.2f" % [trade.symbol, trade.pnl])

## ============================================
## إرسال تحديث حالة المحفظة
## ============================================
func _emit_portfolio_update() -> void:
        var summary := get_portfolio_summary()
        portfolio_updated.emit(summary)

## ============================================
## الحصول على ملخص المحفظة الكامل
## ============================================
func get_portfolio_summary() -> Dictionary:
        return {
                "balance": profile_manager.balance if profile_manager else 0.0,
                "equity": equity,
                "free_margin": free_margin,
                "margin_used": total_margin_used,
                "margin_level": margin_level,
                "unrealized_pnl": unrealized_pnl,
                "open_trades_count": open_trades.size(),
                "closed_trades_count": closed_trades.size(),
                "open_trades": _get_trades_data(open_trades),
                "margin_usage_pct": (total_margin_used / equity * 100.0) if equity > 0 else 0.0
        }

## ============================================
## تحويل الصفقات إلى مصفوفة قواميس
## ============================================
func _get_trades_data(trades: Array) -> Array[Dictionary]:
        var result: Array[Dictionary] = []
        for trade in trades:
                result.append(trade.to_dictionary())
        return result

## ============================================
## حفظ المحفظة
## ============================================
func save_portfolio() -> void:
        var data := {
                "closed_trades": _get_trades_data(closed_trades)
        }
        var save_path := "user://portfolio_data.json"
        var file := FileAccess.open(save_path, FileAccess.WRITE)
        if file:
                file.store_string(JSON.stringify(data, "\t"))
                file.close()

## ============================================
## إعادة تعيين المحفظة — إغلاق كل الصفقات المفتوحة
## ============================================
func reset_portfolio() -> void:
        ## إزالة جميع الصفقات المفتوحة بدون تحديث الرصيد
        for trade in open_trades:
                trade.status = TradeClass.TradeStatus.CLOSED
                trade.close_time = Time.get_unix_time_from_system()
        open_trades.clear()
        closed_trades.clear()
        _emit_portfolio_update()
        save_portfolio()
        print("[PortfolioManager] 🔄 تم إعادة تعيين المحفظة")
