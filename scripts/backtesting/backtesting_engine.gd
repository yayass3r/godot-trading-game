## ============================================
## BacktestingEngine.gd - محرك اختبار الاستراتيجيات
## يسمح للاعبين باختبار استراتيجيات التداول على بيانات تاريخية
## ============================================
extends Node

## ---- إشارات (Signals) ----
signal backtest_started(strategy_name: String, symbol: String, period: String)
signal backtest_progress(current: int, total: int, current_equity: float)
signal backtest_completed(results: Dictionary)
signal backtest_failed(error: String)

## ---- مراجع ----
var data_manager: Node

## ---- استراتيجيات محددة مسبقاً ----
var predefined_strategies: Array[Dictionary] = [
        {
                "name": "SMA Crossover",
                "description": "شراء عند تقاطع SMA السريع فوق البطيء، بيع عند العكس",
                "fast_period": 9, "slow_period": 21, "type": "sma_crossover"
        },
        {
                "name": "RSI Oversold/Overbought",
                "description": "شراء عند RSI < 30، بيع عند RSI > 70",
                "rsi_period": 14, "oversold": 30, "overbought": 70, "type": "rsi_strategy"
        },
        {
                "name": "Bollinger Bounce",
                "description": "شراء عند لمس الباند السفلي، بيع عند الباند العلوي",
                "bb_period": 20, "bb_std": 2.0, "type": "bb_bounce"
        },
        {
                "name": "MACD Signal",
                "description": "شراء عند تقاطع MACD فوق خط الإشارة",
                "fast_ema": 12, "slow_ema": 26, "signal_period": 9, "type": "macd_strategy"
        },
        {
                "name": "Volume Spike",
                "description": "شراء عند ارتفاع الحجم عن المتوسط مع اتجاه صعودي",
                "volume_period": 20, "volume_multiplier": 2.0, "type": "volume_spike"
        }
]

var last_results: Dictionary = {}
var is_running: bool = false
var initial_balance: float = 10000.0

## ============================================
## _ready() - التهيئة
## ============================================
func _ready() -> void:
        data_manager = get_node_or_null("/root/DataManager")
        print("[BacktestingEngine] ✅ محرك الباك تيست جاهز | %d استراتيجيات" % predefined_strategies.size())

## ============================================
## تشغيل باك تيست
## ============================================
func run_backtest(
        strategy: Dictionary,
        symbol: String,
        interval: String = "1h",
        candles: Array = [],
        leverage: int = 1,
        starting_balance: float = 10000.0,
        take_profit_pct: float = 0.05,
        stop_loss_pct: float = 0.03
) -> Dictionary:
        if is_running:
                backtest_failed.emit("باك تيست آخر قيد التشغيل حالياً")
                return {}

        if candles.size() < 50:
                backtest_failed.emit("بيانات غير كافية للاختبار")
                return {}

        is_running = true
        var strategy_name: String = strategy.get("name", "مجهول")
        backtest_started.emit(strategy_name, symbol, interval)

        initial_balance = starting_balance
        var current_equity := starting_balance
        var peak_equity := starting_balance
        var max_drawdown := 0.0

        var trades: Array[Dictionary] = []
        var equity_curve: Array[float] = []
        var position: Dictionary = {}

        var indicators := _calculate_indicators(strategy, candles)

        for i in range(indicators.size()):
                var idx := i + 50
                if idx >= candles.size():
                        break

                if i % 10 == 0:
                        backtest_progress.emit(i, indicators.size(), current_equity)
                        await get_tree().process_frame

                var candle: Dictionary = candles[idx]
                var ind: Dictionary = indicators[i]

                ## إدارة الصفقة المفتوحة
                if not position.is_empty():
                        var entry_price: float = position["entry_price"]
                        var is_long: bool = position["is_long"]
                        var pnl_pct: float

                        if is_long:
                                pnl_pct = (candle["close"] - entry_price) / entry_price
                        else:
                                pnl_pct = (entry_price - candle["close"]) / entry_price

                        pnl_pct *= leverage

                        if pnl_pct >= take_profit_pct or pnl_pct <= -stop_loss_pct or _should_close_position(strategy, ind):
                                var trade_pnl: float = position["margin"] * pnl_pct
                                current_equity += trade_pnl
                                position["exit_price"] = candle["close"]
                                position["pnl"] = trade_pnl
                                position["pnl_pct"] = pnl_pct * 100
                                position["exit_time"] = candle["open_time"]
                                position["reason"] = "جني أرباح" if pnl_pct >= take_profit_pct else ("وقف خسارة" if pnl_pct <= -stop_loss_pct else "إشارة إغلاق")
                                trades.append(position.duplicate(true))
                                position.clear()

                ## فتح صفقة جديدة
                if position.is_empty():
                        var signal_type: String = _get_signal(strategy, ind)

                        if (signal_type == "BUY" or signal_type == "SELL") and current_equity > 100:
                                var margin := current_equity * 0.1
                                position = {
                                        "symbol": symbol,
                                        "is_long": signal_type == "BUY",
                                        "entry_price": candle["close"],
                                        "entry_time": candle["open_time"],
                                        "margin": margin,
                                        "leverage": leverage
                                }
                                current_equity -= margin

                ## تحديث مسار الرصيد
                var open_pnl := 0.0
                if not position.is_empty():
                        var pp: float
                        if position["is_long"]:
                                pp = (candle["close"] - position["entry_price"]) / position["entry_price"]
                        else:
                                pp = (position["entry_price"] - candle["close"]) / position["entry_price"]
                        open_pnl = position["margin"] * pp * leverage

                var total_equity: float = current_equity + position.get("margin", 0.0) + open_pnl
                equity_curve.append(total_equity)

                if total_equity > peak_equity:
                        peak_equity = total_equity
                var drawdown: float = (peak_equity - total_equity) / peak_equity
                if drawdown > max_drawdown:
                        max_drawdown = drawdown

        ## إغلاق الصفقة المفتوحة في النهاية
        if not position.is_empty():
                var last_candle: Dictionary = candles[candles.size() - 1]
                var pp: float
                if position["is_long"]:
                        pp = (last_candle["close"] - position["entry_price"]) / position["entry_price"]
                else:
                        pp = (position["entry_price"] - last_candle["close"]) / position["entry_price"]
                var trade_pnl: float = position["margin"] * pp * leverage
                current_equity += trade_pnl
                position["exit_price"] = last_candle["close"]
                position["pnl"] = trade_pnl
                position["pnl_pct"] = pp * leverage * 100
                position["exit_time"] = last_candle["open_time"]
                position["reason"] = "نهاية الباك تيست"
                trades.append(position.duplicate(true))
                current_equity += position.get("margin", 0.0)

        var results := _calculate_results(trades, equity_curve, initial_balance, current_equity, strategy_name, symbol, interval, leverage)

        last_results = results
        is_running = false
        backtest_completed.emit(results)

        return results

## ============================================
## حساب المؤشرات الفنية
## ============================================
func _calculate_indicators(strategy: Dictionary, candles: Array) -> Array:
        var type: String = strategy.get("type", "sma_crossover")
        var result: Array[Dictionary] = []

        match type:
                "sma_crossover":
                        var fast_sma := _calc_sma_array(candles, int(strategy["fast_period"]))
                        var slow_sma := _calc_sma_array(candles, int(strategy["slow_period"]))
                        for i in range(candles.size()):
                                result.append({"fast_sma": fast_sma[i], "slow_sma": slow_sma[i], "close": candles[i]["close"]})
                "rsi_strategy":
                        var rsi := _calc_rsi_array(candles, int(strategy["rsi_period"]))
                        for i in range(candles.size()):
                                result.append({"rsi": rsi[i] if i < rsi.size() else 50.0, "close": candles[i]["close"]})
                "bb_bounce":
                        var bb := _calc_bb_array(candles, int(strategy["bb_period"]), float(strategy["bb_std"]))
                        for i in range(candles.size()):
                                result.append({"upper": bb["upper"][i], "middle": bb["middle"][i], "lower": bb["lower"][i], "close": candles[i]["close"]})
                "macd_strategy":
                        var macd := _calc_macd_array(candles)
                        for i in range(candles.size()):
                                result.append({
                                        "macd": macd["macd"][i] if i < macd["macd"].size() else 0.0,
                                        "signal": macd["signal"][i] if i < macd["signal"].size() else 0.0,
                                        "close": candles[i]["close"]
                                })
                "volume_spike":
                        var vol_sma := _calc_volume_sma_array(candles, int(strategy["volume_period"]))
                        for i in range(candles.size()):
                                result.append({"volume": candles[i]["volume"], "volume_sma": vol_sma[i], "close": candles[i]["close"], "open": candles[i]["open"]})

        return result

## ============================================
## تحديد إشارة الشراء/البيع
## ============================================
func _get_signal(strategy: Dictionary, ind: Dictionary) -> String:
        var type: String = strategy.get("type", "sma_crossover")

        match type:
                "sma_crossover":
                        if ind["fast_sma"] > 0 and ind["slow_sma"] > 0:
                                if ind["fast_sma"] > ind["slow_sma"]: return "BUY"
                                elif ind["fast_sma"] < ind["slow_sma"]: return "SELL"
                "rsi_strategy":
                        if ind["rsi"] < strategy["oversold"]: return "BUY"
                        elif ind["rsi"] > strategy["overbought"]: return "SELL"
                "bb_bounce":
                        if ind["lower"] > 0 and ind["close"] <= ind["lower"]: return "BUY"
                        elif ind["upper"] > 0 and ind["close"] >= ind["upper"]: return "SELL"
                "macd_strategy":
                        if ind["macd"] > ind["signal"] and ind["macd"] > 0: return "BUY"
                        elif ind["macd"] < ind["signal"] and ind["macd"] < 0: return "SELL"
                "volume_spike":
                        var mult: float = float(strategy["volume_multiplier"])
                        if ind["volume"] > ind["volume_sma"] * mult and ind["close"] > ind["open"]: return "BUY"
                        elif ind["volume"] > ind["volume_sma"] * mult and ind["close"] < ind["open"]: return "SELL"

        return "NONE"

func _should_close_position(strategy: Dictionary, ind: Dictionary) -> bool:
        var signal_type := _get_signal(strategy, ind)
        return (signal_type == "BUY" and ind.get("close", 0) < 0) or (signal_type == "SELL" and ind.get("close", 0) > 0)

## ============================================
## حساب نتائج الباك تيست
## ============================================
func _calculate_results(
        trades: Array, equity_curve: Array[float],
        start_balance: float, end_balance: float,
        strategy_name: String, symbol: String,
        interval: String, leverage: int
) -> Dictionary:
        var winning := 0
        var losing := 0
        var total_pnl := 0.0
        var biggest_win := 0.0
        var biggest_loss := 0.0
        var total_wins := 0.0
        var total_losses := 0.0
        var win_streak := 0
        var best_win_streak := 0

        for trade in trades:
                var pnl: float = trade.get("pnl", 0.0)
                total_pnl += pnl
                if pnl > 0:
                        winning += 1
                        total_wins += pnl
                        win_streak += 1
                        if win_streak > best_win_streak: best_win_streak = win_streak
                        if pnl > biggest_win: biggest_win = pnl
                else:
                        losing += 1
                        total_losses += abs(pnl)
                        win_streak = 0
                        if abs(pnl) > biggest_loss: biggest_loss = abs(pnl)

        var total_trades := trades.size()
        var win_rate := 0.0
        if total_trades > 0:
                win_rate = (float(winning) / float(total_trades)) * 100.0

        var avg_win := total_wins / float(max(winning, 1))
        var avg_loss := total_losses / float(max(losing, 1))
        var profit_factor := total_losses / 1.0 if total_losses > 0 else 999.0

        var total_return_pct := ((end_balance - start_balance) / start_balance) * 100.0

        ## Sharpe Ratio (مبسط)
        var sharpe_ratio := 0.0
        if equity_curve.size() > 1:
                var returns: Array[float] = []
                for i in range(1, equity_curve.size()):
                        if equity_curve[i - 1] > 0:
                                returns.append((equity_curve[i] - equity_curve[i - 1]) / equity_curve[i - 1])
                if returns.size() > 0:
                        var avg_return := 0.0
                        for r in returns: avg_return += r
                        avg_return /= returns.size()
                        var variance := 0.0
                        for r in returns: variance += pow(r - avg_return, 2)
                        variance /= returns.size()
                        var std_dev := sqrt(variance)
                        if std_dev > 0:
                                sharpe_ratio = (avg_return / std_dev) * sqrt(252.0)

        ## Max Drawdown from equity curve
        var max_dd := 0.0
        var peak := 0.0
        for eq in equity_curve:
                if eq > peak: peak = eq
                var dd := (peak - eq) / peak
                if dd > max_dd: max_dd = dd

        var rating: String = _rate_strategy(total_return_pct, win_rate, max_dd, profit_factor, sharpe_ratio)

        return {
                "strategy_name": strategy_name, "symbol": symbol,
                "interval": interval, "leverage": leverage,
                "initial_balance": start_balance, "final_balance": end_balance,
                "total_return": end_balance - start_balance,
                "total_return_pct": total_return_pct,
                "total_trades": total_trades,
                "winning_trades": winning, "losing_trades": losing,
                "win_rate": win_rate, "biggest_win": biggest_win, "biggest_loss": biggest_loss,
                "avg_win": avg_win, "avg_loss": avg_loss, "profit_factor": profit_factor,
                "max_drawdown": max_dd * 100.0, "sharpe_ratio": sharpe_ratio,
                "best_win_streak": best_win_streak, "trades": trades,
                "equity_curve": equity_curve, "rating": rating,
                "timestamp": Time.get_unix_time_from_system()
        }

## ============================================
## تقييم الاستراتيجية
## ============================================
func _rate_strategy(return_pct: float, win_rate: float, drawdown: float, profit_factor: float, sharpe: float) -> String:
        var score := 0.0
        if return_pct > 50: score += 30
        elif return_pct > 20: score += 25
        elif return_pct > 10: score += 20
        elif return_pct > 0: score += 15

        if win_rate > 60: score += 25
        elif win_rate > 50: score += 20
        elif win_rate > 40: score += 15
        else: score += 5

        if drawdown < 10: score += 25
        elif drawdown < 20: score += 20
        elif drawdown < 30: score += 15
        else: score += 5

        if profit_factor > 2.0: score += 20
        elif profit_factor > 1.5: score += 15
        elif profit_factor > 1.0: score += 10

        if score >= 80: return "⭐⭐⭐⭐⭐ ممتاز"
        elif score >= 65: return "⭐⭐⭐⭐ جيد جداً"
        elif score >= 50: return "⭐⭐⭐ جيد"
        elif score >= 35: return "⭐⭐ مقبول"
        else: return "⭐ يحتاج تحسين"

## ============================================
## وظائف مساعدة لحساب المؤشرات
## ============================================
func _calc_sma_array(candles: Array, period: int) -> Array[float]:
        var result: Array[float] = []
        for i in range(candles.size()):
                if i < period - 1:
                        result.append(0.0)
                else:
                        var sum := 0.0
                        for j in range(i - period + 1, i + 1): sum += candles[j]["close"]
                        result.append(sum / period)
        return result

func _calc_rsi_array(candles: Array, period: int) -> Array[float]:
        var result: Array[float] = []
        if candles.size() < period + 1: return result
        var gains: Array[float] = []
        var losses: Array[float] = []
        for i in range(1, candles.size()):
                var change: float = candles[i]["close"] - candles[i-1]["close"]
                gains.append(maxf(change, 0.0))
                losses.append(maxf(-change, 0.0))
        var avg_gain := 0.0
        var avg_loss := 0.0
        for i in range(period):
                avg_gain += gains[i]
                avg_loss += losses[i]
        avg_gain /= period
        avg_loss /= period
        for i in range(period): result.append(50.0)
        if avg_loss == 0: result.append(100.0)
        else: result.append(100.0 - (100.0 / (1.0 + avg_gain / avg_loss)))
        for i in range(period, gains.size()):
                avg_gain = (avg_gain * (period - 1) + gains[i]) / period
                avg_loss = (avg_loss * (period - 1) + losses[i]) / period
                if avg_loss == 0: result.append(100.0)
                else: result.append(100.0 - (100.0 / (1.0 + avg_gain / avg_loss)))
        return result

func _calc_bb_array(candles: Array, period: int, std_dev: float) -> Dictionary:
        var upper: Array[float] = []
        var middle: Array[float] = []
        var lower: Array[float] = []
        for i in range(candles.size()):
                if i < period - 1:
                        upper.append(0.0); middle.append(0.0); lower.append(0.0)
                else:
                        var sum := 0.0
                        for j in range(i - period + 1, i + 1): sum += candles[j]["close"]
                        var avg := sum / period
                        middle.append(avg)
                        var variance := 0.0
                        for j in range(i - period + 1, i + 1): variance += pow(candles[j]["close"] - avg, 2)
                        variance /= period
                        var std := sqrt(variance)
                        upper.append(avg + std_dev * std)
                        lower.append(avg - std_dev * std)
        return {"upper": upper, "middle": middle, "lower": lower}

func _calc_macd_array(candles: Array) -> Dictionary:
        var ema12 := _calc_ema_array(candles, 12)
        var ema26 := _calc_ema_array(candles, 26)
        var macd_line: Array[float] = []
        for i in range(25, candles.size()):
                macd_line.append(ema12[i] - ema26[i])
        var signal_line: Array[float] = []
        if macd_line.size() >= 9:
                var mult := 2.0 / 10.0
                var sum := 0.0
                for i in range(9): sum += macd_line[i]
                var prev := sum / 9.0
                for i in range(9): signal_line.append(0.0)
                signal_line[8] = prev
                for i in range(9, macd_line.size()):
                        var curr: float = (macd_line[i] - prev) * mult + prev
                        signal_line.append(curr)
                        prev = curr
        return {"macd": macd_line, "signal": signal_line}

func _calc_ema_array(candles: Array, period: int) -> Array[float]:
        var result: Array[float] = []
        if candles.size() < period: return result
        var mult := 2.0 / (period + 1.0)
        var sum := 0.0
        for i in range(period): sum += candles[i]["close"]
        var prev := sum / period
        for i in range(period): result.append(0.0)
        result[period - 1] = prev
        for i in range(period, candles.size()):
                var curr: float = (candles[i]["close"] - prev) * mult + prev
                result.append(curr)
                prev = curr
        return result

func _calc_volume_sma_array(candles: Array, period: int) -> Array[float]:
        var result: Array[float] = []
        for i in range(candles.size()):
                if i < period - 1:
                        result.append(0.0)
                else:
                        var sum := 0.0
                        for j in range(i - period + 1, i + 1): sum += candles[j]["volume"]
                        result.append(sum / period)
        return result
