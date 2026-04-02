## ============================================
## ChallengeManager.gd - مدير التحديات اليومية والأسبوعية
## يقدم تحديات متنوعة بمكافآت XP ورصيد
## يربط مع TradingManager و ProfileManager
## ============================================
extends Node

const TradeClass = preload("res://scripts/data_models/trade.gd")
const NP = preload("res://scripts/enums/notification_priority.gd")

## ---- إشارات (Signals) ----
signal challenge_available(challenge: Dictionary)
signal challenge_started(challenge_id: String)
signal challenge_progress_updated(challenge_id: String, current: int, target: int)
signal challenge_completed(challenge_id: String, rewards: Dictionary)
signal challenge_failed(challenge_id: String)
signal daily_challenges_refreshed(challenges: Array[Dictionary])
signal weekly_challenges_refreshed(challenges: Array[Dictionary])
signal streak_updated(current_streak: int, best_streak: int)

## ---- مراجع ----
var profile_manager: Node
var trading_manager: Node

## ---- أنواع التحديات ----
enum ChallengeType {
        TRADE_COUNT, PROFIT_TARGET, WIN_RATE, SHORT_PROFIT, LONG_PROFIT,
        LEVERAGE_TRADE, MULTI_SYMBOL, DAILY_VOLUME, NO_LOSS_DAY,
        SOCIAL_POST, BACKTEST_RUN, TUTORIAL_COMPLETE, STREAK_TRADES,
}

enum ChallengeDifficulty { EASY, MEDIUM, HARD, EXPERT }
enum ChallengeFrequency { DAILY, WEEKLY, SPECIAL }

## ---- بيانات التحديات ----
var active_daily_challenges: Array[Dictionary] = []
var active_weekly_challenges: Array[Dictionary] = []
var completed_challenges: Array[String] = []
var challenge_progress: Dictionary = {}
var last_daily_refresh: int = 0
var last_weekly_refresh: int = 0

## ---- سلسلة التحديات ----
var daily_streak: int = 0
var best_daily_streak: int = 0

## ---- ثوابت ----
const MAX_DAILY_CHALLENGES: int = 3
const MAX_WEEKLY_CHALLENGES: int = 2

## ---- تعريف التحديات المتاحة ----
var CHALLENGE_TEMPLATES: Array[Dictionary] = [
        {
                "id": "daily_trade_5", "name": "نشيط اليوم",
                "description": "أكمل 5 صفقات", "type": ChallengeType.TRADE_COUNT,
                "target": 5, "difficulty": ChallengeDifficulty.EASY,
                "frequency": ChallengeFrequency.DAILY, "xp_reward": 200, "balance_reward": 500.0
        },
        {
                "id": "daily_profit_500", "name": "أرباح سريعة",
                "description": "اجمع 500$ أرباح", "type": ChallengeType.PROFIT_TARGET,
                "target": 500.0, "difficulty": ChallengeDifficulty.MEDIUM,
                "frequency": ChallengeFrequency.DAILY, "xp_reward": 500, "balance_reward": 1000.0
        },
        {
                "id": "daily_no_loss", "name": "اليوم المثالي",
                "description": "أكمل 3 صفقات بدون خسارة", "type": ChallengeType.NO_LOSS_DAY,
                "target": 3, "difficulty": ChallengeDifficulty.HARD,
                "frequency": ChallengeFrequency.DAILY, "xp_reward": 800, "balance_reward": 2000.0
        },
        {
                "id": "daily_social", "name": "خبير المجتمع",
                "description": "انشر 2 منشورات في المنتدى", "type": ChallengeType.SOCIAL_POST,
                "target": 2, "difficulty": ChallengeDifficulty.EASY,
                "frequency": ChallengeFrequency.DAILY, "xp_reward": 150, "balance_reward": 300.0
        },
        {
                "id": "daily_short_profit", "name": "صائد الهبوط",
                "description": "حقق ربحاً من صفقة Short", "type": ChallengeType.SHORT_PROFIT,
                "target": 1, "difficulty": ChallengeDifficulty.MEDIUM,
                "frequency": ChallengeFrequency.DAILY, "xp_reward": 400, "balance_reward": 800.0
        },
        {
                "id": "daily_profit_2000", "name": "مغامر الأرباح",
                "description": "اجمع 2,000$ أرباح", "type": ChallengeType.PROFIT_TARGET,
                "target": 2000.0, "difficulty": ChallengeDifficulty.HARD,
                "frequency": ChallengeFrequency.DAILY, "xp_reward": 1000, "balance_reward": 3000.0
        },
        {
                "id": "daily_leverage_10x", "name": "ملك المخاطرة",
                "description": "حقق ربحاً برافعة 10x أو أعلى", "type": ChallengeType.LEVERAGE_TRADE,
                "target": 1, "difficulty": ChallengeDifficulty.MEDIUM,
                "frequency": ChallengeFrequency.DAILY, "xp_reward": 600, "balance_reward": 1500.0
        },
        {
                "id": "weekly_profit_10000", "name": "أسبوع ذهبي",
                "description": "اجمع 10,000$ أرباح هذا الأسبوع", "type": ChallengeType.PROFIT_TARGET,
                "target": 10000.0, "difficulty": ChallengeDifficulty.HARD,
                "frequency": ChallengeFrequency.WEEKLY, "xp_reward": 5000, "balance_reward": 10000.0
        },
        {
                "id": "weekly_win_rate_70", "name": "قناص دقيق",
                "description": "حقق نسبة ربح 70% على 20 صفقة", "type": ChallengeType.WIN_RATE,
                "target": 70, "difficulty": ChallengeDifficulty.EXPERT,
                "frequency": ChallengeFrequency.WEEKLY, "xp_reward": 8000, "balance_reward": 15000.0
        },
        {
                "id": "weekly_multi_symbol", "name": "متنوع المحفظة",
                "description": "تداول على 8 أدوات مختلفة", "type": ChallengeType.MULTI_SYMBOL,
                "target": 8, "difficulty": ChallengeDifficulty.MEDIUM,
                "frequency": ChallengeFrequency.WEEKLY, "xp_reward": 3000, "balance_reward": 5000.0
        },
        {
                "id": "weekly_streak_7", "name": "مستمر لا يتوقف",
                "description": "أكمل تحدي يومي لمدة 7 أيام متتالية", "type": ChallengeType.STREAK_TRADES,
                "target": 7, "difficulty": ChallengeDifficulty.EXPERT,
                "frequency": ChallengeFrequency.WEEKLY, "xp_reward": 10000, "balance_reward": 20000.0
        },
        {
                "id": "special_backtest", "name": "مختبر الاستراتيجيات",
                "description": "شغّل 3 باك تيست بنجاح", "type": ChallengeType.BACKTEST_RUN,
                "target": 3, "difficulty": ChallengeDifficulty.MEDIUM,
                "frequency": ChallengeFrequency.SPECIAL, "xp_reward": 2000, "balance_reward": 3000.0
        },
        {
                "id": "special_tutorial", "name": "طالب علم",
                "description": "أكمل 3 دروس تعليمية", "type": ChallengeType.TUTORIAL_COMPLETE,
                "target": 3, "difficulty": ChallengeDifficulty.EASY,
                "frequency": ChallengeFrequency.SPECIAL, "xp_reward": 1000, "balance_reward": 1000.0
        },
]

## ---- متغيرات تتبع التقدم ----
var today_trades: int = 0
var today_profit: float = 0.0
var today_winning_trades: int = 0
var today_symbols: Array[String] = []
var today_social_posts: int = 0
var today_backtests: int = 0
var today_tutorials: int = 0
var today_no_loss_count: int = 0
var today_has_loss: bool = false

## ============================================
## _ready() - التهيئة
## ============================================
func _ready() -> void:
        profile_manager = get_node_or_null("/root/ProfileManager")
        trading_manager = get_node_or_null("/root/TradingManager")

        if trading_manager:
                trading_manager.trade_closed.connect(_on_trade_closed)
        if profile_manager:
                profile_manager.level_up.connect(_on_level_up)

        _check_refresh_challenges()
        load_challenge_data()

        var check_timer := Timer.new()
        check_timer.wait_time = 3600.0
        check_timer.autostart = true
        check_timer.timeout.connect(_check_refresh_challenges)
        add_child(check_timer)

        print("[ChallengeManager] ✅ مدير التحديات جاهز | %d قالب تحدي" % CHALLENGE_TEMPLATES.size())

## ============================================
## فحص وتحديث التحديات
## ============================================
func _check_refresh_challenges() -> void:
        var now := Time.get_unix_time_from_system()

        if now - last_daily_refresh >= 86400:
                if _count_completed_daily() > 0:
                        daily_streak += 1
                        if daily_streak > best_daily_streak:
                                best_daily_streak = daily_streak
                else:
                        daily_streak = 0

                _refresh_daily_challenges()
                _reset_daily_tracking()
                last_daily_refresh = now
                daily_challenges_refreshed.emit(active_daily_challenges)
                streak_updated.emit(daily_streak, best_daily_streak)

        if now - last_weekly_refresh >= 86400 * 7:
                _refresh_weekly_challenges()
                last_weekly_refresh = now
                weekly_challenges_refreshed.emit(active_weekly_challenges)

## ============================================
## تجديد التحديات اليومية
## ============================================
func _refresh_daily_challenges() -> void:
        active_daily_challenges.clear()

        var daily_templates: Array[Dictionary] = []
        for template in CHALLENGE_TEMPLATES:
                if template["frequency"] == ChallengeFrequency.DAILY:
                        daily_templates.append(template)

        daily_templates.shuffle()

        var selected: Array[Dictionary] = []
        for t in daily_templates:
                if t["difficulty"] == ChallengeDifficulty.EASY and selected.size() == 0:
                        selected.append(t.duplicate(true))
                elif selected.size() < MAX_DAILY_CHALLENGES and t["difficulty"] != ChallengeDifficulty.EASY:
                        selected.append(t.duplicate(true))

        active_daily_challenges = selected

        for challenge in active_daily_challenges:
                challenge_progress[challenge["id"]] = {
                        "current": 0, "target": challenge["target"],
                        "start_time": Time.get_unix_time_from_system(), "completed": false
                }
                challenge_available.emit(challenge)

## ============================================
## تجديد التحديات الأسبوعية
## ============================================
func _refresh_weekly_challenges() -> void:
        active_weekly_challenges.clear()

        var weekly_templates: Array[Dictionary] = []
        for template in CHALLENGE_TEMPLATES:
                if template["frequency"] == ChallengeFrequency.WEEKLY:
                        weekly_templates.append(template)

        weekly_templates.shuffle()

        for i in range(min(MAX_WEEKLY_CHALLENGES, weekly_templates.size())):
                var challenge := weekly_templates[i].duplicate(true)
                active_weekly_challenges.append(challenge)

                challenge_progress[challenge["id"]] = {
                        "current": 0, "target": challenge["target"],
                        "start_time": Time.get_unix_time_from_system(), "completed": false
                }
                challenge_available.emit(challenge)

## ============================================
## إعادة تعيين التتبع اليومي
## ============================================
func _reset_daily_tracking() -> void:
        today_trades = 0
        today_profit = 0.0
        today_winning_trades = 0
        today_symbols.clear()
        today_social_posts = 0
        today_backtests = 0
        today_tutorials = 0
        today_no_loss_count = 0
        today_has_loss = false

## ============================================
## عند إغلاق صفقة - تتبع التقدم
## ============================================
func _on_trade_closed(trade, pnl: float, _reason: String) -> void:
        today_trades += 1

        if pnl > 0:
                today_profit += pnl
                today_winning_trades += 1
                today_no_loss_count += 1
        else:
                today_has_loss = true

        if not trade.symbol in today_symbols:
                today_symbols.append(trade.symbol)

        _update_challenge_progress("daily_trade_5", today_trades)
        _update_challenge_progress("daily_profit_500", today_profit)
        _update_challenge_progress("daily_profit_2000", today_profit)

        if not today_has_loss:
                _update_challenge_progress("daily_no_loss", today_no_loss_count)

        if trade.trade_type == TradeClass.TradeType.SHORT and pnl > 0:
                _update_challenge_progress("daily_short_profit", 1)

        if trade.leverage >= 10 and pnl > 0:
                _update_challenge_progress("daily_leverage_10x", 1)

        _update_challenge_progress("weekly_profit_10000", today_profit)
        _update_challenge_progress("weekly_multi_symbol", today_symbols.size())

## ============================================
## تحديث تقدم تحدي معين
## ============================================
func _update_challenge_progress(challenge_id: String, current_value: float) -> void:
        if not challenge_progress.has(challenge_id):
                return

        var progress: Dictionary = challenge_progress[challenge_id]
        if progress["completed"]:
                return

        var old_current: float = progress["current"]
        progress["current"] = current_value

        challenge_progress_updated.emit(challenge_id, int(current_value), int(progress["target"]))

        if current_value >= progress["target"] and old_current < progress["target"]:
                _complete_challenge(challenge_id)

## ============================================
## إكمال تحدي وتسليم المكافآت
## ============================================
func _complete_challenge(challenge_id: String) -> void:
        if challenge_id in completed_challenges:
                return

        completed_challenges.append(challenge_id)
        challenge_progress[challenge_id]["completed"] = true

        var challenge_data: Dictionary = {}
        for template in CHALLENGE_TEMPLATES:
                if template["id"] == challenge_id:
                        challenge_data = template
                        break

        if challenge_data.is_empty():
                return

        var rewards := {
                "xp": challenge_data.get("xp_reward", 0),
                "balance": challenge_data.get("balance_reward", 0.0),
                "challenge_name": challenge_data.get("name", "")
        }

        if profile_manager:
                profile_manager.add_experience(rewards["xp"])
                profile_manager.balance += rewards["balance"]

        challenge_completed.emit(challenge_id, rewards)

        NotificationManager.send_notification(
                "🏆 تحدي مكتمل!",
                "%s\n💰 مكافأة: $%.0f | ⭐ XP: %d" % [
                        challenge_data["name"], rewards["balance"], rewards["xp"]
                ],
                NP.SUCCESS
        )

        print("[ChallengeManager] 🏆 تحدي مكتمل: %s" % challenge_data["name"])
        save_challenge_data()

## ============================================
## تسجيل نشاط اجتماعي
## ============================================
func register_social_post() -> void:
        today_social_posts += 1
        _update_challenge_progress("daily_social", today_social_posts)

func register_backtest_run() -> void:
        today_backtests += 1
        _update_challenge_progress("special_backtest", today_backtests)

func register_tutorial_complete() -> void:
        today_tutorials += 1
        _update_challenge_progress("special_tutorial", today_tutorials)

## ============================================
## عد التحديات اليومية المكتملة
## ============================================
func _count_completed_daily() -> int:
        var count := 0
        for challenge in active_daily_challenges:
                if challenge["id"] in completed_challenges:
                        count += 1
        return count

## ============================================
## الحصول على كل التحديات النشطة
## ============================================
func get_all_active_challenges() -> Array[Dictionary]:
        var all: Array[Dictionary] = []

        for challenge in active_daily_challenges:
                var data := challenge.duplicate(true)
                if challenge_progress.has(data["id"]):
                        data["progress"] = challenge_progress[data["id"]]
                        data["is_completed"] = challenge_progress[data["id"]]["completed"]
                all.append(data)

        for challenge in active_weekly_challenges:
                var data := challenge.duplicate(true)
                if challenge_progress.has(data["id"]):
                        data["progress"] = challenge_progress[data["id"]]
                        data["is_completed"] = challenge_progress[data["id"]]["completed"]
                all.append(data)

        return all

## ============================================
## عند ترقية المستوى
## ============================================
func _on_level_up(new_level: int, _rewards: Dictionary) -> void:
        if new_level == 10 or new_level == 25 or new_level == 50:
                NotificationManager.send_notification(
                        "🎮 تحديات جديدة!",
                        "تم فتح تحديات خاصة بالمستوى %d" % new_level,
                        NP.INFO
                )

## ============================================
## حفظ/تحميل بيانات التحديات
## ============================================
func save_challenge_data() -> void:
        var data := {
                "completed_challenges": completed_challenges,
                "challenge_progress": challenge_progress,
                "daily_streak": daily_streak,
                "best_daily_streak": best_daily_streak,
                "last_daily_refresh": last_daily_refresh,
                "last_weekly_refresh": last_weekly_refresh
        }
        var file := FileAccess.open("user://challenge_data.json", FileAccess.WRITE)
        if file:
                file.store_string(JSON.stringify(data, "\t"))
                file.close()

func load_challenge_data() -> void:
        if not FileAccess.file_exists("user://challenge_data.json"):
                return
        var file := FileAccess.open("user://challenge_data.json", FileAccess.READ)
        if file == null:
                return
        var json := JSON.new()
        if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
                var data: Dictionary = json.data
                completed_challenges = data.get("completed_challenges", [])
                challenge_progress = data.get("challenge_progress", {})
                daily_streak = int(data.get("daily_streak", 0))
                best_daily_streak = int(data.get("best_daily_streak", 0))
                last_daily_refresh = int(data.get("last_daily_refresh", 0))
                last_weekly_refresh = int(data.get("last_weekly_refresh", 0))
        file.close()
