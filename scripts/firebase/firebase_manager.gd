## ============================================
## FirebaseManager.gd - مدير Firebase
## يوفر مصادقة المستخدمين ومتصدرين حقيقيين عبر الإنترنت
## يستخدم Firebase Realtime Database و Authentication
## ============================================
extends Node

## ---- إشارات (Signals) ----
signal auth_state_changed(user_id: String, is_logged_in: bool)
signal login_success(user_data: Dictionary)
signal login_failed(error: String)
signal signup_success(user_data: Dictionary)
signal signup_failed(error: String)
signal leaderboard_fetched(category: String, entries: Array[Dictionary])
signal leaderboard_updated(entry: Dictionary)
signal cloud_save_success()
signal cloud_save_failed(error: String)
signal cloud_load_success(data: Dictionary)
signal cloud_load_failed(error: String)
signal achievement_synced(achievements: Array[Dictionary])
signal online_count_updated(count: int)

## ---- إعدادات Firebase ----
## يجب استبدال هذه بقيم مشروعك الحقيقية
var firebase_config: Dictionary = {
        "api_key": "",
        "auth_domain": "",
        "database_url": "",
        "project_id": "",
        "storage_bucket": "",
        "messaging_sender_id": "",
        "app_id": ""
}

## ---- حالة المصادقة ----
var current_user: Dictionary = {}
var is_logged_in: bool = false
var auth_token: String = ""

## ---- مراجع ----
var profile_manager: Node
var leaderboard_manager: Node

## ---- بيانات المتصدرين ----
var cached_leaderboards: Dictionary = {}
var leaderboard_update_timer: Timer

## ---- HTTPRequest ----
var http_auth: HTTPRequest
var http_database: HTTPRequest

## ---- ثوابت ----
const LEADERBOARD_CACHE_DURATION: float = 300.0  ## 5 دقائق
const MAX_LEADERBOARD_ENTRIES: int = 100
const CLOUD_SAVE_INTERVAL: float = 120.0  ## حفظ سحابي كل دقيقتين

## ============================================
## _ready() - التهيئة
## ============================================
func _ready() -> void:
        profile_manager = get_node_or_null("/root/ProfileManager")
        leaderboard_manager = get_node_or_null("/root/LeaderboardManager")

        ## إنشاء عقد HTTP
        http_auth = HTTPRequest.new()
        http_auth.timeout = 15.0
        add_child(http_auth)

        http_database = HTTPRequest.new()
        http_database.timeout = 15.0
        add_child(http_database)

        ## مؤقت تحديث المتصدرين
        leaderboard_update_timer = Timer.new()
        leaderboard_update_timer.wait_time = LEADERBOARD_CACHE_DURATION
        leaderboard_update_timer.autostart = true
        leaderboard_update_timer.timeout.connect(_refresh_leaderboards)
        add_child(leaderboard_update_timer)

        ## مؤقت الحفظ السحابي
        var cloud_timer := Timer.new()
        cloud_timer.wait_time = CLOUD_SAVE_INTERVAL
        cloud_timer.autostart = is_logged_in
        cloud_timer.timeout.connect(_auto_cloud_save)
        add_child(cloud_timer)

        print("[FirebaseManager] ✅ مدير Firebase جاهز")

## ============================================
## ===== المصادقة (Authentication) =====
## ============================================

## تسجيل الدخول بالبريد الإلكتروني
func login_with_email(email: String, password: String) -> void:
        if firebase_config["api_key"].is_empty():
                login_failed.emit("Firebase غير مهيأ. أضف بيانات المشروع في FirebaseManager.gd")
                return

        var url: String = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=%s" % firebase_config["api_key"]
        var body := JSON.stringify({
                "email": email,
                "password": password,
                "returnSecureToken": true
        })

        http_auth.request_completed.connect(_on_login_response)
        var err := http_auth.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
        if err != OK:
                login_failed.emit("فشل الاتصال بالخادم")

func _on_login_response(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
        http_auth.request_completed.disconnect(_on_login_response)

        if result != HTTPRequest.RESULT_SUCCESS:
                login_failed.emit("فشل في الاتصال")
                return

        var json := JSON.new()
        if json.parse(body.get_string_from_utf8()) != OK:
                login_failed.emit("فشل في تحليل الاستجابة")
                return

        var data: Variant = json.data
        if data is Dictionary and data.has("idToken"):
                current_user = {
                        "uid": data.get("localId", ""),
                        "email": data.get("email", ""),
                        "display_name": data.get("displayName", ""),
                        "token": data.get("idToken", "")
                }
                auth_token = data.get("idToken", "")
                is_logged_in = true

                ## تحديث بيانات الملف الشخصي
                if profile_manager:
                        profile_manager.player_id = current_user["uid"]

                login_success.emit(current_user)
                auth_state_changed.emit(current_user["uid"], true)
                print("[FirebaseManager] ✅ تم تسجيل الدخول: %s" % current_user["email"])
        else:
                var error_msg := "فشل تسجيل الدخول"
                if data is Dictionary and data.has("error"):
                        error_msg = data["error"].get("message", error_msg)
                login_failed.emit(error_msg)

## إنشاء حساب جديد
func signup_with_email(email: String, password: String, display_name: String = "") -> void:
        if firebase_config["api_key"].is_empty():
                signup_failed.emit("Firebase غير مهيأ")
                return

        var url: String = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=%s" % firebase_config["api_key"]
        var body := JSON.stringify({
                "email": email,
                "password": password,
                "displayName": display_name,
                "returnSecureToken": true
        })

        http_auth.request_completed.connect(_on_signup_response)
        var err := http_auth.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
        if err != OK:
                signup_failed.emit("فشل الاتصال")

func _on_signup_response(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
        http_auth.request_completed.disconnect(_on_signup_response)

        if result != HTTPRequest.RESULT_SUCCESS:
                signup_failed.emit("فشل في الاتصال")
                return

        var json := JSON.new()
        if json.parse(body.get_string_from_utf8()) != OK:
                signup_failed.emit("فشل في تحليل الاستجابة")
                return

        var data: Variant = json.data
        if data is Dictionary and data.has("idToken"):
                current_user = {
                        "uid": data.get("localId", ""),
                        "email": data.get("email", ""),
                        "display_name": data.get("displayName", ""),
                        "token": data.get("idToken", "")
                }
                auth_token = data.get("idToken", "")
                is_logged_in = true

                ## إنشاء بيانات أولية في الـ Database
                _create_initial_user_data()

                if profile_manager:
                        profile_manager.player_id = current_user["uid"]
                        profile_manager.player_name = current_user["display_name"]

                signup_success.emit(current_user)
                auth_state_changed.emit(current_user["uid"], true)
                print("[FirebaseManager] ✅ تم إنشاء الحساب: %s" % current_user["email"])
        else:
                var error_msg := "فشل إنشاء الحساب"
                if data is Dictionary and data.has("error"):
                        error_msg = data["error"].get("message", error_msg)
                signup_failed.emit(error_msg)

## تسجيل الخروج
func logout() -> void:
        current_user.clear()
        auth_token = ""
        is_logged_in = false
        auth_state_changed.emit("", false)
        print("[FirebaseManager] 👋 تم تسجيل الخروج")

## تسجيل دخول ضيف (بدون حساب)
func login_as_guest() -> void:
        var guest_id := "guest_%d" % Time.get_ticks_msec()
        current_user = {
                "uid": guest_id,
                "email": "",
                "display_name": "زائر %d" % randi() % 9999,
                "token": ""
        }
        is_logged_in = true

        if profile_manager:
                profile_manager.player_id = guest_id
                if profile_manager.player_name == "متداول جديد":
                        profile_manager.player_name = current_user["display_name"]

        login_success.emit(current_user)
        print("[FirebaseManager] 👤 دخول كزائر: %s" % guest_id)

## ============================================
## ===== Realtime Database =====
## ============================================

## إنشاء بيانات أولية
func _create_initial_user_data() -> void:
        if firebase_config["database_url"].is_empty() or current_user.is_empty():
                return

        var path: String = "users/%s" % current_user["uid"]
        var user_data := {
                "display_name": current_user["display_name"],
                "email": current_user.get("email", ""),
                "created_at": Time.get_unix_time_from_system(),
                "last_login": Time.get_unix_time_from_system(),
                "level": 1,
                "balance": 100000.0,
                "total_profit": 0.0,
                "total_trades": 0,
                "win_rate": 0.0
        }

        _database_put(path, user_data)

## ============================================
## ===== متصدرين حقيقيين (Online Leaderboard) =====
## ============================================

## جلب لوحة المتصدرين
func fetch_leaderboard(category: String = "total_profit", limit: int = 50) -> void:
        if firebase_config["database_url"].is_empty():
                _fallback_leaderboard(category, limit)
                return

        var path := "leaderboards/%s?orderBy=\"value\"&limitToLast=%d" % [category, limit]

        http_database.request_completed.connect(_on_leaderboard_fetched.bind(category))
        var url := "%s/%s.json" % [firebase_config["database_url"], path]
        var headers := PackedStringArray()
        if not auth_token.is_empty():
                headers.append("Authorization: Bearer %s" % auth_token)

        http_database.request(url, headers)

## رد جلب المتصدرين
func _on_leaderboard_fetched(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray, category: String) -> void:
        http_database.request_completed.disconnect(_on_leaderboard_fetched)

        if result != HTTPRequest.RESULT_SUCCESS:
                _fallback_leaderboard(category, 50)
                return

        var json := JSON.new()
        if json.parse(body.get_string_from_utf8()) != OK:
                _fallback_leaderboard(category, 50)
                return

        var entries: Array[Dictionary] = []
        var data: Variant = json.data

        if data is Dictionary:
                var sorted: Array = []
                for uid in data:
                        var entry: Dictionary = data[uid]
                        sorted.append({
                                "user_id": uid,
                                "user_name": entry.get("display_name", "مجهول"),
                                "value": entry.get("value", 0.0),
                                "level": entry.get("level", 1),
                                "additional_data": entry.get("additional_data", {})
                        })
                sorted.sort_custom(func(a, b): return a["value"] > b["value"])
                entries = sorted
        elif data is Array:
                for item in data:
                        if item is Dictionary:
                                entries.append({
                                        "user_id": item.get("user_id", ""),
                                        "user_name": item.get("display_name", "مجهول"),
                                        "value": item.get("value", 0.0),
                                        "level": item.get("level", 1),
                                        "additional_data": item.get("additional_data", {})
                                })

        cached_leaderboards[category] = {
                "entries": entries,
                "timestamp": Time.get_unix_time_from_system()
        }

        leaderboard_fetched.emit(category, entries)

## بديل محلي (عند عدم توفر Firebase)
func _fallback_leaderboard(category: String, limit: int) -> void:
        ## إنشاء بيانات وهمية للمتصدرين
        var fake_entries: Array[Dictionary] = []
        var fake_names := [
                "الوصف المالي", "صائد الكريبتو", "ملك السوق", "محلل DF",
                "متداول محترف", "حوت القرش", "رافعة مالية", "مخطط الشارت",
                "ثور وول ستريت", "صقر التداول", "نجم الأسهم", "روبوت التداول"
        ]

        for i in range(min(limit, fake_names.size())):
                var value := 0.0
                match category:
                        "total_profit": value = randf() * 500000 + 10000
                        "win_rate": value = randf() * 30 + 60
                        "total_trades": value = randf() * 1000 + 100
                        "balance": value = randf() * 1000000 + 100000
                        "streak": value = randf() * 15 + 1
                        "level": value = randf() * 50 + 5

                fake_entries.append({
                        "user_id": "bot_%d" % i,
                        "user_name": fake_names[i],
                        "value": value,
                        "level": int(randf() * 50 + 5),
                        "additional_data": {}
                })

        ## إضافة اللاعب الحالي
        if profile_manager:
                var player_value := 0.0
                match category:
                        "total_profit": player_value = profile_manager.total_profit
                        "win_rate":
                                player_value = 0.0
                                if profile_manager.total_trades > 0:
                                        player_value = (float(profile_manager.winning_trades) / float(profile_manager.total_trades)) * 100.0
                        "total_trades": player_value = float(profile_manager.total_trades)
                        "balance": player_value = profile_manager.balance
                        "streak": player_value = float(profile_manager.best_streak)
                        "level": player_value = float(profile_manager.level)

                fake_entries.append({
                        "user_id": profile_manager.player_id,
                        "user_name": profile_manager.player_name + " (أنت)",
                        "value": player_value,
                        "level": profile_manager.level,
                        "additional_data": {"is_current_user": true}
                })

        fake_entries.sort_custom(func(a, b): return a["value"] > b["value"])

        cached_leaderboards[category] = {
                "entries": fake_entries,
                "timestamp": Time.get_unix_time_from_system()
        }

        leaderboard_fetched.emit(category, fake_entries)

## تحديث بيانات اللاعب في المتصدرين
func update_leaderboard_entry(category: String, value: float, additional_data: Dictionary = {}) -> void:
        if not is_logged_in or current_user.is_empty():
                return

        if firebase_config["database_url"].is_empty():
                return

        var path := "leaderboards/%s/%s" % [category, current_user["uid"]]
        var entry := {
                "display_name": profile_manager.player_name if profile_manager else "مجهول",
                "value": value,
                "level": profile_manager.level if profile_manager else 1,
                "additional_data": additional_data,
                "updated_at": Time.get_unix_time_from_system()
        }

        _database_put(path, entry)
        leaderboard_updated.emit(entry)

## تحديث جميع فئات المتصدرين
func sync_all_leaderboards() -> void:
        if not profile_manager:
                return

        update_leaderboard_entry("total_profit", profile_manager.total_profit)
        update_leaderboard_entry("balance", profile_manager.balance)
        update_leaderboard_entry("total_trades", float(profile_manager.total_trades))
        update_leaderboard_entry("level", float(profile_manager.level))
        update_leaderboard_entry("streak", float(profile_manager.best_streak))

        var win_rate := 0.0
        if profile_manager.total_trades > 0:
                win_rate = (float(profile_manager.winning_trades) / float(profile_manager.total_trades)) * 100.0
        update_leaderboard_entry("win_rate", win_rate)

## تحديث دوري للمتصدرين
func _refresh_leaderboards() -> void:
        var categories := ["total_profit", "balance", "win_rate", "total_trades", "level", "streak"]
        for cat in categories:
                fetch_leaderboard(cat)

## ============================================
## ===== الحفظ السحابي =====
## ============================================

## حفظ البيانات في السحابة
func cloud_save(save_data: Dictionary) -> void:
        if not is_logged_in or firebase_config["database_url"].is_empty():
                return

        var path: String = "user_data/%s" % current_user["uid"]
        save_data["last_saved"] = Time.get_unix_time_from_system()

        _database_put(path, save_data)

## تحميل البيانات من السحابة
func cloud_load() -> void:
        if not is_logged_in or firebase_config["database_url"].is_empty():
                cloud_load_failed.emit("غير مسجل الدخول")
                return

        var _path: String = "user_data/%s.json" % current_user["uid"]
        var _url: String = "%s/%s" % [firebase_config["database_url"], _path]

        http_database.request_completed.connect(_on_cloud_load_response)
        var _headers := PackedStringArray()
        if not auth_token.is_empty():
                _headers.append("Authorization: Bearer %s" % auth_token)

        http_database.request(_url, _headers)

func _on_cloud_load_response(result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
        http_database.request_completed.disconnect(_on_cloud_load_response)

        if result != HTTPRequest.RESULT_SUCCESS:
                cloud_load_failed.emit("فشل تحميل البيانات")
                return

        var json := JSON.new()
        if json.parse(body.get_string_from_utf8()) == OK and json.data is Dictionary:
                cloud_load_success.emit(json.data)

## حفظ تلقائي سحابي
func _auto_cloud_save() -> void:
        if not is_logged_in or not profile_manager:
                return

        var save_data := {
                "profile": profile_manager.get_all_stats(),
                "earned_badges": profile_manager.earned_badges,
                "balance": profile_manager.balance
        }

        cloud_save(save_data)

## ============================================
## ===== وظائف مساعدة =====
## ============================================

## HTTP PUT
func _database_put(path: String, data: Dictionary) -> void:
        var url := "%s/%s.json" % [firebase_config["database_url"], path]
        var headers := PackedStringArray(["Content-Type: application/json"])
        if not auth_token.is_empty():
                headers.append("Authorization: Bearer %s" % auth_token)

        http_database.request(url, headers, HTTPClient.METHOD_PUT, JSON.stringify(data))

## تهيئة Firebase ببيانات المشروع
func configure(api_key: String, database_url: String, project_id: String = "") -> void:
        firebase_config = {
                "api_key": api_key,
                "database_url": database_url,
                "project_id": project_id,
                "auth_domain": "",
                "storage_bucket": "",
                "messaging_sender_id": "",
                "app_id": ""
        }
        print("[FirebaseManager] ✅ تم تهيئة Firebase | Project: %s" % project_id)

## الحصول على لوحة المتصدرين المخزنة مؤقتاً
func get_cached_leaderboard(category: String) -> Array[Dictionary]:
        if cached_leaderboards.has(category):
                return cached_leaderboards[category].get("entries", [])
        return []
