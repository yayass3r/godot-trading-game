## ============================================
## ChartManager.gd - مدير الرسوم البيانية للشموع
## يرسم رسوم شموع تفاعلية مع مؤشرات فنية
## يربط مع DataManager لجلب بيانات K-line من Binance
## ============================================
extends Node

## ---- إشارات (Signals) ----
signal chart_updated(symbol: String, interval: String, candle_count: int)
signal chart_rendered(symbol: String)
signal crosshair_moved(price: float, volume: float, time: int)
signal timeframe_changed(new_interval: String)
signal indicator_added(indicator_name: String)
signal indicator_removed(indicator_name: String)
signal drawing_mode_changed(mode: DrawingMode)

## ---- أنواع الرسوم ----
enum DrawingMode {
        NONE,
        HORIZONTAL_LINE,
        TREND_LINE,
        FIBONACCI,
        RECTANGLE,
        TEXT_NOTE
}

enum CandleColor {
        BULLISH,
        BEARISH
}

## ---- فترات الرسم البياني ----
const TIMEFRAMES: Dictionary = {
        "1m": {"label": "1 دقيقة", "seconds": 60, "api": "1m"},
        "5m": {"label": "5 دقائق", "seconds": 300, "api": "5m"},
        "15m": {"label": "15 دقيقة", "seconds": 900, "api": "15m"},
        "1h": {"label": "ساعة", "seconds": 3600, "api": "1h"},
        "4h": {"label": "4 ساعات", "seconds": 14400, "api": "4h"},
        "1d": {"label": "يومي", "seconds": 86400, "api": "1d"},
        "1w": {"label": "أسبوعي", "seconds": 604800, "api": "1w"},
}

## ---- بيانات الشموع ----
var candles: Array[Dictionary] = []
var current_symbol: String = "BTCUSDT"
var current_interval: String = "1h"
var max_candles: int = 500

## ---- مؤشرات فنية ----
var active_indicators: Dictionary = {}
var sma_data: Dictionary = {}
var ema_data: Dictionary = {}
var rsi_data: Dictionary = {}
var macd_data: Dictionary = {}
var bollinger_data: Dictionary = {}
var volume_sma: Array[float] = []

## ---- حالة الرسم ----
var drawing_mode: DrawingMode = DrawingMode.NONE
var drawing_elements: Array[Dictionary] = []
var is_chart_loaded: bool = false

## ---- مراجع ----
var data_manager: Node

## ---- تكبير وتصغير ----
var zoom_level: float = 1.0
var scroll_offset: float = 0.0
var visible_candles_start: int = 0
var visible_candles_count: int = 60

## ============================================
## _ready() - التهيئة
## ============================================
func _ready() -> void:
        data_manager = get_node_or_null("/root/DataManager")

        if data_manager:
                data_manager.kline_received.connect(_on_kline_received)

        var refresh_timer := Timer.new()
        refresh_timer.wait_time = 30.0
        refresh_timer.autostart = true
        refresh_timer.timeout.connect(_auto_refresh)
        add_child(refresh_timer)

        print("[ChartManager] ✅ مدير الرسوم البيانية جاهز")

## ============================================
## تحميل رسم بياني لأداة معينة
## ============================================
func load_chart(symbol: String, interval: String = "1h") -> void:
        current_symbol = symbol
        current_interval = interval
        candles.clear()
        active_indicators.clear()
        is_chart_loaded = false
        scroll_offset = 0.0

        if data_manager:
                data_manager.fetch_klines(symbol, interval, max_candles)

        timeframe_changed.emit(interval)
        print("[ChartManager] 📊 جاري تحميل رسم %s | الإطار: %s" % [symbol, interval])

## ============================================
## تغيير الإطار الزمني
## ============================================
func change_timeframe(interval: String) -> void:
        if TIMEFRAMES.has(interval):
                load_chart(current_symbol, interval)

## ============================================
## استقبال بيانات الشموع من DataManager
## ============================================
func _on_kline_received(symbol: String, interval: String, new_candles: Array) -> void:
        if symbol != current_symbol or interval != current_interval:
                return

        candles = new_candles
        is_chart_loaded = true

        _calculate_all_indicators()

        chart_updated.emit(symbol, interval, candles.size())
        chart_rendered.emit(symbol)

        print("[ChartManager] 📊 تم تحديث الرسم: %d شمعة | %s" % [candles.size(), symbol])

## ============================================
## تحديث تلقائي
## ============================================
func _auto_refresh() -> void:
        if is_chart_loaded and current_symbol != "":
                if data_manager:
                        data_manager.fetch_klines(current_symbol, current_interval, max_candles)

## ============================================
## ===== حساب المؤشرات الفنية =====
## ============================================

func _calculate_all_indicators() -> void:
        if candles.size() < 2:
                return

        calculate_sma(9)
        calculate_sma(21)
        calculate_sma(50)
        calculate_sma(200)
        calculate_ema(12)
        calculate_ema(26)
        calculate_rsi(14)
        calculate_macd()
        calculate_bollinger_bands(20, 2.0)
        calculate_volume_sma(20)

## ============================================
## SMA - المتوسط المتحرك البسيط
## ============================================
func calculate_sma(period: int) -> void:
        var result: Array[float] = []

        for i in range(candles.size()):
                if i < period - 1:
                        result.append(0.0)
                else:
                        var sum := 0.0
                        for j in range(i - period + 1, i + 1):
                                sum += candles[j]["close"]
                        result.append(sum / period)

        sma_data[str(period)] = result
        active_indicators["SMA_%d" % period] = result

## ============================================
## EMA - المتوسط المتحرك الأُسّي
## ============================================
func calculate_ema(period: int) -> void:
        var result: Array[float] = []
        var multiplier: float = 2.0 / (period + 1.0)

        if candles.size() < period:
                return

        var sum := 0.0
        for i in range(period):
                sum += candles[i]["close"]
        var prev_ema := sum / period

        for i in range(period):
                result.append(0.0)
        result[period - 1] = prev_ema

        for i in range(period, candles.size()):
                var current_ema: float = (candles[i]["close"] - prev_ema) * multiplier + prev_ema
                result.append(current_ema)
                prev_ema = current_ema

        ema_data[str(period)] = result
        active_indicators["EMA_%d" % period] = result

## ============================================
## RSI - مؤشر القوة النسبية
## ============================================
func calculate_rsi(period: int = 14) -> void:
        var result: Array[float] = []

        if candles.size() < period + 1:
                return

        var gains: Array[float] = []
        var losses: Array[float] = []

        for i in range(1, candles.size()):
                var change: float = candles[i]["close"] - candles[i - 1]["close"]
                gains.append(maxf(change, 0.0))
                losses.append(maxf(-change, 0.0))

        var avg_gain := 0.0
        var avg_loss := 0.0
        for i in range(period):
                avg_gain += gains[i]
                avg_loss += losses[i]
        avg_gain /= period
        avg_loss /= period

        for i in range(period):
                result.append(50.0)

        if avg_loss == 0.0:
                result.append(100.0)
        else:
                var rs := avg_gain / avg_loss
                result.append(100.0 - (100.0 / (1.0 + rs)))

        for i in range(period, gains.size()):
                avg_gain = (avg_gain * (period - 1) + gains[i]) / period
                avg_loss = (avg_loss * (period - 1) + losses[i]) / period

                if avg_loss == 0.0:
                        result.append(100.0)
                else:
                        var rs := avg_gain / avg_loss
                        result.append(100.0 - (100.0 / (1.0 + rs)))

        rsi_data[str(period)] = result
        active_indicators["RSI_%d" % period] = result

## ============================================
## MACD - التباعد والتقارب
## ============================================
func calculate_macd() -> void:
        calculate_ema(12)
        calculate_ema(26)

        var ema12: Array = ema_data.get("12", [])
        var ema26: Array = ema_data.get("26", [])

        if ema12.size() == 0 or ema26.size() == 0:
                return

        var macd_line: Array[float] = []
        var start_idx := 25

        for i in range(start_idx, candles.size()):
                macd_line.append(ema12[i] - ema26[i])

        var signal_line: Array[float] = []
        var multiplier := 2.0 / 10.0

        if macd_line.size() >= 9:
                var sum := 0.0
                for i in range(9):
                        sum += macd_line[i]
                var prev_signal := sum / 9.0

                for i in range(9):
                        signal_line.append(0.0)
                signal_line[8] = prev_signal

                for i in range(9, macd_line.size()):
                        var current_signal := (macd_line[i] - prev_signal) * multiplier + prev_signal
                        signal_line.append(current_signal)
                        prev_signal = current_signal

        var histogram: Array[float] = []
        for i in range(macd_line.size()):
                var sig_idx := i + (macd_line.size() - signal_line.size())
                if sig_idx >= 0 and sig_idx < signal_line.size():
                        histogram.append(macd_line[i] - signal_line[sig_idx])
                else:
                        histogram.append(0.0)

        macd_data = {"macd": macd_line, "signal": signal_line, "histogram": histogram}
        active_indicators["MACD"] = macd_data

## ============================================
## Bollinger Bands - بولينجر باند
## ============================================
func calculate_bollinger_bands(period: int = 20, std_dev: float = 2.0) -> void:
        var upper: Array[float] = []
        var middle: Array[float] = []
        var lower: Array[float] = []

        if candles.size() < period:
                return

        for i in range(candles.size()):
                if i < period - 1:
                        upper.append(0.0)
                        middle.append(0.0)
                        lower.append(0.0)
                else:
                        var sum := 0.0
                        for j in range(i - period + 1, i + 1):
                                sum += candles[j]["close"]
                        var avg := sum / period
                        middle.append(avg)

                        var variance := 0.0
                        for j in range(i - period + 1, i + 1):
                                variance += pow(candles[j]["close"] - avg, 2)
                        variance /= period
                        var std := sqrt(variance)

                        upper.append(avg + std_dev * std)
                        lower.append(avg - std_dev * std)

        bollinger_data = {"upper": upper, "middle": middle, "lower": lower}
        active_indicators["BB_%d_%.1f" % [period, std_dev]] = bollinger_data

## ============================================
## Volume SMA - متوسط الحجم
## ============================================
func calculate_volume_sma(period: int = 20) -> void:
        volume_sma.clear()

        for i in range(candles.size()):
                if i < period - 1:
                        volume_sma.append(0.0)
                else:
                        var sum := 0.0
                        for j in range(i - period + 1, i + 1):
                                sum += candles[j]["volume"]
                        volume_sma.append(sum / period)

## ============================================
## ===== أدوات الرسم على الشارت =====
## ============================================

func add_horizontal_line(price: float, color: String = "#FFD700", label: String = "") -> void:
        drawing_elements.append({
                "type": "horizontal_line", "price": price,
                "color": color, "label": label,
                "timestamp": Time.get_unix_time_from_system()
        })

func add_trend_line(start_time: int, start_price: float, end_time: int, end_price: float, color: String = "#FFFFFF") -> void:
        drawing_elements.append({
                "type": "trend_line",
                "start_time": start_time, "start_price": start_price,
                "end_time": end_time, "end_price": end_price, "color": color
        })

func add_fibonacci_retracement(high_price: float, low_price: float) -> void:
        var levels := [0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0]
        var diff := high_price - low_price

        var fib_levels: Array[Dictionary] = []
        for level in levels:
                fib_levels.append({
                        "level": level,
                        "price": high_price - diff * level,
                        "label": "%.1f%% — $%.2f" % [level * 100, high_price - diff * level]
                })

        drawing_elements.append({
                "type": "fibonacci", "high": high_price,
                "low": low_price, "levels": fib_levels
        })

func clear_drawing_tools() -> void:
        drawing_elements.clear()

## ============================================
## ===== تحليل الشارت =====
## ============================================

func get_candle_at(index: int) -> Dictionary:
        if index >= 0 and index < candles.size():
                return candles[index]
        return {}

func get_price_range(visible_start: int = -1, visible_end: int = -1) -> Dictionary:
        if candles.size() == 0:
                return {"high": 0.0, "low": 0.0, "range": 0.0}

        var start_idx := visible_start if visible_start >= 0 else 0
        var end_idx := visible_end if visible_end >= 0 else candles.size() - 1

        start_idx = clampi(start_idx, 0, candles.size() - 1)
        end_idx = clampi(end_idx, 0, candles.size() - 1)

        var high_price := -INF
        var low_price := INF

        for i in range(start_idx, end_idx + 1):
                if candles[i]["high"] > high_price:
                        high_price = candles[i]["high"]
                if candles[i]["low"] < low_price:
                        low_price = candles[i]["low"]

        return {"high": high_price, "low": low_price, "range": high_price - low_price}

func get_price_change_percentage() -> Dictionary:
        if candles.size() < 2:
                return {"change": 0.0, "change_pct": 0.0}

        var latest: float = candles[-1]["close"]
        var previous: float = candles[-2]["close"]
        var change: float = latest - previous
        var change_pct: float = (change / previous) * 100.0

        return {"change": change, "change_pct": change_pct, "latest": latest, "previous": previous}

func get_visible_candles() -> Array[Dictionary]:
        var adjusted_start := visible_candles_start + int(scroll_offset)
        adjusted_start = clampi(adjusted_start, 0, max(candles.size() - visible_candles_count, 0))

        var end_idx := mini(adjusted_start + visible_candles_count, candles.size())

        if adjusted_start >= candles.size():
                return []

        return candles.slice(adjusted_start, end_idx)

func zoom_in() -> void:
        visible_candles_count = maxi(visible_candles_count - 10, 15)
        zoom_level *= 1.2

func zoom_out() -> void:
        visible_candles_count = mini(visible_candles_count + 10, candles.size())
        zoom_level = maxf(zoom_level / 1.2, 0.2)

func scroll_left() -> void:
        scroll_offset = maxf(scroll_offset - 5, 0)

func scroll_right() -> void:
        scroll_offset = minf(scroll_offset + 5, float(max(candles.size() - visible_candles_count, 0)))

## ============================================
## تحويل الفهرس إلى إحداثيات الشاشة
## ============================================
func candle_to_screen_position(candle_index: int, chart_rect: Rect2) -> Dictionary:
        if candle_index < 0 or candle_index >= candles.size():
                return {"x": 0, "y": 0, "body_top": 0, "body_bottom": 0}

        var candle := candles[candle_index]
        var price_range := get_price_range()

        if price_range["range"] == 0:
                return {"x": 0, "y": 0, "body_top": 0, "body_bottom": 0}

        var visible := get_visible_candles()
        var local_idx := candle_index - visible_candles_start - int(scroll_offset)
        if local_idx < 0 or local_idx >= visible.size():
                return {"x": 0, "y": 0, "body_top": 0, "body_bottom": 0}

        var candle_width := chart_rect.size.x / visible_candles_count
        var x := chart_rect.position.x + (local_idx + 0.5) * candle_width

        var high_y: float = chart_rect.position.y + (1.0 - (candle["high"] - price_range["low"]) / price_range["range"]) * chart_rect.size.y
        var low_y: float = chart_rect.position.y + (1.0 - (candle["low"] - price_range["low"]) / price_range["range"]) * chart_rect.size.y
        var open_y: float = chart_rect.position.y + (1.0 - (candle["open"] - price_range["low"]) / price_range["range"]) * chart_rect.size.y
        var close_y: float = chart_rect.position.y + (1.0 - (candle["close"] - price_range["low"]) / price_range["range"]) * chart_rect.size.y

        var is_bullish: bool = candle["close"] >= candle["open"]

        return {
                "x": x, "wick_top": high_y, "wick_bottom": low_y,
                "body_top": minf(open_y, close_y), "body_bottom": maxf(open_y, close_y),
                "is_bullish": is_bullish, "width": candle_width * 0.7
        }
