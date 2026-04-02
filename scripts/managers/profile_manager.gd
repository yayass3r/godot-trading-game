## ============================================
## ProfileManager.gd - مدير الملف الشخصي والتطور
## يُدير مستوى اللاعب والخبرة والأوسمة والإحصائيات
## ============================================
extends Node

## ---- إشارات (Signals) ----
signal balance_updated(new_balance: float, delta: float)
signal experience_gained(amount: int, total_xp: int)
signal level_up(new_level: int, rewards: Dictionary)
signal badge_earned(badge_id: String, badge_name: String)
signal stats_updated(stats: Dictionary)

## ---- ثوابت المستويات ----
## خبرة كل مستوى تزداد بشكل أُسّي
const BASE_XP_PER_LEVEL: int = 1000
const XP_MULTIPLIER: float = 1.5
const MAX_LEVEL: int = 100

## ---- متغيرات اللاعب ----
var player_name: String = "متداول جديد"
var player_id: String = ""
var level: int = 1
var total_xp: int = 0
var current_level_xp: int = 0
var xp_to_next_level: int = BASE_XP_PER_LEVEL
var avatar_path: String = ""
var created_at: int = 0
var last_login: int = 0

## ---- الممتلكات (Properties) ----
var balance: float = 100000.0 :  ## الرصيد الابتدائي 100,000$
        set(value):
                var delta: float = value - balance
                balance = value
                balance_updated.emit(balance, delta)
                _check_balance_badges()

var total_trades: int = 0
var winning_trades: int = 0
var losing_trades: int = 0
var biggest_win: float = 0.0
var biggest_loss: float = 0.0
var total_profit: float = 0.0
var total_fees_paid: float = 0.0
var current_streak: int = 0  ## سلسلة صفقات رابحة متتالية
var best_streak: int = 0
var total_volume_traded: float = 0.0

## ---- الأوسمة المكتسبة ----
var earned_badges: Array[String] = []

## ---- تعريف الأوسمة الكاملة ----
## كل وسام له شروط محددة للحصول عليه
var ALL_BADGES: Dictionary = {
        "first_trade": {
                "name": "أول صفقة",
                "description": "أكمل أول صفقة لك",
                "icon": "award_first",
                "condition": func(): return total_trades >= 1
        },
        "ten_trades": {
                "name": "محارب الأسواق",
                "description": "أكمل 10 صفقات",
                "icon": "award_ten",
                "condition": func(): return total_trades >= 10
        },
        "whale": {
                "name": "حوت الكريبتو",
                "description": "تداول بأكثر من 500,000$ حجم إجمالي",
                "icon": "award_whale",
                "condition": func(): return total_volume_traded >= 500000.0
        },
        "leverage_king": {
                "name": "ملك الرافعة المالية",
                "description": "استخدم رافعة 100x وحقق ربحاً",
                "icon": "award_leverage",
                "condition": func(): return true  ## يُتحقق في close_trade
        },
        "streak_5": {
                "name": "خمسة متتالية",
                "description": "فز بـ 5 صفقات متتالية",
                "icon": "award_streak5",
                "condition": func(): return best_streak >= 5
        },
        "streak_10": {
                "name": "لا يُوقفني أحد",
                "description": "فز بـ 10 صفقات متتالية",
                "icon": "award_streak10",
                "condition": func(): return best_streak >= 10
        },
        "millionaire": {
                "name": "مليونير اللعبة",
                "description": "وصل رصيدك إلى مليون دولار",
                "icon": "award_million",
                "condition": func(): return balance >= 1000000.0
        },
        "comeback_kid": {
                "name": "صانع العودة",
                "description": "استرد رصيدك بعد أن انخفض 50%",
                "icon": "award_comeback",
                "condition": func(): return true  ## يُتحقق منطقياً
        },
        "high_roller": {
                "name": "المخاطر الكبيرة",
                "description": "افتح صفقة بحجم أكثر من 50,000$",
                "icon": "award_highroller",
                "condition": func(): return true  ## يُتحقق في open_trade
        },
        "profit_100k": {
                "name": "صائد المئة ألف",
                "description": "اجمع أكثر من 100,000$ أرباح إجمالية",
                "icon": "award_profit100k",
                "condition": func(): return total_profit >= 100000.0
        }
}

## ============================================
## _ready() - التهيئة عند بدء المشهد
## ============================================
func _ready() -> void:
        if player_id.is_empty():
                player_id = str(Time.get_ticks_msec())
        created_at = Time.get_unix_time_from_system()
        last_login = Time.get_unix_time_from_system()
        ## load_profile() is called by GameManager._ready() after all autoloads are set up

## ============================================
## حساب الخبرة المطلوبة للمستوى التالي
## XP(level) = BASE_XP × MULTIPLIER^(level-1)
## ============================================
func get_xp_for_level(lvl: int) -> int:
        return int(BASE_XP_PER_LEVEL * pow(XP_MULTIPLIER, lvl - 1))

## ============================================
## إضافة خبرة جديدة والتحقق من ترقية المستوى
## ============================================
func add_experience(amount: int) -> void:
        total_xp += amount
        current_level_xp += amount
        experience_gained.emit(amount, total_xp)
        
        ## التحقق من المستويات المتعددة (قد يرتقي أكثر من مستوى دفعة واحدة)
        while current_level_xp >= xp_to_next_level and level < MAX_LEVEL:
                current_level_xp -= xp_to_next_level
                level += 1
                xp_to_next_level = get_xp_for_level(level)
                var rewards: Dictionary = _calculate_level_rewards(level)
                level_up.emit(level, rewards)
                print("[ProfileManager] 🎉 ترقية! المستوى: %d | مكافأة: %s" % [level, str(rewards)])
        
        _check_all_badges()

## ============================================
## حساب مكافآت كل مستوى
## ============================================
func _calculate_level_rewards(lvl: int) -> Dictionary:
        var rewards := {"balance_bonus": 0.0, "leverage_unlock": 0, "title": ""}
        
        ## مكافأة رصيد كل 5 مستويات
        if lvl % 5 == 0:
                rewards["balance_bonus"] = lvl * 1000.0
                balance += rewards["balance_bonus"]
        
        ## فتح رافعات أعلى حسب المستوى
        if lvl >= 50:
                rewards["leverage_unlock"] = 100
        elif lvl >= 30:
                rewards["leverage_unlock"] = 50
        elif lvl >= 20:
                rewards["leverage_unlock"] = 25
        elif lvl >= 10:
                rewards["leverage_unlock"] = 10
        elif lvl >= 5:
                rewards["leverage_unlock"] = 5
        
        ## ألقاب خاصة
        var titles := {
                10: "مبتدئ واعِد", 20: "متداول محترف", 30: "محلل مالي",
                50: "أسطورة السوق", 75: "حوت القرش", 100: "إمبراطور التداول"
        }
        if lvl in titles:
                rewards["title"] = titles[lvl]
        
        return rewards

## ============================================
## تحديث الإحصائيات بعد إغلاق صفقة
## تُستدعى من TradingManager عند إغلاق أي صفقة
## ============================================
func update_trade_stats(trade_result: Dictionary) -> void:
        var pnl: float = trade_result.get("pnl", 0.0)
        var fees: float = trade_result.get("fees", 0.0)
        var volume: float = trade_result.get("volume", 0.0)
        var leverage_used: int = trade_result.get("leverage", 1)
        
        total_trades += 1
        total_fees_paid += fees
        total_volume_traded += volume
        
        if pnl > 0:
                winning_trades += 1
                current_streak += 1
                total_profit += pnl
                if pnl > biggest_win:
                        biggest_win = pnl
                if current_streak > best_streak:
                        best_streak = current_streak
                
                ## إضافة خبرة بناءً على حجم الربح
                var xp_earned: int = int(abs(pnl) * 0.5) + 50  ## 50 XP أساسي + 0.5 XP لكل دولار ربح
                if leverage_used >= 50:
                        xp_earned = int(xp_earned * 1.5)  ## مكافأة إضافية للرافعة العالية
                add_experience(xp_earned)
                
        else:
                losing_trades += 1
                current_streak = 0
                if abs(pnl) > biggest_loss:
                        biggest_loss = abs(pnl)
                
                ## خبرة أقل للصفقات الخاسرة (للتعلم)
                add_experience(10)
        
        ## التحقق من أوسمة الصفقات الكبيرة
        if volume >= 50000.0 and "high_roller" not in earned_badges:
                _earn_badge("high_roller")
        if leverage_used >= 100 and pnl > 0 and "leverage_king" not in earned_badges:
                _earn_badge("leverage_king")
        
        ## إرسال إشعار بتحديث الإحصائيات
        var stats := get_all_stats()
        stats_updated.emit(stats)

## ============================================
## الحصول على كل الإحصائيات كقاموس
## ============================================
func get_all_stats() -> Dictionary:
        var win_rate: float = 0.0
        if total_trades > 0:
                win_rate = (float(winning_trades) / float(total_trades)) * 100.0
        
        var avg_profit: float = 0.0
        if winning_trades > 0:
                avg_profit = total_profit / float(winning_trades)
        
        var roi_percentage: float = 0.0
        if (100000.0 - total_profit + total_fees_paid) > 0:
                roi_percentage = (total_profit / 100000.0) * 100.0
        
        return {
                "player_name": player_name,
                "level": level,
                "balance": balance,
                "total_trades": total_trades,
                "winning_trades": winning_trades,
                "losing_trades": losing_trades,
                "win_rate": win_rate,
                "biggest_win": biggest_win,
                "biggest_loss": biggest_loss,
                "total_profit": total_profit,
                "current_streak": current_streak,
                "best_streak": best_streak,
                "avg_profit": avg_profit,
                "roi_percentage": roi_percentage,
                "total_volume": total_volume_traded,
                "total_fees": total_fees_paid,
                "badges_count": earned_badges.size()
        }

## ============================================
## التحقق من جميع الأوسمة وربح الأوسمة الجديدة
## ============================================
func _check_all_badges() -> void:
        for badge_id in ALL_BADGES:
                if badge_id not in earned_badges:
                        var badge_data: Dictionary = ALL_BADGES[badge_id]
                        var condition: Callable = badge_data["condition"]
                        if condition.is_valid() and condition.call():
                                _earn_badge(badge_id)

## ============================================
## فحص أوسمة الرصيد
## ============================================
func _check_balance_badges() -> void:
        if balance >= 1000000.0 and "millionaire" not in earned_badges:
                _earn_badge("millionaire")

## ============================================
## ربح وسام جديد
## ============================================
func _earn_badge(badge_id: String) -> void:
        if badge_id in ALL_BADGES and badge_id not in earned_badges:
                earned_badges.append(badge_id)
                var badge_name: String = ALL_BADGES[badge_id]["name"]
                badge_earned.emit(badge_id, badge_name)
                print("[ProfileManager] 🏅 وسام جديد: %s" % badge_name)

## ============================================
## نسبة التقدم للمستوى الحالي (0.0 - 1.0)
## ============================================
func get_level_progress() -> float:
        if xp_to_next_level <= 0:
                return 1.0
        return float(current_level_xp) / float(xp_to_next_level)

## ============================================
## الحصول على الرافعة القصوى المتاحة حسب المستوى
## ============================================
func get_max_leverage() -> int:
        if level >= 50: return 100
        if level >= 30: return 50
        if level >= 20: return 25
        if level >= 10: return 10
        if level >= 5: return 5
        return 1

## ============================================
## حفظ الملف الشخصي في ملف محلي
## ============================================
func save_profile() -> void:
        var data := {
                "player_id": player_id,
                "player_name": player_name,
                "level": level,
                "total_xp": total_xp,
                "current_level_xp": current_level_xp,
                "balance": balance,
                "total_trades": total_trades,
                "winning_trades": winning_trades,
                "losing_trades": losing_trades,
                "biggest_win": biggest_win,
                "biggest_loss": biggest_loss,
                "total_profit": total_profit,
                "total_fees_paid": total_fees_paid,
                "current_streak": current_streak,
                "best_streak": best_streak,
                "total_volume_traded": total_volume_traded,
                "earned_badges": earned_badges,
                "avatar_path": avatar_path,
                "created_at": created_at,
                "last_login": last_login
        }
        
        var save_path := "user://profile_data.json"
        var file := FileAccess.open(save_path, FileAccess.WRITE)
        if file:
                file.store_string(JSON.stringify(data, "\t"))
                file.close()
                print("[ProfileManager] 💾 تم الحفظ بنجاح")
        else:
                push_error("[ProfileManager] ❌ فشل الحفظ: %s" % save_path)

## ============================================
## إعادة تعيين الملف الشخصي
## ============================================
func reset_profile() -> void:
        level = 1
        total_xp = 0
        current_level_xp = 0
        xp_to_next_level = get_xp_for_level(1)
        balance = 100000.0
        total_trades = 0
        winning_trades = 0
        losing_trades = 0
        biggest_win = 0.0
        biggest_loss = 0.0
        total_profit = 0.0
        total_fees_paid = 0.0
        current_streak = 0
        best_streak = 0
        total_volume_traded = 0.0
        earned_badges.clear()
        save_profile()

## ============================================
## تحميل الملف الشخصي من ملف محلي
## ============================================
func load_profile() -> void:
        var load_path := "user://profile_data.json"
        if not FileAccess.file_exists(load_path):
                print("[ProfileManager] 📝 ملف جديد - سيتم إنشاء ملف شخصي")
                return
        
        var file := FileAccess.open(load_path, FileAccess.READ)
        if file == null:
                push_error("[ProfileManager] ❌ فشل التحميل")
                return
        
        var json := JSON.new()
        var err := json.parse(file.get_as_text())
        file.close()
        
        if err != OK:
                push_error("[ProfileManager] ❌ خطأ في تحليل JSON")
                return
        
        var data: Variant = json.data
        if data is Dictionary:
                player_id = str(data.get("player_id", player_id))
                player_name = str(data.get("player_name", player_name))
                level = int(data.get("level", level))
                total_xp = int(data.get("total_xp", total_xp))
                current_level_xp = int(data.get("current_level_xp", current_level_xp))
                xp_to_next_level = get_xp_for_level(level)
                balance = float(data.get("balance", balance))
                total_trades = int(data.get("total_trades", total_trades))
                winning_trades = int(data.get("winning_trades", winning_trades))
                losing_trades = int(data.get("losing_trades", losing_trades))
                biggest_win = float(data.get("biggest_win", biggest_win))
                biggest_loss = float(data.get("biggest_loss", biggest_loss))
                total_profit = float(data.get("total_profit", total_profit))
                total_fees_paid = float(data.get("total_fees_paid", total_fees_paid))
                current_streak = int(data.get("current_streak", current_streak))
                best_streak = int(data.get("best_streak", best_streak))
                total_volume_traded = float(data.get("total_volume_traded", total_volume_traded))
                avatar_path = str(data.get("avatar_path", avatar_path))
                created_at = int(data.get("created_at", created_at))
                last_login = Time.get_unix_time_from_system()
                
                var badges: Variant = data.get("earned_badges", [])
                if badges is Array:
                        earned_badges = badges as Array[String]
                
                print("[ProfileManager] 📂 تم التحميل: المستوى %d | الرصيد $%.2f" % [level, balance])
