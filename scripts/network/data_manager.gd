## ============================================
## DataManager.gd - مدير البيانات الحية
## يربط APIs حقيقية لجلب أسعار الأسهم والعملات الرقمية
## ============================================
extends Node

## ---- إشارات (Signals) ----
signal price_updated(symbol: String, price: float, timestamp: int)
signal price_update_failed(symbol: String, error: String)
signal kline_received(symbol: String, interval: String, candles: Array)
signal orderbook_received(symbol: String, bids: Array, asks: Array)
signal market_data_loaded(success: bool)

## ---- إعدادات API ----
## Binance API للعملات الرقمية (مجاني، لا يحتاج مفتاح للقراءة)
const BINANCE_BASE_URL: String = "https://api.binance.com/api/v3"
## CoinGecko API كبديل (مجاني تماماً)
const COINGECKO_BASE_URL: String = "https://api.coingecko.com/api/v3"

## ---- فاصل التحديثات ----
const CRYPTO_UPDATE_INTERVAL: float = 2.0   ## تحديث كل ثانيتين للكريبتو
const STOCK_UPDATE_INTERVAL: float = 30.0    ## تحديث كل 30 ثانية للأسهم
const MAX_RETRIES: int = 3
const REQUEST_TIMEOUT: float = 10.0

## ---- حالة البيانات ----
var prices: Dictionary = {}                ## آخر أسعار {symbol: price}
var price_history: Dictionary = {}         ## تاريخ الأسعار {symbol: [{time, price}]}
var is_updating: bool = false

## ---- مرجع TradingManager ----
var trading_manager: Node

## ---- مؤقتات التحديث ----
var crypto_timer: Timer
var stock_timer: Timer

## ---- رموز العملات الرقمية للمراقبة ----
var crypto_symbols: Array[String] = [
        "BTCUSDT", "ETHUSDT", "BNBUSDT", "SOLUSDT", "XRPUSDT", "ADAUSDT", "DOGEUSDT"
]

## ---- HTTPRequest nodes ----
var _http_request_pool: Array[HTTPRequest] = []
var _request_queue: Array[Dictionary] = []
var _active_requests: int = 0
const MAX_CONCURRENT_REQUESTS: int = 3

## ============================================
## التهيئة
## ============================================
func _ready() -> void:
        trading_manager = get_node_or_null("/root/TradingManager")
        
        ## إنشاء مؤقتات التحديث
        crypto_timer = Timer.new()
        crypto_timer.wait_time = CRYPTO_UPDATE_INTERVAL
        crypto_timer.autostart = false
        crypto_timer.timeout.connect(_on_crypto_timer_timeout)
        add_child(crypto_timer)
        
        stock_timer = Timer.new()
        stock_timer.wait_time = STOCK_UPDATE_INTERVAL
        stock_timer.autostart = false
        stock_timer.timeout.connect(_on_stock_timer_timeout)
        add_child(stock_timer)
        
        ## إنشاء مجمع HTTPRequest
        for i in range(MAX_CONCURRENT_REQUESTS):
                var http := HTTPRequest.new()
                http.timeout = REQUEST_TIMEOUT
                http.request_completed.connect(_on_request_completed.bind(http))
                add_child(http)
                _http_request_pool.append(http)
        
        print("[DataManager] ✅ مدير البيانات جاهز")

## ============================================
## بدء جلب البيانات الحية
## ============================================
func start_live_updates() -> void:
        ## جلب أول بيانات
        fetch_all_crypto_prices()
        
        ## بدء المؤقتات
        crypto_timer.start()
        
        print("[DataManager] 📡 بدء التحديثات الحية | كريبتو: كل %.1fs | أسهم: كل %.1fs" % [
                CRYPTO_UPDATE_INTERVAL, STOCK_UPDATE_INTERVAL
        ])

## ============================================
## إيقاف التحديثات
## ============================================
func stop_live_updates() -> void:
        crypto_timer.stop()
        stock_timer.stop()
        print("[DataManager] ⏸️ تم إيقاف التحديثات الحية")

## ============================================
## جلب أسعار كل العملات الرقمية دفعة واحدة
## يستخدم Binance /api/v3/ticker/price
## ============================================
func fetch_all_crypto_prices() -> void:
        var url := "%s/ticker/price" % BINANCE_BASE_URL
        _enqueue_request(url, HTTPClient.METHOD_GET, "", _parse_all_prices)

## ============================================
## جلب سعر عملة واحدة
## ============================================
func fetch_crypto_price(symbol: String) -> void:
        var url := "%s/ticker/price?symbol=%s" % [BINANCE_BASE_URL, symbol]
        _enqueue_request(url, HTTPClient.METHOD_GET, "", func(data):
                if data.has("price"):
                        var price := float(data["price"])
                        prices[symbol] = price
                        price_updated.emit(symbol, price, Time.get_unix_time_from_system())
                        if trading_manager:
                                trading_manager.update_market_price(symbol, price)
        )

## ============================================
## جلب بيانات الشموع (K-line / Candlestick)
## للرسم البياني
## ============================================
func fetch_klines(symbol: String, interval: String = "1h", limit: int = 100) -> void:
        var url := "%s/klines?symbol=%s&interval=%s&limit=%d" % [
                BINANCE_BASE_URL, symbol, interval, limit
        ]
        _enqueue_request(url, HTTPClient.METHOD_GET, "", func(data):
                var candles: Array = []
                if data is Array:
                        for item in data:
                                candles.append({
                                        "open_time": int(item[0]),
                                        "open": float(item[1]),
                                        "high": float(item[2]),
                                        "low": float(item[3]),
                                        "close": float(item[4]),
                                        "volume": float(item[5]),
                                        "close_time": int(item[6])
                                })
                kline_received.emit(symbol, interval, candles)
        )

## ============================================
## جلب بيانات دفتر الأوامر (Order Book)
## من Binance REST API
## ============================================
func fetch_orderbook(symbol: String, limit: int = 20) -> void:
        var url := "%s/depth?symbol=%s&limit=%d" % [
                BINANCE_BASE_URL, symbol, limit
        ]
        _enqueue_request(url, HTTPClient.METHOD_GET, "", func(data):
                var bids: Array = []
                var asks: Array = []
                if data is Dictionary:
                        var raw_bids: Variant = data.get("bids", [])
                        var raw_asks: Variant = data.get("asks", [])
                        for item in raw_bids:
                                bids.append([float(item[0]), float(item[1])])
                        for item in raw_asks:
                                asks.append([float(item[0]), float(item[1])])
                orderbook_received.emit(symbol, bids, asks)
        )

## ============================================
## جلب بيانات الأسهم من API بديل
## يستخدم Alpha Vantage أو API مشابه
## ============================================
func fetch_stock_price(symbol: String) -> void:
        ## مثال: استخدام API مجاني
        var url := "https://query1.finance.yahoo.com/v8/finance/chart/%s" % symbol
        _enqueue_request(url, HTTPClient.METHOD_GET, "", func(data):
                ## تحليل بيانات Yahoo Finance
                if data is Dictionary and data.has("chart"):
                        var result: Dictionary = data["chart"]["result"][0]
                        var meta: Dictionary = result["meta"]
                        var price := float(meta["regularMarketPrice"])
                        prices[symbol] = price
                        price_updated.emit(symbol, price, Time.get_unix_time_from_system())
                        if trading_manager:
                                trading_manager.update_market_price(symbol, price)
        )

## ============================================
## جلب سعر عملة من CoinGecko (بديل)
## ============================================
func fetch_coingecko_price(coin_id: String, symbol: String) -> void:
        var url := "%s/simple/price?ids=%s&vs_currencies=usd" % [COINGECKO_BASE_URL, coin_id]
        _enqueue_request(url, HTTPClient.METHOD_GET, "", func(data):
                if data is Dictionary and data.has(coin_id):
                        var price := float(data[coin_id]["usd"])
                        prices[symbol] = price
                        price_updated.emit(symbol, price, Time.get_unix_time_from_system())
                        if trading_manager:
                                trading_manager.update_market_price(symbol, price)
        )

## ============================================
## الحصول على آخر سعر معروف
## ============================================
func get_price(symbol: String) -> float:
        return prices.get(symbol, 0.0)

## ============================================
## الحصول على كل الأسعار
## ============================================
func get_all_prices() -> Dictionary:
        return prices.duplicate(true)

## ============================================
## ===== نظام طلبات HTTP الداخلي =====
## ============================================

func _enqueue_request(url: String, method: int, body: String, callback: Callable) -> void:
        _request_queue.append({
                "url": url,
                "method": method,
                "body": body,
                "callback": callback,
                "retries": 0
        })
        _process_queue()

func _process_queue() -> void:
        while _request_queue.size() > 0 and _active_requests < MAX_CONCURRENT_REQUESTS:
                var available_http: HTTPRequest = null
                for http in _http_request_pool:
                        if not http.is_processing_request():
                                available_http = http
                                break
                
                if available_http == null:
                        break
                
                var request: Dictionary = _request_queue.pop_front()
                _active_requests += 1
                
                var headers := ["Content-Type: application/json"]
                var err := available_http.request(request["url"], headers, request["method"], request["body"])
                if err != OK:
                        _active_requests -= 1
                        print("[DataManager] ❌ فشل الطلب: %s" % request["url"])

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
        _active_requests -= 1
        
        if result != HTTPRequest.RESULT_SUCCESS:
                print("[DataManager] ❌ خطأ في الطلب: كود %d" % response_code)
                _process_queue()
                return
        
        if response_code != 200:
                print("[DataManager] ❌ استجابة غير ناجحة: HTTP %d" % response_code)
                _process_queue()
                return
        
        ## تحليل JSON
        var json := JSON.new()
        var err := json.parse(body.get_string_from_utf8())
        
        if err != OK:
                print("[DataManager] ❌ خطأ في تحليل JSON")
                _process_queue()
                return
        
        ## معالجة البيانات وإرسالها للcallback
        if _request_queue.size() > 0:
                var next_request: Dictionary = _request_queue.pop_front()
                var callback: Callable = next_request.get("callback", Callable())
                if callback.is_valid():
                        callback.call(json.data)
        else:
                ## إذا لم يكن هناك callback في الطابور، استخدم parse_all_prices
                _parse_all_prices(json.data)
        
        _process_queue()

## ============================================
## تحليل رد أسعار Binance (مصفوفة من {symbol, price})
## ============================================
func _parse_all_prices(data) -> void:
        if data is Array:
                for item in data:
                        var symbol: String = item.get("symbol", "")
                        var price: float = float(item.get("price", 0.0))
                        if symbol in crypto_symbols:
                                prices[symbol] = price
                                price_updated.emit(symbol, price, Time.get_unix_time_from_system())
                                if trading_manager:
                                        trading_manager.update_market_price(symbol, price)
                print("[DataManager] 📊 تم تحديث %d أسعار" % data.size())
                market_data_loaded.emit(true)

## ============================================
## مؤقتات التحديث
## ============================================
func _on_crypto_timer_timeout() -> void:
        if not is_updating:
                fetch_all_crypto_prices()

func _on_stock_timer_timeout() -> void:
        ## تحديث أسعار الأسهم
        pass

## ============================================
## _process - للتحقق من حالة الطلب
## ============================================
func _process(_delta: float) -> void:
        is_updating = _active_requests > 0
