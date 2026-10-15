// JavaScript Dev Mode logging. Disabled by default in html/config.js.
function jrsDevLog(...args) {
    if (typeof config !== "undefined" && config.debug === true) {
        console.log(...args);
    }
}

// Every panel lives in the scaled 1448x1086 canvas (--jrs-exact-scale). jQuery UI
// sizes drop targets with offsetWidth/offsetHeight, which ignore that scale(),
// so above 1.0 (1440p / 4K) each slot only accepted drops in its top-left
// corner, and below 1.0 the hit box spilled onto the neighbouring slot.
// Measure the real on-screen box instead.
(function patchJrsScaledDroppables() {
    if (typeof $ === "undefined" || !$.ui || !$.ui.ddmanager || $.ui.ddmanager.__jrsScaled) return;
    // Replaces jQuery UI's prepareOffsets. The stock one activated each target
    // (a class write) and then measured the next one (a style read), so every
    // drag start recalculated styles once per droppable. All measuring happens
    // first here, then all the activation.
    $.ui.ddmanager.prepareOffsets = function(draggable, event) {
        jrsPruneDetachedDroppables();
        if (!draggable || !draggable.options) return;
        const list = $.ui.ddmanager.droppables[draggable.options.scope] || [];
        const dragged = draggable.currentItem || draggable.element;
        const own = dragged ? dragged.find(":data(ui-droppable)").addBack().toArray() : [];
        const activate = event && event.type === "mousedown" ? [] : null;
        for (let i = 0; i < list.length; i++) {
            const drop = list[i];
            if (!drop || !drop.element || !drop.element[0]) continue;
            if (drop.options.disabled || !drop.accept.call(drop.element[0], dragged)) continue;
            if (own.indexOf(drop.element[0]) !== -1) {
                // The dragged element itself (jQuery UI zeroes its height).
                drop.proportions().height = 0;
                continue;
            }
            const rect = jrsVisibleDropRect(drop.element[0]);
            // Scrolled out of its grid, or inside a panel the player hid: not a
            // drop target. Without this, the bag's hidden rows (which sit right
            // under the quick slots) swallowed hotbar drops.
            drop.visible = !!rect;
            if (!rect) continue;
            // Real on-screen box: offsetWidth/offsetHeight ignore the canvas
            // scale(), which shrank or spilled every slot's hit box.
            drop.offset = { left: rect.left + window.pageXOffset, top: rect.top + window.pageYOffset };
            drop.proportions({ width: rect.width, height: rect.height });
            if (activate) activate.push(drop);
        }
        if (activate) {
            for (let i = 0; i < activate.length; i++) activate[i]._activate.call(activate[i], event);
        }
    };

    // The part of a drop target the player can actually see: clipped to every
    // scrolling grid above it, and null when it is scrolled away or its panel
    // is hidden.
    function jrsVisibleDropRect(element) {
        if (element.closest && element.closest(".jrs-panel-hidden")) return null;
        const r = element.getBoundingClientRect();
        let left = r.left, top = r.top, right = r.right, bottom = r.bottom;
        for (let node = element.parentElement; node && node !== document.body; node = node.parentElement) {
            if (node.id === "tableData" || node.id === "expand_container" || node.id === "groundData" || node.id === "clothingSlotsGrid" || /(auto|scroll|hidden|clip)/.test((node.style && (node.style.overflowY + " " + node.style.overflowX)) || "")) {
                const c = node.getBoundingClientRect();
                left = Math.max(left, c.left);
                top = Math.max(top, c.top);
                right = Math.min(right, c.right);
                bottom = Math.min(bottom, c.bottom);
            }
        }
        if (right - left < 4 || bottom - top < 4) return null;
        return { left: left, top: top, width: right - left, height: bottom - top };
    }
    $.ui.ddmanager.__jrsScaled = true;
})();

// Slot grids are rebuilt with innerHTML, which bypasses jQuery's cleanData, so
// the old slots' droppables never unregistered: $.ui.ddmanager kept every one
// ever created (450+ after a few refreshes, growing all session, even with the
// bag closed) and every drag start / mouse move walked the whole pile. Always
// swap slot HTML through jrsSetWidgetHtml(); the prune is a safety net.
function jrsPruneDetachedDroppables() {
    const all = $.ui && $.ui.ddmanager && $.ui.ddmanager.droppables;
    if (!all) return;
    for (const scope in all) {
        const list = all[scope];
        if (!Array.isArray(list)) continue;
        for (let i = list.length - 1; i >= 0; i--) {
            const node = list[i] && list[i].element && list[i].element[0];
            if (!node || !node.isConnected) list.splice(i, 1);
        }
    }
}

// Layout mode as seen by the body classes: closed, bag, or bag + storage.
function jrsBodyLayoutClass() {
    const list = document.body ? document.body.classList : null;
    if (!list || !list.contains("inventory-layout-standard")) return "";
    return list.contains("inventory-storage-open") ? "storage" : "inventory";
}

function jrsSetWidgetHtml(container, html) {
    if (!container) return;
    if (window.jQuery) window.jQuery(container).empty();
    container.innerHTML = html;
}

// The bag, storage and ground panels are invisible while the menu is closed.
// Rebuilding them there (every metabolism tick, every nearby drop) was pure
// waste; opening always sends a full table and renders it fresh.
function jrsInventoryVisible() {
    return $("#container").is(":visible");
}

var ground_inv = [];
var clicked_drop = 0;
var groundPickupPending = Object.create(null);
const JRS_DRAG_REVERT_MS = 115;
const JRS_DRAG_DISTANCE = 2;
const JRS_DRAG_OPACITY = 0.96;

// Drag ghost. `helper: jrsDragGhost` copied the whole slot into <body>, where none
// of the grid-scoped slot CSS reaches it: the box shrank to the stock 65px and
// the item art overflowed/cropped, and every mouse move repainted the clone's
// stacked drop-shadow/brightness filters. This builds a small standalone node
// at the exact on-screen size of the slot: slot art + the whole item image
// (contained) + the count, nothing else.
function jrsDragGhost() {
    const src = this;
    const rect = src.getBoundingClientRect();
    const img = src.querySelector("img");
    const countEl = src.querySelector(".bottom-right, .slot-count, .item-count");
    // .bottom-right is "count<br>weight": only the first text node is the count.
    const countNode = countEl ? countEl.firstChild : null;
    const count = countNode ? String(countNode.textContent || "").trim() : "";

    const ghost = document.createElement("div");
    ghost.className = "jrs-drag-ghost";
    ghost.style.width = Math.round(rect.width) + "px";
    ghost.style.height = Math.round(rect.height) + "px";
    ghost.style.setProperty("--jrs-ghost-pad", Math.round(Math.min(rect.width, rect.height) * 0.08) + "px");
    if (!img || !img.getAttribute("src")) {
        // Nothing to draw (text-only entry): fall back to a sized clone.
        const clone = src.cloneNode(true);
        clone.removeAttribute("id");
        clone.style.width = ghost.style.width;
        clone.style.height = ghost.style.height;
        return clone;
    }
    {
        const gi = document.createElement("img");
        gi.src = img.currentSrc || img.src;
        gi.draggable = false;
        ghost.appendChild(gi);
    }
    if (count && count !== "1" && /^[\d.,xX]+$/.test(count)) {
        const c = document.createElement("span");
        c.className = "jrs-drag-ghost-count";
        c.textContent = count;
        ghost.appendChild(c);
    }
    return ghost;
}

let jrsDragOrigin = null;
let jrsStorageDropTargetSlot = null;

function setJrsStorageDragState(origin) {
    jrsDragOrigin = origin || null;
    const body = document.body;
    if (!body) return;
    body.classList.toggle("storage-drag-from-inventory", jrsDragOrigin === "inventory");
    body.classList.toggle("storage-drag-from-storage", jrsDragOrigin === "storage");
}

function clearJrsStorageDragState() {
    jrsStorageDropTargetSlot = null;
    setJrsStorageDragState(null);
}

var jrsInventoryResourceName = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'jrs_inventory';
var jrsInventoryUrl = 'https://' + jrsInventoryResourceName;

// JRS_LIGHT_IMAGE_FALLBACK
// Missing item artwork is handled asynchronously. This avoids synchronous
// per-image HEAD requests for every visible inventory/storage/ground slot.
document.addEventListener("error", function(event) {
    const image = event.target;
    if (!image || image.tagName !== "IMG") return;
    const src = String(image.getAttribute("src") || "");
    if (src.indexOf("images/items/") === -1 || src.indexOf("badItem.png") !== -1) return;
    // Item names and PNG filenames sometimes differ only by case. Try a
    // lowercase filename once before falling back to the placeholder, so a
    // case-mismatched item still shows its real artwork.
    if (!image.dataset.jrsTriedLower) {
        image.dataset.jrsTriedLower = "1";
        const match = src.match(/images\/items\/(.+)\.png(\?.*)?$/i);
        if (match && match[1]) {
            const lower = match[1].toLowerCase();
            if (lower !== match[1]) {
                image.src = "images/items/" + lower + ".png";
                return;
            }
        }
    }
    image.onerror = null;
    image.src = "images/items/badItem.png";
}, true);


// ---------------------------------------------------------
// JRS inventory UI sounds
// Exactly three bundled sounds are used by the normal Inventory only:
// open, close, and click. Storage / robbery / other NUI surfaces stay silent.
// ---------------------------------------------------------
const jrsUiSoundConfig = function() {
    const defaults = {
        enabled: true,
        clickEnabled: true,
        openEnabled: true,
        closeEnabled: true,
        clickVolume: 0.34,
        openVolume: 0.40,
        closeVolume: 0.38,
        clickCooldownMs: 45
    };

    if (typeof config === "undefined" || !config.uiSounds) {
        return defaults;
    }

    return Object.assign({}, defaults, config.uiSounds);
};

const jrsUiSoundPools = {
    click: [],
    open: [],
    close: []
};

let jrsLastClickSoundAt = 0;
let jrsInventoryMenuAudiblyOpen = false;

function createJrsSoundPool(type, source, size) {
    if (jrsUiSoundPools[type].length > 0) return;

    for (let i = 0; i < size; i++) {
        const audio = new Audio(source);
        audio.preload = "auto";
        jrsUiSoundPools[type].push(audio);
    }
}

function initializeJrsUiSounds() {
    createJrsSoundPool("open", "sounds/ui_open.mp3", 1);
    createJrsSoundPool("close", "sounds/ui_close.mp3", 1);
    createJrsSoundPool("click", "sounds/ui_click.mp3", 2);
}

function isJrsInventorySoundActive() {
    const body = document.body;
    if (!body || !body.classList.contains("inventory-layout-standard")) return false;
    if (body.classList.contains("inventory-storage-open")) return false;
    const container = document.getElementById("container");
    if (!container) return false;
    return window.getComputedStyle(container).display !== "none";
}

function playJrsUiSound(type) {
    if (!isJrsInventorySoundActive()) return;

    const settings = jrsUiSoundConfig();
    if (!settings.enabled) return;
    if (type === "click" && !settings.clickEnabled) return;
    if (type === "open" && !settings.openEnabled) return;
    if (type === "close" && !settings.closeEnabled) return;

    if (type === "click") {
        const now = Date.now();
        if (now - jrsLastClickSoundAt < Number(settings.clickCooldownMs || 45)) return;
        jrsLastClickSoundAt = now;
    }

    const pool = jrsUiSoundPools[type];
    if (!pool || pool.length === 0) return;

    let audio = pool.find(function(entry) { return entry.paused || entry.ended; });
    if (!audio) audio = pool[0];

    try {
        audio.pause();
        audio.currentTime = 0;
        let selectedVolume = settings.clickVolume;
        if (type === "open") selectedVolume = settings.openVolume;
        if (type === "close") selectedVolume = settings.closeVolume;
        audio.volume = Math.max(0, Math.min(1, Number(selectedVolume) || 0));
        const promise = audio.play();
        if (promise && typeof promise.catch === "function") {
            promise.catch(function() {});
        }
    } catch (error) {
        jrsDevLog("[JRS Inventory] UI sound error:", error);
    }
}

const jrsUiInteractiveSelector = [
    "button",
    "[role='button']",
    "[onclick]",
    ".item",
    ".empty-slot",
    ".storage-slot",
    ".ground-slot",
    ".clothing-slot",
    ".hotbar-slot",
    ".inventory-filter-btn",
    ".inventory-filter-arrow",
    ".content_button",
    ".trash-btn"
].join(",");

function isJrsUiControlDisabled(element) {
    return !element || element.disabled === true || element.getAttribute("aria-disabled") === "true";
}

function playJrsInventoryOpenSoundOnce() {
    if (jrsInventoryMenuAudiblyOpen) return;
    jrsInventoryMenuAudiblyOpen = true;
    playJrsUiSound("open");
}

function playJrsInventoryCloseSoundOnce() {
    if (!jrsInventoryMenuAudiblyOpen) return;
    playJrsUiSound("close");
    jrsInventoryMenuAudiblyOpen = false;
}

function resetJrsInventoryOpenSoundState() {
    jrsInventoryMenuAudiblyOpen = false;
}

document.addEventListener("DOMContentLoaded", function() {
    initializeJrsUiSounds();

    document.addEventListener("mousedown", function(event) {
        if (event.button !== 0 && event.button !== 2) return;
        const control = event.target.closest ? event.target.closest(jrsUiInteractiveSelector) : null;
        if (!control || isJrsUiControlDisabled(control)) return;
        playJrsUiSound("click");
    }, true);
});

const contextMenu = document.getElementById("context-menu");
const table_for_delete = document.querySelector('#playerData');
const cnt1 = document.getElementById("cnt1");
const cnt2 = document.getElementById("cnt2");
const scope = document.querySelector("body");


var dragStartSlot = null;
var dragTargetSlot = null;


var count_inventory = 0;
var count_winventory = 0;
var count_sinventory = 0;
var max_count_inventory = 0;
var max_count_winventory = 0;
var displayed = false;
var changed = false;
var clicked_id = "";
var clicked_meta = {};
var clicked_type = "";
var visible = false;
var drag_to_normal = false
var drag_to_other = false
var id_container = 0
var containerMode = "storage"
var robberyTargetName = ""
var dragged_item_inv = 0
var dragged_witem_inv = 0
var dragged_stor_inv = 0
var dragged = false
// Shift held at drop time = move the whole stack, no amount box. Captured on
// every pointer event (capture phase runs before jQuery UI's drop on mouseup)
// plus the key itself, and cleared when the page loses focus.
var jrsShiftHeld = false
document.addEventListener("keydown", function(e) { if (e.key === "Shift") jrsShiftHeld = true; }, true);
document.addEventListener("keyup", function(e) { if (e.key === "Shift") jrsShiftHeld = false; }, true);
["mousemove", "mousedown", "mouseup"].forEach(function(type) {
    document.addEventListener(type, function(e) { jrsShiftHeld = e.shiftKey === true; }, true);
});
window.addEventListener("blur", function() { jrsShiftHeld = false; });
// Time the last drag ended, so a click fired by that same mouseup can never
// also run the Shift+click quick transfer (double move of one stack).
var jrsLastDragEndAt = 0
document.addEventListener("mouseup", function() { if (dragged) jrsLastDragEndAt = Date.now(); }, true);
var size = 0
var moneysd = 0
var goldsd = 0
var dirtymoneysd = 0

function isCurrencyType(type) {
    return type === "money" || type === "gold" || type === "dirtymoney";
}

function getCurrencyBalance(type) {
    if (type === "money") return Number(moneysd) || 0;
    if (type === "gold") return Number(goldsd) || 0;
    if (type === "dirtymoney") return Number(dirtymoneysd) || 0;
    return 0;
}
var id_for_use_item = -1
var id_for_use_weapon =-1
var clicked_name = ""
var table_inv = []
var wtable_inv = []
var storage_inv = []

function normalizeInventoryCollection(value) {
    if (Array.isArray(value)) return value;
    if (!value || typeof value !== "object") return [];

    return Object.keys(value)
        .sort(function(a, b) {
            const aNumber = Number(a);
            const bNumber = Number(b);
            if (Number.isFinite(aNumber) && Number.isFinite(bNumber)) return aNumber - bNumber;
            return String(a).localeCompare(String(b));
        })
        .map(function(key) { return value[key]; })
        .filter(function(entry) { return entry && typeof entry === "object"; });
}
var usableScroll = 0
var inInput = false
var allCount = 0
var giveItemEnabled = false
var givePlayerSelectorActive = false;
var givePlayerSelectorPurpose = "single";
var givePlayerSelectors = new Map();
var giveTransferPending = false;

function ensureGivePlayerSelectorLayer() {
    let layer = document.getElementById("give-player-selector-layer");
    if (layer) return layer;

    layer = document.createElement("div");
    layer.id = "give-player-selector-layer";
    layer.innerHTML = '<div id="give-player-selector-title">' + JrsI18n.t("inv_select_player", "SELECT PLAYER") + '</div><div id="give-player-selector-hint">' + JrsI18n.t("inv_give_pick_hint", "CLICK THE MARKER ON A PLAYER &nbsp; • &nbsp; ESC TO CANCEL") + '</div><div id="give-player-selector-empty" style="display:none;"></div>';
    document.body.appendChild(layer);
    return layer;
}

function updatePlayerSelectorLabels() {
    const title = document.getElementById("give-player-selector-title");
    const hint = document.getElementById("give-player-selector-hint");
    if (title) title.textContent = givePlayerSelectorPurpose === "trade" ? JrsI18n.t("inv_select_player_trade", "SELECT A PLAYER TO TRADE") : JrsI18n.t("inv_select_player", "SELECT PLAYER");
    if (hint) hint.innerHTML = givePlayerSelectorPurpose === "trade"
        ? JrsI18n.t("inv_selector_hint_trade", "CLICK A NEARBY PLAYER &nbsp; • &nbsp; ESC TO RETURN TO INVENTORY")
        : JrsI18n.t("inv_give_pick_hint", "CLICK THE MARKER ON A PLAYER &nbsp; • &nbsp; ESC TO CANCEL");
    const empty = document.getElementById("give-player-selector-empty");
    if (empty) empty.textContent = JrsI18n.t("inv_give_no_player", "NO PLAYER NEARBY - GET CLOSER");
}

function clearGivePlayerSelectors() {
    givePlayerSelectors.forEach(function(selector) {
        if (selector && selector.parentNode) selector.parentNode.removeChild(selector);
    });
    givePlayerSelectors = new Map();
    const layer = document.getElementById("give-player-selector-layer");
    if (layer) layer.style.display = "none";
}

function selectGivePlayer(targetId) {
    const id = Number(targetId);
    if (!Number.isFinite(id) || id <= 0 || giveTransferPending) return;

    giveTransferPending = true;
    givePlayerSelectorActive = false;
    giveItemEnabled = false;
    const purpose = givePlayerSelectorPurpose;
    clearGivePlayerSelectors();

    if (purpose === "trade") {
        startTradeWithSelectedPlayer(id);
    } else if (purpose === "multi") {
        giveMultiSelectionToPlayer(id);
    } else if (pendingGiveRequest) {
        sendPendingGiveTo(id);
    } else {
        transferToPlayer(id);
    }
}

function renderGivePlayerSelectors(positions) {
    const layer = ensureGivePlayerSelectorLayer();
    layer.style.display = "block";

    const liveIds = new Set();
    (positions || []).forEach(function(pos) {
        const id = Number(pos.id);
        if (!Number.isFinite(id) || !Array.isArray(pos.coords)) return;
        liveIds.add(id);

        let selector = givePlayerSelectors.get(id);
        if (!selector) {
            selector = document.createElement("button");
            selector.type = "button";
            selector.className = "give-player-selector";
            selector.dataset.playerId = String(id);
            const displayName = pos.name ? String(pos.name) : ('Player ' + id);
            selector.innerHTML = '<span class="give-player-selector-dot" aria-hidden="true"></span><span class="give-player-selector-label"><span class="give-player-selector-id">ID: ' + id + '</span><span class="give-player-selector-name"></span></span>';
            selector.querySelector(".give-player-selector-name").textContent = displayName;
            selector.addEventListener("click", function(event) {
                event.preventDefault();
                event.stopPropagation();
                selectGivePlayer(id);
            });
            layer.appendChild(selector);
            givePlayerSelectors.set(id, selector);
        }

        const nextLeft = Math.round(Number(pos.coords[0]) * window.innerWidth);
        const nextTop = Math.round(Number(pos.coords[1]) * window.innerHeight);
        if (selector._jrsLeft !== nextLeft) { selector.style.left = nextLeft + "px"; selector._jrsLeft = nextLeft; }
        if (selector._jrsTop !== nextTop) { selector.style.top = nextTop + "px"; selector._jrsTop = nextTop; }
        const nextTitle = pos.name ? (String(pos.name) + " [" + id + "]") : ("Player " + id);
        if (selector.title !== nextTitle) selector.title = nextTitle;
    });

    givePlayerSelectors.forEach(function(selector, id) {
        if (!liveIds.has(id)) {
            if (selector && selector.parentNode) selector.parentNode.removeChild(selector);
            givePlayerSelectors.delete(id);
        }
    });

    const empty = document.getElementById("give-player-selector-empty");
    if (empty) {
        if (!empty.textContent) empty.textContent = JrsI18n.t("inv_give_no_player", "NO PLAYER NEARBY - GET CLOSER");
        empty.style.display = liveIds.size === 0 ? "block" : "none";
    }
}

var isInContext = false
var canTransfer = false
var blockMe = false
var blockMeSince = 0
// A storage request normally unlocks through cleanTransfer / a storage
// re-render. If neither ever arrives, stop blocking after a few seconds
// instead of freezing every later drag until the window is reopened.
function jrsStorageTransferBusy() {
    if (blockMe !== false && Date.now() - blockMeSince > 8000) blockMe = false;
    return blockMe !== false;
}
function jrsStorageTransferLock() {
    blockMe = true;
    blockMeSince = Date.now();
    jrsStorageLastSendAt = blockMeSince;
}

// Storage transfer queue (2.3.3). A drop made while the previous transfer was
// still waiting on the server used to be thrown away silently, so moving
// several stacks quickly felt slow / "stuck" and each one had to be retried.
// Now each drop is queued and sent as soon as the server answers the previous
// one. Payloads carry itemId / weapon id, never grid indexes, so a re-render
// between drop and send cannot point them at a different stack.
var jrsStorageLastSendAt = 0;
var jrsStorageQueue = [];
var jrsStorageQueueTimer = 0;
const JRS_STORAGE_QUEUE_MAX = 25;
// Server Config.ActionCooldownMs is 100: stay just above it between sends.
const JRS_STORAGE_QUEUE_GAP_MS = 130;

function jrsStorageQueueKey(endpoint, payload) {
    const id = payload.weapon ? ("w" + (payload.id || payload.item)) : ("i" + (payload.itemId || payload.item));
    return endpoint + ":" + id;
}

function jrsMarkStoragePending(endpoint, payload, pending) {
    const inv = endpoint === "transfer_to_storage";
    let selector;
    if (inv) {
        const entryKey = payload.weapon ? ("weapon:" + payload.id) : ("item:" + payload.itemId);
        selector = '#tableData [data-entry-key="' + entryKey.replace(/["\\]/g, "") + '"]';
    } else {
        selector = '#expand_container .storage-slot[data-storage-slot="' + String(payload.storageSlot) + '"]';
    }
    try { $(selector).toggleClass("jrs-transfer-pending", pending !== false); } catch (_) {}
}

function jrsSendStorageTransfer(endpoint, payload) {
    jrsStorageTransferLock();
    jrsMarkStoragePending(endpoint, payload, true);
    $.post(jrsInventoryUrl + '/' + endpoint, JSON.stringify(payload));
}

function jrsQueueStorageTransfer(endpoint, payload) {
    if (!jrsStorageTransferBusy() && jrsStorageQueue.length === 0) {
        jrsSendStorageTransfer(endpoint, payload);
        return;
    }
    const key = jrsStorageQueueKey(endpoint, payload);
    if (jrsStorageQueue.some(function(q) { return q.key === key; })) return;
    if (jrsStorageQueue.length >= JRS_STORAGE_QUEUE_MAX) return;
    jrsStorageQueue.push({ key: key, endpoint: endpoint, payload: payload });
    jrsMarkStoragePending(endpoint, payload, true);
}

// Re-renders drop the pending class; put it back on stacks still waiting.
function jrsMarkQueuedStoragePending() {
    for (const q of jrsStorageQueue) jrsMarkStoragePending(q.endpoint, q.payload, true);
}

function jrsClearStorageQueue() {
    jrsStorageQueue = [];
    if (jrsStorageQueueTimer) { clearTimeout(jrsStorageQueueTimer); jrsStorageQueueTimer = 0; }
    $(".jrs-transfer-pending").removeClass("jrs-transfer-pending");
}

function jrsPumpStorageQueue() {
    if (jrsStorageQueueTimer || jrsStorageQueue.length === 0) return;
    const wait = Math.max(0, JRS_STORAGE_QUEUE_GAP_MS - (Date.now() - jrsStorageLastSendAt));
    jrsStorageQueueTimer = setTimeout(function() {
        jrsStorageQueueTimer = 0;
        if (!id_container || inInput || jrsStorageTransferBusy()) {
            if (!id_container) jrsClearStorageQueue();
            else if (jrsStorageQueue.length) jrsStorageQueueTimer = setTimeout(function() { jrsStorageQueueTimer = 0; jrsPumpStorageQueue(); }, 150);
            return;
        }
        const next = jrsStorageQueue.shift();
        if (next) jrsSendStorageTransfer(next.endpoint, next.payload);
    }, wait);
}
var dragTransferMode = false;
var personalItems = {};
var currentInventoryFilter = "all";
var currentInventorySearch = "";
var lastExpandedInfoSlot = null;
var expandedInfoHideTimer = null;
var currentInventoryFilterIndex = 0;
var currentInventorySortIndex = 0;
var activeTemporarySortMode = null;
var manualItemSlots = {};
var manualWeaponSlots = {};
var inventoryPinnedEntries = {};
var isRenderingTemporarySort = false;
var skipSortReapplyOnce = false;
var splitStackItemId = null;
var quickTransferBusyUntil = 0;
var inventoryDamagedThreshold = 30;
var inventoryWeightWarningPercent = 80;
var inventoryWeightCriticalPercent = 95;
var inventoryWeightWarningSound = false;
var lastWeightAlertLevel = 0;
var inventoryWeightBreakdown = {};
var multiSelectMode = false;
var multiSelectedEntries = {};

var inventorySortOptions = [
    { key: "name", get label() { return JrsI18n.t("inv_sort_name", "NAME") } },
    { key: "type", get label() { return JrsI18n.t("inv_sort_type", "TYPE") } },
    { key: "weight", get label() { return JrsI18n.t("inv_sort_weight", "WEIGHT") } },
    { key: "count", get label() { return JrsI18n.t("inv_sort_count", "COUNT") } },
    { key: "weapons", get label() { return JrsI18n.t("inv_sort_weapons", "WEAPONS") } }
];

var inventoryFilterOptions = [
    {
        key: "all",
        get label() { return JrsI18n.t("inv_filter_all", "ALL") },
        get title() { return JrsI18n.t("inv_filter_all_title", "All items") },
        icon: "images/filter/allitems.png",
        activeIcon: "images/filter/allItemsH.png"
    },
    {
        key: "weapons",
        get label() { return JrsI18n.t("inv_filter_weapons", "WEAPONS") },
        get title() { return JrsI18n.t("inv_filter_weapons_title", "Weapons") },
        icon: "images/filter/allValuable.png",
        activeIcon: "images/filter/allValuableH.png"
    },
    {
        key: "ammo",
        get label() { return JrsI18n.t("inv_filter_ammo", "AMMO") },
        get title() { return JrsI18n.t("inv_filter_ammo_title", "Ammunition") },
        icon: "images/filter/allAmmo.png",
        activeIcon: "images/filter/allAmmoH.png"
    },
    {
        key: "food",
        get label() { return JrsI18n.t("inv_filter_food", "FOOD") },
        get title() { return JrsI18n.t("inv_filter_food_title", "Food") },
        icon: "images/filter/allEat.png",
        activeIcon: "images/filter/allEatH.png"
    },
    {
        key: "drink",
        get label() { return JrsI18n.t("inv_filter_drink", "DRINKS") },
        get title() { return JrsI18n.t("inv_filter_drink_title", "Drinks") },
        icon: "images/filter/allDrink.png",
        activeIcon: "images/filter/allDrinkH.png"
    },
    {
        key: "seeds",
        get label() { return JrsI18n.t("inv_filter_seeds", "SEEDS") },
        get title() { return JrsI18n.t("inv_filter_seeds_title", "Seeds") },
        icon: "images/filter/allHerb.png",
        activeIcon: "images/filter/allHerbH.png"
    },
    {
        key: "equipment",
        get label() { return JrsI18n.t("inv_filter_equipment", "TOOLS") },
        get title() { return JrsI18n.t("inv_filter_equipment_title", "Equipment and tools") },
        icon: "images/filter/allCraft.png",
        activeIcon: "images/filter/allCraftH.png"
    },
    {
        key: "damaged",
        get label() { return JrsI18n.t("inv_filter_damaged", "DAMAGED") },
        get title() { return JrsI18n.t("inv_filter_damaged_title", "Damaged items and weapons") },
        icon: "images/filter/allTrash.png",
        activeIcon: "images/filter/allTrashH.png"
    },
    {
        key: "personal",
        get label() { return JrsI18n.t("inv_filter_personal", "PERSONAL") },
        get title() { return JrsI18n.t("inv_filter_personal_title", "Personal items") },
        icon: "images/filter/allBuild.png",
        activeIcon: "images/filter/allBuildH.png"
    }
];


function clampInventoryPercent(value, usesFractionScale) {
    let number = Number(value);
    if (!Number.isFinite(number)) return null;
    if (usesFractionScale && number >= 0 && number <= 1) number *= 100;
    return Math.max(0, Math.min(100, number));
}

function getItemDurabilityPercent(item) {
    if (!item) return null;
    if (item.metaData && item.metaData.durability !== undefined && item.metaData.durability !== null) {
        return clampInventoryPercent(item.metaData.durability, false);
    }
    return null;
}

function getWeaponConditionPercent(weapon) {
    if (!weapon || weapon.conditionlevel === undefined || weapon.conditionlevel === null) return null;
    return clampInventoryPercent(weapon.conditionlevel, true);
}

function isEntryDamaged(kind, data) {
    const condition = kind === "weapon" ? getWeaponConditionPercent(data) : getItemDurabilityPercent(data);
    return condition !== null && condition <= inventoryDamagedThreshold;
}

function getWeaponAmmoTotal(weapon) {
    let ammo = weapon ? weapon.ammo : null;
    if (typeof ammo === "string") {
        try { ammo = JSON.parse(ammo); } catch (_) { return Number(ammo) || 0; }
    }
    if (typeof ammo === "number") return ammo;
    if (!ammo || typeof ammo !== "object") return 0;
    return Object.values(ammo).reduce(function(total, value) {
        return total + (Number(value) || 0);
    }, 0);
}

function getPrimaryWeightCategory(item) {
    const tags = buildInventoryFilterTags(item, "item").split(/\s+/);
    if (tags.includes("ammo")) return "ammo";
    if (tags.includes("food")) return "food";
    if (tags.includes("drink")) return "drink";
    if (tags.includes("seeds")) return "seeds";
    if (tags.includes("equipment")) return "equipment";
    return "other";
}

function formatInventoryNumber(value) {
    return Math.round((Number(value) || 0) * 100) / 100;
}

function getMultiEntryKey(kind, id) {
    return String(kind) + ":" + String(id);
}

function updateMultiSelectToolbar() {
    const count = Object.keys(multiSelectedEntries).length;
    const toolbar = document.getElementById("multi-select-toolbar");
    const button = document.getElementById("inventoryMultiButton");
    const countLabel = document.getElementById("multiSelectedCount");
    const storageButton = document.getElementById("multiStorageButton");
    const container = document.getElementById("container");

    if (toolbar) toolbar.style.display = multiSelectMode ? "grid" : "none";
    if (button) button.classList.toggle("active", multiSelectMode);
    if (countLabel) countLabel.textContent = JrsI18n.f("inv_n_selected", count);
    // STORAGE only means something while a storage is open next to the bag.
    if (storageButton) {
        storageButton.style.display = id_container === 0 ? "none" : "";
        storageButton.disabled = id_container === 0;
    }
    if (toolbar) toolbar.classList.toggle("multi-has-storage", id_container !== 0);
    if (toolbar) toolbar.classList.toggle("multi-empty", count === 0);
    if (container) container.classList.toggle("multi-select-active", multiSelectMode);
    if (document.body) document.body.classList.toggle("inventory-multi-active", multiSelectMode);
}

function applyMultiSelectionVisuals() {
    document.querySelectorAll("#tableData .item").forEach(function(slot) {
        const key = slot.dataset.entryKey;
        slot.classList.toggle("multi-selected", !!key && multiSelectedEntries[key] === true);
    });
    updateMultiSelectToolbar();
}

function toggleMultiSelectMode() {
    multiSelectMode = !multiSelectMode;
    if (!multiSelectMode) multiSelectedEntries = {};
    contextMenu.classList.remove("visible");
    applyMultiSelectionVisuals();
}

function clearMultiSelection() {
    multiSelectedEntries = {};
    document.querySelectorAll(".multi-selected").forEach(function(slot) {
        slot.classList.remove("multi-selected");
    });
    applyMultiSelectionVisuals();
}
window.clearMultiSelection = clearMultiSelection;

function deleteMultiSelection() {
    const entries = getMultiSelectionPayload();
    if (entries.length === 0) {
        clearMultiSelection();
        flashMultiSelectionEmpty();
        return;
    }
    $.post(jrsInventoryUrl + "/multi_delete_items", JSON.stringify({ entries: entries }), function() {
        clearMultiSelection();
    });
}
window.deleteMultiSelection = deleteMultiSelection;

function toggleMultiSelectionElement(slot) {
    if (!multiSelectMode || !slot) return;
    const key = slot.dataset.entryKey;
    if (!key || isCurrencyType(slot.dataset.type)) return;
    if (slot.dataset.personal === "true") return;

    if (multiSelectedEntries[key]) delete multiSelectedEntries[key];
    else multiSelectedEntries[key] = true;
    applyMultiSelectionVisuals();
}

function selectAllVisibleInventoryItems() {
    if (!multiSelectMode) multiSelectMode = true;
    document.querySelectorAll("#tableData .item").forEach(function(slot) {
        if (slot.style.display === "none") return;
        if (!slot.dataset.entryKey || slot.dataset.personal === "true") return;
        if (isCurrencyType(slot.dataset.type)) return;
        multiSelectedEntries[slot.dataset.entryKey] = true;
    });
    applyMultiSelectionVisuals();
}

function getMultiSelectionPayload() {
    return Object.keys(multiSelectedEntries).map(function(key) {
        const separator = key.indexOf(":");
        return {
            kind: key.slice(0, separator),
            id: Number(key.slice(separator + 1))
        };
    }).filter(function(entry) {
        return (entry.kind === "item" || entry.kind === "weapon") && Number.isFinite(entry.id);
    });
}

// Pressing GIVE / STORAGE with nothing picked: flash the counter instead of
// silently doing nothing.
function flashMultiSelectionEmpty() {
    const countLabel = document.getElementById("multiSelectedCount");
    if (!countLabel) return;
    countLabel.textContent = JrsI18n.t("inv_select_items_first", "SELECT ITEMS FIRST");
    countLabel.classList.remove("jrs-multi-flash");
    void countLabel.offsetWidth;
    countLabel.classList.add("jrs-multi-flash");
    window.clearTimeout(countLabel.__jrsFlashTimer);
    countLabel.__jrsFlashTimer = window.setTimeout(function() {
        countLabel.classList.remove("jrs-multi-flash");
        updateMultiSelectToolbar();
    }, 1200);
}

function moveMultiSelectionToStorage() {
    const entries = getMultiSelectionPayload();
    if (id_container === 0) return;
    if (entries.length === 0) { flashMultiSelectionEmpty(); return; }
    $.post(jrsInventoryUrl + "/multi_transfer_to_storage", JSON.stringify({ entries: entries }), function() {
        clearMultiSelection();
    });
}

function startTradeWithSelectedPlayer(targetId) {
    const id = Number(targetId);
    if (!Number.isFinite(id) || id <= 0) {
        giveTransferPending = false;
        return;
    }
    $.post(jrsInventoryUrl + "/trade_select_player", JSON.stringify({ target: id }))
        .always(function() { giveTransferPending = false; });
}

// Closing the bag (display2(false)) wipes multiSelectedEntries, and the bag is
// closed before the player is picked - so the give used to send nothing.
// The picked entries are kept here until a marker is clicked.
var pendingMultiGiveEntries = null;

function openMultiGivePlayers() {
    const entries = getMultiSelectionPayload();
    if (entries.length === 0) { flashMultiSelectionEmpty(); return; }
    pendingMultiGiveEntries = entries;
    givePlayerSelectorPurpose = "multi";
    giveItemEnabled = true;
    closeMultiPlayerWindow();
    $.post(jrsInventoryUrl + "/multi_start_player_selector", JSON.stringify({}));
}

function closeMultiPlayerWindow() {
    const windowElement = document.getElementById("multi-player-window");
    if (windowElement) windowElement.style.display = "none";
}

function giveMultiSelectionToPlayer(targetId) {
    const entries = (pendingMultiGiveEntries && pendingMultiGiveEntries.length) ? pendingMultiGiveEntries : getMultiSelectionPayload();
    pendingMultiGiveEntries = null;
    if (entries.length === 0) { giveTransferPending = false; return; }
    $.post(jrsInventoryUrl + "/multi_give_to_player", JSON.stringify({ target: Number(targetId), entries: entries }), function() {
        clearMultiSelection();
        closeMultiPlayerWindow();
    });
    display2(false);
}

function renderMultiPlayerList(players) {
    const list = document.getElementById("multi-player-list");
    const windowElement = document.getElementById("multi-player-window");
    if (!list || !windowElement) return;

    list.innerHTML = "";
    (players || []).forEach(function(player) {
        const button = document.createElement("button");
        button.type = "button";
        button.textContent = "[" + player.id + "] " + player.name;
        button.onclick = function() { giveMultiSelectionToPlayer(player.id); };
        list.appendChild(button);
    });

    if (!players || players.length === 0) {
        list.innerHTML = '<div class="multi-player-empty">' + JrsI18n.t("inventory_no_player_nearby", "NO PLAYER NEARBY") + '</div>';
    }

    windowElement.style.display = "block";
}

function toggleWeightBreakdown() {
    const panel = document.getElementById("weight-breakdown-panel");
    if (!panel) return;
    panel.style.display = panel.style.display === "block" ? "none" : "block";
}

function renderWeightBreakdown() {
    const panel = document.getElementById("weight-breakdown-panel");
    if (!panel) return;
    const kg = JrsI18n.t('inv_kg_unit', 'KG');
    const rows = [
        [JrsI18n.t('inv_cat_food', 'FOOD'), inventoryWeightBreakdown.food],
        [JrsI18n.t('inv_cat_drink', 'DRINKS'), inventoryWeightBreakdown.drink],
        [JrsI18n.t('inv_wb_seeds', 'SEEDS'), inventoryWeightBreakdown.seeds],
        [JrsI18n.t('inv_cat_ammo', 'AMMO'), inventoryWeightBreakdown.ammo],
        [JrsI18n.t('inv_wb_tools', 'TOOLS'), inventoryWeightBreakdown.equipment],
        [JrsI18n.t('inv_cat_other', 'OTHER'), inventoryWeightBreakdown.other]
    ];
    panel.innerHTML = rows.map(function(row) {
        return '<div><span>' + row[0] + '</span><b>' + formatInventoryNumber(row[1]) + ' ' + kg + '</b></div>';
    }).join("") + '<div class="weight-breakdown-total"><span>' + JrsI18n.t('inv_wb_total', 'TOTAL') + '</span><b>' + formatInventoryNumber(inventoryWeightBreakdown.total) + ' ' + kg + '</b></div>' +
        '<div><span>' + JrsI18n.t('inv_weapons', 'WEAPONS') + '</span><b>' + (inventoryWeightBreakdown.weapons || 0) + ' ' + JrsI18n.t('inv_wb_items_unit', 'ITEMS') + '</b></div>';
}

function playInventoryWeightAlert(frequency) {
    // Intentionally silent. JRS Inventory uses only the three bundled UI sounds
    // (open, close, click); no generated oscillator/beep is allowed.
    return;
}

function updateWeightWarning(weightPercent) {
    const bar = document.getElementById("inventoryWeightBar");
    const status = document.getElementById("inventory-status");
    let level = 0;
    if (weightPercent >= inventoryWeightCriticalPercent) level = 2;
    else if (weightPercent >= inventoryWeightWarningPercent) level = 1;

    if (bar) {
        bar.classList.toggle("weight-warning", level === 1);
        bar.classList.toggle("weight-critical", level === 2);
    }
    if (status) {
        status.classList.toggle("weight-warning", level === 1);
        status.classList.toggle("weight-critical", level === 2);
    }
    if (level > lastWeightAlertLevel) playInventoryWeightAlert(level === 2 ? 260 : 420);
    lastWeightAlertLevel = level;
}

function buildExpandedInfoHtml(slot) {
    if (!slot) return "";
    const type = slot.dataset.type;
    const index = Number(slot.dataset.index);

    if (type === "weapon") {
        const weapon = wtable_inv[index] || {};
        const condition = getWeaponConditionPercent(weapon);
        const dirt = clampInventoryPercent(weapon.dirtlevel, true);
        const weaponSerial = String(weapon.serial_number || weapon.serial || weapon.id || "-");
        // Set only for weapons delivered from a jrs_weapons package (jrs_weaponloadout.package_name).
        const packageName = String(weapon.package_name || "").trim();
        const packageRow = packageName ? '<div class="expanded-info-package-row"><span>' + JrsI18n.t("inv_package", "PACKAGE") + '</span><b>' + escapeDescriptionHtml(packageName) + '</b></div>' : '';
        const stolenRow = weapon.stolen ? '<div class="expanded-info-stolen-row"><span>' + JrsI18n.t("inventory_9888_reported_stolen", "&#9888; REPORTED STOLEN") + '</span></div>' : '';
        const statusText = Number(weapon.used) === 1
            ? JrsI18n.t("inv_equipped", "EQUIPPED")
            : JrsI18n.t("inv_unequipped", "UNEQUIPPED");
        return '<div class="expanded-info-title">' + escapeDescriptionHtml(weapon.label || weapon.name || "WEAPON") + '</div>' +
            stolenRow +
            '<div class="expanded-info-serial-row' + (weapon.stolen ? ' expanded-info-serial-stolen' : '') + '"><span>' + JrsI18n.t("inv_serial", "SERIAL") + '</span><button type="button" class="copy-weapon-serial jrs-ltr" data-serial="' + escapeDescriptionHtml(weaponSerial) + '" title="' + JrsI18n.t("inv_click_copy_serial", "Click to copy serial") + '">' + escapeDescriptionHtml(weaponSerial) + '</button></div>' +
            '<div class="expanded-info-copy-status" aria-live="polite"></div>' +
            packageRow +
            '<div><span>' + JrsI18n.t("inv_ammo", "AMMO") + '</span><b>' + getWeaponAmmoTotal(weapon) + '</b></div>' +
            '<div><span>' + JrsI18n.t("inv_condition", "CONDITION") + '</span><b>' + (condition === null ? "-" : formatInventoryNumber(condition) + "%") + '</b></div>' +
            '<div><span>' + JrsI18n.t("inv_dirt", "DIRT") + '</span><b>' + (dirt === null ? "-" : formatInventoryNumber(dirt) + "%") + '</b></div>' +
            '<div><span>' + JrsI18n.t("inv_status", "STATUS") + '</span><b>' + statusText + '</b></div>';
    }

    if (type === "item") {
        const item = table_inv[index] || {};
        const count = Number(item.count) || 0;
        const unitWeight = Number(item.limit) || 0;
        const durability = getItemDurabilityPercent(item);
        const rawCategory = (item.category || getPrimaryWeightCategory(item) || "other").toString().toLowerCase();
        const categoryLabel = JrsI18n.t("inv_cat_" + rawCategory, rawCategory.toUpperCase());
        const personalText = isPersonalItem(item.item)
            ? JrsI18n.t("inv_yes", "YES")
            : JrsI18n.t("inv_no", "NO");
        const isAr = (typeof JrsI18n !== 'undefined' && JrsI18n.language === 'ar');
        const displayLabel = getInventoryItemDisplayLabel(item);
        return '<div class="expanded-info-title">' + escapeDescriptionHtml(displayLabel) + '</div>' +
            '<div><span>' + JrsI18n.t("inv_count", "COUNT") + '</span><b>' + count + '</b></div>' +
            '<div><span>' + JrsI18n.t("inventory_unit_weight", "UNIT WEIGHT") + '</span><b>' + formatInventoryNumber(unitWeight) + ' ' + JrsI18n.t('inv_kg_unit', 'KG') + '</b></div>' +
            '<div><span>' + JrsI18n.t("inventory_total_weight", "TOTAL WEIGHT") + '</span><b>' + formatInventoryNumber(count * unitWeight) + ' ' + JrsI18n.t('inv_kg_unit', 'KG') + '</b></div>' +
            '<div><span>' + JrsI18n.t("inv_category", "CATEGORY") + '</span><b>' + categoryLabel + '</b></div>' +
            '<div><span>' + JrsI18n.t("inv_durability", "DURABILITY") + '</span><b>' + (durability === null ? "-" : formatInventoryNumber(durability) + "%") + '</b></div>' +
            '<div><span>' + JrsI18n.t("inv_personal", "PERSONAL") + '</span><b>' + personalText + '</b></div>';
    }

    return "";
}

function cancelExpandedInfoHide() {
    if (expandedInfoHideTimer) {
        clearTimeout(expandedInfoHideTimer);
        expandedInfoHideTimer = null;
    }
}

function hideExpandedInfoNow() {
    cancelExpandedInfoHide();
    const tooltip = document.getElementById("expanded-item-info");
    if (tooltip) {
        tooltip.style.display = "none";
        tooltip.classList.remove("jrs-tip-glide", "jrs-tip-in");
    }
    lastExpandedInfoSlot = null;
    jrsTipLastHtml = "";
}

function scheduleExpandedInfoHide() {
    cancelExpandedInfoHide();
    expandedInfoHideTimer = setTimeout(hideExpandedInfoNow, 120);
}

function showExpandedInfoForSlot(slot, mouseEvent) {
    // Floating details tooltip: a small box shown next to the hovered item.
    const tooltip = document.getElementById("expanded-item-info");
    if (!tooltip || !slot) { hideExpandedInfoNow(); return; }
    const html = buildExpandedInfoHtml(slot);
    if (!html) { hideExpandedInfoNow(); return; }
    cancelExpandedInfoHide();
    // Already open (moving slot to slot): glide to the new slot. Opening from
    // hidden: jump into place and fade in, so it never slides from a stale spot.
    const wasOpen = tooltip.style.display === "block" && lastExpandedInfoSlot !== null;
    // Same content as what is already shown (re-hover, click on the hovered
    // slot): skip the innerHTML rebuild and the size re-measure.
    if (html !== jrsTipLastHtml) {
        tooltip.innerHTML = html;
        jrsTipLastHtml = html;
        jrsTipSize = null;
    }
    if (wasOpen) {
        tooltip.classList.add("jrs-tip-glide");
    } else {
        invalidateContainerMetricsCache();
        getExpandedInfoHost(tooltip);
        tooltip.classList.remove("jrs-tip-glide", "jrs-tip-in");
        tooltip.style.display = "block";
        void tooltip.offsetWidth;
        tooltip.classList.add("jrs-tip-in");
    }
    lastExpandedInfoSlot = slot;
    positionExpandedInfo(slot, mouseEvent);
}

let jrsContainerRectCache = null;
let jrsContainerRectTime = 0;
// Last tooltip HTML and its measured size, so moving between slots does not
// rebuild the box or force a layout read when nothing in it changed.
var jrsTipLastHtml = "";
var jrsTipSize = null;
// Panels the details box must never cover (same list the window drag uses).
const JRS_TIP_BLOCKERS = ["container", "container_other", "clothing-side-panel", "ground-container", "currency-panel", "hotbar", "jrs-panel-dock"];

// The box used to live inside #container (overflow:hidden), so it could only
// sit on top of the slots. It now lives on the scaled layout canvas and docks
// outside the bag, in free space beside the panels.
function getExpandedInfoHost(tooltip) {
    const host = document.getElementById("standard-inventory-layout");
    if (host && tooltip && tooltip.parentElement !== host) host.appendChild(tooltip);
    return host || (tooltip && tooltip.parentElement);
}

function getCachedContainerMetrics(container) {
    const now = performance.now();
    if (!jrsContainerRectCache || (now - jrsContainerRectTime > 300)) {
        const host = getExpandedInfoHost(document.getElementById("expanded-item-info"));
        const hostRect = host.getBoundingClientRect();
        // The canvas is scaled to the screen: rects are screen px, the box is
        // placed in the canvas' own px.
        let scale = host.offsetWidth > 0 ? (hostRect.width / host.offsetWidth) : 1;
        if (!(scale > 0.05 && isFinite(scale))) scale = 1;
        const blockers = [];
        const hardBlockers = [];
        JRS_TIP_BLOCKERS.forEach(function(id) {
            const el = document.getElementById(id);
            if (!el || el.offsetParent === null || el.classList.contains("jrs-panel-hidden")) return;
            const r = el.getBoundingClientRect();
            if (r.width <= 0 || r.height <= 0) return;
            blockers.push(r);
            // Clothing/ground side panels may be covered when the screen has
            // no free space; the item grids, wallet and quick slots never.
            if (id !== "clothing-side-panel" && id !== "ground-container") hardBlockers.push(r);
        });
        jrsContainerRectCache = {
            rect: container.getBoundingClientRect(),
            hostRect: hostRect,
            scale: scale,
            blockers: blockers,
            hardBlockers: hardBlockers
        };
        jrsContainerRectTime = now;
    }
    return jrsContainerRectCache;
}

function invalidateContainerMetricsCache() {
    jrsContainerRectCache = null;
}

function positionExpandedInfo(slot, mouseEvent) {
    const tooltip = document.getElementById("expanded-item-info");
    const container = document.getElementById("container");
    if (!tooltip || tooltip.style.display === "none") return;

    slot = slot || lastExpandedInfoSlot;
    if (!slot || !container) return;

    const m = getCachedContainerMetrics(container);
    const scale = m.scale;
    const slotRect = slot.getBoundingClientRect();
    const cRect = m.rect;
    if (!jrsTipSize) jrsTipSize = { w: tooltip.offsetWidth || 245, h: tooltip.offsetHeight || 180 };
    // Everything below is in screen px.
    const w = jrsTipSize.w * scale;
    const h = jrsTipSize.h * scale;
    const gap = 10 * scale;
    const vw = window.innerWidth || 1920;
    const vh = window.innerHeight || 1080;

    function fits(x, y, list) {
        list = list || m.blockers;
        if (x < 4 || y < 4 || x + w > vw - 4 || y + h > vh - 4) return false;
        for (let i = 0; i < list.length; i++) {
            const r = list[i];
            if (x < r.right && x + w > r.left && y < r.bottom && y + h > r.top) return false;
        }
        return true;
    }

    // Row-aligned with the hovered slot, beside the bag or beside any panel
    // edge; the spot nearest to the slot wins.
    const rowY = Math.min(Math.max(4, slotRect.top), vh - h - 4);
    const xs = [cRect.right + gap, cRect.left - gap - w];
    m.blockers.forEach(function(r) { xs.push(r.right + gap, r.left - gap - w); });
    const slotMid = slotRect.left + slotRect.width / 2;
    let best = null;
    xs.forEach(function(x) {
        if (!fits(x, rowY)) return;
        const d = Math.abs(x + w / 2 - slotMid);
        if (!best || d < best.d) best = { x: x, y: rowY, d: d };
    });
    // No free column (storage: two bags side by side): under the bag, else
    // above it, lined up with the slot.
    if (!best) {
        const x = Math.min(Math.max(4, slotMid - w / 2), vw - w - 4);
        [cRect.bottom + gap, cRect.top - gap - h].forEach(function(y) {
            if (!best && fits(x, y)) best = { x: x, y: y };
        });
    }
    // Screen too narrow for free space: right beside the bag, over the
    // clothing/ground side panel rather than over the bag's own items.
    if (!best) {
        [cRect.right + gap, cRect.left - gap - w].forEach(function(x) {
            if (best || !fits(x, rowY, m.hardBlockers)) return;
            best = { x: x, y: rowY };
        });
    }
    // Nothing free on screen: old in-bag placement, never over the hovered
    // slot (beside it, else under/over it).
    if (!best) {
        let x = slotRect.right + gap;
        let y = slotRect.top;
        if (x + w > cRect.right - 8) x = slotRect.left - gap - w;
        if (x < cRect.left + 8) {
            x = Math.min(Math.max(cRect.left + 8, slotMid - w / 2), cRect.right - w - 8);
            y = slotRect.bottom + gap;
            if (y + h > cRect.bottom - 8) y = slotRect.top - gap - h;
        }
        y = Math.min(Math.max(cRect.top + 8, y), cRect.bottom - h - 8);
        best = { x: x, y: y };
    }

    // Moved with a GPU transform instead of left/top: the glide between slots
    // no longer relayouts and repaints the glow filter on every frame.
    const lx = Math.round((best.x - m.hostRect.left) / scale);
    const ly = Math.round((best.y - m.hostRect.top) / scale);
    if (tooltip.style.left !== "0px") { tooltip.style.left = "0px"; tooltip.style.top = "0px"; }
    tooltip.style.transform = "translate3d(" + lx + "px," + ly + "px,0)";
}

function getInventoryItemDisplayLabel(entry) {
    const isAr = (typeof JrsI18n !== 'undefined' && JrsI18n.language === 'ar');
    const base = (isAr && entry.label_ar) ? entry.label_ar : (entry.label || entry.item || 'Item');
    const meta = entry.metaData;
    if (!meta || !meta.housing_key || !meta.property_id) return base;
    // Older keys already carry the house name in their metadata label.
    const legacyName = typeof meta.label === 'string' && meta.label.startsWith('House Key - ')
        ? meta.label.slice('House Key - '.length) : '';
    const house = String(meta.property_name || legacyName || meta.property_id);
    return (isAr ? 'مفتاح المنزل' : 'House Key') + ' - ' + house;
}

function getInventorySortEntryLabel(entry) {

    if (entry.kind === "weapon") {
        return normalizeInventoryText(entry.data.label || entry.data.name);
    }
    return normalizeInventoryText(getInventoryItemDisplayLabel(entry.data));
}

function getInventorySortEntryCategory(entry) {
    if (entry.kind === "weapon") return "00_weapons";
    const tags = buildInventoryFilterTags(entry.data, "item");
    if (tags.includes("ammo")) return "05_ammo";
    if (tags.includes("food")) return "10_food";
    if (tags.includes("drink")) return "20_drink";
    if (tags.includes("seeds")) return "30_seeds";
    if (tags.includes("equipment")) return "40_equipment";
    return "90_misc";
}

function getInventorySortEntryWeight(entry) {
    if (entry.kind === "weapon") return 0;
    return (Number(entry.data.limit) || 0) * (Number(entry.data.count) || 0);
}

function getInventorySortEntryCount(entry) {
    if (entry.kind === "weapon") return 1;
    return Number(entry.data.count) || 0;
}

function compareInventorySortEntries(a, b, mode) {
    if (mode === "type") {
        const categoryCompare = getInventorySortEntryCategory(a).localeCompare(getInventorySortEntryCategory(b));
        if (categoryCompare !== 0) return categoryCompare;
        return getInventorySortEntryLabel(a).localeCompare(getInventorySortEntryLabel(b));
    }

    if (mode === "weight") {
        const difference = getInventorySortEntryWeight(b) - getInventorySortEntryWeight(a);
        if (difference !== 0) return difference;
        return getInventorySortEntryLabel(a).localeCompare(getInventorySortEntryLabel(b));
    }

    if (mode === "count") {
        const difference = getInventorySortEntryCount(b) - getInventorySortEntryCount(a);
        if (difference !== 0) return difference;
        return getInventorySortEntryLabel(a).localeCompare(getInventorySortEntryLabel(b));
    }

    if (mode === "weapons") {
        if (a.kind !== b.kind) return a.kind === "weapon" ? -1 : 1;
        return getInventorySortEntryLabel(a).localeCompare(getInventorySortEntryLabel(b));
    }

    return getInventorySortEntryLabel(a).localeCompare(getInventorySortEntryLabel(b));
}

function getInventoryEntryKey(kind, data) {
    if (kind === "weapon") return "weapon:" + String(data.id);
    return "item:" + String(data.itemId);
}

function loadInventoryPins() {
    try {
        const saved = window.localStorage.getItem("jrs_inventory_pinned_entries");
        inventoryPinnedEntries = saved ? JSON.parse(saved) : {};
    } catch (error) {
        inventoryPinnedEntries = {};
    }
}

function saveInventoryPins() {
    try {
        window.localStorage.setItem("jrs_inventory_pinned_entries", JSON.stringify(inventoryPinnedEntries));
    } catch (error) {
        jrsDevLog("Unable to save inventory pins", error);
    }
}

function isInventoryEntryPinned(kind, data) {
    return inventoryPinnedEntries[getInventoryEntryKey(kind, data)] === true;
}

function captureManualInventorySlots() {
    manualItemSlots = {};
    manualWeaponSlots = {};

    table_inv.forEach(function(item) {
        manualItemSlots[String(item.itemId)] = Number(item.slot) || 0;
    });

    wtable_inv.forEach(function(weapon) {
        manualWeaponSlots[String(weapon.id)] = Number(weapon.slot) || 0;
    });
}

function restoreManualInventorySlotsLocal() {
    table_inv.forEach(function(item) {
        const savedSlot = manualItemSlots[String(item.itemId)];
        if (savedSlot !== undefined) item.slot = Number(savedSlot);
    });

    wtable_inv.forEach(function(weapon) {
        const savedSlot = manualWeaponSlots[String(weapon.id)];
        if (savedSlot !== undefined) weapon.slot = Number(savedSlot);
    });
}

function getManualSlotForEntry(entry) {
    if (entry.kind === "weapon") {
        return Number(manualWeaponSlots[String(entry.data.id)]) || Number(entry.data.slot) || 0;
    }
    return Number(manualItemSlots[String(entry.data.itemId)]) || Number(entry.data.slot) || 0;
}

function updateSortControlState(message) {
    const manualButton = document.getElementById("inventoryManualButton");
    const saveButton = document.getElementById("inventorySaveSortButton");
    const hint = document.getElementById("quickTransferHint");

    if (manualButton) manualButton.classList.toggle("active", activeTemporarySortMode === null);
    if (saveButton) {
        saveButton.classList.toggle("active", activeTemporarySortMode !== null);
        saveButton.disabled = activeTemporarySortMode === null;
    }

    if (hint) {
        hint.textContent = message || (activeTemporarySortMode ? JrsI18n.t("inv_temp_view_hint", "TEMP VIEW — SAVE OR MANUAL") : JrsI18n.t("inv_quick_transfer_hint", "SHIFT: ALL   CTRL: 1"));
    }
}

function applyTemporaryInventorySort(mode) {
    if (!mode) return;

    if (Object.keys(manualItemSlots).length === 0 && Object.keys(manualWeaponSlots).length === 0) {
        captureManualInventorySlots();
    } else {
        restoreManualInventorySlotsLocal();
    }

    const combined = [];
    table_inv.forEach(function(item) {
        combined.push({ kind: "item", data: item });
    });
    wtable_inv.forEach(function(weapon) {
        combined.push({ kind: "weapon", data: weapon });
    });

    const pinned = combined.filter(function(entry) {
        return isInventoryEntryPinned(entry.kind, entry.data);
    });
    const movable = combined.filter(function(entry) {
        return !isInventoryEntryPinned(entry.kind, entry.data);
    });

    movable.sort(function(a, b) {
        return compareInventorySortEntries(a, b, mode);
    });

    const occupiedSlots = {};
    pinned.forEach(function(entry) {
        const fixedSlot = getManualSlotForEntry(entry);
        if (fixedSlot > 0) {
            entry.data.slot = fixedSlot;
            occupiedSlots[fixedSlot] = true;
        }
    });

    let nextSlot = 1;
    movable.forEach(function(entry) {
        while (occupiedSlots[nextSlot]) nextSlot++;
        entry.data.slot = nextSlot;
        occupiedSlots[nextSlot] = true;
        nextSlot++;
    });

    activeTemporarySortMode = mode;
    isRenderingTemporarySort = true;
    loadTableData(table_inv, moneysd, wtable_inv, goldsd, dirtymoneysd);
    isRenderingTemporarySort = false;
    updateSortControlState(JrsI18n.t("inv_sort_prefix", "SORT:") + " " + ((inventorySortOptions.find(function(o) { return o.key === mode; }) || { label: String(mode).toUpperCase() }).label) + " — " + JrsI18n.t("inv_save_or_manual", "SAVE OR MANUAL"));
}

function setInventoryTradeButtonVisible(enabled) {
    const button = document.getElementById("inventoryTradeButton");
    if (!button) return;
    const visible = enabled === true;
    button.style.display = visible ? "" : "none";
    button.disabled = !visible;
    // Row 2 of the action bar: MULTI fills the whole row when TRADE is hidden.
    const bar = document.getElementById("inventory-action-bar");
    if (bar) bar.classList.toggle("jrs-no-trade", !visible);
}

function openTradeSystem() {
    if (!document.body || !document.body.classList.contains("inventory-layout-standard")) return;
    if (document.body.classList.contains("inventory-storage-open")) return;

    givePlayerSelectorPurpose = "trade";
    const button = document.getElementById("inventoryTradeButton");
    if (button) button.disabled = true;

    $.post(jrsInventoryUrl + "/open_trade", JSON.stringify({}), function() {
        if (button) button.disabled = false;
    }).fail(function() {
        if (button) button.disabled = false;
    });
}

function cycleInventorySort() {
    const option = inventorySortOptions[currentInventorySortIndex] || inventorySortOptions[0];
    applyTemporaryInventorySort(option.key);

    const label = document.getElementById("inventorySortLabel");
    if (label) label.textContent = JrsI18n.t("inv_sort_prefix", "SORT:") + " " + option.label;

    currentInventorySortIndex = (currentInventorySortIndex + 1) % inventorySortOptions.length;
    const nextOption = inventorySortOptions[currentInventorySortIndex];
    const button = document.getElementById("inventorySortButton");
    if (button) button.title = JrsI18n.t("inventory_next_temporary_sort", "Next temporary sort:") + " " + nextOption.label;
}

function showManualInventoryLayout() {
    // When we are NOT in a temporary sort view, table_inv/wtable_inv already
    // hold the real persisted arrangement, so snapshot THAT as the manual truth
    // (fixes MANUAL restoring a stale snapshot after drags / relogs). Only fall
    // back to capturing-when-empty while a temp sort is active.
    if (activeTemporarySortMode === null
        || (Object.keys(manualItemSlots).length === 0 && Object.keys(manualWeaponSlots).length === 0)) {
        captureManualInventorySlots();
    }

    restoreManualInventorySlotsLocal();
    activeTemporarySortMode = null;
    isRenderingTemporarySort = true;
    loadTableData(table_inv, moneysd, wtable_inv, goldsd, dirtymoneysd);
    isRenderingTemporarySort = false;

    const label = document.getElementById("inventorySortLabel");
    const nextOption = inventorySortOptions[currentInventorySortIndex] || inventorySortOptions[0];
    if (label) label.textContent = JrsI18n.t("inv_sort_prefix", "SORT:") + " " + nextOption.label;
    updateSortControlState(JrsI18n.t("inv_manual_restored", "MANUAL SLOTS RESTORED"));
}

let inventorySlotSaveTimer = 0;
// The server only reads itemId/id + slot from a layout save. Posting the full
// records (labels, descriptions, deed metadata) was ~55KB per save and close
// to the server's 64KB layout cap, past which the save is rejected.
function jrsSlotLayoutPayload() {
    const items = [];
    const weapons = [];
    for (const it of (table_inv || [])) {
        if (it && it.itemId != null && it.slot != null) items.push({ itemId: it.itemId, slot: it.slot });
    }
    for (const w of (wtable_inv || [])) {
        if (w && w.id != null && w.slot != null) weapons.push({ id: w.id, slot: w.slot });
    }
    return { items: items, weapons: weapons };
}
function postInventorySlotsNow() {
    if (inventorySlotSaveTimer) {
        clearTimeout(inventorySlotSaveTimer);
        inventorySlotSaveTimer = 0;
    }
    $.post(jrsInventoryUrl + "/saveSlots", JSON.stringify(jrsSlotLayoutPayload()));
}

function queueInventorySlotSave() {
    if (inventorySlotSaveTimer) clearTimeout(inventorySlotSaveTimer);
    inventorySlotSaveTimer = setTimeout(function() {
        inventorySlotSaveTimer = 0;
        $.post(jrsInventoryUrl + "/saveSlots", JSON.stringify(jrsSlotLayoutPayload()));
    }, 300);
}

function flushPendingInventorySlotSave() {
    if (!inventorySlotSaveTimer) return;
    clearTimeout(inventorySlotSaveTimer);
    inventorySlotSaveTimer = 0;
    $.post(jrsInventoryUrl + "/saveSlots", JSON.stringify(jrsSlotLayoutPayload()));
}

function saveTemporaryInventorySort() {
    if (!activeTemporarySortMode) return;

    postInventorySlotsNow();

    captureManualInventorySlots();
    activeTemporarySortMode = null;

    const label = document.getElementById("inventorySortLabel");
    const nextOption = inventorySortOptions[currentInventorySortIndex] || inventorySortOptions[0];
    if (label) label.textContent = JrsI18n.t("inv_sort_prefix", "SORT:") + " " + nextOption.label;
    updateSortControlState(JrsI18n.t("inv_layout_saved", "LAYOUT SAVED"));
}

function updateContextPinButton() {
    const pinButton = document.getElementById("contextPinButton");
    if (!pinButton) return;

    if (clicked_type !== "item" && clicked_type !== "weapon") {
        pinButton.style.display = "none";
        return;
    }

    let pinned = false;
    if (clicked_type === "weapon") {
        const index = wtable_inv.findIndex(function(weapon) { return String(weapon.id) === String(clicked_id); });
        if (index >= 0) pinned = isInventoryEntryPinned("weapon", wtable_inv[index]);
    } else {
        const index = table_inv.findIndex(function(item) { return String(item.itemId) === String(clicked_id); });
        if (index >= 0) pinned = isInventoryEntryPinned("item", table_inv[index]);
    }

    pinButton.style.display = "block";
    const pinText = (typeof JrsI18n !== "undefined" && typeof JrsI18n.t === "function")
        ? JrsI18n.t(pinned ? "inv_unpin" : "inv_pin", pinned ? "إلغاء التثبيت" : "تثبيت")
        : (pinned ? "إلغاء التثبيت" : "تثبيت");
    pinButton.innerHTML = "<center>" + pinText + "</center>";
}

function getSelectedWeaponForContext() {
    if (clicked_type !== "weapon") return null;
    return wtable_inv.find(function(entry) {
        return String(entry.id) === String(clicked_id);
    }) || null;
}

function updateContextSerialButton() {
    const copyButton = document.getElementById("contextCopySerialButton");
    if (!copyButton) return;

    const weapon = getSelectedWeaponForContext();
    const serial = weapon ? String(weapon.serial_number || weapon.serial || "").trim() : "";

    if (!weapon || !serial || serial === "-") {
        copyButton.style.display = "none";
        copyButton.dataset.serial = "";
        return;
    }

    copyButton.style.display = "block";
    copyButton.dataset.serial = serial;
    copyButton.title = serial;
    copyButton.innerHTML = "<center>" + JrsI18n.t("inv_copy_serial", "Copy Serial") + "</center>";
}

function copySelectedWeaponSerial(event) {
    if (event) {
        event.preventDefault();
        event.stopPropagation();
    }

    const copyButton = document.getElementById("contextCopySerialButton");
    const weapon = getSelectedWeaponForContext();
    const serial = String(
        (copyButton && copyButton.dataset.serial) ||
        (weapon && (weapon.serial_number || weapon.serial)) ||
        ""
    ).trim();

    if (!serial || serial === "-") {
        if (copyButton) copyButton.innerHTML = "<center>" + JrsI18n.t("inventory_serial_unavailable", "Serial Unavailable") + "</center>";
        setTimeout(function() {
            contextMenu.classList.remove("visible");
            if (copyButton) copyButton.innerHTML = "<center>" + JrsI18n.t("inv_copy_serial", "Copy Serial") + "</center>";
        }, 500);
        return;
    }

    copyTextToClipboard(serial).then(function() {
        if (copyButton) copyButton.innerHTML = "<center>" + JrsI18n.t("inventory_serial_copied", "Serial Copied") + "</center>";
        playJrsUiSound("click");
        setTimeout(function() {
            contextMenu.classList.remove("visible");
            if (copyButton) copyButton.innerHTML = "<center>" + JrsI18n.t("inv_copy_serial", "Copy Serial") + "</center>";
        }, 450);
    }).catch(function() {
        if (copyButton) copyButton.innerHTML = "<center>" + JrsI18n.t("inventory_copy_failed", "Copy Failed") + "</center>";
        setTimeout(function() {
            contextMenu.classList.remove("visible");
            if (copyButton) copyButton.innerHTML = "<center>" + JrsI18n.t("inv_copy_serial", "Copy Serial") + "</center>";
        }, 650);
    });
}

function toggleSelectedInventoryPin() {
    if (clicked_type !== "item" && clicked_type !== "weapon") return;

    let key = null;
    if (clicked_type === "weapon") {
        const weapon = wtable_inv.find(function(entry) { return String(entry.id) === String(clicked_id); });
        if (weapon) key = getInventoryEntryKey("weapon", weapon);
    } else {
        const item = table_inv.find(function(entry) { return String(entry.itemId) === String(clicked_id); });
        if (item) key = getInventoryEntryKey("item", item);
    }

    if (!key) return;
    inventoryPinnedEntries[key] = inventoryPinnedEntries[key] !== true;
    if (inventoryPinnedEntries[key] !== true) delete inventoryPinnedEntries[key];
    saveInventoryPins();
    contextMenu.classList.remove("visible");

    if (activeTemporarySortMode) {
        applyTemporaryInventorySort(activeTemporarySortMode);
    } else {
        skipSortReapplyOnce = true;
        loadTableData(table_inv, moneysd, wtable_inv, goldsd, dirtymoneysd);
    }
}

function findInventoryItemIndexByItemId(itemId) {
    const numericId = Number(itemId);
    for (let i = 0; i < table_inv.length; i++) {
        if (Number(table_inv[i].itemId) === numericId) return i;
    }
    return -1;
}

function updateContextSplitButton() {
    const splitButton = document.getElementById("contextSplitButton");
    if (!splitButton) return;

    const itemIndex = findInventoryItemIndexByItemId(clicked_id);
    const item = itemIndex >= 0 ? table_inv[itemIndex] : null;
    const canSplit = clicked_type === "item" && item && Number(item.count) > 1;
    splitButton.style.display = canSplit ? "block" : "none";
}

function openSplitStack() {
    contextMenu.classList.remove("visible");

    const itemIndex = findInventoryItemIndexByItemId(clicked_id);
    if (itemIndex < 0) return;

    const item = table_inv[itemIndex];
    const itemCount = Number(item.count) || 0;
    if (itemCount <= 1) return;

    splitStackItemId = Number(item.itemId);

    const input = document.getElementById("split-stack-count");
    const name = document.getElementById("split-stack-item-name");
    if (input) {
        input.min = "1";
        input.max = String(itemCount - 1);
        input.value = String(Math.max(1, Math.floor(itemCount / 2)));
    }
    if (name) {
        const isAr = (typeof JrsI18n !== 'undefined' && JrsI18n.language === 'ar');
        name.textContent = getInventoryItemDisplayLabel(item);
    }

    $("#split-stack-window").show();
    if (input) input.focus();
}

function closeSplitStack() {
    splitStackItemId = null;
    $("#split-stack-window").hide();
}

function confirmSplitStack() {
    if (!splitStackItemId) return;

    const input = document.getElementById("split-stack-count");
    const count = input ? Number(input.value) : 0;
    if (!Number.isInteger(count) || count <= 0) return;

    $.post(jrsInventoryUrl + "/split_stack", JSON.stringify({
        itemId: splitStackItemId,
        count: count
    }));

    closeSplitStack();
}

function quickTransferCooldownActive() {
    return Date.now() < quickTransferBusyUntil;
}

function beginQuickTransferCooldown() {
    quickTransferBusyUntil = Date.now() + 120;
}

function quickTransferInventorySlot(slotElement, oneOnly) {
    if (id_container === 0 || quickTransferCooldownActive()) return;
    if (slotElement.classList && slotElement.classList.contains("inventory-pinned")) {
        jrsFlashPinnedLock(slotElement);
        return;
    }

    const type = slotElement.dataset.type;
    const index = Number(slotElement.dataset.index);
    let payload = null;

    if (type === "money") {
        payload = { item: "money", weapon: false, count: oneOnly ? 1 : moneysd, currentSize: count_sinventory, limit: 0.2 };
    } else if (type === "gold") {
        payload = { item: "gold", weapon: false, count: oneOnly ? 1 : goldsd, currentSize: count_sinventory, limit: 0.2 };
    } else if (type === "dirtymoney") {
        payload = { item: "dirtymoney", weapon: false, count: oneOnly ? 1 : dirtymoneysd, currentSize: count_sinventory, limit: 0.2 };
    } else if (type === "weapon") {
        const weapon = wtable_inv[index];
        if (!weapon) return;
        payload = { weapon: true, id: weapon.id, item: weapon.name, used: weapon.used || 0, count: 1, currentSize: count_sinventory, limit: 1 };
    } else {
        const item = table_inv[index];
        if (!item) return;
        payload = {
            weapon: false,
            itemId: item.itemId,
            item: item.item,
            count: oneOnly ? 1 : Number(item.count),
            countInInventory: Number(item.count),
            currentSize: count_sinventory,
            limit: Number(item.limit) || 0,
            metaData: item.metaData || {}
        };
    }

    beginQuickTransferCooldown();
    $.post(jrsInventoryUrl + "/quick_transfer_to_storage", JSON.stringify(payload));
}

function quickTransferStorageSlot(slotElement, oneOnly) {
    if (id_container === 0 || quickTransferCooldownActive()) return;

    const index = Number(slotElement.dataset.storageIndex);
    const storageItem = storage_inv[index];
    if (!storageItem) return;

    const payload = {
        weapon: storageItem.weapon === true,
        item: storageItem.item,
        itemId: storageItem.itemId,
        metaData: storageItem.metaData || {},
        used: storageItem.used || 0,
        count: storageItem.weapon === true ? 1 : (oneOnly ? 1 : Number(storageItem.count)),
        countInInventory: Number(storageItem.count) || 1,
        limit: Number(storageItem.limit) || (storageItem.weapon === true ? 1 : 0)
    };

    beginQuickTransferCooldown();
    $.post(jrsInventoryUrl + "/quick_transfer_from_storage", JSON.stringify(payload));
}

function normalizeInventoryText(value) {
    return String(value || "").toLowerCase();
}

function buildInventoryFilterTags(entry, entryType) {
    if (entryType === "weapon") {
        return "weapons equipment";
    }

    const text = [entry.item, entry.label, entry.description, entry.category].map(normalizeInventoryText).join(" ");
    const tags = [];

    if (/\b(food|eat|edible|meal|meat|fish|apple|bread|berry|berries|fruit|egg|corn|carrot|potato|stew|ration|cheese)\b/.test(text)) {
        tags.push("food");
    }

    if (/\b(drink|water|coffee|tea|milk|whiskey|whisky|beer|wine|liquor|juice|tonic)\b/.test(text)) {
        tags.push("drink");
    }

    if (/\b(seed|seeds|sapling|fertilizer|fertiliser)\b/.test(text)) {
        tags.push("seeds");
    }

    if (/\b(ammo|ammunition|bullet|bullets|cartridge|cartridges|shell|shells|round|rounds|arrow|arrows|gunpowder)\b/.test(text)) {
        tags.push("ammo");
    }

    if (/\b(tool|equipment|equip|craft|kit|axe|hatchet|hammer|pickaxe|pick|knife|rope|lasso|shovel|lantern|fishing|rod|bait|bucket|brush|repair|lockpick)\b/.test(text)) {
        tags.push("equipment");
    }

    const category = normalizeInventoryText(entry.category);
    if (category) {
        tags.push(category.replace(/\s+/g, "_"));
    }

    if (tags.length === 0) {
        tags.push("misc");
    }

    return Array.from(new Set(tags)).join(" ");
}


function getInventorySlotSearchText(slotElement) {
    if (!slotElement) return "";

    const slotType = slotElement.dataset.type;
    const slotIndex = Number(slotElement.dataset.index);

    if (slotType === "money") {
        return "money cash dollar dollars currency";
    }

    if (slotType === "gold") {
        return "gold currency";
    }

    if (slotType === "dirtymoney") {
        return "dirty money illegal cash black money currency";
    }

    if (slotType === "weapon") {
        const weapon = wtable_inv[slotIndex] || {};
        return [weapon.name, weapon.label, weapon.description, weapon.serial_number, weapon.serial]
            .map(normalizeInventoryText)
            .join(" ");
    }

    const item = table_inv[slotIndex] || {};
    return [item.item, item.label, item.description, item.category]
        .map(normalizeInventoryText)
        .join(" ");
}

function itemMatchesInventorySearch(slotElement) {
    if (currentInventorySearch === "") return true;
    return getInventorySlotSearchText(slotElement).includes(currentInventorySearch);
}

let inventorySearchDebounceTimer = 0;
function searchInventoryItems(value) {
    currentInventorySearch = normalizeInventoryText(value).trim();
    if (inventorySearchDebounceTimer) clearTimeout(inventorySearchDebounceTimer);
    inventorySearchDebounceTimer = setTimeout(function() {
        inventorySearchDebounceTimer = 0;
        applyInventoryFilter();
    }, 60);
}

function resetInventorySearchAndFilter() {
    currentInventoryFilter = "all";
    currentInventoryFilterIndex = 0;
    currentInventorySearch = "";

    const searchInput = document.getElementById("inventorySearch");
    if (searchInput) searchInput.value = "";

    updateInventoryFilterButtons();
}


function showAllInventoryView() {
    currentInventorySearch = "";
    currentInventoryFilter = "all";
    currentInventoryFilterIndex = 0;
    const search = document.getElementById("inventorySearch");
    if (search) search.value = "";
    applyInventoryFilter();
    updateInventoryFilterButtons();
}

function updateInventoryFilterButtons() {
    const option = inventoryFilterOptions[currentInventoryFilterIndex] || inventoryFilterOptions[0];
    const icon = document.getElementById("inventoryFilterIcon");
    const label = document.getElementById("inventoryFilterLabel");
    const current = document.getElementById("inventory-filter-current");

    if (icon) {
        icon.src = option.activeIcon || option.icon;
        icon.alt = option.title;
    }

    if (label) {
        label.textContent = option.label;
    }

    if (current) {
        current.title = option.title;
        current.dataset.filter = option.key;
    }
}

function changeInventoryFilter(direction) {
    const total = inventoryFilterOptions.length;
    currentInventoryFilterIndex = (currentInventoryFilterIndex + direction + total) % total;
    currentInventoryFilter = inventoryFilterOptions[currentInventoryFilterIndex].key;
    applyInventoryFilter();
    jrsPlayFilterSwap(direction);
}

// Soft swap when flipping filters with the arrows: the grid fades up and the
// label slides in from the side you clicked. Opacity/transform only.
function jrsPlayFilterSwap(direction) {
    const grid = document.getElementById("tableData");
    const label = document.getElementById("inventoryFilterLabel");
    if (grid) {
        grid.classList.remove("jrs-grid-swap");
        void grid.offsetWidth;
        grid.classList.add("jrs-grid-swap");
    }
    if (label) {
        label.classList.remove("jrs-label-next", "jrs-label-prev");
        void label.offsetWidth;
        label.classList.add(direction < 0 ? "jrs-label-prev" : "jrs-label-next");
    }
}

function itemMatchesInventoryFilter(slotElement) {
    if (!slotElement) return false;
    if (currentInventoryFilter === "all") return true;

    if (isCurrencyType(slotElement.dataset.type)) {
        return false;
    }

    if (currentInventoryFilter === "weapons") {
        return slotElement.dataset.type === "weapon";
    }
    if (currentInventoryFilter === "damaged") {
        return slotElement.dataset.damaged === "true";
    }
    if (currentInventoryFilter === "personal") {
        return slotElement.dataset.personal === "true";
    }

    const tags = normalizeInventoryText(slotElement.dataset.filterTags);
    return tags.split(/\s+/).includes(currentInventoryFilter);
}

function applyInventoryFilter() {
    const inventoryGrid = document.getElementById("tableData");
    if (!inventoryGrid) return;

    const hasActiveFilter = currentInventoryFilter !== "all" || currentInventorySearch !== "";
    const slots = inventoryGrid.querySelectorAll(".item, .empty-slot");

    slots.forEach(function(slot) {
        if (slot.classList.contains("empty-slot")) {
            slot.style.display = hasActiveFilter ? "none" : "";
            return;
        }

        const categoryMatches = itemMatchesInventoryFilter(slot);
        const searchMatches = itemMatchesInventorySearch(slot);
        slot.style.display = categoryMatches && searchMatches ? "" : "none";
    });

    updateInventoryFilterButtons();
}

function setInventoryFilter(filterKey) {
    const index = inventoryFilterOptions.findIndex(function(option) {
        return option.key === filterKey;
    });

    currentInventoryFilterIndex = index >= 0 ? index : 0;
    currentInventoryFilter = inventoryFilterOptions[currentInventoryFilterIndex].key;
    applyInventoryFilter();
}

function filterAllItem() { setInventoryFilter("all"); }
function filterAllValuable() { setInventoryFilter("weapons"); }
function filterAllAmmo() { setInventoryFilter("ammo"); }
function filterAllEat() { setInventoryFilter("food"); }
function filterAllDrink() { setInventoryFilter("drink"); }
function filterAllHerb() { setInventoryFilter("seeds"); }
function filterAllCraft() { setInventoryFilter("equipment"); }
function filterDamaged() { setInventoryFilter("damaged"); }
function filterPersonal() { setInventoryFilter("personal"); }
function filterAllHorse() { setInventoryFilter("all"); }
function filterAllBuild() { setInventoryFilter("all"); }
function filterAllTrash() { setInventoryFilter("all"); }

function setPersonalItems(items) {
    personalItems = {};
    (items || []).forEach(function (name) {
        personalItems[String(name).toLowerCase()] = true;
    });
}

function isPersonalItem(name) {
    return name != null && personalItems[String(name).toLowerCase()] === true;
}

function selectedPersonalItemName() {
    if (dragged_item_inv !== undefined && table_inv[dragged_item_inv]) return table_inv[dragged_item_inv].item;
    if (dragged_witem_inv !== undefined && wtable_inv[dragged_witem_inv]) return wtable_inv[dragged_witem_inv].name;
    return clicked_name;
}

$(document).keydown(function(e) {
    var close = 27,close2 = 66, presse=69, pressenter=13;
    var giveWinOpen = document.getElementById("give-player-window");
    giveWinOpen = !!(giveWinOpen && giveWinOpen.style.display !== "none");
    if (e.keyCode === close && giveWinOpen) {
        e.preventDefault();
        e.stopPropagation();
        closeGivePlayerWindow();
        return;
    }
    // The amount box is open: Enter moves on to picking the player, and the
    // bag's own keys (B closes, E uses) must not fire while typing.
    if (giveWinOpen) {
        if (e.keyCode === pressenter) {
            e.preventDefault();
            confirmGiveAmountAndPickPlayer();
        }
        return;
    }
    if (e.keyCode === close && givePlayerSelectorActive) {
        e.preventDefault();
        e.stopPropagation();
        givePlayerSelectorActive = false;
        giveItemEnabled = false;
        giveTransferPending = false;
        pendingGiveRequest = null;
        pendingMultiGiveEntries = null;
        clearGivePlayerSelectors();
        $.post(jrsInventoryUrl + '/give_selector_cancel', JSON.stringify({}));
        return;
    }
    switch (e.keyCode) {
        case close:
            closeGivePlayerWindow();
            blockMe = false
            isInContext = false
            flushPendingInventorySlotSave();
            $.post(jrsInventoryUrl + '/exit', JSON.stringify({id:id_container}));
            contextMenu.classList.remove("visible");
            removeAllChildNodes(table_for_delete);
            setTimeout(() => {  
                changed= false
                id_container = 0
                usableScroll = 0
                allCount = 0
                document.getElementById("input_type").value = "";
                $("#input_data").hide();
                inInput = false
            }, 100);
            $.post(jrsInventoryUrl + '/transferLeaveItem', JSON.stringify({}));
            if (giveItemEnabled == true) {
                $.post(jrsInventoryUrl + '/exit2', JSON.stringify({}));
                giveItemEnabled = false
            }
        break;
        case close2:
            blockMe = false
            isInContext = false
            if (id_container == 0) {
                flushPendingInventorySlotSave();
                $.post(jrsInventoryUrl + '/exit', JSON.stringify({id:id_container}));
                contextMenu.classList.remove("visible");
                removeAllChildNodes(table_for_delete);
                setTimeout(() => {  
                    changed= false
                    id_container = 0
                    usableScroll = 0
                    allCount = 0
                    document.getElementById("input_type").value = "";
                    $("#input_data").hide();
                    inInput = false
                }, 100);
            }
            if (giveItemEnabled == true) {
                $.post(jrsInventoryUrl + '/exit2', JSON.stringify({}));
                giveItemEnabled = false
            }
            $.post(jrsInventoryUrl + '/transferLeaveItem', JSON.stringify({}));
        break;
        case pressenter:
            if (inInput) {
                // Storage: the server answer (cleanTransfer) unlocks, not the
                // Enter key; unlocking here let the next drop race into 'busy'.
                if (!id_container) blockMe = false
                $.post(jrsInventoryUrl + '/transferAcceptItem', JSON.stringify({count:document.getElementById("input_type").value}));
                allCount = 0
                document.getElementById("input_type").value = "";
                $("#input_data").hide();
                inInput = false
            }
        break
        case presse:
            if (id_container == 0) {
                if (Number(id_for_use_item) !== -1) {
                    const entry = table_inv && table_inv[id_for_use_item];
                    if (entry) {
                        var myDiv = document.getElementById('tableData');
                        if (myDiv) usableScroll = myDiv.scrollTop;
                        $.post(jrsInventoryUrl + '/use_item', JSON.stringify({ item: entry.item, id: entry.itemId }));
                    }
                }
                if (Number(id_for_use_weapon) !== -1) {
                    var myDiv = document.getElementById('tableData');
                    usableScroll = myDiv.scrollTop
                    $.post(jrsInventoryUrl + '/use_UseWeapon', JSON.stringify({ id: wtable_inv[id_for_use_weapon].id, model:wtable_inv[id_for_use_weapon].name }));
                }
            }
        break;
    }
});

$(document).mousedown(function(e) {
    var close2 = 2;
    switch (e.keyCode) {
        case close2:
            flushPendingInventorySlotSave();
            $.post(jrsInventoryUrl + '/exit')
            break;
    }
});

function syncCurrencyPanelPosition() {
    const panel = document.getElementById("currency-panel");
    if (!panel || panel.style.display === "none") return;

    // The responsive layout engine positions the currency panel through CSS
    // variables. Clear legacy inline geometry so it cannot fight the current
    // screen-size calculation after storage/inventory mode changes.
    panel.style.removeProperty("left");
    panel.style.removeProperty("right");
    panel.style.removeProperty("top");
    panel.style.removeProperty("bottom");
    panel.style.removeProperty("width");
}

function showCurrencyPanel() {
    const panel = document.getElementById("currency-panel");
    if (!panel) return;
    panel.style.display = "flex";
    requestAnimationFrame(function() {
        syncCurrencyPanelPosition();
        makeCurrencyDraggable();
    });
}

function hideCurrencyPanel() {
    const panel = document.getElementById("currency-panel");
    if (panel) panel.style.display = "none";
}

// The standard layout is a fixed 1448x1086 design canvas (index.css, "EXACT
// REFERENCE LAYOUT"): every panel inside it - including the quick-slot row at
// canvas y 865..967 - is positioned in canvas pixels and the whole thing is
// scaled by --jrs-exact-scale. That variable was declared as the constant 1 and
// never computed, so on any screen shorter than 1086px the quick slots hung off
// the bottom edge and could not be dropped onto. Compute it for real.
const JRS_DESIGN_CANVAS_WIDTH = 1448;
const JRS_DESIGN_CANVAS_HEIGHT = 1086;

function applyJrsExactCanvasScale() {
    const root = document.documentElement;
    if (!root) return;

    const width = Math.max(320, Number(window.innerWidth) || JRS_DESIGN_CANVAS_WIDTH);
    const height = Math.max(360, Number(window.innerHeight) || JRS_DESIGN_CANVAS_HEIGHT);

    // Scale comfortably across all resolutions (720p, 1080p, 1440p, 4K UHD)
    const scale = Math.min(
        2.4,
        (width - 16) / JRS_DESIGN_CANVAS_WIDTH,
        (height - 16) / JRS_DESIGN_CANVAS_HEIGHT
    );

    root.style.setProperty("--jrs-exact-scale", String(Math.max(0.4, Math.round(scale * 1000) / 1000)));
}

window.addEventListener("resize", function() {
    window.clearTimeout(window.__jrsInventoryResizeTimer);
    applyJrsExactCanvasScale();
    window.__jrsInventoryResizeTimer = window.setTimeout(applyResponsiveInventoryLayout, 40);
});

applyJrsExactCanvasScale();

function jrsClamp(value, minimum, maximum) {
    return Math.max(minimum, Math.min(maximum, value));
}

function applyResponsiveInventoryLayout() {
    const body = document.body;
    if (!body) return;

    // The exact-reference canvas must be re-fitted whenever the layout is
    // re-applied (open, layout switch, resize), not only at parse time.
    applyJrsExactCanvasScale();

    const width = Math.max(320, Number(window.innerWidth) || 1920);
    const height = Math.max(360, Number(window.innerHeight) || 1080);
    const isStorage = body.classList.contains("inventory-layout-storage");
    const isStandard = body.classList.contains("inventory-layout-standard");

    // Keep JS geometry identical to the final CSS geometry.
    // This prevents the panels from snapping back to old dimensions after opening.
    const mainWidth = 490;
    const mainHeight = 720;
    const sideWidth = 282;
    const sideHeight = 720;
    const storageWidth = 490;
    const standardColumnGap = 24;
    const storageColumnGap = 64;
    const footerGap = 8;
    const footerHeight = 94;
    const outerMargin = 12;
    // Storage hides wallet/hotbar, so it must scale against the two panels only.
    const totalHeight = isStorage ? mainHeight : (sideHeight + footerGap + footerHeight);

    body.classList.toggle("inventory-short-screen", height < 700);
    body.classList.remove("inventory-hide-clothing", "inventory-hide-ground");

    let groupWidth = mainWidth;
    if (isStorage) {
        groupWidth = mainWidth + storageColumnGap + storageWidth;
    } else if (isStandard) {
        groupWidth = sideWidth + standardColumnGap + mainWidth + standardColumnGap + sideWidth;
    }

    const widthScale = (width - outerMargin * 2) / groupWidth;
    const heightScale = (height - outerMargin * 2) / totalHeight;
    const scale = jrsClamp(Math.min(widthScale, heightScale), 0.42, 2.2);

    const groupPhysicalWidth = groupWidth * scale;
    const groupPhysicalHeight = totalHeight * scale;
    const groupLeft = (width - groupPhysicalWidth) / 2;
    const groupTop = (height - groupPhysicalHeight) / 2;

    let mainCenterX = width / 2;
    let clothingCenterX = width / 2;
    let groundCenterX = width / 2;
    let storageCenterX = width / 2;

    if (isStorage) {
        mainCenterX = groupLeft + (mainWidth * scale) / 2;
        storageCenterX = groupLeft + (mainWidth + storageColumnGap + storageWidth / 2) * scale;
    } else if (isStandard) {
        clothingCenterX = groupLeft + (sideWidth * scale) / 2;
        mainCenterX = groupLeft + (sideWidth + standardColumnGap + mainWidth / 2) * scale;
        groundCenterX = groupLeft + (sideWidth + standardColumnGap + mainWidth + standardColumnGap + sideWidth / 2) * scale;
    }

    // All three panels share the same final height and align from the same top edge.
    const mainCenterY = groupTop + (mainHeight * scale) / 2;
    const sideCenterY = groupTop + (sideHeight * scale) / 2;
    const footerCenterY = groupTop + (sideHeight + footerGap + footerHeight / 2) * scale;

    const currencyX = isStorage ? storageCenterX : clothingCenterX;
    const hotbarX = mainCenterX;

    body.style.setProperty("--jrs-ui-scale", scale.toFixed(4));
    body.style.setProperty("--jrs-panel-y", mainCenterY.toFixed(2) + "px");
    body.style.setProperty("--jrs-side-y", sideCenterY.toFixed(2) + "px");
    body.style.setProperty("--jrs-main-x", mainCenterX.toFixed(2) + "px");
    body.style.setProperty("--jrs-clothing-x", clothingCenterX.toFixed(2) + "px");
    body.style.setProperty("--jrs-ground-x", groundCenterX.toFixed(2) + "px");
    body.style.setProperty("--jrs-storage-x", storageCenterX.toFixed(2) + "px");
    body.style.setProperty("--jrs-footer-y", footerCenterY.toFixed(2) + "px");
    body.style.setProperty("--jrs-currency-x", currencyX.toFixed(2) + "px");
    body.style.setProperty("--jrs-hotbar-x", hotbarX.toFixed(2) + "px");

    syncCurrencyPanelPosition();
}

function setInventoryLayoutMode(mode) {
    const body = document.body;
    if (!body) return;

    body.classList.remove("inventory-layout-standard", "inventory-layout-storage", "inventory-storage-open");

    if (mode === "storage") {
        // Storage now reuses the bag's own design canvas (same size, same skin);
        // inventory-storage-open only swaps clothing/ground for the storage panel.
        // The old inventory-layout-storage CSS layer is no longer applied.
        body.classList.add("inventory-layout-standard", "inventory-storage-open");
    } else if (mode === "inventory") {
        body.classList.add("inventory-layout-standard");
    }

    // Calculate once immediately so the first visible frame is already in its
    // final position, then re-run next frame after CEF applies display changes.
    applyResponsiveInventoryLayout();
    requestAnimationFrame(applyResponsiveInventoryLayout);
}

let jrsLastScreenWidth = 0;
let jrsLastScreenHeight = 0;
function sendScreenMetricsIfChanged(force) {
    const width = Number(window.screen.availWidth) || 0;
    const height = Number(window.screen.availHeight) || 0;
    if (!force && width === jrsLastScreenWidth && height === jrsLastScreenHeight) return;
    jrsLastScreenWidth = width;
    jrsLastScreenHeight = height;
    $.post(jrsInventoryUrl + '/screen', JSON.stringify({ x: width, y: height }));
}


// Coalesced re-renders.
//
// These were requestAnimationFrame calls behind a "one frame already pending"
// guard. CEF stops running animation frames while the inventory page is not
// painting, and both of these are driven by messages that arrive constantly
// with the menu CLOSED - updateGround fires every time anything is dropped or
// picked up nearby. The first frame that never ran left the guard set forever,
// and from then on every later call returned immediately: the ground panel
// stopped refreshing for the rest of the session and opened empty or stale.
//
// A timer is used instead of a frame - it still runs when the page is not
// painting - and the guard is cleared before the work, never after, so a throw
// inside a render cannot wedge it either.
let jrsInventoryRenderFrame = 0;
let jrsGroundRenderFrame = 0;
function scheduleLightInventoryRender() {
    if (!jrsInventoryVisible()) return;
    if (jrsInventoryRenderFrame) return;
    jrsInventoryRenderFrame = setTimeout(function() {
        jrsInventoryRenderFrame = 0;
        loadTableData(table_inv, moneysd, wtable_inv, goldsd, dirtymoneysd);
        jrsMarkQueuedStoragePending();
    }, 0);
}
function scheduleLightGroundRender() {
    if (!jrsInventoryVisible()) return;
    if (jrsGroundRenderFrame) return;
    jrsGroundRenderFrame = setTimeout(function() {
        jrsGroundRenderFrame = 0;
        loadGroundData(ground_inv || []);
    }, 0);
}

function display2(bool, mode) {
    if (bool) {
        const targetMode = mode === "storage" ? "storage" : "inventory";
        setInventoryLayoutMode(targetMode);

        // Make the normal inventory visible before playing its open sound.
        // The old order tried to play while #container was still display:none,
        // so the sound guard correctly rejected it.
        $("#container").show();
        $("#container_other").hide();
        $("#show_weapons").hide();

        if (targetMode === "inventory") {
            showCurrencyPanel();
            $("#ground-container").show();
            $("#hotbar").show();
            giveTransferPending = false;
            playJrsInventoryOpenSoundOnce();
        } else {
            // Storage is intentionally a clean two-panel mode:
            // player inventory + storage only. Wallet/hotbar/ground stay hidden.
            hideCurrencyPanel();
            $("#ground-container").hide();
            $("#hotbar").hide();
            resetJrsInventoryOpenSoundState();
        }

    } else {
        jrsClearStorageQueue();
        flushJrsHotbarSave();
        // Play close while the normal inventory is still visible and still has
        // the standard layout class. Storage/robbery remains silent.
        playJrsInventoryCloseSoundOnce();
        containerMode = "storage";
        robberyTargetName = "";
        const header = document.getElementById("header");
        if (header && typeof config !== "undefined" && config.language && config.language[29]) {
            header.innerHTML = config.language[29].text;
        }
        const headerContainer = document.getElementById("header_container");
        if (headerContainer && typeof config !== "undefined" && config.language && config.language[2]) {
            headerContainer.innerHTML = config.language[2].text;
        }
        setInventoryLayoutMode(null);
        $(".ui-draggable-dragging").remove();
        $(".ui-draggable").trigger("mouseup");

        $("#container_other").hide();
        $("#container").hide();
        hideExpandedInfoNow();
        hideCurrencyPanel();
        $("#ground-container").hide(); 

        $("#hotbar").hide();
        resetInventorySearchAndFilter();
        multiSelectMode = false;
        multiSelectedEntries = {};
        updateMultiSelectToolbar();
        closeMultiPlayerWindow();
        closeGivePlayerWindow();
        dragged_item_inv = undefined;
        dragged_witem_inv = undefined;
        dragged_stor_inv = undefined;
        clicked_id = "";
        clicked_name = "";
        clicked_type = "";
        clicked_meta = {};
    }
}
window.display2 = display2;

$(function() {
    loadInventoryPins();
    updateSortControlState();
    applyResponsiveInventoryLayout();
    const header = document.getElementById("header");
    if (header && typeof config !== "undefined" && config.language && config.language[29]) {
        header.innerHTML = config.language[29].text;
    }
    const headerContainer = document.getElementById("header_container");
    if (headerContainer && typeof config !== "undefined" && config.language && config.language[2]) {
        headerContainer.innerHTML = config.language[2].text;
    }

    $("#input_data").hide();
    display2(false);
    

    window.addEventListener('message', function(event) {

        var item = event.data;
        if (item.type === "give_player_selector") {
            if (typeof item.purpose === "string" && item.purpose.length) {
                givePlayerSelectorPurpose = item.purpose;
            }
            givePlayerSelectorActive = item.active === true;
            if (givePlayerSelectorActive) {
                ensureGivePlayerSelectorLayer();
                updatePlayerSelectorLabels();
                renderGivePlayerSelectors(item.positions || []);
            } else {
                clearGivePlayerSelectors();
            }
        }
        if (item.type === "give_flow_finished") {
            pendingGiveRequest = null;
            pendingMultiGiveEntries = null;
            givePlayerSelectorActive = false;
            giveItemEnabled = false;
            giveTransferPending = false;
            clearGivePlayerSelectors();
            closeMultiPlayerWindow();
            closeGivePlayerWindow();
            if (contextMenu) contextMenu.classList.remove("visible");
            removeAllChildNodes(table_for_delete);
            display2(false);
        }

        if (item.type === "clothing_state") {
            renderClothingSlots(item.definitions || [], item.state || {}, item.integration === true);
        }
        if (item.type === "trade_availability") {
            setInventoryTradeButtonVisible(item.enabled === true);
        }
        if (Array.isArray(item.personal_items)) setPersonalItems(item.personal_items);
        if (typeof item.trade_enabled !== "undefined") {
            setInventoryTradeButtonVisible(item.trade_enabled === true);
        }
        if (item.ui_config) {
            inventoryDamagedThreshold = Number(item.ui_config.DamagedThreshold) || 30;
            inventoryWeightWarningPercent = Number(item.ui_config.WeightWarningPercent) || 80;
            inventoryWeightCriticalPercent = Number(item.ui_config.WeightCriticalPercent) || 95;
            inventoryWeightWarningSound = false;
        }
        if (item.type === "inventory_loading" || item.type === "inventory_table" || item.type === "container_table") {
            sendScreenMetricsIfChanged(false);
        }
        if (item.type === "inventory_loading") {
            // Keep the previous frame clean while the server prepares data.
            // No text overlay, no panel flash, and no extra DOM/image work.
            setInventoryLayoutMode(null);
            $("#inv_loading_overlay").remove();
            $("#container").hide();
            hideExpandedInfoNow();
            $("#clothing-side-panel").hide();
            $("#ground-container").hide();
            hideCurrencyPanel();
            $("#hotbar").hide();
        }

        if (item.type === "inventory_table") {
            $("#inv_loading_overlay").remove();
            if (item.status == true) {
                isInContext = false
                giveItemEnabled = false
                table_inv = normalizeInventoryCollection(item.table_for_json)
                wtable_inv = normalizeInventoryCollection(item.wtable_for_json)
                max_count_inventory = item.max_limit_i
                max_count_winventory = item.max_limit_w
                moneysd = Math.round((Number(item.money) || 0) * 100)/100
                goldsd = Number(item.gold) || 0
                dirtymoneysd = Math.round((Number(item.dirtymoney) || 0) * 100)/100
                loadTableData(table_inv, moneysd, wtable_inv, goldsd, dirtymoneysd)
                if (item.ground) {
                    loadGroundData(item.ground);
                }
                display2(true)
                $("#weaponData").hide();
                $("#tableData").show();


                document.getElementById("id03").innerHTML = ""+config.language[0].text+" : "+Math.round(count_inventory * 100) / 100+" "+JrsI18n.t('inv_kg_unit','KG')+" / "+max_count_inventory+" "+JrsI18n.t('inv_kg_unit','KG');
                document.getElementById("id07").innerHTML = ""+config.language[1].text+" : "+count_winventory+" / "+max_count_winventory;
} else {
                reset_button()
                display2(false)
            }
        }
        if (item.type === "container_table") {
            if (item.status == true) {
                // Moves queued for another storage must never land in this one.
                if (String(item.id_con) !== String(id_container)) jrsClearStorageQueue();
                canTransfer = true
                dragged_item_inv = undefined;
                dragged_witem_inv = undefined;
                dragged_stor_inv = undefined;
                clicked_id = "";
                clicked_name = "";
                clicked_type = "";
                clicked_meta = {};
                table_inv = []
                wtable_inv = []
                storage_inv = []
                size = 0
                max_count_inventory = 0
                max_count_winventory = 0
                table_inv = normalizeInventoryCollection(item.table_for_json)
                wtable_inv = normalizeInventoryCollection(item.wtable_for_json)
                max_count_inventory = item.max_limit_i
                max_count_winventory = item.max_limit_w
                moneysd = Math.round((Number(item.money) || 0) * 100)/100
                goldsd = Number(item.gold) || 0
                dirtymoneysd = Math.round((Number(item.dirtymoney) || 0) * 100)/100
                size = item.size
                id_container = item.id_con
                containerMode = item.container_mode || "storage"
                robberyTargetName = String(item.target_name || "")
                storageTitle = typeof item.container_title === "string" ? item.container_title : ""
                storageName = typeof item.container_name === "string" ? item.container_name : ""
                storage_inv = normalizeInventoryCollection(item.strg_tbl)
                loadTableData(table_inv, moneysd, wtable_inv, goldsd, dirtymoneysd)
                var storageSearch = document.getElementById("myInput");
                if (storageSearch) storageSearch.value = "";
                loadstoragedata(storage_inv)
                display2(true, "storage")
                // Clothing and the ground/drop panel are hidden while storage is open.
                $("#clothing-side-panel").hide();
                $("#ground-container").hide();
                $("#groundAmountWindow").hide();
                $("#weaponData").hide();
                $("#tableData").show();
                if (containerMode === "robbery" || containerMode === "admin_search") {
                    document.getElementById("header").innerHTML = JrsI18n.t("inventory_your_inventory", "YOUR INVENTORY");
                    const storageHeader = document.getElementById("header_container");
                    storageHeader.innerHTML = JrsI18n.t("inv_player_inventory", "PLAYER INVENTORY");
                    const targetDisplayName = robberyTargetName || storageName || "";
                    storageHeader.title = targetDisplayName ? (JrsI18n.t('inv_player_colon', 'Player:') + " " + targetDisplayName) : JrsI18n.t('inv_player_inventory', 'PLAYER INVENTORY');
                } else {
                    document.getElementById("header").innerHTML = config.language[29].text;
                    const storageHeader = document.getElementById("header_container");
                    storageHeader.textContent = storageTitle || String(config.language[2].text || "Storage");
                    storageHeader.title = storageName || storageTitle || "";
                }
                document.getElementById("id03").innerHTML = ""+config.language[0].text+" : "+Math.round(count_inventory * 100) / 100+" "+JrsI18n.t('inv_kg_unit','KG')+" / "+max_count_inventory+" "+JrsI18n.t('inv_kg_unit','KG');
                document.getElementById("id07").innerHTML = ""+config.language[1].text+" : "+count_winventory+" / "+max_count_winventory;
                document.getElementById("id08").innerHTML = (containerMode === "robbery" || containerMode === "admin_search")
                    ? JrsI18n.t('inv_target_weight', 'TARGET WEIGHT') + " : " + Math.round(count_sinventory * 100) / 100 + " " + JrsI18n.t('inv_kg_unit', 'KG') + " / " + size + " " + JrsI18n.t('inv_kg_unit', 'KG')
                    : JrsI18n.t('inv_storage', 'STORAGE') + " " + escapeDescriptionHtml(id_container || "") + "  •  " + Math.round(count_sinventory * 100) / 100 + " / " + size + " " + JrsI18n.t('inv_kg_unit', 'KG');
                updateStorageStatus();
                $("#container_other").show();
            }
        }

        if (item.type === "updateInventory") {
            table_inv = normalizeInventoryCollection(item.table_for_json)
            wtable_inv = normalizeInventoryCollection(item.wtable_for_json)
            moneysd = Math.round((Number(item.money) || 0) * 100) / 100
            goldsd = Number(item.gold) || 0
            dirtymoneysd = Math.round((Number(item.dirtymoney) || 0) * 100) / 100
            scheduleLightInventoryRender()
        }
        if (item.type === "inventory_update") {
            if (item.update == true) {
                table_inv = normalizeInventoryCollection(item.table_for_json)
                wtable_inv = normalizeInventoryCollection(item.wtable_for_json)
                moneysd = Math.round((Number(item.money) || 0) * 100) / 100
                goldsd = Number(item.gold) || 0
                dirtymoneysd = Math.round((Number(item.dirtymoney) || 0) * 100) / 100
                scheduleLightInventoryRender()
            } else {
                table_inv = normalizeInventoryCollection(item.table_for_json)
                dirtymoneysd = Math.round((Number(item.dirtymoney) || 0) * 100) / 100
                update_item(table_inv, item.iditem, item.idcount, Math.round(item.money * 100)/100, item.gold, item.dirtymoney)
            }
        }
        if (item.type === "currency_update") {
            moneysd = Math.round((Number(item.money) || 0) * 100) / 100;
            goldsd = Math.round((Number(item.gold) || 0) * 100) / 100;
            dirtymoneysd = Math.round((Number(item.dirtymoney) || 0) * 100) / 100;
            renderCurrencyPanel(moneysd, goldsd, dirtymoneysd);
        }
        if (item.type === "playertable") {
            table_play = item.table_p_for_json || [];
            renderGivePlayerList(table_play);
        }
        if (item.type === "weapon_state_update") {
            change_active_weapon(item.id, item.state);
        }
        if (item.type === "weapon_desc_update") {
            change_active_weapon(item.data_info)
        }
        if (item.type === "cleanTransfer") {
            blockMe = false
            clearJrsStorageDragState();
            // Player closed/cancelled the amount box: drop the rest of the queue too.
            if (item.reason === "cancelled") jrsClearStorageQueue();
            else {
                // The answered stack is no longer in flight (a refused one must
                // be draggable again); only still-queued stacks stay dimmed.
                $(".jrs-transfer-pending").removeClass("jrs-transfer-pending");
                jrsMarkQueuedStoragePending();
                jrsPumpStorageQueue();
            }
        }

        // Light storage refresh (2.3.3): after a transfer only the storage grid
        // and its weight change. The old path re-sent the whole container_table,
        // which re-rendered the player grid, re-ran the open layout and hid and
        // re-showed the storage panel on every single move.
        if (item.type === "storage_refresh") {
            if (!id_container || String(item.id_con) !== String(id_container)) return;
            if (typeof item.size !== "undefined") size = item.size;
            storage_inv = normalizeInventoryCollection(item.strg_tbl);
            loadstoragedata(storage_inv);
            const weightLine = document.getElementById("id08");
            if (weightLine && containerMode !== "robbery" && containerMode !== "admin_search") {
                weightLine.innerHTML = JrsI18n.t('inv_storage', 'STORAGE') + " " + escapeDescriptionHtml(id_container || "") + "  •  " + Math.round(count_sinventory * 100) / 100 + " / " + size + " " + JrsI18n.t('inv_kg_unit', 'KG');
            }
            jrsMarkQueuedStoragePending();
        }

        if(item.type == "updateGround"){

           ground_inv = item.ground || [];

           scheduleLightGroundRender();
           

        }
        if(item.type == "loadHotbar"){

         loadHotbar(item.hotbar);

        }
        
        if (item.type === "multi_player_table") {
            renderMultiPlayerList(item.table_p_for_json || []);
        }

        if (item.type === "input_data") {
            if (item.status === true) {
                allCount = 0
                allCount = item.count
                inInput = true
                $("#input_data").show();
                $("#input_type").focus();
            } else {
                inInput = false
                $("#input_data").hide();
                allCount = 0
                document.getElementById("input_type").value = "";
            }
        }
    })

    $("#close").click(function() {
        flushPendingInventorySlotSave();
        $.post(jrsInventoryUrl + '/exit', JSON.stringify({}));
        return
    })

})

function getDragSourceFromDraggable(draggable) {
    if (!draggable) return null;
    const el = $(draggable);
    const type = String(el.attr("data-type") || "");
    if (el.hasClass("currency-entry") || isCurrencyType(type)) {
        return { kind: "currency", currency: type || el.attr("data-slot") };
    }
    const indexAttr = el.attr("data-index") !== undefined ? el.attr("data-index") : el.find(".item-content").attr("id");
    const index = (indexAttr !== undefined && indexAttr !== "") ? Number(indexAttr) : null;
    if (type === "weapon") {
        return { kind: "weapon", index: index };
    }
    if (type === "item" || index !== null) {
        return { kind: "item", index: index };
    }
    return null;
}

function getStorageIndexFromDraggable(draggable) {
    if (!draggable) return null;
    const el = $(draggable);
    const attr = el.attr("data-storage-index");
    if (attr !== undefined && attr !== "") {
        const num = Number(attr);
        if (Number.isInteger(num)) return num;
    }
    const contentId = el.find(".item-content").attr("id");
    if (contentId !== undefined && contentId !== "") {
        const num = Number(contentId);
        if (Number.isInteger(num)) return num;
    }
    return null;
}

// source: { kind: "item" | "weapon" | "currency", index?, currency? }
// Deterministically resolves the exact source item/weapon/currency being moved
// to storage, eliminating any dependency on stale clicked_type or hover variables.
function transfer_to_storage(targetSlot, source) {
    // Robbery mode is intentionally one-way: target (right) -> robber (left).
    if (containerMode === "robbery") {
        drag_to_other = false;
        return;
    }
    // Busy is no longer a reason to drop the move: jrsQueueStorageTransfer
    // holds it until the previous transfer is answered.

    const normalizedTargetSlot = Number(targetSlot);
    const targetStorageSlot = Number.isInteger(normalizedTargetSlot) && normalizedTargetSlot > 0
        ? normalizedTargetSlot
        : null;

    let payload = null;

    if (source && source.kind === "currency") {
        const curr = source.currency;
        if (curr === 'money') {
            payload = {weapon:false, item: "money", count: moneysd, container_id:id_container, size:count_sinventory};
        } else if (curr === 'gold') {
            payload = {weapon:false, item: "gold", count: goldsd, container_id:id_container, size:count_sinventory};
        } else if (curr === 'dirtymoney') {
            payload = {weapon:false, item: "dirtymoney", count: dirtymoneysd, container_id:id_container, size:count_sinventory};
        }
        dragged_item_inv = curr;
        dragged_witem_inv = undefined;
    } else if (source && source.kind === "weapon") {
        if (!wtable_inv || !wtable_inv[source.index]) return;
        const weapon = wtable_inv[source.index];
        payload = {weapon:true, id: weapon.id, item: weapon.name, container_id:id_container, used:weapon.used, size:count_sinventory};
        dragged_witem_inv = source.index;
        dragged_item_inv = undefined;
    } else if (source && source.kind === "item") {
        if (!table_inv || !table_inv[source.index]) return;
        const item = table_inv[source.index];
        payload = {
            weapon:false,
            itemId:item.itemId,
            item:item.item,
            count:item.count,
            container_id:id_container,
            size:count_sinventory,
            limit:item.limit,
            metaData:item.metaData,
            countInInventory:item.count
        };
        dragged_item_inv = source.index;
        dragged_witem_inv = undefined;
    } else {
        // Fallback only if caller passed no source:
        if (isCurrencyType(dragged_item_inv)) {
            if (dragged_item_inv === 'money') {
                payload = {weapon:false, item: "money", count: moneysd, container_id:id_container, size:count_sinventory};
            } else if (dragged_item_inv === 'gold') {
                payload = {weapon:false, item: "gold", count: goldsd, container_id:id_container, size:count_sinventory};
            } else if (dragged_item_inv === 'dirtymoney') {
                payload = {weapon:false, item: "dirtymoney", count: dirtymoneysd, container_id:id_container, size:count_sinventory};
            }
        } else if (dragged_witem_inv !== undefined && wtable_inv && wtable_inv[dragged_witem_inv]) {
            const weapon = wtable_inv[dragged_witem_inv];
            payload = {weapon:true, id: weapon.id, item: weapon.name, container_id:id_container, used:weapon.used, size:count_sinventory};
        } else if (dragged_item_inv !== undefined && table_inv && table_inv[dragged_item_inv]) {
            const item = table_inv[dragged_item_inv];
            payload = {
                weapon:false,
                itemId:item.itemId,
                item:item.item,
                count:item.count,
                container_id:id_container,
                size:count_sinventory,
                limit:item.limit,
                metaData:item.metaData,
                countInInventory:item.count
            };
        } else {
            return;
        }
    }

    if (!payload) return;
    if (isPersonalItem(selectedPersonalItemName())) return;

    if (targetStorageSlot !== null) payload.targetSlot = targetStorageSlot;
    if (jrsShiftHeld) payload.fullStack = true;

    jrsQueueStorageTransfer('transfer_to_storage', payload);
    canTransfer = false;
    drag_to_other = false;
}


function transferOneItem() {
    document.getElementById("input_type").value = 1;
    transferAcceptItem()
}

function transferAllItem() {
    document.getElementById("input_type").value = allCount;
    transferAcceptItem()
}


function transferAcceptItem() {

    $.post(
        jrsInventoryUrl + '/transferAcceptItem',
        JSON.stringify({
            count: document.getElementById("input_type").value
        })
    );

    allCount = 0;

    document.getElementById("input_type").value = "";

    $("#input_data").hide();

    inInput = false;

}

function transferLeaveItem() {
    allCount = 0
    document.getElementById("input_type").value = "";
    $.post(jrsInventoryUrl + '/transferLeaveItem', JSON.stringify({}));
    $("#input_data").hide();
    inInput = false
}

function money_update(money){
    const moneyCount = document.getElementById("count_money");
    if (moneyCount) moneyCount.innerHTML = ''+Math.round(money * 100)/100+' $';
}

function renderCurrencyPanel(money, gold, dirtymoney) {
    const moneyCount = document.getElementById("count_money");
    const goldCount = document.getElementById("count_gold");
    const dirtyMoneyCount = document.getElementById("count_dirtymoney");

    if (moneyCount) moneyCount.textContent = (Math.round((Number(money) || 0) * 100) / 100) + " $";
    if (goldCount) goldCount.textContent = Math.round((Number(gold) || 0) * 100) / 100;
    if (dirtyMoneyCount) dirtyMoneyCount.textContent = (Math.round((Number(dirtymoney) || 0) * 100) / 100) + " $";
}


// Bag grid size: at least 20 slots, and always 4 free ones after the last used
// slot so a full grid still has somewhere to drop.
const JRS_INVENTORY_BASE_SLOTS = 20;
const JRS_INVENTORY_TRAILING_EMPTY_SLOTS = 4;
let jrsInventoryRenderedSlots = 0;

function jrsInventoryGridSize(highestUsedSlot) {
    return Math.max(JRS_INVENTORY_BASE_SLOTS, highestUsedSlot + JRS_INVENTORY_TRAILING_EMPTY_SLOTS);
}

function buildInventoryBadges(kind, entry, name) {
    let html = "";
    if (isPersonalItem(name)) {
        html += '<span class="personal-lock" title="' + JrsI18n.t("inventory_personal_item", "Personal item") + '">&#128274;</span>';
    }
    if (isInventoryEntryPinned(kind, entry)) {
        html += '<span class="inventory-pin-badge" title="' + JrsI18n.t("inv_pinned_title", "Pinned") + '">&#9733;</span>';
    }
    if (kind === "weapon" && entry.stolen) {
        html += '<span class="stolen-badge" title="' + JrsI18n.t("inventory_reported_stolen", "Reported Stolen") + '">&#9888;</span>';
    }
    return html;
}

// One bag slot. Shared by the full render and by jrsRefreshInventorySlots(),
// which only rebuilds the slots a move touched instead of the whole grid.
// `i` is the entry's index in table_inv (items) or wtable_inv (weapons).
function buildInventorySlotHtml(slot, slotData, i) {
    if (!slotData) {
        return '<div class="empty-slot" data-origin="inventory" data-slot="' + slot + '" title="Inventory slot ' + slot + '">' +
            '<span class="slot-id-badge">' + slot + '</span></div>';
    }

    const item = slotData.data;

    if (slotData.type === "weapon") {
        const personal = isPersonalItem(item.name);
        const damaged = isEntryDamaged("weapon", item);
        const classes = "item" +
            (item.used == 1 ? " weapon-used" : "") +
            (personal ? " personal-locked" : "") +
            (damaged ? " inventory-damaged" : "") +
            (isInventoryEntryPinned("weapon", item) ? " inventory-pinned" : "") +
            (item.stolen ? " weapon-stolen" : "");

        return '<div class="' + classes + '" ' +
                'data-slot="' + slot + '" ' +
                'data-origin="inventory" ' +
                'data-type="weapon" ' +
                'data-index="' + i + '" ' +
                'data-entry-key="weapon:' + item.id + '" ' +
                'data-personal="' + personal + '" ' +
                'data-damaged="' + damaged + '" ' +
                'data-stolen="' + (item.stolen ? 'true' : 'false') + '" ' +
                'data-content="valuable" ' +
                'data-filter-tags="' + buildInventoryFilterTags(item, "weapon") + '" ' +
                'title="' + JrsI18n.f("inv_slot_inventory", slot) + '">' +
            '<span class="slot-id-badge">' + slot + '</span>' +
            '<div id="' + i + '" class="item-content" ' +
                'onmouseenter="change_name_wep(' + i + ')" ' +
                'ondblclick="if(!multiSelectMode){UseWeapon(\'' + item.id + '\',\'' + item.name + '\')}">' +
                '<img loading="lazy" decoding="async" src="images/items/' + item.name + '.png" width="60" height="60">' +
                buildInventoryBadges("weapon", item, item.name) +
            '</div>' +
        '</div>';
    }

    const personal = isPersonalItem(item.item);
    const damaged = isEntryDamaged("item", item);
    const classes = "item" +
        (personal ? " personal-locked" : "") +
        (damaged ? " inventory-damaged" : "") +
        (isInventoryEntryPinned("item", item) ? " inventory-pinned" : "");
    const durabilityValue = getItemDurabilityPercent(item);
    const stackWeight = item.count * parseFloat(item.limit);

    return '<div class="' + classes + '" ' +
            'data-slot="' + slot + '" ' +
            'data-origin="inventory" ' +
            'data-type="item" ' +
            'data-index="' + i + '" ' +
            'data-entry-key="item:' + item.itemId + '" ' +
            'data-personal="' + personal + '" ' +
            'data-damaged="' + damaged + '" ' +
            'data-content="' + (item.category || "") + '" ' +
            'data-filter-tags="' + buildInventoryFilterTags(item, "item") + '" ' +
            'title="' + JrsI18n.f("inv_slot_inventory", slot) + '">' +
        '<span class="slot-id-badge">' + slot + '</span>' +
        '<div id="' + i + '" class="item-content" ' +
            'onmouseenter="change_name(' + i + ')" ' +
            'ondblclick="if(!multiSelectMode){UseItem(' + i + ')}">' +
            '<img loading="lazy" decoding="async" src="images/items/' + item.item + '.png" width="60" height="60" id="item">' +
            buildInventoryBadges("item", item, item.item) +
            (durabilityValue !== null ? '<progress id="progress" max="100" value="' + durabilityValue + '"></progress>' : '') +
            '<div class="bottom-right">' + item.count + '<br>' + (Math.round(stackWeight * 100) / 100) + 'kg</div>' +
        '</div>' +
    '</div>';
}

function loadTableData(table_inv, money, wtable_inv, gold, dirtymoney = dirtymoneysd) {
    table_inv = normalizeInventoryCollection(table_inv);
    wtable_inv = normalizeInventoryCollection(wtable_inv);

    renderCurrencyPanel(money, gold, dirtymoney);

    if (!isRenderingTemporarySort) {
        if (skipSortReapplyOnce) {
            skipSortReapplyOnce = false;
        } else {
            captureManualInventorySlots();
            if (activeTemporarySortMode) {
                applyTemporaryInventorySort(activeTemporarySortMode);
                return;
            }
        }
    }

    // slot -> { type, data } and slot -> index in its source table
    const slotMap = {};
    const slotIndexMap = {};
    let highestUsedSlot = 0;

    count_inventory = 0;
    count_winventory = 0;
    inventoryWeightBreakdown = { food: 0, drink: 0, seeds: 0, ammo: 0, equipment: 0, other: 0, total: 0, weapons: 0 };

    for (let i = 0; i < table_inv.length; i++) {
        const item = table_inv[i];
        slotMap[item.slot] = { type: "item", data: item };
        slotIndexMap[item.slot] = i;
        highestUsedSlot = Math.max(highestUsedSlot, Number(item.slot) || 0);

        const stackWeight = (Number(item.count) || 0) * (Number(item.limit) || 0);
        const weightCategory = getPrimaryWeightCategory(item);
        count_inventory += stackWeight;
        inventoryWeightBreakdown[weightCategory] = (inventoryWeightBreakdown[weightCategory] || 0) + stackWeight;
        inventoryWeightBreakdown.total += stackWeight;
    }

    for (let i = 0; i < wtable_inv.length; i++) {
        const weapon = wtable_inv[i];
        slotMap[weapon.slot] = { type: "weapon", data: weapon };
        slotIndexMap[weapon.slot] = i;
        highestUsedSlot = Math.max(highestUsedSlot, Number(weapon.slot) || 0);
        count_winventory++;
        inventoryWeightBreakdown.weapons++;
    }

    const totalSlots = jrsInventoryGridSize(highestUsedSlot);
    let dataHtml = "";
    for (let slot = 1; slot <= totalSlots; slot++) {
        dataHtml += buildInventorySlotHtml(slot, slotMap[slot], slotIndexMap[slot]);
    }
    jrsInventoryRenderedSlots = totalSlots;
    jrsSetWidgetHtml(document.getElementById("tableData"), dataHtml);

    applyInventoryFilter();
    applyMultiSelectionVisuals();
    makeItemsDraggableAndDroppable();
    renderJrsHotbar();
    makeCurrencyDraggable();
    syncCurrencyPanelPosition();

    // Status bar
    $("#weightText").text(
        Math.round(count_inventory * 100) / 100 + " / " + max_count_inventory + " " + JrsI18n.t("inv_kg_unit", "KG")
    );
    $("#slotText").text(count_winventory + " / " + max_count_winventory);

    const weightPercent = max_count_inventory > 0
        ? Math.min(100, (count_inventory / max_count_inventory) * 100)
        : 0;
    $("#weightFill").css("width", weightPercent + "%");
    updateWeightWarning(weightPercent);
    renderWeightBreakdown();
}


// ============================================================================
// Quick access / Hotbar 1..5
// Server remains authoritative. The UI keeps a small local mirror so assigning,
// swapping and clearing slots feels instant while a single debounced save is sent.
// ============================================================================
var jrsHotbarState = {
    1: null,
    2: null,
    3: null,
    4: null,
    5: null
};
var jrsHotbarSaveTimer = 0;
var jrsHotbarDirty = false;
var jrsHotbarRebindFrame = 0;

function normalizeJrsHotbarEntry(raw) {
    if (!raw || typeof raw !== "object") return null;
    const itemName = String(raw.item || "").trim();
    if (!itemName) return null;

    const idNumber = Number(raw.id);
    return {
        item: itemName,
        id: Number.isFinite(idNumber) ? idNumber : raw.id,
        weapon: raw.weapon === true || Number(raw.weapon) === 1 || String(raw.weapon) === "true"
    };
}

function jrsHotbarEntryKey(entry) {
    entry = normalizeJrsHotbarEntry(entry);
    if (!entry) return "";
    return (entry.weapon ? "weapon:" : "item:") + String(entry.id != null ? entry.id : "") + ":" + entry.item;
}

function serializeJrsHotbar() {
    const payload = {};
    for (let i = 1; i <= 5; i++) {
        payload["slot" + i] = jrsHotbarState[i]
            ? Object.assign({}, jrsHotbarState[i])
            : {};
    }
    return payload;
}

function flushJrsHotbarSave() {
    if (jrsHotbarSaveTimer) {
        clearTimeout(jrsHotbarSaveTimer);
        jrsHotbarSaveTimer = 0;
    }
    if (!jrsHotbarDirty) return;
    jrsHotbarDirty = false;
    $.post(jrsInventoryUrl + "/hotbar_save_all", JSON.stringify({
        hotbar: serializeJrsHotbar()
    }));
}

function queueJrsHotbarSave() {
    jrsHotbarDirty = true;
    if (jrsHotbarSaveTimer) clearTimeout(jrsHotbarSaveTimer);
    jrsHotbarSaveTimer = setTimeout(function() {
        jrsHotbarSaveTimer = 0;
        flushJrsHotbarSave();
    }, 110);
}

function findJrsHotbarInventoryEntry(entry) {
    entry = normalizeJrsHotbarEntry(entry);
    if (!entry) return null;

    if (entry.weapon) {
        let fallback = null;
        const entryUpper = String(entry.item || "").toUpperCase();
        for (const weapon of normalizeInventoryCollection(wtable_inv)) {
            if (String(weapon.name || "").toUpperCase() !== entryUpper) continue;
            fallback = fallback || weapon;
            if (String(weapon.id) === String(entry.id)) return weapon;
        }
        return fallback;
    }

    let fallback = null;
    for (const item of normalizeInventoryCollection(table_inv)) {
        if (String(item.item) !== entry.item || Number(item.count || 0) <= 0) continue;
        fallback = fallback || item;
        if (String(item.itemId) === String(entry.id)) return item;
    }
    return fallback;
}

function renderJrsHotbarSlot(slot) {
    const entry = normalizeJrsHotbarEntry(jrsHotbarState[slot]);
    const root = $("#slot" + slot);
    const image = $("#slot" + slot + "-item");
    const count = $("#slot" + slot + "-count");

    root.removeClass("hotbar-filled hotbar-stale");
    image.attr("src", "").hide();
    count.text("");
    root.attr("title", "Quick slot " + slot + " — drag an item here. Right-click to clear.");
    window["slot" + slot] = "";

    if (!entry) return;

    const inventoryEntry = findJrsHotbarInventoryEntry(entry);
    if (inventoryEntry && String(entry.id) !== String(entry.weapon ? inventoryEntry.id : inventoryEntry.itemId)) {
        // Stack IDs can legitimately change after merges. Keep the shortcut alive
        // by following the same owned stack/weapon and persist the repaired ID.
        entry.id = entry.weapon ? inventoryEntry.id : inventoryEntry.itemId;
        jrsHotbarState[slot] = entry;
        queueJrsHotbarSave();
    }

    image.attr("src", "images/items/" + entry.item + ".png").show();
    root.addClass("hotbar-filled");
    window["slot" + slot] = entry.item;

    if (inventoryEntry) {
        if (!entry.weapon) count.text(Number(inventoryEntry.count || 0));
        root.attr("title", "Quick slot " + slot + " — " + entry.item + ". Right-click to clear.");
    } else {
        // Do not delete locally just because the table is mid-refresh; the server
        // will authoritatively clean stale shortcuts and sync them back.
        root.addClass("hotbar-stale");
    }
}

function renderJrsHotbar() {
    // A refresh can move what sits in a slot, so a menu opened against the old
    // contents must not survive it.
    closeJrsHotbarContextMenu();
    for (let i = 1; i <= 5; i++) renderJrsHotbarSlot(i);
}

function applyJrsHotbarEntry(slot, rawEntry, persist) {
    slot = Number(slot);
    if (!Number.isInteger(slot) || slot < 1 || slot > 5) return false;

    const entry = normalizeJrsHotbarEntry(rawEntry);
    const key = jrsHotbarEntryKey(entry);

    // One physical item/weapon should occupy only one shortcut slot. Moving it to
    // another slot automatically frees the previous shortcut instead of creating
    // two keys that point at the exact same database entry.
    if (entry && key) {
        for (let i = 1; i <= 5; i++) {
            if (i !== slot && jrsHotbarEntryKey(jrsHotbarState[i]) === key) {
                jrsHotbarState[i] = null;
            }
        }
    }

    jrsHotbarState[slot] = entry;
    renderJrsHotbar();
    scheduleJrsHotbarRebind();
    if (persist !== false) queueJrsHotbarSave();
    return true;
}

function hotbarEntryFromInventoryElement(sourceElement) {
    const element = $(sourceElement);
    const type = String(element.attr("data-type") || "");
    const index = Number(element.attr("data-index"));
    const slot = Number(element.attr("data-slot"));
    const entryKey = String(element.attr("data-entry-key") || "");
    const normalizedItems = normalizeInventoryCollection(table_inv);
    const normalizedWeapons = normalizeInventoryCollection(wtable_inv);

    if (type === "weapon" || entryKey.indexOf("weapon:") === 0) {
        let weapon = Number.isInteger(index) ? normalizedWeapons[index] : null;
        if (!weapon && entryKey.indexOf("weapon:") === 0) {
            const rawId = entryKey.split(":")[1];
            weapon = normalizedWeapons.find(function(w) { return String(w.id) === String(rawId); });
        }
        if (!weapon && Number.isInteger(slot)) {
            weapon = normalizedWeapons.find(function(w) { return Number(w.slot) === slot; });
        }
        if (!weapon) return null;
        return normalizeJrsHotbarEntry({
            item: weapon.name,
            id: weapon.id,
            weapon: true
        });
    }

    if (type === "item" || entryKey.indexOf("item:") === 0) {
        let item = Number.isInteger(index) ? normalizedItems[index] : null;
        if (!item && entryKey.indexOf("item:") === 0) {
            const rawId = entryKey.split(":")[1];
            item = normalizedItems.find(function(it) { return String(it.itemId) === String(rawId); });
        }
        if (!item && Number.isInteger(slot)) {
            item = normalizedItems.find(function(it) { return Number(it.slot) === slot; });
        }
        if (!item || Number(item.count || 0) <= 0) return null;
        return normalizeJrsHotbarEntry({
            item: item.item,
            id: item.itemId,
            weapon: false
        });
    }

    return null;
}

function show_hotbar(slot, sourceElement) {
    const entry = hotbarEntryFromInventoryElement(sourceElement);
    if (!entry) return false;
    return applyJrsHotbarEntry(slot, entry, true);
}

function loadHotbar(hotbar) {
    hotbar = hotbar && typeof hotbar === "object" ? hotbar : {};
    for (let i = 1; i <= 5; i++) {
        jrsHotbarState[i] = normalizeJrsHotbarEntry(hotbar["slot" + i]);
    }
    jrsHotbarDirty = false;
    if (jrsHotbarSaveTimer) {
        clearTimeout(jrsHotbarSaveTimer);
        jrsHotbarSaveTimer = 0;
    }
    renderJrsHotbar();
    scheduleJrsHotbarRebind();
}

function clear_hotbar(id) {
    return applyJrsHotbarEntry(Number(id), null, true);
}

function swapJrsHotbarSlots(fromSlot, toSlot) {
    fromSlot = Number(fromSlot);
    toSlot = Number(toSlot);
    if (!Number.isInteger(fromSlot) || !Number.isInteger(toSlot)) return;
    if (fromSlot < 1 || fromSlot > 5 || toSlot < 1 || toSlot > 5 || fromSlot === toSlot) return;

    const temp = jrsHotbarState[fromSlot];
    jrsHotbarState[fromSlot] = jrsHotbarState[toSlot];
    jrsHotbarState[toSlot] = temp;
    renderJrsHotbar();
    scheduleJrsHotbarRebind();
    queueJrsHotbarSave();
}

// Right-clicking a quick slot used to clear it on the spot, which made it far
// too easy to lose a shortcut while aiming for something else. It now opens a
// one-entry menu at the cursor and the removal only happens on the click.
let jrsHotbarContextSlot = 0;

function closeJrsHotbarContextMenu() {
    const menu = document.getElementById("hotbar-context-menu");
    if (menu) menu.classList.remove("visible");
    jrsHotbarContextSlot = 0;
}

function openJrsHotbarContextMenu(slot, event) {
    slot = Number(slot);
    const menu = document.getElementById("hotbar-context-menu");

    // Nothing to remove from an empty slot.
    if (!normalizeJrsHotbarEntry(jrsHotbarState[slot])) {
        closeJrsHotbarContextMenu();
        return;
    }

    // Older HTML builds have no menu element; keep the previous behaviour there
    // rather than leaving the slot unclearable.
    if (!menu) {
        clear_hotbar(slot);
        return;
    }

    jrsHotbarContextSlot = slot;
    if (typeof contextMenu !== "undefined" && contextMenu) contextMenu.classList.remove("visible");

    menu.classList.add("visible");

    const pointerX = Number(event && (event.clientX !== undefined ? event.clientX : (event.originalEvent || {}).clientX)) || 0;
    const pointerY = Number(event && (event.clientY !== undefined ? event.clientY : (event.originalEvent || {}).clientY)) || 0;
    const width = menu.offsetWidth || 160;
    const height = menu.offsetHeight || 34;
    const maxLeft = Math.max(0, (window.innerWidth || width) - width - 6);
    const maxTop = Math.max(0, (window.innerHeight || height) - height - 6);

    menu.style.left = Math.min(pointerX, maxLeft) + "px";
    menu.style.top = Math.min(pointerY, maxTop) + "px";
}

function removeSelectedHotbarSlot() {
    const slot = Number(jrsHotbarContextSlot);
    closeJrsHotbarContextMenu();
    if (Number.isInteger(slot) && slot >= 1 && slot <= 5) clear_hotbar(slot);
}

document.addEventListener("mousedown", function(event) {
    const menu = document.getElementById("hotbar-context-menu");
    if (!menu || !menu.classList.contains("visible")) return;
    if (menu.contains(event.target)) return;
    closeJrsHotbarContextMenu();
}, true);

document.addEventListener("keydown", function(event) {
    if (event.key === "Escape" || event.key === "Esc") closeJrsHotbarContextMenu();
});

// The rebind used to be deferred with requestAnimationFrame behind a
// "one frame already pending" guard. CEF stops firing animation frames while
// the inventory page is not painting, and loadHotbar() runs on every inventory
// refresh - including while the menu is closed. The very first dropped frame
// left jrsHotbarRebindFrame set forever, so every later call returned early and
// the quick slots kept whatever jQuery UI bindings they had at that moment:
// a slot filled after that point never became draggable, so slot-to-slot moves
// silently did nothing. jrs_inventory rebinds its hotbar synchronously for the
// same reason; this now does too, with a timer (not a frame) only to coalesce
// bursts, and the guard is always cleared.
function scheduleJrsHotbarRebind() {
    if (jrsHotbarRebindFrame) {
        clearTimeout(jrsHotbarRebindFrame);
        jrsHotbarRebindFrame = 0;
    }

    // Bind straight away so the slots are usable even if no timer ever runs.
    bindJrsHotbarInteractions();

    // A second pass after the current render settles, in case this call landed
    // mid-refresh and the DOM was replaced right after.
    jrsHotbarRebindFrame = setTimeout(function() {
        jrsHotbarRebindFrame = 0;
        bindJrsHotbarInteractions();
    }, 0);
}

function bindJrsHotbarInteractions() {
    if (!jrsHasDragDrop()) return;
    const slots = $("#hotbar .hotbar-slot");
    if (!slots.length) return;

    // Rebinding is intentional. Inventory rendering destroys old jQuery UI
    // droppables; the previous implementation created the hotbar drops only once,
    // which is why they stopped accepting items after the first inventory refresh.
    jrsDestroyDragDrop(slots);
    slots.off(".jrsHotbar");

    slots.each(function() {
        const root = $(this);
        const slot = Number(root.attr("data-hotbar-slot") || root.attr("id").replace("slot", ""));
        const hasEntry = !!normalizeJrsHotbarEntry(jrsHotbarState[slot]);

        root.droppable({
            accept: "#tableData .item, #hotbar .hotbar-slot",
            tolerance: "pointer",
            hoverClass: "drag-hover",
            activeClass: "jrs-drop-ready",
            addClasses: false,
            drop: function(event, ui) {
                const source = $(ui.draggable);
                const fromSlot = source.hasClass("hotbar-slot")
                    ? Number(source.attr("data-hotbar-slot"))
                    : null;

                // Applying the change rebinds these quick slots, which destroys
                // and recreates the droppable whose drop handler is running right
                // now. Leave jQuery UI's drop loop first (jrs_inventory defers
                // its hotbar assign/swap the same way) and act on the next tick.
                setTimeout(function() {
                    if (fromSlot !== null) {
                        swapJrsHotbarSlots(fromSlot, slot);
                        return;
                    }
                    show_hotbar(slot, source);
                }, 0);
            }
        });

        if (hasEntry) {
            root.draggable({
                helper: jrsDragGhost,
                appendTo: "body",
                zIndex: 999999,
                revert: "invalid",
                revertDuration: 70,
                distance: JRS_DRAG_DISTANCE,
                scroll: false,
                addClasses: false,
                opacity: 0.96,
                start: function() { $(this).addClass("jrs-drag-source"); },
                stop: function() { $(this).removeClass("jrs-drag-source"); }
            });
        }

        root.on("contextmenu.jrsHotbar", function(event) {
            event.preventDefault();
            event.stopPropagation();
            openJrsHotbarContextMenu(slot, event);
            return false;
        });
    });
}

var activeGiveItem = null;

function transferItem() {
    if (giveTransferPending) return;
    if (contextMenu) contextMenu.classList.remove("visible");
    if (table_for_delete) table_for_delete.classList.remove("visible");
    isInContext = false;

    var itemType = clicked_type || "item";
    var itemId = clicked_id;
    var itemName = clicked_name;
    var maxCount = 1;
    var itemLabel = itemName || "Item";
    var itemImg = "images/items/money.png";

    if (itemType === "weapon") {
        var weapon = null;
        for (var w = 0; w < wtable_inv.length; w++) {
            if (wtable_inv[w] && (wtable_inv[w].id == clicked_id || w == clicked_id)) {
                weapon = wtable_inv[w];
                break;
            }
        }
        if (weapon) {
            itemLabel = weapon.label || weapon.name || "Weapon";
            itemImg = "images/items/" + (weapon.name || "").toLowerCase() + ".png";
            itemId = weapon.id;
            itemName = weapon.name;
        } else {
            itemLabel = clicked_name || "Weapon";
            itemImg = "images/items/" + (clicked_name || "").toLowerCase() + ".png";
        }
        maxCount = 1;
    } else if (itemType === "money") {
        itemLabel = (typeof JrsI18n !== 'undefined') ? JrsI18n.t("inv_currency_money", "Money") : "Money";
        itemImg = "images/items/money.png";
        maxCount = Number(moneysd) || 0;
        itemId = "money";
        itemName = "money";
    } else if (itemType === "gold") {
        itemLabel = (typeof JrsI18n !== 'undefined') ? JrsI18n.t("inv_currency_gold", "Gold") : "Gold";
        itemImg = "images/items/gold.png";
        maxCount = Number(goldsd) || 0;
        itemId = "gold";
        itemName = "gold";
    } else if (itemType === "dirtymoney") {
        itemLabel = (typeof JrsI18n !== 'undefined') ? JrsI18n.t("inv_currency_dirtymoney", "Dirty Money") : "Dirty Money";
        itemImg = "images/items/dirtymoney.png";
        maxCount = Number(dirtymoneysd) || 0;
        itemId = "dirtymoney";
        itemName = "dirtymoney";
    } else {
        // The exact stack that was right-clicked. Matching by name as well
        // picked the FIRST stack of that item (wrong count / metadata).
        var invItem = null;
        for (var i = 0; i < table_inv.length; i++) {
            if (table_inv[i] && String(table_inv[i].itemId) === String(clicked_id)) {
                invItem = table_inv[i];
                break;
            }
        }
        if (invItem) {
            const isAr = (typeof JrsI18n !== 'undefined' && JrsI18n.language === 'ar');
            itemLabel = getInventoryItemDisplayLabel(invItem);
            maxCount = Number(invItem.count) || 1;
            itemImg = "images/items/" + (invItem.item || "").toLowerCase() + ".png";
            itemId = invItem.itemId;
            itemName = invItem.item;
        } else {
            itemLabel = clicked_name || "Item";
            itemImg = "images/items/" + (clicked_name || "").toLowerCase() + ".png";
        }
    }

    if (isPersonalItem(itemName)) {
        return;
    }

    activeGiveItem = {
        id: itemId,
        name: itemName,
        type: itemType,
        label: itemLabel,
        image: itemImg,
        maxCount: maxCount,
        metaData: clicked_meta || {}
    };

    var previewImg = document.getElementById("give-player-item-img");
    var previewName = document.getElementById("give-player-item-name");
    var previewCount = document.getElementById("give-player-item-count");
    var qtySection = document.getElementById("give-player-quantity-section");
    var qtyInput = document.getElementById("give-player-quantity-input");
    var win = document.getElementById("give-player-window");

    // One of something: nothing to choose, go straight to picking the player.
    if (activeGiveItem.type === "weapon" || activeGiveItem.maxCount <= 1) {
        startGivePlayerPick(1);
        return;
    }

    if (previewImg) previewImg.src = activeGiveItem.image;
    if (previewName) previewName.textContent = activeGiveItem.label;
    if (previewCount) {
        var availTxt = (typeof JrsI18n !== 'undefined') ? JrsI18n.t("inv_available", "Available") : "Available";
        previewCount.textContent = (availTxt + ": " + activeGiveItem.maxCount);
    }

    if (qtySection && qtyInput) {
        qtySection.style.display = "block";
        qtyInput.value = "1";
        qtyInput.max = String(activeGiveItem.maxCount);
        qtyInput.min = "1";
    }

    if (win) {
        win.style.display = "flex";
    }
}

// Give = choose the amount (only when there is more than one), then the bag
// closes and the player picks the recipient by clicking the marker over their
// head. The item is sent only after that click.
var pendingGiveRequest = null;

function readGiveAmount() {
    var qtyInput = document.getElementById("give-player-quantity-input");
    var amount = 1;
    if (qtyInput && activeGiveItem && activeGiveItem.maxCount > 1 && activeGiveItem.type !== "weapon") {
        amount = Math.floor(Number(qtyInput.value)) || 1;
        if (amount < 1) amount = 1;
        if (amount > activeGiveItem.maxCount) amount = activeGiveItem.maxCount;
    }
    return amount;
}

function confirmGiveAmountAndPickPlayer() {
    if (!activeGiveItem) {
        closeGivePlayerWindow();
        return;
    }
    startGivePlayerPick(readGiveAmount());
}

function startGivePlayerPick(amount) {
    if (!activeGiveItem || giveTransferPending) return;
    pendingGiveRequest = {
        item: activeGiveItem.id,
        count: Math.max(1, Math.floor(Number(amount)) || 1),
        is: activeGiveItem.type,
        metaData: activeGiveItem.metaData || {},
        itemName: activeGiveItem.name
    };
    givePlayerSelectorPurpose = "single";
    giveItemEnabled = true;
    const win = document.getElementById("give-player-window");
    if (win) win.style.display = "none";
    activeGiveItem = null;
    hideExpandedInfoNow();
    $.post(jrsInventoryUrl + '/give_pick_player', JSON.stringify({
        itemName: pendingGiveRequest.itemName,
        is: pendingGiveRequest.is
    }));
}

function sendPendingGiveTo(targetId) {
    const request = pendingGiveRequest;
    pendingGiveRequest = null;
    if (!request) {
        giveTransferPending = false;
        return false;
    }
    $.post(jrsInventoryUrl + '/give_checked_item', JSON.stringify({
        id: Number(targetId),
        item: request.item,
        count: request.count,
        is: request.is,
        metaData: request.metaData,
        itemName: request.itemName
    })).always(function() {
        giveTransferPending = false;
    });
    return true;
}

function renderGivePlayerList(players) {
    const list = document.getElementById("give-player-list");
    const win = document.getElementById("give-player-window");
    if (!list) return;

    list.innerHTML = "";
    if (!players || players.length === 0) {
        var emptyTxt = (typeof JrsI18n !== 'undefined') ? JrsI18n.t("inventory_no_player_nearby", "NO PLAYER NEARBY") : "NO PLAYER NEARBY";
        list.innerHTML = '<div class="give-player-empty">' + emptyTxt + '</div>';
        if (win) win.style.display = "flex";
        return;
    }

    players.forEach(function(player) {
        const btn = document.createElement("button");
        btn.type = "button";
        var distStr = (player.distance !== undefined) ? " (" + player.distance + "m)" : "";
        btn.textContent = "[" + player.id + "] " + player.name + distStr;
        btn.onclick = function() {
            confirmGiveToPlayer(player.id);
        };
        list.appendChild(btn);
    });

    if (win) win.style.display = "flex";
}

function confirmGiveToPlayer(targetId) {
    if (!activeGiveItem) {
        closeGivePlayerWindow();
        return;
    }
    const selectedTarget = Number(targetId);
    if (!Number.isFinite(selectedTarget) || selectedTarget <= 0) return;

    var qtyInput = document.getElementById("give-player-quantity-input");
    var amount = 1;
    if (qtyInput && activeGiveItem.maxCount > 1 && activeGiveItem.type !== "weapon") {
        amount = Math.floor(Number(qtyInput.value)) || 1;
        if (amount < 1) amount = 1;
        if (amount > activeGiveItem.maxCount) amount = activeGiveItem.maxCount;
    }

    giveTransferPending = true;
    $.post(jrsInventoryUrl + '/give_checked_item', JSON.stringify({
        id: selectedTarget,
        item: activeGiveItem.id,
        count: amount,
        is: activeGiveItem.type,
        metaData: activeGiveItem.metaData,
        itemName: activeGiveItem.name
    })).always(function() {
        giveTransferPending = false;
    });

    closeGivePlayerWindow();
    display2(false);
}

function closeGivePlayerWindow() {
    const win = document.getElementById("give-player-window");
    if (win) win.style.display = "none";
    activeGiveItem = null;
}

function adjustGiveQuantity(delta) {
    var qtyInput = document.getElementById("give-player-quantity-input");
    if (!qtyInput || !activeGiveItem) return;
    var current = parseInt(qtyInput.value, 10) || 1;
    var next = current + delta;
    if (next < 1) next = 1;
    if (next > activeGiveItem.maxCount) next = activeGiveItem.maxCount;
    qtyInput.value = next;
}

function setGiveQuantityMax() {
    var qtyInput = document.getElementById("give-player-quantity-input");
    if (!qtyInput || !activeGiveItem) return;
    qtyInput.value = activeGiveItem.maxCount;
}
function transferToPlayer(targetId) {
    if (isPersonalItem(selectedPersonalItemName())) return;
    const selectedTarget = Number(targetId);
    if (!Number.isFinite(selectedTarget) || selectedTarget <= 0) return;
    givePlayerSelectorActive = false;
    giveItemEnabled = false;
    clearGivePlayerSelectors();
    if (isCurrencyType(dragged_item_inv)) {
        if (dragged_item_inv === 'money') {
            $.post(jrsInventoryUrl + '/transferToPlayer', JSON.stringify({target:selectedTarget, weapon:false, item: "money", count: moneysd, container_id:id_container, size:count_sinventory}));
        } else if (dragged_item_inv === 'gold') {
            $.post(jrsInventoryUrl + '/transferToPlayer', JSON.stringify({target:selectedTarget, weapon:false, item: "gold", count: goldsd, container_id:id_container, size:count_sinventory}));
        } else if (dragged_item_inv === 'dirtymoney') {
            $.post(jrsInventoryUrl + '/transferToPlayer', JSON.stringify({target:selectedTarget, weapon:false, item: "dirtymoney", count: dirtymoneysd, container_id:id_container, size:count_sinventory}));
        }
    } else if (dragged_witem_inv !== undefined && wtable_inv && wtable_inv[dragged_witem_inv]) {
        $.post(jrsInventoryUrl + '/transferToPlayer', JSON.stringify({target:selectedTarget, weapon:true, id: wtable_inv[dragged_witem_inv].id, item: wtable_inv[dragged_witem_inv].name, container_id:id_container, used:wtable_inv[dragged_witem_inv].used, size:count_sinventory}));
    } else if (dragged_item_inv !== undefined && table_inv && table_inv[dragged_item_inv]) {
        $.post(jrsInventoryUrl + '/transferToPlayer', JSON.stringify({target:selectedTarget, weapon:false, itemId: table_inv[dragged_item_inv].itemId, item: table_inv[dragged_item_inv].item, count: table_inv[dragged_item_inv].count, container_id:id_container, size:count_sinventory, limit:table_inv[dragged_item_inv].limit, metaData:table_inv[dragged_item_inv].metaData, countInInventory:table_inv[dragged_item_inv].count}));
    }
    drag_to_other = false;
    display2(false);
}

// storageIndex: the double-clicked stack. Drags leave it undefined and use
// dragged_stor_inv, which the drag start sets.
function transfer_from_storage(targetInventorySlot, storageIndex) {
    const index = storageIndex !== undefined && storageIndex !== null ? storageIndex : dragged_stor_inv;
    const entry = storage_inv && storage_inv[index];
    if (!entry) return;

    const normalizedTargetSlot = Number(targetInventorySlot);
    const requestedInventorySlot = Number.isInteger(normalizedTargetSlot) && normalizedTargetSlot > 0
        ? normalizedTargetSlot
        : null;

    jrsQueueStorageTransfer('transfer_from_storage', {
        item: entry.item,
        itemId: entry.itemId,
        metaData: entry.metaData,
        weapon: entry.weapon,
        count: entry.count,
        container_id: id_container,
        limit: entry.limit,
        countInInventory: entry.count,
        used: entry.used,
        storageSlot: entry.slot,
        targetInventorySlot: requestedInventorySlot,
        fullStack: jrsShiftHeld === true
    });
    drag_to_normal = false;
}

// Storage capacity readout. Mirrors the player panel's WEIGHT row + bar exactly
// so both sides of the transfer screen read the same way.
var storageTitle = "";
var storageName = "";

function updateStorageStatus() {
    var used = Math.round((Number(count_sinventory) || 0) * 100) / 100;
    var max = Number(size) || 0;

    var text = document.getElementById("storageWeightText");
    if (text) {
        text.innerHTML = used + " / " + max + " " + JrsI18n.t("inv_kg_unit", "KG");
    }

    var bar = document.getElementById("storageWeightBar");
    var fill = document.getElementById("storageWeightFill");
    if (fill) {
        var percent = max > 0 ? (used / max) * 100 : 0;
        if (percent < 0) percent = 0;
        if (percent > 100) percent = 100;
        fill.style.width = percent + "%";
        if (bar) {
            bar.classList.toggle("weight-warning", percent >= inventoryWeightWarningPercent && percent < inventoryWeightCriticalPercent);
            bar.classList.toggle("weight-critical", percent >= inventoryWeightCriticalPercent);
        }
    }

    var label = document.getElementById("storageContainerLabel");
    var name = document.getElementById("storageContainerName");
    var sideLabel = document.getElementById("storage-side-label");
    if (containerMode === "robbery" || containerMode === "admin_search") {
        if (label) label.innerHTML = JrsI18n.t("inv_player", "PLAYER");
        // textContent: this is a player's own (Steam) name. As HTML it ran
        // script in the robber's / admin's inventory UI.
        if (name) name.textContent = String(robberyTargetName || storageName || "-");
        if (sideLabel) sideLabel.innerHTML = JrsI18n.t("inv_player_inventory", "PLAYER INVENTORY");
    } else {
        // Real storage name instead of the raw database id (e.g. jrs_stash:1:2:3).
        if (label) label.innerHTML = JrsI18n.t("inv_container", "CONTAINER");
        if (name) name.textContent = storageName || storageTitle || JrsI18n.t("inv_storage", "STORAGE");
        if (sideLabel) sideLabel.textContent = storageName || storageTitle || JrsI18n.t("inv_storage", "STORAGE");
    }
}

function loadstoragedata(strg_dt) {
    $("#expand_container").show();

    const tableBodyStorage = document.getElementById('expand_container');
    const STORAGE_COLUMNS = 5;
    const STORAGE_BASE_SLOTS = 20;
    let data_storage_Html = '';
    count_sinventory = 0;

    // Keep legacy category order only for entries that do not yet have a saved slot.
    const orderedIndexes = [];
    const pushBy = function(predicate) {
        for (let i = 0; i < strg_dt.length; i++) {
            if (predicate(strg_dt[i])) orderedIndexes.push(i);
        }
    };
    pushBy(v => v.weapon == false && v.item === 'money');
    pushBy(v => v.weapon == false && v.item === 'gold');
    pushBy(v => v.weapon == false && v.item === 'dirtymoney');
    pushBy(v => v.weapon == false && v.item !== 'money' && v.item !== 'gold' && v.item !== 'dirtymoney');
    pushBy(v => v.weapon == true && v.item !== 'money' && v.item !== 'gold' && v.item !== 'dirtymoney');

    const slotMap = Object.create(null);
    const usedSlots = new Set();
    let fallbackSlot = 1;

    function nextFreeSlot() {
        while (usedSlots.has(fallbackSlot)) fallbackSlot++;
        const result = fallbackSlot;
        usedSlots.add(result);
        fallbackSlot++;
        return result;
    }

    // Honor persisted slots first. Invalid/duplicate legacy slots are assigned safely.
    for (const i of orderedIndexes) {
        const entry = strg_dt[i];
        let slot = Number(entry && entry.slot);
        if (!Number.isInteger(slot) || slot <= 0 || usedSlots.has(slot)) {
            slot = nextFreeSlot();
        } else {
            usedSlots.add(slot);
        }
        entry.slot = slot;
        slotMap[slot] = i;
    }

    const occupiedSlots = Object.keys(slotMap).map(Number);
    const highestUsedSlot = occupiedSlots.length ? Math.max(...occupiedSlots) : 0;
    // Always leave at least one usable empty target after a completely full row.
    const minimumWithTarget = highestUsedSlot > 0 ? highestUsedSlot + 1 : STORAGE_BASE_SLOTS;
    const totalSlots = Math.max(
        STORAGE_BASE_SLOTS,
        Math.ceil(minimumWithTarget / STORAGE_COLUMNS) * STORAGE_COLUMNS
    );

    for (let slot = 1; slot <= totalSlots; slot++) {
        const i = slotMap[slot];
        if (i === undefined) {
            data_storage_Html +=
                '<div class="empty-slot storage-empty-slot" data-origin="storage" data-storage-slot="' + slot + '" data-slot="' + slot + '" title="Storage slot ' + slot + '">' +
                    '<span class="storage-slot-number">' + slot + '</span>' +
                '</div>';
            continue;
        }

        const storageItem = strg_dt[i];
        const label = storageItem.label || storageItem.item || '';
        let image = storageItem.item;
        let details = '';
        let durabilityHtml = '';

        if (storageItem.weapon == true) {
            if (containerMode !== "robbery") count_sinventory += 1;
            image = storageItem.count;
        } else {
            const itemLimit = parseFloat(storageItem.limit) || 0;
            const itemCount = parseFloat(storageItem.count) || 0;
            const weight_item = itemCount * itemLimit;
            count_sinventory += weight_item;

            if (isCurrencyType(storageItem.item)) {
                details = escapeDescriptionHtml(storageItem.count);
            } else {
                const durabilityValue = getItemDurabilityPercent(storageItem);
                if (durabilityValue !== null) {
                    durabilityHtml = '<progress class="storage-durability" max="100" value="' + durabilityValue + '"></progress>';
                }
                details = escapeDescriptionHtml(storageItem.count) + '<br>' + (Math.round(weight_item * 100) / 100) + ' kg';
            }
        }

        const doubleClickAction = containerMode === "robbery" ? "" : ' ondblclick="transfer_from_storage(null, ' + i + ')"';
        data_storage_Html +=
            '<div class="item storage-slot" data-origin="storage" data-storage-index="' + i + '" data-storage-slot="' + slot + '" data-slot="' + slot + '" data-content="' + escapeDescriptionHtml(label) + '" title="Storage slot ' + slot + '">' +
                '<span class="storage-slot-number">' + slot + '</span>' +
                '<div id="' + i + '" class="item-content"' + doubleClickAction + ' onmouseenter="change_name_other(' + i + ')">' +
                    '<img loading="lazy" decoding="async" src="images/items/' + escapeDescriptionHtml(image) + '.png" width="60" height="60" id="item">' +
                    durabilityHtml +
                    (details !== '' ? '<div class="bottom-right" id="count_' + i + '">' + details + '</div>' : '') +
                '</div>' +
            '</div>';
    }

    jrsSetWidgetHtml(tableBodyStorage, data_storage_Html);
    makeStorageItemsDraggable();
    bindStorageSlotDroppables();
    filterTextInput();
    updateStorageStatus();

    // Legacy safety unlock, now only when nothing is in flight or queued:
    // it used to fire mid-transfer and let the next drop hit 'busy'.
    setTimeout(() => {
        if (jrsStorageTransferBusy() || jrsStorageQueue.length) return;
        blockMe = false;
        $.post(jrsInventoryUrl + '/cancelBlock');
    }, 200);
}

var grid0Hover = document.getElementById('grid0');
if (grid0Hover) {
    grid0Hover.addEventListener("mouseenter", function() { drag_to_other = false; drag_to_normal = true; });
}
var grid1Hover = document.getElementById('grid1');
if (grid1Hover) {
    grid1Hover.addEventListener("mouseenter", function() { drag_to_other = false; drag_to_normal = true; });
}


document.getElementById("container_other").addEventListener("mouseenter", function() {drag_to_other=true,drag_to_normal=false;});
document.getElementById("expand_container").addEventListener("mouseenter", function() {drag_to_other=true,drag_to_normal=false;});
document.getElementById("container").addEventListener("mouseenter", function() {drag_to_other=false ,drag_to_normal=true;});

$(document).on("mouseleave", "#expand_container .item, #expand_container .empty-slot", function() {
    if (!dragged && !isInContext && !giveItemEnabled) {
        document.getElementById("id05").innerHTML = "";
        reset_button();
    }
});

$(document).on("click", "#tableData .item", function(event) {
    if (id_container === 0 || (!event.shiftKey && !event.ctrlKey)) return;
    if (Date.now() - jrsLastDragEndAt < 400) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    quickTransferInventorySlot(this, event.ctrlKey === true);
});

$(document).on("click", "#expand_container .storage-slot", function(event) {
    if (id_container === 0 || (!event.shiftKey && !event.ctrlKey)) return;
    if (Date.now() - jrsLastDragEndAt < 400) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    quickTransferStorageSlot(this, event.ctrlKey === true);
});

function removeAllChildNodes(parent) {
    while (parent.firstChild) {
        parent.removeChild(parent.firstChild);
    }
}
let clothingSlotDefinitions = [];
let clothingSlotState = {};
let clothingIntegrationAvailable = false;

function clothingSlotDescription(definition, state) {
    if (!clothingIntegrationAvailable) return JrsI18n.t("inv_clothing_desc_unavailable", "Clothing system is unavailable");
    if (!state || state.available !== true) return JrsI18n.t("inv_clothing_desc_none", "No clothing from this category is currently owned or worn");
    return state.equipped === true
        ? JrsI18n.t("inv_clothing_desc_equipped", "Currently equipped - click to remove")
        : JrsI18n.t("inv_clothing_desc_unequipped", "Currently unequipped - click to wear");
}

function getClothingSlotLabel(definition, key) {
    if (!definition) return key || "";
    const isAr = (typeof JrsI18n !== 'undefined' && JrsI18n.language === 'ar');
    if (isAr && definition.ar_label) return definition.ar_label;
    const i18nKey = "inv_clothing_" + String(key || "");
    const translated = JrsI18n.t(i18nKey, "");
    if (translated && translated !== i18nKey) return translated;
    return String(definition.label || key || "");
}

function renderClothingSlots(definitions, state, integrationAvailable) {
    clothingSlotDefinitions = Array.isArray(definitions) ? definitions : [];
    clothingSlotState = state && typeof state === "object" ? state : {};
    clothingIntegrationAvailable = integrationAvailable === true;

    const grid = document.getElementById("clothingSlotsGrid");
    const status = document.getElementById("clothing-integration-status");
    if (!grid) return;
    grid.innerHTML = "";

    if (status) {
        status.textContent = "";
        status.classList.remove("offline");
    }

    clothingSlotDefinitions.forEach(function(definition) {
        if (!definition || !definition.key) return;
        const key = String(definition.key);
        const slotState = clothingSlotState[key] || {};
        const available = clothingIntegrationAvailable && slotState.available === true;
        const equipped = slotState.equipped === true;
        const description = clothingSlotDescription(definition, slotState);
        const label = getClothingSlotLabel(definition, key);

        const button = document.createElement("button");
        button.type = "button";
        button.className = "clothing-slot";
        button.dataset.clothingSlot = key;
        button.title = label + " - " + description;
        button.setAttribute("aria-label", button.title);
        button.setAttribute("aria-pressed", equipped ? "true" : "false");
        button.classList.toggle("active-clothe", equipped);
        button.classList.toggle("clothing-slot-unavailable", !available);

        const image = document.createElement("img");
        image.src = "images/clothes/" + String(definition.icon || "clothing.png");
        image.className = "cloth-image";
        image.alt = label;
        button.appendChild(image);

        const indicator = document.createElement("span");
        indicator.className = "clothing-state-indicator";
        button.appendChild(indicator);

        button.addEventListener("mouseenter", function() {
            const name = document.getElementById("name");
            const desc = document.getElementById("desc");
            if (name) name.textContent = label;
            if (desc) desc.textContent = description;
        });
        button.addEventListener("mouseleave", clean_clothe);
        button.addEventListener("click", function() { put_clothe(key); });
        grid.appendChild(button);
    });
}

function put_clothe(slotKey){
    const key = String(slotKey || "");
    const button = Array.from(document.querySelectorAll("[data-clothing-slot]")).find(function(element) {
        return element.dataset.clothingSlot === key;
    });
    if (!key || (button && button.classList.contains("clothing-slot-pending"))) return;
    if (button) button.classList.add("clothing-slot-pending");

    $.post(jrsInventoryUrl + '/put_clothe', JSON.stringify({ slot: key }))
        .always(function() {
            if (button) button.classList.remove("clothing-slot-pending");
        });
}
function clean_clothe() {
    document.getElementById("name").innerHTML = "";
    document.getElementById("desc").innerHTML = "";
}

function Show_Items() {


    $("#weightText").text(
        count_inventory + " / " + max_count_inventory + " " + JrsI18n.t("inv_kg_unit", "KG")
    );

    $("#slotText").text(
        count_winventory + " / " + max_count_winventory
    );

    let percent = (count_inventory / max_count_inventory) * 100;

    if (percent > 100)
        percent = 100;

    $("#weightFill").css("width", percent + "%");

    $("#tableData").show();

}

function escapeDescriptionHtml(value) {
    return String(value == null ? "" : value)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
}

function formatInventoryWeightValue(count, limit) {
    const stackWeight = (Number(count) || 0) * (Number(limit) || 0);
    const rounded = Math.round(stackWeight * 100) / 100;
    return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
}

function buildDescriptionMetaLines(entry, type, source) {
    const lines = [];
    if (!entry || typeof entry !== "object") return lines;

    if (type === "weapon") {
        lines.push(JrsI18n.t("inv_status", "STATUS") + ": " + ((entry.used == 1) ? JrsI18n.t("inv_equipped", "Equipped") : JrsI18n.t("inv_stored", "Stored")));
        if (entry.serial_number || entry.serial) {
            lines.push(JrsI18n.t("inv_serial", "SERIAL") + ": " + String(entry.serial_number || entry.serial));
        }
        if (entry.conditionlevel !== undefined && entry.conditionlevel !== null) {
            const condition = getWeaponConditionPercent(entry);
            if (condition !== null) lines.push(JrsI18n.t("inv_condition", "CONDITION") + ": " + Math.round(condition) + "%");
        }
        return lines;
    }

    if (entry.count !== undefined) lines.push(JrsI18n.t("inv_amount", "AMOUNT") + ": " + String(entry.count));
    if (entry.limit !== undefined) lines.push(JrsI18n.t("inv_weight", "WEIGHT") + ": " + formatInventoryWeightValue(entry.count, entry.limit) + " " + JrsI18n.t("inv_kg_unit", "KG"));
    if (entry.category) lines.push(JrsI18n.t("inv_category", "CATEGORY") + ": " + JrsI18n.t("inv_cat_" + String(entry.category).toLowerCase(), String(entry.category).toUpperCase()));
    const durabilityValue = getItemDurabilityPercent(entry);
    if (durabilityValue !== null) lines.push(JrsI18n.t("inv_durability", "DURABILITY") + ": " + Math.round(durabilityValue) + "%");
    if (source === "storage" && entry.slot) lines.push(JrsI18n.t("inv_storage_slot", "STORAGE SLOT") + ": " + String(entry.slot));
    return lines;
}

function renderDescriptionCard(title, description, metaLines, sourceLabel) {
    const nameEl = document.getElementById("name");
    const descEl = document.getElementById("desc");
    if (!nameEl || !descEl) return;

    const safeTitle = escapeDescriptionHtml(title || JrsI18n.t("inv_fallback_item", "Item"));
    const safeDescription = escapeDescriptionHtml(description || "");
    const rows = Array.isArray(metaLines) ? metaLines.filter(Boolean) : [];
    const safeSource = escapeDescriptionHtml(sourceLabel || JrsI18n.t("inv_source_inventory", "INVENTORY"));

    // The floating hover tooltip replaces this bottom detail bar, so keep it
    // hidden. (It still populates name/desc for any code that reads them.)
    const detailsEl = document.getElementById("item-details");
    if (detailsEl) detailsEl.style.setProperty("display", "none", "important");
    nameEl.innerHTML = '<span class="jrs-desc-title">' + safeTitle + '</span><span class="jrs-desc-source">' + safeSource + '</span>';
    descEl.innerHTML =
        '<div class="jrs-desc-card">' +
            '<div class="jrs-desc-main' + (safeDescription ? '' : ' empty') + '">' + (safeDescription || JrsI18n.t('inv_no_description_available', 'No description available.')) + '</div>' +
            (rows.length ? '<div class="jrs-desc-meta">' + rows.map(function(row) { return '<span>' + escapeDescriptionHtml(row) + '</span>'; }).join('') + '</div>' : '') +
        '</div>';
}

function setDescriptionForInventoryItem(entry) {
    if (!entry) return;
    const isAr = (typeof JrsI18n !== 'undefined' && JrsI18n.language === 'ar');
    const displayLabel = getInventoryItemDisplayLabel(entry);
    const displayDesc = (isAr && entry.description_ar) ? entry.description_ar : (entry.description || "");
    renderDescriptionCard(displayLabel, displayDesc, buildDescriptionMetaLines(entry, "item", "inventory"), JrsI18n.t("inv_source_inventory", "INVENTORY"));
}

function setDescriptionForWeapon(entry) {
    if (!entry) return;
    const isAr = (typeof JrsI18n !== 'undefined' && JrsI18n.language === 'ar');
    const displayLabel = (isAr && entry.label_ar) ? entry.label_ar : (entry.label || entry.name || JrsI18n.t("inv_fallback_weapon", "Weapon"));
    renderDescriptionCard(displayLabel, entry.used == 1 ? config.language[26].text : config.language[27].text, buildDescriptionMetaLines(entry, "weapon", "inventory"), JrsI18n.t("inv_source_weapon", "WEAPON"));
}

function setDescriptionForCurrency(title, description, balance) {
    renderDescriptionCard(title, description, [JrsI18n.t("inv_balance", "BALANCE") + ": " + String(balance)], JrsI18n.t("inv_source_currency", "CURRENCY"));
}

function setDescriptionForStorageItem(entry) {
    if (!entry) return;
    const isAr = (typeof JrsI18n !== 'undefined' && JrsI18n.language === 'ar');
    const displayLabel = getInventoryItemDisplayLabel(entry);
    const displayDesc = (isAr && entry.description_ar) ? entry.description_ar : (entry.description || JrsI18n.t("inv_stored_item_ready", "Stored item ready to transfer."));
    renderDescriptionCard(displayLabel, displayDesc, buildDescriptionMetaLines(entry, entry.weapon == true ? "weapon" : "item", "storage"), JrsI18n.t("inv_source_storage", "STORAGE"));
}

function reset_button(){
    // Runs on every slot mouseleave; skip DOM writes when already cleared.
    const nameEl = document.getElementById("name");
    const descEl = document.getElementById("desc");
    if (nameEl && nameEl.firstChild) nameEl.innerHTML = '';
    if (descEl && descEl.firstChild) descEl.innerHTML = '';
    const detailsEl = document.getElementById("item-details");
    if (detailsEl) detailsEl.style.setProperty("display", "none", "important");
}
function CloseList() {
    removeAllChildNodes(table_for_delete);
}
//
function GiveItemNow(id_player, item, count,itemName){
    if (isPersonalItem(itemName)) return;
    removeAllChildNodes(table_for_delete);
    if (item == "money") {
        $.post(jrsInventoryUrl + '/give_checked_item', JSON.stringify({ id: id_player, item: item, count: count, is:clicked_type }));
    } else if (item == "gold") {
            $.post(jrsInventoryUrl + '/give_checked_item', JSON.stringify({ id: id_player, item: item, count: count, is:clicked_type }));
    } else if (item == "dirtymoney") {
            $.post(jrsInventoryUrl + '/give_checked_item', JSON.stringify({ id: id_player, item: item, count: count, is:clicked_type }));
    } else {
        $.post(jrsInventoryUrl + '/give_checked_item', JSON.stringify({ id: id_player, item: item, count: Math.floor(count), is:clicked_type, metaData:clicked_meta, itemName:itemName }));
    }
}


function setContextInfoForSlot(slotType, clickedid) {
    try {
        if (slotType === "weapon") {
            const weapon = wtable_inv[Number(clickedid)];
            if (!weapon) return;
            setDescriptionForWeapon(weapon);
            dragged_witem_inv = Number(clickedid);
            dragged_item_inv = undefined;
            return;
        }
        if (slotType === "money") {
            setDescriptionForCurrency(config.language[22].text, config.language[23].text, moneysd + " $");
            return;
        }
        if (slotType === "gold") {
            setDescriptionForCurrency(config.language[24].text, config.language[25].text, goldsd);
            return;
        }
        if (slotType === "dirtymoney") {
            setDescriptionForCurrency(config.language[33].text, config.language[34].text, dirtymoneysd + " $");
            return;
        }
        const item = table_inv[Number(clickedid)];
        if (!item) return;
        setDescriptionForInventoryItem(item);
        dragged_item_inv = Number(clickedid);
        dragged_witem_inv = undefined;
    } catch (e) {}
}

$(document).on("contextmenu", "#tableData .item-content, #currency-panel .item-content", function(evt) {
    evt.preventDefault();

    const clickedid = $(this).attr('id');
    const slotElement = $(this).closest('.item');
    const slotType = String(slotElement.attr('data-type') || 'item');
    setContextInfoForSlot(slotType, clickedid);
    isInContext = true;
    const { clientX: mouseX, clientY: mouseY } = evt;

    clicked_name = "";
    clicked_meta = {};

    if (slotType === "weapon") {
        const weapon = wtable_inv[Number(clickedid)];
        if (!weapon) return;
        clicked_id = weapon.id;
        clicked_name = weapon.name;
        clicked_type = "weapon";
    } else if (slotType === "money") {
        clicked_id = "money";
        clicked_name = "money";
        clicked_type = "money";
    } else if (slotType === "gold") {
        clicked_id = "gold";
        clicked_name = "gold";
        clicked_type = "gold";
    } else if (slotType === "dirtymoney") {
        clicked_id = "dirtymoney";
        clicked_name = "dirtymoney";
        clicked_type = "dirtymoney";
    } else {
        const item = table_inv[Number(clickedid)];
        if (!item) return;
        clicked_name = item.item;
        clicked_id = item.itemId;
        clicked_meta = item.metaData || {};
        clicked_type = "item";
    }

    updateContextSplitButton();
    updateContextPinButton();
    updateContextSerialButton();
    updateContextDropButton();
    contextMenu.style.top = `${mouseY}px`;
    contextMenu.style.left = `${mouseX}px`;
    contextMenu.classList.add("visible");
})

 scope.addEventListener("click", (e) => {
    if (e.target.offsetParent != contextMenu ) {
        table_for_delete.classList.remove("visible");
        contextMenu.classList.remove("visible");
        setTimeout(() => {  
            isInContext = false
        }, 100);
    }
  });

  

$(document).on("click", "#multiClearButton", function(e) {
    e.preventDefault();
    deleteMultiSelection();
});

$(document).on("click", "#tableData .item", function(event) {
    if (!multiSelectMode) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    toggleMultiSelectionElement(this);
    return false;
});

// Expanded item/weapon details are click-to-view only.
// A normal hover no longer opens the information panel.
$(document).on("click", "#tableData .item", function(event) {
    // Multi-select owns the click while that mode is enabled.
    if (multiSelectMode) return;

    // Only react to a normal left mouse click.
    if (event.which && event.which !== 1) return;

    // Ignore the click that can be emitted at the end of a drag.
    if ($(this).hasClass("ui-draggable-dragging")) return;

    showExpandedInfoForSlot(this, event);
});

// Show the floating details box as soon as the pointer enters an item slot.
$(document).on("mouseenter", "#tableData .item", function(event) {
    if (dragged || isInContext || multiSelectMode) return;
    showExpandedInfoForSlot(this, event);
});

// The details panel closes as soon as the pointer leaves the selected slot.
$(document).on("mouseleave", "#tableData .item", function() {
    // Short grace so crossing the gap into the next slot (or onto the box
    // itself for the serial copy button) does not blink the details box.
    if (dragged || isInContext || multiSelectMode) hideExpandedInfoNow();
    else scheduleExpandedInfoHide();
    // Clear the fixed item name/description as soon as the pointer leaves the slot.
    // Do not leave stale item details on screen after hover/drag.
    if (!dragged && !isInContext && !giveItemEnabled) {
        reset_button();
    }
});

$(document).on("dragstart mousedown", "#tableData .item", function() {
    hideExpandedInfoNow();
});

$(document).on("mouseenter", "#expanded-item-info", function() {
    if (lastExpandedInfoSlot) cancelExpandedInfoHide();
});
$(document).on("mouseleave", "#expanded-item-info", function() {
    if (lastExpandedInfoSlot) scheduleExpandedInfoHide();
});

$(document).on("mouseleave", "#container", function(event) {
    // The box now docks outside the bag: give the pointer a moment to reach
    // it (serial copy button) instead of closing the instant it leaves.
    const to = event.relatedTarget;
    if (to && to.closest && to.closest("#expanded-item-info")) cancelExpandedInfoHide();
    else if (lastExpandedInfoSlot && !dragged && !isInContext) scheduleExpandedInfoHide();
    else hideExpandedInfoNow();
    if (!dragged && !isInContext && !giveItemEnabled) {
        reset_button();
    }
});

function copyTextToClipboard(value) {
    const text = String(value || "").trim();
    if (!text || text === "-") return Promise.reject(new Error("missing_serial"));

    // Do not use navigator.clipboard inside RedM NUI. Chromium exposes it, but
    // the embedded page blocks it through Permissions Policy and prints an F8 warning.
    // Keep the entire copy operation inside the original click gesture.
    return new Promise(function(resolve, reject) {
        let copyNode = null;
        let previousFocus = document.activeElement;

        function cleanup() {
            try {
                const selection = window.getSelection ? window.getSelection() : null;
                if (selection) selection.removeAllRanges();
            } catch (_) {}

            if (copyNode && copyNode.parentNode) {
                copyNode.parentNode.removeChild(copyNode);
            }
            copyNode = null;

            if (previousFocus && typeof previousFocus.focus === "function") {
                try { previousFocus.focus(); } catch (_) {}
            }
        }

        function executeCopy() {
            try {
                return document.execCommand("copy") === true;
            } catch (_) {
                return false;
            }
        }

        try {
            // Input/textarea selection is the most reliable path in CEF/NUI.
            copyNode = document.createElement("textarea");
            copyNode.value = text;
            copyNode.setAttribute("autocomplete", "off");
            copyNode.setAttribute("autocorrect", "off");
            copyNode.setAttribute("autocapitalize", "off");
            copyNode.setAttribute("spellcheck", "false");
            copyNode.style.position = "fixed";
            copyNode.style.left = "0";
            copyNode.style.top = "0";
            copyNode.style.width = "2px";
            copyNode.style.height = "2px";
            copyNode.style.padding = "0";
            copyNode.style.margin = "0";
            copyNode.style.border = "0";
            copyNode.style.outline = "0";
            copyNode.style.opacity = "0.01";
            copyNode.style.zIndex = "-1";
            document.body.appendChild(copyNode);

            try { window.focus(); } catch (_) {}
            copyNode.focus();
            copyNode.select();
            copyNode.setSelectionRange(0, text.length);

            if (executeCopy()) {
                cleanup();
                resolve();
                return;
            }

            // Secondary CEF fallback: copy a selected contenteditable text node.
            cleanup();
            copyNode = document.createElement("div");
            copyNode.contentEditable = "true";
            copyNode.textContent = text;
            copyNode.style.position = "fixed";
            copyNode.style.left = "0";
            copyNode.style.top = "0";
            copyNode.style.width = "2px";
            copyNode.style.height = "2px";
            copyNode.style.opacity = "0.01";
            copyNode.style.overflow = "hidden";
            copyNode.style.zIndex = "-1";
            document.body.appendChild(copyNode);

            const range = document.createRange();
            range.selectNodeContents(copyNode);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);

            if (executeCopy()) {
                cleanup();
                resolve();
                return;
            }

            cleanup();
            reject(new Error("nui_copy_failed"));
        } catch (error) {
            cleanup();
            reject(error);
        }
    });
}

$(document).on("click", ".copy-weapon-serial", function(event) {
    event.preventDefault();
    event.stopPropagation();
    cancelExpandedInfoHide();

    const button = this;
    const serial = button.dataset.serial || button.textContent;
    const tooltip = button.closest("#expanded-item-info");
    const status = tooltip ? tooltip.querySelector(".expanded-info-copy-status") : null;

    copyTextToClipboard(serial).then(function() {
        if (status) status.textContent = JrsI18n.t("inventory_serial_copied_2", "SERIAL COPIED");
        button.classList.add("copied");
        playJrsUiSound("click");
        setTimeout(function() {
            button.classList.remove("copied");
            if (status) status.textContent = "";
        }, 1100);
    }).catch(function() {
        if (status) status.textContent = JrsI18n.t("inventory_copy_failed_2", "COPY FAILED");
        setTimeout(function() {
            if (status) status.textContent = "";
        }, 1100);
    });
});

function update_item(table_inv, name, count, money, gold, dirtymoney = dirtymoneysd) {
    renderCurrencyPanel(money, gold, dirtymoney);
    for (var i in table_inv) {
        if (table_inv[i].item == name) {
            const countElement = document.getElementById("count_"+i+"");
            if (countElement) countElement.innerHTML = count;
        }
    }
}

function change_name(id) {
    // The drag helper has pointer-events:none, so every slot the cursor
    // crosses while dragging fires mouseenter. Without this guard that
    // re-pointed dragged_item_inv at the hovered slot, and dropping a weapon
    // (or item) on the storage moved whatever was last hovered instead.
    if (dragged) return;
    id_for_use_item = -1;
    document.getElementById("id05").innerHTML = "";
    if (giveItemEnabled || isInContext) return;

    if (id == -1) {
        setDescriptionForCurrency(config.language[22].text, config.language[23].text, moneysd + " $");
        return;
    }
    if (id == -2) {
        setDescriptionForCurrency(config.language[24].text, config.language[25].text, goldsd);
        return;
    }
    if (id == -3) {
        setDescriptionForCurrency(config.language[33].text, config.language[34].text, dirtymoneysd + " $");
        return;
    }

    if (!table_inv[id]) return;
    id_for_use_item = id;
    id_for_use_weapon = -1;
    dragged_item_inv = id;
    dragged_witem_inv = undefined;
    setDescriptionForInventoryItem(table_inv[id]);
}

function change_name_wep(id) {
    id_for_use_weapon = id;
    id_for_use_item = -1;
    document.getElementById("id05").innerHTML = "";
    if (dragged || giveItemEnabled || isInContext || !wtable_inv[id]) return;
    dragged_witem_inv = id;
    dragged_item_inv = undefined;
    setDescriptionForWeapon(wtable_inv[id]);
}

function change_name_other(id) {
    id_for_use_weapon = -1;
    id_for_use_item = -1;
    if (dragged) return;

    if (id == -1) {
        document.getElementById("id05").innerHTML = config.language[22].text;
        setDescriptionForCurrency(config.language[22].text, config.language[23].text, moneysd + " $");
        return;
    }
    if (id == -2) {
        document.getElementById("id05").innerHTML = config.language[24].text;
        setDescriptionForCurrency(config.language[24].text, config.language[25].text, goldsd);
        return;
    }
    if (id == -3) {
        document.getElementById("id05").innerHTML = config.language[33].text;
        setDescriptionForCurrency(config.language[33].text, config.language[34].text, dirtymoneysd + " $");
        return;
    }
    if (!storage_inv[id]) return;
    document.getElementById("id05").textContent = storage_inv[id].label || storage_inv[id].item || "";
    dragged_stor_inv = id;
    setDescriptionForStorageItem(storage_inv[id]);
}

function change_active_weapon(id, state){
    for (var i in wtable_inv) {
        if (wtable_inv[i].id == id) {
            if (state !== undefined) {
                wtable_inv[i].used = Number(state) === 1 ? 1 : 0;
            } else if (wtable_inv[i].used == 1){
                wtable_inv[i].used = 0
            } else{
                wtable_inv[i].used = 1
            }
            if (wtable_inv[i].used == 1){
                document.getElementById("desc").innerHTML = config.language[26].text;
            } else{
                document.getElementById("desc").innerHTML = config.language[27].text;
            }
            let slotEl = document.querySelector('.item[data-slot="' + wtable_inv[i].slot + '"]');
            if (slotEl) {
                if (wtable_inv[i].used == 1) {
                    slotEl.classList.add('weapon-used');
                } else {
                    slotEl.classList.remove('weapon-used');
                }
            }
        }
    }
}
function UseItem(id) {
    if (multiSelectMode) return;
    if (id_container === 0) {
        const entry = table_inv && table_inv[id];
        if (entry) {
            $.post(jrsInventoryUrl + '/use_item', JSON.stringify({ item: entry.item, id: entry.itemId }));
        }
    } else {
        transfer_to_storage(null, { kind: "item", index: Number(id) });
    }
}

function UseWeapon(id, model) {
    if (multiSelectMode) return;
    if (id_container === 0) {
        $.post(jrsInventoryUrl + '/use_UseWeapon', JSON.stringify({ id: id, model:model }));
    } else {
        // id is the weapon's DB id; storage moves need its wtable_inv index.
        let index = null;
        for (const key in wtable_inv) {
            if (wtable_inv[key] && String(wtable_inv[key].id) === String(id)) { index = Number(key); break; }
        }
        if (index === null) return;
        transfer_to_storage(null, { kind: "weapon", index: index });
    }
}

function submitInputData() {
    // Read the amount the player typed.
    var count = parseInt(document.getElementById('input_size').value) || 1;
    var type = document.getElementById('input_type').value;

    // A "drop" means the item was dragged onto the bin.
    if (type === "drop") {
        // run the original drop handler and tell the server at once
        DropItem(count); 
    }
    
    // hide the quantity prompt when done
    document.getElementById("input_data").style.display = "none";
}

function GiveItem(count) {
    contextMenu.classList.remove("visible");
    if (count !== 0) {
        $.post(jrsInventoryUrl + '/give_item', JSON.stringify({ item: clicked_id, count: count, metaData:clicked_meta, itemName:clicked_name }));
    }
}


function selectedDropMaximum() {
    if (clicked_type === "money" || clicked_type === "gold" || clicked_type === "dirtymoney") {
        return Math.max(0, Math.floor(getCurrencyBalance(clicked_type)));
    }
    if (clicked_type === "valuable" || clicked_type === "weapon") return 1;
    if (dragged_item_inv !== undefined && table_inv[dragged_item_inv]) {
        return Math.max(1, Math.floor(Number(table_inv[dragged_item_inv].count) || 1));
    }
    return 1;
}

function openDropFromContext() {
    if (!clicked_id || clicked_id === "") return;
    if (isPersonalItem(selectedPersonalItemName())) return;
    contextMenu.classList.remove("visible");
    const maxCount = selectedDropMaximum();
    if (maxCount <= 1 || clicked_type === "valuable" || clicked_type === "weapon") {
        DropItem(1);
        return;
    }
    showGroundAmount(maxCount);
}

function updateContextDropButton() {
    const button = document.getElementById("contextDropButton");
    if (!button) return;
    button.style.display = (clicked_id && !isPersonalItem(selectedPersonalItemName())) ? "block" : "none";
}

function Show_Weap() {
    contextMenu.classList.remove("visible");
    $.post(jrsInventoryUrl + '/show_weapon', JSON.stringify({}));
}


function normalizeMetadataForMerge(value) {
    if (Array.isArray(value)) {
        return value.map(normalizeMetadataForMerge);
    }

    if (value && typeof value === "object") {
        const normalized = {};
        Object.keys(value).sort().forEach(function(key) {
            normalized[key] = normalizeMetadataForMerge(value[key]);
        });
        return normalized;
    }

    return value;
}

function inventoryMetadataMatches(first, second) {
    try {
        return JSON.stringify(normalizeMetadataForMerge(first || {})) ===
            JSON.stringify(normalizeMetadataForMerge(second || {}));
    } catch (error) {
        return false;
    }
}

function tryMergeInventoryStacks(sourceElement, targetElement) {
    if (!sourceElement || !targetElement) return false;
    if (sourceElement.attr("data-type") !== "item" || targetElement.attr("data-type") !== "item") {
        return false;
    }

    const sourceIndex = Number(sourceElement.attr("data-index"));
    const targetIndex = Number(targetElement.attr("data-index"));
    const sourceItem = table_inv[sourceIndex];
    const targetItem = table_inv[targetIndex];

    if (!sourceItem || !targetItem) return false;
    if (String(sourceItem.item) !== String(targetItem.item)) return false;
    if (!inventoryMetadataMatches(sourceItem.metaData, targetItem.metaData)) return false;
    if (String(sourceItem.itemId) === String(targetItem.itemId)) return false;

    $.post(jrsInventoryUrl + "/merge_stacks", JSON.stringify({
        sourceItemId: sourceItem.itemId,
        targetItemId: targetItem.itemId
    }));

    return true;
}

function jrsPulseMovedSlots(fromSlot, toSlot) {
    requestAnimationFrame(function() {
        [fromSlot, toSlot].forEach(function(slot) {
            const node = document.querySelector('#tableData [data-slot="' + Number(slot) + '"]');
            if (!node) return;
            node.classList.remove('jrs-slot-land');
            void node.offsetWidth;
            node.classList.add('jrs-slot-land');
            window.setTimeout(function() {
                if (node && node.classList) node.classList.remove('jrs-slot-land');
            }, 150);
        });
    });
}

// Rebuild only the given bag slots from table_inv / wtable_inv. Returns false
// when the grid needs a full render instead (its slot count would change, or a
// slot node is missing).
function jrsRefreshInventorySlots(slots) {
    const grid = document.getElementById("tableData");
    if (!grid || !jrsHasDragDrop() || !jrsInventoryRenderedSlots) return false;

    const wanted = {};
    slots.forEach(function(slot) { wanted[Number(slot)] = null; });
    let highestUsedSlot = 0;
    for (let i = 0; i < table_inv.length; i++) {
        const slot = Number(table_inv[i].slot);
        if (slot > highestUsedSlot) highestUsedSlot = slot;
        if (slot in wanted) wanted[slot] = { type: "item", data: table_inv[i], index: i };
    }
    for (let i = 0; i < wtable_inv.length; i++) {
        const slot = Number(wtable_inv[i].slot);
        if (slot > highestUsedSlot) highestUsedSlot = slot;
        if (slot in wanted) wanted[slot] = { type: "weapon", data: wtable_inv[i], index: i };
    }
    if (jrsInventoryGridSize(highestUsedSlot) !== jrsInventoryRenderedSlots) return false;

    const nodes = [];
    for (const key in wanted) {
        const old = grid.querySelector(':scope > [data-slot="' + key + '"]');
        if (!old) return false;
        nodes.push(old);
    }

    const fresh = [];
    const scratch = document.createElement("div");
    nodes.forEach(function(old) {
        const slot = Number(old.getAttribute("data-slot"));
        const entry = wanted[slot];
        scratch.innerHTML = buildInventorySlotHtml(slot, entry, entry ? entry.index : undefined);
        const node = scratch.firstElementChild;
        $(old).replaceWith(node);
        fresh.push(node);
    });

    jrsBindInventorySlots(fresh);
    applyInventoryFilter();
    applyMultiSelectionVisuals();
    return true;
}

function swapSlotsLocal(fromSlot, toSlot) {

    let fromObject = null;
    let toObject = null;

    // search items
    for (let i = 0; i < table_inv.length; i++) {

        if (Number(table_inv[i].slot) === Number(fromSlot))
            fromObject = table_inv[i];

        if (Number(table_inv[i].slot) === Number(toSlot))
            toObject = table_inv[i];

    }

    // search weapons
    for (let i = 0; i < wtable_inv.length; i++) {

        if (Number(wtable_inv[i].slot) === Number(fromSlot))
            fromObject = wtable_inv[i];

        if (Number(wtable_inv[i].slot) === Number(toSlot))
            toObject = wtable_inv[i];

    }

    if (!fromObject)
        return;

    if (toObject) {

        let temp = fromObject.slot;

        fromObject.slot = toObject.slot;
        toObject.slot = temp;

    } else {

        fromObject.slot = Number(toSlot);

    }

    if (activeTemporarySortMode) {
        skipSortReapplyOnce = true;
    }

    if (activeTemporarySortMode || !jrsRefreshInventorySlots([fromSlot, toSlot])) {
        loadTableData(
            table_inv,
            moneysd,
            wtable_inv,
            goldsd,
            dirtymoneysd
        );
    }
    jrsPulseMovedSlots(fromSlot, toSlot);

    if (activeTemporarySortMode) {
        updateSortControlState("TEMP LAYOUT CHANGED — SAVE OR MANUAL");
    } else {
        captureManualInventorySlots();
        queueInventorySlotSave();
    }
}

function jrsHasDragDrop() {
    return typeof window.jQuery !== "undefined"
        && typeof $.fn.draggable === "function"
        && typeof $.fn.droppable === "function";
}

function jrsDestroyDragDrop(elements) {
    if (!jrsHasDragDrop() || !elements || !elements.length) return;
    elements.each(function() {
        const element = $(this);
        try {
            if (element.data("ui-draggable")) element.draggable("destroy");
        } catch (_) {}
        try {
            if (element.data("ui-droppable")) element.droppable("destroy");
        } catch (_) {}
    });
}

function makeCurrencyDraggable() {
    const entries = $("#currency-panel .currency-entry");
    if (!entries.length || !jrsHasDragDrop()) return;

    jrsDestroyDragDrop(entries);

    entries.draggable({
        helper: jrsDragGhost,
        appendTo: "body",
        zIndex: 999999,
        revert: "invalid",
        revertDuration: JRS_DRAG_REVERT_MS,
        distance: JRS_DRAG_DISTANCE,
        scroll: false,
        addClasses: false,
        refreshPositions: false,
        cursorAt: { left: 30, top: 30 },

        start: function() {
            const currencyType = String($(this).attr("data-type") || "");
            if (!isCurrencyType(currencyType)) return false;

            dragged_item_inv = currencyType;
            dragged_witem_inv = undefined;
            clicked_id = currencyType;
            clicked_name = currencyType;
            clicked_type = currencyType;
            clicked_meta = {};
            dragStartSlot = currencyType;
            drag_to_normal = true;
            drag_to_other = false;
            dragged = true;
        },

        stop: function() {
            dragged_item_inv = undefined;
            dragged_witem_inv = undefined;
            clicked_type = "";
            clicked_id = "";
            dragged = false;
            drag_to_normal = false;
            drag_to_other = false;
            dragStartSlot = null;
            dragTargetSlot = null;
        }
    });
}

function pickupGroundFromDraggable(draggable) {
    const element = $(draggable);
    if (!element.hasClass("ground-item")) return false;

    const dropId = Number(element.attr("data-dropid"));
    if (!Number.isFinite(dropId) || dropId <= 0) return true;
    if (groundPickupPending[dropId]) return true;

    groundPickupPending[dropId] = true;
    clicked_drop = dropId;

    $.post(
        jrsInventoryUrl + "/pickup_ground",
        JSON.stringify({ id: dropId })
    ).always(function() {
        setTimeout(function() {
            delete groundPickupPending[dropId];
        }, 700);
    });

    // Do not remove the slot optimistically. The server response refreshes the
    // authoritative Ground list, and failed pickups remain visible.
    return true;
}

// Trying to drag a pinned item: a short shake on its star plus a hint, so the
// player knows why it did not move.
function jrsFlashPinnedLock(slotElement) {
    if (!slotElement || !slotElement.classList) return;
    slotElement.classList.remove("jrs-pin-deny");
    void slotElement.offsetWidth;
    slotElement.classList.add("jrs-pin-deny");
    window.clearTimeout(slotElement.__jrsPinDenyTimer);
    slotElement.__jrsPinDenyTimer = window.setTimeout(function() {
        slotElement.classList.remove("jrs-pin-deny");
    }, 650);
    const badge = slotElement.querySelector(".inventory-pin-badge");
    if (badge) badge.title = JrsI18n.t("inv_pinned_locked", "Pinned - unpin it to move it");
}

let jrsPinnedPress = null;
$(document).on("mousedown.jrsPinLock", "#tableData .item.inventory-pinned", function(event) {
    if (event.which !== 1 || multiSelectMode) return;
    jrsPinnedPress = { element: this, x: event.clientX, y: event.clientY, shown: false };
});
$(document).on("mousemove.jrsPinLock", function(event) {
    if (!jrsPinnedPress || jrsPinnedPress.shown) return;
    if (Math.abs(event.clientX - jrsPinnedPress.x) + Math.abs(event.clientY - jrsPinnedPress.y) < 6) return;
    jrsPinnedPress.shown = true;
    jrsFlashPinnedLock(jrsPinnedPress.element);
});
$(document).on("mouseup.jrsPinLock", function() { jrsPinnedPress = null; });

// Drag/drop options shared by every bag slot: the full render binds all of
// them, a swap only re-binds the two slots it rebuilt.
const JRS_INVENTORY_SLOT_DRAG = {

        helper: jrsDragGhost,
        appendTo: 'body',
        // A pinned item stays in its slot until it is unpinned.
        cancel: "input,textarea,button,select,option,.inventory-pinned",
        zIndex: 99999,
        revert: 'invalid',
        revertDuration: JRS_DRAG_REVERT_MS,
        distance: JRS_DRAG_DISTANCE,
        scroll: false,
        addClasses: false,
        refreshPositions: false,
        opacity: JRS_DRAG_OPACITY,

        start: function (event, ui) {

            $(this).addClass("jrs-drag-source");
            setJrsStorageDragState("inventory");
            dragStartSlot = $(this).attr("data-slot");


            dragged_item_inv = undefined;
            dragged_witem_inv = undefined;
            clicked_type = "";
            clicked_id = "";
            clicked_meta = {};


           
            var contentDiv = $(this).find('.item-content');
            var itemId = contentDiv.attr('id');

            if (itemId) {

                var actualContent = $(this).attr('data-content') || "";

                if (isCurrencyType(itemId)) {

                    clicked_id = itemId;
                    clicked_type = itemId;
                    clicked_meta = {};
                    dragged_item_inv = itemId;

                }
               else if ($(this).attr("data-type") === "weapon") {
                    /////////////////
                    clicked_id = wtable_inv[itemId].id;
                    clicked_type = "valuable";
                    clicked_meta = wtable_inv[itemId].metaData || {};
                    dragged_witem_inv = itemId;
                    dragged_item_inv = undefined;


                }
                else {

                    if (typeof table_inv !== 'undefined' && table_inv[itemId]) {

                        clicked_id = table_inv[itemId].itemId;
                        clicked_meta = table_inv[itemId].metaData || {};

                        dragged_item_inv = itemId;
                        dragged_witem_inv = undefined;

                    } else {

                        clicked_id = itemId;
                        clicked_meta = {};

                    }

                    clicked_type = "item";
                }

                drag_to_normal = true;
                drag_to_other = false;
                dragged = true;

            }

        },

        stop: function () {

            $(this).removeClass("jrs-drag-source");
            window.setTimeout(clearJrsStorageDragState, 0);
            dragged_item_inv = undefined;
            dragged_witem_inv = undefined;
            clicked_type = "";
            clicked_id = "";
            dragged = false;

            drag_to_normal = false;
            drag_to_other = false;

            dragStartSlot = null;
            dragTargetSlot = null;

        }

};

//==================================
// Swap inside the satchel
//==================================
const JRS_INVENTORY_SLOT_DROP = {

    // A pinned slot keeps its item: nothing is swapped or merged into it.
    accept: function(draggable) {
        return $(draggable).is(".item") && !this.classList.contains("inventory-pinned");
    },

    tolerance: "pointer",

    hoverClass: "drag-hover",

    drop: function (event, ui) {

        const sourceOrigin = String($(ui.draggable).attr("data-origin") || "");
        if (sourceOrigin === "storage") {
            const requestedSlot = Number($(this).attr("data-slot"));
            const targetSlot = Number.isInteger(requestedSlot) && requestedSlot > 0 ? requestedSlot : null;
            const storageIndex = getStorageIndexFromDraggable(ui.draggable);
            transfer_from_storage(targetSlot, storageIndex);
            return;
        }

        // ==========================
        // items on the ground cannot be swapped
        // ==========================
        if (pickupGroundFromDraggable(ui.draggable)) {
            return;
        }

        const draggedType = String($(ui.draggable).attr("data-type") || "");
        if (isCurrencyType(draggedType)) {
            return;
        }

        dragTargetSlot = $(this).attr("data-slot");

        if (!dragTargetSlot)
            return;

        if (dragStartSlot == dragTargetSlot)
            return;

        // Dragging one identical stack over another merges the full source
        // stack into the target. Different items or different metadata keep
        // the normal slot-swap behavior.
        if (tryMergeInventoryStacks($(ui.draggable), $(this))) {
            return;
        }

        // Swap once jQuery UI has finished its drop loop: the two slots are
        // rebuilt, and this droppable is one of them.
        const fromSlot = Number(dragStartSlot);
        const toSlot = Number(dragTargetSlot);
        queueMicrotask(function() {
            swapSlotsLocal(fromSlot, toSlot);
        });

    }

};

function jrsBindInventorySlots(nodes) {
    const slots = $(nodes);
    slots.filter(".item").draggable(JRS_INVENTORY_SLOT_DRAG);
    slots.droppable(JRS_INVENTORY_SLOT_DROP);
}

function makeItemsDraggableAndDroppable() {
    if (!jrsHasDragDrop()) {
        jrsDevLog("[JRS Inventory] Local drag-and-drop library is unavailable.");
        return;
    }

    // The grid was just rebuilt through jrsSetWidgetHtml(), so these slots are
    // new and unbound.
    jrsBindInventorySlots($("#tableData > .item, #tableData > .empty-slot"));

    // Quick slots and the panel-level drop targets are rebound with them so
    // drag-to-hotbar, ground pickup and storage transfers keep working.
    bindJrsHotbarInteractions();
    bindJrsPanelDropTargets();
}


// Panel-level drop targets: dropping onto the blank area of a panel, not onto
// one particular slot. These used to be created once at load - and then
// makeItemsDraggableAndDroppable() destroyed them on the very first inventory
// render, because its `inventoryTargets` list contains #tableData and
// #expand_container. From then on, dropping a ground item or a storage stack
// anywhere except exactly on a slot did nothing. They are rebound with
// everything else now.
function bindJrsPanelDropTargets() {
    if (!jrsHasDragDrop()) return;

    const panels = $("#tableData, #expand_container");
    if (!panels.length) return;
    jrsDestroyDragDrop(panels);

    //========================
    // Storage
    //========================
    $("#expand_container").droppable({
        accept: function(draggable) {
            return String($(draggable).attr("data-origin") || "") === "inventory";
        },
        tolerance: "pointer",
        hoverClass: "storage-panel-drop-hover",
        drop: function (event, ui) {
            if (id_container == 0) return;
            if (String($(ui.draggable).attr("data-origin") || "") !== "inventory") return;
            const source = getDragSourceFromDraggable(ui.draggable);
            transfer_to_storage(null, source);
        }
    });

    //========================
    // Inventory
    //========================
    $("#tableData").droppable({
        accept: ".item, .ground-item",
        tolerance: "pointer",
        hoverClass: "inventory-panel-drop-hover",
        drop: function (event, ui) {
            if (pickupGroundFromDraggable(ui.draggable)) return;
            if (id_container == 0) return;

            const origin = String($(ui.draggable).attr("data-origin") || "");
            if (origin === "storage") {
                const storageIndex = getStorageIndexFromDraggable(ui.draggable);
                transfer_from_storage(null, storageIndex);
            }
        }
    });

    // Hotbar drop/drag binding is refreshed by bindJrsHotbarInteractions().
}

bindJrsPanelDropTargets();


function bindStorageSlotDroppables() {
    if (!jrsHasDragDrop()) return;
    const targets = $("#expand_container .storage-slot, #expand_container .storage-empty-slot");
    targets.each(function() {
        const target = $(this);
        try {
            if (target.data("ui-droppable")) target.droppable("destroy");
        } catch (_) {}
    });

    targets.droppable({
        accept: function(draggable) {
            return String($(draggable).attr("data-origin") || "") === "inventory";
        },
        greedy: true,
        tolerance: "pointer",
        hoverClass: "storage-slot-drop-hover",
        drop: function(event, ui) {
            if (String($(ui.draggable).attr("data-origin") || "") !== "inventory") return;
            const isEmptyTarget = $(this).hasClass("storage-empty-slot");
            const slot = Number($(this).attr("data-storage-slot"));
            jrsStorageDropTargetSlot = isEmptyTarget && Number.isInteger(slot) && slot > 0 ? slot : null;
            const source = getDragSourceFromDraggable(ui.draggable);
            transfer_to_storage(jrsStorageDropTargetSlot, source);
        }
    });
}


function makeStorageItemsDraggable() {
    if (!jrsHasDragDrop()) return;
    const storageItems = $("#expand_container .item");
    jrsDestroyDragDrop(storageItems);

    storageItems.draggable({

        helper: jrsDragGhost,
        appendTo: "body",
        zIndex: 99999,
        revert: "invalid",
        revertDuration: JRS_DRAG_REVERT_MS,
        distance: JRS_DRAG_DISTANCE,
        scroll: false,
        addClasses: false,
        refreshPositions: false,
        opacity: JRS_DRAG_OPACITY,

        start: function () {
            $(this).addClass("jrs-drag-source");
            setJrsStorageDragState("storage");
            const storageIndex = $(this).attr("data-storage-index");
            dragged_stor_inv = storageIndex !== undefined ? storageIndex : $(this).find(".item-content").attr("id");
            dragged = true;
        },

        stop: function () {
            $(this).removeClass("jrs-drag-source");
            window.setTimeout(clearJrsStorageDragState, 0);
            dragged_stor_inv = undefined;
            dragged = false;
        }

    });

}


function DropItem(count) {
    if (isPersonalItem(selectedPersonalItemName())) return;

    if (typeof contextMenu !== 'undefined')
        contextMenu.classList.remove("visible");

    if (count !== 0 && clicked_id && clicked_id !== "") {

        let finalCount = Math.floor(count);

        if (clicked_type === "valuable")
            finalCount = 1;

        const dropPayloadType = isCurrencyType(clicked_type)
            ? "item"
            : clicked_type;

        $.post(
            jrsInventoryUrl + "/drop_item",
            JSON.stringify({
                item: clicked_id,
                count: finalCount,
                is_weapon: dropPayloadType,
                metaData: clicked_meta
            })
        );

        clearTrashData();
    }

}

function confirmTrashDrop() {
    var input = document.getElementById('trash-item-count');
    var count = parseInt(input ? input.value : 1) || 1;
    var maxCount = parseInt(input ? input.max : count) || count;
    count = Math.max(1, Math.min(count, maxCount));
    
    // run the original handler
    DropItem(count);
    
    // hide the prompt and reset the bin
    $("#trash-action-view").hide();
    $("#trash-default-view").show();
}

// Standalone cancel handler.
function cancelTrashDrop() {
    $("#trash-action-view").hide();
    $("#trash-default-view").show();
    
    // clear immediately - the player cancelled
    clearTrashData();
}

// Wipe the globals completely.
function clearTrashData() {
    clicked_id = "";
    clicked_type = "";
    clicked_meta = {};
    if (typeof clicked_name !== 'undefined') clicked_name = "";
    dragged = false;
    
    var trashInput = document.getElementById('trash-item-count');
    if (trashInput) {
        trashInput.value = "1";
        trashInput.disabled = false;
        trashInput.removeAttribute("max");
    }

}


function handleInventoryDropToGround(ui) {
    const draggable = $(ui.draggable);
    if (draggable.hasClass("ground-item")) return;

    // Rebuild the selected payload from the dragged element if another hover/click
    // changed the global selection while dragging.
    const sourceOrigin = String(draggable.attr("data-origin") || "");
    if (sourceOrigin !== "inventory" && !isCurrencyType(String(draggable.attr("data-type") || ""))) return;

    const draggedType = String(draggable.attr("data-type") || clicked_type || "");
    const content = draggable.find(".item-content");
    const contentId = content.attr("id");

    if (isCurrencyType(draggedType)) {
        clicked_id = draggedType;
        clicked_type = draggedType;
        clicked_meta = {};
        dragged_item_inv = draggedType;
        const maxCount = Math.floor(getCurrencyBalance(draggedType) || 0);
        if (maxCount > 0 && jrsShiftHeld) DropItem(maxCount);
        else if (maxCount > 0) showGroundAmount(maxCount);
        return;
    }

    if (draggedType === "weapon" || clicked_type === "valuable") {
        if (contentId !== undefined && wtable_inv[contentId]) {
            clicked_id = wtable_inv[contentId].id;
            clicked_type = "valuable";
            clicked_meta = wtable_inv[contentId].metaData || {};
            clicked_name = wtable_inv[contentId].name || "";
        }
        if (clicked_id) DropItem(1);
        return;
    }

    if (contentId !== undefined && table_inv[contentId]) {
        const entry = table_inv[contentId];
        clicked_id = entry.itemId;
        clicked_type = "item";
        clicked_meta = entry.metaData || {};
        clicked_name = entry.item || "";
        dragged_item_inv = Number(contentId);
        const count = Math.max(1, Math.floor(Number(entry.count) || 1));
        if (count <= 1) DropItem(1);
        else if (jrsShiftHeld) DropItem(count);
        else showGroundAmount(count);
        return;
    }

    if (clicked_id) {
        const count = selectedDropMaximum();
        if (count <= 1) DropItem(1);
        else if (jrsShiftHeld) DropItem(count);
        else showGroundAmount(count);
    }
}

function loadGroundData(groundTable) {
    const groundBody = document.getElementById("groundData");
    if (!groundBody) return;
    if (!Array.isArray(groundTable)) groundTable = [];

    let html = "";

    const TOTAL_SLOTS = Math.max(21, groundTable.reduce((max, it) => Math.max(max, Number(it.slot) || 0), 0));

    let slotMap = {};

    for (let i = 0; i < groundTable.length; i++) {

        slotMap[groundTable[i].slot] = groundTable[i];

    }

    for (let slot = 1; slot <= TOTAL_SLOTS; slot++) {

        let item = slotMap[slot];

        if (!item) {

            html += '<div class="empty-slot ground-slot" data-slot="' + slot + '" title="Ground slot ' + slot + '"><span class="slot-id-badge">' + slot + '</span></div>';
            continue;

        }

        const isWeapon = item.weapon === true || item.weapon === 1 || item.weapon === "1" || String(item.weapon).toLowerCase() === "true";
        let image = String(isWeapon ? (item.weapon_model || "") : (item.item || ""));
        if (!image) image = "badItem";

        html +=
        '<div class="item ground-item" ' +
            'data-slot="' + slot + '" ' +
            'data-dropid="' + escapeDescriptionHtml(item.id) + '" ' +
            'data-index="' + (slot - 1) + '" ' +
            'data-type="ground" ' +
            'data-weapon="' + (isWeapon ? 'true' : 'false') + '" ' +
            'data-weapon-model="' + escapeDescriptionHtml(item.weapon_model || '') + '">' +

            '<div class="item-content">' +

                '<img loading="lazy" decoding="async" src="images/items/' + escapeDescriptionHtml(image) + '.png" width="60" height="60">' +

                '<div class="bottom-right">' +
                    escapeDescriptionHtml(item.count) +
                '</div>' +

            '</div>' +

        '</div>';

    }

    jrsSetWidgetHtml(groundBody, html);


    makeGroundDraggableAndDroppable();


}

function makeGroundDraggableAndDroppable() {
    if (!jrsHasDragDrop()) return;

    const groundPanel = $("#ground-container");
    const groundGrid = $("#groundData");
    const groundSlots = $("#groundData .ground-slot, #groundData .ground-item");
    const groundItems = $("#groundData .ground-item");

    // Destroy only bindings we own and then rebuild them after every ground refresh.
    jrsDestroyDragDrop(groundItems);
    groundPanel.add(groundGrid).add(groundSlots).each(function() {
        const element = $(this);
        try {
            if (element.data("ui-droppable")) element.droppable("destroy");
        } catch (_) {}
    });

    const acceptInventory = function(draggable) {
        const node = $(draggable);
        if (node.hasClass("ground-item")) return false;
        const origin = String(node.attr("data-origin") || "");
        const type = String(node.attr("data-type") || "");
        return origin === "inventory" || isCurrencyType(type);
    };

    // Bind panel + grid + every visible ground slot. A greedy slot consumes the
    // drop so the callback fires once, while dropping between slots still works.
    groundPanel.droppable({
        accept: acceptInventory,
        tolerance: "pointer",
        hoverClass: "drag-hover",
        drop: function(event, ui) {
            handleInventoryDropToGround(ui);
        }
    });

    groundGrid.droppable({
        accept: acceptInventory,
        greedy: true,
        tolerance: "pointer",
        hoverClass: "drag-hover",
        drop: function(event, ui) {
            handleInventoryDropToGround(ui);
        }
    });

    groundSlots.droppable({
        accept: acceptInventory,
        greedy: true,
        tolerance: "pointer",
        hoverClass: "drag-hover",
        drop: function(event, ui) {
            handleInventoryDropToGround(ui);
        }
    });

    groundItems.draggable({
        helper: jrsDragGhost,
        appendTo: "body",
        zIndex: 99999,
        revert: "invalid",
        revertDuration: JRS_DRAG_REVERT_MS,
        distance: JRS_DRAG_DISTANCE,
        scroll: false,
        addClasses: false,
        refreshPositions: false,
        opacity: 0.94,
        start: function() {
            $(this).addClass("jrs-drag-source");
            clicked_drop = Number($(this).attr("data-dropid"));
            dragged = true;
        },
        stop: function() {
            $(this).removeClass("jrs-drag-source");
            $(".ui-draggable-dragging").remove();
            dragged = false;
        }
    });
}

// function pickupGroundItem(dropId) {

//     $.post(
//         jrsInventoryUrl + "/pickup_ground",
//         JSON.stringify({
//             id: dropId
//         })
//     );

// }


function showGroundAmount(maxCount) {
    const max = Math.max(1, Math.floor(Number(maxCount) || 1));
    const windowEl = document.getElementById("groundAmountWindow");
    const input = document.getElementById("groundAmountInput");
    if (!windowEl || !input) return;

    input.min = "1";
    input.max = String(max);
    input.value = String(max);
    windowEl.style.setProperty("display", "block", "important");
    requestAnimationFrame(function() {
        input.focus();
        input.select();
    });
}

function confirmGroundDrop() {
    const input = document.getElementById("groundAmountInput");
    const windowEl = document.getElementById("groundAmountWindow");
    const max = Math.max(1, Math.floor(Number(input && input.max) || 1));
    let count = Math.floor(Number(input && input.value) || 1);
    count = Math.max(1, Math.min(count, max));
    if (windowEl) windowEl.style.setProperty("display", "none", "important");
    DropItem(count);
}

function cancelGroundDrop() {
    const windowEl = document.getElementById("groundAmountWindow");
    if (windowEl) windowEl.style.setProperty("display", "none", "important");
}

// ============================================================================
// JRS: force the search / filter / sort bars to the TOP of the inventory panel.
// Uses inline !important styles so it wins over every CSS media-query and layout
// rule, and re-applies whenever the layout mode (body class) changes.
// ============================================================================
(function jrsTopControls() {
    // Put the control rows into the container's own flex column via `order`, so
    // everything stacks cleanly (title, filter, action, [multi], grid, status)
    // with no overlap or dead space. Backup for the matching CSS. We deliberately
    // do NOT touch the grid's width/columns, so the fixed slot geometry — and the
    // jQuery-UI drop targets — stay exactly where the slots are drawn.
    function flow(id, order) {
        var el = document.getElementById(id);
        if (!el) return;
        el.style.setProperty("order", String(order), "important");
        el.style.setProperty("position", "relative", "important");
        ["top", "left", "right", "bottom"].forEach(function (p) { el.style.setProperty(p, "auto", "important"); });
        el.style.setProperty("margin", "0", "important");
    }
    function place() {
        if (!document.body || !document.body.classList.contains("inventory-layout-standard")) return;
        var container = document.getElementById("container");
        if (!container) return;
        container.style.setProperty("display", "flex", "important");
        container.style.setProperty("flex-direction", "column", "important");
        container.style.setProperty("gap", "8px", "important");
        var title = container.querySelector(".panel-title-wrap");
        if (title) title.style.setProperty("order", "0", "important");
        flow("inventory-filter-bar", 1);
        flow("inventory-action-bar", 2);
        flow("multi-select-toolbar", 3);
        flow("inventory-status", 5);
        var grid = document.getElementById("tableData");
        if (grid) {
            grid.style.setProperty("order", "4", "important");
            grid.style.setProperty("position", "static", "important");
            grid.style.setProperty("margin", "0", "important");
        }
    }
    // Re-applied only when the layout mode changes (each open re-adds the
    // standard class, and hide()/show() is what drops the inline flex). The old
    // 600 ms timer rewrote ~30 inline styles for as long as the bag was open,
    // and every drag's body-class toggle ran it again.
    function start() {
        var lastLayout = null;
        function onBodyClass() {
            var layout = jrsBodyLayoutClass();
            if (layout === lastLayout) return;
            lastLayout = layout;
            place();
        }
        onBodyClass();
        try {
            new MutationObserver(onBodyClass).observe(document.body, { attributes: true, attributeFilter: ["class"] });
        } catch (e) {}
    }
    if (document.readyState !== "loading") start();
    else document.addEventListener("DOMContentLoaded", start);
})();

// JRS selection clarity and draggable inventory window.
$(document).on("click.jrsSelection", "#tableData .item, #tableData .empty-slot", function(event) {
    if (multiSelectMode || (event.which && event.which !== 1)) return;
    document.querySelectorAll("#tableData .inventory-selected").forEach(function(slot) {
        slot.classList.remove("inventory-selected");
    });
    this.classList.add("inventory-selected");
});

// The standard layout is ONE scaled canvas (#standard-inventory-layout) holding
// clothing, bag, ground, wallet and quick slots. The old version translated only
// #container and #hotbar - in screen pixels inside a scaled parent - so the bag
// slid away from its own clothing/ground/wallet and drifted faster than the
// mouse. Now the whole canvas moves as a unit: the offset is fed into the
// canvas transform through --jrs-win-x / --jrs-win-y (index.css, v2.1.0) and is
// applied before the scale, so it is 1:1 with the cursor at every resolution.
// Any of the three panel headers is a handle; double-click one to re-centre.
(function bindInventoryWindowDrag() {
    const STORAGE_KEY = "jrs_inventory_window_offset";
    const HANDLES = "#container > .panel-title-wrap, #container_other > .panel-title-wrap, #clothing-side-panel > .clothing-header, #ground-container > .ground-title";
    const PANELS = ["container", "container_other", "clothing-side-panel", "ground-container", "currency-panel", "hotbar", "jrs-panel-dock"];
    let offset = { x: 0, y: 0 };
    let dragState = null;
    let activeHandle = null;

    function canvas() { return document.getElementById("standard-inventory-layout"); }
    function isStandard() { return !!document.body && document.body.classList.contains("inventory-layout-standard"); }

    function apply(directGpu) {
        const el = canvas();
        if (!el) return;
        const x = Math.round(offset.x);
        const y = Math.round(offset.y);
        if (directGpu) {
            // Apply transform directly to GPU compositor layer:
            // Completely avoids child style recalculations and provides 0 input latency.
            el.style.setProperty("transform", "translate3d(calc(-50% + " + x + "px), calc(-50% + " + y + "px), 0px) scale(var(--jrs-exact-scale, 1))", "important");
        } else {
            el.style.setProperty("--jrs-win-x", x + "px");
            el.style.setProperty("--jrs-win-y", y + "px");
            el.style.removeProperty("transform");
        }
    }

    function save() {
        try { window.localStorage.setItem(STORAGE_KEY, JSON.stringify(offset)); } catch (e) {}
    }

    // Screen-space box around every visible panel, at the CURRENT offset.
    function visibleBounds() {
        let box = null;
        PANELS.forEach(function(id) {
            const el = document.getElementById(id);
            if (!el || el.offsetParent === null || el.classList.contains("jrs-panel-hidden")) return;
            const r = el.getBoundingClientRect();
            if (r.width <= 0 || r.height <= 0) return;
            if (!box) box = { left: r.left, top: r.top, right: r.right, bottom: r.bottom };
            else {
                box.left = Math.min(box.left, r.left);
                box.top = Math.min(box.top, r.top);
                box.right = Math.max(box.right, r.right);
                box.bottom = Math.max(box.bottom, r.bottom);
            }
        });
        return box;
    }

    // Keep the inventory accessible on screen while allowing completely free dragging
    function clampAxis(next, current, lo, hi, limit) {
        const size = hi - lo;
        const baseLo = lo - current;
        const minVisible = Math.min(120, Math.max(50, size * 0.2));
        const minOffset = minVisible - size - baseLo;
        const maxOffset = limit - minVisible - baseLo;
        return Math.min(Math.max(next, minOffset), maxOffset);
    }

    function clampTo(x, y) {
        const box = visibleBounds();
        if (!box) return { x: x, y: y };
        return {
            x: clampAxis(x, offset.x, box.left, box.right, window.innerWidth || 1920),
            y: clampAxis(y, offset.y, box.top, box.bottom, window.innerHeight || 1080)
        };
    }

    function reclamp() {
        if (!isStandard() || dragState) return;
        const next = clampTo(offset.x, offset.y);
        if (Math.abs(next.x - offset.x) < 0.5 && Math.abs(next.y - offset.y) < 0.5) return;
        offset = next;
        apply(false);
    }

    try {
        const saved = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || "null");
        if (saved && Number.isFinite(saved.x) && Number.isFinite(saved.y)) offset = { x: saved.x, y: saved.y };
    } catch (e) {}

    function start() {
        ["container", "hotbar"].forEach(function(id) {
            const el = document.getElementById(id);
            if (el) el.style.removeProperty("transform");
        });
        apply(false);
        let lastLayout = jrsBodyLayoutClass();
        try {
            // Layout switches only; drag-state body classes change constantly.
            new MutationObserver(function() {
                const layout = jrsBodyLayoutClass();
                if (layout === lastLayout) return;
                lastLayout = layout;
                setTimeout(reclamp, 60);
            }).observe(document.body, { attributes: true, attributeFilter: ["class"] });
        } catch (e) {}
        window.addEventListener("resize", function() { setTimeout(reclamp, 80); });
    }
    if (document.readyState !== "loading") start();
    else document.addEventListener("DOMContentLoaded", start);

    $(document).on("pointerdown.jrsWindowDrag", HANDLES, function(event) {
        if (event.button !== 0 || !isStandard()) return;
        if ($(event.target).closest("input, button, select, textarea, .tab, .category-btn").length) return;
        event.preventDefault();
        activeHandle = this;
        try { if (activeHandle.setPointerCapture) activeHandle.setPointerCapture(event.pointerId); } catch (e) {}
        const winW = window.innerWidth || 1920;
        const winH = window.innerHeight || 1080;
        dragState = {
            pointerId: event.pointerId,
            startX: event.clientX,
            startY: event.clientY,
            x: offset.x,
            y: offset.y,
            bounds: visibleBounds(),
            winW: winW,
            winH: winH,
            next: { x: offset.x, y: offset.y }
        };
        document.body.classList.add("inventory-window-dragging");
    });

    $(document).on("pointermove.jrsWindowDrag", function(event) {
        if (!dragState || (event.pointerId && event.pointerId !== dragState.pointerId)) return;
        const x = dragState.x + event.clientX - dragState.startX;
        const y = dragState.y + event.clientY - dragState.startY;
        const box = dragState.bounds;
        dragState.next = box ? {
            x: clampAxis(x, dragState.x, box.left, box.right, dragState.winW),
            y: clampAxis(y, dragState.y, box.top, box.bottom, dragState.winH)
        } : { x: x, y: y };

        offset = dragState.next;
        apply(true);
    });

    function endWindowDrag(event) {
        if (!dragState) return;
        if (activeHandle && event && event.pointerId) {
            try { if (activeHandle.releasePointerCapture) activeHandle.releasePointerCapture(event.pointerId); } catch (e) {}
        }
        activeHandle = null;
        dragState = null;
        document.body.classList.remove("inventory-window-dragging");
        apply(false);
        invalidateContainerMetricsCache();
        save();
    }

    $(document).on("pointerup.jrsWindowDrag pointercancel.jrsWindowDrag", function(event) {
        if (!dragState || (event.pointerId && event.pointerId !== dragState.pointerId)) return;
        endWindowDrag(event);
    });
    window.addEventListener("blur", function() { endWindowDrag(); });
    window.addEventListener("resize", function() { endWindowDrag(); });

    $(document).on("dblclick.jrsWindowDrag", HANDLES, function() {
        if (!isStandard()) return;
        offset = { x: 0, y: 0 };
        apply(false);
        reclamp();
        save();
    });
})();

// Panel dock above the bag: Clothing / Ground / Money / Slots can each be hidden
// so only the bag is left. The choice is remembered per player (localStorage).
// Hiding is a class (index.css v2.2.0 fade/slide): the panels are still shown
// and hidden by display2() as before, the class only makes them invisible and
// out of reach - drop targets inside them are skipped (jrsVisibleDropRect).
(function bindJrsPanelDock() {
    const STORAGE_KEY = "jrs_inventory_hidden_panels";
    const PANELS = {
        clothing: "clothing-side-panel",
        ground: "ground-container",
        money: "currency-panel",
        slots: "hotbar"
    };
    let hidden = {};
    try {
        const saved = JSON.parse(window.localStorage.getItem(STORAGE_KEY) || "{}");
        if (saved && typeof saved === "object") hidden = saved;
    } catch (e) {}

    function apply() {
        Object.keys(PANELS).forEach(function(key) {
            const off = hidden[key] === true;
            const panel = document.getElementById(PANELS[key]);
            if (panel) panel.classList.toggle("jrs-panel-hidden", off);
            const button = document.querySelector('#jrs-panel-dock .jrs-panel-toggle[data-panel="' + key + '"]');
            if (button) {
                button.classList.toggle("is-off", off);
                button.setAttribute("aria-pressed", off ? "false" : "true");
            }
        });
    }

    function save() {
        try { window.localStorage.setItem(STORAGE_KEY, JSON.stringify(hidden)); } catch (e) {}
    }

    $(document).on("click.jrsPanelDock", "#jrs-panel-dock .jrs-panel-toggle", function(event) {
        event.preventDefault();
        event.stopPropagation();
        const key = this.getAttribute("data-panel");
        if (!PANELS[key]) return;
        if (hidden[key] === true) delete hidden[key];
        else hidden[key] = true;
        save();
        apply();
        if (key === "slots") closeJrsHotbarContextMenu();
    });

    if (document.readyState !== "loading") apply();
    else document.addEventListener("DOMContentLoaded", apply);
})();

// jrs_inventory: JS-written labels follow the player's language too. jrs-i18n.js
// rewrites the [data-i18n] markup first, then runs these listeners, so the
// current filter/selector text is put back over the static default.
if (typeof JrsI18n !== "undefined") {
    JrsI18n.onChange(function() {
        try { updateInventoryFilterButtons(); } catch (e) {}
        try { updatePlayerSelectorLabels(); } catch (e) {}
        try { updateSortControlState(); } catch (e) {}
        try { updateMultiSelectToolbar(); } catch (e) {}
    });
}

// jrs_inventory 2.3.1: smooth wheel scrolling for the slot grids. One wheel
// notch used to jump a whole row at once; now the grid eases toward the target.
// Skipped while dragging (jQuery UI measured the drop targets at drag start),
// for shift/ctrl wheel, and whenever something else sets scrollTop (usable
// scroll restore, re-render) - that just cancels the glide.
(function() {
    const EASE = 0.22;

    function bind(el) {
        if (!el || el.dataset.jrsSmoothWheel === "1") return;
        el.dataset.jrsSmoothWheel = "1";
        let target = 0;
        let lastSet = 0;
        let raf = 0;
        let rafAt = 0;

        function stop() {
            if (raf) cancelAnimationFrame(raf);
            raf = 0;
        }

        function queue() {
            rafAt = performance.now();
            raf = requestAnimationFrame(step);
        }

        function step() {
            raf = 0;
            const cur = el.scrollTop;
            if (Math.abs(cur - lastSet) > 1.5) return;
            const diff = target - cur;
            if (Math.abs(diff) < 1) { el.scrollTop = target; return; }
            let move = diff * EASE;
            if (Math.abs(move) < 1) move = diff > 0 ? 1 : -1;
            el.scrollTop = cur + move;
            lastSet = el.scrollTop;
            if (Math.abs(lastSet - cur) < 0.1) return;
            queue();
        }

        el.addEventListener("wheel", function(e) {
            if (e.ctrlKey || e.shiftKey || dragged) { stop(); return; }
            if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) return;
            // A frame that never ran (page was not drawing) must not leave the
            // wheel swallowed forever.
            if (raf && performance.now() - rafAt > 150) stop();
            const max = el.scrollHeight - el.clientHeight;
            if (max <= 0) return;
            let dy = e.deltaY;
            if (e.deltaMode === 1) dy *= 40;
            else if (e.deltaMode === 2) dy *= el.clientHeight;
            const base = raf ? target : el.scrollTop;
            const next = Math.max(0, Math.min(max, base + dy));
            e.preventDefault();
            if (next === base && !raf) return;
            target = next;
            if (!raf) {
                lastSet = el.scrollTop;
                queue();
            }
        }, { passive: false });
    }

    function bindAll() {
        bind(document.getElementById("tableData"));
        bind(document.getElementById("expand_container"));
        bind(document.getElementById("groundData"));
    }

    if (document.readyState !== "loading") bindAll();
    else document.addEventListener("DOMContentLoaded", bindAll);
})();
