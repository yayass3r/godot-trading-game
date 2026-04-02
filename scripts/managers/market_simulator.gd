## ============================================
## MarketSimulator.gd - محاكي حركة السوق الواقعية
## يولّد تقلبات أسعار واقعية تحاكي السوق الحقيقي
## ============================================
extends Node
class_name MarketSimulator

const NP = preload("res://scripts/enums/notification_priority.gd")

## ---- إشارات ----
signal price_tick(symbol: String, price: float, timestamp: int)
signal trend_changed(symbol: String, new_trend: TrendType, strength: float)

## ---- أنواع الاتجاهات ----
enum TrendType {
        BULLISH,    ## صاعد
        BEARISH,    ## هابط
        SIDEWAYS    ## عرضي
}

## ---- ثوابت التقلب ----
## كل عملة لها تقلب مختلف (ATR - Average True Range)
const VOLATILITY_PROFILE: Dictionary = {
        "BTCUSDT": {"base_volatility": 0.015, "trend_strength": 0.001, "mean_reversion": 0.002},
        "ETHUSDT": {"base_volatility": 0.020, "trend_strength": 0.0015, "mean_reversion": 0.003},
        "BNBUSDT": {"base_volatility": 0.018, "trend_strength": 0.0012, "mean_reversion": 0.0025},
        "SOLUSDT": {"base_volatility": 0.035, "trend_strength": 0.002, "mean_reversion": 0.004},
        "XRPUSDT": {"base_volatility": 0.025, "trend_strength": 0.001, "mean_reversion": 0.003},
        "DOGEUSDT": {"base_volatility": 0.045, "trend_strength": 0.0025, "mean_reversion": 0.005},
        "ADAUSDT": {"base_volatility": 0.030, "trend_strength": 0.0012, "mean_reversion": 0.003},
}

## ---- حالة السوق ----
var symbol_prices: Dictionary = {}      ## {symbol: current_price}
var symbol_trends: Dictionary = {}     ## {symbol: {type, strength, duration}}
var symbol_history: Dictionary = {}    ## {symbol: [{price, volume, time}]}
var market_hours_active: bool = true   ## ساعات السوق
var news_events: Array[Dictionary] = []

## ---- مؤقتات ----
var _tick_timer: Timer
var _trend_timer: Timer
var _news_timer: Timer

## ============================================
## التهيئة
## ============================================
func _ready() -> void:
        ## مؤقت تقلبات الأسعار (كل ثانية)
        _tick_timer = Timer.new()
        _tick_timer.wait_time = 1.0
        _tick_timer.autostart = true
        _tick_timer.timeout.connect(_on_tick)
        add_child(_tick_timer)
        
        ## مؤقت تغيير الاتجاهات (كل 30-120 ثانية)
        _trend_timer = Timer.new()
        _trend_timer.wait_time = randf_range(30.0, 120.0)
        _trend_timer.autostart = true
        _trend_timer.timeout.connect(_on_trend_change)
        add_child(_trend_timer)
        
        ## مؤقت الأحداث الإخبارية العشوائية
        _news_timer = Timer.new()
        _news_timer.wait_time = randf_range(60.0, 300.0)
        _news_timer.autostart = true
        _news_timer.timeout.connect(_on_random_news)
        add_child(_news_timer)

## ============================================
## تسجيل رمز جديد في المحاكي
## ============================================
func register_symbol(symbol: String, initial_price: float) -> void:
        symbol_prices[symbol] = initial_price
        symbol_trends[symbol] = {
                "type": TrendType.SIDEWAYS,
                "strength": 0.0,
                "duration": 0,
                "max_duration": randi_range(50, 200)
        }
        symbol_history[symbol] = []

## ============================================
## ضبط السعر الابتدائي من API
## ============================================
func set_real_price(symbol: String, price: float) -> void:
        if not symbol_prices.has(symbol):
                register_symbol(symbol, price)
        else:
                symbol_prices[symbol] = price

## ============================================
## جلب آخر سعر
## ============================================
func get_price(symbol: String) -> float:
        return symbol_prices.get(symbol, 0.0)

## ============================================
## حساب التغير اللحظي — نموذج هندسي براوني (GBM)
## ============================================
func _calculate_tick(symbol: String) -> float:
        var price: float = symbol_prices.get(symbol, 0.0)
        if price <= 0.0:
                return 0.0
        
        var profile: Dictionary = VOLATILITY_PROFILE.get(symbol, VOLATILITY_PROFILE["BTCUSDT"])
        var volatility: float = profile["base_volatility"]
        var trend_str: float = profile["trend_strength"]
        var mean_rev: float = profile["mean_reversion"]
        
        ## ---- مكونات الحركة ----
        
        ## 1) تقلب عشوائي (Brownian Motion)
        var random_shock: float = (randf() * 2.0 - 1.0) * volatility * 0.3  ## Approximate Gaussian noise
        
        ## 2) اتجاه السوق (Trend)
        var trend: Dictionary = symbol_trends.get(symbol, {})
        var trend_bias: float = 0.0
        match trend.get("type", 0):
                TrendType.BULLISH:  trend_bias = trend_str
                TrendType.BEARISH:  trend_bias = -trend_str
                TrendType.SIDEWAYS: trend_bias = 0.0
        
        ## 3) ارتداد إلى المتوسط (Mean Reversion)
        ## يمنع السعر من التحرك بعيداً جداً
        var history: Array = symbol_history.get(symbol, [])
        var mean_price: float = price
        if history.size() >= 50:
                var sum := 0.0
                for h in history.slice(-50):
                        sum += h["price"]
                mean_price = sum / 50.0
        var mean_reversion_force: float = (mean_price - price) / price * mean_rev
        
        ## 4) تقلب عالي في أوقات الأخبار
        var news_volatility_boost: float = 1.0
        for event in news_events:
                if event["symbol"] == symbol and event["active"]:
                        news_volatility_boost = 3.0
                        if event["sentiment"] > 0:
                                trend_bias += event["sentiment"] * 0.01
                        else:
                                trend_bias += event["sentiment"] * 0.01
        
        ## 5) حجم التداول (Volume Impact)
        ## أحجام عالية = حركات أكبر
        var volume_multiplier: float = randf_range(0.5, 2.0)
        if volume_multiplier > 1.8:
                random_shock *= 1.5  ## أحجام مرتفعة = صدمات أكبر
        
        ## ---- حساب التغير الكلي ----
        var price_change_pct: float = (
                random_shock +
                trend_bias +
                mean_reversion_force
        ) * news_volatility_boost * volume_multiplier
        
        ## تحديد الحد الأقصى للتغير (±5% لكل علامة)
        price_change_pct = clampf(price_change_pct, -0.05, 0.05)
        
        ## تطبيق التغير
        var new_price: float = price * (1.0 + price_change_pct)
        new_price = maxf(new_price, price * 0.5)  ## الحد الأدنى: لا ينخفض أكثر من 50% دفعة واحدة
        
        ## ---- تحديث السجل ----
        if history.size() > 500:
                history.pop_front()
        history.append({
                "price": new_price,
                "volume": volume_multiplier * 1000.0,
                "time": Time.get_unix_time_from_system()
        })
        symbol_history[symbol] = history
        
        return new_price

## ============================================
## نبضة السوق (كل ثانية)
## ============================================
func _on_tick() -> void:
        if not market_hours_active:
                return
        
        for symbol in symbol_prices:
                var new_price := _calculate_tick(symbol)
                symbol_prices[symbol] = new_price
                price_tick.emit(symbol, new_price, Time.get_unix_time_from_system())

## ============================================
## تغيير الاتجاه عشوائي
## ============================================
func _on_trend_change() -> void:
        ## تغيير اتجاه 1-3 رموز عشوائياً
        var symbols_to_change: Array = symbol_trends.keys()
        var count: int = randi() % min(3, symbols_to_change.size()) + 1
        symbols_to_change.shuffle()
        
        for i in range(count):
                var symbol: String = symbols_to_change[i]
                var roll := randf()
                var new_trend: TrendType
                var strength: float
                
                if roll < 0.40:
                        new_trend = TrendType.BULLISH
                        strength = randf_range(0.5, 2.0)
                elif roll < 0.80:
                        new_trend = TrendType.BEARISH
                        strength = randf_range(0.5, 2.0)
                else:
                        new_trend = TrendType.SIDEWAYS
                        strength = randf_range(0.1, 0.5)
                
                symbol_trends[symbol] = {
                        "type": new_trend,
                        "strength": strength,
                        "duration": 0,
                        "max_duration": randi_range(30, 200)
                }
                trend_changed.emit(symbol, new_trend, strength)
                print("[MarketSim] 📊 اتجاه جديد: %s → %s | القوة: %.2f" % [
                        symbol, TrendType.keys()[new_trend], strength
                ])
        
        ## ضبط الوقت التالي
        _trend_timer.wait_time = randf_range(30.0, 120.0)

## ============================================
## أحداث إخبارية عشوائية
## ============================================
func _on_random_news() -> void:
        var symbols: Array = symbol_prices.keys()
        if symbols.is_empty():
                return
        
        var symbol: String = symbols[randi() % symbols.size()]
        var is_positive: bool = randf() > 0.45  ## 55% أخبار إيجابية
        var magnitude: float = randf_range(0.3, 1.0)
        
        var news_titles := {
                true: [
                        "تقرير إيجابي: %s تحقق مكاسب قياسية",
                        "شراكة استراتيجية تعزز قيمة %s",
                        "توصية محللين بارزين بشراء %s",
                        "ارتفاع الطلب المؤسسي على %s",
                        "تحديث تقني جديد يعزز %s"
                ],
                false: [
                        "تحذير تنظيمي يضرب %s",
                        "تسريبات خسائر كبيرة في %s",
                        "محللون يحذرون من فقاعة %s",
                        "انقطاع شبكة %s مؤقتاً",
                        "تقارير عن عمليات بيع كبيرة في %s"
                ]
        }
        
        var titles: Array = news_titles[is_positive]
        var title: String = titles[randi() % titles.size()] % symbol
        
        var event := {
                "symbol": symbol,
                "title": title,
                "sentiment": magnitude if is_positive else -magnitude,
                "active": true,
                "duration": randi_range(5, 15),  ## ثوانٍ
                "timestamp": Time.get_unix_time_from_system()
        }
        
        news_events.append(event)
        
        ## إشعار بصري
        NotificationManager.send_notification(
                "📰 أخبار السوق",
                title,
                NP.INFO,
                false
        )
        
        ## إنهاء الحدث بعد مدة
        var news_end_timer := Timer.new()
        news_end_timer.wait_time = event["duration"]
        news_end_timer.one_shot = true
        news_end_timer.timeout.connect(func():
                event["active"] = false
                news_end_timer.queue_free()
        )
        add_child(news_end_timer)
        
        ## ضبط الوقت التالي للأخبار
        _news_timer.wait_time = randf_range(60.0, 300.0)

## ============================================
## توليد حدث إخباري محدد (للاختبار)
## ============================================
func force_news_event(symbol: String, positive: bool, magnitude: float = 1.0) -> void:
        var event := {
                "symbol": symbol,
                "title": "حدث إخباري قوي على %s" % symbol,
                "sentiment": magnitude if positive else -magnitude,
                "active": true,
                "duration": 10,
                "timestamp": Time.get_unix_time_from_system()
        }
        news_events.append(event)

## ============================================
## الحصول على مؤشرات فنية (SMA, RSI, MACD)
## ============================================
func get_sma(symbol: String, period: int = 20) -> float:
        var history: Array = symbol_history.get(symbol, [])
        if history.size() < period:
                return get_price(symbol)
        
        var sum := 0.0
        for i in range(history.size() - period, history.size()):
                sum += history[i]["price"]
        return sum / float(period)

func get_rsi(symbol: String, period: int = 14) -> float:
        var history: Array = symbol_history.get(symbol, [])
        if history.size() < period + 1:
                return 50.0  ## محايد
        
        var gains := 0.0
        var losses := 0.0
        
        for i in range(history.size() - period, history.size()):
                var change: float = history[i]["price"] - history[i-1]["price"]
                if change > 0:
                        gains += change
                else:
                        losses += abs(change)
        
        gains /= float(period)
        losses /= float(period)
        
        if losses == 0:
                return 100.0
        var rs: float = gains / losses
        return 100.0 - (100.0 / (1.0 + rs))

## ============================================
## حساب بيانات الشموع (Candlestick)
## للرسم البياني
## ============================================
func get_candlestick_data(symbol: String, interval_secs: int = 60) -> Array[Dictionary]:
        var history: Array = symbol_history.get(symbol, [])
        var candles: Array[Dictionary] = []
        
        var current_candle: Dictionary = {}
        var candle_start_time: int = 0
        
        for tick in history:
                var tick_time: int = int(tick["time"])
                var price: float = tick["price"]
                
                if current_candle.is_empty() or tick_time - candle_start_time >= interval_secs:
                        if not current_candle.is_empty():
                                candles.append(current_candle)
                        current_candle = {
                                "open": price,
                                "high": price,
                                "low": price,
                                "close": price,
                                "volume": tick.get("volume", 0.0),
                                "start_time": tick_time
                        }
                        candle_start_time = tick_time
                else:
                        current_candle["close"] = price
                        current_candle["high"] = maxf(current_candle["high"], price)
                        current_candle["low"] = minf(current_candle["low"], price)
                        current_candle["volume"] += tick.get("volume", 0.0)
        
        if not current_candle.is_empty():
                candles.append(current_candle)
        
        return candles
