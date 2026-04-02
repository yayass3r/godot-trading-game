## ============================================
## SentimentAnalyzer.gd - تحليل مشاعر المنتدى
## يحلل منشورات المنتدى وتغريدات المتداولين
## لتحديد المزاج العام للسوق (صعود/هبوط/محايد)
## ============================================
extends Node

## ---- إشارات (Signals) ----
signal sentiment_updated(symbol: String, score: float, label: String)
signal trend_alert(symbol: String, direction: String, strength: float)
signal fear_greed_updated(index: float, label: String)
signal sentiment_report_generated(report: Dictionary)
signal social_signal_detected(symbol: String, signal_type: String, confidence: float)

## ---- مراجع ----
var forum_manager: Node
var data_manager: Node

## ---- كلمات مفتاحية للتحليل (ثنائية اللغة) ----
var bullish_keywords: Array[String] = [
        "bullish", "moon", "pump", "buy", "long", "breakout", "resistance breakout",
        "golden cross", "ath", "rally", "uptrend", "buy the dip", "oversold",
        "cup and handle", "ascending triangle", "hammer", "engulfing",
        "strong support", "accumulation", "institutional buying",
        "صعود", "شراء", "قوي", "مضاربة", "ارتفاع", "فرصة", "شراء الآن",
        "مؤشر إيجابي", "دعم قوي", "اختراق", "صاروخ", "قمر", "هبوط شراء",
        "مؤشرات صاعدة", "اتجاه صاعد", "فرصة ذهبية", "لا تفوت",
        "سعر منخفض", "شراء طويل", "long", "بيقوم برفع", "رالي"
]

var bearish_keywords: Array[String] = [
        "bearish", "dump", "sell", "short", "breakdown", "death cross",
        "overbought", "correction", "crash", "downtrend", "sell off",
        "resistance rejected", "descending triangle", "bear trap", "double top",
        "distribution", "whales selling", "bubble burst",
        "هبوط", "بيع", "خسارة", "ضعيف", "انخفاض", "خطر", "بيع الآن",
        "مؤشر سلبي", "تصحيح", "انهيار", "اتجاه هابط", "فخ",
        "سعر مرتفع", "فقاعة", "بيع قصير", "short", "يقوم بالبيع",
        "احذر", "خسارة كبيرة", "سوق دببة"
]

## ---- مؤشر الخوف والطمع ----
var fear_greed_index: float = 50.0

## ---- نتائج التحليل ----
var sentiment_scores: Dictionary = {}
var symbol_mentions: Dictionary = {}
var sentiment_history: Dictionary = {}
var market_sentiment: float = 0.0

## ---- إعدادات التحليل ----
const MIN_POSTS_FOR_ANALYSIS: int = 5
const HISTORY_RETENTION: int = 86400
const TREND_THRESHOLD: float = 0.3
const ANALYSIS_INTERVAL: float = 60.0

## ---- مؤقت التحليل ----
var analysis_timer: Timer

## ============================================
## _ready() - التهيئة
## ============================================
func _ready() -> void:
        forum_manager = get_node_or_null("/root/ForumManager")
        data_manager = get_node_or_null("/root/DataManager")

        analysis_timer = Timer.new()
        analysis_timer.wait_time = ANALYSIS_INTERVAL
        analysis_timer.autostart = true
        analysis_timer.timeout.connect(perform_full_analysis)
        add_child(analysis_timer)

        if forum_manager:
                forum_manager.post_created.connect(_on_new_post)

        print("[SentimentAnalyzer] ✅ محلل المشاعر جاهز | %d كلمة صعود | %d كلمة هبوط" % [
                bullish_keywords.size(), bearish_keywords.size()
        ])

## ============================================
## تحليل منشور جديد فوراً
## ============================================
func _on_new_post(post) -> void:
        if post.attached_symbol.is_empty():
                return

        symbol_mentions[post.attached_symbol] = symbol_mentions.get(post.attached_symbol, 0) + 1

        var post_sentiment := analyze_text(post.content)

        if not sentiment_scores.has(post.attached_symbol):
                sentiment_scores[post.attached_symbol] = {
                        "score": 0.0, "label": "محايد", "volume": 0,
                        "confidence": 0.0, "weighted_score": 0.0
                }

        var sym_data: Dictionary = sentiment_scores[post.attached_symbol]
        sym_data["weighted_score"] = (sym_data["weighted_score"] * sym_data["volume"] + post_sentiment) / (sym_data["volume"] + 1)
        sym_data["volume"] += 1
        sym_data["confidence"] = minf(sym_data["volume"] / 20.0, 1.0)

        if not sentiment_history.has(post.attached_symbol):
                sentiment_history[post.attached_symbol] = []

        sentiment_history[post.attached_symbol].append({
                "time": Time.get_unix_time_from_system(), "score": post_sentiment
        })

        _cleanup_old_history(post.attached_symbol)

## ============================================
## تحليل نص ودرجة المشاعر (-1.0 إلى 1.0)
## ============================================
func analyze_text(text: String) -> float:
        var lower_text := text.to_lower()
        var bull_hits := 0
        var bear_hits := 0

        for keyword in bullish_keywords:
                if keyword.to_lower() in lower_text:
                        bull_hits += 1

        for keyword in bearish_keywords:
                if keyword.to_lower() in lower_text:
                        bear_hits += 1

        var total_hits := bull_hits + bear_hits
        if total_hits == 0:
                return 0.0

        var score := float(bull_hits - bear_hits) / float(total_hits)

        if score > 0.7 or score < -0.7:
                score *= 1.2
        score = clampf(score, -1.0, 1.0)

        return score

## ============================================
## تحليل كامل لكل الرموز
## ============================================
func perform_full_analysis() -> void:
        if forum_manager == null or forum_manager.posts.size() == 0:
                return

        sentiment_scores.clear()
        symbol_mentions.clear()

        for post in forum_manager.posts:
                if post.attached_symbol.is_empty():
                        continue

                symbol_mentions[post.attached_symbol] = symbol_mentions.get(post.attached_symbol, 0) + 1
                var post_sentiment := analyze_text(post.content)

                if not sentiment_scores.has(post.attached_symbol):
                        sentiment_scores[post.attached_symbol] = {
                                "score": 0.0, "label": "محايد", "volume": 0,
                                "confidence": 0.0, "weighted_score": 0.0
                        }

                var sym_data: Dictionary = sentiment_scores[post.attached_symbol]
                sym_data["weighted_score"] = (sym_data["weighted_score"] * sym_data["volume"] + post_sentiment) / (sym_data["volume"] + 1)
                sym_data["volume"] += 1
                sym_data["confidence"] = minf(sym_data["volume"] / 20.0, 1.0)

        for symbol in sentiment_scores:
                var data: Dictionary = sentiment_scores[symbol]
                data["score"] = data["weighted_score"]
                data["label"] = _get_sentiment_label(data["score"])
                sentiment_updated.emit(symbol, data["score"], data["label"])

                if abs(data["score"]) >= TREND_THRESHOLD and data["confidence"] >= 0.5:
                        var direction := "صعود" if data["score"] > 0 else "هبوط"
                        trend_alert.emit(symbol, direction, data["score"])
                        social_signal_detected.emit(symbol, direction, data["confidence"])

        _calculate_market_sentiment()
        _calculate_fear_greed_index()

        print("[SentimentAnalyzer] 📊 تحليل كامل | رموز محللة: %d | المزاج: %.2f" % [
                sentiment_scores.size(), market_sentiment
        ])

## ============================================
## تحديد تصنيف المشاعر
## ============================================
func _get_sentiment_label(score: float) -> String:
        if score >= 0.7: return "🟢 صعود قوي جداً"
        elif score >= 0.3: return "🟢 صعود"
        elif score >= 0.1: return "🟡 صعود خفيف"
        elif score <= -0.7: return "🔴 هبوط قوي جداً"
        elif score <= -0.3: return "🔴 هبوط"
        elif score <= -0.1: return "🟡 هبوط خفيف"
        else: return "⚪ محايد"

## ============================================
## حساب المزاج العام للسوق
## ============================================
func _calculate_market_sentiment() -> void:
        var total_weighted := 0.0
        var total_volume := 0

        for symbol in sentiment_scores:
                var data: Dictionary = sentiment_scores[symbol]
                total_weighted += data["weighted_score"] * data["volume"]
                total_volume += data["volume"]

        if total_volume > 0:
                market_sentiment = total_weighted / total_volume
        else:
                market_sentiment = 0.0

## ============================================
## حساب مؤشر الخوف والطمع
## ============================================
func _calculate_fear_greed_index() -> void:
        var sentiment_factor := (market_sentiment + 1.0) * 50.0
        var volume_factor := 50.0

        var total_mentions := 0
        for count in symbol_mentions.values():
                total_mentions += count
        var mention_factor := clampf(float(total_mentions) / 50.0 * 100.0, 0.0, 100.0)

        fear_greed_index = sentiment_factor * 0.5 + volume_factor * 0.2 + mention_factor * 0.3
        fear_greed_index = clampf(fear_greed_index, 0.0, 100.0)

        var label := _get_fear_greed_label(fear_greed_index)
        fear_greed_updated.emit(fear_greed_index, label)

## ============================================
## تصنيف الخوف والطمع
## ============================================
func _get_fear_greed_label(index: float) -> String:
        if index <= 25: return "😱 خوف شديد"
        elif index <= 45: return "😰 خوف"
        elif index <= 55: return "😐 محايد"
        elif index <= 75: return "😊 طمع"
        else: return "🤑 طمع شديد"

## ============================================
## تنظيف التاريخ القديم
## ============================================
func _cleanup_old_history(symbol: String) -> void:
        if not sentiment_history.has(symbol):
                return
        var cutoff := Time.get_unix_time_from_system() - HISTORY_RETENTION
        var history: Array = sentiment_history[symbol]
        history = history.filter(func(entry): return int(entry["time"]) > cutoff)
        sentiment_history[symbol] = history

## ============================================
## الحصول على ملخص تحليل رمز
## ============================================
func get_symbol_sentiment(symbol: String) -> Dictionary:
        if not sentiment_scores.has(symbol):
                return {"symbol": symbol, "score": 0.0, "label": "لا توجد بيانات", "volume": 0, "confidence": 0.0}
        var data: Dictionary = sentiment_scores[symbol]
        data["symbol"] = symbol
        return data

## ============================================
## توليد تقرير تحليل المشاعر
## ============================================
func generate_report() -> Dictionary:
        var report := {
                "timestamp": Time.get_unix_time_from_system(),
                "market_sentiment": market_sentiment,
                "fear_greed_index": fear_greed_index,
                "fear_greed_label": _get_fear_greed_label(fear_greed_index),
                "total_symbols_analyzed": sentiment_scores.size(),
                "top_bullish": [], "top_bearish": [],
                "most_discussed": [], "recommendations": []
        }

        var sorted_symbols: Array[Dictionary] = []
        for symbol in sentiment_scores:
                sorted_symbols.append({
                        "symbol": symbol, "score": sentiment_scores[symbol]["score"],
                        "volume": sentiment_scores[symbol]["volume"],
                        "confidence": sentiment_scores[symbol]["confidence"]
                })

        sorted_symbols.sort_custom(func(a, b): return a["score"] > b["score"])

        for i in range(min(3, sorted_symbols.size())):
                report["top_bullish"].append(sorted_symbols[i])

        for i in range(max(0, sorted_symbols.size() - 3), sorted_symbols.size()):
                report["top_bearish"].append(sorted_symbols[i])

        var most_discussed: Array = []
        for symbol in symbol_mentions:
                most_discussed.append({"symbol": symbol, "mentions": symbol_mentions[symbol]})
        most_discussed.sort_custom(func(a, b): return a["mentions"] > b["mentions"])
        report["most_discussed"] = most_discussed.slice(0, 5)

        for entry in sorted_symbols:
                if entry["confidence"] >= 0.3:
                        if entry["score"] >= 0.5:
                                report["recommendations"].append({
                                        "symbol": entry["symbol"], "action": "شراء",
                                        "reason": "مشاعر إيجابية قوية (%.0f%%)" % (entry["score"] * 100)
                                })
                        elif entry["score"] <= -0.5:
                                report["recommendations"].append({
                                        "symbol": entry["symbol"], "action": "بيع",
                                        "reason": "مشاعر سلبية قوية (%.0f%%)" % (abs(entry["score"]) * 100)
                                })

        sentiment_report_generated.emit(report)
        return report
