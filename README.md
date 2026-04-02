# Godot Trading Simulator Game

> محاكي تداول واقعي للأسهم والعملات الرقمية على أندرويد — مُطوَّر بـ **Godot 4 / GDScript**

![Godot 4](https://img.shields.io/badge/Godot-4.x-blue?logo=godotengine)
![Platform](https://img.shields.io/badge/Platform-Android-green?logo=android)
![GDScript](https://img.shields.io/badge/Language-GDScript-purple)

---

## 🎮 نظرة عامة

لعبة أندرويد متكاملة تحاكي تداول الأسهم والعملات الرقمية بواقعية شديدة. تدعم التداول بالرافعة المالية حتى **100x** مع أسعار حية من Binance API، ونظام محفظة كامل، وتطور شخصي، ومنتدى اجتماعي.

---

## ✨ المميزات الرئيسية

| الميزة | التفاصيل |
|--------|----------|
| 📈 **تداول بالرافعة** | حتى 100x مع حساب دقيق لسعر التصفية |
| 💰 **نظام محفظة** | تتبع الرصيد، الهامش المتاح، Equity لحظي |
| ⚠️ **نداء الهامش** | تنبيهات + هز الهاتف عند الاقتراب من التصفية |
| 📊 **أسعار حية** | Binance API كل ثانيتين + بيانات الشموع |
| 🎯 **نظام مستويات** | خبرة تراكمية + 10 أوسمة + مكافآت |
| 🏆 **لوحة المتصدرين** | 6 فئات تصنيف (رصيد، ربح، نسبة فوز...) |
| 💬 **منتدى اجتماعي** | نشر توصيات + لقطات شاشة + إعجابات وتعليقات |
| 🔔 **إشعارات متقدمة** | 5 مستويات أولوية + أنماط اهتزاز مختلفة |
| 📱 **تصميم أندرويد** | واجهة Portrait 720×1280 مع Dark Theme |

---

## 🏗️ هيكل المشروع

```
godot-trading-game/
├── project.godot              ← إعدادات المشروع + AutoLoad
├── scripts/
│   ├── managers/
│   │   ├── game_manager.gd         # المدير العام — يربط كل الأنظمة
│   │   ├── trading_manager.gd      # فتح/إغلاق الصفقات بالرافعة
│   │   ├── portfolio_manager.gd     # المحفظة + الهامش + التصفية
│   │   ├── profile_manager.gd      # المستوى + الخبرة + الأوسمة
│   │   ├── notification_manager.gd  # الإشعارات + هز الهاتف
│   │   ├── forum_manager.gd        # المنتدى الاجتماعي
│   │   └── leaderboard_manager.gd    # لوحة المتصدرين
│   ├── data_models/
│   │   └── trade.gd                  # نموذج بيانات الصفقة
│   ├── network/
│   │   └── data_manager.gd           # HTTP لجلب الأسعار الحية
│   └── ui/
│       ├── trading_ui.gd             # واجهة التداول
│       ├── profile_ui.gd             # واجهة الملف الشخصي
│       ├── forum_ui.gd               # واجهة المنتدى
│       └── leaderboard_ui.gd          # واجهة المتصدرين
├── scenes/                     ← مشاهد اللعبة (tscn)
├── addons/
│   └── vibration_plugin/      ← اهتزاز أندرويد عبر JNI
└── assets/                    ← أصوات، أيقونات، خطوط، UI
```

---

## 🔄 ربط الأنظمة (Architecture)

```
 DataManager (API) ──→ TradingManager ──→ PortfolioManager
                              │                      │
                              ▼                      ▼
                       ProfileManager ◄──────────────┘
                              │
                    ┌─────────┼─────────┐
                    ▼         ▼         ▼
              ForumManager  Leaderboard  Notifications
```

**تدفق إغلاق صفقة:**
1. `TradingManager.close_trade()` → البحث عن الصفقة
2. `PortfolioManager.close_trade()` → حساب PnL + خصم الرسوم
3. `ProfileManager.balance += pnl` → تحديث الرصيد
4. `ProfileManager.update_trade_stats()` → تحديث الإحصائيات + الخبرة
5. `GameManager` → نشر تلقائي في المنتدى إن كان الربح > $1000

---

## 🚀 البدء بالتطوير

### المتطلبات
- **Godot 4.2+** — [تحميل من الموقع الرسمي](https://godotengine.org/download)
- حساب **Binance** (مجاني للقراءة — لا يحتاج API Key)
- **Android Studio** (للبناء على أندرويد)

### التثبيت
```bash
# استنساخ المستودع
git clone https://github.com/trading-game-dev/godot-trading-simulator.git

# فتح المشروع في Godot Editor
# File → Open → اختر مجلد godot-trading-game
```

### البناء لأندرويد
1. افتح **Project → Export**
2. أضف **Android** platform
3. عيّن مسار Android SDK
4. اضغط **Export APK** أو **Export Project**

---

## 🛠️ التقنيات المستخدمة

| التقنية | الاستخدام |
|---------|-----------|
| GDScript | كل المنطق البرمجي والواجهات |
| AutoLoad Pattern | وصول عالمي للأنظمة |
| Signal System | التواصل اللاسلسي بين الأنظمة |
| Binance REST API | الأسعار الحية للعملات الرقمية |
| HTTPRequest | الاتصال بالبيانات |
| JSON + FileAccess | حفظ وتحميل بيانات اللاعب |
| Android JNI | اهتزاز الهاتف (Vibration) |

---

## 📋 خارطة الطريق

- [x] نظام التداول بالرافعة المالية (1x-100x)
- [x] حساب سعر التصفية ونداء الهامش
- [x] أسعار حية من Binance API
- [x] نظام المستويات والخبرة والأوسمة
- [x] المنتدى الاجتماعي + لوحة المتصدرين
- [x] إشعارات + اهتزاز الهاتف
- [ ] رسوم بيانية تفاعلية (Candlestick Charts)
- [ ] صوت أسواق (Market Sounds)
- [ ] Firebase لبيانات المتصدرين الحقيقية
- [ ] Backtesting — اختبار استراتيجيات تاريخية
- [ ] أوضاع تحدي (Challenges) يومية/أسبوعية
- [ ] نظام تعليمي (Tutorials) للمبتدئين

---

## 🤝 المساهمة

نرحب بمساهماتكم! يرجى:
1. Fork المستودع
2. إنشاء فرع `feature/your-feature`
3. Commit مع رسائل واضحة
4. Push وإنشاء Pull Request

---

## 📄 الرخصة

MIT License — استخدمها بحرية في مشاريعكم.

---

<p align="center">
  مبني بـ ❤️ باستخدام Godot 4 | <a href="https://z.ai">Z.ai</a>
</p>
