## ============================================
## OrderBookManager.gd - مدير دفتر الأوامر
## يعرض أوامر الشراء والبيع الحقيقية من Binance
## ============================================
extends Node

## ---- إشارات (Signals) ----
signal orderbook_updated(symbol: String, bids: Array, asks: Array)
signal orderbook_depth_updated(symbol: String, depth: Dictionary)
signal spread_updated(symbol: String, spread: float, spread_pct: float)
signal large_order_detected(symbol: String, side: String, price: float, quantity: float)
signal imbalance_alert(symbol: String, buy_pressure: float, sell_pressure: float)

## ---- مراجع ----
var data_manager: Node

## ---- بيانات دفتر الأوامر ----
var orderbooks: Dictionary = {}
var active_symbol: String = "BTCUSDT"

## ---- إعدادات ----
const DEPTH_LEVELS: int = 20
const UPDATE_INTERVAL: float = 2.0
const LARGE_ORDER_THRESHOLD: float = 5.0
const IMBALANCE_THRESHOLD: float = 0.7

## ---- مؤقت التحديث ----
var update_timer: Timer
var is_streaming: bool = false

## ============================================
## _ready() - التهيئة
## ============================================
func _ready() -> void:
        data_manager = get_node_or_null("/root/DataManager")

        update_timer = Timer.new()
        update_timer.wait_time = UPDATE_INTERVAL
        update_timer.autostart = false
        update_timer.timeout.connect(_on_update_timeout)
        add_child(update_timer)

        print("[OrderBookManager] ✅ مدير دفتر الأوامر جاهز | عمق: %d مستوى" % DEPTH_LEVELS)

## ============================================
## بدء/إيقاف تدفق دفتر الأوامر
## ============================================
func start_streaming(symbol: String) -> void:
        active_symbol = symbol
        is_streaming = true
        if data_manager:
                data_manager.fetch_orderbook(symbol, DEPTH_LEVELS)
        update_timer.start()
        print("[OrderBookManager] 📡 بدء تدفق: %s" % symbol)

func stop_streaming() -> void:
        is_streaming = false
        update_timer.stop()

func _on_update_timeout() -> void:
        if is_streaming and data_manager:
                data_manager.fetch_orderbook(active_symbol, DEPTH_LEVELS)

## ============================================
## معالجة بيانات دفتر الأوامر
## ============================================
func process_orderbook_data(symbol: String, raw_bids: Array, raw_asks: Array) -> void:
        var bids := _parse_order_levels(raw_bids, "BUY")
        var asks := _parse_order_levels(raw_asks, "SELL")

        var spread := 0.0
        var spread_pct := 0.0
        if bids.size() > 0 and asks.size() > 0:
                spread = asks[0]["price"] - bids[0]["price"]
                if asks[0]["price"] > 0:
                        spread_pct = (spread / asks[0]["price"]) * 100.0

        _detect_large_orders(symbol, bids, asks)
        _analyze_imbalance(symbol, bids, asks)

        orderbooks[symbol] = {
                "bids": bids, "asks": asks,
                "spread": spread, "spread_pct": spread_pct,
                "timestamp": Time.get_unix_time_from_system()
        }

        orderbook_updated.emit(symbol, bids, asks)
        spread_updated.emit(symbol, spread, spread_pct)
        orderbook_depth_updated.emit(symbol, _calculate_depth(bids, asks))

## ============================================
## تحليل مستويات الأوامر
## ============================================
func _parse_order_levels(raw_levels: Array, side: String) -> Array[Dictionary]:
        var levels: Array[Dictionary] = []
        for item in raw_levels:
                if item.size() >= 2:
                        var price: float = float(item[0])
                        var quantity: float = float(item[1])
                        levels.append({
                                "price": price, "quantity": quantity,
                                "total": price * quantity, "side": side
                        })

        if side == "BUY":
                levels.sort_custom(func(a, b): return a["price"] > b["price"])
        else:
                levels.sort_custom(func(a, b): return a["price"] < b["price"])

        var cumulative_total := 0.0
        for level in levels:
                cumulative_total += level["total"]
                level["cumulative_total"] = cumulative_total

        return levels

## ============================================
## كشف الأوامر الكبيرة (Walls)
## ============================================
func _detect_large_orders(symbol: String, bids: Array, asks: Array) -> void:
        var all_quantities: Array[float] = []
        for level in bids: all_quantities.append(level["quantity"])
        for level in asks: all_quantities.append(level["quantity"])
        if all_quantities.size() == 0: return

        var avg_quantity := 0.0
        for q in all_quantities: avg_quantity += q
        avg_quantity /= all_quantities.size()
        var threshold := avg_quantity * LARGE_ORDER_THRESHOLD

        for level in bids:
                if level["quantity"] >= threshold:
                        large_order_detected.emit(symbol, "BUY", level["price"], level["quantity"])
        for level in asks:
                if level["quantity"] >= threshold:
                        large_order_detected.emit(symbol, "SELL", level["price"], level["quantity"])

## ============================================
## تحليل عدم التوازن
## ============================================
func _analyze_imbalance(symbol: String, bids: Array, asks: Array) -> void:
        var total_bid_volume := 0.0
        var total_ask_volume := 0.0
        for level in bids: total_bid_volume += level["quantity"]
        for level in asks: total_ask_volume += level["quantity"]

        var total := total_bid_volume + total_ask_volume
        if total == 0: return

        var buy_pressure := total_bid_volume / total
        var sell_pressure := total_ask_volume / total

        if buy_pressure >= IMBALANCE_THRESHOLD or sell_pressure >= IMBALANCE_THRESHOLD:
                imbalance_alert.emit(symbol, buy_pressure, sell_pressure)

## ============================================
## حساب العمق الكلي
## ============================================
func _calculate_depth(bids: Array, asks: Array) -> Dictionary:
        var bid_depth := 0.0
        var ask_depth := 0.0
        for level in bids: bid_depth += level["total"]
        for level in asks: ask_depth += level["total"]

        return {
                "bid_depth": bid_depth, "ask_depth": ask_depth,
                "total_depth": bid_depth + ask_depth,
                "bid_pct": (bid_depth / max(bid_depth + ask_depth, 0.01)) * 100.0,
                "ask_pct": (ask_depth / max(bid_depth + ask_depth, 0.01)) * 100.0
        }

## ============================================
## الحصول على دفتر الأوامر وأفضل الأسعار
## ============================================
func get_orderbook(symbol: String) -> Dictionary:
        if orderbooks.has(symbol):
                return orderbooks[symbol]
        return {"bids": [], "asks": [], "spread": 0.0, "spread_pct": 0.0, "timestamp": 0}

func get_best_prices(symbol: String) -> Dictionary:
        var ob := get_orderbook(symbol)
        var bids: Array = ob.get("bids", [])
        var asks: Array = ob.get("asks", [])
        var best_bid: float = bids[0]["price"] if bids.size() > 0 else 0.0
        var best_ask: float = asks[0]["price"] if asks.size() > 0 else 0.0

        return {
                "best_bid": best_bid, "best_ask": best_ask,
                "mid_price": (best_bid + best_ask) / 2.0 if best_bid > 0 and best_ask > 0 else 0.0,
                "spread": ob.get("spread", 0.0), "spread_pct": ob.get("spread_pct", 0.0)
        }

func get_pressure(symbol: String) -> Dictionary:
        var ob := get_orderbook(symbol)
        var depth := _calculate_depth(ob.get("bids", []), ob.get("asks", []))
        return {
                "buy_pressure_pct": depth.get("bid_pct", 50.0),
                "sell_pressure_pct": depth.get("ask_pct", 50.0),
                "dominant_side": "شراء" if depth.get("bid_pct", 50.0) > 60 else ("بيع" if depth.get("ask_pct", 50.0) > 60 else "متوازن")
        }
