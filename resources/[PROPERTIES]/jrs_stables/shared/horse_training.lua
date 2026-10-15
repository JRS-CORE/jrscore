HorseAbilities = {}
local Settings = Config.HorseTraining
local modelBreeds = {}
for _, breed in ipairs(Horses) do
    for model in pairs(breed.colors) do modelBreeds[model:lower()] = breed.breed end
end
local function bound(value, low, high)
    value = tonumber(value)
    if not value or value ~= value then value = low end
    return math.max(low, math.min(high, value))
end
function HorseAbilities.Profile(model)
    model = tostring(model or ''):lower()
    local profile = Settings.models[model] or Settings.breeds[modelBreeds[model]] or Settings.defaults
    local result = {}
    for _, key in ipairs({'health', 'stamina'}) do
        local cfg = profile[key] or Settings.defaults[key]
        local start = math.floor(bound(cfg.start, 1, 10))
        result[key] = { start=start, max=math.floor(bound(cfg.max, start, 10)) }
    end
    return result
end
function HorseAbilities.Stats(model, healthXp, staminaXp)
    local profile = HorseAbilities.Profile(model)
    local target = math.max(1, tonumber(Settings.xpToMax) or 100)
    local result = { maxLevel=4, revivePrice=math.max(0, tonumber(Settings.revivePrice) or 10) }
    local progress = 1
    for _, key in ipairs({'health','stamina'}) do
        local xp = math.floor(bound(key == 'health' and healthXp or staminaXp, 0, target))
        local p = profile[key]
        local ratio = p.max == p.start and 1 or xp / target
        result[key] = { start=p.start, max=p.max, value=math.floor(p.start + (p.max-p.start)*ratio),
            xp=xp, xpToMax=target, percent=math.floor(ratio*100) }
        progress = math.min(progress, ratio)
    end
    -- Both abilities must be fully trained before the horse reaches level 4.
    result.level = math.min(4, 1 + math.floor(progress * 3))
    return result
end
local labels = {
    en = {
        horseHealth='Health', horseStamina='Stamina', horseLevel='Level', horseCeiling='Training ceiling',
        horseSelected='Selected for whistle / call', horseSelect='Use This Horse', horseCall='Call Horse',
        horseDead='Needs revival', horseRevive='Revive', horseTrainHealth='Train Health', horseTrainStamina='Train Stamina',
        horseTraining='Training', horseMaxed='Fully trained', horseTrainingHint='Health: care beside your horse. Stamina: ride or lead it.',
        horseSelectedNotice='This horse will answer your next whistle or call.', horseRevivedNotice='Horse revived.',
        horseInvalid='Invalid horse or action.', horseForbidden='You do not own this horse.', horseTooFar='Move closer to the stable or horse.',
        horseCash='Not enough cash to revive the horse.', horseAlive='This horse does not need revival.',
        horseNeedRevive='Revive this horse at a stable before calling or training it.',
        horseCallFirst='Call this horse first, then open the stable to start its training.',
        horseBusy='Finish the current horse action or training first.', horseUnavailable='Horse care is temporarily unavailable.',
        horseHealthStarted='Care for your horse while standing beside it. Delete cancels training.',
        horseStaminaStarted='Ride or lead your horse for the training distance. Delete cancels training.',
        horseTrainingComplete='Training completed.', horseTrainingCancelled='Training cancelled; no XP was awarded.',
        horseCooldown='Your horse needs a short rest before training again.', horseTrainingSeconds='seconds',
        horseCore='Current condition', horsePurchaseStats='Starting abilities',
    },
    ar = {
        horseHealth='الصحة', horseStamina='التحمّل', horseLevel='المستوى', horseCeiling='سقف التدريب',
        horseSelected='الحصان المحدد للصفير والاستدعاء', horseSelect='اختيار هذا الحصان', horseCall='استدعاء الحصان',
        horseDead='يحتاج إنعاش', horseRevive='إنعاش', horseTrainHealth='تدريب الصحة', horseTrainStamina='تدريب التحمّل',
        horseTraining='التدريب', horseMaxed='اكتمل التدريب', horseTrainingHint='الصحة: العناية قرب الحصان. التحمّل: الركوب أو قيادة الحصان.',
        horseSelectedNotice='هذا الحصان سيأتي عند الصفير أو الاستدعاء القادم.', horseRevivedNotice='تم إنعاش الحصان.',
        horseInvalid='الحصان أو الإجراء غير صالح', horseForbidden='هذا الحصان ليس ملكك', horseTooFar='اقترب من الإسطبل أو الحصان',
        horseCash='النقود غير كافية لإنعاش الحصان', horseAlive='هذا الحصان لا يحتاج إنعاشًا',
        horseNeedRevive='أنعش هذا الحصان في الإسطبل قبل استدعائه أو تدريبه',
        horseCallFirst='استدعِ هذا الحصان أولًا، ثم افتح الإسطبل لبدء تدريبه',
        horseBusy='أنهِ إجراء الحصان أو التدريب الحالي أولًا', horseUnavailable='العناية بالخيل غير متاحة مؤقتًا',
        horseHealthStarted='اعتنِ بالحصان وأنت واقف بجانبه. زر Delete يلغي التدريب.',
        horseStaminaStarted='اركب الحصان أو قُده لمسافة التدريب. زر Delete يلغي التدريب.',
        horseTrainingComplete='اكتمل التدريب', horseTrainingCancelled='تم إلغاء التدريب، لم تُضف نقاط',
        horseCooldown='يحتاج الحصان استراحة قصيرة قبل التدريب مجددًا', horseTrainingSeconds='ثانية',
        horseCore='الحالة الحالية', horsePurchaseStats='القدرات عند الشراء',
    },
}
function HorseTranslations(src) return labels[StableLanguage(src)] end
function HorseText(key, src) return HorseTranslations(src)[key] or labels.en[key] or key end
