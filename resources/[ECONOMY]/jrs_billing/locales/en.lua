Locales = Locales or {}
Locales["en"] = Locales["en"] or {}
for k, v in pairs({
    billing_not_allowed = "You are not allowed to bill",
    billing_self = "You cannot bill yourself",
    billing_not_found = "Player not found",
    billing_too_far = "The player is too far away",
    billing_bad_amount = "Invalid amount (max $%s)",
    billing_no_money = "The player does not have enough money",
    billing_sent = "Bill sent to %s for $%s",
    billing_received = "You paid a bill of $%s to %s - %s",
    billing_receipt = "Receipt<br>Amount: $%s<br>Billed by: %s<br>Date: %s<br>Reason: %s",
    billing_suggestion = "Bill a nearby player",
}) do Locales["en"][k] = v end
