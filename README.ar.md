<div align="center" dir="rtl">

<img src=".github/assets/banner.png" alt="JRS Core" width="100%">

# JRS Core

**فريمورك رول بلاي مجاني ومفتوح المصدر لـ RedM.**

[الشرح](https://docs.jrs-core.com) · [الديسكورد](https://discord.gg/jrscore) · [English](README.md)

</div>

<div dir="rtl">

## وش هو JRS Core؟

JRS Core باقة سيرفر RedM كاملة مبنية على كور واحد. كل السكربتات تستخدم نفس الـ API ونفس شكل الواجهات
ونفس قاعدة البيانات، فالسيرفر يشتغل من أول تشغيل.

- **74 سكربت** من JRS مصممة تشتغل مع بعض
- **تثبيت بضغطة وحدة** من txAdmin مع قاعدة البيانات
- **عربي وإنجليزي** في كل الواجهات
- **مجاني للأبد** تحت رخصة GNU GPL v3

## المتطلبات

- سيرفر RedM (آخر artifacts موصى بها) مع txAdmin
- قاعدة بيانات MariaDB أو MySQL
- مفتاح سيرفر من [بوابة Cfx.re](https://portal.cfx.re)
- تفعيل OneSync

## التثبيت

### الطريقة 1: من txAdmin (الأفضل)

1. افتح txAdmin واختر **Remote URL Template**.
2. الصق الرابط:
   ```
   https://raw.githubusercontent.com/JRS-CORE/jrscore/main/recipe/jrscore.yaml
   ```
3. txAdmin ينزّل كل السكربتات، يسوي قاعدة البيانات ويستورد الجداول، ويكتب `server.cfg` بنفسه.
4. شغّل السيرفر.

### الطريقة 2: بدون إنترنت

شغّل `INSTALL.bat` واكتب مجلد السيرفر وبيانات MySQL ومفتاح السيرفر.
المثبّت ينسخ السكربتات ويستورد `sql/jrscore.sql` ويكتب `server.cfg`.

### الطريقة 3: يدوي

1. انسخ مجلد `resources` لمجلد السيرفر.
2. استورد `sql/jrscore.sql` في قاعدة بيانات فاضية.
3. انسخ `server.cfg` وعدّل قيم `{{...}}`.

### بعد التثبيت

- خل `sv_enforceGameBuild 1491` في `server.cfg`.
- `oxmysql` و `jrs_core` لازم يشتغلون قبل كل شيء.
- عشان تصير أونر: حط الستيم هيكس حقك في `Config.CoreOwners` داخل
  `resources/[CORE]/jrs_core/config/config.lua`، أو خل `group` = `owner` في جدول `jrs_users`، ثم ادخل من جديد.

## أهم الإعدادات

| الملف | وش فيه |
|---|---|
| `jrs_core/config/config.lua` | اللغة الافتراضية، الوايتلست، فلوس وأغراض البداية، الأدمن، الأوامر |
| `jrs_core/config/levels.lua` | اللفلات والخبرة |
| `jrs_inventory/config/config.lua` | الوزن، الخانات، الأغراض |
| `jrs_character/config/config.lua` | أماكن السبون، عدد الشخصيات، المنشئ |
| `jrs_loadingscreen/web/config_main.js` | اسم السيرفر، الروابط، الفيديو والموسيقى |
| `jrs_loadingscreen/web/config_staff.js` | الطاقم، القوانين، الأخبار |

## المتاجر

- **JRS SOTR:** [jrs-sotr.tebex.io](https://jrs-sotr.tebex.io/)
- **Gum Scripts:** [gum-scripts.tebex.io](https://gum-scripts.tebex.io/)
## الدعم
- **الشرح الكامل:** [docs.jrs-core.com](https://docs.jrs-core.com)
- **المجتمع والدعم:** [discord.gg/jrscore](https://discord.gg/jrscore)
- **المشاكل والاقتراحات:** [افتح Issue](../../issues/new/choose)

## الفريق

| | الدور |
|---|---|
| **ALFIE** | المؤسس والمطور الرئيسي |
| **JRS** | مطور |
| **GM** | مدير المشروع |

## الرخصة

JRS Core برنامج حر تحت رخصة [GNU GPL v3](LICENSE). تقدر تستخدمه وتعدله وتشاركه، وأي شيء تبنيه عليه
لازم يبقى بنفس الرخصة مع إبقاء الحقوق.

</div>
