const app = document.getElementById('app');
const inviteView = document.getElementById('inviteView');
const tradeView = document.getElementById('tradeView');
const inventoryPanel = document.getElementById('inventoryPanel');
const inventoryGrid = document.getElementById('inventoryGrid');
const inventoryDropZone = document.getElementById('inventoryDropZone');
const offerDropZone = document.getElementById('offerDropZone');
const offerGrid = document.getElementById('offerGrid');
const offerEmpty = document.getElementById('offerEmpty');
const offerTitle = document.getElementById('offerTitle');
const offerHint = document.getElementById('offerHint');
const priceInput = document.getElementById('priceInput');
const lockBtn = document.getElementById('lockBtn');
const payBtn = document.getElementById('payBtn');
const cancelBtn = document.getElementById('cancelBtn');
const lockNotice = document.getElementById('lockNotice');
const balanceText = document.getElementById('balanceText');
const statusBadge = document.getElementById('statusBadge');
const quantityModal = document.getElementById('quantityModal');
const quantityTitle = document.getElementById('quantityTitle');
const quantityAvailable = document.getElementById('quantityAvailable');
const quantityInput = document.getElementById('quantityInput');
const quantityError = document.getElementById('quantityError');
const quantityConfirm = document.getElementById('quantityConfirm');
const quantityCancel = document.getElementById('quantityCancel');

let state = null;
let invite = null;
let inviteInterval = null;
let priceTimer = null;
let quantityContext = null;
let dragPayload = null;

const JRS_TRADE_RESOURCE = 'jrs_inventory';
const post = (name, data = {}) => {
    try {
        fetch(`https://${JRS_TRADE_RESOURCE}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data)
        }).catch(() => {});
    } catch (_) {}

    try {
        if (window.parent && window.parent !== window) {
            window.parent.postMessage({ __jrsTradeCallback: name, data: data }, '*');
        }
    } catch (_) {}
};

const escapeHtml = (value) => String(value ?? '').replace(/[&<>'"]/g, c => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#039;', '"': '&quot;'
}[c]));
const money = (n) => Number(n || 0).toLocaleString('en-US');
const integer = (value, fallback = 0) => {
    const n = Math.floor(Number(value));
    return Number.isFinite(n) ? n : fallback;
};

function iconCandidates(name, base) {
    const raw = String(name || '');
    const lower = raw.toLowerCase();
    const underscored = raw.replaceAll(' ', '_');
    return [
        `${base}${raw}.png`, `${base}${raw}.PNG`,
        `${base}${lower}.png`, `${base}${lower}.PNG`,
        `${base}${underscored}.png`, `${base}${underscored}.PNG`
    ];
}

function imageHtml(name, className = '') {
    const list = iconCandidates(name, state?.imageBase || '');
    const encoded = list.map((url) => escapeHtml(url));
    return `<img class="slot-icon ${className}" src="${encoded[0]}" data-fallbacks='${escapeHtml(JSON.stringify(encoded.slice(1)))}' onerror="window.jrsImageFallback(this)" alt="" />`;
}

window.jrsImageFallback = function(img) {
    let candidates = [];
    try { candidates = JSON.parse(img.dataset.fallbacks || '[]'); } catch (_) {}
    const next = candidates.shift();
    if (next) {
        img.dataset.fallbacks = JSON.stringify(candidates);
        img.src = next;
        return;
    }
    img.style.display = 'none';
};

function sellerCanEdit() {
    return !!state && state.role === 'seller' && state.status === 'draft';
}

function showInvite(data) {
    invite = data;
    state = null;
    closeQuantityModal();
    app.classList.remove('hidden');
    inviteView.classList.remove('hidden');
    tradeView.classList.add('hidden');
    statusBadge.textContent = JrsI18n.t('request', 'REQUEST');
    document.getElementById('inviteSeller').textContent = `${data.seller?.name || JrsI18n.t('player', 'Player')}  #${data.seller?.id || '-'}`;
    let left = integer(data.seconds, 30);
    document.getElementById('inviteTimer').textContent = `${left}s`;
    clearInterval(inviteInterval);
    inviteInterval = setInterval(() => {
        left -= 1;
        document.getElementById('inviteTimer').textContent = `${Math.max(0, left)}s`;
        if (left <= 0) {
            clearInterval(inviteInterval);
            hideAll();
        }
    }, 1000);
}

function hideAll() {
    app.classList.add('hidden');
    inviteView.classList.add('hidden');
    tradeView.classList.add('hidden');
    clearInterval(inviteInterval);
    closeQuantityModal();
    dragPayload = null;
}

function selectedItemMap() {
    const map = new Map();
    for (const entry of state?.offer?.items || []) {
        map.set(Number(entry.itemId), integer(entry.amount ?? entry.count, 0));
    }
    return map;
}

function selectedWeaponSet() {
    return new Set((state?.offer?.weapons || []).map(x => Number(x.weaponId)));
}

function inventoryEntriesBySlot() {
    const slotMap = new Map();
    for (const entry of state?.inventory?.items || []) {
        const slot = Math.max(1, integer(entry.slot, 1));
        slotMap.set(slot, { kind: 'item', entry });
    }
    for (const entry of state?.inventory?.weapons || []) {
        const slot = Math.max(1, integer(entry.slot, 1));
        slotMap.set(slot, { kind: 'weapon', entry });
    }
    return slotMap;
}

function buildDragData(origin, kind, entry) {
    if (kind === 'item') {
        return {
            origin,
            kind,
            itemId: Number(entry.itemId),
            item: entry.item,
            label: entry.label || entry.item,
            count: integer(entry.count ?? entry.amount, 1)
        };
    }
    return {
        origin,
        kind,
        weaponId: Number(entry.weaponId),
        name: entry.name,
        label: entry.label || entry.name,
        used: integer(entry.used, 0)
    };
}

function setDragPayload(event, payload) {
    dragPayload = payload;
    try {
        event.dataTransfer.effectAllowed = payload.origin === 'inventory' ? 'copy' : 'move';
        event.dataTransfer.setData('text/plain', JSON.stringify(payload));
    } catch (_) {}
}

function readDragPayload(event) {
    if (dragPayload) return dragPayload;
    try {
        const raw = event.dataTransfer.getData('text/plain');
        return raw ? JSON.parse(raw) : null;
    } catch (_) {
        return null;
    }
}

function wireDraggable(node, payload) {
    if (!node || !sellerCanEdit()) return;
    node.setAttribute('draggable', 'true');
    node.addEventListener('dragstart', (event) => {
        setDragPayload(event, payload);
        node.classList.add('dragging');
    });
    node.addEventListener('dragend', () => {
        node.classList.remove('dragging');
        dragPayload = null;
        clearDropHighlights();
    });
}

function clearDropHighlights() {
    inventoryDropZone.classList.remove('drop-active');
    offerDropZone.classList.remove('drop-active');
}

function makeSlotNumber(slot) {
    return `<span class="slot-number">${slot}</span>`;
}

function renderInventory() {
    if (!sellerCanEdit()) {
        inventoryGrid.innerHTML = '';
        return;
    }

    const selectedItems = selectedItemMap();
    const selectedWeapons = selectedWeaponSet();
    const slotMap = inventoryEntriesBySlot();
    const occupied = [...slotMap.keys()];
    const highest = occupied.length ? Math.max(...occupied) : 0;
    const totalSlots = Math.max(20, highest + 4);

    let html = '';
    for (let slot = 1; slot <= totalSlots; slot += 1) {
        const data = slotMap.get(slot);
        if (!data) {
            html += `<div class="bag-slot empty-slot" data-slot="${slot}">${makeSlotNumber(slot)}</div>`;
            continue;
        }

        const entry = data.entry;
        if (data.kind === 'item') {
            const selected = selectedItems.get(Number(entry.itemId)) || 0;
            const count = integer(entry.count, 0);
            html += `<div class="bag-slot filled-slot inventory-drag-source${selected ? ' selected-for-trade' : ''}" data-slot="${slot}" data-kind="item" data-id="${Number(entry.itemId)}">
                ${makeSlotNumber(slot)}
                ${imageHtml(entry.item)}
                <span class="slot-count">${count}</span>
                ${selected ? `<span class="reserved-badge">${JrsI18n.t('trade_offer', 'OFFER')} ${selected}</span>` : ''}
                <span class="slot-tooltip">${escapeHtml(entry.label || entry.item)} ×${count}</span>
            </div>`;
        } else {
            const selected = selectedWeapons.has(Number(entry.weaponId));
            const equipped = integer(entry.used, 0) === 1;
            const conditionRaw = Number(entry.conditionlevel);
            const condition = Number.isFinite(conditionRaw) ? Math.round(conditionRaw * (conditionRaw <= 1 ? 100 : 1)) : null;
            html += `<div class="bag-slot filled-slot inventory-drag-source weapon-slot${selected ? ' selected-for-trade' : ''}${equipped ? ' equipped-slot' : ''}" data-slot="${slot}" data-kind="weapon" data-id="${Number(entry.weaponId)}">
                ${makeSlotNumber(slot)}
                ${imageHtml(entry.name)}
                <span class="weapon-mark">W</span>
                ${selected ? `<span class="reserved-badge">${JrsI18n.t('trade_offer', 'IN OFFER')}</span>` : ''}
                ${equipped ? '<span class="equipped-badge">EQUIPPED</span>' : ''}
                <span class="slot-tooltip">${escapeHtml(entry.label || entry.name)}${entry.serial_number ? ` • ${escapeHtml(entry.serial_number)}` : ''}${condition !== null ? ` • ${condition}%` : ''}</span>
            </div>`;
        }
    }

    inventoryGrid.innerHTML = html;

    inventoryGrid.querySelectorAll('.inventory-drag-source').forEach((node) => {
        const kind = node.dataset.kind;
        const id = Number(node.dataset.id);
        if (kind === 'item') {
            const entry = (state.inventory?.items || []).find(x => Number(x.itemId) === id);
            if (!entry) return;
            const payload = buildDragData('inventory', 'item', entry);
            wireDraggable(node, payload);
            node.addEventListener('dblclick', () => openQuantityModal(entry));
        } else {
            const entry = (state.inventory?.weapons || []).find(x => Number(x.weaponId) === id);
            if (!entry) return;
            if (integer(entry.used, 0) !== 1) {
                wireDraggable(node, buildDragData('inventory', 'weapon', entry));
                node.addEventListener('dblclick', () => post('addWeapon', { weaponId: Number(entry.weaponId) }));
            }
        }
    });
}

function renderOffer() {
    const editable = sellerCanEdit();
    const items = state.offer?.items || [];
    const weapons = state.offer?.weapons || [];
    const entries = [
        ...items.map(entry => ({ kind: 'item', entry })),
        ...weapons.map(entry => ({ kind: 'weapon', entry }))
    ];

    offerEmpty.classList.toggle('hidden', entries.length > 0);
    offerTitle.textContent = editable ? JrsI18n.t('drop_here', 'Drop items here') : (state.status === 'draft' ? JrsI18n.t('current_offer', 'Current offer') : JrsI18n.t('secured_offer', 'Secured offer'));
    offerHint.textContent = editable ? JrsI18n.t('drop_zone', 'DROP ZONE') : JrsI18n.t(state.status || 'draft', String(state.status || '').toUpperCase());

    offerGrid.innerHTML = entries.map(({ kind, entry }) => {
        if (kind === 'item') {
            const amount = integer(entry.amount ?? entry.count, 1);
            return `<div class="offer-slot${editable ? ' offer-drag-source' : ''}" data-kind="item" data-id="${Number(entry.itemId)}">
                ${imageHtml(entry.item)}
                <span class="offer-count">×${amount}</span>
                <span class="offer-type">${JrsI18n.t('item_type', 'ITEM')}</span>
                <div class="offer-label">${escapeHtml(entry.label || entry.item)}</div>
                ${editable ? `<span class="return-hint">${JrsI18n.t('drag_back', 'DRAG BACK')}</span>` : ''}
            </div>`;
        }
        const conditionRaw = Number(entry.conditionlevel);
        const condition = Number.isFinite(conditionRaw) ? Math.round(conditionRaw * (conditionRaw <= 1 ? 100 : 1)) : null;
        return `<div class="offer-slot weapon-offer${editable ? ' offer-drag-source' : ''}" data-kind="weapon" data-id="${Number(entry.weaponId)}">
            ${imageHtml(entry.name)}
            <span class="offer-type">${JrsI18n.t('weapon_type', 'WEAPON')}</span>
            <div class="offer-label">${escapeHtml(entry.label || entry.name)}</div>
            <div class="offer-meta">${escapeHtml(entry.serial_number || JrsI18n.t('no_serial', 'NO SERIAL'))}${condition !== null ? ` • ${condition}%` : ''}</div>
            ${editable ? `<span class="return-hint">${JrsI18n.t('drag_back', 'DRAG BACK')}</span>` : ''}
        </div>`;
    }).join('');

    if (editable) {
        offerGrid.querySelectorAll('.offer-drag-source').forEach((node) => {
            const kind = node.dataset.kind;
            const id = Number(node.dataset.id);
            if (kind === 'item') {
                const entry = items.find(x => Number(x.itemId) === id);
                if (entry) wireDraggable(node, buildDragData('offer', 'item', entry));
            } else {
                const entry = weapons.find(x => Number(x.weaponId) === id);
                if (entry) wireDraggable(node, buildDragData('offer', 'weapon', entry));
            }
        });
    }
}

function openQuantityModal(entry) {
    if (!sellerCanEdit() || !entry) return;
    const max = Math.max(1, integer(entry.count, 1));
    const selected = selectedItemMap().get(Number(entry.itemId)) || 0;
    quantityContext = { itemId: Number(entry.itemId), max };
    quantityTitle.textContent = entry.label || entry.item || JrsI18n.t('item', 'Item');
    quantityAvailable.textContent = JrsI18n.f('available', max) + (selected ? JrsI18n.f('currently_in_offer', selected) : '');
    quantityInput.min = '1';
    quantityInput.max = String(max);
    quantityInput.value = String(selected > 0 ? selected : 1);
    quantityError.textContent = '';
    quantityModal.classList.remove('hidden');
    setTimeout(() => {
        quantityInput.focus();
        quantityInput.select();
    }, 0);
}

function closeQuantityModal() {
    quantityContext = null;
    quantityError.textContent = '';
    quantityModal.classList.add('hidden');
}

function confirmQuantity() {
    if (!quantityContext) return;
    const count = integer(quantityInput.value, 0);
    if (count < 1 || count > quantityContext.max) {
        quantityError.textContent = JrsI18n.f('choose_qty', quantityContext.max);
        return;
    }
    post('addItem', { itemId: quantityContext.itemId, count });
    closeQuantityModal();
}

function acceptOfferDrop(event) {
    if (!sellerCanEdit()) return;
    event.preventDefault();
    const payload = readDragPayload(event);
    clearDropHighlights();
    if (!payload || payload.origin !== 'inventory') return;

    if (payload.kind === 'item') {
        const entry = (state.inventory?.items || []).find(x => Number(x.itemId) === Number(payload.itemId));
        if (entry) openQuantityModal(entry);
        return;
    }

    if (payload.kind === 'weapon' && integer(payload.used, 0) !== 1) {
        post('addWeapon', { weaponId: Number(payload.weaponId) });
    }
}

function acceptInventoryDrop(event) {
    if (!sellerCanEdit()) return;
    event.preventDefault();
    const payload = readDragPayload(event);
    clearDropHighlights();
    if (!payload || payload.origin !== 'offer') return;
    if (payload.kind === 'item') post('removeItem', { itemId: Number(payload.itemId) });
    if (payload.kind === 'weapon') post('removeWeapon', { weaponId: Number(payload.weaponId) });
}

function wireDropZone(zone, expectedOrigin, handler) {
    zone.addEventListener('dragenter', (event) => {
        if (!sellerCanEdit()) return;
        const payload = readDragPayload(event);
        if (!payload || payload.origin !== expectedOrigin) return;
        event.preventDefault();
        zone.classList.add('drop-active');
    });
    zone.addEventListener('dragover', (event) => {
        if (!sellerCanEdit()) return;
        const payload = readDragPayload(event);
        if (!payload || payload.origin !== expectedOrigin) return;
        event.preventDefault();
        if (event.dataTransfer) event.dataTransfer.dropEffect = expectedOrigin === 'inventory' ? 'copy' : 'move';
        zone.classList.add('drop-active');
    });
    zone.addEventListener('dragleave', (event) => {
        if (!zone.contains(event.relatedTarget)) zone.classList.remove('drop-active');
    });
    zone.addEventListener('drop', handler);
}

wireDropZone(offerDropZone, 'inventory', acceptOfferDrop);
wireDropZone(inventoryDropZone, 'offer', acceptInventoryDrop);

function renderState(next) {
    state = next;
    invite = null;
    clearInterval(inviteInterval);
    closeQuantityModal();
    app.classList.remove('hidden');
    inviteView.classList.add('hidden');
    tradeView.classList.remove('hidden');

    const sellerMode = state.role === 'seller';
    inventoryPanel.classList.toggle('hidden', !sellerMode || state.status !== 'draft');
    tradeView.classList.toggle('buyer-mode', !sellerMode || state.status !== 'draft');

    document.getElementById('sellerName').textContent = `${state.seller?.name || JrsI18n.t('seller', 'Seller')}${state.seller?.id ? `  #${state.seller.id}` : ''}`;
    document.getElementById('buyerName').textContent = `${state.buyer?.name || JrsI18n.t('buyer', 'Buyer')}${state.buyer?.id ? `  #${state.buyer.id}` : ''}`;
    document.getElementById('sellerStatus').textContent = state.seller?.online ? JrsI18n.t('online', 'ONLINE') : JrsI18n.t('offline', 'OFFLINE');
    document.getElementById('buyerStatus').textContent = state.buyer?.online ? JrsI18n.t('online', 'ONLINE') : JrsI18n.t('offline', 'OFFLINE');
    statusBadge.textContent = JrsI18n.t(state.status || 'draft', String(state.status || 'draft').toUpperCase());

    priceInput.value = integer(state.price, 0);
    priceInput.disabled = !(sellerMode && state.status === 'draft');
    balanceText.textContent = state.role === 'buyer' ? JrsI18n.f('your_cash', money(state.balance)) : '';

    const locked = state.status !== 'draft';
    lockNotice.classList.toggle('hidden', !locked);
    lockBtn.classList.toggle('hidden', !(sellerMode && state.status === 'draft'));
    payBtn.classList.toggle('hidden', !(state.role === 'buyer' && state.status === 'locked'));
    cancelBtn.classList.toggle('hidden', state.status === 'processing');

    renderInventory();
    renderOffer();
}

priceInput.addEventListener('input', () => {
    if (!state || state.role !== 'seller' || state.status !== 'draft') return;
    clearTimeout(priceTimer);
    priceTimer = setTimeout(() => {
        post('setPrice', { price: Math.max(0, integer(priceInput.value, 0)) });
    }, 260);
});

quantityConfirm.addEventListener('click', confirmQuantity);
quantityCancel.addEventListener('click', closeQuantityModal);
quantityInput.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') confirmQuantity();
    if (event.key === 'Escape') closeQuantityModal();
});

lockBtn.addEventListener('click', () => post('lockOffer'));
payBtn.addEventListener('click', () => post('pay'));
cancelBtn.addEventListener('click', () => post('cancelTrade'));
document.getElementById('closeBtn').addEventListener('click', () => {
    post('closeUi');
    hideAll();
});
document.getElementById('acceptInvite').addEventListener('click', () => {
    if (invite) post('acceptInvite', { tradeKey: invite.tradeKey });
});
document.getElementById('declineInvite').addEventListener('click', () => {
    if (invite) post('declineInvite', { tradeKey: invite.tradeKey });
    hideAll();
});

document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    if (!quantityModal.classList.contains('hidden')) {
        closeQuantityModal();
        return;
    }
    post('closeUi');
    hideAll();
});

window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.action === 'invite') showInvite(msg.data || {});
    if (msg.action === 'state') renderState(msg.data || {});
    if (msg.action === 'close') hideAll();
});
