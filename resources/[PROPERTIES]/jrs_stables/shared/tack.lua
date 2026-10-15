-- Saved tack stays an array for the stable UI, even when legacy JSON has holes.
StableTack = {
    order = {'Saddlecloths','Saddles','Stirrups','SaddleBags','SaddleHorns','Bedrolls',
             'Manes','Tails','Masks','Mustaches','Holsters','Bridles','Horseshoes'},
    categories = {
        Saddlecloths=0x17CEB41A, Saddles=0xBAA7E618, Stirrups=0xDA6DADCA,
        SaddleBags=0x80451C25, SaddleHorns=0x05447332, Bedrolls=0xEFB31921,
        Manes=0xAA0217AB, Tails=0xA63CAE10, Masks=0xD3500E5D,
        Mustaches=0x30DEFDDF, Holsters=0xAC106B30, Bridles=0x94B2E3AF, Horseshoes=0xFACFC3C0,
    },
    items = {},
}
function StableTack.Hash(value)
    local n = tonumber(value)
    if not n or n ~= n or n % 1 ~= 0 or n == 0 or n < -2147483648 or n > 4294967295 then return end
    return n % 4294967296
end
for category, items in pairs(HorseComp) do
    for _, item in ipairs(items) do
        StableTack.items[StableTack.Hash(item.hash)] = {category=category, item=item}
    end
end
function StableTack.Decode(raw)
    if type(raw) == 'string' then
        local ok, decoded = pcall(json.decode, raw)
        if not ok then return {} end
        raw = decoded
    end
    return type(raw) == 'table' and raw or {}
end
function StableTack.State(raw)
    local state, extras, seen = {}, {}, {}
    local entries = {}
    for key, value in pairs(StableTack.Decode(raw)) do
        entries[#entries+1] = {key=tostring(key), value=value}
    end
    table.sort(entries, function(a,b)
        local x,y=tonumber(a.key),tonumber(b.key)
        if x and y then return x<y end
        return a.key<b.key
    end)
    for _, entry in ipairs(entries) do
        local hash = StableTack.Hash(entry.value)
        if hash then
            local found = StableTack.items[hash]
            if found then state[found.category]=found.item.hash
            elseif not seen[hash] then extras[#extras+1]=string.format('0x%08X',hash) end
            seen[hash]=true
        end
    end
    return state, extras
end
function StableTack.Pack(state, extras)
    local list = {}
    for _, category in ipairs(StableTack.order) do
        local hash = state[category]
        if StableTack.Hash(hash) then list[#list+1]=hash end
    end
    for _, hash in ipairs(extras or {}) do list[#list+1]=hash end
    return list
end
function StableTack.List(raw)
    local state, extras = StableTack.State(raw)
    return StableTack.Pack(state, extras)
end
