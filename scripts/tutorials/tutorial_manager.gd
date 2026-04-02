## ============================================
## TutorialManager.gd - نظام تعليمي تفاعلي للمبتدئين
## يقدم دروساً متدرجة مع اختبارات قصيرة ومكافآت XP
## ============================================
extends Node

const NP = preload("res://scripts/enums/notification_priority.gd")

## ---- إشارات (Signals) ----
signal tutorial_unlocked(tutorial_id: String, title: String)
signal tutorial_started(tutorial_id: String)
signal lesson_completed(tutorial_id: String, lesson_index: int)
signal tutorial_completed(tutorial_id: String, xp_earned: int)
signal quiz_answered(question_index: int, correct: bool)
signal progress_saved()

## ---- مراجع ----
var profile_manager: Node

## ---- حالة التعلم ----
var completed_tutorials: Array[String] = []
var completed_lessons: Dictionary = {}
var tutorial_scores: Dictionary = {}
var last_tutorial: String = ""

## ---- قاعدة بيانات الدروس ----
var tutorials: Array[Dictionary] = [
        {
                "id": "basics_01", "title": "ما هو التداول؟",
                "description": "تعرف على عالم التداول والأسواق المالية",
                "category": "أساسيات", "difficulty": 1, "required_level": 1, "xp_reward": 500,
                "lessons": [
                        {
                                "title": "مقدمة في التداول",
                                "content": "التداول هو عملية شراء وبيع الأصول المالية مثل الأسهم والعملات الرقمية بهدف تحقيق الربح من فرق السعر. يعتمد التداول على تحليل حركة الأسعار واتخاذ قرارات شراء عند انخفاض السعر وبيع عند ارتفاعه. يوجد أنواع متعددة من التداول: اليومي (يوم واحد)، المتأرجح (أيام إلى أسابيع)، والطويل الأجل (أسابيع إلى أشهر). كل نوع له استراتيجيات ومخاطر مختلفة يجب فهمها قبل البدء.",
                                "key_points": ["التداول = شراء عند سعر منخفض + بيع عند سعر مرتفع", "أنواع التداول: يومي، متأرجح، طويل الأجل", "الهدف: تحقيق أرباح من حركة الأسعار"]
                        },
                        {
                                "title": "الأسواق المالية",
                                "content": "تتضمن الأسواق المالية عدة أنواع رئيسية: سوق الأسهم الذي تتداول فيه حصص الشركات مثل Apple و Tesla، وسوق العملات الرقمية مثل Bitcoin و Ethereum الذي يعمل على مدار الساعة، وسوق الفوركس لتبادل العملات التقليدية. كل سوق له ساعات عمل خاصة ومستوى تقلب مختلف. سوق الكريبتو هو الأكثر تقلباً ويعمل 24/7 مما يجعله مثالياً للمتداولين الذين يفضلون النشاط المستمر.",
                                "key_points": ["سوق الأسهم: حصص الشركات (AAPL, TSLA, GOOGL)", "سوق الكريبتو: عملات رقمية (BTC, ETH, SOL) - يعمل 24/7", "سوق الفوركس: تبادل العملات التقليدية"]
                        },
                        {
                                "title": "أدوات التداول الأساسية",
                                "content": "قبل البدء بالتداول تحتاج لفهم الأدوات الأساسية: الرسم البياني (Chart) يعرض حركة السعر التاريخية واللحظية. الشموع اليابانية (Candlesticks) هي الأداة الأكثر استخداماً حيث تعرض 4 بيانات: سعر الافتتاح والإغلاق وأعلى وأدنى سعر. كل شمعة تمثل فترة زمنية محددة (دقيقة، ساعة، يوم). الشمعة الخضراء تعني صعود والحمرة تعني هبوط.",
                                "key_points": ["الرسم البياني: عرض حركة السعر", "الشموع اليابانية: افتتاح، إغلاق، أعلى، أدنى", "أخضر = صعود | أحمر = هبوط"]
                        }
                ],
                "quiz": [
                        {"question": "ما هو الهدف الأساسي من التداول؟", "options": ["حفظ المال", "تحقيق الربح من فرق الأسعار", "استهلاك المنتجات", "شراء الشركات"], "correct": 1},
                        {"question": "ماذا تعني الشمعة الخضراء؟", "options": ["سعر الإغلاق = سعر الافتتاح", "سعر الإغلاق أعلى من الافتتاح", "سعر الإغلاق أدنى من الافتتاح", "لا توجد شموع خضراء"], "correct": 1},
                        {"question": "أي سوق يعمل 24/7؟", "options": ["سوق الأسهم الأمريكي", "سوق الكريبتو", "سوق الذهب", "سوق العقارات"], "correct": 1}
                ]
        },
        {
                "id": "basics_02", "title": "الأوامر الأساسية",
                "description": "تعرف على أنواع الأوامر وكيفية استخدامها",
                "category": "أساسيات", "difficulty": 1, "required_level": 1, "xp_reward": 500,
                "lessons": [
                        {
                                "title": "أمر السوق (Market Order)",
                                "content": "أمر السوق هو أبسط أنواع الأوامر. عند تنفيذه يتم الشراء أو البيع فوراً بأفضل سعر متاح حالياً في السوق. مميزاته: التنفيذ الفوري والسهولة. عيوبه: قد تحصل على سعر مختلف قليلاً عما تتوقع خاصة في الأسواق شديدة التقلب. مناسب للمبتدئين والأوقات التي تريد فيها الدخول أو الخروج من السوق فوراً.",
                                "key_points": ["تنفيذ فوري بأفضل سعر متاح", "سهل الاستخدام للمبتدئين", "قد يختلف السعر المتوقع في التقلبات العالية"]
                        },
                        {
                                "title": "الأمر المعلق (Limit Order)",
                                "content": "الأمر المعلق يسمح لك بتحديد السعر الذي تريد الشراء أو البيع عنده. مثال: إذا كان سعر BTC 60000$ وتريد الشراء عند 55000$ تضع أمر شراء معلق عند هذا السعر. يتم التنفيذ فقط عندما يصل السعر إلى مستواك. مميزاته: تحكم كامل بسعر الدخول. عيوبه: قد لا ينفذ أبداً إذا لم يصل السعر للمستوى المطلوب.",
                                "key_points": ["تحديد سعر محدد للتنفيذ", "لا يتنفذ إلا عند وصول السعر للمستوى", "مفيد للتخطيط الاستراتيجي"]
                        },
                        {
                                "title": "جني الأرباح ووقف الخسارة (TP & SL)",
                                "content": "جني الأرباح (Take Profit / TP) يغلق الصفقة تلقائياً عند مستوى ربح محدد. وقف الخسارة (Stop Loss / SL) يغلق الصفقة تلقائياً عند مستوى خسارة محدد لتحديد أقصى خسارة ممكنة. القاعدة الذهبية: دائماً حدد SL لكل صفقة لحماية رأس مالك من الخسائر الكبيرة.",
                                "key_points": ["TP = إغلاق تلقائي عند تحقيق الربح المستهدف", "SL = إغلاق تلقائي عند بلوغ حد الخسارة", "القاعدة الذهبية: حدد SL دائماً!"]
                        }
                ],
                "quiz": [
                        {"question": "ما الفرق بين أمر السوق والأمر المعلق؟", "options": ["لا يوجد فرق", "السوق فوري، المعلق عند سعر محدد", "السوق أرخص، المعلق أغلى", "المعلق لا يعمل أبدًا"], "correct": 1},
                        {"question": "ما هو وقف الخسارة (SL)؟", "options": ["أمر شراء إضافي", "إغلاق تلقائي عند حد خسارة محدد", "نوع من العملات الرقمية", "استراتيجية ربح مضمونة"], "correct": 1},
                        {"question": "ما القاعدة الذهبية في إدارة المخاطر؟", "options": ["تداول بأقصى رافعة ممكنة", "حدد وقف خسارة لكل صفقة", "لا تستخدم جني الأرباح", "تداول فقط بالعملات الرقمية"], "correct": 1}
                ]
        },
        {
                "id": "intermediate_01", "title": "التحليل الفني",
                "description": "تعلم قراءة الرسوم البيانية والمؤشرات الفنية",
                "category": "متوسط", "difficulty": 2, "required_level": 5, "xp_reward": 1000,
                "lessons": [
                        {
                                "title": "المتوسطات المتحركة (Moving Averages)",
                                "content": "المتوسط المتحرك (MA) هو مؤشر فني يحسب متوسط السعر على فترة محددة. نوعان رئيسيان: SMA البسيط و EMA الأُسّي (أسرع استجابة). الاستخدامات: تحديد الاتجاه العام (SMA 200)، إشارات شراء/بيع عند التقاطع. تقاطع Golden Cross = صعود، Death Cross = هبوط.",
                                "key_points": ["SMA = متوسط بسيط | EMA = متوسط أسّي (أسرع)", "تقاطع صاعد (Golden Cross) = إشارة شراء", "تقاطع هابط (Death Cross) = إشارة بيع"]
                        },
                        {
                                "title": "RSI - مؤشر القوة النسبية",
                                "content": "RSI يقيس سرعة وتغير حركات الأسعار. مداه من 0 إلى 100. فوق 70 = مفرط الشراء، تحت 30 = مفرط البيع. لا تعتمد عليه وحده - استخدمه للتأكيد مع مؤشرات أخرى. في الاتجاهات القوية قد يبقى RSI فوق 70 لفترة طويلة.",
                                "key_points": ["RSI > 70 = مفرط الشراء | RSI < 30 = مفرط البيع", "لا تعتمد عليه وحده - استخدمه للتأكيد", "في الاتجاه القوي قد يبقى متطرفاً لفترة طويلة"]
                        },
                        {
                                "title": "بولينجر باند (Bollinger Bands)",
                                "content": "يتكون من 3 خطوط: الباند الأوسط = SMA 20، العلوي والسفلي = SMA +/- (2 × الانحراف المعياري). تضيق الباندات = قد تتبعه حركة قوية. استراتيجية الارتداد تنجح في الأسواق الجانبية.",
                                "key_points": ["3 خطوط: أعلى + وسط + أسفل", "تسع الباندات = حركة سعر قوية قادمة", "الارتداد من الباندات ينجح في السوق الجانبي"]
                        }
                ],
                "quiz": [
                        {"question": "ماذا يعني Golden Cross؟", "options": ["السعر وصل لأعلى مستوى", "SMA السريع يقطع البطيء للأعلى", "RSI وصل لـ 100", "تم بيع كل الأسهم"], "correct": 1},
                        {"question": "عندما يبقى RSI فوق 70 لفترة طويلة ماذا يعني؟", "options": ["يجب البيع فوراً", "اتجاه صعودي قوي", "السوق سينهار", "السعر لن يتحرك"], "correct": 1},
                        {"question": "ماذا يحدث عند تضيق بولينجر باند؟", "options": ["السوق سيتوقف", "قد تتبعه حركة سعر قوية", "لا شيء مهم", "يجب إغلاق كل الصفقات"], "correct": 1}
                ]
        },
        {
                "id": "intermediate_02", "title": "الرافعة المالية والهامش",
                "description": "فهم المخاطر والمكافآت في التداول بالرافعة",
                "category": "متوسط", "difficulty": 2, "required_level": 5, "xp_reward": 1500,
                "lessons": [
                        {
                                "title": "مبادئ الرافعة المالية",
                                "content": "الرافعة المالية تتيح لك التحكم بمبلغ أكبر من رأس مالك الفعلي. مثال: برافعة 10x و 1000$ هامش، يمكنك التداول بـ 10000$. إذا تحرك السعر 1% لصالحك = ربح 10%. لكن إذا تحرك 1% ضدك = خسارة 10%. القاعدة: لا تستخدم رافعة أعلى مما تستطيع تحمل خسارته.",
                                "key_points": ["الرافعة تضاعف الأرباح والخسائر بنفس النسبة", "10x = حركة 1% = ربح/خسارة 10%", "كل مستوى يفتح رافعة أعلى"]
                        },
                        {
                                "title": "الهامش والتصفية",
                                "content": "الهامش هو المبلغ المحجوز من رصيدك لفتح صفقة. سعر التصفية هو السعر الذي يتم عنده إغلاق صفقتك بالقوة وخسارة هامشك بالكامل. مع رافعة 10x: التصفية عند انخفاض 10%. مع رافعة 100x: التصفية عند انخفاض 1% فقط!",
                                "key_points": ["الهامش = رأس المال المحجوز للصفقة", "التصفية = خسارة كل الهامش عند حركة عكسية", "100x = تصفية عند حركة 1% فقط!"]
                        },
                        {
                                "title": "إدارة المخاطر مع الرافعة",
                                "content": "قواعد أساسية: 1) لا تخاطر بأكثر من 1-2% من رصيدك في صفقة واحدة. 2) دائماً حدد Stop Loss. 3) استخدم الرافعة المناسبة: المبتدئين 1-5x، المتوسطين 5-25x، المحترفين 25-50x. 4) لا تزيد الرافعة للتعويض عن خسارة. تذكر: 90% من المتداولين يخسرون لأنهم لا يديرون مخاطرهم.",
                                "key_points": ["قاعدة 1-2%: لا تخاطر بأكثر من ذلك", "حدد Stop Loss دائماً", "لا تزيد الرافعة للتعويض عن خسارة"]
                        }
                ],
                "quiz": [
                        {"question": "مع رافعة 50x إذا تحرك السعر 2% ضدك كم تخسر؟", "options": ["2%", "10%", "50%", "100%"], "correct": 3},
                        {"question": "ما هو سعر التصفية؟", "options": ["سعر الشراء", "السعر الذي يتم عنده إغلاق الصفقة وخسارة الهامش كاملاً", "أعلى سعر في اليوم", "سعر جني الأرباح"], "correct": 1},
                        {"question": "ما النسبة القصوى الموصى بها للمخاطرة؟", "options": ["10%", "5%", "1-2%", "50%"], "correct": 2}
                ]
        },
        {
                "id": "advanced_01", "title": "استراتيجيات متقدمة",
                "description": "تعلم استراتيجيات احترافية لتحسين أدائك",
                "category": "متقدم", "difficulty": 3, "required_level": 20, "xp_reward": 2000,
                "lessons": [
                        {
                                "title": "تقاطع المتوسطات مع RSI",
                                "content": "استراتيجية الجمع بين SMA Crossover و RSI تزيد من دقة الإشارات. قواعد الدخول: SMA 9 يقطع SMA 21 للأعلى AND RSI بين 40-60. قواعد الخروج: SMA 9 يقطع SMA 21 للأسفل OR RSI فوق 80. الأفضل استخدامها على الإطارات 1h و 4h.",
                                "key_points": ["اجمع بين مؤشرين على الأقل للتأكيد", "SMA Cross = إشارة الاتجاه | RSI = التأكيد", "أقل إشارات لكن أدق"]
                        },
                        {
                                "title": "البيع على المكشوف (Short Selling)",
                                "content": "البيع على المكشوف يعني الربح من انخفاض الأسعار. تستعير الأصل وتبيعه بالسعر الحالي، ثم تشتريه بسعر أقل وتعيده. المخاطر مماثلة في كلا الاتجاهين مع الرافعة.",
                                "key_points": ["Short = ربح من الهبوط | Long = ربح من الصعود", "المخاطر مماثلة في كلا الاتجاهين مع الرافعة", "يمكنك التداول على كلا الاتجاهين في اللعبة"]
                        },
                        {
                                "title": "تقرير Fear & Greed",
                                "content": "مؤشر الخوف والطمع يقيس المزاج العام: 0-25 = خوف شديد (فرصة شراء)، 25-45 = خوف، 45-55 = محايد، 55-75 = طمع (حذر)، 75-100 = طمع شديد (خطر). القاعدة: كن جشعاً عندما يخاف الآخرون، وخف عندما يكونون جشعين - وارن بافيت.",
                                "key_points": ["خوف شديد = فرصة شراء | طمع شديد = حذر", "وارن بافيت: كن جشعاً عندما يخاف الآخرون", "اللعبة تحسب المؤشر من تحليل المنتدى تلقائياً"]
                        }
                ],
                "quiz": [
                        {"question": "لماذا الجمع بين SMA و RSI أفضل؟", "options": ["لأنه أسرع", "يقلل الإشارات الكاذبة ويزيد الدقة", "لا يوجد فرق", "لأنه أسهل"], "correct": 1},
                        {"question": "ماذا يعني Selling Short؟", "options": ["بيع سريع", "الربح من انخفاض الأسعار", "توقف عن التداول", "شراء كمية قليلة"], "correct": 1},
                        {"question": "حسب وارن بافيت متى تكون جشعاً؟", "options": ["عندما يكون الجميع جشعاً", "عندما يخاف الجميع", "عندما يكون السوق مستقراً", "لا يجب أن تكون جشعاً أبداً"], "correct": 1}
                ]
        }
]

## ============================================
## _ready() - التهيئة
## ============================================
func _ready() -> void:
        profile_manager = get_node_or_null("/root/ProfileManager")
        load_progress()
        print("[TutorialManager] ✅ النظام التعليمي جاهز | %d دروس" % tutorials.size())

## ============================================
## الحصول على الدروس المتاحة
## ============================================
func get_available_tutorials(player_level: int) -> Array[Dictionary]:
        var available: Array[Dictionary] = []
        for tutorial in tutorials:
                if tutorial["required_level"] <= player_level:
                        var data := tutorial.duplicate(true)
                        data["is_completed"] = tutorial["id"] in completed_tutorials
                        data["completed_lessons"] = completed_lessons.get(tutorial["id"], [])
                        available.append(data)
        return available

## ============================================
## بدء درس معين
## ============================================
func start_tutorial(tutorial_id: String) -> Dictionary:
        var tutorial: Dictionary = {}
        for t in tutorials:
                if t["id"] == tutorial_id:
                        tutorial = t
                        break
        if tutorial.is_empty():
                return {"error": "الدرس غير موجود"}
        if profile_manager and tutorial["required_level"] > profile_manager.level:
                return {"error": "يجب الوصول للمستوى %d أولاً" % tutorial["required_level"]}

        last_tutorial = tutorial_id
        tutorial_started.emit(tutorial_id)

        return {
                "tutorial_id": tutorial_id, "title": tutorial["title"],
                "lessons": tutorial["lessons"], "total_lessons": tutorial["lessons"].size(),
                "completed_lessons": completed_lessons.get(tutorial_id, [])
        }

## ============================================
## إكمال درس
## ============================================
func complete_lesson(tutorial_id: String, lesson_index: int) -> void:
        if not completed_lessons.has(tutorial_id):
                completed_lessons[tutorial_id] = []
        if lesson_index not in completed_lessons[tutorial_id]:
                completed_lessons[tutorial_id].append(lesson_index)
        lesson_completed.emit(tutorial_id, lesson_index)
        save_progress()

## ============================================
## الإجابة على سؤال الاختبار
## ============================================
func answer_quiz(tutorial_id: String, question_index: int, selected_option: int) -> bool:
        var tutorial: Dictionary = {}
        for t in tutorials:
                if t["id"] == tutorial_id:
                        tutorial = t
                        break
        if tutorial.is_empty(): return false
        var quiz: Array = tutorial.get("quiz", [])
        if question_index >= quiz.size(): return false
        var is_correct: bool = selected_option == quiz[question_index]["correct"]
        quiz_answered.emit(question_index, is_correct)
        return is_correct

## ============================================
## إكمال اختبار الدرس بالكامل
## ============================================
func complete_quiz(tutorial_id: String, answers: Array[int]) -> Dictionary:
        var tutorial: Dictionary = {}
        for t in tutorials:
                if t["id"] == tutorial_id:
                        tutorial = t
                        break
        if tutorial.is_empty():
                return {"error": "الدرس غير موجود"}

        var quiz: Array = tutorial.get("quiz", [])
        var correct := 0
        for i in range(min(answers.size(), quiz.size())):
                if answers[i] == quiz[i]["correct"]:
                        correct += 1

        var score_pct := (float(correct) / float(quiz.size())) * 100.0
        var passed := score_pct >= 60.0

        tutorial_scores[tutorial_id] = score_pct

        var xp_earned := 0
        if passed:
                if tutorial_id not in completed_tutorials:
                        completed_tutorials.append(tutorial_id)
                        xp_earned = tutorial["xp_reward"]
                        if profile_manager:
                                profile_manager.add_experience(xp_earned)
                        var challenge_manager: Node = get_node_or_null("/root/ChallengeManager")
                        if challenge_manager:
                                challenge_manager.register_tutorial_complete()
                tutorial_completed.emit(tutorial_id, xp_earned)
                NotificationManager.send_notification(
                        "📚 درس مكتمل!", "%s | %.0f%% | ⭐ +%d XP" % [tutorial["title"], score_pct, xp_earned],
                        NP.SUCCESS
                )
        else:
                NotificationManager.send_notification(
                        "❌ لم تجتز الاختبار", "%s | %.0f%% | حاول مجدداً!" % [tutorial["title"], score_pct],
                        NP.WARNING
                )

        save_progress()
        return {
                "tutorial_id": tutorial_id, "score": score_pct,
                "correct_answers": correct, "total_questions": quiz.size(),
                "passed": passed, "xp_earned": xp_earned
        }

## ============================================
## حفظ/تحميل التقدم
## ============================================
func save_progress() -> void:
        var data := {
                "completed_tutorials": completed_tutorials,
                "completed_lessons": completed_lessons,
                "tutorial_scores": tutorial_scores,
                "last_tutorial": last_tutorial
        }
        var file := FileAccess.open("user://tutorial_progress.json", FileAccess.WRITE)
        if file:
                file.store_string(JSON.stringify(data, "\t"))
                file.close()
                progress_saved.emit()

func load_progress() -> void:
        if not FileAccess.file_exists("user://tutorial_progress.json"):
                return
        var file := FileAccess.open("user://tutorial_progress.json", FileAccess.READ)
        if file == null: return
        var json := JSON.new()
        if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
                var data: Dictionary = json.data
                completed_tutorials = data.get("completed_tutorials", [])
                completed_lessons = data.get("completed_lessons", {})
                tutorial_scores = data.get("tutorial_scores", {})
                last_tutorial = data.get("last_tutorial", "")
        file.close()

## ============================================
## إحصائيات التعلم
## ============================================
func get_learning_stats() -> Dictionary:
        var total_lessons := 0
        var total_completed_lessons := 0
        for tutorial in tutorials:
                total_lessons += tutorial["lessons"].size()
                total_completed_lessons += completed_lessons.get(tutorial["id"], []).size()
        return {
                "total_tutorials": tutorials.size(),
                "completed_tutorials": completed_tutorials.size(),
                "total_lessons": total_lessons,
                "completed_lessons": total_completed_lessons,
                "average_score": _calc_average_score(),
                "progress_pct": (float(completed_tutorials.size()) / max(tutorials.size(), 1)) * 100.0
        }

func _calc_average_score() -> float:
        if tutorial_scores.is_empty(): return 0.0
        var total := 0.0
        for score in tutorial_scores.values():
                total += float(score)
        return total / float(tutorial_scores.size())
