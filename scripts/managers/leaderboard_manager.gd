## ============================================
## LeaderboardManager.gd - مدير لوحة المتصدرين
## يرتب اللاعبين حسب الأرباح والمستوى والأداء
## ============================================
extends Node

## ---- إشارات ----
signal leaderboard_updated(category: String, entries: Array[Dictionary])
signal player_rank_updated(category: String, rank: int, total: int)

## ---- بيانات المتصدرين ----
## في الإصدار الحقيقي: تُجلب من Firebase أو خادم
var local_leaderboard: Array[Dictionary] = []
var simulated_players: Array[Dictionary] = []

## ---- مرجع ProfileManager ----
var profile_manager: Node

## ============================================
## التهيئة
## ============================================
func _ready() -> void:
        profile_manager = get_node_or_null("/root/ProfileManager")
        _generate_simulated_players()

## ============================================
## توليد لاعبين وهميين (للعرض)
## في الإصدار الحقيقي: استبدل ببيانات من الخادم
## ============================================
func _generate_simulated_players() -> void:
        var fake_names := [
                "CryptoWolf", "TradingKing", "DiamondHands",
                "StockMaster", "MoonTrader", "BearHunter",
                "BullRider", "SatoshiFan", "WallStPro", "DeFiLord"
        ]
        
        for i in range(10):
                var fake_level := randi_range(5, 80)
                var fake_balance := randf_range(50000.0, 5000000.0)
                var fake_profit := fake_balance - 100000.0
                simulated_players.append({
                        "player_id": "fake_%d" % i,
                        "player_name": fake_names[i],
                        "level": fake_level,
                        "balance": fake_balance,
                        "total_profit": fake_profit,
                        "win_rate": randf_range(30.0, 80.0),
                        "best_streak": randi_range(3, 20),
                        "total_volume": fake_balance * randf_range(2.0, 10.0),
                        "badges_count": randi_range(1, 8),
                        "is_real_player": false
                })

## ============================================
## الحصول على لوحة المتصدرين حسب الفئة
## ============================================
func get_leaderboard(
        category: int,
        limit: int = 50
) -> Array[Dictionary]:
        ## تجميع اللاعبين الحقيقي والوهميين
        var all_players: Array[Dictionary] = []
        
        ## إضافة اللاعب الحقيقي
        if profile_manager:
                var stats: Dictionary = profile_manager.get_all_stats()
                all_players.append({
                        "player_id": profile_manager.player_id,
                        "player_name": profile_manager.player_name,
                        "level": profile_manager.level,
                        "balance": profile_manager.balance,
                        "total_profit": stats.get("total_profit", 0.0),
                        "win_rate": stats.get("win_rate", 0.0),
                        "best_streak": profile_manager.best_streak,
                        "total_volume": profile_manager.total_volume_traded,
                        "badges_count": profile_manager.earned_badges.size(),
                        "is_real_player": true
                })
        
        ## إضافة اللاعبين الوهميين
        for player in simulated_players:
                all_players.append(player.duplicate(true))
        
        ## الترتيب حسب الفئة
        match category:
                LeaderboardCategory.BALANCE:
                        all_players.sort_custom(func(a, b): return a["balance"] > b["balance"])
                LeaderboardCategory.PROFIT:
                        all_players.sort_custom(func(a, b): return a["total_profit"] > b["total_profit"])
                LeaderboardCategory.WIN_RATE:
                        all_players.sort_custom(func(a, b): return a["win_rate"] > b["win_rate"])
                LeaderboardCategory.LEVEL:
                        all_players.sort_custom(func(a, b): return a["level"] > b["level"])
                LeaderboardCategory.STREAK:
                        all_players.sort_custom(func(a, b): return a["best_streak"] > b["best_streak"])
                LeaderboardCategory.VOLUME:
                        all_players.sort_custom(func(a, b): return a["total_volume"] > b["total_volume"])
        
        ## إضافة الترتيب
        for i in range(all_players.size()):
                all_players[i]["rank"] = i + 1
        
        ## إيجاد ترتيب اللاعب الحقيقي
        for player in all_players:
                if player.get("is_real_player", false):
                        var cat_names: Array = ["BALANCE", "PROFIT", "WIN_RATE", "LEVEL", "STREAK", "VOLUME"]
                        var cat_name: String = cat_names[category] if category < cat_names.size() else "BALANCE"
                        player_rank_updated.emit(cat_name, player["rank"], all_players.size())
                        break
        
        return all_players.slice(0, limit)

## ============================================
## تحديث لوحة المتصدرين وإرسالها
## ============================================
func refresh_leaderboard(category: int = LeaderboardCategory.BALANCE) -> void:
        var entries := get_leaderboard(category)
        var cat_names: Array = ["BALANCE", "PROFIT", "WIN_RATE", "LEVEL", "STREAK", "VOLUME"]
        var cat_name: String = cat_names[category] if category < cat_names.size() else "BALANCE"
        leaderboard_updated.emit(cat_name, entries)
