## ============================================
## Trade.gd - نموذج بيانات الصفقة الواحدة
## يخزن كل تفاصيل الصفقة من فتحها حتى إغلاقها
## ============================================
class_name Trade
extends Resource

## أنواع الصفقات
enum TradeType {
	LONG,    ## شراء (مراهنة على الارتفاع)
	SHORT    ## بيع (مراهنة على الانخفاض)
}

## حالات الصفقة
enum TradeStatus {
	OPEN,        ## الصفقة مفتوحة ونشطة
	CLOSED,      ## الصفقة أُغلقت يدوياً
	LIQUIDATED,  ## الصفقة أُغلقت قسراً بسبب التصفية
	MARGIN_CALL  ## تنبيه نداء الهامش (قريب من التصفية)
}

## ---- بيانات أساسية ----
@export var trade_id: String = ""                    ## معرّف فريد للصفقة
@export var symbol: String = ""                      ## رمز الأداة (مثال: BTCUSDT, AAPL)
@export var trade_type: TradeType = TradeType.LONG  ## نوع الصفقة
@export var status: TradeStatus = TradeStatus.OPEN   ## حالة الصفقة الحالية
@export var leverage: int = 1                        ## الرافعة المالية (1x إلى 100x)

## ---- بيانات السعر ----
@export var entry_price: float = 0.0   ## سعر الدخول عند فتح الصفقة
@export var current_price: float = 0.0 ## السعر الحالي (يُحدّث لحظياً)
@export var exit_price: float = 0.0    ## سعر الخروج عند إغلاق الصفقة
@export var liquidation_price: float = 0.0 ## سعر التصفية المحسوب

## ---- بيانات المبالغ ----
@export var position_size: float = 0.0  ## حجم المركز بالعملة الأساسية (مثال: 0.5 BTC)
@export var margin_used: float = 0.0    ## الهامش المحجوز لهذه الصفقة
@export var take_profit: float = -1.0   ## سعر جني الأرباح (-1 = غير محدد)
@export var stop_loss: float = -1.0     ## سعر وقف الخسارة (-1 = غير محدد)

## ---- بيانات الوقت ----
@export var open_time: int = 0           ## وقت الفتح (Unix timestamp)
@export var close_time: int = 0          ## وقت الإغلاق (Unix timestamp)
@export var margin_call_time: int = 0    ## وقت تنبيه نداء الهامش

## ---- النتائج ----
@export var pnl: float = 0.0             ## الربح/الخسارة الفعلي بعد الإغلاق
@export var pnl_percentage: float = 0.0  ## نسبة الربح/الخسارة %
@export var fees_paid: float = 0.0       ## الرسوم المدفوعة

## ============================================
## حساب سعر التصفية بناءً على الرافعة واتجاه الصفقة
## ============================================
func calculate_liquidation_price() -> float:
	if entry_price <= 0.0 or leverage <= 1:
		return 0.0
	
	match trade_type:
		TradeType.LONG:
			## للمشتري: التصفية = سعر الدخول × (1 - 1/الرافعة + فاصل الأمان)
			var safety_buffer: float = 0.005  ## 0.5% فاصل أمان
			liquidation_price = entry_price * (1.0 - (1.0 / leverage) + safety_buffer)
		TradeType.SHORT:
			## للبائع: التصفية = سعر الدخول × (1 + 1/الرافعة - فاصل الأمان)
			var safety_buffer: float = 0.005
			liquidation_price = entry_price * (1.0 + (1.0 / leverage) - safety_buffer)
	
	return liquidation_price

## ============================================
## حساب الربح/الخسارة اللحظي (Unrealized PnL)
## ============================================
func calculate_unrealized_pnl() -> float:
	if current_price <= 0.0 or entry_price <= 0.0:
		return 0.0
	
	var price_diff: float = 0.0
	match trade_type:
		TradeType.LONG:
			price_diff = current_price - entry_price
		TradeType.SHORT:
			price_diff = entry_price - current_price
	
	## الربح = فرق السعر × حجم المركز × الرافعة
	pnl = price_diff * position_size * leverage
	pnl_percentage = ((price_diff / entry_price) * 100.0) * leverage
	
	return pnl

## ============================================
## تحديد ما إذا كانت الصفقة قريبة من التصفية
## يُستخدم لتشغيل تنبيه نداء الهامش
## ============================================
func is_near_liquidation(threshold_percent: float = 0.25) -> bool:
	if liquidation_price <= 0.0 or current_price <= 0.0:
		return false
	
	var distance_to_liquidation: float
	match trade_type:
		TradeType.LONG:
			distance_to_liquidation = (current_price - liquidation_price) / current_price
		TradeType.SHORT:
			distance_to_liquidation = (liquidation_price - current_price) / current_price
		_:
			return false
	
	## إذا كانت المسافة أقل من النسبة المحددة (25% افتراضياً)
	return distance_to_liquidation <= threshold_percent

## ============================================
## التحقق مما إذا كانت الصفقة بلغت سعر التصفية
## ============================================
func is_liquidated() -> bool:
	if liquidation_price <= 0.0:
		return false
	
	match trade_type:
		TradeType.LONG:
			return current_price <= liquidation_price
		TradeType.SHORT:
			return current_price >= liquidation_price
		_:
			return false

## ============================================
## تحويل بيانات الصفقة إلى قاموس (للحفظ/التحميل)
## ============================================
func to_dictionary() -> Dictionary:
	return {
		"trade_id": trade_id,
		"symbol": symbol,
		"trade_type": trade_type,
		"status": status,
		"leverage": leverage,
		"entry_price": entry_price,
		"current_price": current_price,
		"exit_price": exit_price,
		"liquidation_price": liquidation_price,
		"position_size": position_size,
		"margin_used": margin_used,
		"take_profit": take_profit,
		"stop_loss": stop_loss,
		"open_time": open_time,
		"close_time": close_time,
		"margin_call_time": margin_call_time,
		"pnl": pnl,
		"pnl_percentage": pnl_percentage,
		"fees_paid": fees_paid
	}

## ============================================
## استعادة بيانات الصفقة من قاموس
## ============================================
static func from_dictionary(data: Dictionary) -> Trade:
	var trade := Trade.new()
	for key in data:
		if key in trade:
			trade[key] = data[key]
	return trade
