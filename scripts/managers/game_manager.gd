## ============================================
## GameManager.gd - المدير العام للمشروع (AutoLoad)
## يربط كل الأنظمة معاً ويتحكم في دورة حياة اللعبة
## ============================================
extends Node

const TradeClass = preload("res://scripts/data_models/trade.gd")
const NP = preload("res://scripts/enums/notification_priority.gd")
const ForumPostClass = preload("res://scripts/data_models/forum_post.gd")

## ---- مراجع الأنظمة ----
@onready var profile_manager: Node = get_node_or_null("/root/ProfileManager")
@onready var portfolio_manager: Node = get_node_or_null("/root/PortfolioManager")
@onready var trading_manager: Node = get_node_or_null("/root/TradingManager")
@onready var data_manager: Node = get_node_or_null("/root/DataManager")
@onready var notification_manager: Node = get_node_or_null("/root/NotificationManager")
@onready var forum_manager: Node = get_node_or_null("/root/ForumManager")
@onready var leaderboard_manager: Node = get_node_or_null("/root/LeaderboardManager")
@onready var chart_manager: Node = get_node_or_null("/root/ChartManager")
@onready var sentiment_analyzer: Node = get_node_or_null("/root/SentimentAnalyzer")
@onready var challenge_manager: Node = get_node_or_null("/root/ChallengeManager")
@onready var backtesting_engine: Node = get_node_or_null("/root/BacktestingEngine")
@onready var tutorial_manager: Node = get_node_or_null("/root/TutorialManager")
@onready var orderbook_manager: Node = get_node_or_null("/root/OrderBookManager")
@onready var firebase_manager: Node = get_node_or_null("/root/FirebaseManager")

## ---- حالة اللعبة ----
enum GameState {
        MAIN_MENU,
        TRADING,
        PORTFOLIO,
        PROFILE,
        FORUM,
        LEADERBOARD,
        CHARTS,
        CHALLENGES,
        BACKTESTING,
        TUTORIALS,
        ORDERBOOK,
        SETTINGS
}

var current_state: GameState = GameState.MAIN_MENU
var is_game_paused: bool = false

## ============================================
## _ready() - تهيئة اللعبة بالكامل
## ============================================
func _ready() -> void:
        print("╔══════════════════════════════════════════════════╗")
        print("║   🎮 Trading Simulator Game - Godot 4            ║")
        print("║   📈 محاكاة تداول الأسهم والكريبتو               ║")
        print("║   🕯️ شموع | 📊 تحليلات | 🎯 تحديات | 📚 تعليم   ║")
        print("╚══════════════════════════════════════════════════╝")
        
        _validate_systems()
        _connect_systems()
        
        ## تحميل بيانات اللاعب المحفوظة
        profile_manager.load_profile()
        
        ## بدء جلب البيانات الحية
        data_manager.start_live_updates()
        
        ## حفظ تلقائي كل 30 ثانية
        var save_timer := Timer.new()
        save_timer.wait_time = 30.0
        save_timer.autostart = true
        save_timer.timeout.connect(_auto_save)
        add_child(save_timer)
        
        ## مرجب
        NotificationManager.send_notification(
                "👋 أهلاً بك!",
                "مرحباً %s | المستوى %d | الرصيد: $%.2f" % [
                        profile_manager.player_name,
                        profile_manager.level,
                        profile_manager.balance
                ],
                NP.INFO
        )

## ============================================
## التحقق من وجود كل الأنظمة
## ============================================
func _validate_systems() -> void:
        var systems := [
                ["ProfileManager", profile_manager],
                ["PortfolioManager", portfolio_manager],
                ["TradingManager", trading_manager],
                ["DataManager", data_manager],
                ["NotificationManager", notification_manager],
                ["ForumManager", forum_manager],
                ["LeaderboardManager", leaderboard_manager],
                ["ChartManager", chart_manager],
                ["SentimentAnalyzer", sentiment_analyzer],
                ["ChallengeManager", challenge_manager],
                ["BacktestingEngine", backtesting_engine],
                ["TutorialManager", tutorial_manager],
                ["OrderBookManager", orderbook_manager],
                ["FirebaseManager", firebase_manager]
        ]
        
        for sys_name in systems:
                if sys_name[1] == null:
                        push_error("[GameManager] ❌ النظام غير موجود: %s" % sys_name[0])
                else:
                        print("[GameManager] ✅ %s جاهز" % sys_name[0])

## ============================================
## ربط الإشارات بين الأنظمة
## ============================================
func _connect_systems() -> void:
        ## أنظمة الأساسية
        trading_manager.trade_closed.connect(_on_trade_closed)
        trading_manager.trade_liquidated.connect(_on_trade_liquidated)
        profile_manager.badge_earned.connect(_on_badge_earned)
        profile_manager.level_up.connect(_on_level_up)
        data_manager.price_updated.connect(_on_price_updated)
        portfolio_manager.margin_call_triggered.connect(_on_margin_call)
        
        ## ===== الأنظمة الجديدة =====
        
        ## دفتر الأوامر
        data_manager.orderbook_received.connect(_on_orderbook_received)
        
        ## Firebase
        if firebase_manager:
                firebase_manager.login_success.connect(_on_firebase_login)
        
        ## التحديات
        if challenge_manager:
                challenge_manager.challenge_completed.connect(_on_challenge_completed)
        
        ## الباك تيست
        if backtesting_engine:
                backtesting_engine.backtest_completed.connect(_on_backtest_completed)
        
        ## التعليم
        if tutorial_manager:
                tutorial_manager.tutorial_completed.connect(_on_tutorial_completed)
        
        ## تحليل المشاعر
        if sentiment_analyzer:
                sentiment_analyzer.trend_alert.connect(_on_sentiment_trend)

## ============================================
## عند إغلاق صفقة
## ============================================
func _on_trade_closed(trade, pnl: float, reason: String) -> void:
        ## نشر تلقائي في المنتدى للصفقات الكبيرة
        if pnl > 1000.0:
                var direction := "LONG 🟢" if trade.trade_type == TradeClass.TradeType.LONG else "SHORT 🔴"
                var post_content := "🎯 صفقة %s على %s\n💰 الربح: $%.2f (+%.1f%%)\n⚡ رافعة: %dx\n🤖 %s" % [
                        direction, trade.symbol, pnl, trade.pnl_percentage, trade.leverage, reason
                ]
                forum_manager.create_post(
                        profile_manager.player_id,
                        profile_manager.player_name,
                        post_content,
                        ForumPostClass.PostType.TRADE_RESULT,
                        trade.symbol
                )
        
        ## تحديث لوحة المتصدرين
        leaderboard_manager.refresh_leaderboard()
        
        ## مزامنة Firebase
        if firebase_manager and firebase_manager.is_logged_in:
                firebase_manager.sync_all_leaderboards()

## ============================================
## عند تصفية صفقة
## ============================================
func _on_trade_liquidated(trade, loss: float) -> void:
        NotificationManager.send_notification(
                "💥 تمت التصفية!",
                "صفقة %s @ رافعة %dx\nالخسارة: $%.2f" % [trade.symbol, trade.leverage, loss],
                NP.CRITICAL
        )

## ============================================
## عند ربح وسام جديد
## ============================================
func _on_badge_earned(badge_id: String, badge_name: String) -> void:
        NotificationManager.send_notification(
                "🏅 وسام جديد!",
                "تهانينا! حصلت على وسام: %s" % badge_name,
                NP.SUCCESS
        )

## ============================================
## عند ترقية المستوى
## ============================================
func _on_level_up(new_level: int, rewards: Dictionary) -> void:
        var msg := "ترقية إلى المستوى %d!" % new_level
        if rewards.get("balance_bonus", 0.0) > 0:
                msg += "\n💰 مكافأة: $%.0f" % rewards["balance_bonus"]
        if rewards.get("title", "") != "":
                msg += "\n👑 لقب جديد: %s" % rewards["title"]
        
        NotificationManager.send_notification(
                "🎉 ترقية!",
                msg,
                NP.SUCCESS
        )

## ============================================
## عند تحديث الأسعار
## ============================================
func _on_price_updated(symbol: String, price: float, _timestamp: int) -> void:
        pass

## ============================================
## عند نداء هامش
## ============================================
func _on_margin_call(trade, free_margin: float) -> void:
        NotificationManager.send_notification(
                "🚨 نداء هامش!",
                "صفقة %s | الهامش الحر: $%.2f\nسعر التصفية: $%.2f" % [
                        trade.symbol, free_margin, trade.liquidation_price
                ],
                NP.HIGH
        )

## ===== الأنظمة الجديدة: معالجات الإشارات =====

## استقبال بيانات دفتر الأوامر
func _on_orderbook_received(symbol: String, bids: Array, asks: Array) -> void:
        if orderbook_manager:
                orderbook_manager.process_orderbook_data(symbol, bids, asks)

## عند تسجيل الدخول عبر Firebase
func _on_firebase_login(user_data: Dictionary) -> void:
        print("[GameManager] ✅ Firebase: %s" % user_data.get("email", "زائر"))
        firebase_manager.fetch_leaderboard("total_profit")
        firebase_manager.fetch_leaderboard("balance")

## عند إكمال تحدي
func _on_challenge_completed(challenge_id: String, rewards: Dictionary) -> void:
        if firebase_manager and firebase_manager.is_logged_in:
                firebase_manager.sync_all_leaderboards()

## عند إكمال باك تيست
func _on_backtest_completed(results: Dictionary) -> void:
        if challenge_manager:
                challenge_manager.register_backtest_run()

## عند إكمال درس تعليمي
func _on_tutorial_completed(tutorial_id: String, xp_earned: int) -> void:
        if firebase_manager and firebase_manager.is_logged_in:
                firebase_manager.update_leaderboard_entry("level", float(profile_manager.level))

## عند كشف اتجاه مشاعر
func _on_sentiment_trend(symbol: String, direction: String, strength: float) -> void:
        NotificationManager.send_notification(
                "📊 اتجاه مشاعر %s" % symbol,
                "%s | القوة: %.0f%%" % [direction, strength * 100],
                NP.INFO
        )

## ============================================
## حفظ تلقائي
## ============================================
func _auto_save() -> void:
        if profile_manager:
                profile_manager.save_profile()
        if portfolio_manager:
                portfolio_manager.save_portfolio()
        if challenge_manager:
                challenge_manager.save_challenge_data()
        if firebase_manager and firebase_manager.is_logged_in:
                firebase_manager.sync_all_leaderboards()
        print("[GameManager] 💾 حفظ تلقائي")

## ============================================
## تغيير حالة اللعبة
## ============================================
func change_state(new_state: GameState) -> void:
        current_state = new_state
        print("[GameManager] 🎮 الحالة: %s" % GameState.keys()[new_state])
