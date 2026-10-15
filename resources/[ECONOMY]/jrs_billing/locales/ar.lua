Locales = Locales or {}
Locales["ar"] = Locales["ar"] or {}
for k, v in pairs({
    billing_not_allowed = "ما عندك صلاحية تكتب فاتورة",
    billing_self = "ما تقدر تكتب فاتورة لنفسك",
    billing_not_found = "اللاعب غير موجود",
    billing_too_far = "اللاعب بعيد عنك",
    billing_bad_amount = "مبلغ غير صحيح (الحد $%s)",
    billing_no_money = "اللاعب ما عنده فلوس كافية",
    billing_sent = "تم إرسال فاتورة إلى %s بمبلغ $%s",
    billing_received = "دفعت فاتورة بمبلغ $%s إلى %s - %s",
    billing_receipt = "إيصال<br>المبلغ: $%s<br>من: %s<br>التاريخ: %s<br>السبب: %s",
    billing_suggestion = "اكتب فاتورة للاعب قريب",
}) do Locales["ar"][k] = v end
