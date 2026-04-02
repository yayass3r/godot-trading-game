## ============================================
## LimitOrder.gd - نموذج بيانات أمر الحد
## أمر معلق ينتظر وصول السعر لسعر محدد
## ============================================
class_name LimitOrder
extends Resource

## أنواع الأوامر
enum OrderType {
	LIMIT,          ## أمر حد - يُنفذ عند وصول السعر
	STOP_MARKET,    ## وقف السوق - يُنفذ عند تجاوز السعر
	TAKE_PROFIT,    ## جني أرباح محدد
	STOP_LOSS       ## وقف خسارة محدد
}

## حالة الأمر
enum OrderStatus {
	PENDING,        ## في الانتظار
	FILLED,         ## تم التنفيذ
	CANCELLED,      ## تم الإلغاء
	EXPIRED         ## منتهي الصلاحية
}

## أنواع الاتجاه
enum OrderSide {
	BUY,            ## شراء (LONG)
	SELL            ## بيع (SHORT)
}

## ---- بيانات الأمر ----
@export var order_id: String = ""
@export var symbol: String = ""
@export var order_type: OrderType = OrderType.LIMIT
@export var order_side: OrderSide = OrderSide.BUY
@export var status: OrderStatus = OrderStatus.PENDING

## ---- أسعار ومبالغ ----
@export var trigger_price: float = 0.0     ## السعر الذي يُنفذ عنده
@export var position_size: float = 0.0     ## حجم المركز
@export var leverage: int = 1              ## الرافعة المالية
@export var filled_price: float = 0.0      ## السعر الفعلي للتنفيذ
@export var filled_size: float = 0.0       ## الحجم المنفذ فعلياً

## ---- TP/SL للصفقة الناتجة ----
@export var take_profit: float = -1.0
@export var stop_loss: float = -1.0

## ---- أوقات ----
@export var created_time: int = 0
@export var filled_time: int = 0
@export var expire_time: int = 0           ## 0 = بدون انتهاء

## ---- معلومات ----
@export var margin_required: float = 0.0
@export var fee: float = 0.0

## ============================================
## هل يجب تنفيذ هذا الأمر عند السعر المعطى؟
## ============================================
func should_trigger(current_price: float) -> bool:
	if status != OrderStatus.PENDING:
		return false

	match order_type:
		OrderType.LIMIT:
			match order_side:
				OrderSide.BUY:
					return current_price <= trigger_price
				OrderSide.SELL:
					return current_price >= trigger_price
		OrderType.STOP_MARKET:
			match order_side:
				OrderSide.BUY:
					return current_price >= trigger_price
				OrderSide.SELL:
					return current_price <= trigger_price
		OrderType.TAKE_PROFIT:
			return true  ## يُحدد من الخارج
		OrderType.STOP_LOSS:
			return true  ## يُحدد من الخارج

	return false

## ============================================
## هل انتهت صلاحية الأمر؟
## ============================================
func is_expired() -> bool:
	if expire_time <= 0:
		return false
	return Time.get_unix_time_from_system() > expire_time

## ============================================
## تحويل إلى قاموس
## ============================================
func to_dictionary() -> Dictionary:
	return {
		"order_id": order_id,
		"symbol": symbol,
		"order_type": order_type,
		"order_side": order_side,
		"status": status,
		"trigger_price": trigger_price,
		"position_size": position_size,
		"leverage": leverage,
		"filled_price": filled_price,
		"filled_size": filled_size,
		"take_profit": take_profit,
		"stop_loss": stop_loss,
		"created_time": created_time,
		"filled_time": filled_time,
		"expire_time": expire_time,
		"margin_required": margin_required,
		"fee": fee,
		"side": "BUY" if order_side == OrderSide.BUY else "SELL",
		"type_name": ["LIMIT", "STOP_MARKET", "TAKE_PROFIT", "STOP_LOSS"][order_type]
	}
