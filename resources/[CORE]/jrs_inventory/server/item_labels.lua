-- ---------------------------------------------------------------------------
-- Translated item names
--
-- Item labels and descriptions live in the `items` database table, not in a
-- locale pack: they are data the server owner edits, and there are well over a
-- thousand of them. So the translation lives beside the English, one nullable
-- column per language:
--
--     items.label          "Bear Pelt"      <- the English source, unchanged
--     items.label_ar       "فروة دب"        <- NULL until translated
--     items.descriptions   / descriptions_ar
--
-- A NULL simply falls back to the English, so an untranslated item is readable
-- rather than blank, and the columns can be filled in over time without
-- touching any code.
--
-- The columns are created on boot when missing, the same way jrs_core adds
-- users.language, so no migration has to be applied by hand.
-- ---------------------------------------------------------------------------

local COLUMNS = {
    { name = 'label_ar', definition = 'VARCHAR(100) NULL DEFAULT NULL AFTER `label`' },
    { name = 'descriptions_ar', definition = 'VARCHAR(255) NULL DEFAULT NULL AFTER `descriptions`' },
}

local function ensureColumn(entry, done)
    exports.oxmysql:execute([[
        SELECT COUNT(*) AS present
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'jrs_items'
          AND COLUMN_NAME = @column
    ]], { column = entry.name }, function(result)
        local present = result and result[1] and tonumber(result[1].present) or 0
        if present > 0 then
            if done then done() end
            return
        end

        exports.oxmysql:execute(
            ('ALTER TABLE `jrs_items` ADD COLUMN `%s` %s'):format(entry.name, entry.definition),
            {},
            function()
                print(('[jrs_inventory] items.%s column created.'):format(entry.name))
                if done then done() end
            end
        )
    end)
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do Wait(250) end
    for _, entry in ipairs(COLUMNS) do
        ensureColumn(entry)
        Wait(150)
    end
end)

-- ---------------------------------------------------------------------------
-- Resolution
-- ---------------------------------------------------------------------------

--- The column that holds a given language's text, or nil for the English base.
local function columnFor(language, field)
    local code = JrsLang.Normalize(language)
    if not code or code == 'en' then return nil end
    return field .. '_' .. code
end

--- Pick the right label out of an item definition for one language.
--- Falls back to the English column, then to the raw item name.
local function pick(definition, itemName, language, field)
    if type(definition) ~= 'table' then return field == 'descriptions' and '' or tostring(itemName or '') end

    local column = columnFor(language, field)
    if column then
        local translated = definition[column]
        if type(translated) == 'string' and translated ~= '' then
            return translated
        end
        local catalog = JrsItemTranslations and JrsItemTranslations[tostring(itemName or ''):lower()]
        if catalog then
            local translated = catalog[field]
            if type(translated) == 'string' and translated ~= '' then return translated end
        end
    end

    local base = definition[field]
    -- Old imports contain numeric IDs or the column name, not descriptions.
    if field == 'descriptions' and (base == 'descriptions' or tostring(base or ''):match('^%d+$')) then return '' end
    if type(base) == 'string' and base ~= '' then return base end
    return field == 'descriptions' and '' or tostring(itemName or '')
end

--- The item's name as player `source` should read it.
--- This is the one every player-facing message and payload should use.
function ItemLabelFor(source, itemName)
    local name = tostring(itemName or '')
    local definition = (itemTableForData and itemTableForData[name]) or (itemTableForDataLower and itemTableForDataLower[name:lower()])
    return pick(definition, name, JrsLang.Of(source), 'label')
end

--- The item's description as player `source` should read it.
function ItemDescriptionFor(source, itemName)
    local name = tostring(itemName or '')
    local definition = (itemTableForData and itemTableForData[name]) or (itemTableForDataLower and itemTableForDataLower[name:lower()])
    return pick(definition, name, JrsLang.Of(source), 'descriptions')
end

--- Same, but for a definition table already in hand (the inventory payload
--- builder walks definitions rather than names).
function ItemLabelFromDefinition(source, definition, itemName)
    return pick(definition, itemName, JrsLang.Of(source), 'label')
end

function ItemDescriptionFromDefinition(source, definition, itemName)
    return pick(definition, itemName, JrsLang.Of(source), 'descriptions')
end

exports('GetItemLabel', function(playerSource, itemName)
    return ItemLabelFor(playerSource, itemName)
end)

--- The item's English label, whatever the caller's language.
--- Callers use it to tell a stock item name apart from a custom one an owner
--- typed in: a label that already differs from this is not a translation
--- candidate and must be left exactly as it is.
exports('GetItemLabelEnglish', function(itemName)
    local name = tostring(itemName or '')
    local definition = itemTableForData and itemTableForData[name]
    return pick(definition, name, 'en', 'label')
end)

exports('GetItemDescription', function(playerSource, itemName)
    return ItemDescriptionFor(playerSource, itemName)
end)
