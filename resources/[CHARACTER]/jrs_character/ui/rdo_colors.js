// ============================================================================
// Red Dead Online Authentic Color Palettes (Hair, Makeup, and Clothing)
// Built specifically for 1899 realism, matching Red Dead Online standards.
// ============================================================================

const RDO_HAIR_COLORS = [
    { id: 1,  name: "Jet Black",            name_ar: "أسود فاحم",          hex: "#151515", tint0: 0,   tint1: 0,   tint2: 0 },
    { id: 2,  name: "Raven Black",          name_ar: "أسود طبيعي",         hex: "#211f1f", tint0: 1,   tint1: 1,   tint2: 1 },
    { id: 3,  name: "Dark Espresso",        name_ar: "إسبريسو داكن",       hex: "#2c1f19", tint0: 2,   tint1: 2,   tint2: 2 },
    { id: 4,  name: "Dark Chocolate",       name_ar: "شوكولاتة داكنة",     hex: "#38241a", tint0: 3,   tint1: 3,   tint2: 3 },
    { id: 5,  name: "Rich Chestnut",        name_ar: "كستنائي دافئ",       hex: "#442b1d", tint0: 4,   tint1: 4,   tint2: 4 },
    { id: 6,  name: "Medium Brown",         name_ar: "بني متوسط",          hex: "#533524", tint0: 5,   tint1: 5,   tint2: 5 },
    { id: 7,  name: "Cinnamon Brown",       name_ar: "بني قرفي",           hex: "#613c27", tint0: 6,   tint1: 6,   tint2: 6 },
    { id: 8,  name: "Light Ash Brown",      name_ar: "بني رمادي فاتح",     hex: "#6b4b35", tint0: 7,   tint1: 7,   tint2: 7 },
    { id: 9,  name: "Sandy Brown",          name_ar: "بني رملي",           hex: "#7a583e", tint0: 8,   tint1: 8,   tint2: 8 },
    { id: 10, name: "Dirty Blonde",         name_ar: "أشقر رمادي داكن",    hex: "#886948", tint0: 9,   tint1: 9,   tint2: 9 },
    { id: 11, name: "Honey Blonde",         name_ar: "أشقر عسلي",          hex: "#9c7a50", tint0: 10,  tint1: 10,  tint2: 10 },
    { id: 12, name: "Golden Blonde",        name_ar: "أشقر ذهبي",          hex: "#b4935e", tint0: 11,  tint1: 11,  tint2: 11 },
    { id: 13, name: "Sandy Blonde",         name_ar: "أشقر رملي",          hex: "#c1a06c", tint0: 12,  tint1: 12,  tint2: 12 },
    { id: 14, name: "Light Natural Blonde", name_ar: "أشقر طبيعي فاتح",    hex: "#d3b47f", tint0: 13,  tint1: 13,  tint2: 13 },
    { id: 15, name: "Platinum Ash Blonde",  name_ar: "أشقر بلاتيني",       hex: "#ded0a5", tint0: 14,  tint1: 14,  tint2: 14 },
    { id: 16, name: "Deep Auburn",          name_ar: "أوبورن داكن",        hex: "#491d15", tint0: 15,  tint1: 15,  tint2: 15 },
    { id: 17, name: "Dark Chestnut Red",    name_ar: "كستنائي أحمر",       hex: "#592217", tint0: 16,  tint1: 16,  tint2: 16 },
    { id: 18, name: "Irish Ginger",         name_ar: "أحمر زنجبيلي أيرلندي", hex: "#772d19", tint0: 17, tint1: 17, tint2: 17 },
    { id: 19, name: "Bright Copper",        name_ar: "نحاسي ساطع",         hex: "#8c361b", tint0: 18,  tint1: 18,  tint2: 18 },
    { id: 20, name: "Strawberry Blonde",    name_ar: "أشقر فراولة",        hex: "#a25336", tint0: 19,  tint1: 19,  tint2: 19 },
    { id: 21, name: "Salt & Pepper",        name_ar: "ملح وفلفل (شيب خفيف)", hex: "#444341", tint0: 145, tint1: 145, tint2: 145 },
    { id: 22, name: "Charcoal Gray",        name_ar: "رمادي فحمي",         hex: "#363638", tint0: 148, tint1: 148, tint2: 148 },
    { id: 23, name: "Steel Gray",           name_ar: "رمادي فولاذي",       hex: "#5f5e63", tint0: 152, tint1: 152, tint2: 152 },
    { id: 24, name: "Silver Fox",           name_ar: "فضي أنيق",           hex: "#858488", tint0: 156, tint1: 156, tint2: 156 },
    { id: 25, name: "Aged Gray",            name_ar: "رمادي مسنّ",         hex: "#ababaf", tint0: 160, tint1: 160, tint2: 160 },
    { id: 26, name: "Pure White",           name_ar: "أبيض ناصع",          hex: "#dedee2", tint0: 161, tint1: 161, tint2: 161 }
];

const RDO_MAKEUP_PALETTES = {
    lipsticks: [
        { id: 1,  name: "Natural Nude",    name_ar: "نود طبيعي",         hex: "#9b6059", paletteId: 1,  tint: 12 },
        { id: 2,  name: "Dusty Rose",      name_ar: "وردي مغبر",         hex: "#a65c66", paletteId: 2,  tint: 18 },
        { id: 3,  name: "Soft Peach",      name_ar: "خوخي هادئ",         hex: "#b8685b", paletteId: 3,  tint: 24 },
        { id: 4,  name: "Warm Terracotta", name_ar: "طوبي دافئ",         hex: "#a6503e", paletteId: 4,  tint: 30 },
        { id: 5,  name: "Vintage Brick",   name_ar: "أحمر قرميدي عتيق",   hex: "#993a32", paletteId: 5,  tint: 36 },
        { id: 6,  name: "Classic Crimson", name_ar: "عنابي كلاسيكي",     hex: "#8c2326", paletteId: 6,  tint: 42 },
        { id: 7,  name: "Deep Ruby",       name_ar: "ياقوتي عميق",       hex: "#781a22", paletteId: 7,  tint: 48 },
        { id: 8,  name: "Wild Berry",      name_ar: "توتي بري",          hex: "#6d1f36", paletteId: 8,  tint: 54 },
        { id: 9,  name: "Victorian Plum",  name_ar: "برقوقي فيكتوري",    hex: "#5c223c", paletteId: 9,  tint: 60 },
        { id: 10, name: "Dark Wine",       name_ar: "نبيذي داكن",        hex: "#4d1626", paletteId: 10, tint: 66 },
        { id: 11, name: "Warm Cocoa",      name_ar: "كاكاو دافئ",        hex: "#6e4036", paletteId: 11, tint: 72 },
        { id: 12, name: "Deep Mahogany",   name_ar: "ماهوجني داكن",      hex: "#4b2925", paletteId: 12, tint: 80 }
    ],
    shadows: [
        { id: 1,  name: "Smoky Charcoal",  name_ar: "فحمي دخاني",        hex: "#2c2a2b", paletteId: 1,  tint: 8 },
        { id: 2,  name: "Soft Ash Brown",  name_ar: "بني رمادي ناعم",    hex: "#4a413d", paletteId: 2,  tint: 16 },
        { id: 3,  name: "Earth Taupe",     name_ar: "رمادي ترابي",       hex: "#614f47", paletteId: 3,  tint: 24 },
        { id: 4,  name: "Warm Chestnut",   name_ar: "كستنائي دافئ",      hex: "#563a30", paletteId: 4,  tint: 32 },
        { id: 5,  name: "Golden Amber",    name_ar: "كهرماني ذهبي",      hex: "#7d5937", paletteId: 5,  tint: 40 },
        { id: 6,  name: "Burnished Copper",name_ar: "نحاسي محروق",       hex: "#73402d", paletteId: 6,  tint: 48 },
        { id: 7,  name: "Dark Walnut",     name_ar: "جوزي داكن",         hex: "#382b27", paletteId: 7,  tint: 56 },
        { id: 8,  name: "Plum Smoke",      name_ar: "دخان برقوقي",       hex: "#45303c", paletteId: 8,  tint: 64 },
        { id: 9,  name: "Soft Terracotta", name_ar: "طوبي ناعم",         hex: "#6e4438", paletteId: 9,  tint: 72 },
        { id: 10, name: "Deep Espresso",   name_ar: "إسبريسو عميق",      hex: "#271e1a", paletteId: 10, tint: 80 }
    ],
    blush: [
        { id: 1, name: "Natural Flush",    name_ar: "تورّد طبيعي خفيف",   hex: "#c07e79", paletteId: 1,  tint: 12 },
        { id: 2, name: "Rosy Glow",        name_ar: "وهج وردي",          hex: "#b5696c", paletteId: 2,  tint: 22 },
        { id: 3, name: "Warm Peach",       name_ar: "خوخي دافئ",         hex: "#c47963", paletteId: 3,  tint: 30 },
        { id: 4, name: "Muted Rosewood",   name_ar: "خشب الورد الهادئ",   hex: "#a3615e", paletteId: 4,  tint: 38 },
        { id: 5, name: "Subtle Terracotta",name_ar: "طوبي هادئ",         hex: "#995747", paletteId: 5,  tint: 46 },
        { id: 6, name: "Sun-Kissed",       name_ar: "مشمشي مشرق",        hex: "#b47350", paletteId: 6,  tint: 54 },
        { id: 7, name: "Vintage Mauve",    name_ar: "موف عتيق",          hex: "#8f5360", paletteId: 7,  tint: 62 },
        { id: 8, name: "Deep Berry Glow",  name_ar: "توتي دافئ",         hex: "#783e47", paletteId: 8,  tint: 70 }
    ],
    eyeliners: [
        { id: 1, name: "Kohl Black",       name_ar: "أسود كحل",          hex: "#191819", paletteId: 1,  tint: 6 },
        { id: 2, name: "Soft Charcoal",    name_ar: "فحمي هادئ",         hex: "#272526", paletteId: 2,  tint: 14 },
        { id: 3, name: "Deep Slate",       name_ar: "رمادي حجري داكن",   hex: "#343335", paletteId: 3,  tint: 24 },
        { id: 4, name: "Dark Espresso",    name_ar: "إسبريسو داكن",       hex: "#2f221e", paletteId: 4,  tint: 36 },
        { id: 5, name: "Warm Umber",       name_ar: "بني ترابي محروق",   hex: "#403027", paletteId: 5,  tint: 48 },
        { id: 6, name: "Smoky Granite",    name_ar: "جرانيتي دخاني",     hex: "#3b3b42", paletteId: 6,  tint: 60 }
    ],
    foundation: [
        { id: 1, name: "Porcelain Fair",   name_ar: "بورسلين فاتح",      hex: "#e4c5b1", paletteId: 1,  tint: 6 },
        { id: 2, name: "Natural Ivory",    name_ar: "عاجي طبيعي",        hex: "#dcba9c", paletteId: 2,  tint: 16 },
        { id: 3, name: "Warm Sand",        name_ar: "رملي دافئ",         hex: "#d0a887", paletteId: 3,  tint: 26 },
        { id: 4, name: "Golden Tan",       name_ar: "حنطي ذهبي",         hex: "#c1946e", paletteId: 4,  tint: 36 },
        { id: 5, name: "Sunlit Bronze",    name_ar: "برونزي مشمس",       hex: "#ac7c55", paletteId: 5,  tint: 46 },
        { id: 6, name: "Rich Amber",       name_ar: "كهرماني غني",       hex: "#90603b", paletteId: 6,  tint: 56 },
        { id: 7, name: "Deep Cocoa",       name_ar: "كاكاو دافئ",        hex: "#6e4427", paletteId: 7,  tint: 66 },
        { id: 8, name: "Deep Espresso",    name_ar: "إسبريسو عميق",      hex: "#4d2e19", paletteId: 8,  tint: 76 }
    ],
    paintedmasks: [
        { id: 1, name: "War Paint Red",    name_ar: "أحمر صبغي حربي",    hex: "#8a231f", paletteId: 1,  tint: 20 },
        { id: 2, name: "Clay White",       name_ar: "أبيض طيني",         hex: "#dad6cd", paletteId: 2,  tint: 20 },
        { id: 3, name: "Coal Black",       name_ar: "أسود كربوني",       hex: "#1b1a19", paletteId: 3,  tint: 20 },
        { id: 4, name: "Earth Ochre",      name_ar: "أصفر مغرة ترابي",   hex: "#bf8932", paletteId: 4,  tint: 20 },
        { id: 5, name: "Dusty Turquoise",  name_ar: "فيروزي هادئ",       hex: "#3d6b69", paletteId: 5,  tint: 20 },
        { id: 6, name: "Spirit Indigo",    name_ar: "نيلي طبيعي",        hex: "#2c3b52", paletteId: 6,  tint: 20 },
        { id: 7, name: "Terracotta Earth", name_ar: "ترابي فخاري",       hex: "#7d3f2c", paletteId: 7,  tint: 20 },
        { id: 8, name: "Forest Moss",      name_ar: "أخضر طحلبي",        hex: "#3d4b32", paletteId: 8,  tint: 20 }
    ]
};

const RDO_CLOTHING_DYES = [
    { id: 1,  name: "Worn Coal Black",      name_ar: "أسود فحمي عتيق",    hex: "#1b1b1b" },
    { id: 2,  name: "Charcoal Tweed",       name_ar: "تويد رمادي غامق",   hex: "#2d2e31" },
    { id: 3,  name: "Aged Espresso Leather",name_ar: "جلد إسبريسو معتق",  hex: "#31231c" },
    { id: 4,  name: "Saddle Brown Leather", name_ar: "جلد بني سرج",       hex: "#4a3221" },
    { id: 5,  name: "Oiled Chestnut",       name_ar: "كستنائي مزيّت",     hex: "#563622" },
    { id: 6,  name: "Raw Sienna Leather",   name_ar: "جلد سيينا طبيعي",   hex: "#6f4426" },
    { id: 7,  name: "Dark Terracotta",      name_ar: "طوبي فخاري داكن",   hex: "#662e21" },
    { id: 8,  name: "Frontier Brick Red",   name_ar: "أحمر قرميدي عتيق",   hex: "#732520" },
    { id: 9,  name: "Madder Crimson Wool",  name_ar: "صوف قرمزي تقليدي",  hex: "#561a1a" },
    { id: 10, name: "Indigo Denim Blue",    name_ar: "دنيم أزرق نيلي",    hex: "#222c3f" },
    { id: 11, name: "Weathered Navy Wool",  name_ar: "صوف كحلي قديم",     hex: "#192233" },
    { id: 12, name: "Deep Forest Green",    name_ar: "أخضر غابات داكن",   hex: "#1d2a20" },
    { id: 13, name: "Dusty Sage Olive",    name_ar: "زيتي ترابي هادئ",   hex: "#363d2f" },
    { id: 14, name: "Prairie Tan Canvas",   name_ar: "قماش كانفاس بري",   hex: "#755e41" },
    { id: 15, name: "Light Duck Canvas",   name_ar: "كانفاس كاكي فاتح",  hex: "#917c5b" },
    { id: 16, name: "Raw Flax Linen",       name_ar: "كتان كتاني خام",    hex: "#c2b79a" },
    { id: 17, name: "Natural Cotton",       name_ar: "قطن طبيعي كلاسيكي", hex: "#d9d3c3" },
    { id: 18, name: "Ash Heather Wool",     name_ar: "صوف رمادي ترابي",   hex: "#535250" },
    { id: 19, name: "Silver Grey Cloth",    name_ar: "قماش رمادي فضي",   hex: "#787878" },
    { id: 20, name: "Deep Tobacco Brown",   name_ar: "بني تبغي داكن",     hex: "#3a2515" }
];

// Calculate a realistic color swatch representation for clothing variants
function getRdoClothingVariantColor(option, index) {
    if (!option) return RDO_CLOTHING_DYES[index % RDO_CLOTHING_DYES.length].hex;
    
    const t0 = Number(option.tint0 || 0);
    const t1 = Number(option.tint1 || 0);
    const t2 = Number(option.tint2 || 0);

    if (t0 > 0 || t1 > 0 || t2 > 0) {
        const r = Math.min(235, Math.max(22, Math.round(t0 * 0.9 + 18)));
        const g = Math.min(235, Math.max(22, Math.round(t1 * 0.85 + 16)));
        const b = Math.min(235, Math.max(22, Math.round(t2 * 0.8 + 14)));
        return `rgb(${r}, ${g}, ${b})`;
    }

    return RDO_CLOTHING_DYES[index % RDO_CLOTHING_DYES.length].hex;
}

window.RDO_HAIR_COLORS = RDO_HAIR_COLORS;
window.RDO_MAKEUP_PALETTES = RDO_MAKEUP_PALETTES;
window.RDO_CLOTHING_DYES = RDO_CLOTHING_DYES;
window.getRdoClothingVariantColor = getRdoClothingVariantColor;
