# JRS Stables — الخيل والعربات

مورد JRS Stables من JRS TEAM يجمع الخيل و24 موديل عربة في واجهة jrs_stables. افتح الإسطبل كالمعتاد واختر «العربات»، ثم «متجر العربات». تظهر معاينة العربة داخل اللعبة، وتختار الدفع بالنقود أو الذهب، وتكتب الاسم بالماوس في الواجهة نفسها. تبويب «الخيل» يحتفظ بمتجر الخيل وتجهيزاته.

اللغة تتبع اختيار الشخصية في jrs_character / jrs_core عبر jrsLanguage. تدعم القوائم والتسمية والتنبيهات الجديدة العربية والإنجليزية، وتتغير لغة الواجهة المفتوحة عند تغيير لغة الشخصية.

تنبيهات الخيل وعنوان مخزونها تتبع لغة اللاعب أيضًا؛ عند نقل حصان بين لاعبين، يصل تنبيه كل لاعب بلغته.

## إدارة العربات

- اختيار العربة، تغيير اسمها وبيعها من قائمة عرباتك.
- الاستدعاء والإرجاع، وفتح مخزون العربة وصيانتها ونقل ملكيتها للاعب قريب، من أزرار الواجهة.
- أزرار الإدارة سلوتات بنفس خلفية وشكل سلوتات الخيل، ضمن قائمة قابلة للتمرير.
- حرف J يستدعي العربة المحددة أثناء اللعب، باستخدام اختيار «عرباتك». لا يعمل أثناء فتح القوائم أو الكتابة.
- الاسم العائم فوق الخيل والعربات معطل. تبقى الأسماء داخل الإسطبل لإدارة الملكية.
- فتح قائمة العربة بزر G عند الاقتراب من عربتك، وفتح مخزون العربات المشتركة عند الاقتراب منها.
- تبديل الفرامل بزر O أثناء قيادة العربة. يمنع التحرك عندما تصل الحالة إلى صفر حتى إجراء الصيانة.
- استهلاك مطرقة hammer للصيانة؛ هذا العنصر موجود في تعريفات JRS. قيمة الإصلاح حسب إعداد الموديل.
- نقل الملكية ينقل المخزون أيضًا. يجب إرجاع العربة قبل البيع أو نقل الملكية، وإفراغ مخزونها قبل البيع.
- ملكية العربة مرتبطة بمعرّف الحساب والشخصية. يتحقق السيرفر من السعر والرصيد وحدود العدد والوظيفة والملكية والمسافة.
- المخزون يستخدم jrs_inventory ومخازنه الأصلية؛ العناصر والأسلحة تتبع إعداد الموديل. قواعد الوظائف والقوائم البيضاء والسوداء تُفحص عند نقل المحتويات، بما فيها اقتراب اللاعب من العربة.

أوامر الاستدعاء والإرجاع والمخزون: `/wagonEnter`، `/wagonReturn`، `/wagoncargo`.

## التشغيل والإعدادات

المورد مستقل داخل jrs_stables، واعتماداته jrs_core وjrs_inventory وoxmysql. جدول player_wagons يُنشأ تلقائيًا عند تشغيل المورد. إن وُجد جدول ملكية سابق، يُضاف عمود condition فقط، مع إبقاء سجلات الملكية الحالية؛ ظهورها للشخصية يتطلب مطابقة معرّفات الحساب والشخصية المستخدمة في JRS. سكربت الإنشاء موجود في sql/wagons.sql للتثبيت اليدوي الاختياري.

في كونسول السيرفر بعد تحديث الملفات:

```text
restart jrs_stables
restart jrs_admin
```

الحد الافتراضي 5 عربات للاعب و10 لوظيفة wainwright. البيع مقابل 70% من السعر النقدي. الإعدادات العامة والأوامر ومطرقة الصيانة في config/wagon_settings.lua، والموديلات والأسعار والمخزون والحالة والوظائف في config/wagons.lua، ومواقع المعاينة والاستدعاء في config/wagon_sites.lua.

خيار إعطاء عربة في الأدمن مرتبط بتصدير GrantWagon من jrs_stables، بعد تحقق الأدمن المعتاد من صلاحية give_wagon. يستخدم جدول الملكية نفسه بدل الكتابة إلى جدول wagons غير مستخدم. لا يقبل التصدير استدعاء من العميل أو من مورد غير مسموح.

## التحقق

اجتازت الملفات فحص صياغة Lua، ومحاكاة وظائف العميل والسيرفر (الملكية، الشراء والإرجاع عند الفشل، الحدود، الاستدعاء، المخزون، الصيانة، الحالة، البيع ونقل الملكية)، وفحص المتصفح للغتين وأزرار الماوس والتسمية والتبديل والشراء والشفافية وأحجام الشاشة. اجتاز ربط إعطاء العربات فحص صلاحيات الأدمن أيضًا.

لم يُعد تشغيل السيرفر أثناء التعديل ولم تُنفذ عمليات على قاعدة بياناته. المعاينة الفعلية للموديلات والقيادة داخل RedM تحتاج اختبارًا داخل اللعبة بعد إعادة تشغيل المورد.

تستخدم الإضافة ملفات Lua وJavaScript واضحة، مع تعديلات محدودة على حزمة Vue الحالية لتجاوز اختيار جنس العربة وإخفاء متجر تجهيزات الخيل في تبويب العربات. تطوير تكامل JRS وتعديلاته باسم JRS TEAM. إسناد الأجزاء الموروثة وترخيصها محفوظان في licenses/THIRD-PARTY.md وlicenses/GPL-3.0.txt.

## English

Wagons are a second family in the existing stable UI. Purchase the 24 supplied models with cash or gold, name them in the mouse dialog, and manage selection, renaming, sale, spawn/return, cargo, repair, brakes and nearby ownership transfers. Existing horse/tack functionality remains available in the Horses tab. Language follows the character's replicated jrsLanguage setting.

Press J during gameplay to spawn the selected wagon. The shortcut is suspended while a menu, text input or pause screen is open. Wagon actions use the same textured slots as horses: Spawn Wagon, Return Wagon, Wagon Inventory, Repair Wagon and Transfer Ownership. Floating horse and wagon name tags are disabled; owned names remain in the stable menu. This UI/control update only requires `restart jrs_stables`.

JRS Stables is maintained as a JRS TEAM integration using jrs_core, jrs_inventory and oxmysql. The player_wagons schema is created automatically; existing legacy rows remain and receive a condition column. Model, price, capacity, job and condition settings are in config/wagons.lua; general limits, commands and the existing hammer repair item are in config/wagon_settings.lua. A transfer includes the cargo. Return the wagon before transferring/selling; empty cargo before selling. Third-party attribution and licensing are in licenses/THIRD-PARTY.md and licenses/GPL-3.0.txt.

The server validates ownership, source prices, payment, limits, entity registration and nearby storage access. Native JRS storage handlers perform item/weapon transfers. The admin grant uses the trusted server-only GrantWagon export. Automated checks passed outside RedM; in-game model spawning/driving still needs verification after restarting jrs_stables and jrs_admin.
