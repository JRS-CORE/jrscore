/* ══════════════════════════════════════════════════════════════
   jrs_huntingpets - NUI Script
   Keeps all NUI callback names expected by client_shop.lua
   ══════════════════════════════════════════════════════════════ */

var currentPetData = false;
var paymentMethod = 'cash';
var currentPet = {};
var myPets = [];
var currentIndex = '';
var state = {
    dogs: [],
    birds: [],
    birdCategories: [],
    ownedDogs: [],
    ownedBirds: [],
    activePet: 'None',
    modelNames: {},
    selectedDog: null,
    selectedBird: null,
    scavengerItems: [],
    fishItems: [],
    ui: {}
};

/* ─────────────── LOCALIZATION ───────────────
   English fallback text. The Lua side (client_shop.lua's GetUiLocale())
   sends the real strings resolved through the JRS kit's locale() -- keyed off
   the same names -- on every 'open'/'openDogAnims' NUI message. These
   defaults are only used if that hasn't arrived yet (or a key is missing),
   so the UI never shows a blank/undefined label. */
var DEFAULT_UI = {
    ui_back: 'Back', ui_close: 'Close', ui_header_title: 'Hunting Pets',
    ui_header_subtitle: 'Trapper & Kennel', ui_tab_shop: 'Shop', ui_tab_mypets: 'My Pets',
    ui_wallet_cash: 'Cash', ui_purchase_pet_title: 'Purchase Pet', ui_gold: 'Gold',
    ui_pet_name_label: 'Pet Name', ui_pet_name_placeholder: 'Name your pet',
    ui_cancel: 'Cancel', ui_buy: 'Buy', ui_animations_title: 'Animations',
    ui_put_dog_away: 'Put Dog Away', ui_commands_title: 'Commands',
    ui_dogs_title: 'Dogs', ui_dogs_desc: 'Loyal hunting companions',
    ui_birds_desc: 'Hunting birds for sale', ui_no_pets_available: 'No pets available today',
    ui_shelf_empty: 'This shelf is empty', ui_no_pets_owned: 'No pets owned',
    ui_no_animations_available: 'No animations available',
    ui_no_animations_for_pet: 'No animations for this pet',
    ui_no_commands_for_pet: 'No commands for this pet',
    ui_type_dog: 'Dog', ui_type_bird: 'Bird', ui_type_xp: 'Type %s • XP %s',
    ui_hunting_dog: 'Hunting Dog', ui_hunting_bird: 'Hunting Bird',
    ui_dead: 'Dead', ui_active: 'Active', ui_select_pet: 'Select as Default', ui_selected: 'Selected',
    ui_condition_title: 'Condition', ui_health: 'Health', ui_hunger: 'Hunger', ui_thirst: 'Thirst',
    ui_actions_title: 'Actions', ui_call_flee: 'Call / Flee', ui_call_pet: 'Call Pet',
    ui_feeding: 'Feeding', ui_drinking: 'Drinking', ui_carrying: 'Carrying',
    ui_commands: 'Commands', ui_follow_unfollow: 'Follow / Unfollow', ui_transfer: 'Transfer',
    ui_follow_position_title: 'Follow Position', ui_forward: 'Forward', ui_left: 'Left', ui_right: 'Right',
    ui_carry_anim: 'Carry', ui_take_shoulder: 'Take Shoulder',
    ui_please_select_pet: 'Please select a pet first',
    ui_toast_success: 'Success', ui_toast_error: 'Error', ui_toast_notice: 'Notice',
    ui_dog_actions_title: 'Dog Actions', ui_stop_animation: 'Stop Animation'
};

/* t('ui_type_xp', 'Dog', 5) -> "Type Dog • XP 5" (simple sequential %s substitution) */
function t(key) {
    var str = (state.ui && state.ui[key]) || DEFAULT_UI[key] || key;
    var args = Array.prototype.slice.call(arguments, 1);
    var i = 0;
    return str.replace(/%s/g, function () { return args[i++]; });
}

function applyUiLocale() {
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
        el.textContent = t(el.getAttribute('data-i18n'));
    });
    document.querySelectorAll('[data-i18n-title]').forEach(function (el) {
        el.title = t(el.getAttribute('data-i18n-title'));
    });
    document.querySelectorAll('[data-i18n-placeholder]').forEach(function (el) {
        el.placeholder = t(el.getAttribute('data-i18n-placeholder'));
    });
}

/* ─────────────── HELPERS ─────────────── */
function post(name, data, cb) {
    fetch('https://' + GetParentResourceName() + '/' + name, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {})
    })
        .then(function (res) { return res.json(); })
        .then(cb || function () { })
        .catch(function () { });
}

function qs(sel) { return document.querySelector(sel); }

function show(el) { if (el) el.classList.remove('hidden'); }

function hide(el) { if (el) el.classList.add('hidden'); }

function getModelName(model) {
    if (state.modelNames[model]) return state.modelNames[model];
    var name = String(model);
    name = name.replace(/^A_C_Dog/i, '').replace(/^A_C_/i, '').replace(/_\d+$/, '').replace(/_/g, ' ');
    return name || model;
}

function toast(message, type) {
    var container = qs('#toasts');
    var el = document.createElement('div');
    el.className = 'toast toast-' + (type || 'info');
    el.innerHTML = '<div class="toast-label">' + (type === 'success' ? t('ui_toast_success') : (type === 'error' ? t('ui_toast_error') : t('ui_toast_notice'))) +
        '</div><div class="toast-msg">' + message + '</div>';
    container.appendChild(el);
    setTimeout(function () {
        el.classList.add('leaving');
        setTimeout(function () { if (el.parentNode) el.parentNode.removeChild(el); }, 300);
    }, 3200);
}

function safeCssClass(model) {
    return 'pet-' + String(model).replace(/[^a-zA-Z0-9_-]/g, '_');
}

/* ─────────────── NUI ACTIONS ─────────────── */
function startanim(scene) {
    post('startanim', { index: currentIndex, scene: scene });
}

function docommand(label) {
    post('docommand', { index: currentIndex, label: label });
}

/* ─────────────── OPEN / CLOSE ─────────────── */
function openUI(data) {
    state.dogs = data.dogs || [];
    state.birds = data.birds || [];
    state.birdCategories = data.birdCategories || [];
    state.ownedDogs = data.ownedDogs || [];
    state.ownedBirds = data.ownedBirds || [];
    state.activePet = data.activePet || 'None';
    state.modelNames = data.modelNames || {};
    /* Use `!== undefined` rather than `||` so a pet ID of 0 is kept as a
       real selection instead of being coerced to "nothing selected". */
    state.selectedDog = data.selectedDog !== undefined ? data.selectedDog : null;
    state.selectedBird = data.selectedBird !== undefined ? data.selectedBird : null;
    state.scavengerItems = data.scavengerItems || [];
    state.fishItems = data.fishItems || [];
    if (data.ui) state.ui = Object.assign({}, DEFAULT_UI, data.ui);
    applyUiLocale();

    closeModals();
    show(qs('#app'));
    switchTab('shop');
    renderCategories();
    hide(qs('#petList'));
    show(qs('#categoryList'));

    post('getMoney', {}, function (money) {
        if (money && money.cash !== undefined) {
            qs('#pcash').textContent = Math.floor(parseFloat(money.cash) * 100) / 100;
        }
    });
}

function closeUI() {
    closeModals();
    hide(qs('#app'));
    post('close', {});
}

function closeModals() {
    hide(qs('#buyModal'));
    hide(qs('#animModal'));
    hide(qs('#commandModal'));
    qs('#animModal').classList.remove('top-left');
}

/* Is the main shop frame open (vs. a standalone overlay modal)? */
function nuiFrameOpen() {
    return !qs('#app').classList.contains('hidden');
}

/* ─────────────── DOG ANIMATIONS MENU (standalone NUI) ─────────────── */
function openDogAnimsMenu(title, animations, ui) {
    if (ui) state.ui = Object.assign({}, DEFAULT_UI, ui);
    applyUiLocale();
    qs('#animTitle').textContent = title || t('ui_dog_actions_title');
    show(qs('#animPutAway'));
    qs('#animModal').classList.add('top-left');
    var list = qs('#animList');
    list.innerHTML = '';

    if (!animations || animations.length === 0) {
        list.appendChild(emptyNote(t('ui_no_animations_available')));
        return;
    }

    animations.forEach(function (entry) {
        list.appendChild(makeRow({
            title: entry.label || '',
            icon: '<i class="ic">\u266A</i>',
            onSelect: function () {
                post('dogAnimSelect', {
                    action: entry.action,
                    dict: entry.dict,
                    dictname: entry.dictname
                });
                hide(qs('#animModal'));
            }
        }));
    });

    show(qs('#animModal'));
}

/* ─────────────── TABS ─────────────── */
function switchTab(tab) {
    var isShop = tab === 'shop';
    qs('#tabShop').classList.toggle('active', isShop);
    qs('#tabMyPets').classList.toggle('active', !isShop);
    hide(qs('#viewMyPets'));
    hide(qs('#petDetail'));
    show(qs('#ownedPetList'));
    if (isShop) {
        show(qs('#viewShop'));
    } else {
        hide(qs('#viewShop'));
        show(qs('#viewMyPets'));
        openMyPets();
    }
}

/* ─────────────── SHOP RENDER ─────────────── */
function renderCategories() {
    var list = qs('#categoryList');
    list.innerHTML = '';

    if (state.dogs.length > 0) {
        var dogImg = state.dogs[0].img || 'animal_dog_husky.png';
        list.appendChild(makeRow({
            id: 'category-dogs',
            icon: '<img src="images/' + dogImg + '" alt="" onerror="this.src=\'images/missing.png\'">',
            title: t('ui_dogs_title'),
            desc: t('ui_dogs_desc'),
            pill: String(state.dogs.length),
            onSelect: function () { showPetList('dogs'); }
        }));
    }

    if (state.birds.length > 0) {
        var counts = {};
        state.birds.forEach(function (b) {
            var cat = b.category || 'Other';
            counts[cat] = (counts[cat] || 0) + 1;
        });
        Object.keys(counts).forEach(function (cat) {
            var first = state.birds.find(function (b) { return b.category === cat; }) || {};
            var img = first.img || 'missing.png';
            var catId = cat.toLowerCase().replace(/\s/g, '-');
            list.appendChild(makeRow({
                id: 'category-' + catId,
                icon: '<img src="images/' + img + '" alt="" onerror="this.src=\'images/missing.png\'">',
                title: cat,
                desc: t('ui_birds_desc'),
                pill: String(counts[cat]),
                onSelect: function () { showPetListByCategory(cat); }
            }));
        });
    }

    if (list.children.length === 0) {
        list.appendChild(emptyNote(t('ui_no_pets_available')));
    }
}

function showPetList(type) {
    var pets = type === 'dogs' ? state.dogs : state.birds;
    renderPetList(pets, type);
}

function showPetListByCategory(category) {
    var filtered = state.birds.filter(function (b) { return b.category === category; });
    renderPetList(filtered, 'birds');
}

function renderPetList(pets, type) {
    hide(qs('#categoryList'));
    show(qs('#petList'));
    var list = qs('#petList');
    list.innerHTML = '';

    if (!pets || pets.length === 0) {
        list.appendChild(emptyNote(t('ui_shelf_empty')));
        return;
    }

    pets.forEach(function (pet) {
        var img = pet.img || 'missing.png';
        var desc = pet.desc || (pet.type ? pet.type + ' bird' : '');
        var cls = safeCssClass(pet.model) + '-' + (type === 'dogs' ? 'dog' : 'bird');
        list.appendChild(makeRow({
            id: cls,
            icon: '<img src="images/' + img + '" alt="" onerror="this.src=\'images/missing.png\'">',
            title: pet.name,
            desc: desc,
            pill: '$' + pet.price,
            onSelect: function () {
                selectShopPet(pet, type);
            }
        }));
    });
}

function selectShopPet(pet, type) {
    currentPetData = { category: type, pet: pet.model, price: pet.price, preset: pet.preset || 0 };
    var tools = qs('#buyPetName');
    tools.textContent = pet.name;
    qs('#petName').value = '';
    paymentMethod = 'cash';
    qs('#typeCash').classList.add('active');
    qs('#typeGold').classList.remove('active');
    show(qs('#buyModal'));
    qs('#petName').focus();
}

/* Whether `element` (a tagged entry from myPets, with a .type of 'dog' or
   'bird') is the player's currently selected default pet of its type.
   Compares with `!= null` rather than truthiness so a pet ID of 0 still
   counts as selected, and is the single source of truth for this check
   instead of being reimplemented at each call site. */
function isPetSelected(element) {
    var selectedId = element.type === 'dog' ? state.selectedDog : state.selectedBird;
    return selectedId != null && selectedId == element.id;
}

/* ─────────────── MY PETS ─────────────── */
function openMyPets() {
    currentIndex = '';
    var taggedDogs = state.ownedDogs.map(function (d) {
        var name = getModelName(d.model);
        var imgKey = d.model + '_img';
        var img = state.modelNames[imgKey] || 'missing.png';
        return Object.assign({}, d, { type: 'dog', name: name, img: img });
    });
    var taggedBirds = state.ownedBirds.map(function (b) {
        var name = getModelName(b.model);
        var imgKey = b.model + '_img';
        var img = state.modelNames[imgKey] || 'missing.png';
        return Object.assign({}, b, { type: 'bird', name: name, img: img });
    });

    myPets = taggedDogs.concat(taggedBirds);
    hide(qs('#petDetail'));
    show(qs('#ownedPetList'));

    renderOwnedPetList();
}

function renderOwnedPetList() {
    var list = qs('#ownedPetList');
    list.innerHTML = '';

    if (myPets.length === 0) {
        list.appendChild(emptyNote(t('ui_no_pets_owned')));
        return;
    }

    myPets.forEach(function (element, index) {
        var isDog = element.type === 'dog';
        var petType = isDog ? t('ui_type_dog') : t('ui_type_bird');
        var isActive = currentPet[element.name] === true;
        var isSelected = isPetSelected(element);

        var pill = '';
        if (element.isDead === true) {
            pill = '<span class="pill">' + t('ui_dead') + '</span>';
        } else if (isActive) {
            pill = '<span class="pill">' + t('ui_active') + '</span>';
        } else if (isSelected) {
            pill = '<span class="pill muted">' + t('ui_selected') + '</span>';
        }

        var row = makeRow({
            id: 'petid-' + index,
            icon: '<img src="images/' + element.img + '" alt="" onerror="this.src=\'images/missing.png\'">',
            title: element.name,
            desc: t('ui_type_xp', petType, element.xp || 0),
            pillHtml: pill,
            onSelect: function () {
                openPetDetail(element, index);
            }
        });
        list.appendChild(row);
    });
}

function openPetDetail(element, index) {
    currentIndex = element.name;
    hide(qs('#ownedPetList'));
    show(qs('#petDetail'));

    var isActive = currentPet[element.name] === true;
    var isDog = element.type === 'dog';
    var isSelected = isPetSelected(element);
    var detail = qs('#petDetail');
    var img = 'images/' + element.img;

    detail.innerHTML =
        '<div class="detail-hero">' +
        '   <div class="hero-img"><img src="' + img + '" alt="" onerror="this.src=\'images/missing.png\'"></div>' +
        '   <div class="hero-meta">' +
        '       <div class="hero-title">' + element.name + '</div>' +
        '       <div class="hero-desc">' + (element.type === 'dog' ? t('ui_hunting_dog') : t('ui_hunting_bird')) + ' \u2022 XP ' + (element.xp || 0) + '</div>' +
        '   </div>' +
        (isActive ? '<span class="pill">' + t('ui_active') + '</span>' : '') +
        (isSelected ? '<span class="pill muted" id="heroSelectedPill">' + t('ui_selected') + '</span>' : '') +
        '</div>';

    if (isActive) {
        detail.insertAdjacentHTML('beforeend',
            '<div class="detail-block">' +
            '   <div class="detail-block-title">' + t('ui_condition_title') + '</div>' +
            '   <div class="stat-row"><span class="stat-label">' + t('ui_health') + '</span><div class="statbar" id="statHealth"><div class="stat-fill"></div></div><span class="stat-val" id="valHealth">0%</span></div>' +
            '   <div class="stat-row"><span class="stat-label">' + t('ui_hunger') + '</span><div class="statbar" id="statHunger"><div class="stat-fill"></div></div><span class="stat-val" id="valHunger">0%</span></div>' +
            '   <div class="stat-row"><span class="stat-label">' + t('ui_thirst') + '</span><div class="statbar" id="statThirst"><div class="stat-fill"></div></div><span class="stat-val" id="valThirst">0%</span></div>' +
            '</div>'
        );
    }

    var extraBtn = '';
    if (isActive) {
        extraBtn =
            '<button class="wood-btn muted" id="actCommands" type="button">' + t('ui_commands') + '</button>' +
            '<button class="wood-btn muted" id="actAnim" type="button">' + t('ui_animations_title') + '</button>';
    }

    detail.insertAdjacentHTML('beforeend',
        '<div class="detail-block">' +
        '   <div class="detail-block-title">' + t('ui_actions_title') + '</div>' +
        '   <div class="action-grid" id="actionGrid">' +
        (isActive
            ? '<button class="wood-btn" id="actCallFlee" type="button">' + t('ui_call_flee') + '</button>' +
              '<button class="wood-btn muted" id="actFeed" type="button">' + t('ui_feeding') + '</button>' +
              '<button class="wood-btn muted" id="actDrink" type="button">' + t('ui_drinking') + '</button>' +
              '<button class="wood-btn muted" id="actCarry" type="button">' + t('ui_carrying') + '</button>' +
              extraBtn +
              '<button class="wood-btn muted" id="actFollow" type="button">' + t('ui_follow_unfollow') + '</button>' +
              '<button class="wood-btn' + (isSelected ? ' muted' : '') + '" id="actSelect" type="button">' + (isSelected ? t('ui_selected') : t('ui_select_pet')) + '</button>'
            : '<button class="wood-btn" id="actCallFlee" type="button">' + t('ui_call_pet') + '</button>' +
              '<button class="wood-btn' + (isSelected ? ' muted' : '') + '" id="actSelect" type="button">' + (isSelected ? t('ui_selected') : t('ui_select_pet')) + '</button>' +
              '<button class="wood-btn muted" id="actTransfer" type="button">' + t('ui_transfer') + '</button>') +
        '   </div>' +
        '</div>'
    );

    if (isActive) {
        detail.insertAdjacentHTML('beforeend',
            '<div class="detail-block">' +
            '   <div class="detail-block-title">' + t('ui_follow_position_title') + '</div>' +
            '   <div class="range-row" id="distRow">' +
            '       <div class="range-labels"><span>' + t('ui_back') + '</span><span>' + t('ui_forward') + '</span></div>' +
            '       <input type="range" id="distanceRange" class="range" min="-30" max="30" value="0" step="1">' +
            '   </div>' +
            '   <div class="range-row" id="sideRow">' +
            '       <div class="range-labels"><span>' + t('ui_left') + '</span><span>' + t('ui_right') + '</span></div>' +
            '       <input type="range" id="sideRange" class="range" min="-30" max="30" value="0" step="1">' +
            '   </div>' +
            '</div>'
        );
    }

    wireDetailActions(element, isActive, index);

    post('getPetData', { index: currentIndex }, function (data) {
        if (!data) data = {};
        if (isActive) {
            setStat('statHealth', 'valHealth', Number(data.health) || 0);
            setStat('statHunger', 'valHunger', Number(data.hungry) || 0);
            setStat('statThirst', 'valThirst', Number(data.thirst) || 0);
            qs('#distanceRange').value = Number(data.followDistance) || 0;
            qs('#sideRange').value = Number(data.leftRightDistance) || 0;
        }
    });
}

function setStat(barId, valId, value) {
    var fill = qs('#' + barId + ' .stat-fill');
    var label = qs('#' + valId);
    if (!fill) return;
    value = Math.max(0, Math.min(100, value));
    fill.style.width = value + '%';
    fill.classList.remove('stat-good', 'stat-warn', 'stat-bad');
    if (value >= 60) fill.classList.add('stat-good');
    else if (value >= 30) fill.classList.add('stat-warn');
    else fill.classList.add('stat-bad');
    if (label) label.textContent = Math.round(value) + '%';
}

function wireDetailActions(element, isActive, index) {
    bindBtn('actCallFlee', function () {
        post('spawnPet', { pet: element, index: currentIndex });
        closeUI();
    });

    bindBtn('actSelect', function () {
        var isDog = element.type === 'dog';
        if (isPetSelected(element)) return;
        /* The NUI callback now only resolves once the server has verified
           ownership and actually saved the selection (see selectDog/selectBird
           in server_dogs.lua), so `result.success` reflects the real outcome
           instead of the UI assuming success as soon as the round-trip lands. */
        post(isDog ? 'selectDog' : 'selectBird', { id: element.id }, function (result) {
            if (!result || !result.success) {
                toast(t('ui_toast_error'), 'error');
                return;
            }
            if (isDog) { state.selectedDog = element.id; } else { state.selectedBird = element.id; }
            renderOwnedPetList();
            markPetSelectedInDetail();
        });
    });

    if (isActive) {
        bindBtn('actFeed', function () {
            post('feedPet', { pet: element, index: currentIndex, type: 'food' });
        });
        bindBtn('actDrink', function () {
            post('feedPet', { pet: element, index: currentIndex, type: 'drink' });
        });
        bindBtn('actCarry', function () {
            var list = qs('#animList');
            list.innerHTML = '';
            hide(qs('#animPutAway'));
            qs('#animModal').classList.remove('top-left');
            list.appendChild(makeRow({ title: t('ui_carry_anim'), icon: '<i class="ic">\u266A</i>', onSelect: function () { startanim('carry'); hide(qs('#animModal')); } }));
            list.appendChild(makeRow({ title: t('ui_take_shoulder'), icon: '<i class="ic">\u27A5</i>', onSelect: function () { startanim('takeshoulder'); hide(qs('#animModal')); } }));
            show(qs('#animModal'));
        });
        bindBtn('actFollow', function () {
            post('follow', { pet: element, index: currentIndex });
            closeUI();
        });
        bindBtn('actAnim', function () {
            qs('#animTitle').textContent = t('ui_animations_title');
            hide(qs('#animPutAway'));
            qs('#animModal').classList.remove('top-left');
            post('getAnimations', { index: currentIndex }, function (animations) {
                var list = qs('#animList');
                list.innerHTML = '';
                var count = 0;
                eachInto(animations, function (label, scene) {
                    count++;
                    list.appendChild(makeRow({
                        title: String(label),
                        icon: '<i class="ic">\u266B</i>',
                        onSelect: function () {
                            startanim(scene);
                            hide(qs('#animModal'));
                        }
                    }));
                });
                if (count === 0) {
                    list.appendChild(emptyNote(t('ui_no_animations_for_pet')));
                }
                show(qs('#animModal'));
            });
        });
        bindBtn('actCommands', function () {
            post('getCommands', { index: currentIndex }, function (commands) {
                var list = qs('#commandList');
                list.innerHTML = '';
                var count = 0;
                eachInto(commands, function (label, scene) {
                    count++;
                    list.appendChild(makeRow({
                        title: String(label),
                        icon: '<i class="ic">\u2714</i>',
                        onSelect: function () {
                            docommand(label);
                            hide(qs('#commandModal'));
                        }
                    }));
                });
                if (count === 0) {
                    list.appendChild(emptyNote(t('ui_no_commands_for_pet')));
                }
                show(qs('#commandModal'));
            });
        });
        bindChange(qs('#distanceRange'), function () {
            post('follow', { index: currentIndex, followDistance: Number(this.value) || 0 });
        });
        bindChange(qs('#sideRange'), function () {
            post('follow', { index: currentIndex, leftRightDistance: Number(this.value) || 0 });
        });
    } else {
        bindBtn('actTransfer', function () {
            post('transferPet', { pet: element, index: currentIndex });
            closeUI();
        });
    }
}

/* Reflects a just-confirmed selection in the already-open detail panel
   without rebuilding it (which would also re-run getPetData needlessly) --
   just adds the "Selected" pill if it isn't there yet and mutes the button. */
function markPetSelectedInDetail() {
    var hero = qs('.detail-hero');
    if (hero && !qs('#heroSelectedPill')) {
        hero.insertAdjacentHTML('beforeend', '<span class="pill muted" id="heroSelectedPill">' + t('ui_selected') + '</span>');
    }
    var btn = qs('#actSelect');
    if (btn) {
        btn.textContent = t('ui_selected');
        btn.classList.add('muted');
    }
}

function bindBtn(id, fn) {
    var el = qs('#' + id);
    if (el) el.addEventListener('click', fn);
}

function bindChange(el, fn) {
    if (el) el.addEventListener('change', fn);
}

/* ─────────────── ROW FACTORY ─────────────── */
function makeRow(opts) {
    var el = document.createElement('div');
    el.className = 'row' + (opts.disabled ? ' disabled' : '');
    if (opts.id) el.id = opts.id;
    el.innerHTML =
        '<span class="badge">' + (opts.icon || '<i class="ic">\u2660</i>') + '</span>' +
        '<div class="row-meta">' +
        '   <div class="row-title">' + (opts.title || '') + '</div>' +
        '   <div class="row-desc">' + (opts.desc || '') + '</div>' +
        '</div>' +
        (opts.pillHtml || (opts.pill ? '<span class="pill">' + opts.pill + '</span>' : ''));
    if (opts.onSelect) el.addEventListener('click', opts.onSelect);
    return el;
}

function emptyNote(text) {
    var el = document.createElement('div');
    el.className = 'empty-note';
    el.textContent = text;
    return el;
}

function eachInto(list, fn) {
    if (!list) return;
    if (Array.isArray(list)) {
        list.forEach(function (v) {
            if (v && typeof v === 'object') {
                fn(v.label !== undefined ? v.label : v.name, v.scene !== undefined ? v.scene : undefined);
            } else {
                fn(v, undefined);
            }
        });
    } else if (typeof list === 'object') {
        Object.keys(list).forEach(function (k) { fn(k, list[k]); });
    }
}

/* ══════════════════════════════════════════════════════════════
   EVENT BINDINGS
   ══════════════════════════════════════════════════════════════ */
document.addEventListener('DOMContentLoaded', function () {
    hide(qs('#app'));

    qs('#closeBtn').addEventListener('click', closeUI);
    qs('#backBtn').addEventListener('click', handleBack);

    qs('#tabShop').addEventListener('click', function () { switchTab('shop'); });
    qs('#tabMyPets').addEventListener('click', function () { switchTab('mypets'); });

    /* Buy modal */
    qs('#buyConfirm').addEventListener('click', function () {
        var pet = currentPetData;
        hide(qs('#buyModal'));
        if (pet && pet.pet) {
            post('buyPet', {
                model: pet.pet,
                category: pet.category,
                price: pet.price || 0,
                preset: pet.preset || 0,
                paymentMethod: paymentMethod,
                petName: qs('#petName').value
            });
        } else {
            toast(t('ui_please_select_pet'), 'error');
        }
    });
    qs('#buyCancel').addEventListener('click', function () { hide(qs('#buyModal')); });

    qs('#typeCash').addEventListener('click', function () {
        paymentMethod = 'cash';
        qs('#typeCash').classList.add('active');
        qs('#typeGold').classList.remove('active');
    });
    qs('#typeGold').addEventListener('click', function () {
        paymentMethod = 'gold';
        qs('#typeGold').classList.add('active');
        qs('#typeCash').classList.remove('active');
    });
    qs('#petName').addEventListener('keydown', function (e) {
        if (e.key === 'Enter') qs('#buyConfirm').click();
    });

    /* Animation / command modals */
    qs('#animClose').addEventListener('click', function () {
        hide(qs('#animModal'));
        if (!nuiFrameOpen()) post('close', {});
    });
    qs('#animPutAway').addEventListener('click', function () {
        hide(qs('#animModal'));
        post('dogAnimSelect', { action: 'putaway' });
    });
    qs('#commandClose').addEventListener('click', function () {
        hide(qs('#commandModal'));
        if (!nuiFrameOpen()) post('close', {});
    });

    /* Escape */
    document.addEventListener('keyup', function (e) {
        if (e.key === 'Escape') closeUI();
    });
});

function handleBack() {
    if (!qs('#buyModal').classList.contains('hidden')) { hide(qs('#buyModal')); return; }
    if (!qs('#animModal').classList.contains('hidden')) { hide(qs('#animModal')); return; }
    if (!qs('#commandModal').classList.contains('hidden')) { hide(qs('#commandModal')); return; }

    if (!qs('#viewShop').classList.contains('hidden') && !qs('#petList').classList.contains('hidden')) {
        hide(qs('#petList'));
        show(qs('#categoryList'));
        return;
    }

    if (!qs('#viewMyPets').classList.contains('hidden') && !qs('#petDetail').classList.contains('hidden')) {
        hide(qs('#petDetail'));
        show(qs('#ownedPetList'));
        return;
    }
}

/* ─────────────── MESSAGES FROM LUA ─────────────── */
window.addEventListener('message', function (event) {
    var data = event.data || {};
    if (data.action === 'open') {
        openUI(data);
    } else if (data.action === 'close') {
        closeModals();
        hide(qs('#app'));
    } else if (data.action === 'openDogAnims') {
        openDogAnimsMenu(data.title, data.animations || [], data.ui);
    } else if (data.action === 'updateMoney') {
        if (data.cash !== undefined) qs('#pcash').textContent = Math.floor(parseFloat(data.cash) * 100) / 100;
    } else if (data.action === 'setCurrentPet') {
        currentPet[data.name] = data.val;
    }
});