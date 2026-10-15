-- Generated 2026-09-29 from shared/clothing/assets.lua (jrs_clothing 3.10.3).
-- NPC trousers whose source NPC outfits never had a separate boots item AND
-- never had a lower-body (legs) mesh: on those NPCs the trousers were the legs
-- and the shoes/gaiters in one mesh, so a boot always comes with them.
-- Smart body fit wears them with NO lower-body mesh, exactly like the NPC:
-- any leg mesh underneath pokes through (crotch) and shows at the calves.
-- Regenerate if assets.lua changes. Indices are ClothingAssets[gender].pants.
BuiltInFootwearPants = {
    ["male"] = { -- 145 pants
        [1]=true, [3]=true, [4]=true, [5]=true, [6]=true, [7]=true, [8]=true, [9]=true, [10]=true, [11]=true, [12]=true, [13]=true, [14]=true, [16]=true, [17]=true, [18]=true,
        [19]=true, [20]=true, [21]=true, [22]=true, [24]=true, [25]=true, [28]=true, [29]=true, [30]=true, [31]=true, [32]=true, [33]=true, [35]=true, [36]=true, [38]=true, [39]=true,
        [41]=true, [42]=true, [43]=true, [45]=true, [46]=true, [47]=true, [48]=true, [49]=true, [51]=true, [54]=true, [55]=true, [57]=true, [58]=true, [59]=true, [60]=true, [65]=true,
        [67]=true, [68]=true, [69]=true, [70]=true, [71]=true, [72]=true, [73]=true, [74]=true, [75]=true, [78]=true, [79]=true, [80]=true, [81]=true, [86]=true, [88]=true, [89]=true,
        [90]=true, [92]=true, [93]=true, [98]=true, [102]=true, [103]=true, [106]=true, [112]=true, [113]=true, [114]=true, [119]=true, [120]=true, [124]=true, [179]=true, [182]=true, [184]=true,
        [185]=true, [219]=true, [249]=true, [294]=true, [295]=true, [333]=true, [335]=true, [338]=true, [341]=true, [345]=true, [346]=true, [350]=true, [351]=true, [352]=true, [373]=true, [374]=true,
        [380]=true, [383]=true, [391]=true, [393]=true, [395]=true, [396]=true, [397]=true, [398]=true, [400]=true, [401]=true, [406]=true, [424]=true, [429]=true, [430]=true, [434]=true, [435]=true,
        [446]=true, [447]=true, [450]=true, [455]=true, [460]=true, [461]=true, [464]=true, [466]=true, [470]=true, [472]=true, [475]=true, [477]=true, [480]=true, [484]=true, [485]=true, [491]=true,
        [494]=true, [495]=true, [496]=true, [497]=true, [500]=true, [503]=true, [506]=true, [508]=true, [513]=true, [515]=true, [516]=true, [517]=true, [521]=true, [523]=true, [525]=true, [527]=true,
        [530]=true,
    },
    ["female"] = { -- 14 pants
        [1]=true, [5]=true, [6]=true, [32]=true, [37]=true, [43]=true, [47]=true, [50]=true, [52]=true, [58]=true, [63]=true, [65]=true, [68]=true, [70]=true,
    },
}

function HasBuiltInFootwear(gender, category, assetIndex)
    if category ~= "pants" then return false end
    local list = BuiltInFootwearPants[gender]
    return list ~= nil and list[tonumber(assetIndex) or 0] == true
end
