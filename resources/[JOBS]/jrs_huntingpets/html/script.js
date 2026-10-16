// jrs_huntingpets | the pet shop window and the dog action list
// Everything that comes from the game or the server is written with textContent / attributes, never as HTML.
'use strict';

const $ = (selector) => document.querySelector(selector);
const show = (el) => el && el.classList.remove('hidden');
const hide = (el) => el && el.classList.add('hidden');
const isHidden = (selector) => $(selector).classList.contains('hidden');

const state = {
  dogs: [], birds: [], birdCategories: [], ownedDogs: [], ownedBirds: [],
  activePet: 'None', modelNames: {}, selectedDog: null, selectedBird: null,
  scavengerItems: [], fishItems: [], ui: {},
};
let buying = null;           // { category, pet (model), price, preset } while the buy window is open
let payWith = 'cash';
let owned = [];              // dogs and birds of the player, tagged with their type
let activeNames = {};        // pet name -> true while that pet is out (set by the game script)
let openName = '';           // name of the pet whose detail panel is open

// ------------------------------------------------------------------ texts

// English fallbacks; the game script sends the real ones (in the server language) with every open
const FALLBACK = {
  ui_back: 'Back', ui_close: 'Close', ui_header_title: 'Hunting Pets', ui_header_subtitle: 'Trapper & Kennel',
  ui_tab_shop: 'Shop', ui_tab_mypets: 'My Pets', ui_wallet_cash: 'Cash', ui_purchase_pet_title: 'Purchase Pet',
  ui_gold: 'Gold', ui_pet_name_label: 'Pet Name', ui_pet_name_placeholder: 'Name your pet', ui_cancel: 'Cancel',
  ui_buy: 'Buy', ui_animations_title: 'Animations', ui_put_dog_away: 'Put Dog Away', ui_commands_title: 'Commands',
  ui_dogs_title: 'Dogs', ui_dogs_desc: 'Loyal hunting companions', ui_birds_desc: 'Hunting birds for sale',
  ui_no_pets_available: 'No pets available today', ui_shelf_empty: 'This shelf is empty', ui_no_pets_owned: 'No pets owned',
  ui_no_animations_available: 'No animations available', ui_no_animations_for_pet: 'No animations for this pet',
  ui_no_commands_for_pet: 'No commands for this pet', ui_type_dog: 'Dog', ui_type_bird: 'Bird', ui_type_xp: 'Type %s • XP %s',
  ui_hunting_dog: 'Hunting Dog', ui_hunting_bird: 'Hunting Bird', ui_dead: 'Dead', ui_active: 'Active',
  ui_select_pet: 'Select as Default', ui_selected: 'Selected', ui_condition_title: 'Condition', ui_health: 'Health',
  ui_hunger: 'Hunger', ui_thirst: 'Thirst', ui_actions_title: 'Actions', ui_call_flee: 'Call / Flee', ui_call_pet: 'Call Pet',
  ui_feeding: 'Feeding', ui_drinking: 'Drinking', ui_carrying: 'Carrying', ui_commands: 'Commands',
  ui_follow_unfollow: 'Follow / Unfollow', ui_transfer: 'Transfer', ui_follow_position_title: 'Follow Position',
  ui_forward: 'Forward', ui_left: 'Left', ui_right: 'Right', ui_carry_anim: 'Carry', ui_take_shoulder: 'Take Shoulder',
  ui_please_select_pet: 'Please select a pet first', ui_toast_success: 'Success', ui_toast_error: 'Error',
  ui_toast_notice: 'Notice', ui_dog_actions_title: 'Dog Actions', ui_stop_animation: 'Stop Animation',
};

// t('ui_type_xp', 'Dog', 5) -> "Type Dog • XP 5": every %s takes the next argument
function t(key, ...args) {
  const text = (state.ui && state.ui[key]) || FALLBACK[key] || key;
  let i = 0;
  return text.replace(/%s/g, () => args[i++]);
}

function translatePage() {
  document.querySelectorAll('[data-i18n]').forEach((el) => { el.textContent = t(el.dataset.i18n); });
  document.querySelectorAll('[data-i18n-title]').forEach((el) => { el.title = t(el.dataset.i18nTitle); });
  document.querySelectorAll('[data-i18n-placeholder]').forEach((el) => { el.placeholder = t(el.dataset.i18nPlaceholder); });
}

// ------------------------------------------------------------------ small building blocks

function post(name, body, then) {
  fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}),
  }).then((r) => r.json()).then(then || (() => {})).catch(() => {});
}

// h('div', { class: 'row' }, child, 'text', ...) builds an element
function h(tag, attrs, ...children) {
  const el = document.createElement(tag);
  Object.entries(attrs || {}).forEach(([k, v]) => { if (v != null && v !== false) el.setAttribute(k, v === true ? '' : v); });
  children.flat().forEach((c) => { if (c != null) el.append(c); });
  return el;
}

const glyph = (char) => h('i', { class: 'ic' }, char);

function picture(file) {
  const img = h('img', { src: `images/${file || 'missing.png'}`, alt: '' });
  img.onerror = () => { img.onerror = null; img.src = 'images/missing.png'; };
  return img;
}

function pill(text, muted, id) { return h('span', { class: muted ? 'pill muted' : 'pill', id }, text); }

// one list row: { id, icon (node), title, desc, pill (text) | pillNode, onSelect }
function row(o) {
  const el = h('div', { class: o.disabled ? 'row disabled' : 'row', id: o.id },
    h('span', { class: 'badge' }, o.icon || glyph('♠')),
    h('div', { class: 'row-meta' }, h('div', { class: 'row-title' }, o.title || ''), h('div', { class: 'row-desc' }, o.desc || '')),
    o.pillNode || (o.pill ? pill(o.pill) : null));
  if (o.onSelect) el.addEventListener('click', o.onSelect);
  return el;
}

const note = (text) => h('div', { class: 'empty-note' }, text);

function clear(selector) { const el = $(selector); el.replaceChildren(); return el; }

function toast(message, kind) {
  const label = kind === 'success' ? t('ui_toast_success') : kind === 'error' ? t('ui_toast_error') : t('ui_toast_notice');
  const el = h('div', { class: `toast toast-${kind || 'info'}` }, h('div', { class: 'toast-label' }, label), h('div', { class: 'toast-msg' }, message));
  $('#toasts').append(el);
  setTimeout(() => {
    el.classList.add('leaving');
    setTimeout(() => el.remove(), 300);
  }, 3200);
}

function modelLabel(model) {
  if (state.modelNames[model]) return state.modelNames[model];
  return String(model).replace(/^A_C_Dog/i, '').replace(/^A_C_/i, '').replace(/_\d+$/, '').replace(/_/g, ' ') || model;
}

const cssName = (model) => `pet-${String(model).replace(/[^a-zA-Z0-9_-]/g, '_')}`;
const showCash = (amount) => { $('#pcash').textContent = Math.floor(parseFloat(amount) * 100) / 100; };

// ------------------------------------------------------------------ opening and closing

function closeModals() {
  ['#buyModal', '#animModal', '#commandModal'].forEach((s) => hide($(s)));
  $('#animModal').classList.remove('top-left');
}

function closeWindow() {
  closeModals();
  hide($('#app'));
  post('close');
}

function openWindow(data) {
  Object.assign(state, {
    dogs: data.dogs || [], birds: data.birds || [], birdCategories: data.birdCategories || [],
    ownedDogs: data.ownedDogs || [], ownedBirds: data.ownedBirds || [], activePet: data.activePet || 'None',
    modelNames: data.modelNames || {}, scavengerItems: data.scavengerItems || [], fishItems: data.fishItems || [],
    // an id of 0 is a real selection, so undefined (not falsy) means "none"
    selectedDog: data.selectedDog !== undefined ? data.selectedDog : null,
    selectedBird: data.selectedBird !== undefined ? data.selectedBird : null,
  });
  if (data.ui) state.ui = { ...FALLBACK, ...data.ui };
  translatePage();

  closeModals();
  show($('#app'));
  switchTab('shop');
  drawCategories();
  hide($('#petList'));
  show($('#categoryList'));
  post('getMoney', {}, (m) => { if (m && m.cash !== undefined) showCash(m.cash); });
}

// ------------------------------------------------------------------ the dog action list (standalone)

function openDogActions(title, actions, ui) {
  if (ui) state.ui = { ...FALLBACK, ...ui };
  translatePage();
  $('#animTitle').textContent = title || t('ui_dog_actions_title');
  show($('#animPutAway'));
  $('#animModal').classList.add('top-left');

  const list = clear('#animList');
  if (!actions || !actions.length) {
    list.append(note(t('ui_no_animations_available')));
    return;
  }
  actions.forEach((a) => list.append(row({
    title: a.label || '', icon: glyph('♪'),
    onSelect: () => {
      post('dogAnimSelect', { action: a.action, dict: a.dict, dictname: a.dictname });
      hide($('#animModal'));
    },
  })));
  show($('#animModal'));
}

// ------------------------------------------------------------------ tabs

function switchTab(tab) {
  const shop = tab === 'shop';
  $('#tabShop').classList.toggle('active', shop);
  $('#tabMyPets').classList.toggle('active', !shop);
  hide($('#viewMyPets'));
  hide($('#petDetail'));
  show($('#ownedPetList'));
  if (shop) {
    show($('#viewShop'));
  } else {
    hide($('#viewShop'));
    show($('#viewMyPets'));
    loadOwned();
  }
}

// ------------------------------------------------------------------ the shop

function drawCategories() {
  const list = clear('#categoryList');

  if (state.dogs.length) {
    list.append(row({
      id: 'category-dogs', icon: picture(state.dogs[0].img || 'animal_dog_husky.png'),
      title: t('ui_dogs_title'), desc: t('ui_dogs_desc'), pill: String(state.dogs.length),
      onSelect: () => drawPets(state.dogs, 'dogs'),
    }));
  }

  const perCategory = {};
  state.birds.forEach((b) => { const c = b.category || 'Other'; (perCategory[c] = perCategory[c] || []).push(b); });
  Object.entries(perCategory).forEach(([category, birds]) => {
    list.append(row({
      id: `category-${category.toLowerCase().replace(/\s/g, '-')}`, icon: picture(birds[0].img),
      title: category, desc: t('ui_birds_desc'), pill: String(birds.length),
      onSelect: () => drawPets(birds, 'birds'),
    }));
  });

  if (!list.children.length) list.append(note(t('ui_no_pets_available')));
}

function drawPets(pets, type) {
  hide($('#categoryList'));
  show($('#petList'));
  const list = clear('#petList');
  if (!pets || !pets.length) return list.append(note(t('ui_shelf_empty')));

  pets.forEach((pet) => list.append(row({
    id: `${cssName(pet.model)}-${type === 'dogs' ? 'dog' : 'bird'}`, icon: picture(pet.img), title: pet.name,
    desc: pet.desc || (pet.type ? `${pet.type} bird` : ''), pill: `$${pet.price}`,
    onSelect: () => askToBuy(pet, type),
  })));
}

function askToBuy(pet, type) {
  buying = { category: type, pet: pet.model, price: pet.price, preset: pet.preset || 0 };
  $('#buyPetName').textContent = pet.name;
  $('#petName').value = '';
  setPayment('cash');
  show($('#buyModal'));
  $('#petName').focus();
}

function setPayment(kind) {
  payWith = kind;
  $('#typeCash').classList.toggle('active', kind === 'cash');
  $('#typeGold').classList.toggle('active', kind === 'gold');
}

// ------------------------------------------------------------------ my pets

// is this pet the default one of its kind? (compared with != null so id 0 counts)
function isDefault(pet) {
  const id = pet.type === 'dog' ? state.selectedDog : state.selectedBird;
  return id != null && id == pet.id;
}

function loadOwned() {
  openName = '';
  const tag = (type) => (p) => ({ ...p, type, name: modelLabel(p.model), img: state.modelNames[`${p.model}_img`] || 'missing.png' });
  owned = state.ownedDogs.map(tag('dog')).concat(state.ownedBirds.map(tag('bird')));
  hide($('#petDetail'));
  show($('#ownedPetList'));
  drawOwned();
}

function drawOwned() {
  const list = clear('#ownedPetList');
  if (!owned.length) return list.append(note(t('ui_no_pets_owned')));

  owned.forEach((pet, index) => {
    const out = activeNames[pet.name] === true;
    let tag = null;
    if (pet.isDead === true) tag = pill(t('ui_dead'));
    else if (out) tag = pill(t('ui_active'));
    else if (isDefault(pet)) tag = pill(t('ui_selected'), true);

    list.append(row({
      id: `petid-${index}`, icon: picture(pet.img), title: pet.name,
      desc: t('ui_type_xp', pet.type === 'dog' ? t('ui_type_dog') : t('ui_type_bird'), pet.xp || 0),
      pillNode: tag, onSelect: () => openDetail(pet),
    }));
  });
}

const statRow = (label, id) => h('div', { class: 'stat-row' },
  h('span', { class: 'stat-label' }, label), h('div', { class: 'statbar', id: `stat${id}` }, h('div', { class: 'stat-fill' })),
  h('span', { class: 'stat-val', id: `val${id}` }, '0%'));

const button = (id, label, muted) => h('button', { class: muted ? 'wood-btn muted' : 'wood-btn', id, type: 'button' }, label);

const slider = (rowId, id, left, right) => h('div', { class: 'range-row', id: rowId },
  h('div', { class: 'range-labels' }, h('span', {}, left), h('span', {}, right)),
  h('input', { type: 'range', id, class: 'range', min: '-30', max: '30', value: '0', step: '1' }));

function openDetail(pet) {
  openName = pet.name;
  hide($('#ownedPetList'));
  show($('#petDetail'));

  const out = activeNames[pet.name] === true;
  const picked = isDefault(pet);
  const detail = clear('#petDetail');

  detail.append(h('div', { class: 'detail-hero' },
    h('div', { class: 'hero-img' }, picture(pet.img)),
    h('div', { class: 'hero-meta' }, h('div', { class: 'hero-title' }, pet.name),
      h('div', { class: 'hero-desc' }, `${pet.type === 'dog' ? t('ui_hunting_dog') : t('ui_hunting_bird')} • XP ${pet.xp || 0}`)),
    out ? pill(t('ui_active')) : null,
    picked ? pill(t('ui_selected'), true, 'heroSelectedPill') : null));

  if (out) {
    detail.append(h('div', { class: 'detail-block' }, h('div', { class: 'detail-block-title' }, t('ui_condition_title')),
      statRow(t('ui_health'), 'Health'), statRow(t('ui_hunger'), 'Hunger'), statRow(t('ui_thirst'), 'Thirst')));
  }

  const select = button('actSelect', picked ? t('ui_selected') : t('ui_select_pet'), picked);
  const actions = out
    ? [button('actCallFlee', t('ui_call_flee')), button('actFeed', t('ui_feeding'), true), button('actDrink', t('ui_drinking'), true),
       button('actCarry', t('ui_carrying'), true), button('actCommands', t('ui_commands'), true), button('actAnim', t('ui_animations_title'), true),
       button('actFollow', t('ui_follow_unfollow'), true), select]
    : [button('actCallFlee', t('ui_call_pet')), select, button('actTransfer', t('ui_transfer'), true)];
  detail.append(h('div', { class: 'detail-block' }, h('div', { class: 'detail-block-title' }, t('ui_actions_title')),
    h('div', { class: 'action-grid', id: 'actionGrid' }, actions)));

  if (out) {
    detail.append(h('div', { class: 'detail-block' }, h('div', { class: 'detail-block-title' }, t('ui_follow_position_title')),
      slider('distRow', 'distanceRange', t('ui_back'), t('ui_forward')), slider('sideRow', 'sideRange', t('ui_left'), t('ui_right'))));
  }

  wireDetail(pet, out);

  post('getPetData', { index: openName }, (data) => {
    data = data || {};
    if (!out) return;
    setStat('Health', Number(data.health) || 0);
    setStat('Hunger', Number(data.hungry) || 0);
    setStat('Thirst', Number(data.thirst) || 0);
    $('#distanceRange').value = Number(data.followDistance) || 0;
    $('#sideRange').value = Number(data.leftRightDistance) || 0;
  });
}

function setStat(id, value) {
  const fill = $(`#stat${id} .stat-fill`);
  if (!fill) return;
  value = Math.max(0, Math.min(100, value));
  fill.style.width = `${value}%`;
  fill.classList.remove('stat-good', 'stat-warn', 'stat-bad');
  fill.classList.add(value >= 60 ? 'stat-good' : value >= 30 ? 'stat-warn' : 'stat-bad');
  const label = $(`#val${id}`);
  if (label) label.textContent = `${Math.round(value)}%`;
}

// names or label/scene pairs: lists come as arrays or as { label: scene } objects
function entries(list) {
  if (!list) return [];
  if (Array.isArray(list)) return list.map((v) => (v && typeof v === 'object' ? [v.label !== undefined ? v.label : v.name, v.scene] : [v, undefined]));
  return Object.entries(list);
}

function on(id, fn) { const el = $(`#${id}`); if (el) el.addEventListener('click', fn); }

function openList(title, items, empty, icon, pick) {
  const modal = $('#animModal');
  $('#animTitle').textContent = title;
  hide($('#animPutAway'));
  modal.classList.remove('top-left');
  const list = clear('#animList');
  if (!items.length) list.append(note(empty));
  items.forEach(([label, scene]) => list.append(row({ title: String(label), icon: glyph(icon), onSelect: () => { pick(label, scene); hide(modal); } })));
  show(modal);
}

function wireDetail(pet, out) {
  on('actCallFlee', () => { post('spawnPet', { pet, index: openName }); closeWindow(); });

  // the server confirms (and saves) the choice before the window shows it as selected
  on('actSelect', () => {
    if (isDefault(pet)) return;
    const dog = pet.type === 'dog';
    post(dog ? 'selectDog' : 'selectBird', { id: pet.id }, (result) => {
      if (!result || !result.success) return toast(t('ui_toast_error'), 'error');
      if (dog) state.selectedDog = pet.id; else state.selectedBird = pet.id;
      drawOwned();
      const hero = $('.detail-hero');
      if (hero && !$('#heroSelectedPill')) hero.append(pill(t('ui_selected'), true, 'heroSelectedPill'));
      const btn = $('#actSelect');
      if (btn) { btn.textContent = t('ui_selected'); btn.classList.add('muted'); }
    });
  });

  if (!out) return on('actTransfer', () => { post('transferPet', { pet, index: openName }); closeWindow(); });

  on('actFeed', () => post('feedPet', { pet, index: openName, type: 'food' }));
  on('actDrink', () => post('feedPet', { pet, index: openName, type: 'drink' }));
  on('actFollow', () => { post('follow', { pet, index: openName }); closeWindow(); });

  on('actCarry', () => openList(t('ui_animations_title'), [[t('ui_carry_anim'), 'carry'], [t('ui_take_shoulder'), 'takeshoulder']],
    '', '♪', (_, scene) => post('startanim', { index: openName, scene })));

  on('actAnim', () => post('getAnimations', { index: openName }, (list) => openList(t('ui_animations_title'), entries(list),
    t('ui_no_animations_for_pet'), '♫', (_, scene) => post('startanim', { index: openName, scene }))));

  on('actCommands', () => post('getCommands', { index: openName }, (list) => {
    const items = entries(list);
    const body = clear('#commandList');
    if (!items.length) body.append(note(t('ui_no_commands_for_pet')));
    items.forEach(([label]) => body.append(row({
      title: String(label), icon: glyph('✔'),
      onSelect: () => { post('docommand', { index: openName, label }); hide($('#commandModal')); },
    })));
    show($('#commandModal'));
  }));

  $('#distanceRange').addEventListener('change', (e) => post('follow', { index: openName, followDistance: Number(e.target.value) || 0 }));
  $('#sideRange').addEventListener('change', (e) => post('follow', { index: openName, leftRightDistance: Number(e.target.value) || 0 }));
}

// ------------------------------------------------------------------ wiring

function goBack() {
  if (!isHidden('#buyModal')) return hide($('#buyModal'));
  if (!isHidden('#animModal')) return hide($('#animModal'));
  if (!isHidden('#commandModal')) return hide($('#commandModal'));
  if (!isHidden('#viewShop') && !isHidden('#petList')) {
    hide($('#petList'));
    return show($('#categoryList'));
  }
  if (!isHidden('#viewMyPets') && !isHidden('#petDetail')) {
    hide($('#petDetail'));
    show($('#ownedPetList'));
  }
}

document.addEventListener('DOMContentLoaded', () => {
  hide($('#app'));

  $('#closeBtn').addEventListener('click', closeWindow);
  $('#backBtn').addEventListener('click', goBack);
  $('#tabShop').addEventListener('click', () => switchTab('shop'));
  $('#tabMyPets').addEventListener('click', () => switchTab('mypets'));

  $('#buyConfirm').addEventListener('click', () => {
    const pet = buying;
    hide($('#buyModal'));
    if (!pet || !pet.pet) return toast(t('ui_please_select_pet'), 'error');
    post('buyPet', { model: pet.pet, category: pet.category, price: pet.price || 0, preset: pet.preset || 0, paymentMethod: payWith, petName: $('#petName').value });
  });
  $('#buyCancel').addEventListener('click', () => hide($('#buyModal')));
  $('#typeCash').addEventListener('click', () => setPayment('cash'));
  $('#typeGold').addEventListener('click', () => setPayment('gold'));
  $('#petName').addEventListener('keydown', (e) => { if (e.key === 'Enter') $('#buyConfirm').click(); });

  // the action list can be open without the shop behind it
  const shopOpen = () => !isHidden('#app');
  $('#animClose').addEventListener('click', () => { hide($('#animModal')); if (!shopOpen()) post('close'); });
  $('#animPutAway').addEventListener('click', () => { hide($('#animModal')); post('dogAnimSelect', { action: 'putaway' }); });
  $('#commandClose').addEventListener('click', () => { hide($('#commandModal')); if (!shopOpen()) post('close'); });

  document.addEventListener('keyup', (e) => { if (e.key === 'Escape') closeWindow(); });
});

window.addEventListener('message', ({ data }) => {
  data = data || {};
  switch (data.action) {
    case 'open': openWindow(data); break;
    case 'close': closeModals(); hide($('#app')); break;
    case 'openDogAnims': openDogActions(data.title, data.animations || [], data.ui); break;
    case 'updateMoney': if (data.cash !== undefined) showCash(data.cash); break;
    case 'setCurrentPet': activeNames[data.name] = data.val; break;
    default: break;
  }
});
