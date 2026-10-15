let creatorDebugEnabled = false;
const creatorDebugLog = (...args) => { if (creatorDebugEnabled) console.log(...args); };

let pinElem = [];
let pinPerso = [];

let globalMenuStructure = {
    CharacterSexe: true,
    CharacterLore: true,
    CharacterBirthday: true,
    playAsAPed: false,
    EditPed: false
};

let userPed = false;
let userSexe = "Male";
let isSecondChanceMode = false;


let EditionElem = [];
let pedsList = [];
let categories = [];
let items = [];
let currentOutfitMode = null;
let clothingPinData = [];
let clothingGroupOpen = false;
let barberPinData = [];
let barberGroupOpen = false;
let currentInlineContextData = null;


// NUI reliability layer: keep only the newest value for fast-changing controls.
// This prevents slider/matrix spam from applying stale values after a newer choice.
const creatorNuiLatestChannels = new Map();

function creatorPost(endpoint, payload = {}, onResponse) {
    const endpointName = String(endpoint || '');
    const longRequest = new Set(['spawnCharacter', 'createNewChar', 'PlaySelectedChar', 'SaveSecondChance']);
    const timeout = longRequest.has(endpointName) ? 40000 : 10000;
    const request = $.ajax({
        url: `https://${GetParentResourceName()}/${endpointName}`,
        method: 'POST',
        data: JSON.stringify(payload || {}),
        contentType: 'application/json; charset=UTF-8',
        timeout
    });
    if (typeof onResponse === 'function') request.done(onResponse);
    return request;
}

// Chromium can finish loading after Lua has already tried to open the creator.
// Announce document readiness independently from any game message so Lua can
// queue/replay the first selector/creator presentation instead of losing it.
let characterNuiBootAcknowledged = false;
let characterNuiBootRetryTimer = null;

function announceCharacterNuiReady(delay = 0) {
    if (characterNuiBootAcknowledged) return;
    if (characterNuiBootRetryTimer) {
        window.clearTimeout(characterNuiBootRetryTimer);
        characterNuiBootRetryTimer = null;
    }

    characterNuiBootRetryTimer = window.setTimeout(() => {
        characterNuiBootRetryTimer = null;
        let request;
        try {
            request = creatorPost('characterNuiReady', {
                readyState: String(document.readyState || ''),
                timestamp: Date.now()
            }, response => {
                let result = response;
                if (typeof result === 'string') {
                    try { result = JSON.parse(result); } catch (_) { result = {}; }
                }
                if (!result || result.ok !== false) {
                    characterNuiBootAcknowledged = true;
                }
            });
        } catch (_) {
            announceCharacterNuiReady(400);
            return;
        }

        if (request && typeof request.always === 'function') {
            request.always(() => {
                if (!characterNuiBootAcknowledged) announceCharacterNuiReady(400);
            });
        } else if (!characterNuiBootAcknowledged) {
            announceCharacterNuiReady(400);
        }
    }, Math.max(0, Number(delay) || 0));
}

// Recover the native RedM cursor after alt-tab/front-end focus changes. The
// Lua side only honors this while the character UI explicitly owns NUI focus.
let characterFocusRecoveryTimer = null;
// Last time the player pressed the mouse inside the page. A click proves the
// cursor already works, and the recovery below toggles NUI focus off/on -
// doing that right after a click into a text field dropped the caret, so the
// next letters typed (W/A/S/D) drove the creator camera instead of the name.
let characterLastPointerDownAt = 0;
window.addEventListener('pointerdown', () => { characterLastPointerDownAt = Date.now(); }, true);

function isCreatorTextField(element) {
    if (!element || element === document.body) return false;
    if (element.isContentEditable) return true;
    if (element.tagName === 'TEXTAREA') return true;
    if (element.tagName !== 'INPUT') return false;
    const type = String(element.type || 'text').toLowerCase();
    return !['range', 'checkbox', 'radio', 'button', 'submit', 'reset', 'color', 'file', 'image'].includes(type);
}

function requestCharacterFocusRecovery(reason = 'browser-focus') {
    if (characterFocusRecoveryTimer) window.clearTimeout(characterFocusRecoveryTimer);
    characterFocusRecoveryTimer = window.setTimeout(() => {
        characterFocusRecoveryTimer = null;
        if (Date.now() - characterLastPointerDownAt < 600 || isCreatorTextField(document.activeElement)) return;
        try {
            creatorPost('characterFocusRecovery', { reason: String(reason || '') });
        } catch (_) {}
    }, 40);
}

window.addEventListener('focus', () => requestCharacterFocusRecovery('window-focus'));
document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
        requestCharacterFocusRecovery('document-visible');
    }
});

function creatorPostLatest(channel, endpoint, payload = {}, onResponse) {
    const key = String(channel || endpoint);
    let state = creatorNuiLatestChannels.get(key);
    if (!state) {
        state = { inFlight: false, pending: null };
        creatorNuiLatestChannels.set(key, state);
    }

    state.pending = { endpoint, payload, onResponse };
    if (state.inFlight) return;

    const dispatch = () => {
        if (state.inFlight || !state.pending) return;
        const current = state.pending;
        state.pending = null;
        state.inFlight = true;

        let request;
        try {
            request = creatorPost(current.endpoint, current.payload, current.onResponse);
        } catch (_) {
            state.inFlight = false;
            if (state.pending) requestAnimationFrame(dispatch);
            return;
        }

        if (request && typeof request.always === 'function') {
            // A Lua callback that errors never answers, and the request then
            // sits until the 10s ajax timeout - every control on this channel
            // looked frozen for that long. Free the channel after 1.5s; a late
            // answer from the old request is harmless for latest-value posts.
            let released = false;
            let failsafe = null;
            const release = () => {
                if (released) return;
                released = true;
                if (failsafe) window.clearTimeout(failsafe);
                state.inFlight = false;
                // setTimeout, not requestAnimationFrame: CEF pauses rAF while
                // the NUI surface isn't painting, which parked the queue.
                if (state.pending) window.setTimeout(dispatch, 16);
            };
            failsafe = window.setTimeout(release, 1500);
            request.always(release);
        } else {
            // Fallback for older embedded jQuery builds.
            window.setTimeout(() => {
                state.inFlight = false;
                if (state.pending) dispatch();
            }, 24);
        }
    };

    dispatch();
}

function creatorLatestChannel(endpoint, payload = {}) {
    return [
        endpoint,
        payload.category ?? '',
        payload.elem ?? '',
        payload.ElementID ?? '',
        payload.matriceId ?? '',
        payload.advancedValue ?? '',
        payload.tintId ?? '',
        payload.cameraName ?? '',
        payload.action ?? ''
    ].join(':');
}

function creatorPostControl(endpoint, payload = {}, onResponse) {
    creatorPostLatest(creatorLatestChannel(endpoint, payload), endpoint, payload, onResponse);
}

function creatorPostAction(element, endpoint, payload = {}, onResponse) {
    if (!element || element.dataset.creatorBusy === '1') return null;
    element.dataset.creatorBusy = '1';
    element.classList.add('creator-action-busy');
    element.setAttribute('aria-disabled', 'true');

    const release = () => {
        element.dataset.creatorBusy = '0';
        element.classList.remove('creator-action-busy');
        element.removeAttribute('aria-disabled');
    };

    let request;
    try {
        request = creatorPost(endpoint, payload, onResponse);
    } catch (error) {
        release();
        throw error;
    }

    if (request && typeof request.always === 'function') {
        request.always(release);
    } else {
        window.setTimeout(release, 1000);
    }
    return request;
}

// Every creator panel is a tall side panel drawn from a 1920x1080 design, so
// the binding constraint is vertical room, not horizontal. Scaling by
// min(w/1920, h/1080) made 4:3 / 5:4 clients (1024x768, 1280x1024) shrink the
// whole UI to ~53% while a third of the screen height stayed empty. Width is
// still bounded, but against the width a single panel column actually needs.
const CREATOR_DESIGN_HEIGHT = 1080;
const CREATOR_DESIGN_WIDTH = 1280;
const CREATOR_MIN_SCALE = 0.5;
const CREATOR_MAX_SCALE = 2.0;

function updateCreatorViewportMetrics() {
    const viewport = window.visualViewport;
    const width = Math.max(1, Number(viewport?.width) || window.innerWidth ||
        document.documentElement.clientWidth || 1920);
    const height = Math.max(1, Number(viewport?.height) || window.innerHeight ||
        document.documentElement.clientHeight || 1080);
    const rawScale = Math.min(height / CREATOR_DESIGN_HEIGHT, width / CREATOR_DESIGN_WIDTH);
    // Lower bound keeps very small windowed clients inside the screen; the upper
    // cap prevents 4K panels from becoming unnecessarily huge.
    const scale = Math.max(CREATOR_MIN_SCALE, Math.min(CREATOR_MAX_SCALE, rawScale));
    const root = document.documentElement;
    root.style.setProperty('--creator-scale', scale.toFixed(4));
    root.style.setProperty('--creator-viewport-width', `${width}px`);
    root.style.setProperty('--creator-viewport-height', `${height}px`);
    root.style.setProperty('--creator-layout-width', `${(width / scale).toFixed(2)}px`);
    root.style.setProperty('--creator-layout-height', `${(height / scale).toFixed(2)}px`);
    root.style.setProperty('--creator-aspect', (width / height).toFixed(4));
    updateCreatorRightColumnReserve();
}

// The View Controls panel is pinned bottom-right while the Variation / Tint /
// Camera panels are pinned top-right. Publish the real height of the controls
// so those panels cap themselves instead of growing into the controls.
function updateCreatorRightColumnReserve() {
    const controls = document.getElementById('CreatorPlayerControls');
    const root = document.documentElement;
    const scale = Number(getComputedStyle(root).getPropertyValue('--creator-scale')) || 1;
    let reserved = 0;

    if (controls && !controls.classList.contains('hidden')) {
        const rect = controls.getBoundingClientRect();
        if (rect.height > 0) {
            // Convert back into the zoomed design space the panels lay out in.
            reserved = Math.round((rect.height / scale) + 28);
        }
    }

    root.style.setProperty('--creator-right-reserved', `${reserved}px`);
}

// CEF can report a stale innerWidth/innerHeight for a frame or two after the
// game resolution changes, so re-measure once the new size has settled.
let creatorViewportSettleTimer = null;
function scheduleCreatorViewportRemeasure() {
    updateCreatorViewportMetrics();
    if (typeof updateCachedDimensions === 'function') updateCachedDimensions();
    if (Array.isArray(pinElem) && pinElem.length > 0) {
        positionPin(pinElem);
    }
    if (creatorViewportSettleTimer) window.clearTimeout(creatorViewportSettleTimer);
    creatorViewportSettleTimer = window.setTimeout(() => {
        creatorViewportSettleTimer = null;
        updateCreatorViewportMetrics();
        if (typeof updateCachedDimensions === 'function') updateCachedDimensions();
        if (Array.isArray(pinElem) && pinElem.length > 0) {
            positionPin(pinElem);
        }
        window.requestAnimationFrame(() => {
            updateCreatorViewportMetrics();
            if (typeof updateCachedDimensions === 'function') updateCachedDimensions();
            if (Array.isArray(pinElem) && pinElem.length > 0) {
                positionPin(pinElem);
            }
        });
    }, 160);
}

updateCreatorViewportMetrics();
window.addEventListener('resize', scheduleCreatorViewportRemeasure, { passive: true });
window.addEventListener('load', scheduleCreatorViewportRemeasure, { passive: true });
window.visualViewport?.addEventListener('resize', scheduleCreatorViewportRemeasure, { passive: true });
window.visualViewport?.addEventListener('scroll', updateCreatorViewportMetrics, { passive: true });

// CEF does not always fire a window resize when the game resolution changes
// underneath the NUI surface, which would leave every panel scaled for the old
// screen. Watching the root element catches that case for free.
let lastCreatorViewportKey = `${Math.round(window.innerWidth)}x${Math.round(window.innerHeight)}`;

function creatorViewportChanged() {
    const key = `${Math.round(window.innerWidth)}x${Math.round(window.innerHeight)}`;
    if (key === lastCreatorViewportKey) return false;
    lastCreatorViewportKey = key;
    return true;
}

if (typeof ResizeObserver === 'function') {
    new ResizeObserver(() => {
        if (creatorViewportChanged()) scheduleCreatorViewportRemeasure();
    }).observe(document.documentElement);
}

// ResizeObserver and the resize event are both tied to the rendering lifecycle,
// which CEF suspends while the NUI surface is not being painted. A one-second
// size comparison is the only check that survives that, and it costs nothing.
window.setInterval(() => {
    if (creatorViewportChanged()) scheduleCreatorViewportRemeasure();
}, 1000);


// ===== Stable selection state + creator view controls =====
function creatorIdsEqual(a, b) {
    return String(a ?? '') === String(b ?? '');
}

function setCreatorStyleSelection(itemId) {
    document.querySelectorAll('.styleElem.selected').forEach(element => element.classList.remove('selected'));
    const selected = document.getElementById(`item_${itemId}`);
    if (selected) selected.classList.add('selected');
}

function setCreatorColourSelection(prefix, colours, value) {
    const selectedValue = String(value ?? '');
    (Array.isArray(colours) ? colours : []).forEach(colour => {
        const element = document.getElementById(`${prefix}${colour.id}`);
        if (!element) return;
        const active = String(colour.id) === selectedValue;
        element.classList.toggle('selected', active);
        element.setAttribute('aria-selected', active ? 'true' : 'false');
    });
}

function isCreatorElementVisible(id) {
    const element = document.getElementById(id);
    return !!element && !element.classList.contains('hidden');
}

let creatorViewControlsFrame = null;
function scheduleCreatorViewControlsSync() {
    if (creatorViewControlsFrame !== null) return;
    creatorViewControlsFrame = window.requestAnimationFrame(() => {
        creatorViewControlsFrame = null;
        syncCreatorViewControls();
    });
}

function creatorHasActiveEditTarget() {
    return isCreatorElementVisible('BodyPartsMenu') ||
        isCreatorElementVisible('CharactersMenu') ||
        isCreatorElementVisible('GlobalCharacterMenu') ||
        isCreatorElementVisible('EditionMenu') ||
        isCreatorElementVisible('PedSelectionMenu') ||
        isCreatorElementVisible('OutfitMenu') ||
        isCreatorElementVisible('VariationSettings') ||
        isCreatorElementVisible('TintSettings') ||
        isCreatorElementVisible('CameraSettings');
}

function syncCreatorViewControls() {
    const controls = document.getElementById('CreatorPlayerControls');
    if (!controls) return;

    const editing = creatorHasActiveEditTarget();
    if (editing) {
        document.getElementById('SelectCharMenu')?.classList.add('hidden');
        document.getElementById('ChooseCharacterMenu')?.classList.add('hidden');
        document.getElementById('SpawnMenu')?.classList.add('hidden');
        controls.classList.remove('hidden');
    } else {
        controls.classList.add('hidden');
    }
    updateCreatorRightColumnReserve();
}

function sendCreatorViewAction(action, extra = {}) {
    creatorPostControl('creatorViewControl', Object.assign({ action: String(action || '') }, extra || {}));
}

function bindCreatorViewControls() {
    const controls = document.getElementById('CreatorPlayerControls');
    if (!controls || controls.dataset.bound === '1') return;
    controls.dataset.bound = '1';

    // Only continuous adjustments auto-repeat while held. Up/Down/Center step
    // the camera to a preset with a 1s interpolation - repeating those every
    // 55ms restarted the interpolation mid-flight and left the camera fighting
    // itself, which read as the creator locking up.
    const REPEATABLE_VIEW_ACTIONS = new Set(['rotateLeft', 'rotateRight', 'panLeft', 'panRight', 'zoomIn', 'zoomOut']);
    // Hard cap on a single hold. CEF inside RedM sometimes never delivers the
    // pointerup (focus flicker, cursor leaving the NUI surface), and without a
    // cap the interval kept rotating/zooming forever.
    const HOLD_MAX_MS = 6000;

    let holdDelay = null;
    let holdInterval = null;
    let holdStartedAt = 0;
    let holdButton = null;
    const stopHold = () => {
        if (holdDelay) window.clearTimeout(holdDelay);
        if (holdInterval) window.clearInterval(holdInterval);
        holdDelay = null;
        holdInterval = null;
        holdStartedAt = 0;
        if (holdButton) holdButton.classList.remove('creator-view-held');
        holdButton = null;
    };

    controls.querySelectorAll('[data-view-action]').forEach(button => {
        const action = button.dataset.viewAction;
        const repeatable = REPEATABLE_VIEW_ACTIONS.has(action);

        button.addEventListener('pointerdown', event => {
            event.preventDefault();
            event.stopPropagation();
            stopHold();
            if (event.button !== undefined && event.button !== 0) return;
            // togglePins is handled on click only - doing it here as well
            // flipped the pins twice per press, so the button did nothing.
            if (action === 'togglePins') return;
            sendCreatorViewAction(action);
            if (!repeatable) return;
            try { button.setPointerCapture(event.pointerId); } catch (_) {}
            holdButton = button;
            button.classList.add('creator-view-held');
            holdStartedAt = Date.now();
            holdDelay = window.setTimeout(() => {
                holdDelay = null;
                holdInterval = window.setInterval(() => {
                    if (!holdStartedAt || Date.now() - holdStartedAt > HOLD_MAX_MS ||
                        controls.classList.contains('hidden') || document.visibilityState === 'hidden') {
                        stopHold();
                        return;
                    }
                    sendCreatorViewAction(action);
                }, 55);
            }, 220);
        });
        button.addEventListener('pointermove', event => {
            // Mouse button already released but the pointerup was lost.
            if (holdButton === button && event.buttons === 0) stopHold();
        });
        button.addEventListener('click', event => {
            event.preventDefault();
            event.stopPropagation();
            if (action === 'togglePins') {
                toggleCreatorPins();
            }
        });
        button.addEventListener('pointerup', stopHold);
        button.addEventListener('pointercancel', stopHold);
        button.addEventListener('lostpointercapture', stopHold);
        button.addEventListener('pointerleave', stopHold);
    });

    controls.querySelectorAll('[data-view-focus]').forEach(button => {
        const target = String(button.dataset.viewFocus || '').trim();
        if (!target) return;
        button.addEventListener('pointerdown', event => {
            event.preventDefault();
            event.stopPropagation();
            stopHold();
            sendCreatorViewAction('focus', { target });
        });
        button.addEventListener('click', event => {
            event.preventDefault();
            event.stopPropagation();
        });
    });

    window.addEventListener('pointerup', stopHold, { passive: true });
    window.addEventListener('mouseup', stopHold, { passive: true });
    window.addEventListener('blur', stopHold);
    document.addEventListener('visibilitychange', stopHold);
    controls.addEventListener('wheel', event => {
        event.preventDefault();
        event.stopPropagation();
        sendCreatorViewAction(event.deltaY < 0 ? 'zoomIn' : 'zoomOut');
    }, { passive: false });

    if (!window.__jrsCreatorWheelBound) {
        window.__jrsCreatorWheelBound = true;
        window.addEventListener('wheel', event => {
            const ctrl = document.getElementById('CreatorPlayerControls');
            if (!ctrl || ctrl.classList.contains('hidden')) return;
            const target = event.target;
            // Zoom only when the wheel is over the scene itself. Scrolling over
            // any panel (the identity form, the story box, edit sliders) used
            // to zoom the camera behind it.
            if (target && target.closest && target.closest('.Categories, .ContextSettings, .TintList, .edition_scroll, .scrollable, #OutfitList, .creator-player-controls, .CharactersMenuContent, #EditionMenuContent, #PedSelectionMenuContent, #OutfitMenuContent, #OutfitListMenuContent, #OutfitVariationContent, #VariationSettings, #TintSettings, #CameraSettings, input, textarea, select, button')) {
                return;
            }
            if (isCreatorTextField(document.activeElement)) return;
            sendCreatorViewAction(event.deltaY < 0 ? 'zoomIn' : 'zoomOut');
        }, { passive: true });
    }
}

let globalApparenceMenu = [];
let eyeApparenceMenu = [];
// Eye colours shown inside the Edit Appearance panel (Global Settings).
// Separate from eyeApparenceMenu, which drives the contextual eyes panel that
// only opens from the face pin.
let eyeGlobalColours = [];
let skinApparenceMenu = [];

// Height slider -> centimetres. Same formula as JRSHeightToCm in client.lua:
//   scale = min + (slider / 100) * (max - min);  cm = round(baseCm * scale)
function creatorHeightCm(value) {
    const entry = (globalApparenceMenu || []).find(e => e && e.id === 'height') || {};
    const min = Number.isFinite(Number(entry.heightMin)) ? Number(entry.heightMin) : 0.95;
    const max = Number.isFinite(Number(entry.heightMax)) ? Number(entry.heightMax) : 1.05;
    const baseCm = Number(entry.heightBaseCm) > 0 ? Number(entry.heightBaseCm) : 180;
    const slider = Math.max(0, Math.min(100, Number(value) || 0));
    return Math.round(baseCm * (min + (slider / 100) * (max - min)));
}

function formatBodyOrStyleValue(id, value) {
    if (id === 'height') {
        return `${creatorHeightCm(value)} ${JrsI18n.t("character_height_cm", "cm")}`;
    }
    const valNum = parseInt(value) || 0;
    if ((id === 'bodies_upper' || id === 'bodies_lower' || id === 'upper' || id === 'legs') && valNum === 0) {
        if (id === 'bodies_upper' || id === 'upper') {
            return (window.JrsI18n && typeof window.JrsI18n.t === 'function')
                ? JrsI18n.t("character_body_upper_erased", "مسح المعصم والخصر (مخفي)")
                : "Erased / Hidden";
        } else {
            return (window.JrsI18n && typeof window.JrsI18n.t === 'function')
                ? JrsI18n.t("character_body_lower_erased", "مسح الفخوذ والخصر (مخفي)")
                : "Erased / Hidden";
        }
    }
    return `${JrsI18n.t("character_style", "Style")} ${value}`;
}
let spawnLocationList = [];
let spawnBookConfig = {};
let actualLocationIndex = 0;
let creatorPinnedMenuId = null;
let creatorPinOutsideClickBound = false;


///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                      GLOBAL ELEMENTS                                              //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////



////////////////////////// ELEMENT EDITION MENU //////////////////////////

// Show menu for edition of selected element
function showElementEditionMenu() {

    createEditionMenu();
    const editionMenu = document.getElementById('EditionMenu');
    editionMenu.classList.remove('hidden');

    // Camera focus is handled automatically by Lua for the selected body part.
    const cameraMenu = document.getElementById('CameraSettings');
    if (cameraMenu) cameraMenu.classList.add('hidden');
}

function hideElementEditionMenu() {
    const editionMenu = document.getElementById('EditionMenu');
    editionMenu.classList.add('hidden');

    const editionContainer = document.getElementById('EditionMenuElemList');
    editionContainer.innerHTML = '';

    //CAM
    const cameraMenu = document.getElementById('CameraSettings');
    cameraMenu.classList.add('hidden');
}

// Show menu for body parts
function showBodyPartsMenu() {

    resetCreatorPinMenus();
    const bodyPartsMenu = document.getElementById('BodyPartsMenu');
    bodyPartsMenu.classList.remove('hidden');
    scheduleCreatorViewControlsSync();
}

function hideBodyPartsMenu() {

    resetCreatorPinMenus();
    const bodyPartsMenu = document.getElementById('BodyPartsMenu');
    bodyPartsMenu.classList.add('hidden');
    scheduleCreatorViewControlsSync();
}

// Show menu for body parts
function showCharSelectMenu() {
    const selectCharMenu = document.getElementById('SelectCharMenu');
    if (selectCharMenu) selectCharMenu.classList.remove('hidden');
}

function hideCharSelectMenu() {
    const selectCharMenu = document.getElementById('SelectCharMenu');
    if (selectCharMenu) selectCharMenu.classList.add('hidden');
}

//Global Character Menu
function showCharGlobalMenu() {
    const charGlobalMenu = document.getElementById('CharactersMenu');
    if (charGlobalMenu) charGlobalMenu.classList.remove('hidden');
    scheduleCreatorViewControlsSync();
}

function hideCharGlobalMenu() {
    const charGlobalMenu = document.getElementById('CharactersMenu');
    if (charGlobalMenu) charGlobalMenu.classList.add('hidden');
    scheduleCreatorViewControlsSync();
}


//Ped list menu
function showPedListMenu() {
    const pedListMenu = document.getElementById('PedSelectionMenu');
    pedListMenu.classList.remove('hidden');
    loadPeds();
}

function hidePedListMenu() {
    const pedListMenu = document.getElementById('PedSelectionMenu');
    pedListMenu.classList.add('hidden');
}

////////////////////////// OUTFIT MENU (MODIFICATION / CREATION) //////////////////////////

// Show and Hide Job Menu
function showOutfitMenu() {
    const outfitMenu = document.getElementById('OutfitMenu');
    const categoriesContainer = document.getElementById('Categories');
    const clothingBodySelector = document.getElementById('ClothingBodySelector');
    const barberBodySelector = document.getElementById('BarberBodySelector');
    const selectedSection = document.getElementById('SelectedOutfitSection');
    const cameraMenu = document.getElementById('CameraSettings');

    outfitMenu.classList.remove('hidden');
    outfitMenu.classList.remove('clothing-body-mode', 'barber-body-mode');
    if (cameraMenu) cameraMenu.classList.add('hidden');
    if (clothingBodySelector) clothingBodySelector.classList.add('hidden');
    if (barberBodySelector) barberBodySelector.classList.add('hidden');

    currentSelectedCategorie = null;
    currentSelectedItem = null;
    hideContextualMenu();
    loadItems();

    if (selectedSection) selectedSection.classList.add('hidden');
    if (clothingBodySelector) clothingBodySelector.classList.add('hidden');
    if (barberBodySelector) barberBodySelector.classList.add('hidden');
    if (categoriesContainer) categoriesContainer.classList.remove('hidden');
    loadCategories();

    const backButton = document.getElementById('CancelOutfit');
    if (backButton) backButton.textContent = JrsI18n.t("character_back", "Back");
    scheduleCreatorViewControlsSync();
}

// Hide Outfit Menu
function hideOutfitMenu() {
    const outfitMenu = document.getElementById('OutfitMenu');
    const cameraMenu = document.getElementById('CameraSettings');
    const clothingBodySelector = document.getElementById('ClothingBodySelector');
    const barberBodySelector = document.getElementById('BarberBodySelector');
    const selectedSection = document.getElementById('SelectedOutfitSection');
    outfitMenu.classList.add('hidden');
    outfitMenu.classList.remove('clothing-body-mode', 'barber-body-mode');
    if (cameraMenu) cameraMenu.classList.add('hidden');
    if (clothingBodySelector) clothingBodySelector.classList.add('hidden');
    if (barberBodySelector) barberBodySelector.classList.add('hidden');
    if (selectedSection) selectedSection.classList.add('hidden');

    const categoriesContainer = document.getElementById('Categories');
    categoriesContainer.innerHTML = '';
    categoriesContainer.classList.remove('hidden');

    const clothingPins = document.getElementById('clothingPinContainer');
    if (clothingPins) clothingPins.innerHTML = '';
    clothingPinData = [];
    clothingGroupOpen = false;

    const barberPins = document.getElementById('barberPinContainer');
    if (barberPins) barberPins.innerHTML = '';
    barberPinData = [];
    barberGroupOpen = false;

    const itemsContainer = document.getElementById('StyleProperties');
    itemsContainer.innerHTML = '';

    hideContextualMenu();

    // The integrated creator does not use the legacy CreateOutfit button.
    const createOutfitButton = document.getElementById('CreateOutfit');
    if (createOutfitButton) {
        createOutfitButton.textContent = 'Save - $0.00';
    }
    currentOutfitMode = null;
    scheduleCreatorViewControlsSync();
}

function requestAutomaticOutfitCamera(category, group) {
    $.post(`https://${GetParentResourceName()}/focusOutfitCategory`, JSON.stringify({
        mode: currentOutfitMode,
        category: category || group,
        group: group || category
    }));
}

function selectClothingBodyGroup(groupId) {
    const category = categories.find(entry => String(entry.id) === String(groupId));
    if (!category) return;

    currentSelectedCategorie = category.id;
    currentSelectedItem = null;
    clothingGroupOpen = true;
    changeCategory(category.id);
    hideContextualMenu();

    const clothingBodySelector = document.getElementById('ClothingBodySelector');
    if (clothingBodySelector) clothingBodySelector.classList.add('hidden');
    const backButton = document.getElementById('CancelOutfit');
    if (backButton) backButton.textContent = JrsI18n.t("character_back_to_clothing_areas", "Back to Clothing Areas");

    const selectedSection = document.getElementById('SelectedOutfitSection');
    if (selectedSection) {
        selectedSection.textContent = category.name || category.id;
        selectedSection.classList.remove('hidden');
    }

    document.querySelectorAll('.clothing-body-pin').forEach(pin => {
        pin.classList.toggle('selected', String(pin.dataset.group) === String(category.id));
    });
    document.querySelectorAll('.styleElem').forEach(item => item.classList.remove('selected'));
    requestAutomaticOutfitCamera(category.id, category.id);
    scheduleCreatorViewControlsSync();
}

function returnToClothingBodyAreas() {
    clothingGroupOpen = false;
    currentSelectedCategorie = null;
    currentSelectedItem = null;
    hideContextualMenu();

    document.querySelectorAll('#StyleProperties .styleElem').forEach(item => {
        item.classList.add('hidden');
        item.classList.remove('selected');
    });
    document.querySelectorAll('.clothing-body-pin').forEach(pin => pin.classList.remove('selected'));

    const selectedSection = document.getElementById('SelectedOutfitSection');
    if (selectedSection) {
        selectedSection.textContent = JrsI18n.t("character_select_a_clothing_area", "Select a clothing area");
        selectedSection.classList.remove('hidden');
    }
    const selector = document.getElementById('ClothingBodySelector');
    if (selector) selector.classList.remove('hidden');
    const backButton = document.getElementById('CancelOutfit');
    if (backButton) backButton.textContent = JrsI18n.t("character_back", "Back");
    requestAutomaticOutfitCamera(null, null);
    scheduleCreatorViewControlsSync();
}

function renderClothingBodyPins(pins) {
    if (currentOutfitMode !== 'clothing') return;
    const selector = document.getElementById('ClothingBodySelector');
    if (selector && !clothingGroupOpen) selector.classList.remove('hidden');
    const container = document.getElementById('clothingPinContainer');
    if (!container) return;

    const pinMap = new Map((pins || []).map(pin => [String(pin.id), pin]));
    const preparedPins = [];

    categories.forEach(category => {
        const key = String(category.id);
        const pin = pinMap.get(key);
        if (!pin) return;

        let element = document.getElementById(`clothing_pin_${key}`);
        if (!element) {
            element = document.createElement('button');
            element.type = 'button';
            element.id = `clothing_pin_${key}`;
            element.dataset.group = key;
            element.className = 'clothing-body-pin';
            element.innerHTML = `<img src="${category.image}" alt=""><span>${category.name}</span>`;
            element.addEventListener('click', () => selectClothingBodyGroup(category.id));
            container.appendChild(element);
        }

        const rawX = (Number(pin.x) || 0) + (Number(pin.offsetX) || 0);
        const rawY = (Number(pin.y) || 0) + (Number(pin.offsetY) || 0);
        const pinX = Math.max(0.035, Math.min(0.965, rawX));
        const pinY = Math.max(0.055, Math.min(0.945, rawY));

        // Respect the side selected by the Lua skeleton layout. Only flip when
        // the card would otherwise leave the viewport.
        let direction = pin.direction === 'left' ? 'left' : 'right';
        if (pinX < 0.17) direction = 'right';
        if (pinX > 0.83) direction = 'left';

        preparedPins.push({
            element,
            pin,
            x: pinX,
            y: pinY,
            direction,
            visible: pin.visible !== false
        });
    });

    // Keep cards on each side separated. This protects the layout on different
    // resolutions/FOV values without detaching the selector from its body area.
    const distributeSide = (entries) => {
        const visible = entries.filter(entry => entry.visible).sort((a, b) => a.y - b.y);
        if (visible.length < 2) return;

        const minY = 0.075;
        const maxY = 0.925;
        const minimumGap = Math.max(0.068, 66 / Math.max(window.innerHeight, 720));

        visible[0].y = Math.max(minY, visible[0].y);
        for (let index = 1; index < visible.length; index += 1) {
            visible[index].y = Math.max(visible[index].y, visible[index - 1].y + minimumGap);
        }

        if (visible[visible.length - 1].y > maxY) {
            visible[visible.length - 1].y = maxY;
            for (let index = visible.length - 2; index >= 0; index -= 1) {
                visible[index].y = Math.min(visible[index].y, visible[index + 1].y - minimumGap);
            }
        }

        if (visible[0].y < minY) {
            const shift = minY - visible[0].y;
            visible.forEach(entry => { entry.y += shift; });
        }
    };

    distributeSide(preparedPins.filter(entry => entry.direction === 'left'));
    distributeSide(preparedPins.filter(entry => entry.direction === 'right'));

    preparedPins.forEach(entry => {
        const { element, direction } = entry;
        element.classList.toggle('pin-left', direction === 'left');
        element.classList.toggle('pin-right', direction !== 'left');
        element.style.left = `${entry.x * 100}%`;
        element.style.top = `${entry.y * 100}%`;
        element.style.visibility = entry.visible ? 'visible' : 'hidden';
        element.style.zIndex = String(30 + Math.round((1 - entry.y) * 10));
    });
}


function selectBarberBodyGroup(groupId) {
    const category = categories.find(entry => String(entry.id) === String(groupId));
    if (!category) return;

    currentSelectedCategorie = category.id;
    currentSelectedItem = null;
    barberGroupOpen = true;
    changeCategory(category.id);
    hideContextualMenu();

    const barberBodySelector = document.getElementById('BarberBodySelector');
    if (barberBodySelector) barberBodySelector.classList.add('hidden');
    const backButton = document.getElementById('CancelOutfit');
    if (backButton) backButton.textContent = JrsI18n.t("character_back_to_hair_face_areas", "Back to Hair & Face Areas");

    const selectedSection = document.getElementById('SelectedOutfitSection');
    if (selectedSection) {
        selectedSection.textContent = category.name || category.id;
        selectedSection.classList.remove('hidden');
    }

    document.querySelectorAll('.barber-body-pin').forEach(pin => {
        pin.classList.toggle('selected', String(pin.dataset.group) === String(category.id));
    });
    document.querySelectorAll('.styleElem').forEach(item => item.classList.remove('selected'));
    requestAutomaticOutfitCamera(category.id, category.id);
}

function returnToBarberBodyAreas() {
    barberGroupOpen = false;
    currentSelectedCategorie = null;
    currentSelectedItem = null;
    hideContextualMenu();

    document.querySelectorAll('#StyleProperties .styleElem').forEach(item => {
        item.classList.add('hidden');
        item.classList.remove('selected');
    });
    document.querySelectorAll('.barber-body-pin').forEach(pin => pin.classList.remove('selected'));

    const selectedSection = document.getElementById('SelectedOutfitSection');
    if (selectedSection) {
        selectedSection.textContent = JrsI18n.t("character_select_a_hair_or_face_area", "Select a hair or face area");
        selectedSection.classList.remove('hidden');
    }
    const selector = document.getElementById('BarberBodySelector');
    if (selector) selector.classList.remove('hidden');
    const backButton = document.getElementById('CancelOutfit');
    if (backButton) backButton.textContent = JrsI18n.t("character_back", "Back");
    requestAutomaticOutfitCamera(null, null);
}

function renderBarberBodyPins(pins) {
    if (currentOutfitMode !== 'barber') return;
    const selector = document.getElementById('BarberBodySelector');
    if (selector && !barberGroupOpen) selector.classList.remove('hidden');
    const container = document.getElementById('barberPinContainer');
    if (!container) return;

    const pinMap = new Map((pins || []).map(pin => [String(pin.id), pin]));
    categories.forEach(category => {
        const key = String(category.id);
        const pin = pinMap.get(key);
        if (!pin) return;

        let element = document.getElementById(`barber_pin_${key}`);
        if (!element) {
            element = document.createElement('button');
            element.type = 'button';
            element.id = `barber_pin_${key}`;
            element.dataset.group = key;
            element.className = 'barber-body-pin';
            element.innerHTML = `<img src="${category.image}" alt=""><span>${category.name}</span>`;
            element.addEventListener('click', () => selectBarberBodyGroup(category.id));
            container.appendChild(element);
        }

        element.classList.toggle('pin-left', pin.direction === 'left');
        element.classList.toggle('pin-right', pin.direction !== 'left');
        element.style.left = `${Math.max(0, Math.min(1, Number(pin.x) || 0)) * 100}%`;
        element.style.top = `${Math.max(0, Math.min(1, Number(pin.y) || 0)) * 100}%`;
        element.style.visibility = pin.visible === false ? 'hidden' : 'visible';
    });
}



function isInlineOutfitContext() {
    return false;
}

function ensureInlineItemSettingsPanel() {
    let panel = document.getElementById('InlineItemSettings');
    if (!panel) {
        // Defensive fallback only - index.html already declares this panel
        // as a static child of #OutfitMenuList, and it now stays there
        // permanently (floats via CSS position:fixed instead of being
        // moved into the selected row), so this branch should not run.
        panel = document.createElement('div');
        panel.id = 'InlineItemSettings';
        panel.className = 'hidden';
        document.getElementById('OutfitMenuList')?.appendChild(panel);
    }
    return panel;
}

function clearInlineItemSettings() {
    const panel = document.getElementById('InlineItemSettings');
    if (panel) {
        panel.classList.add('hidden');
        panel.innerHTML = '';
    }
    document.querySelectorAll('.style-item-wrapper.settings-open').forEach(wrapper => {
        wrapper.classList.remove('settings-open');
    });
    currentInlineContextData = null;
    scheduleCreatorViewControlsSync();
}

const BARBER_HAIR_TONE_CATEGORIES = new Set([
    'hairstabble', 'hair', 'hair_bonnet'
]);

const BARBER_BEARD_TONE_CATEGORIES = new Set([
    'beardstabble', 'beard', 'beards_complete', 'beards_chin', 'beards_chops', 'beards_mustache'
]);

const BARBER_MAKEUP_TONE_CATEGORIES = new Set([
    'eyeliners', 'lipsticks', 'shadows', 'paintedmasks', 'blush', 'blush2', 'foundation'
]);

// Advanced value names arrive from Lua as fixed identifiers ('Palette',
// 'Opacity') that other code compares against, so they are translated only
// where they are displayed.
function creatorAdvancedValueName(name) {
    if (name === 'Opacity') return JrsI18n.t("character_opacity", "Opacity");
    if (name === 'Palette') return JrsI18n.t("character_palette", "Palette");
    return name;
}

function getBarberToneTheme(category) {
    const key = String(category || '').toLowerCase();
    if (BARBER_HAIR_TONE_CATEGORIES.has(key)) {
        return { name: JrsI18n.t("character_hair_tone", "Hair Tone"), className: 'tone-theme-hair' };
    }
    if (BARBER_BEARD_TONE_CATEGORIES.has(key)) {
        return { name: JrsI18n.t("character_beard_tone", "Beard Tone"), className: 'tone-theme-hair' };
    }
    if (key === 'eyebrows') {
        return { name: JrsI18n.t("character_eyebrow_tone", "Eyebrow Tone"), className: 'tone-theme-hair' };
    }
    if (BARBER_MAKEUP_TONE_CATEGORIES.has(key)) {
        return { name: JrsI18n.t("character_makeup_tone", "Makeup Tone"), className: 'tone-theme-makeup' };
    }
    return null;
}

function toneDisplayValue(value, min, max) {
    const numeric = Math.max(min, Math.min(max, Number(value) || min));
    return {
        numeric,
        current: (numeric - min) + 1,
        total: (max - min) + 1
    };
}

function updateToneCaption(id, value, min, max) {
    const display = toneDisplayValue(value, min, max);
    const caption = document.getElementById(id);
    if (caption) caption.textContent = `${JrsI18n.t("character_tone", "Tone")} ${display.current} / ${display.total}`;
}

function buildCircularMeterMarkup({
    id,
    title,
    value,
    min = 0,
    max = 255,
    leftId,
    rightId,
    meterColor = '#c8c8c8',
    accentClass = '',
    valueLabel,
    meterText,
    extraClass = ''
}) {
    const numeric = Math.max(min, Math.min(max, Number(value) || min));
    const range = Math.max(1, max - min);
    const progress = ((numeric - min) / range) * 100;
    const resolvedValueLabel = valueLabel !== undefined ? valueLabel : String(numeric);
    const resolvedMeterText = meterText !== undefined ? meterText : String(numeric);
    return `
        <div class="inline-setting-row ${extraClass}">
            <div class="inline-setting-label unselectable">
                <span class="inline-setting-name ${accentClass}">${title}</span>
                <span class="inline-setting-value" id="${id}_value">${resolvedValueLabel}</span>
            </div>
            <div class="inline-circular-control unselectable">
                <a id="${leftId}" class="arrow circular-arrow"><img src="./img/arrow.png" alt="Previous"></a>
                <div class="inline-circular-meter ${accentClass}" id="${id}_meter" style="--progress:${progress}%; --meter-color:${meterColor};">
                    <div class="inline-circular-meter-inner">
                        <span class="inline-circular-meter-text" id="${id}_meter_text">${resolvedMeterText}</span>
                    </div>
                </div>
                <a id="${rightId}" class="arrow circular-arrow"><img src="./img/arrow.png" alt="Next" style="transform: rotate(180deg);"></a>
            </div>
            <input type="range" id="${id}" class="inline-hidden-range" min="${min}" max="${max}" value="${numeric}">
        </div>
    `;
}

// Same numbered-chip grid jrs_clothing uses for its own native colour/variant
// picker (.jrs-actual-color-*) - used here for the Palette control, which has
// a small discrete option count (unlike the 0-255 continuous tint sliders,
// which stay on the circular meter above).
function buildPaletteChipMarkup({ id, title, value, min = 0, max = 0 }) {
    const lo = Math.floor(Number(min) || 0);
    const hi = Math.max(lo, Math.floor(Number(max) || lo));
    const numeric = Math.max(lo, Math.min(hi, Math.floor(Number(value) || lo)));

    let chips = '';
    for (let i = lo; i <= hi; i++) {
        const selected = i === numeric ? ' selected' : '';
        const swatchHex = window.RDO_HAIR_COLORS?.[(i - lo) % 26]?.hex || '#442b1d';
        chips += `<button type="button" class="jrs-actual-color-chip${selected}" data-value="${i}" aria-label="${JrsI18n.t("character_color", "Color")} ${i - lo + 1}"><span class="jrs-chip-swatch-dot" style="background:${swatchHex};"></span><span>${i - lo + 1}</span><i></i></button>`;
    }

    return `
        <div class="jrs-actual-color-picker">
            <div class="jrs-actual-color-title unselectable"><span>${title}</span><b>${hi - lo + 1}</b></div>
            <div class="jrs-actual-color-grid" id="${id}_grid">${chips}</div>
        </div>
    `;
}

// Same component, but driven by an explicit options array (each entry's own
// UI index, not a contiguous min..max range) - this is what jrs_clothing's
// jrsRenderActualVariantPicker renders for "Style"/variation items that have
// real, distinct native colour variants, kept alongside the Style meter
// rather than replacing it.
function buildNativeColorChipMarkup(id, title, options) {
    const chips = options.map((option, index) => {
        const selected = option.selected ? ' selected' : '';
        const swatchHex = window.getRdoClothingVariantColor ? window.getRdoClothingVariantColor(option, index) : '#33251e';
        return `<button type="button" class="jrs-actual-color-chip${selected}" data-value="${option.value}" aria-label="${JrsI18n.t("character_color", "Color")} ${index + 1}"><span class="jrs-chip-swatch-dot" style="background:${swatchHex};"></span><span>${index + 1}</span><i></i></button>`;
    }).join('');

    return `
        <div class="jrs-actual-color-picker">
            <div class="jrs-actual-color-title unselectable"><span>${title}</span><b>${options.length}</b></div>
            <div class="jrs-actual-color-grid" id="${id}_grid">${chips}</div>
        </div>
    `;
}

function updateCircularMeter(id, value, min, max, options = {}) {
    const numeric = Math.max(min, Math.min(max, Number(value) || min));
    const range = Math.max(1, max - min);
    const progress = ((numeric - min) / range) * 100;
    const meter = document.getElementById(`${id}_meter`);
    if (meter) {
        meter.style.setProperty('--progress', `${progress}%`);
        if (options.color) {
            meter.style.setProperty('--meter-color', options.color);
        }
    }
    const meterText = document.getElementById(`${id}_meter_text`);
    if (meterText) meterText.textContent = String(options.meterText !== undefined ? options.meterText : numeric);
    const valueElement = document.getElementById(`${id}_value`);
    if (valueElement) valueElement.textContent = String(options.valueLabel !== undefined ? options.valueLabel : numeric);
}

function bindCircularMeterDrag(id, min, max, onValue) {
    const meter = document.getElementById(`${id}_meter`);
    const range = document.getElementById(id);
    if (!meter || !range || typeof onValue !== 'function') return;

    let dragging = false;
    let lastValue = Number(range.value) || min;

    const valueFromPointer = event => {
        const rect = meter.getBoundingClientRect();
        const centerX = rect.left + rect.width / 2;
        const centerY = rect.top + rect.height / 2;
        const dx = event.clientX - centerX;
        const dy = event.clientY - centerY;

        // CSS conic-gradient begins at twelve o'clock and moves clockwise.
        let angle = Math.atan2(dy, dx) * (180 / Math.PI) + 90;
        if (angle < 0) angle += 360;

        const span = Math.max(1, max - min);
        return Math.max(min, Math.min(max, Math.round(min + (angle / 360) * span)));
    };

    const applyPointer = event => {
        const value = valueFromPointer(event);
        if (value === lastValue) return;
        lastValue = value;
        range.value = String(value);
        onValue(value, false);
    };

    meter.addEventListener('pointerdown', event => {
        event.preventDefault();
        dragging = true;
        meter.classList.add('is-dragging');
        meter.setPointerCapture?.(event.pointerId);
        applyPointer(event);
    });

    meter.addEventListener('pointermove', event => {
        if (!dragging) return;
        event.preventDefault();
        applyPointer(event);
    });

    const finishDrag = event => {
        if (!dragging) return;
        dragging = false;
        meter.classList.remove('is-dragging');
        meter.releasePointerCapture?.(event.pointerId);
        onValue(lastValue, true);
    };

    meter.addEventListener('pointerup', finishDrag);
    meter.addEventListener('pointercancel', finishDrag);
}

function buildToneSliderMarkup({
    id,
    title,
    value,
    min = 0,
    max = 255,
    theme = 'tone-theme-hair',
    leftId,
    rightId
}) {
    const display = toneDisplayValue(value, min, max);
    return `
        <div class="tone-slider-card ${theme}">
            <div class="tone-slider-heading unselectable">${title}</div>
            <div class="tone-slider-control unselectable">
                <a id="${leftId}" class="arrow tone-arrow"><img src="./img/arrow.png" alt="Previous"></a>
                <div class="tone-slider-main">
                    <div class="tone-slider-endpoints"><span>${JrsI18n.t("character_tone_light", "Light")}</span><span>${JrsI18n.t("character_tone_dark", "Dark")}</span></div>
                    <input type="range" id="${id}" class="tone-range" min="${min}" max="${max}" value="${display.numeric}">
                    <div class="tone-slider-caption" id="${id}_caption">${JrsI18n.t("character_tone", "Tone")} ${display.current} / ${display.total}</div>
                </div>
                <a id="${rightId}" class="arrow tone-arrow"><img src="./img/arrow.png" alt="Next" style="transform: rotate(180deg);"></a>
            </div>
        </div>
    `;
}

function tintPreviewColour(value, tintId) {
    const numeric = Math.max(0, Math.min(255, Number(value) || 0));
    if (numeric === 0) return '#202020';
    if (window.RDO_HAIR_COLORS && window.RDO_HAIR_COLORS.length > 0) {
        return window.RDO_HAIR_COLORS[numeric % window.RDO_HAIR_COLORS.length].hex;
    }
    return '#3a261c';
}

function updateInlineTintDisplay(tintId, value) {
    const preview = tintPreviewColour(value, tintId);
    updateCircularMeter(`inline_tint_range_${tintId}`, value, 0, 255, {
        valueLabel: value,
        meterText: value,
        color: preview
    });
    updateToneCaption(`inline_tint_range_${tintId}_caption`, value, 0, 255);
}

function postInlineValue(endpoint, payload) {
    creatorPostControl(endpoint, payload);
}

function renderInlineOutfitContextualData(contextualData) {
    if (!isInlineOutfitContext() || !contextualData) return;

    const category = String(contextualData.category || currentSelectedItem || '');
    if (!category) return;

    const wrapper = document.getElementById(`style_wrapper_${category}`);
    const selectedRow = document.getElementById(`item_${category}`);
    const panel = ensureInlineItemSettingsPanel();
    if (!wrapper || !selectedRow || !panel) return;

    document.querySelectorAll('.style-item-wrapper.settings-open').forEach(openWrapper => {
        openWrapper.classList.remove('settings-open');
    });

    // The panel used to be moved into the selected row (wrapper.appendChild)
    // and laid out inline there. It now stays put in its static index.html
    // slot and floats top-right via CSS (position: fixed, see
    // inline_item_settings.css) - only wrapper's own highlight class moves.
    wrapper.classList.add('settings-open');
    panel.classList.remove('hidden');
    currentInlineContextData = contextualData;
    scheduleCreatorViewControlsSync();

    const itemInfo = items.find(entry => String(entry.id) === category);
    const itemName = itemInfo?.name || category;
    const variationAmount = Math.max(1, Number(contextualData.variationAmount) || 1);
    const variationValue = Math.max(1, Math.min(variationAmount, Number(contextualData.variationValue) || 1));
    const isClothingContext = currentOutfitMode === 'clothing';

    const tintNames = {
        1: JrsI18n.t("character_primary_color", "Primary Color"),
        2: JrsI18n.t("character_secondary_color", "Secondary Color"),
        3: JrsI18n.t("character_detail_color", "Detail Color")
    };

    let content = `
        <div class="inline-settings-title unselectable">
            <span>${itemName}</span>
            <span>${JrsI18n.t("character_item_settings", "Item Settings")}</span>
        </div>
    `;
    const settingsBlocks = [];

    if (variationAmount > 1) {
        settingsBlocks.push(buildCircularMeterMarkup({
            id: 'inline_variation_range',
            title: JrsI18n.t("character_style", "Style"),
            value: variationValue,
            min: 1,
            max: variationAmount,
            leftId: 'inline_variation_left',
            rightId: 'inline_variation_right',
            meterColor: '#b83a3a',
            accentClass: 'meter-accent-style',
            valueLabel: `${variationValue} / ${variationAmount}`,
            meterText: variationValue
        }));
    }

    const hasNativeColor = contextualData.nativeColor === true
        && Array.isArray(contextualData.actualColorOptions)
        && contextualData.actualColorOptions.length > 1;
    if (hasNativeColor) {
        settingsBlocks.push(buildNativeColorChipMarkup(
            'inline_native_color',
            JrsI18n.t("character_available_colors", "Available Colors"),
            contextualData.actualColorOptions
        ));
    }

    if (!isClothingContext && contextualData.advanced === true && Array.isArray(contextualData.advancedValues)) {
        contextualData.advancedValues.forEach(advanced => {
            const id = Number(advanced.valueId) || 0;
            const label = advanced.valueName === 'Palette' ? JrsI18n.t("character_color_palette", "Color Palette") : creatorAdvancedValueName(advanced.valueName);
            const paletteCount = Math.floor(Number(advanced.maxValue) || 0) - Math.floor(Number(advanced.minValue) || 0) + 1;

            if (advanced.valueName === 'Palette' && paletteCount > 0 && paletteCount <= 30) {
                // Matches jrs_barber's own layout: the colour picker sits
                // first (top-left of the settings grid), ahead of Style/
                // Opacity/Tone, not wherever it happened to fall in the
                // advancedValues array order.
                settingsBlocks.unshift(buildPaletteChipMarkup({
                    id: `inline_advanced_range_${id}`,
                    title: label,
                    value: advanced.valueValue,
                    min: advanced.minValue,
                    max: advanced.maxValue
                }));
            } else {
                settingsBlocks.push(buildCircularMeterMarkup({
                    id: `inline_advanced_range_${id}`,
                    title: label,
                    value: advanced.valueValue,
                    min: advanced.minValue,
                    max: advanced.maxValue,
                    leftId: `inline_advanced_left_${id}`,
                    rightId: `inline_advanced_right_${id}`,
                    meterColor: advanced.valueName === 'Palette' ? '#d2b277' : '#8aa4b8',
                    accentClass: advanced.valueName === 'Palette' ? 'meter-accent-palette' : 'meter-accent-secondary'
                }));
            }
        });
    }

    if (!isClothingContext && Array.isArray(contextualData.tints) && contextualData.tints.length > 0) {
        const toneTheme = currentOutfitMode === 'barber' ? getBarberToneTheme(category) : null;
        contextualData.tints.forEach((tint, index) => {
            const tintId = Number(tint.tintId) || 1;
            const tintValue = Math.max(0, Math.min(255, Number(tint.value) || 0));

            if (toneTheme) {
                const suffix = index === 0 ? '' : (index === 1 ? ' · ' + JrsI18n.t("character_tone_secondary", "Secondary") : ' · ' + JrsI18n.t("character_tone_detail", "Detail"));
                settingsBlocks.push(buildToneSliderMarkup({
                    id: `inline_tint_range_${tintId}`,
                    title: `${toneTheme.name}${suffix}`,
                    value: tintValue,
                    min: 0,
                    max: 255,
                    theme: toneTheme.className,
                    leftId: `inline_tint_left_${tintId}`,
                    rightId: `inline_tint_right_${tintId}`
                }));
            } else {
                settingsBlocks.push(buildCircularMeterMarkup({
                    id: `inline_tint_range_${tintId}`,
                    title: `${tintNames[tintId] || `${JrsI18n.t("character_color", "Color")} ${tintId}`}`,
                    value: tintValue,
                    min: 0,
                    max: 255,
                    leftId: `inline_tint_left_${tintId}`,
                    rightId: `inline_tint_right_${tintId}`,
                    meterColor: tintPreviewColour(tintValue, tintId),
                    accentClass: `meter-accent-tint-${tintId}`,
                    valueLabel: tintValue,
                    meterText: tintValue
                }));
            }
        });
    }

    if (isClothingContext && settingsBlocks.length === 0) {
        clearInlineItemSettings();
        return;
    }

    content += `<div class="inline-settings-grid">${settingsBlocks.join('')}</div>`;
    content += '<button type="button" class="inline-reset-item" id="inline_reset_item">' + JrsI18n.t("character_reset_item", "Reset Item") + '</button>';
    panel.innerHTML = content;

    const variationRange = document.getElementById('inline_variation_range');
    const sendVariation = value => {
        const numeric = Math.max(1, Math.min(variationAmount, Number(value) || 1));
        if (variationRange) variationRange.value = String(numeric);
        updateCircularMeter('inline_variation_range', numeric, 1, variationAmount, {
            valueLabel: `${numeric} / ${variationAmount}`,
            meterText: numeric,
            color: '#b83a3a'
        });
        postInlineValue('varValue', { item: numeric, category });
    };

    if (hasNativeColor) {
        const nativeColorGrid = document.getElementById('inline_native_color_grid');
        nativeColorGrid?.addEventListener('click', event => {
            const chip = event.target.closest('.jrs-actual-color-chip');
            if (!chip) return;
            event.preventDefault();
            event.stopPropagation();
            const value = Number(chip.dataset.value);
            if (!Number.isFinite(value)) return;
            nativeColorGrid.querySelectorAll('.jrs-actual-color-chip.selected').forEach(el => el.classList.remove('selected'));
            chip.classList.add('selected');
            sendVariation(value);
        });
    }

    if (variationRange) {
        variationRange.addEventListener('input', event => {
            event.stopPropagation();
            const numeric = Math.max(1, Math.min(variationAmount, Number(variationRange.value) || 1));
            updateCircularMeter('inline_variation_range', numeric, 1, variationAmount, {
                valueLabel: `${numeric} / ${variationAmount}`,
                meterText: numeric,
                color: '#b83a3a'
            });
        });
        variationRange.addEventListener('change', event => { event.stopPropagation(); sendVariation(variationRange.value); });
        variationRange.addEventListener('pointerdown', event => event.stopPropagation());
        variationRange.addEventListener('click', event => event.stopPropagation());
        document.getElementById('inline_variation_left')?.addEventListener('click', event => {
            event.preventDefault();
            sendVariation(Number(variationRange.value) - 1);
        });
        document.getElementById('inline_variation_right')?.addEventListener('click', event => {
            event.preventDefault();
            sendVariation(Number(variationRange.value) + 1);
        });
        bindCircularMeterDrag('inline_variation_range', 1, variationAmount, value => sendVariation(value));
    }

    if (!isClothingContext && contextualData.advanced === true && Array.isArray(contextualData.advancedValues)) {
        contextualData.advancedValues.forEach(advanced => {
            const id = Number(advanced.valueId) || 0;
            const min = Number(advanced.minValue) || 0;
            const max = Number(advanced.maxValue) || 100;

            const chipGrid = document.getElementById(`inline_advanced_range_${id}_grid`);
            if (chipGrid) {
                chipGrid.addEventListener('click', event => {
                    const chip = event.target.closest('.jrs-actual-color-chip');
                    if (!chip) return;
                    event.preventDefault();
                    event.stopPropagation();
                    const numeric = Math.max(min, Math.min(max, Number(chip.dataset.value)));
                    chipGrid.querySelectorAll('.jrs-actual-color-chip.selected').forEach(el => el.classList.remove('selected'));
                    chip.classList.add('selected');
                    postInlineValue('varValue', {
                        advancedValue: advanced.valueName,
                        itemValue: numeric,
                        category
                    });
                });
                return;
            }

            const range = document.getElementById(`inline_advanced_range_${id}`);
            if (!range) return;
            const sendAdvanced = value => {
                const numeric = Math.max(min, Math.min(max, Number(value) || min));
                range.value = String(numeric);
                updateCircularMeter(`inline_advanced_range_${id}`, numeric, min, max, {
                    valueLabel: numeric,
                    meterText: numeric,
                    color: advanced.valueName === 'Palette' ? '#d2b277' : '#8aa4b8'
                });
                postInlineValue('varValue', {
                    advancedValue: advanced.valueName,
                    itemValue: numeric,
                    category
                });
            };
            range.addEventListener('input', event => { event.stopPropagation(); sendAdvanced(range.value); });
            range.addEventListener('pointerdown', event => event.stopPropagation());
            range.addEventListener('click', event => event.stopPropagation());
            document.getElementById(`inline_advanced_left_${id}`)?.addEventListener('click', event => {
                event.preventDefault();
                sendAdvanced(Number(range.value) - 1);
            });
            document.getElementById(`inline_advanced_right_${id}`)?.addEventListener('click', event => {
                event.preventDefault();
                sendAdvanced(Number(range.value) + 1);
            });
            bindCircularMeterDrag(`inline_advanced_range_${id}`, min, max, value => sendAdvanced(value));
        });
    }

    if (!isClothingContext && Array.isArray(contextualData.tints)) {
        contextualData.tints.forEach(tint => {
            const tintId = Number(tint.tintId) || 1;
            const range = document.getElementById(`inline_tint_range_${tintId}`);
            if (!range) return;
            const sendTint = value => {
                const numeric = Math.max(0, Math.min(255, Number(value) || 0));
                range.value = String(numeric);
                updateInlineTintDisplay(tintId, numeric);
                postInlineValue('tintValue', { tintId, value: numeric, category });
            };
            range.addEventListener('input', event => { event.stopPropagation(); sendTint(range.value); });
            range.addEventListener('pointerdown', event => event.stopPropagation());
            range.addEventListener('click', event => event.stopPropagation());
            document.getElementById(`inline_tint_left_${tintId}`)?.addEventListener('click', event => {
                event.preventDefault();
                sendTint(Number(range.value) - 1);
            });
            document.getElementById(`inline_tint_right_${tintId}`)?.addEventListener('click', event => {
                event.preventDefault();
                sendTint(Number(range.value) + 1);
            });
            // Circular clothing colour meters can be dragged directly with the mouse.
            if (!range.classList.contains('tone-range')) {
                bindCircularMeterDrag(`inline_tint_range_${tintId}`, 0, 255, value => sendTint(value));
            }
        });
    }

    document.getElementById('inline_reset_item')?.addEventListener('click', () => {
        $.post(`https://${GetParentResourceName()}/resetOutfitItem`, JSON.stringify({
            category,
            mode: currentOutfitMode
        }), response => {
            let result = response;
            if (typeof result === 'string') {
                try { result = JSON.parse(result); } catch (_) { result = {}; }
            }
            const itemRange = document.getElementById(`rangeGlobal_${category}`);
            if (itemRange && result && result.value !== undefined) {
                itemRange.value = String(result.value);
                const valueLabel = document.getElementById(`sliderValue_${category}`);
                if (valueLabel) valueLabel.textContent = formatBodyOrStyleValue(category, result.value);
                updateRangeBackground(`rangeGlobal_${category}`);
            }
        });
    });

    const stylePropertiesContainer = document.getElementById('StyleProperties');
    if (stylePropertiesContainer) {
        // offsetTop is relative to the nearest positioned ancestor, which is not
        // necessarily the scroll container. Using it directly scrolled the header
        // of the expanded item out of view every time an item was opened.
        const containerRect = stylePropertiesContainer.getBoundingClientRect();
        const panelRect = panel.getBoundingClientRect();
        const panelTop = (panelRect.top - containerRect.top) + stylePropertiesContainer.scrollTop;
        const panelHeight = panelRect.height || panel.offsetHeight;
        const viewTop = stylePropertiesContainer.scrollTop;
        const viewHeight = stylePropertiesContainer.clientHeight;
        const viewBottom = viewTop + viewHeight;
        const panelBottom = panelTop + panelHeight;
        const maxScroll = Math.max(0, stylePropertiesContainer.scrollHeight - viewHeight);

        let target = viewTop;
        if (panelHeight >= viewHeight || panelTop < viewTop) {
            // Always keep the header of the opened item visible.
            target = panelTop - 8;
        } else if (panelBottom > viewBottom) {
            target = panelBottom - viewHeight + 8;
        }

        stylePropertiesContainer.scrollTop = Math.max(0, Math.min(maxScroll, target));
    }
}

////////////////////////// CONTEXTUAL MENU (FOR OUTFIT MODIFICATION / CREATION - TINT, VARIATIONS...) //////////////////////////

// Show Contextual Menu
function showContextualMenu(contextualType) {
    if (isInlineOutfitContext()) return;
    const variationMenu = document.getElementById("VariationSettings");
    const tintMenu = document.getElementById("TintSettings");

    if (contextualType === "variation") {
        // Only show variation menu if it's currently hidden
        if (variationMenu.classList.contains('hidden')) {
            variationMenu.classList.remove('hidden');
            tintMenu.classList.add('hidden');
        }
        scheduleCreatorViewControlsSync();
    } else if (contextualType === "colour") {
        // Only show tint menu if it's currently hidden
        if (tintMenu.classList.contains('hidden')) {
            tintMenu.classList.remove('hidden');
            variationMenu.classList.add('hidden');
        }
        scheduleCreatorViewControlsSync();
    }
}

// Hide Contextual Menu
function hideContextualMenu() {
    clearInlineItemSettings();
    const variationSettings = document.getElementById('VariationSettings');
    const tintSettings = document.getElementById('TintSettings');

    if (!variationSettings.classList.contains('hidden')) {
        variationSettings.classList.add('hidden');
    }

    if (!tintSettings.classList.contains('hidden')) {
        tintSettings.classList.add('hidden');
    }
    scheduleCreatorViewControlsSync();
}


// Show Eye Tint Menu
function showEyesContextualMenu() {
    const tintMenu = document.getElementById("TintSettings");
    tintMenu.classList.remove('hidden');
    createEyesColourSelector();
}

// Show Eye Tint Menu
function hideEyesContextualMenu() {
    const tintMenu = document.getElementById("TintSettings");
    tintMenu.classList.add('hidden');
}




//Actual Selected Values
currentSelectedCategorie = 0;
currentSelectedItem = 0;

////////////////////////// EDIT APPARENCE MENU //////////////////////////

function setActionButtonContent(button, label, icon, iconOnRight = false) {
    if (!button) return;
    const safeLabel = label || '';
    const safeIcon = icon || '';
    button.innerHTML = iconOnRight
        ? `<span class="action-button-label">${safeLabel}</span><span class="action-button-icon">${safeIcon}</span>`
        : `<span class="action-button-icon">${safeIcon}</span><span class="action-button-label">${safeLabel}</span>`;
}

function showApparenceMenu() {
    const apparenceMenu = document.getElementById('GlobalCharacterMenu');
    apparenceMenu.classList.remove('hidden');
    createEditApparenceMenu();
    scheduleCreatorViewControlsSync();
    
    // Show/hide Save button based on Second Chance mode
    const saveSecondChanceBtn = document.getElementById('SaveSecondChance');
    const continueCreatorBtn = document.getElementById('ContinueCreator');
    const backBtn = document.getElementById('CancelApparenceEdition');
    setActionButtonContent(document.getElementById('ResetApparenceEdition'), t('ui.reset', 'Reset'), '↻');

    creatorDebugLog("[SecondChance] showApparenceMenu called, isSecondChanceMode:", isSecondChanceMode);
    creatorDebugLog("[SecondChance] saveSecondChanceBtn element:", saveSecondChanceBtn);
    
    if (saveSecondChanceBtn) {
        if (isSecondChanceMode) {
            creatorDebugLog("[SecondChance] Showing Save button");
            saveSecondChanceBtn.classList.remove('hidden');
            saveSecondChanceBtn.style.display = 'block';
            if (continueCreatorBtn) continueCreatorBtn.classList.add('hidden');
            setActionButtonContent(backBtn, t('ui.back', 'Back'), '↩');
            setActionButtonContent(continueCreatorBtn, t('character_next', 'Next'), '➜', true);
        } else {
            saveSecondChanceBtn.classList.add('hidden');
            if (continueCreatorBtn) continueCreatorBtn.classList.remove('hidden');
            setActionButtonContent(backBtn, t('ui.back', 'Back'), '↩');
            setActionButtonContent(continueCreatorBtn, t('character_next', 'Next'), '➜', true);
        }
    } else {
        creatorDebugLog("[SecondChance] ERROR: SaveSecondChance button not found!");
    }
}

function hideApparenceMenu() {
    const apparenceMenu = document.getElementById('GlobalCharacterMenu');
    apparenceMenu.classList.add('hidden');
    scheduleCreatorViewControlsSync();
}

////////////////////////// SPAWN MENU //////////////////////////

function showSpawnMenu() {
    const spawnMenu = document.getElementById('SpawnMenu');
    actualLocationIndex = 0;
    spawnMenu.classList.remove('hidden');
    loadSpawnLocations(true);
    scheduleCreatorViewControlsSync();
}

function hideSpawnMenu() {
    const spawnMenu = document.getElementById('SpawnMenu');
    spawnMenu.classList.add('hidden');
    scheduleCreatorViewControlsSync();
}


////////////////////////// SELECTED CHAR //////////////////////////

let lastSelectedCharData = null;

function showSelectedCharMenu(charData) {
    lastSelectedCharData = charData;
    const spawnMenu = document.getElementById('ChooseCharacterMenu');
    spawnMenu.classList.remove('hidden');
    loadSelectedCharData(charData);
    if (typeof updateTranslations === 'function') {
        updateTranslations(spawnMenu);
    }
    scheduleCreatorViewControlsSync();
}

function hideSelectedCharMenu() {
    const spawnMenu = document.getElementById('ChooseCharacterMenu');
    spawnMenu.classList.add('hidden');
    scheduleCreatorViewControlsSync();
}



///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                     LOAD CATEGORIES                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////


function selectOutfitCategory(categoryId) {
    changeCategory(categoryId);
    currentSelectedCategorie = categoryId;
    requestAutomaticOutfitCamera(categoryId, categoryId);

    // Hide Contextual Datas until item clicked
    const varSettings = document.getElementById('VariationSettings');
    const tintSettings = document.getElementById('TintSettings');
    if (varSettings) varSettings.classList.add('hidden');
    if (tintSettings) tintSettings.classList.add('hidden');

    const cate = document.querySelectorAll('.categoryElem');
    cate.forEach(catego => {
        catego.classList.remove('selected');
    });

    const activeCat = document.getElementById('category_btn_' + categoryId);
    if (activeCat) {
        activeCat.classList.add('selected');
    }
}

// Load Categories
function loadCategories() {
    const categoriesContainer = document.getElementById('Categories');
    categoriesContainer.innerHTML = '';

    categories.forEach((category, index) => {
        const categoryElem = document.createElement('a');
        categoryElem.classList.add('categoryElem');
        categoryElem.id = 'category_btn_' + category.id;

        categoryElem.innerHTML = `
                <img src="${category.image}" alt="${category.name}">
        `;

        categoryElem.addEventListener('click', () => {
            selectOutfitCategory(category.id);
        });
        categoriesContainer.appendChild(categoryElem);
    });

    if (categories.length > 0) {
        selectOutfitCategory(categories[0].id);
    }
}





///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                       LOAD ITEMS                                                  //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////

function changeCategory(categoryId) {

    items.forEach(item => {

        const itemElem = document.getElementById('item_' + item.id);
        const wrapper = document.getElementById('style_wrapper_' + item.id);
        const target = wrapper || itemElem;
        if (!target) return;

        if (item.category === categoryId) {
            target.classList.remove('hidden');
            if (itemElem) itemElem.classList.remove('hidden');
        }
        else {
            target.classList.add('hidden');
        }

    });

};


// MP | NPC switch on creator clothing sliders (4.2.45), same behaviour as the
// jrs_clothing shop: each mode has its own list; switching takes the garment
// off and the slider starts from 0 in the new list.
window._creatorClothingModes = window._creatorClothingModes || {};
function creatorClothingModeOf(item) {
    return (item && item.clothingMode) ? (window._creatorClothingModes[item.id] || item.clothingMode) : undefined;
}

function bindCreatorClothingModeToggle(item) {
    window._creatorClothingModes[item.id] = item.clothingMode;
    const setMode = (mode, event) => {
        event.preventDefault();
        event.stopPropagation();
        const count = mode === 'npc' ? item.npcCount : item.mpCount;
        if (!(count > 0) || creatorClothingModeOf(item) === mode) return;
        window._creatorClothingModes[item.id] = mode;
        document.getElementById('clothingMpMode_' + item.id).classList.toggle('active', mode === 'mp');
        document.getElementById('clothingNpcMode_' + item.id).classList.toggle('active', mode === 'npc');
        const slider = document.getElementById('rangeGlobal_' + item.id);
        slider.max = count;
        slider.value = 0;
        item.totalAmount = count;
        document.getElementById('sliderValue_' + item.id).innerText = formatBodyOrStyleValue(item.id, 0);
        updateRangeBackground('rangeGlobal_' + item.id);
        if (currentSelectedItem !== item.id) {
            clearInlineItemSettings();
            currentSelectedItem = item.id;
            setCreatorStyleSelection(item.id);
            scheduleCreatorViewControlsSync();
        }
        creatorPostControl('itemValue', {
            category: item.id, menu: item.category, item: 0, clothingMode: mode
        });
    };
    document.getElementById('clothingMpMode_' + item.id).addEventListener('click', e => setMode('mp', e));
    document.getElementById('clothingNpcMode_' + item.id).addEventListener('click', e => setMode('npc', e));
}

// Load Items
function loadItems() {
    const itemsContainer = document.getElementById('StyleProperties');
    itemsContainer.innerHTML = '';

    items.forEach(item => {

        if (item.selectorType === "slider") {
            const itemTitle = (window.JrsI18n && typeof window.JrsI18n.t === 'function')
                ? JrsI18n.t('creator_cat_' + item.id, item.name)
                : item.name;

            const itemElem = document.createElement('div');
            itemElem.className = 'style-item-wrapper';
            itemElem.id = `style_wrapper_${item.id}`;
            itemElem.innerHTML = `
                    <div class="styleElem unselectable hidden" id="item_${item.id}">
                        <p class="elemTitle">${itemTitle}</p>
                        <div class="sliderDiv">
                            <p class="sliderValue unselectable" id="sliderValue_${item.id}">${formatBodyOrStyleValue(item.id, item.value)}</p>
                            <div class="sliderElem">
                                ${item.clothingMode ? `<div class="clothingModeToggle">
                                    <a class="clothingModeBtn ${item.clothingMode === 'mp' ? 'active' : ''} ${item.mpCount > 0 ? '' : 'disabled'}" id="clothingMpMode_${item.id}" data-i18n="creator_clothing_mode_mp" data-i18n-title="creator_clothing_mode_mp_hint" title="${JrsI18n.t('creator_clothing_mode_mp_hint', 'Player clothing (MP)')}">${JrsI18n.t('creator_clothing_mode_mp', 'MP')}</a>
                                    <a class="clothingModeBtn ${item.clothingMode === 'npc' ? 'active' : ''} ${item.npcCount > 0 ? '' : 'disabled'}" id="clothingNpcMode_${item.id}" data-i18n="creator_clothing_mode_npc" data-i18n-title="creator_clothing_mode_npc_hint" title="${JrsI18n.t('creator_clothing_mode_npc_hint', 'NPC clothing')}">${JrsI18n.t('creator_clothing_mode_npc', 'NPC')}</a>
                                </div>` : ''}
                                <a id="left_arrow_${item.id}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_left", "Arrow left")}"></a>
                                <input type="range" min="${item.min !== undefined ? item.min : 0}" max="${item.totalAmount}" value="${item.value}" class="slider" id="rangeGlobal_${item.id}">
                                <a id="right_arrow_${item.id}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_right", "Arrow right")}" style="transform: rotate(180deg);"></a>
                            </div>
                        </div>
                    </div>
                `;

            itemsContainer.appendChild(itemElem);

            //Update Range Background
            updateRangeBackground('rangeGlobal_' + item.id);

            if (item.clothingMode) bindCreatorClothingModeToggle(item);

            itemElem.addEventListener('click', () => {

                if (currentSelectedItem !== item.id) {
                    clearInlineItemSettings();

                    currentSelectedItem = item.id;
                    setCreatorStyleSelection(item.id);
                    scheduleCreatorViewControlsSync();

                    if (item.contextual === "variation") {
                        document.getElementById("VariationSettings").classList.remove('hidden');
                        document.getElementById("TintSettings").classList.add('hidden');
                    } else if (item.contextual === "tint") {
                        document.getElementById("TintSettings").classList.remove('hidden');
                        document.getElementById("VariationSettings").classList.add('hidden');
                    }

                    creatorPostControl('itemValue', {
                        category: item.id, menu: item.category
                    });

                }

            });

            document.getElementById('right_arrow_' + item.id).addEventListener('click', (event) => {
                event.preventDefault();
                event.stopPropagation();
                if (currentSelectedItem !== item.id) {
                    clearInlineItemSettings();
                    currentSelectedItem = item.id;
                    setCreatorStyleSelection(item.id);
                    scheduleCreatorViewControlsSync();
                }
                const slider = document.getElementById('rangeGlobal_' + item.id);
                if (slider.value !== slider.max) {
                    slider.value = parseInt(slider.value) + 1;
                    document.getElementById('sliderValue_' + item.id).innerText = formatBodyOrStyleValue(item.id, slider.value);

                    updateRangeBackground('rangeGlobal_' + item.id);
                }

                creatorPostControl('itemValue', {
                    category: item.id, menu: item.category,
                    item: slider.value,
                    clothingMode: creatorClothingModeOf(item)
                });


            });

            document.getElementById('left_arrow_' + item.id).addEventListener('click', (event) => {
                event.preventDefault();
                event.stopPropagation();
                if (currentSelectedItem !== item.id) {
                    clearInlineItemSettings();
                    currentSelectedItem = item.id;
                    setCreatorStyleSelection(item.id);
                    scheduleCreatorViewControlsSync();
                }
                const slider = document.getElementById('rangeGlobal_' + item.id);
                if (slider.value !== slider.min) {
                    slider.value = parseInt(slider.value) - 1;
                    document.getElementById('sliderValue_' + item.id).innerText = formatBodyOrStyleValue(item.id, slider.value);

                    updateRangeBackground('rangeGlobal_' + item.id);

                }

                creatorPostControl('itemValue', {
                    category: item.id, menu: item.category,
                    item: slider.value,
                    clothingMode: creatorClothingModeOf(item)
                });


            });

            // document.getElementById('rangeGlobal_' + item.id).addEventListener('input', () => {
            //     const slider = document.getElementById('rangeGlobal_' + item.id);
            //     document.getElementById('sliderValue_' + item.id).innerText = `${JrsI18n.t("character_style", "Style")} ${slider.value}`;

            //     $.post(`https://${GetParentResourceName()}/itemValue`, JSON.stringify({
            //         category: item.id, menu: item.category,,
            //         item: slider.value
            //     }));
            // });

            const outfitRange = document.getElementById('rangeGlobal_' + item.id);
            outfitRange.addEventListener('pointerdown', event => {
                event.stopPropagation();
                if (currentSelectedItem !== item.id) {
                clearInlineItemSettings();
                currentSelectedItem = item.id;
                setCreatorStyleSelection(item.id);
            }
            });
            outfitRange.addEventListener('click', event => event.stopPropagation());

            document.getElementById('rangeGlobal_' + item.id).addEventListener('input', () => {
                const slider = document.getElementById('rangeGlobal_' + item.id);
                document.getElementById('sliderValue_' + item.id).innerText = formatBodyOrStyleValue(item.id, slider.value);

                updateRangeBackground('rangeGlobal_' + item.id);
                creatorPostControl('itemValue', {
                    category: item.id, menu: item.category,
                    item: slider.value,
                    clothingMode: creatorClothingModeOf(item)
                });
            });

            document.getElementById('rangeGlobal_' + item.id).addEventListener('change', () => {
                const slider = document.getElementById('rangeGlobal_' + item.id);
                creatorPostControl('itemValue', {
                    category: item.id, menu: item.category,
                    item: slider.value,
                    clothingMode: creatorClothingModeOf(item)
                });
            });

        }
        else if (item.selectorType === "selector") {

            const itemElem = document.createElement('div');
            itemElem.className = 'style-item-wrapper';
            itemElem.id = `style_wrapper_${item.id}`;
            itemElem.innerHTML = `
                    <div class="styleElem typeTwo unselectable" id="item_${item.id}">
                        <p class="elemTitle">${item.name}</p>
                        <div class="sliderDiv">
                            <div class="sliderElemTypeTwo">
                                <a id="left_arrow_${item.id}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_left", "Arrow left")}"></a>
                                <p class="sliderValueTypeTwo unselectable" id="sliderValue_${item.id}">${JrsI18n.t("character_style", "Style")} ${item.value}</p>
                                <input type="range" min="0" max="${item.totalAmount}" value="${item.value}" class="hidden" id="rangeGlobal_${item.id}">
                                <a id="right_arrow_${item.id}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_right", "Arrow right")}" style="transform: rotate(180deg);"></a>
                            </div>
                        </div>

                    </div>
                `;

            itemElem.addEventListener('click', () => {

                if (currentSelectedItem !== item.id) {
                    clearInlineItemSettings();
                    currentSelectedItem = item.id;
                    setCreatorStyleSelection(item.id);

                    if (!isInlineOutfitContext()) {
                        if (item.contextual === "variation") {
                            document.getElementById("VariationSettings").classList.remove('hidden');
                            document.getElementById("TintSettings").classList.add('hidden');
                        } else if (item.contextual === "tint") {
                            document.getElementById("TintSettings").classList.remove('hidden');
                            document.getElementById("VariationSettings").classList.add('hidden');
                        }
                    }

                    creatorPostControl('itemValue', {
                        category: item.id, menu: item.category
                    });
                }

            });
            itemsContainer.appendChild(itemElem);

            document.getElementById(`right_arrow_${item.id}`).addEventListener('click', (event) => {
                event.preventDefault();
                event.stopPropagation();
                if (currentSelectedItem !== item.id) {
                    clearInlineItemSettings();
                    currentSelectedItem = item.id;
                    setCreatorStyleSelection(item.id);
                    scheduleCreatorViewControlsSync();
                }
                const slider = document.getElementById(`rangeGlobal_${item.id}`);
                if (slider.value < slider.max) {
                    slider.value = parseInt(slider.value) + 1;
                    document.getElementById('sliderValue_' + item.id).innerText = `${JrsI18n.t("character_style", "Style")} ${slider.value}`;
                }

                creatorPostControl('itemValue', {
                    category: item.id, menu: item.category,
                    item: slider.value
                });

            });

            document.getElementById(`left_arrow_${item.id}`).addEventListener('click', (event) => {
                event.preventDefault();
                event.stopPropagation();
                if (currentSelectedItem !== item.id) {
                    clearInlineItemSettings();
                    currentSelectedItem = item.id;
                    setCreatorStyleSelection(item.id);
                    scheduleCreatorViewControlsSync();
                }
                const slider = document.getElementById(`rangeGlobal_${item.id}`);
                if (slider.value > slider.min) {
                    slider.value = parseInt(slider.value) - 1;
                    document.getElementById('sliderValue_' + item.id).innerText = `${JrsI18n.t("character_style", "Style")} ${slider.value}`;
                }

                creatorPostControl('itemValue', {
                    category: item.id, menu: item.category,
                    item: slider.value
                });
            });


        }
    });
}






///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                     LOAD CONTEXTUAL                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////

// Load Contextual Datas
function loadContextualDatas(contextualDatas) {
    // Check if contextualDatas is an array
    if (!Array.isArray(contextualDatas)) {
        console.error('contextualDatas must be an array');
        return;
    }

    if (isInlineOutfitContext()) {
        const contextualData = contextualDatas[0];
        if (contextualData) renderInlineOutfitContextualData(contextualData);
        return;
    }

    contextualDatas.forEach(contextualData => {
        if (contextualData.contextual === "variation") {
            // Check if there is only one variation
            if (contextualData.variationAmount === 1) {

                //Don't show the variation menu
                document.getElementById('VariationContextSettings').classList.add('hidden');
                document.getElementById('separator_var').classList.add('hidden');

            } else {
                document.getElementById('VariationContextSettings').classList.remove('hidden');
                document.getElementById('separator_var').classList.remove('hidden');
                //Show the variation menu
                document.getElementById('varSlider').innerHTML = `
                
                <p class="unselectable">${JrsI18n.t("character_var", "Var -")} <span id="actualVar">${contextualData.variationValue}</span></p>

                <div class="unselectable">

                    <a id="left_arrow_variation" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_left", "Arrow left")}"></a>
                    <input type="range" name="Variation" id="rangeVariation" min="1" max="${contextualData.variationAmount}" value="${contextualData.variationValue}" class="contRange">
                    <a id="right_arrow_variation" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_right", "Arrow right")}" style="transform: rotate(180deg);"></a>

                </div>
                `;

                updateRangeBackground('rangeVariation');

                document.getElementById('right_arrow_variation').addEventListener('click', () => {
                    const slider = document.getElementById('rangeVariation');
                    if (slider.value !== slider.max) {
                        slider.value = parseInt(slider.value) + 1;
                        document.getElementById('actualVar').innerText = `${slider.value}`;
                        updateRangeBackground('rangeVariation');
                    }

                    creatorPostControl(contextualData.contextualEndpoint || 'varValue', {
                        item: slider.value,
                        category: contextualData.category
                    });
                });

                document.getElementById('left_arrow_variation').addEventListener('click', () => {
                    const slider = document.getElementById('rangeVariation');
                    if (slider.value !== slider.min) {
                        slider.value = parseInt(slider.value) - 1;
                        document.getElementById('actualVar').innerText = `${slider.value}`;
                        updateRangeBackground('rangeVariation');
                    }

                    creatorPostControl('varValue', {
                        item: slider.value,
                        category: contextualData.category
                    });
                });

                document.getElementById('rangeVariation').addEventListener('input', () => {
                    const slider = document.getElementById('rangeVariation');
                    document.getElementById('actualVar').innerText = `${slider.value}`;
                    updateRangeBackground('rangeVariation');

                    creatorPostControl('varValue', {
                        item: slider.value,
                        category: contextualData.category
                    });
                });
            };

            advancedContainer = document.getElementById('ContextSettingsAdvanced');
            advancedContainer.innerHTML = '';

            if (contextualData.advanced === true) {

                document.getElementById('ContextSettingsAdvanced').classList.remove('hidden');
                document.getElementById('separator_colour').classList.remove('hidden');

                contextualData.advancedValues.forEach(advanced => {


                    const tintElem = document.createElement('div');
                    tintElem.classList.add('ContextElem');

                    tintElem.innerHTML = `

                    <p class="unselectable">${creatorAdvancedValueName(advanced.valueName)} - <span id="actuelAdvandedVar_${advanced.valueId}">${advanced.valueValue}</span></p>
                    <div class="unselectable">

                    <a id="left_arrow_advanced_${advanced.valueId}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_left", "Arrow left")}"></a>
                    <input type="range" name="Advanced_${advanced.valueId}" class="contRange" id="rangeadvanced_${advanced.valueId}" min="${advanced.minValue}" max="${advanced.maxValue}" value="${advanced.valueValue}">
                    <a id="right_arrow_advanced_${advanced.valueId}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_right", "Arrow right")}" style="transform: rotate(180deg);"></a>

                    </div>`;

                    advancedContainer.appendChild(tintElem);
                    updateRangeBackground('rangeadvanced_' + advanced.valueId);

                    document.getElementById('right_arrow_advanced_' + advanced.valueId).addEventListener('click', () => {
                        const slider = document.getElementById('rangeadvanced_' + advanced.valueId);
                        if (slider.value !== slider.max) {
                            slider.value = parseInt(slider.value) + 1;
                            document.getElementById('actuelAdvandedVar_' + advanced.valueId).innerText = `${slider.value}`;
                            updateRangeBackground('rangeadvanced_' + advanced.valueId);
                        }

                        creatorPostControl('varValue', {
                            advancedValue: advanced.valueName,
                            itemValue: slider.value,
                            category: contextualData.category
                        });
                    });

                    document.getElementById('left_arrow_advanced_' + advanced.valueId).addEventListener('click', () => {
                        const slider = document.getElementById('rangeadvanced_' + advanced.valueId);
                        if (slider.value !== slider.min) {
                            slider.value = parseInt(slider.value) - 1;
                            document.getElementById('actuelAdvandedVar_' + advanced.valueId).innerText = `${slider.value}`;
                            updateRangeBackground('rangeadvanced_' + advanced.valueId);
                        }

                        creatorPostControl('varValue', {
                            advancedValue: advanced.valueName,
                            itemValue: slider.value,
                            category: contextualData.category
                        });
                    });

                    document.getElementById('rangeadvanced_' + advanced.valueId).addEventListener('input', () => {
                        const slider = document.getElementById('rangeadvanced_' + advanced.valueId);
                        document.getElementById('actuelAdvandedVar_' + advanced.valueId).innerText = `${slider.value}`;
                        updateRangeBackground('rangeadvanced_' + advanced.valueId);

                        creatorPostControl('varValue', {
                            advancedValue: advanced.valueName,
                            itemValue: slider.value,
                            category: contextualData.category
                        });
                    });

                });

            } else {
                document.getElementById('ContextSettingsAdvanced').classList.add('hidden');
                document.getElementById('separator_colour').classList.add('hidden');
            };

            tintContainer = document.querySelector('.TintList');
            tintContainer.innerHTML = '';

            (contextualData.tints || []).forEach(tint => {


                const tintElem = document.createElement('div');
                tintElem.classList.add('ContextElem');

                tintElem.innerHTML = `

                <p class="unselectable">T${tint.tintId} - <span id="actualTint${tint.tintId}">${tint.value}</span></p>
                <div class="unselectable">

                <a id="left_arrow_tint${tint.tintId}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_left", "Arrow left")}"></a>
                <input type="range" name="Tint${tint.tintId}" class="contRange" id="rangeTint${tint.tintId}" min="1" max="255" value="${tint.value}">
                <a id="right_arrow_tint${tint.tintId}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_right", "Arrow right")}" style="transform: rotate(180deg);"></a>

                </div>


                `;

                tintContainer.appendChild(tintElem);
                updateRangeBackground('rangeTint' + tint.tintId);

                document.getElementById('right_arrow_tint' + tint.tintId).addEventListener('click', () => {
                    const slider = document.getElementById('rangeTint' + tint.tintId);
                    if (slider.value !== slider.max) {
                        slider.value = parseInt(slider.value) + 1;
                        document.getElementById('actualTint' + tint.tintId).innerText = `${slider.value}`;
                        updateRangeBackground('rangeTint' + tint.tintId);
                    }

                    creatorPostControl('tintValue', {
                        tintId: tint.tintId,
                        value: slider.value,
                        category: contextualData.category
                    });
                });

                document.getElementById('left_arrow_tint' + tint.tintId).addEventListener('click', () => {
                    const slider = document.getElementById('rangeTint' + tint.tintId);
                    if (slider.value !== slider.min) {
                        slider.value = parseInt(slider.value) - 1;
                        document.getElementById('actualTint' + tint.tintId).innerText = `${slider.value}`;
                        updateRangeBackground('rangeTint' + tint.tintId);
                    }

                    creatorPostControl('tintValue', {
                        tintId: tint.tintId,
                        value: slider.value,
                        category: contextualData.category
                    });
                });

                document.getElementById('rangeTint' + tint.tintId).addEventListener('input', () => {
                    const slider = document.getElementById('rangeTint' + tint.tintId);
                    document.getElementById('actualTint' + tint.tintId).innerText = `${slider.value}`;
                    updateRangeBackground('rangeTint' + tint.tintId);

                    creatorPostControl('tintValue', {
                        tintId: tint.tintId,
                        value: slider.value,
                        category: contextualData.category
                    });
                });

            });


        } else if (contextualData.contextual === "colour") {


            document.getElementById('TintElement').innerHTML = `
                
                <div class="ElemSliderTint unselectable">

                    <div class="sliderElemTypeTwo">
                        <a id="Colour_left_arrow" class="arrow"><img src="./img/arrow.png"
                                alt="${JrsI18n.t("character_arrow_left", "Arrow left")}"></a>
                        <p class="sliderValueTypeTwo unselectable" id="ColourTintValue">${JrsI18n.t("character_colour", "Colour")} ${contextualData.tintValue}</p>
                        <input type="range" name="Colour" class="contRange hidden" id="ColourRange" min="1" max="${contextualData.tintAmount}" value="${contextualData.tintValue}">
                        <a id="Colour_right_arrow" class="arrow"><img src="./img/arrow.png"
                                alt="${JrsI18n.t("character_arrow_right", "Arrow right")}" style="transform: rotate(180deg);"></a>
                    </div>
                </div>`;

            document.getElementById('Colour_right_arrow').addEventListener('click', () => {
                const slider = document.getElementById('ColourRange');
                if (slider.value !== slider.max) {
                    slider.value = parseInt(slider.value) + 1;
                    document.getElementById('ColourTintValue').innerText = `${JrsI18n.t("character_colour", "Colour")} ${slider.value}`;
                    setCreatorColourSelection('Colour_', contextualData.colours, slider.value);

                    contextualData.colours.forEach(colour => {

                        document.getElementById('Colour_' + colour.id).classList.remove('selected');

                        if (creatorIdsEqual(colour.id, slider.value)) {
                            document.getElementById('Colour_' + colour.id).classList.add('selected');
                        };

                    });

                }

                creatorPostControl(contextualData.contextualEndpoint || 'varValue', {
                    item: slider.value,
                    category: contextualData.category
                });
            });

            document.getElementById('Colour_left_arrow').addEventListener('click', () => {
                const slider = document.getElementById('ColourRange');
                if (slider.value !== slider.min) {
                    slider.value = parseInt(slider.value) - 1;
                    document.getElementById('ColourTintValue').innerText = `${JrsI18n.t("character_colour", "Colour")} ${slider.value}`;
                    setCreatorColourSelection('Colour_', contextualData.colours, slider.value);

                    contextualData.colours.forEach(colour => {

                        document.getElementById('Colour_' + colour.id).classList.remove('selected');

                        if (creatorIdsEqual(colour.id, slider.value)) {
                            document.getElementById('Colour_' + colour.id).classList.add('selected');
                        };

                    });
                }

                creatorPostControl(contextualData.contextualEndpoint || 'varValue', {
                    item: slider.value,
                    category: contextualData.category
                });
            });

            //Empty Colour List
            colourList = document.getElementById('ColourList');
            colourList.innerHTML = '';

            //Create new Colour List
            contextualData.colours.forEach(colour => {

                const colourElem = document.createElement('a');

                colourElem.innerHTML = `<img src="${colour.image}" alt="colour ${colour.id}" id="Colour_${colour.id}" class="Colour">`;
                colourList.appendChild(colourElem);

                document.getElementById('Colour_' + colour.id).addEventListener('click', () => {
                    const slider = document.getElementById('ColourRange');
                    slider.value = parseInt(colour.id);

                    document.getElementById('ColourTintValue').innerText = `${JrsI18n.t("character_colour", "Colour")} ${slider.value}`;
                    setCreatorColourSelection('Colour_', contextualData.colours, slider.value);

                    contextualData.colours.forEach(colour => {

                        document.getElementById('Colour_' + colour.id).classList.remove('selected');

                        if (creatorIdsEqual(colour.id, slider.value)) {
                            document.getElementById('Colour_' + colour.id).classList.add('selected');
                        };

                    });


                    creatorPostControl('varValue', {
                        item: slider.value,
                        category: contextualData.category
                    });
                });

                if (creatorIdsEqual(colour.id, contextualData.tintValue)) {
                    document.getElementById('Colour_' + colour.id).classList.add('selected');
                };

            });


        }
    });
}


///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                GENERATE EDIT APPARENCRE MENU                                      //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////


function createEditApparenceMenu() {

    createGlobalApparenceMenu();
    createSkinColourSelector();
    createEyeColourGlobalSelector();
    createEyesColourSelector();

}



function createGlobalApparenceMenu() {

    const globalApparenceMenuList = document.getElementById('GlobalSettingsContainer');
    globalApparenceMenuList.innerHTML = '';

    if (globalApparenceMenu.length === 0) {
        document.getElementById('GlobalSettingsContainer').classList.add('hidden');
        document.getElementById('EditionTitleGlobSet').classList.add('hidden');
        document.getElementById('GlobalSetSeparator').classList.add('hidden');
    }
    else {
        document.getElementById('GlobalSettingsContainer').classList.remove('hidden');
        document.getElementById('EditionTitleGlobSet').classList.remove('hidden');
        document.getElementById('GlobalSetSeparator').classList.remove('hidden');
    }

    globalApparenceMenu.forEach(elem => {
        const globalApparenceMenuElem = document.createElement('div');
        globalApparenceMenuElem.classList.add('GlobalSettingsElem');

        globalApparenceMenuElem.innerHTML = `
                <div class="styleElem unselectable" id="item_app_${elem.id}">
                        <p class="elemTitle">${elem.name}</p>
                        <div class="sliderDiv">
                            <p class="sliderValue unselectable" id="sliderValue_app_${elem.id}">${formatBodyOrStyleValue(elem.id, elem.value)}</p>
                            <div class="sliderElem">
                                <a id="left_arrow_app_${elem.id}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_left", "Arrow left")}"></a>
                                <input type="range" min="${elem.min !== undefined ? elem.min : 1}" max="${elem.totalAmount}" value="${elem.value}" class="slider" id="rangeGlobalApp_${elem.id}">
                                <a id="right_arrow_app_${elem.id}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_right", "Arrow right")}" style="transform: rotate(180deg);"></a>
                            </div>
                        </div>
                    </div>`;

        globalApparenceMenuList.appendChild(globalApparenceMenuElem);

        updateRangeBackground('rangeGlobalApp_' + elem.id);


        document.getElementById('right_arrow_app_' + elem.id).addEventListener('click', () => {
            const slider = document.getElementById('rangeGlobalApp_' + elem.id);
            if (slider.value !== slider.max) {
                slider.value = parseInt(slider.value) + 1;
                document.getElementById('sliderValue_app_' + elem.id).innerText = formatBodyOrStyleValue(elem.id, slider.value);
                updateRangeBackground('rangeGlobalApp_' + elem.id);
            }

            creatorPostControl('globalApparence', {
                item: slider.value,
                elem: elem.id
            });
        });

        document.getElementById('left_arrow_app_' + elem.id).addEventListener('click', () => {
            const slider = document.getElementById('rangeGlobalApp_' + elem.id);

            if (slider.value !== slider.min) {
                slider.value = parseInt(slider.value) - 1;
                document.getElementById('sliderValue_app_' + elem.id).innerText = formatBodyOrStyleValue(elem.id, slider.value);
                updateRangeBackground('rangeGlobalApp_' + elem.id);
            }

            creatorPostControl('globalApparence', {
                item: slider.value,
                elem: elem.id
            });
        });

        document.getElementById('rangeGlobalApp_' + elem.id).addEventListener('input', () => {
            const slider = document.getElementById('rangeGlobalApp_' + elem.id);
            document.getElementById('sliderValue_app_' + elem.id).innerText = formatBodyOrStyleValue(elem.id, slider.value);
            updateRangeBackground('rangeGlobalApp_' + elem.id);

            creatorPostControl('globalApparence', {
                item: slider.value,
                elem: elem.id
            });
        });
    });

}

function createSkinColourSelector() {
    const globalSettingsContainer = document.getElementById('GlobalSettingsContainer');
    if (!globalSettingsContainer) return;

    // Skin tone now lives inside Global Settings as a normal slot, just like
    // Height / Body / Waist / Legs / Upper Body. Remove any stale copy first.
    document.getElementById('SkinToneGlobalRow')?.remove();

    const skinData = Array.isArray(skinApparenceMenu) ? skinApparenceMenu[0] : null;
    if (!skinData || Number(skinData.tintAmount) < 1) return;

    const skinSwatches = Array.isArray(skinData.colours) ? skinData.colours : [];
    const min = 1;
    const max = Math.max(1, Number(skinData.tintAmount) || 1);
    const initial = Math.max(min, Math.min(max, Number(skinData.tintValue) || min));

    // The skin row is part of Global Settings, so make sure the section is visible
    // even in the unlikely case there are no other global appearance options.
    globalSettingsContainer.classList.remove('hidden');
    document.getElementById('EditionTitleGlobSet')?.classList.remove('hidden');
    document.getElementById('GlobalSetSeparator')?.classList.remove('hidden');

    const skinRow = document.createElement('div');
    skinRow.id = 'SkinToneGlobalRow';
    skinRow.classList.add('GlobalSettingsElem');
    skinRow.innerHTML = `
        <div class="styleElem unselectable" id="item_app_skin_tone">
            <p class="elemTitle">${JrsI18n.t("character_skin_tone", "Skin Tone")}</p>
            <div class="sliderDiv">
                <p class="sliderValue unselectable" id="sliderValue_app_skin_tone">${JrsI18n.t("character_tone", "Tone")} ${initial} / ${max}</p>
                <div class="sliderElem">
                    <a id="left_arrow_app_skin_tone" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_left", "Arrow left")}"></a>
                    <input type="range" min="${min}" max="${max}" value="${initial}" class="slider" id="rangeGlobalApp_skin_tone">
                    <a id="right_arrow_app_skin_tone" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_right", "Arrow right")}" style="transform: rotate(180deg);"></a>
                </div>
            </div>
        </div>
        <div class="coloursDiv global-eye-colours" id="SkinToneGlobalList"></div>`;

    globalSettingsContainer.appendChild(skinRow);

    const slider = document.getElementById('rangeGlobalApp_skin_tone');
    const valueLabel = document.getElementById('sliderValue_app_skin_tone');
    const skinList = document.getElementById('SkinToneGlobalList');
    if (!slider) return;

    // The strip mirrors the Eye Colour row so both colour slots read the same
    // way. Hide it entirely when the payload carries no swatch images.
    if (skinList && skinSwatches.length < 1) skinList.remove();

    const markSkinSelected = value => {
        skinSwatches.forEach(colour => {
            const swatch = document.getElementById(`SkinToneGlobal_${colour.id}`);
            if (!swatch) return;
            swatch.classList.toggle('selected', creatorIdsEqual(colour.id, value));
        });
    };

    const previewSkinTone = value => {
        const numeric = Math.max(min, Math.min(max, Number(value) || min));
        slider.value = String(numeric);
        if (valueLabel) valueLabel.innerText = `${JrsI18n.t("character_tone", "Tone")} ${numeric} / ${max}`;
        updateRangeBackground('rangeGlobalApp_skin_tone');
        markSkinSelected(numeric);
        return numeric;
    };

    const applySkinTone = value => {
        const numeric = previewSkinTone(value);
        skinData.tintValue = numeric;
        creatorPostControl('SkinColourValue', { item: numeric });
    };

    if (skinList) {
        skinSwatches.forEach(colour => {
            const link = document.createElement('a');
            link.href = '#';
            link.innerHTML = `<img src="${colour.image}" alt="skin tone ${colour.id}" id="SkinToneGlobal_${colour.id}" class="Colour">`;
            skinList.appendChild(link);
            link.addEventListener('click', event => {
                event.preventDefault();
                applySkinTone(colour.id);
            });
        });
    }

    updateRangeBackground('rangeGlobalApp_skin_tone');
    markSkinSelected(initial);

    document.getElementById('right_arrow_app_skin_tone')?.addEventListener('click', event => {
        event.preventDefault();
        if (Number(slider.value) < max) applySkinTone(Number(slider.value) + 1);
    });

    document.getElementById('left_arrow_app_skin_tone')?.addEventListener('click', event => {
        event.preventDefault();
        if (Number(slider.value) > min) applySkinTone(Number(slider.value) - 1);
    });

    slider.addEventListener('input', () => previewSkinTone(slider.value));
    slider.addEventListener('change', () => applySkinTone(slider.value));
}


// Eye colour lives in Global Settings next to Skin Tone so it can be changed
// from the main Edit Appearance page instead of only from the face pin.
function createEyeColourGlobalSelector() {
    const globalSettingsContainer = document.getElementById('GlobalSettingsContainer');
    if (!globalSettingsContainer) return;

    document.getElementById('EyeColourGlobalRow')?.remove();

    const eyeData = Array.isArray(eyeGlobalColours) ? eyeGlobalColours[0] : null;
    const swatches = eyeData && Array.isArray(eyeData.colours) ? eyeData.colours : [];
    if (!eyeData || swatches.length < 1) return;

    const min = 1;
    const max = Math.max(1, Number(eyeData.tintAmount) || swatches.length);
    const initial = Math.max(min, Math.min(max, Number(eyeData.tintValue) || min));

    globalSettingsContainer.classList.remove('hidden');
    document.getElementById('EditionTitleGlobSet')?.classList.remove('hidden');
    document.getElementById('GlobalSetSeparator')?.classList.remove('hidden');

    const row = document.createElement('div');
    row.id = 'EyeColourGlobalRow';
    row.classList.add('GlobalSettingsElem');
    row.innerHTML = `
        <div class="styleElem unselectable" id="item_app_eye_colour">
            <p class="elemTitle">${JrsI18n.t("character_eye_colour", "Eye Colour")}</p>
            <div class="sliderDiv">
                <p class="sliderValue unselectable" id="sliderValue_app_eye_colour">${JrsI18n.t("character_colour", "Colour")} ${initial} / ${max}</p>
                <div class="sliderElem">
                    <a id="left_arrow_app_eye_colour" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_left", "Arrow left")}"></a>
                    <input type="range" min="${min}" max="${max}" value="${initial}" class="slider" id="rangeGlobalApp_eye_colour">
                    <a id="right_arrow_app_eye_colour" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_right", "Arrow right")}" style="transform: rotate(180deg);"></a>
                </div>
            </div>
        </div>
        <div class="coloursDiv global-eye-colours" id="EyeColourGlobalList"></div>`;

    globalSettingsContainer.appendChild(row);

    const slider = document.getElementById('rangeGlobalApp_eye_colour');
    const valueLabel = document.getElementById('sliderValue_app_eye_colour');
    const list = document.getElementById('EyeColourGlobalList');
    if (!slider || !list) return;

    const markSelected = value => {
        swatches.forEach(colour => {
            const swatch = document.getElementById(`EyeColourGlobal_${colour.id}`);
            if (!swatch) return;
            swatch.classList.toggle('selected', creatorIdsEqual(colour.id, value));
        });
    };

    const preview = value => {
        const numeric = Math.max(min, Math.min(max, Number(value) || min));
        slider.value = String(numeric);
        if (valueLabel) valueLabel.innerText = `${JrsI18n.t("character_colour", "Colour")} ${numeric} / ${max}`;
        updateRangeBackground('rangeGlobalApp_eye_colour');
        markSelected(numeric);
        return numeric;
    };

    const apply = value => {
        const numeric = preview(value);
        if (eyeData) eyeData.tintValue = numeric;
        // Global Settings already frames the character in the wide "edit
        // apparence" shot - skip the pin-editor's head zoom/pin-hide so this
        // row doesn't yank the camera and hide the surrounding panel.
        creatorPostControl('EyeColourValue', { item: numeric, skipCameraFocus: true });
    };

    swatches.forEach(colour => {
        const link = document.createElement('a');
        link.href = '#';
        link.innerHTML = `<img src="${colour.image}" alt="eye colour ${colour.id}" id="EyeColourGlobal_${colour.id}" class="Colour">`;
        list.appendChild(link);
        link.addEventListener('click', event => {
            event.preventDefault();
            apply(colour.id);
        });
    });

    document.getElementById('right_arrow_app_eye_colour')?.addEventListener('click', event => {
        event.preventDefault();
        if (Number(slider.value) < max) apply(Number(slider.value) + 1);
    });

    document.getElementById('left_arrow_app_eye_colour')?.addEventListener('click', event => {
        event.preventDefault();
        if (Number(slider.value) > min) apply(Number(slider.value) - 1);
    });

    slider.addEventListener('input', () => preview(slider.value));
    slider.addEventListener('change', () => apply(slider.value));

    preview(initial);
}


function createEyesColourSelector() {

    const eyesColourContainer = document.getElementById('ContextSettingsEyes');

    // Nothing to render until the contextual eyes panel has been opened from
    // the face pin. The Edit Appearance page uses createEyeColourGlobalSelector.
    if (!eyesColourContainer || !Array.isArray(eyeApparenceMenu) || eyeApparenceMenu.length === 0) {
        return;
    }

    // Clone and replace container to remove all old event listeners
    const newContainer = eyesColourContainer.cloneNode(false);
    eyesColourContainer.parentNode.replaceChild(newContainer, eyesColourContainer);

    eyeApparenceMenu.forEach(elem => {

        newContainer.innerHTML = `

                <div class="TintElem" id="TintElement">

                            <div class="ElemSliderTint">

                                <div class="sliderElemTypeTwo">
                                    <a id="Eye_left_arrow" class="arrow"><img src="./img/arrow.png"
                                            alt="${JrsI18n.t("character_arrow_left", "Arrow left")}"></a>
                                    <p class="sliderValueTypeTwo" id="ColourEyeValue">${JrsI18n.t("character_colour", "Colour")} ${elem.tintValue}</p>
                                    <input type="range" name="Colour" class="contRange hidden" id="EyeColourRange" min="1" max="${elem.tintAmount}" value="${elem.tintValue}">
                                    <a id="Eye_right_arrow" class="arrow"><img src="./img/arrow.png"
                                            alt="${JrsI18n.t("character_arrow_right", "Arrow right")}"style="transform: rotate(180deg);"></a>
                                </div>
                            </div>

                        </div>

                        <div class="TintElem">

                            <div class="coloursDiv" id="ColourListEye"></div>

                        </div>

                    </div>
            `;

        // Add event listeners only once after innerHTML is set
        setTimeout(() => {
            const rightArrow = document.getElementById('Eye_right_arrow');
            const leftArrow = document.getElementById('Eye_left_arrow');
            
            if (rightArrow) {
                rightArrow.addEventListener('click', () => {
                    const slider = document.getElementById('EyeColourRange');
                    if (slider.value !== slider.max) {
                        slider.value = parseInt(slider.value) + 1;
                        document.getElementById('ColourEyeValue').innerText = `${JrsI18n.t("character_colour", "Colour")} ${slider.value}`;
                        setCreatorColourSelection('ColourEye_', elem.colours, slider.value);

                        elem.colours.forEach(colour => {
                            const colourElem = document.getElementById('ColourEye_' + colour.id);
                            if (colourElem) {
                                colourElem.classList.remove('selected');
                                if (creatorIdsEqual(colour.id, slider.value)) {
                                    colourElem.classList.add('selected');
                                }
                            }
                        });
                    }

                    creatorPostControl('EyeColourValue', { item: slider.value });
                });
            }
            
            if (leftArrow) {
                leftArrow.addEventListener('click', () => {
                    const slider = document.getElementById('EyeColourRange');
                    if (slider.value !== slider.min) {
                        slider.value = parseInt(slider.value) - 1;
                        document.getElementById('ColourEyeValue').innerText = `${JrsI18n.t("character_colour", "Colour")} ${slider.value}`;
                        setCreatorColourSelection('ColourEye_', elem.colours, slider.value);

                        elem.colours.forEach(colour => {
                            const colourElem = document.getElementById('ColourEye_' + colour.id);
                            if (colourElem) {
                                colourElem.classList.remove('selected');
                                if (creatorIdsEqual(colour.id, slider.value)) {
                                    colourElem.classList.add('selected');
                                }
                            }
                        });
                    }

                    creatorPostControl('EyeColourValue', { item: slider.value });
                });
            }
        }, 0);

        //Empty Colour List
        colourList = document.getElementById('ColourListEye');
        colourList.innerHTML = '';

        //Create new Colour List
        elem.colours.forEach(colour => {

            const colourElem = document.createElement('a');

            colourElem.innerHTML = `<img src="${colour.image}" alt="colour ${colour.id}" id="ColourEye_${colour.id}" class="Colour">`;
            colourList.appendChild(colourElem);

            document.getElementById('ColourEye_' + colour.id).addEventListener('click', () => {
                const slider = document.getElementById('EyeColourRange');
                slider.value = parseInt(colour.id);

                document.getElementById('ColourEyeValue').innerText = `${JrsI18n.t("character_colour", "Colour")} ${slider.value}`;
                setCreatorColourSelection('ColourEye_', elem.colours, slider.value);

                elem.colours.forEach(colour => {

                    document.getElementById('ColourEye_' + colour.id).classList.remove('selected');

                    if (creatorIdsEqual(colour.id, slider.value)) {
                        document.getElementById('ColourEye_' + colour.id).classList.add('selected');
                    };

                });


                creatorPostControl('EyeColourValue', { item: slider.value });
            });

            if (creatorIdsEqual(colour.id, elem.tintValue)) {
                document.getElementById('ColourEye_' + colour.id).classList.add('selected');
            };

        });


    });

}


///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                  GENERATE EDITION MENU                                            //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////

function prettyCreatorExpressionName(hashName) {
    if (!hashName) return '';
    return hashName
        .replace(/_/g, ' ')
        .replace(/withd/gi, 'Width')
        .replace(/\b\w/g, char => char.toUpperCase());
}

function safeCreatorDomId(value) {
    return String(value || '').replace(/[^a-zA-Z0-9_-]/g, '_');
}

function clampCreatorPercent(value) {
    const numericValue = Number(value);
    if (Number.isNaN(numericValue)) return 50;
    return Math.max(0, Math.min(100, Math.round(numericValue)));
}

function buildCreatorExpressionSlider(sliderKey, title, leftLabel, rightLabel, startValue) {
    const safeTitle = title || JrsI18n.t("character_value", "Value");
    const safeLeftLabel = leftLabel || JrsI18n.t("character_min", "Min");
    const safeRightLabel = rightLabel || JrsI18n.t("character_max", "Max");
    const safeStartValue = clampCreatorPercent(startValue);

    return `
        <div class="creator-expression-slider">
            <div class="creator-expression-slider-title">
                <p class="creator-expression-name">${safeTitle}</p>
                <p class="creator-expression-value" id="creatorExpressionValue_${sliderKey}">${safeStartValue}</p>
            </div>
            <div class="creator-expression-slider-row">
                <span class="creator-expression-end">${safeLeftLabel}</span>
                <a id="creator_left_arrow_${sliderKey}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_left", "Arrow left")}"></a>
                <input type="range" min="0" max="100" value="${safeStartValue}" class="creatorSlider creatorSliderArrow" id="creatorRange_${sliderKey}">
                <a id="creator_right_arrow_${sliderKey}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_right", "Arrow right")}" style="transform: rotate(180deg);"></a>
                <span class="creator-expression-end">${safeRightLabel}</span>
            </div>
        </div>`;
}

function bindCreatorExpressionSlider(sliderKey, expressionId) {
    const slider = document.getElementById(`creatorRange_${sliderKey}`);
    const valueLabel = document.getElementById(`creatorExpressionValue_${sliderKey}`);
    const leftArrow = document.getElementById(`creator_left_arrow_${sliderKey}`);
    const rightArrow = document.getElementById(`creator_right_arrow_${sliderKey}`);

    if (!slider || !valueLabel) return;

    const syncValue = () => {
        valueLabel.innerText = `${slider.value}`;
    };

    const postChange = () => {
        creatorPostControl('sliderCharChange', {
            ElementID: expressionId,
            value: slider.value
        });
    };

    slider.addEventListener('input', () => {
        syncValue();
        postChange();
    });

    slider.addEventListener('change', () => {
        syncValue();
        postChange();
    });

    if (leftArrow) {
        leftArrow.addEventListener('click', () => {
            if (parseInt(slider.value, 10) > parseInt(slider.min, 10)) {
                slider.value = parseInt(slider.value, 10) - 1;
                syncValue();
                postChange();
            }
        });
    }

    if (rightArrow) {
        rightArrow.addEventListener('click', () => {
            if (parseInt(slider.value, 10) < parseInt(slider.max, 10)) {
                slider.value = parseInt(slider.value, 10) + 1;
                syncValue();
                postChange();
            }
        });
    }
}

function createEditionMenu() {

    // Rebuild from scratch: a second showEditionMenu (double-clicked sub-item)
    // used to append a second copy of the sliders under the first.
    const editionList = document.getElementById('EditionMenuElemList');
    if (editionList) editionList.innerHTML = '';

    EditionElem.forEach(elem => {

        titleMenu = document.getElementById('titleEditionMenu');
        const titleText = String(elem.name ?? '');
        titleMenu.textContent = titleText.startsWith('@@') && typeof JrsI18n !== 'undefined' && typeof JrsI18n.t === 'function'
            ? JrsI18n.t(titleText.slice(2), titleText.slice(2))
            : titleText;

        elem.division.forEach(div => {

            const editionContainer = document.getElementById('EditionMenuElemList');
            const editionElement = document.createElement('div');
            editionElement.classList.add('EditionMenuElem');

            editionElement.innerHTML = `
                    <div id="EditionTitle">

                        <img src="${div.icon}" alt="${JrsI18n.t("character_camera_icon", "Camera Icon")}">
                        <h2>${div.name}</h2>


                    </div>

                    <img src="img/separator.png" alt="separator" class="separatorEdition">`;
            editionContainer.appendChild(editionElement);


            div.elements.forEach(element => {

                if (element.type === "matrice") {

                    const editionContainer = document.getElementById('EditionMenuElemList');
                    const sliderReplacementContainer = document.createElement('div');
                    sliderReplacementContainer.classList.add('creator-matrix-replacement');

                    const xSliderKey = safeCreatorDomId(`${div.id}_${element.id}_${element.XHashes}`);
                    const ySliderKey = safeCreatorDomId(`${div.id}_${element.id}_${element.YHashes}`);

                    const xStartValue = clampCreatorPercent((Number(element.startPositionX ?? 0.5)) * 100);
                    const yStartValue = clampCreatorPercent((Number(element.startPositionY ?? 0.5)) * 100);

                    const xTitle = prettyCreatorExpressionName(element.XHashes);
                    const yTitle = prettyCreatorExpressionName(element.YHashes);

                    sliderReplacementContainer.innerHTML = `
                        <div class="creator-matrix-replacement-inner" id="matriceContainer_${div.id}_${element.id}">
                            ${buildCreatorExpressionSlider(xSliderKey, xTitle, element.leftValueName, element.rightValueName, xStartValue)}
                            ${buildCreatorExpressionSlider(ySliderKey, yTitle, element.topValueName, element.bottomValueName, yStartValue)}
                        </div>`;

                    editionContainer.appendChild(sliderReplacementContainer);

                    bindCreatorExpressionSlider(xSliderKey, element.XHashes);
                    bindCreatorExpressionSlider(ySliderKey, element.YHashes);

                } else if (element.type === "slider") {


                    const editionContainer = document.getElementById('EditionMenuElemList');
                    const sliderContainer = document.createElement('div');
                    sliderContainer.classList.add('sliderContainer');

                    sliderContainer.innerHTML = `

                        <div class="sliderContainer">

                        <p>${element.leftValueName}</p>

                        <div class="slider">
                            <input type="range" value="${element.startValue}" min="0" max="100" name="Variation" class="creatorSlider" id="slider_editionChar_${element.id}">
                        </div>

                        <p>${element.rightValueName}</p>

                    </div>`;

                    editionContainer.appendChild(sliderContainer);

                    // Send data
                    document.getElementById('slider_editionChar_' + element.id).addEventListener('input', () => {
                        const slider = document.getElementById('slider_editionChar_' + element.id);
                        creatorPostControl('sliderCharChange', {
                            ElementID: element.id,
                            value: slider.value
                        });
                    });
                } else if (element.type === "slider_legacy") {

                    const globalApparenceMenuElem = document.createElement('div');
                    globalApparenceMenuElem.classList.add('GlobalSettingsElem');

                    globalApparenceMenuElem.innerHTML = `
                <div class="styleElem unselectable" id="item_app_${div.id}_${element.id}">
                        <p class="elemTitle">${element.name}</p>
                        <div class="sliderDiv">
                            <p class="sliderValue unselectable" id="sliderValue_app_${div.id}_${element.id}">${JrsI18n.t("character_style", "Style")} ${element.value}</p>
                            <div class="sliderElem">
                                <a id="left_arrow_app_${div.id}_${element.id}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_left", "Arrow left")}"></a>
                                <input type="range" min="1" max="${element.totalAmount}" value="${element.value}" class="slider" id="rangeGlobalApp_${div.id}_${element.id}">
                                <a id="right_arrow_app_${div.id}_${element.id}" class="arrow"><img src="./img/arrow.png" alt="${JrsI18n.t("character_arrow_right", "Arrow right")}" style="transform: rotate(180deg);"></a>
                            </div>
                        </div>
                    </div>`;

                    editionContainer.appendChild(globalApparenceMenuElem);

                    updateRangeBackground('rangeGlobalApp_' + div.id + '_' + element.id);


                    document.getElementById('right_arrow_app_' + div.id + '_' + element.id).addEventListener('click', () => {
                        const slider = document.getElementById('rangeGlobalApp_' + div.id + '_' + element.id);
                        if (slider.value !== slider.max) {
                            slider.value = parseInt(slider.value) + 1;
                            document.getElementById('sliderValue_app_' + div.id + '_' + element.id).innerText = `${JrsI18n.t("character_style", "Style")} ${slider.value}`;
                            updateRangeBackground('rangeGlobalApp_' + div.id + '_' + element.id);
                        }

                        creatorPostControl('globalApparence', {
                            item: slider.value,
                            elem: element.id
                        });
                    });

                    document.getElementById('left_arrow_app_' + div.id + '_' + element.id).addEventListener('click', () => {
                        const slider = document.getElementById('rangeGlobalApp_' + div.id + '_' + element.id);

                        if (slider.value !== slider.min) {
                            slider.value = parseInt(slider.value) - 1;
                            document.getElementById('sliderValue_app_' + div.id + '_' + element.id).innerText = `${JrsI18n.t("character_style", "Style")} ${slider.value}`;
                            updateRangeBackground('rangeGlobalApp_' + div.id + '_' + element.id);
                        }

                        creatorPostControl('globalApparence', {
                            item: slider.value,
                            elem: element.id
                        });
                    });

                    document.getElementById('rangeGlobalApp_' + div.id + '_' + element.id).addEventListener('input', () => {
                        const slider = document.getElementById('rangeGlobalApp_' + div.id + '_' + element.id);
                        document.getElementById('sliderValue_app_' + div.id + '_' + element.id).innerText = `${JrsI18n.t("character_style", "Style")} ${slider.value}`;
                        updateRangeBackground('rangeGlobalApp_' + div.id + '_' + element.id);

                        creatorPostControl('globalApparence', {
                            item: slider.value,
                            elem: element.id
                        });
                    });
                }

            });




        });

    });

};


///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                       INDICATOR MNG                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////// UPDATE LINE POSITION //////////////////////////

let cachedCardHeight = 32;
let cachedCardOffset = 155;

function updateCachedDimensions() {
    const card = document.querySelector('.head-indicator, .head-indicator-right');
    if (card) {
        if (card.offsetHeight > 0) {
            cachedCardHeight = card.offsetHeight;
        }
        if (card.classList.contains('head-indicator') && card.offsetLeft > 0) {
            cachedCardOffset = card.offsetLeft;
        }
    }
    if (!cachedCardOffset || cachedCardOffset < 50) {
        cachedCardOffset = Math.min(155, Math.max(110, 0.095 * window.innerWidth));
    }
}

function getCardHeight() {
    return cachedCardHeight || 32;
}

function getCardHorizontalOffset() {
    return cachedCardOffset || Math.min(155, Math.max(110, 0.095 * window.innerWidth));
}

function updateLine(index, sens, targetCenterY) {
    const line = document.getElementById('line_' + index);
    const container = document.getElementById('pin' + index);
    if (!line || !container) return;

    const startX = Number(container.dataset.pinX) || 0;
    const startY = Number(container.dataset.pinY) || 0;
    const cardOffset = getCardHorizontalOffset();
    const isRight = sens === 'right';

    // Direct geometric connection from dot to nearest card edge:
    // If card is on the right side of the body, connect to its left edge.
    // If card is on the left side of the body, connect to its right edge.
    const endX = isRight ? (startX + cardOffset) : (startX - cardOffset);
    const endY = typeof targetCenterY === 'number' ? targetCenterY : startY;

    const dx = endX - startX;
    const dy = endY - startY;
    const length = Math.sqrt((dx * dx) + (dy * dy));
    const angle = Math.atan2(dy, dx);

    line.style.width = `${length}px`;
    line.style.position = 'absolute';
    line.style.left = '0px';
    line.style.top = '0px';
    line.style.transform = `rotate(${angle}rad)`;
}

function updateSelectLine(index) {

    const dot = document.getElementById('dot_select_' + index);
    const line = document.getElementById('line_select_' + index);
    const indicator = document.getElementById('head_select_' + index);

    if (!dot || !line || !indicator) return;

    const dotRect = dot.getBoundingClientRect();
    const indicatorRect = indicator.getBoundingClientRect();

    const startX = dotRect.left + dotRect.width / 2;
    const startY = dotRect.top + dotRect.height / 2;

    const endX = indicatorRect.right;
    const endY = indicatorRect.bottom;

    const distance = Math.min(
        Math.abs(endX - startX),
        Math.abs(endY - startY)
    );

    const dirX = endX > startX ? 1 : -1;
    const dirY = endY > startY ? 1 : -1;

    const inflectionX = startX + (distance * dirX + 35);
    const inflectionY = startY + (distance * dirY);

    const length1 = Math.sqrt(Math.pow(inflectionX - startX, 2) + Math.pow(inflectionY - startY, 2));
    const angle1 = Math.atan2(inflectionY - startY, inflectionX - startX);

    const length2 = Math.sqrt(Math.pow(endX - inflectionX, 2) + Math.pow(endY - inflectionY, 2));
    const angle2 = Math.atan2(endY - inflectionY, endX - inflectionX);

    line.style.width = `${length1}px`;
    line.style.left = `${startX}px`;
    line.style.top = `${startY}px`;
    line.style.transform = `rotate(${angle1}rad)`;

    let line2 = document.getElementById('line2_select' + index);
    if (!line2) {
        line2 = document.createElement('div');
        line2.id = 'line2_select' + index;
        line2.className = 'line';
        document.getElementById('pinSelect' + index).appendChild(line2);
    }

    line2.style.width = `${length2}px`;
    line2.style.left = `${inflectionX}px`;
    line2.style.top = `${inflectionY}px`;
    line2.style.transform = `rotate(${angle2}rad)`;



}

////////////////////////// INDICATOR POSITION ON START //////////////////////////

function positionnerElementStart(index, x, y, sens) {
    const container = document.getElementById('pin' + index);

    if (!container) return;

    const pixelX = (Number(x) || 0) * window.innerWidth;
    const pixelY = (Number(y) || 0) * window.innerHeight;

    updateDotPos(index, pixelX, pixelY, sens, pixelY);
}


function positionnerSelectElementStart(index, x, y, sens) {
    const container = document.getElementById('pinSelect' + index);
    if (!container) return;

    const pixelX = (Number(x) || 0) * window.innerWidth;
    const pixelY = (Number(y) || 0) * window.innerHeight;

    container.style.left = `${pixelX}px`;
    container.style.top = `${pixelY}px`;

    setTimeout(() => {
        if (typeof updateSelectLine === 'function') updateSelectLine(index, sens);
    }, 10);
}

////////////////////////// UPDATE POSITION OF THE DOT //////////////////////////

function updateDotPos(index, pixelX, pixelY, sens, targetCenterY) {
    const container = document.getElementById('pin' + index);
    const dot = document.getElementById('dot_' + index);

    if (!container || !dot) return;

    container.dataset.pinX = pixelX;
    container.dataset.pinY = pixelY;
    container.style.left = '0px';
    container.style.top = '0px';
    container.style.transform = `translate3d(${pixelX}px, ${pixelY}px, 0)`;
    dot.style.position = 'absolute';
    dot.style.left = '0px';
    dot.style.top = '0px';

    updateLine(index, sens, targetCenterY);
}



////////////////////////// CREATE (GENERATE) PIN FROM JSON //////////////////////////

let activeHoveredPinId = null;

function closeCreatorPinMenu(pinId, restoreOthers = true) {
    const underMenu = document.getElementById(`Under_menu_${pinId}`);
    if (underMenu) underMenu.classList.add('hidden');
    if (creatorPinnedMenuId === pinId) creatorPinnedMenuId = null;
    if (activeHoveredPinId === pinId) activeHoveredPinId = null;
    if (restoreOthers) underMenuAppears(pinId, "show");
}

// Visible gap between a pin card and its sub-menu. The card width follows the
// label length, so the menu is placed from the card's real edge instead of a
// fixed CSS offset (long Arabic labels made the menu cover the card arrow).
// The gap itself stays hoverable (padding / spacer) so the menu doesn't close
// while the mouse crosses it.
const CREATOR_PIN_MENU_GAP = 14;

function placeCreatorPinMenu(pinId) {
    const card = document.getElementById(`head_${pinId}`);
    const underMenu = document.getElementById(`Under_menu_${pinId}`);
    if (!card || !underMenu || underMenu.classList.contains('hidden')) return;

    const opensRight = underMenu.classList.contains('under_menu');
    const cardLeft = card.offsetLeft;
    const cardRight = card.offsetLeft + card.offsetWidth;

    underMenu.style.right = 'auto';
    if (opensRight) {
        underMenu.style.paddingLeft = CREATOR_PIN_MENU_GAP + 'px';
        underMenu.style.left = cardRight + 'px';
    } else {
        // padding (not a spacer div) so RTL flex order can't flip the gap side
        underMenu.style.paddingRight = CREATOR_PIN_MENU_GAP + 'px';
        underMenu.style.left = (cardLeft - underMenu.offsetWidth) + 'px';
    }
}

function openCreatorPinMenu(pinId) {
    if (creatorPinnedMenuId !== null && creatorPinnedMenuId !== pinId) {
        closeCreatorPinMenu(creatorPinnedMenuId, true);
    }
    const underMenu = document.getElementById(`Under_menu_${pinId}`);
    if (!underMenu) return;
    creatorPinnedMenuId = pinId;
    activeHoveredPinId = pinId;
    underMenu.classList.remove('hidden');
    placeCreatorPinMenu(pinId);
    underMenuAppears(pinId, "hide");
}

function resetCreatorPinMenus() {
    activeHoveredPinId = null;
    if (creatorPinnedMenuId !== null) {
        closeCreatorPinMenu(creatorPinnedMenuId, true);
        creatorPinnedMenuId = null;
    }
    document.querySelectorAll('[id^="Under_menu_"]').forEach(menu => menu.classList.add('hidden'));
    if (Array.isArray(pinElem)) {
        pinElem.forEach(pin => {
            const wrapper = document.getElementById('pin' + pin.id);
            if (wrapper) wrapper.classList.remove('hidden');
        });
    }
}

function bindCreatorPinOutsideClick() {
    if (creatorPinOutsideClickBound) return;
    creatorPinOutsideClickBound = true;
    document.addEventListener('click', event => {
        if (creatorPinnedMenuId === null) return;
        const container = document.getElementById('BodyPartsMenu');
        if (container && container.contains(event.target)) return;
        resetCreatorPinMenus();
    });
}

function getBodyPinIcon(pinId) {
    const id = String(pinId || '').toLowerCase();
    if (id === 'head') return './img/categories/head_male.png';
    if (id === 'eyesandbrows') return './img/icons/eye.png';
    if (id === 'facial') return './img/categories/skin.png';
    if (id === 'mouth') return './img/categories/barber.png';
    if (id === 'upperbody') return './img/categories/upper_male.png';
    if (id === 'lowerbody') return './img/categories/lower_male.png';
    if (id === 'clothes') return './img/categories/shirt.png';
    return './img/icons/variation_icon.png';
}

let creatorPinsUserHidden = false;

function toggleCreatorPins() {
    creatorPinsUserHidden = !creatorPinsUserHidden;
    const pinContainer = document.getElementById('pinContainer');
    const toggleBtn = document.getElementById('creatorTogglePinsBtn');
    const toggleLabel = document.getElementById('creatorTogglePinsLabel');
    if (creatorPinsUserHidden) {
        if (pinContainer) pinContainer.classList.add('hidden');
        if (toggleBtn) toggleBtn.classList.add('active');
        if (toggleLabel) toggleLabel.textContent = JrsI18n.t('character_pins_off', 'Pins: OFF');
    } else {
        if (pinContainer) pinContainer.classList.remove('hidden');
        if (toggleBtn) toggleBtn.classList.remove('active');
        if (toggleLabel) toggleLabel.textContent = JrsI18n.t('character_pins_on', 'Pins: ON');
        if (Array.isArray(pinElem)) {
            positionPin(pinElem);
        }
    }
}

window.addEventListener('keydown', event => {
    if (isCreatorTextField(document.activeElement) || isCreatorTextField(event.target)) return;
    if (event.ctrlKey || event.altKey || event.metaKey || event.isComposing) return;
    // The identity form (name / nickname / story) is all typing: a keystroke
    // that missed the field must not move the camera there.
    if (isCreatorElementVisible('CharactersMenu')) return;

    if (event.key === 'h' || event.key === 'H') {
        const globalMenu = document.getElementById('GlobalCharacterMenu');
        if (globalMenu && !globalMenu.classList.contains('hidden')) {
            toggleCreatorPins();
        }
    } else if (creatorHasActiveEditTarget()) {
        if (event.key === 'ArrowLeft' || event.key === 'a' || event.key === 'A') {
            sendCreatorViewAction('rotateLeft');
        } else if (event.key === 'ArrowRight' || event.key === 'd' || event.key === 'D') {
            sendCreatorViewAction('rotateRight');
        } else if (event.key === 'ArrowUp' || event.key === 'w' || event.key === 'W') {
            sendCreatorViewAction('moveUp');
        } else if (event.key === 'ArrowDown' || event.key === 's' || event.key === 'S') {
            sendCreatorViewAction('moveDown');
        }
    }
});

let isDraggingCreatorPed = false;
let dragCreatorStartX = 0;
let creatorDragDelta = 0;
let creatorDragFrame = null;
let creatorDragInFlight = false;

function scheduleCreatorDrag() {
    if (creatorDragFrame !== null || creatorDragInFlight || !creatorDragDelta) return;
    creatorDragFrame = requestAnimationFrame(() => {
        creatorDragFrame = null;
        if (!creatorHasActiveEditTarget()) { creatorDragDelta = 0; return; }
        const delta = creatorDragDelta;
        creatorDragDelta = 0;
        creatorDragInFlight = true;
        // Deltas must accumulate while a request is in flight; latest-value
        // coalescing would discard part of the user's movement.
        try {
            creatorPost('creatorViewControl', { action: 'rotateDrag', delta }).always(() => {
                creatorDragInFlight = false;
                scheduleCreatorDrag();
            });
        } catch (_) {
            creatorDragInFlight = false;
        }
    });
}

function stopCreatorDrag() {
    isDraggingCreatorPed = false;
    scheduleCreatorDrag();
}

window.addEventListener('pointerdown', event => {
    if (!creatorHasActiveEditTarget()) return;
    if (event.target.closest('button, a, input, textarea, select, .container_pin, .styleElem, #CreatorPlayerControls, .CharactersMenuContent, .under_elem')) return;
    if (event.button === 0 || event.button === 2) {
        isDraggingCreatorPed = true;
        dragCreatorStartX = event.clientX;
    }
});

window.addEventListener('pointermove', event => {
    if (!isDraggingCreatorPed) return;
    if (!creatorHasActiveEditTarget()) { isDraggingCreatorPed = false; creatorDragDelta = 0; return; }
    // The pointerup was lost (cursor left the NUI surface, focus flicker):
    // without this the ped kept spinning with every mouse move afterwards.
    if (event.buttons === 0) { stopCreatorDrag(); return; }
    creatorDragDelta += (event.clientX - dragCreatorStartX) * 0.3;
    dragCreatorStartX = event.clientX;
    scheduleCreatorDrag();
});

window.addEventListener('pointerup', stopCreatorDrag);
window.addEventListener('pointercancel', stopCreatorDrag);
window.addEventListener('blur', stopCreatorDrag);


// Which side a pin's card actually floats to, decided once per menu-open
// (resolveClusterSides) and reused on every later position update.
const pinActualDirection = {};

// Only the head/eyes/face/mouth pins share one bone (21030) and can end up
// clustered close enough together to cross - upperbody/clothes/lowerbody
// come from different bones far enough apart vertically that they never
// have, in any reported case. Those three always render at Murphy's
// literal default; only this cluster's sides get resolved below.
const PIN_CLUSTER_SHARED_BONE = ['head', 'eyesandbrows', 'facial', 'mouth'];

function segmentsIntersect(a, b) {
    function ccw(ax, ay, bx, by, cx, cy) { return (cy - ay) * (bx - ax) - (by - ay) * (cx - ax); }
    const d1 = ccw(a.x1, a.y1, a.x2, a.y2, b.x1, b.y1), d2 = ccw(a.x1, a.y1, a.x2, a.y2, b.x2, b.y2);
    const d3 = ccw(b.x1, b.y1, b.x2, b.y2, a.x1, a.y1), d4 = ccw(b.x1, b.y1, b.x2, b.y2, a.x2, a.y2);
    return ((d1 > 0) !== (d2 > 0)) && ((d3 > 0) !== (d4 > 0));
}

// Approximates a pin's connector line (dot -> card's near edge) without
// touching the DOM, using the same fixed offsets createPin's CSS produces
// (.head-indicator right:26px in a 315px-wide container -> near edge at
// dot+119; .head-indicator-right left:-238px, width 170px -> near edge at
// dot-68; both cards sit ~30px below their dot's row via top:10px + half
// their own height). Precise enough to decide left/right, not meant to
// match getBoundingClientRect pixel-for-pixel.
function approxPinLine(pin, side) {
    const dotX = (Number(pin.startPosition?.x) || 0.5) * window.innerWidth;
    const dotY = (Number(pin.startPosition?.y) || 0.5) * window.innerHeight;
    const dx = side === 'right' ? 70 : -70;
    return { x1: dotX, y1: dotY, x2: dotX + dx, y2: dotY };
}

// Shortest distance between two segments, by sampling points along each -
// simple and robust for these short 4-point connector lines. Used instead
// of a plain intersection test below: a pair of lines that pass within a
// couple of pixels of each other without technically crossing (their
// dot ends, specifically) still reads as visually crossing once real font
// metrics/icon sizing shift things by a pixel or two, so "close" is
// treated the same as "crossing" for picking a side combination.
function segMinDistance(a, b, samples) {
    const n = samples || 10;
    let minDist = Infinity;
    for (let i = 0; i <= n; i += 1) {
        const t = i / n;
        const px = a.x1 + (a.x2 - a.x1) * t;
        const py = a.y1 + (a.y2 - a.y1) * t;
        for (let j = 0; j <= n; j += 1) {
            const s = j / n;
            const qx = b.x1 + (b.x2 - b.x1) * s;
            const qy = b.y1 + (b.y2 - b.y1) * s;
            const dist = Math.hypot(px - qx, py - qy);
            if (dist < minDist) minDist = dist;
        }
    }
    return minDist;
}

const PIN_LINE_SAFETY_MARGIN_PX = 10;
function linesConflict(a, b) {
    return segmentsIntersect(a, b) || segMinDistance(a, b) < PIN_LINE_SAFETY_MARGIN_PX;
}

// Resolves which side (left/right) each pin in PIN_CLUSTER_SHARED_BONE
// floats its card to. Murphy's own per-category `direction` is a FIXED
// pairing (head+mouth one side, eyes+facial the other) that assumes the
// four head-area dots stay spread apart - true at Murphy's fixed camera
// distance, false once jrs_character's camera zooms in close enough that
// all four dots pack into a small area (confirmed live TWICE: once with a
// user screenshot's exact coordinates, once by reverting to pure Murphy
// on request and immediately reproducing the same crossing again).
// Brute-forces every left/right combination for the (at most 4) cluster
// pins, keeps only the ones with the fewest actual line crossings, and
// among those picks the one closest to Murphy's own pairing - so a shot
// that already renders crossing-free at Murphy's default keeps that exact
// default (zero deviation), and only a shot that would actually cross
// gets the minimum change needed to stop it.
function resolveClusterSides(clusterPins) {
    const n = clusterPins.length;
    const defaults = clusterPins.map(p => (p.direction === 'right' ? 'right' : 'left'));
    if (n === 0) return {};
    let bestSides = defaults, bestCrossings = Infinity, bestDeviation = Infinity;
    for (let mask = 0; mask < (1 << n); mask += 1) {
        const sides = clusterPins.map((p, i) => (mask & (1 << i)) ? 'right' : 'left');
        let crossings = 0;
        for (let i = 0; i < n; i += 1) {
            for (let j = i + 1; j < n; j += 1) {
                if (linesConflict(approxPinLine(clusterPins[i], sides[i]), approxPinLine(clusterPins[j], sides[j]))) crossings += 1;
            }
        }
        const deviation = sides.reduce((sum, side, i) => sum + (side !== defaults[i] ? 1 : 0), 0);
        if (crossings < bestCrossings || (crossings === bestCrossings && deviation < bestDeviation)) {
            bestCrossings = crossings;
            bestDeviation = deviation;
            bestSides = sides;
        }
    }
    const result = {};
    clusterPins.forEach((p, i) => { result[p.id] = bestSides[i]; });
    return result;
}

function createPin(pinElem) {

    bindCreatorPinOutsideClick();
    creatorPinnedMenuId = null;
    activeHoveredPinId = null;
    updateCachedDimensions();

    const pinContainer = document.getElementById('pinContainer');
    if (!pinContainer) return;
    pinContainer.innerHTML = '';

    if (!Array.isArray(pinElem)) return;

    pinElem.forEach(pin => {
        pinActualDirection[pin.id] = (pin.direction === 'right' ? 'right' : 'left');
        const isRight = pinActualDirection[pin.id] === "right";
        const pinWrapper = document.createElement('div');
        pinWrapper.classList.add(isRight ? 'container' : 'container-right');
        pinWrapper.id = 'pin' + pin.id;

        const pinDisplayName = (typeof JrsI18n !== 'undefined' && typeof JrsI18n.t === 'function' && typeof pin.name === 'string' && pin.name.startsWith('@@'))
            ? JrsI18n.t(pin.name.slice(2), pin.name)
            : pin.name;

        pinWrapper.innerHTML = isRight ? `
            <div class="head-indicator" id="head_${pin.id}">
             <div class="body-pin-label">
                <img src="${getBodyPinIcon(pin.id)}" alt="${pinDisplayName}" class="body-pin-icon">
                <p>${pinDisplayName}</p>
             </div>
             <img src="./img/arrow.png" alt="arrow" class="right_arrow">
            </div>
            <div id="line_${pin.id}" class="line"></div>
            <div id="dot_${pin.id}" class="dot"></div>
            <div id="Under_menu_${pin.id}" class="under_menu hidden"></div>
        ` : `
            <div class="head-indicator-right" id="head_${pin.id}">
             <img src="./img/arrow.png" alt="arrow" class="right_arrow-right">
             <div class="body-pin-label body-pin-label-right">
                <img src="${getBodyPinIcon(pin.id)}" alt="${pinDisplayName}" class="body-pin-icon">
                <p>${pinDisplayName}</p>
             </div>
            </div>
            <div id="line_${pin.id}" class="line-right"></div>
            <div id="dot_${pin.id}" class="dot-right"></div>
            <div id="Under_menu_${pin.id}" class="under_menu-right hidden"></div>
        `;

        pinContainer.appendChild(pinWrapper);
        positionnerElementStart(pin.id, pin.startPosition.x, pin.startPosition.y, pinActualDirection[pin.id]);

        const headerAct = document.getElementById('head_' + pin.id);
        const underMenu = document.getElementById('Under_menu_' + pin.id);
        if (!headerAct || !underMenu) return;

        const showHoverMenu = () => {
            if (creatorPinnedMenuId !== null && creatorPinnedMenuId !== pin.id) return;
            activeHoveredPinId = pin.id;
            underMenu.classList.remove('hidden');
            placeCreatorPinMenu(pin.id);
            underMenuAppears(pin.id, "hide");
        };

        const hideHoverMenu = () => {
            if (creatorPinnedMenuId === pin.id) return;
            if (activeHoveredPinId === pin.id) activeHoveredPinId = null;
            underMenu.classList.add('hidden');
            underMenuAppears(pin.id, "show");
        };

        headerAct.addEventListener('mouseenter', showHoverMenu);
        pinWrapper.addEventListener('mouseleave', hideHoverMenu);
        underMenu.addEventListener('mouseenter', showHoverMenu);
        underMenu.addEventListener('mouseleave', hideHoverMenu);

        headerAct.addEventListener('click', event => {
            event.preventDefault();
            event.stopPropagation();
            if (creatorPinnedMenuId === pin.id) {
                closeCreatorPinMenu(pin.id, true);
            } else {
                openCreatorPinMenu(pin.id);
            }
        });

        underMenu.addEventListener('click', event => event.stopPropagation());

        pin.subElem.forEach(subElem => {
            const elemUnder = document.createElement('a');
            elemUnder.classList.add('under_elem');
            elemUnder.id = 'elem_under_' + subElem.id;
            const subElemDisplayName = (typeof JrsI18n !== 'undefined' && typeof JrsI18n.t === 'function' && typeof subElem.name === 'string' && subElem.name.startsWith('@@'))
                ? JrsI18n.t(subElem.name.slice(2), subElem.name)
                : subElem.name;
            elemUnder.textContent = subElemDisplayName;

            if (isRight) {
                underMenu.appendChild(elemUnder);
            } else {
                const flexWrapper = document.createElement('div');
                flexWrapper.style.display = 'flex';
                flexWrapper.appendChild(elemUnder);
                underMenu.appendChild(flexWrapper);
            }

            elemUnder.addEventListener('click', event => {
                event.preventDefault();
                event.stopPropagation();
                activeHoveredPinId = null;
                $.post(`https://${GetParentResourceName()}/showEditionMenu`, JSON.stringify({
                    pinId: pin.id,
                    pinName: pin.name,
                    elemId: subElem.id,
                    subElemName: subElem.name
                }));
                resetCreatorPinMenus();
            });
        });
    });

    updateCachedDimensions();
    positionPin(pinElem);
}



////////////////////////// SELECT CHAR PIN CREATOR //////////////////////////

function setCreateCharacterSelectorAction(canCreate, currentCharacters, maxCharacters) {
    const action = document.getElementById('CreateCharacterSelectorAction');
    if (!action) return;

    const current = Number(currentCharacters);
    const maximum = Number(maxCharacters);
    const hasExactLimit = Number.isFinite(current) && Number.isFinite(maximum) && maximum > 0;
    const countAllowed = hasExactLimit ? current < maximum : true;
    const allowed = canCreate === true && countAllowed;

    action.classList.toggle('hidden', !allowed);
    action.setAttribute('aria-hidden', allowed ? 'false' : 'true');
    action.style.pointerEvents = allowed ? 'auto' : 'none';
}

function createPinSelection(pinPerso) {
    const pinsContainer = document.getElementById('selectCharPinContainer');
    if (!pinsContainer) return;
    pinsContainer.innerHTML = '';

    (Array.isArray(pinPerso) ? pinPerso : []).forEach(pin => {
        if (pin.ExistingChar !== true) return;

        const pinContainer = document.getElementById('selectCharPinContainer');
        const pinElem = document.createElement('div');
        pinElem.classList.add('container_select');
        pinElem.id = 'pinSelect' + pin.id;

        const pinFallbackName = JrsI18n.t("character_pin_fallback", "Character");
        const safeName = String(pin.name || pinFallbackName).trim() || pinFallbackName;
        pinElem.innerHTML = `
            <div class="head-indicator-select" id="head_select_${pin.id}">
                <p title="${safeName.replace(/"/g, '&quot;')}">${safeName}</p>
                <img src="./img/arrow.png" alt="arrow" class="right_arrow">
            </div>
        `;

        pinContainer.appendChild(pinElem);
        positionnerSelectElementStart(pin.id, pin.startPosition.x, pin.startPosition.y, pin.direction);

        const selectorCard = document.getElementById('pinSelect' + pin.id);
        selectorCard?.addEventListener('click', event => {
            event.preventDefault();
            event.stopPropagation();
            creatorPostAction(selectorCard, 'selectedChar', {
                pinId: pin.id,
                pinName: safeName,
            });
        });
    });
}



////////////////////////// SUB MENU ELEMENTS //////////////////////////

function underMenuAppears(pinAct, state) {
    pinElem.forEach(pin => {

        if (state === "hide") {
            if (pin.id !== pinAct) {
                const underMenu = document.getElementById('pin' + pin.id);
                underMenu.classList.add('hidden');
            }
        } else if (state === "show") {
            const underMenu = document.getElementById('pin' + pin.id);
            underMenu.classList.remove('hidden');
        }

    });


}

////////////////////////// UPDATE POSITION OF THE PIN //////////////////////////

// Keep body-part dots firmly anchored to their exact 3D bone screen positions
function declutterDotPositions(entries) {
    // Exact bone coordinates from 3D projection are preserved
}

// Keeps indicator cards on the same side from visually overlapping or
// colliding when body parts are close together vertically (e.g. face and mouth,
// or head and eyes). Guarantees a minimum vertical clearance between adjacent cards.
function declutterCardPositions(visibleEntries) {
    const sides = { left: [], right: [] };
    const cardH = getCardHeight();

    visibleEntries.forEach(entry => {
        const side = entry.sens === 'left' ? 'left' : 'right';
        sides[side].push({
            id: entry.id,
            entry: entry,
            dotY: entry.y,
            cardH: cardH,
            targetCenterY: entry.y
        });
    });

    ['left', 'right'].forEach(sideKey => {
        const list = sides[sideKey];
        if (list.length <= 1) {
            if (list.length === 1) {
                list[0].entry.targetCenterY = list[0].targetCenterY;
                const card = document.getElementById('head_' + list[0].id);
                const underMenu = document.getElementById('Under_menu_' + list[0].id);
                if (card) card.style.top = '-16px';
                if (underMenu) underMenu.style.top = '-16px';
            }
            return;
        }

        list.sort((a, b) => a.targetCenterY - b.targetCenterY);

        const MIN_CARD_GAP = 16;
        for (let pass = 0; pass < 8; pass += 1) {
            let changed = false;
            for (let i = 0; i < list.length - 1; i += 1) {
                const current = list[i];
                const next = list[i + 1];
                const requiredPitch = ((current.cardH + next.cardH) / 2) + MIN_CARD_GAP;
                const diff = next.targetCenterY - current.targetCenterY;
                if (diff < requiredPitch) {
                    const push = (requiredPitch - diff) / 2;
                    current.targetCenterY -= push;
                    next.targetCenterY += push;
                    changed = true;
                }
            }
            if (!changed) break;
        }

        list.forEach(item => {
            item.entry.targetCenterY = item.targetCenterY;
            const offsetY = item.targetCenterY - item.dotY;
            const card = document.getElementById('head_' + item.id);
            const underMenu = document.getElementById('Under_menu_' + item.id);
            const topPx = -16 + offsetY;
            if (card) card.style.top = `${topPx}px`;
            if (underMenu) underMenu.style.top = `${topPx}px`;
        });
    });
}

let positionPinRafId = null;
function schedulePositionPin() {
    if (positionPinRafId) return;
    positionPinRafId = requestAnimationFrame(() => {
        positionPinRafId = null;
        if (Array.isArray(pinElem) && pinElem.length > 0) {
            positionPin(pinElem);
        }
    });
}

function positionPin(pinElem) {
    if (!Array.isArray(pinElem) || pinElem.length === 0) return;

    if (creatorPinsUserHidden) {
        pinElem.forEach(pin => {
            const wrapper = document.getElementById('pin' + pin.id);
            if (wrapper) wrapper.classList.add('hidden');
        });
        return;
    }

    const visibleEntries = [];

    pinElem.forEach(pin => {
        const wrapper = document.getElementById('pin' + pin.id);
        const isVisible = pin.visible !== false
            && typeof pin.startPosition?.x === 'number'
            && typeof pin.startPosition?.y === 'number'
            && Number.isFinite(pin.startPosition.x)
            && Number.isFinite(pin.startPosition.y)
            && pin.startPosition.x >= 0.01 && pin.startPosition.x <= 0.99
            && pin.startPosition.y >= 0.01 && pin.startPosition.y <= 0.99;

        const shouldBeHiddenByMenu = (creatorPinnedMenuId !== null && pin.id !== creatorPinnedMenuId)
            || (activeHoveredPinId !== null && pin.id !== activeHoveredPinId);

        if (!isVisible || shouldBeHiddenByMenu) {
            if (wrapper) wrapper.classList.add('hidden');
            return;
        }

        if (wrapper) wrapper.classList.remove('hidden');
        visibleEntries.push({
            id: pin.id,
            sens: pinActualDirection[pin.id] || pin.direction,
            x: pin.startPosition.x * window.innerWidth,
            y: pin.startPosition.y * window.innerHeight,
        });
    });

    declutterDotPositions(visibleEntries);
    declutterCardPositions(visibleEntries);

    visibleEntries.forEach(entry => {
        updateDotPos(entry.id, entry.x, entry.y, entry.sens, entry.targetCenterY);
    });
}

///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                  LOAD SELECTED CHAR DATA                                          //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////



function formatSelectedNumber(value) {
    const numeric = Number(value);
    if (!Number.isFinite(numeric)) return '0';
    return new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 }).format(numeric);
}

// One authority. This used to answer "Arabic" if ANY of getLocale(), JrsI18n,
// <html lang> or the body class still said so, which let a single lagging
// source hold the dynamic values in Arabic after switching back to English.
// locale-helper's applyLanguage() always runs last on a switch and keeps all
// of those in step, so its locale is the one to trust.
function isSelectedCharUiArabic() {
    if (typeof getLocale === 'function') return getLocale() === 'ar';
    if (typeof JrsI18n !== 'undefined') return JrsI18n.language === 'ar';
    return document.documentElement && document.documentElement.getAttribute('lang') === 'ar';
}

// Job identifiers are plain DB strings ('mining', 'police', ...). Reuse the
// same Arabic labels the base menu already uses for jobs (jrs_core html/locales/ar.js)
// so a job reads the same everywhere instead of falling back to a raw capitalized string.
const SELECTED_CHAR_JOB_LABELS_AR = {
    unemployed: 'عاطـل',
    mining: 'تعدين',
    police: 'شرطة',
    sheriff: 'شريف',
    doctor: 'طبيب',
    medic: 'مسعف',
    blacksmith: 'حداد',
    gunsmith: 'صانع أسلحة',
    hunting: 'صيد',
    hunter: 'صياد',
    farmer: 'مزارع',
    delivery: 'توصيل',
    trainings: 'تدريب',
    offpolice: 'خارج الخدمة',
    offdoctor: 'خارج الخدمة',
    fisherman: 'صياد سمك',
    woodcutter: 'حطاب',
    lumberjack: 'حطاب',
    horse_trainer: 'مدرب خيول',
    stable: 'إسطبل',
};

// Matches server.lua's LAST_LOCATION_POINTS town names to the Arabic names
// already used server-wide (jrs_core locales/ar.lua town_* keys).
const SELECTED_CHAR_LOCATION_LABELS_AR = {
    'Valentine': 'فالنتاين',
    'Saint Denis': 'سان دينيس',
    'Blackwater': 'بلاك ووتر',
    'Rhodes': 'رودس',
    'Strawberry': 'ستروبيري',
    'Armadillo': 'أرماديلو',
    'Tumbleweed': 'تمبلويد',
    'Annesburg': 'آنيسبرغ',
    'Van Horn': 'فان هورن',
    'Emerald Ranch': 'إميرالد رانش',
    'Lagras': 'لاغراس',
    'Wapiti Reservation': 'وابيتي',
    'Colter': 'كولتر',
    'Manzanita Post': 'مانزانيتا',
    "MacFarlane's Ranch": 'ماكفارلين رانش',
    "Thieves' Landing": 'ثيفز لاندينغ',
    'Benedict Point': 'بينديكت بوينت',
    'Wallace Station': 'والاس ستيشن',
    'Riggs Station': 'ريغز ستيشن',
};

function formatSelectedLocation(lastLocation) {
    const isAr = isSelectedCharUiArabic();
    const raw = String(lastLocation || '').trim();
    if (!raw || raw.toLowerCase() === 'unknown') {
        return isAr ? 'غير معروف' : 'Unknown';
    }
    if (isAr && SELECTED_CHAR_LOCATION_LABELS_AR[raw]) {
        return SELECTED_CHAR_LOCATION_LABELS_AR[raw];
    }
    return raw;
}

function formatSelectedJob(job, grade) {
    const isAr = isSelectedCharUiArabic();
    const raw = String(job || (isAr ? 'عاطـل' : 'unemployed')).trim();
    const key = raw.toLowerCase().replace(/[\s-]+/g, '_');
    if (key === 'unemployed') {
        return isAr ? 'عاطـل' : 'Unemployed';
    }
    const readable = isAr && SELECTED_CHAR_JOB_LABELS_AR[key]
        ? SELECTED_CHAR_JOB_LABELS_AR[key]
        : raw.replace(/[_-]+/g, ' ').replace(/\b\w/g, letter => letter.toUpperCase());
    const numericGrade = Number(grade);
    const gradeLabel = isAr ? 'رتبة' : 'Grade';
    return Number.isFinite(numericGrade) && numericGrade > 0
        ? `${readable} · ${gradeLabel} ${numericGrade}`
        : readable;
}

function formatSelectedBirthDate(day, month, year) {
    const isAr = isSelectedCharUiArabic();
    const monthsEn = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    ];
    const monthsAr = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    const months = isAr ? monthsAr : monthsEn;

    const dayNumber = Number(day);
    const yearNumber = Number(year);
    let monthLabel = String(month ?? '').trim();
    const monthNumber = Number(monthLabel);

    if (Number.isFinite(monthNumber) && monthNumber >= 1 && monthNumber <= 12) {
        monthLabel = months[monthNumber - 1];
    } else if (monthLabel) {
        monthLabel = monthLabel.charAt(0).toUpperCase() + monthLabel.slice(1).toLowerCase();
    }

    if (!Number.isFinite(dayNumber) || !Number.isFinite(yearNumber) || !monthLabel) {
        return isAr ? 'غير معروف' : 'Unknown';
    }

    return `${String(dayNumber).padStart(2, '0')} ${monthLabel} ${yearNumber}`;
}

function setSelectedDetail(id, value, fallback = 'Unknown') {
    const element = document.getElementById(id);
    if (!element) return;
    const normalized = value === undefined || value === null || value === '' ? fallback : value;
    element.textContent = normalized;
}

function formatSelectedCharacterCount(currentCharacters, maxCharacters) {
    const current = Number(currentCharacters);
    const maximum = Number(maxCharacters);
    const safeCurrent = Number.isFinite(current) ? Math.max(0, Math.trunc(current)) : 0;

    if (!Number.isFinite(maximum) || maximum <= 0) {
        return String(safeCurrent);
    }

    return `${safeCurrent} / ${Math.max(1, Math.trunc(maximum))}`;
}

function formatSelectedHeight(height, isAr) {
    const h = parseFloat(height);
    if (!Number.isFinite(h) || h <= 0) return isAr ? 'غير معروف' : 'Unknown';
    const fixed = h.toFixed(2);
    if (h >= 1.15) return isAr ? `طويل جداً (${fixed})` : `Very Tall (${fixed})`;
    if (h >= 1.05) return isAr ? `طويل (${fixed})` : `Tall (${fixed})`;
    if (h >= 1.02) return isAr ? `طويل نسبياً (${fixed})` : `Slightly Tall (${fixed})`;
    if (h >= 0.98) return isAr ? `معتدل (${fixed})` : `Average (${fixed})`;
    if (h >= 0.92) return isAr ? `قصير نسبياً (${fixed})` : `Slightly Short (${fixed})`;
    if (h >= 0.82) return isAr ? `قصير (${fixed})` : `Short (${fixed})`;
    return isAr ? `قصير جداً (${fixed})` : `Very Short (${fixed})`;
}

function loadSelectedCharData(charData) {
    const data = charData || {};
    const isAr = isSelectedCharUiArabic();

    const goldUnit = isAr ? 'ذهب' : 'Gold';
    const ageUnit = isAr ? 'سنة' : 'Years';
    const unknownText = isAr ? 'غير معروف' : 'Unknown';
    const unemployedText = isAr ? 'عاطـل' : 'Unemployed';
    const charTitleText = isAr ? 'الشخصية' : 'Character';

    setSelectedDetail('titleSelectedCharactersMenu', data.name, charTitleText);
    setSelectedDetail('SelectedCharacterMoney', `$${formatSelectedNumber(data.money)}`, '$0');
    setSelectedDetail('SelectedCharacterGold', `${formatSelectedNumber(data.gold)} ${goldUnit}`, `0 ${goldUnit}`);
    setSelectedDetail('SelectedCharacterDirtyMoney', `$${formatSelectedNumber(data.dirtymoney)}`, '$0');
    setSelectedDetail(
        'SelectedCharacterCount',
        formatSelectedCharacterCount(data.currentCharacters, data.maxCharacters),
        '0'
    );
    setSelectedDetail('SelectedCharacterJob', formatSelectedJob(data.job, data.grade), unemployedText);
    setSelectedDetail('SelectedCharacterLocation', formatSelectedLocation(data.lastLocation), unknownText);
    setSelectedDetail(
        'SelectedCharacterBirthday',
        formatSelectedBirthDate(data.DayBirth, data.MonthBirth, data.YearBirth),
        unknownText
    );
    const ageValue = Number(data.age);
    setSelectedDetail(
        'SelectedCharacterAge',
        Number.isFinite(ageValue) ? `${Math.max(0, Math.trunc(ageValue))} ${ageUnit}` : unknownText,
        unknownText
    );
    setSelectedDetail(
        'SelectedCharacterHeight',
        formatSelectedHeight(data.height, isAr),
        unknownText
    );

    if (typeof updateTranslations === 'function') {
        const charMenu = document.getElementById('ChooseCharacterMenu');
        if (charMenu) updateTranslations(charMenu);
    }
}


///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                       GET CHAR DATA                                               //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////


function collectCharacterIdentity() {
    const birthDate = getCharacterBirthDateISO();
    let birthYear = '';
    let birthMonth = '';
    let birthDay = '';

    if (/^\d{4}-\d{2}-\d{2}$/.test(birthDate)) {
        const parts = birthDate.split('-');
        birthYear = parts[0];
        birthMonth = String(Number(parts[1]));
        birthDay = String(Number(parts[2]));
    }

    return {
        CharacterName: (document.getElementById('characterName')?.value || '').trim(),
        CharacterSurname: (document.getElementById('characterSurname')?.value || '').trim(),
        CharacterTitle: (document.getElementById('characterTitle')?.value || '').trim(),
        CharacterOccupation: (document.getElementById('characterOccupation')?.value || '').trim(),
        CharacterLore: (document.getElementById('characterLore')?.value || '').trim(),
        CharacterBirthDate: birthDate,
        CharacterBirthDay: birthDay,
        CharacterBirthMonth: birthMonth,
        CharacterBirthYear: birthYear,
        CharacterIsAPed: userPed,
        CharacterSexe: userSexe
    };
}

function setCreatorInputInvalid(id, invalid) {
    const element = document.getElementById(id);
    if (!element) return;
    element.classList.toggle('creator-input-invalid', invalid === true);
}

let CHARACTER_MINIMUM_AGE = 18;

// The world's own date, not the machine's. Red Dead is set in 1899, so a
// character's age is measured from there; bounding the picker with `new Date()`
// is what used to force players to enter a modern birth year. Config.WorldDate
// on the Lua side is the single source of truth and is fetched below - these
// are only the values used until it answers.
let CHARACTER_WORLD_YEAR = 1899;
let CHARACTER_WORLD_MONTH = 6;
let CHARACTER_WORLD_DAY = 1;
let CHARACTER_EARLIEST_BIRTH_YEAR = 1790;

const pad2 = (n) => String(n).padStart(2, '0');

// The server is the authority on this (a modified client could send anything),
// but the dropdowns already only offer years/days within range, and the form
// rejects an out-of-range date immediately instead of only after a server
// round-trip.
function isBirthDateOldEnough(isoDate) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(isoDate || ''));
    if (!match) return false;
    const [, y, m, d] = match.map(Number);
    if (y < CHARACTER_EARLIEST_BIRTH_YEAR) return false;
    let age = CHARACTER_WORLD_YEAR - y;
    if (CHARACTER_WORLD_MONTH < m || (CHARACTER_WORLD_MONTH === m && CHARACTER_WORLD_DAY < d)) age -= 1;
    return age >= CHARACTER_MINIMUM_AGE;
}

// Click-only date of birth (day/month/year). Not a native <select> or
// <input type="date">: in the RedM NUI overlay those open an OS-level popup
// that the game's cursor hook doesn't route clicks into, so the page stops
// responding to anything until the client is restarted. This renders the
// option list as plain DOM inside the page instead.
const birthDateState = { day: null, month: null, year: null };

function getCharacterBirthDateISO() {
    const { day, month, year } = birthDateState;
    if (!day || !month || !year) return '';
    return `${year}-${pad2(month)}-${pad2(day)}`;
}

function setBirthDateInvalid(invalid) {
    ['characterBirthDayButton', 'characterBirthMonthButton', 'characterBirthYearButton'].forEach(id => {
        document.getElementById(id)?.classList.toggle('creator-input-invalid', invalid === true);
    });
}

function daysInBirthMonth(year, month) {
    if (!year || !month) return 31;
    return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

function buildBirthMonthOptions() {
    const isAr = isSelectedCharUiArabic();
    const monthsEn = [
        'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
    ];
    const monthsAr = [
        'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
        'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return (isAr ? monthsAr : monthsEn).map((label, index) => ({ value: index + 1, label }));
}

function buildBirthYearOptions() {
    const min = CHARACTER_EARLIEST_BIRTH_YEAR;
    const max = CHARACTER_WORLD_YEAR - CHARACTER_MINIMUM_AGE;
    const options = [];
    for (let year = max; year >= min; year--) options.push({ value: year, label: String(year) });
    return options;
}

function buildBirthDayOptions() {
    const total = daysInBirthMonth(birthDateState.year, birthDateState.month);
    const options = [];
    for (let day = 1; day <= total; day++) options.push({ value: day, label: pad2(day) });
    return options;
}

function renderDropdownOptions(listEl, options, selectedValue, onSelect) {
    if (!listEl) return;
    listEl.innerHTML = '';
    options.forEach(option => {
        const row = document.createElement('div');
        row.className = 'customDropdownOption';
        row.textContent = option.label;
        if (option.value === selectedValue) row.classList.add('selected');
        row.addEventListener('click', event => {
            event.preventDefault();
            event.stopPropagation();
            onSelect(option.value);
            closeAllBirthDropdowns();
        });
        listEl.appendChild(row);
    });
}

function closeAllBirthDropdowns() {
    document.querySelectorAll('.customDropdownList').forEach(el => el.classList.add('hidden'));
}

function toggleBirthDropdown(listEl) {
    if (!listEl) return;
    const isHidden = listEl.classList.contains('hidden');
    closeAllBirthDropdowns();
    if (isHidden) listEl.classList.remove('hidden');
}

function refreshBirthDropdowns() {
    const dayList = document.getElementById('characterBirthDayList');
    const monthList = document.getElementById('characterBirthMonthList');
    const yearList = document.getElementById('characterBirthYearList');
    const dayButton = document.getElementById('characterBirthDayButton');
    const monthButton = document.getElementById('characterBirthMonthButton');
    const yearButton = document.getElementById('characterBirthYearButton');
    if (!dayList || !monthList || !yearList || !dayButton || !monthButton || !yearButton) return;

    const minYear = CHARACTER_EARLIEST_BIRTH_YEAR;
    const maxYear = CHARACTER_WORLD_YEAR - CHARACTER_MINIMUM_AGE;
    if (birthDateState.year !== null && (birthDateState.year < minYear || birthDateState.year > maxYear)) {
        birthDateState.year = null;
    }

    const monthOptions = buildBirthMonthOptions();
    renderDropdownOptions(monthList, monthOptions, birthDateState.month, value => {
        birthDateState.month = value;
        setBirthDateInvalid(false);
        refreshBirthDropdowns();
    });
    monthButton.textContent = birthDateState.month
        ? (monthOptions.find(option => option.value === birthDateState.month)?.label || '--')
        : '--';

    const yearOptions = buildBirthYearOptions();
    renderDropdownOptions(yearList, yearOptions, birthDateState.year, value => {
        birthDateState.year = value;
        setBirthDateInvalid(false);
        refreshBirthDropdowns();
    });
    yearButton.textContent = birthDateState.year ? String(birthDateState.year) : '----';

    const totalDays = daysInBirthMonth(birthDateState.year, birthDateState.month);
    if (birthDateState.day !== null && birthDateState.day > totalDays) birthDateState.day = null;
    const dayOptions = buildBirthDayOptions();
    renderDropdownOptions(dayList, dayOptions, birthDateState.day, value => {
        birthDateState.day = value;
        setBirthDateInvalid(false);
        dayButton.textContent = pad2(value);
    });
    dayButton.textContent = birthDateState.day ? pad2(birthDateState.day) : '--';
}

function initBirthDateDropdowns() {
    const dayButton = document.getElementById('characterBirthDayButton');
    const monthButton = document.getElementById('characterBirthMonthButton');
    const yearButton = document.getElementById('characterBirthYearButton');
    if (!dayButton || !monthButton || !yearButton) return;

    dayButton.addEventListener('click', event => {
        event.preventDefault();
        event.stopPropagation();
        toggleBirthDropdown(document.getElementById('characterBirthDayList'));
    });
    monthButton.addEventListener('click', event => {
        event.preventDefault();
        event.stopPropagation();
        toggleBirthDropdown(document.getElementById('characterBirthMonthList'));
    });
    yearButton.addEventListener('click', event => {
        event.preventDefault();
        event.stopPropagation();
        toggleBirthDropdown(document.getElementById('characterBirthYearList'));
    });

    document.addEventListener('click', event => {
        if (!event.target.closest('.customDropdown')) closeAllBirthDropdowns();
    });

    refreshBirthDropdowns();
}

document.addEventListener('DOMContentLoaded', () => {
    initBirthDateDropdowns();

    // Ask Lua for the configured world date; keep the defaults above if the
    // callback is unavailable (standalone browser preview, for instance).
    try {
        $.post(`https://${GetParentResourceName()}/getCreatorEra`, JSON.stringify({}), (era) => {
            if (!era || typeof era !== 'object') return;
            if (Number.isFinite(Number(era.year))) CHARACTER_WORLD_YEAR = Number(era.year);
            if (Number.isFinite(Number(era.month))) CHARACTER_WORLD_MONTH = Number(era.month);
            if (Number.isFinite(Number(era.day))) CHARACTER_WORLD_DAY = Number(era.day);
            if (Number.isFinite(Number(era.minimumAge))) CHARACTER_MINIMUM_AGE = Number(era.minimumAge);
            if (Number.isFinite(Number(era.earliestBirthYear))) CHARACTER_EARLIEST_BIRTH_YEAR = Number(era.earliestBirthYear);
            refreshBirthDropdowns();
        });
    } catch (_) { /* preview outside RedM */ }
});

function validateCharacterIdentity(payload) {
    const required = [
        ['characterName', payload.CharacterName],
        ['characterSurname', payload.CharacterSurname]
    ];

    if (globalMenuStructure.CharacterLore === true) {
        required.push(['characterLore', payload.CharacterLore]);
    }

    let valid = true;
    required.forEach(([id, value]) => {
        const missing = String(value || '').trim() === '';
        setCreatorInputInvalid(id, missing);
        if (missing) valid = false;
    });

    const birthDateMissing = String(payload.CharacterBirthDate || '').trim() === '';
    const birthDateMalformed = !birthDateMissing && !/^\d{4}-\d{2}-\d{2}$/.test(payload.CharacterBirthDate);
    const birthDateTooYoung = !birthDateMissing && !birthDateMalformed && !isBirthDateOldEnough(payload.CharacterBirthDate);
    setBirthDateInvalid(birthDateMissing || birthDateMalformed || birthDateTooYoung);
    if (birthDateMissing || birthDateMalformed || birthDateTooYoung) valid = false;

    return valid;
}

function getCharData() {
    const payload = collectCharacterIdentity();

    // Keep the compatibility callback populated for any older creator code that
    // still reads these values later in the flow.
    $.post(`https://${GetParentResourceName()}/CharValues`, JSON.stringify(payload));
    return payload;
}

// Reset all character identity fields.
function resetCharData() {
    const fields = [
        'characterName',
        'characterSurname',
        'characterTitle',
        'characterLore'
    ];

    fields.forEach(id => {
        const element = document.getElementById(id);
        if (!element) return;
        element.value = '';
        element.classList.remove('creator-input-invalid');
    });

    birthDateState.day = null;
    birthDateState.month = null;
    birthDateState.year = null;
    setBirthDateInvalid(false);
    refreshBirthDropdowns();

    userPed = "false";
    loadPedStatus();
    userSexe = "Male";
    loadSexeStatus();
}

function loadPedStatus() {


    const PedVariation = document.getElementById('ped_selector');


    btnSelectPed = document.getElementById('SelectPed');

    if (userPed === "true") {

        btnSelectPed.classList.remove('hidden');

        PedVariation.innerHTML = `

                                    <p class="elemTitle">${JrsI18n.t("charCreation.playAsPedToggle", "Play as a ped")}</p>
                        <div class="sliderDiv">
                            <div class="sliderElemTypeTwo">
                                <a id="left_arrow_ped_selector" class="arrow"><img src="./img/arrow.png"
                                        alt="Arrow left"></a>
                                <p class="sliderValueTypeTwo unselectable" id="sliderValue_ped_selector">${JrsI18n.t("ui.yes", "Yes")}</p>
                                <input type="range" min="0" max="1" value="1" class="hidden"
                                    id="rangeGlobal_ped_selector">
                                <a id="right_arrow_ped_selector" class="arrow"><img src="./img/arrow.png"
                                        alt="Arrow right" style="transform: rotate(180deg);"></a>
                            </div>
                        </div>
        `;

        document.getElementById('right_arrow_ped_selector').addEventListener('click', () => {
            userPed = "false";
            loadPedStatus();
            loadCharCreationInputs();

        });

        document.getElementById('left_arrow_ped_selector').addEventListener('click', () => {
            userPed = "false";
            loadPedStatus();
            loadCharCreationInputs();


        });

        btnSelectPed.addEventListener('click', () => {
            $.post(`https://${GetParentResourceName()}/PedSelection`, JSON.stringify({}));
        });

        creatorPostControl('PedTrueFalse', { userPed });

    } else {

        btnSelectPed.classList.add('hidden');
        PedVariation.innerHTML = `

           <p class="elemTitle">${JrsI18n.t("charCreation.playAsPedToggle", "Play as a ped")}</p>
                        <div class="sliderDiv">
                            <div class="sliderElemTypeTwo">
                                <a id="left_arrow_ped_selector" class="arrow"><img src="./img/arrow.png"
                                        alt="Arrow left"></a>
                                <p class="sliderValueTypeTwo unselectable" id="sliderValue_ped_selector">${JrsI18n.t("ui.no", "No")}</p>
                                <input type="range" min="0" max="1" value="0" class="hidden"
                                    id="rangeGlobal_ped_selector">
                                <a id="right_arrow_ped_selector" class="arrow"><img src="./img/arrow.png"
                                        alt="Arrow right" style="transform: rotate(180deg);"></a>
                            </div>
                        </div>
        `;

        document.getElementById('right_arrow_ped_selector').addEventListener('click', () => {
            userPed = "true";
            loadPedStatus();
            loadCharCreationInputs();

        });

        document.getElementById('left_arrow_ped_selector').addEventListener('click', () => {
            userPed = "true";
            loadPedStatus();
            loadCharCreationInputs();
        });

        creatorPostControl('PedTrueFalse', { userPed });
    }

}


function loadSexeStatus() {


    const SexeVariation = document.getElementById('sexe_selector');

    if (userSexe === "Male") {

        SexeVariation.innerHTML = `

                                    <p class="elemTitle">${JrsI18n.t("charSelect.sexe", "Sex")}</p>
                        <div class="sliderDiv">
                            <div class="sliderElemTypeTwo">
                                <a id="left_arrow_sexe_selector" class="arrow"><img src="./img/arrow.png"
                                        alt="Arrow left"></a>
                                <p class="sliderValueTypeTwo unselectable" id="sliderValue_sexe_selector">${JrsI18n.t("charSelect.male", "Male")}</p>
                                <input type="range" min="0" max="1" value="1" class="hidden"
                                    id="rangeGlobal_sexe_selector">
                                <a id="right_arrow_sexe_selector" class="arrow"><img src="./img/arrow.png"
                                        alt="Arrow right" style="transform: rotate(180deg);"></a>
                            </div>
                        </div>
        `;

        document.getElementById('right_arrow_sexe_selector').addEventListener('click', () => {
            creatorPostControl('sexeStatusChanged', { currentSexe: 'Female' });
        });

        document.getElementById('left_arrow_sexe_selector').addEventListener('click', () => {
            creatorPostControl('sexeStatusChanged', { currentSexe: 'Female' });
        });

    } else {

        SexeVariation.innerHTML = `

           <p class="elemTitle">${JrsI18n.t("charSelect.sexe", "Sex")}</p>
                        <div class="sliderDiv">
                            <div class="sliderElemTypeTwo">
                                <a id="left_arrow_sexe_selector" class="arrow"><img src="./img/arrow.png"
                                        alt="Arrow left"></a>
                                <p class="sliderValueTypeTwo unselectable" id="sliderValue_sexe_selector">${JrsI18n.t("charSelect.female", "Female")}</p>
                                <input type="range" min="0" max="1" value="1" class="hidden"
                                    id="rangeGlobal_sexe_selector">
                                <a id="right_arrow_sexe_selector" class="arrow"><img src="./img/arrow.png"
                                        alt="Arrow right" style="transform: rotate(180deg);"></a>
                            </div>
                        </div>
        `;

        document.getElementById('right_arrow_sexe_selector').addEventListener('click', () => {
            creatorPostControl('sexeStatusChanged', { currentSexe: 'Male' });
        });

        document.getElementById('left_arrow_sexe_selector').addEventListener('click', () => {
            creatorPostControl('sexeStatusChanged', { currentSexe: 'Male' });
        });
    }

}


// Repaint every string this file builds itself. locale-helper's
// applyLanguage() calls window.onLocaleChanged after the static [data-i18n]
// labels are done, on every switch in either direction (language menu,
// /language, a server push), so no JS-built value keeps the previous language
// until its screen happens to be rebuilt. Nothing here posts to Lua:
// loadPedStatus() does (PedTrueFalse), so the ped stepper is relabelled in
// place rather than rebuilt.
function refreshCharacterUiLanguage() {
    // Not gated on the selector being visible: switching language from the
    // creation screen and then pressing Back only unhides the selector, which
    // would otherwise show English labels over Arabic values (or the reverse).
    if (lastSelectedCharData) {
        loadSelectedCharData(lastSelectedCharData);
    }

    loadSexeStatus();
    updateLanguageSwitchLabel();

    const pedTitle = document.querySelector('#ped_selector .elemTitle');
    if (pedTitle) pedTitle.textContent = JrsI18n.t("charCreation.playAsPedToggle", "Play as a ped");
    const pedValue = document.getElementById('sliderValue_ped_selector');
    if (pedValue) pedValue.textContent = userPed === "true" ? JrsI18n.t("ui.yes", "Yes") : JrsI18n.t("ui.no", "No");

    refreshBirthDropdowns();

    document.querySelectorAll('.tone-slider-endpoints').forEach(el => {
        const spans = el.querySelectorAll('span');
        if (spans[0]) spans[0].textContent = JrsI18n.t("character_tone_light", "Light");
        if (spans[1]) spans[1].textContent = JrsI18n.t("character_tone_dark", "Dark");
    });
    const toneWord = JrsI18n.t("character_tone", "Tone");
    document.querySelectorAll('.tone-slider-caption, #sliderValue_app_skin_tone').forEach(el => {
        el.textContent = el.textContent.replace(/^.*?(?=\s*\d+\s*\/\s*\d+\s*$)/, toneWord);
    });

    const backButton = document.getElementById('CancelOutfit');
    const selectedSection = document.getElementById('SelectedOutfitSection');
    if (currentOutfitMode === 'clothing') {
        if (backButton) backButton.textContent = clothingGroupOpen
            ? JrsI18n.t("character_back_to_clothing_areas", "Back to Clothing Areas")
            : JrsI18n.t("character_back", "Back");
        if (selectedSection && !clothingGroupOpen) {
            selectedSection.textContent = JrsI18n.t("character_select_a_clothing_area", "Select a clothing area");
        }
    } else if (currentOutfitMode === 'barber') {
        if (backButton) backButton.textContent = barberGroupOpen
            ? JrsI18n.t("character_back_to_hair_face_areas", "Back to Hair & Face Areas")
            : JrsI18n.t("character_back", "Back");
        if (selectedSection && !barberGroupOpen) {
            selectedSection.textContent = JrsI18n.t("character_select_a_hair_or_face_area", "Select a hair or face area");
        }
    }
}

window.onLocaleChanged = refreshCharacterUiLanguage;


function loadCharCreationInputs() {

    //All containes
    const birthdayContainer = document.getElementById('BirthdayContainer');
    const loreContainer = document.getElementById('characterLore');
    const pedContainer = document.getElementById('ped_selector');
    const pedTitle = document.getElementById('PedTitle');
    const pedSeparator = document.getElementById('PedSeparator');
    const sexeContainer = document.getElementById('sexe_selector');


    //If Character birthday is enabled = ask the user
    if (globalMenuStructure.CharacterBirthday === true) {
        birthdayContainer.classList.remove('hidden');
    } else {

        birthdayContainer.classList.add('hidden');
    }

    //If Character lore is enabled = ask the user
    if (globalMenuStructure.CharacterLore === true) {
        loreContainer.classList.remove('hidden');
    } else {

        loreContainer.classList.add('hidden');
    }

    //If  Play as a ped is enabled = ask the user
    if (globalMenuStructure.playAsAPed === true) {
        pedContainer.classList.remove('hidden');
        pedTitle.classList.remove('hidden');
        pedSeparator.classList.remove('hidden');
    } else {

        pedContainer.classList.add('hidden');
        pedTitle.classList.add('hidden');
        pedSeparator.classList.add('hidden');
    }

    //If Character sexe is enabled = ask the user
    if (globalMenuStructure.CharacterSexe === true) {
        sexeContainer.classList.remove('hidden');
    } else {

        sexeContainer.classList.add('hidden');
    }

}

///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                          LOAD PEDS                                                //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////

currentSelectedPed = 0;

// Load Items
function loadPeds() {
    currentSelectedPed = 0;
    const itemsContainer = document.getElementById('PedListContainer');
    itemsContainer.innerHTML = '';

    pedsList.forEach(item => {


        const itemElem = document.createElement('div');
        itemElem.innerHTML = `
                    <div class="styleElem unselectable" id="item_${item.id}">
                        <p class="elemTitle">${item.name}</p>
                        <div class="sliderDiv">
                            <p class="sliderValue unselectable" id="sliderValue_${item.id}">${JrsI18n.t("character_style", "Style")} ${item.value}</p>
                            <div class="sliderElem">
                                <a id="left_arrow_${item.id}" class="arrow"><img src="./img/arrow.png" alt="Arrow left"></a>
                                <input type="range" min="1" max="${item.totalAmount}" value="${item.value}" class="slider" id="rangeGlobal_${item.id}">
                                <a id="right_arrow_${item.id}" class="arrow"><img src="./img/arrow.png" alt="Arrow right" style="transform: rotate(180deg);"></a>
                            </div>
                        </div>
                    </div>
                `;

        itemsContainer.appendChild(itemElem);

        updateRangeBackground('rangeGlobal_' + item.id);

        itemElem.addEventListener('click', () => {

            if (currentSelectedPed !== item.id) {
                currentSelectedPed = item.id;
                setCreatorStyleSelection(item.id);

                const slider = document.getElementById('rangeGlobal_' + item.id);
                creatorPostControl('pedValue', {
                    id: item.id,
                    item: slider ? slider.value : 1
                });

            }

        });

        document.getElementById('right_arrow_' + item.id).addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            if (currentSelectedPed !== item.id) {
                currentSelectedPed = item.id;
                setCreatorStyleSelection(item.id);
            }
            const slider = document.getElementById('rangeGlobal_' + item.id);
            if (slider.value !== slider.max) {
                slider.value = parseInt(slider.value) + 1;
                document.getElementById('sliderValue_' + item.id).innerText = `${JrsI18n.t("character_style", "Style")} ${slider.value}`;

                updateRangeBackground('rangeGlobal_' + item.id);
            }

            creatorPostControl('pedValue', {
                id: item.id,
                item: slider.value
            });


        });

        document.getElementById('left_arrow_' + item.id).addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            if (currentSelectedPed !== item.id) {
                currentSelectedPed = item.id;
                setCreatorStyleSelection(item.id);
            }
            const slider = document.getElementById('rangeGlobal_' + item.id);
            if (slider.value !== slider.min) {
                slider.value = parseInt(slider.value) - 1;
                document.getElementById('sliderValue_' + item.id).innerText = `${JrsI18n.t("character_style", "Style")} ${slider.value}`;

                updateRangeBackground('rangeGlobal_' + item.id);

            }

            creatorPostControl('pedValue', {
                id: item.id,
                item: slider.value
            });


        });

        // document.getElementById('rangeGlobal_' + item.id).addEventListener('input', () => {
        //     const slider = document.getElementById('rangeGlobal_' + item.id);
        //     document.getElementById('sliderValue_' + item.id).innerText = `${JrsI18n.t("character_style", "Style")} ${slider.value}`;

        //     $.post(`https://${GetParentResourceName()}/itemValue`, JSON.stringify({
        //         category: item.id, menu: item.category,,
        //         item: slider.value
        //     }));
        // });

        const pedRange = document.getElementById('rangeGlobal_' + item.id);
        pedRange.addEventListener('pointerdown', event => {
            event.stopPropagation();
            if (currentSelectedPed !== item.id) {
                currentSelectedPed = item.id;
                setCreatorStyleSelection(item.id);
            }
        });
        pedRange.addEventListener('click', event => event.stopPropagation());

        document.getElementById('rangeGlobal_' + item.id).addEventListener('input', () => {
            const slider = document.getElementById('rangeGlobal_' + item.id);
            document.getElementById('sliderValue_' + item.id).innerText = `${JrsI18n.t("character_style", "Style")} ${slider.value}`;

            updateRangeBackground('rangeGlobal_' + item.id);
            creatorPostControl('pedValue', {
                id: item.id,
                item: slider.value
            });
        });

        document.getElementById('rangeGlobal_' + item.id).addEventListener('change', () => {
            const slider = document.getElementById('rangeGlobal_' + item.id);
            creatorPostControl('pedValue', {
                id: item.id,
                item: slider.value
            });
        });
    });
}

// Search peds
function searchPeds() {
    const searchInput = document.getElementById('searchPed');
    const filter = searchInput.value.toLowerCase();
    const itemsContainer = document.getElementById('PedListContainer');
    const items = itemsContainer.getElementsByClassName('styleElem');

    for (let i = 0; i < items.length; i++) {
        const titleElement = items[i].getElementsByClassName('elemTitle')[0];
        if (titleElement) {
            const txtValue = titleElement.textContent || titleElement.innerText;
            if (txtValue.toLowerCase().indexOf(filter) > -1) {
                items[i].parentElement.style.display = "";
            } else {
                items[i].parentElement.style.display = "none";
            }
        }
    }
}

///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                        LOAD CAMERA                                                //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////

function loadCameraMenu() {

    //NE PAS SUPPRIMER OU REMPLACER JSON LOCAL
    const cameraDatas = [
        {
            "cameraName": 'Z',
            "value": 154
        },
        {
            "cameraName": 'R',
            "value": 180
        }
    ]


    const camContainer = document.querySelector('.CameraList');
    // Clone and replace container to remove all old event listeners
    const newContainer = camContainer.cloneNode(false);
    camContainer.parentNode.replaceChild(newContainer, camContainer);

    cameraDatas.forEach(cam => {


        const camElem = document.createElement('div');
        camElem.classList.add('CamElem');

        camElem.innerHTML = `

                <p class="unselectable">${cam.cameraName}</p>
                <div class="unselectable">

                    <a id="left_arrow_cam_${cam.cameraName}" class="arrow"><img src="./img/arrow.png" alt="Arrow left"></a>
                    <input type="range" value="${cam.value}" min="1" max="360" name="Variation" class="contRange" id="camRange_${cam.cameraName}">
                    <a id="right_arrow_cam_${cam.cameraName}" class="arrow"><img src="./img/arrow.png" alt="Arrow right" style="transform: rotate(180deg);"></a>

                </div>`;

        newContainer.appendChild(camElem);

        document.getElementById('right_arrow_cam_' + cam.cameraName).addEventListener('click', () => {
            const slider = document.getElementById('camRange_' + cam.cameraName);
            if (slider.value !== slider.max) {
                slider.value = parseInt(slider.value) + 1;
            }



            creatorPostControl('cameraChange', {
                cameraName: cam.cameraName,
                value: slider.value
            });
        });

        document.getElementById('left_arrow_cam_' + cam.cameraName).addEventListener('click', () => {
            const slider = document.getElementById('camRange_' + cam.cameraName);
            if (slider.value !== slider.min) {
                const slider = document.getElementById('camRange_' + cam.cameraName);
                if (slider.value !== slider.min) {
                    slider.value = parseInt(slider.value) - 1;
                }
            }

            creatorPostControl('cameraChange', {
                cameraName: cam.cameraName,
                value: slider.value
            });
        });

        document.getElementById('camRange_' + cam.cameraName).addEventListener('input', () => {
            const slider = document.getElementById('camRange_' + cam.cameraName);

            creatorPostControl('cameraChange', {
                cameraName: cam.cameraName,
                value: slider.value
            });
        });

    });

}


///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                        SPAWN MENU                                                 //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////

function escapeSpawnHtml(value) {
    return String(value ?? '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
}

function formatSpawnLabel(template, values) {
    let output = String(template || '');
    values.forEach(value => {
        output = output.replace('%s', String(value));
    });
    return output;
}

// The book's copy is Config.SpawnBook in English, with an optional Arabic twin
// under i18n.ar. A field the translation leaves out still reads in English.
function spawnBookLanguage() {
    if (window.JrsI18n && window.JrsI18n.language) return window.JrsI18n.language;
    return typeof getLocale === 'function' ? getLocale() : 'en';
}

function spawnLocalized(source, field) {
    if (!source) return '';
    const translated = source.i18n && source.i18n[spawnBookLanguage()];
    if (translated && typeof translated[field] === 'string' && translated[field] !== '') {
        return translated[field];
    }
    return source[field] ?? '';
}

function spawnLocalizedCity(location) {
    const out = {};
    ['name', 'tagline', 'description', 'region', 'climate', 'economy', 'danger'].forEach(field => {
        out[field] = spawnLocalized(location, field);
    });
    return out;
}

// Language picker on the book. It is not a second language setting: a click
// goes through chooseLanguage(), the same path as the Character Selection
// overlay, so jrs_core saves it on the account and every resource follows.
function spawnLanguageToggleHtml() {
    const options = (Array.isArray(languageOptions) && languageOptions.length)
        ? languageOptions
        : [{ code: 'en', native: 'English' }, { code: 'ar', native: 'العربية' }];
    const active = spawnBookLanguage();
    const buttons = options.map(entry => `
        <button class="spawn-language-option ${entry.code === active ? 'active' : ''}"
                type="button" data-spawn-language="${escapeSpawnHtml(entry.code)}"
                lang="${escapeSpawnHtml(entry.code)}" aria-pressed="${entry.code === active}">${escapeSpawnHtml(entry.native || entry.label || entry.code)}</button>`).join('');
    return `<div class="spawn-language" role="group" aria-label="${escapeSpawnHtml(t('spawn.language', 'Language'))}">${buttons}</div>`;
}

// Repaint the open book whenever the language changes, whichever screen or
// command changed it.
if (window.JrsI18n && typeof window.JrsI18n.onChange === 'function') {
    window.JrsI18n.onChange(() => {
        const menu = document.getElementById('SpawnMenu');
        if (menu && !menu.classList.contains('hidden')) loadSpawnLocations(false);
    });
}

function setSpawnLocation(index, requestPreview = true) {
    if (!spawnLocationList.length) return;
    actualLocationIndex = (index + spawnLocationList.length) % spawnLocationList.length;
    loadSpawnLocations(requestPreview);
}

function loadSpawnLocations(requestPreview = true) {
    const container = document.getElementById('SpawnMenu');
    if (!container) return;

    if (!spawnLocationList.length) {
        container.innerHTML = `
            <div class="spawn-empty-book">
                <h1>${escapeSpawnHtml(t('spawn.noCitiesTitle', 'No Spawn Cities Enabled'))}</h1>
                <p>${escapeSpawnHtml(t('spawn.noCitiesBody', 'Enable at least one city in Config.SpawnBook.Cities.'))}</p>
            </div>`;
        return;
    }

    if (actualLocationIndex < 0 || actualLocationIndex >= spawnLocationList.length) {
        actualLocationIndex = 0;
    }

    const location = spawnLocationList[actualLocationIndex];
    const pageNumber = actualLocationIndex + 1;
    const totalPages = spawnLocationList.length;
    const cityText = spawnLocalizedCity(location);
    const title = spawnLocalized(spawnBookConfig, 'title') || 'Choose Your Beginning';
    const subtitle = spawnLocalized(spawnBookConfig, 'subtitle');
    const selectText = formatSpawnLabel(spawnLocalized(spawnBookConfig, 'selectLabel') || 'Begin in %s', [cityText.name]);
    const pageText = formatSpawnLabel(spawnLocalized(spawnBookConfig, 'pageLabel') || 'Page %s of %s', [pageNumber, totalPages]);
    const dots = spawnLocationList.map((city, index) => `
        <button class="spawn-page-dot ${index === actualLocationIndex ? 'active' : ''}"
                type="button" data-spawn-index="${index}"
                aria-label="${escapeSpawnHtml(spawnLocalized(city, 'name'))}"></button>`).join('');

    container.innerHTML = `
        <div class="spawn-book-shell">
            <button id="left_arrow_spawn" class="spawn-nav-button spawn-nav-prev" type="button" aria-label="${escapeSpawnHtml(t('spawn.previousCity', 'Previous city'))}">
                <img src="./img/arrow.png" alt="">
            </button>

            <section class="spawn-page spawn-page-left">
                <div class="spawn-city-photo-frame">
                    <img class="spawn-city-photo" src="./${escapeSpawnHtml(location.image)}" alt="${escapeSpawnHtml(cityText.name)}">
                    <div class="spawn-city-photo-vignette"></div>
                </div>
                <div class="spawn-photo-caption">${escapeSpawnHtml(cityText.name)}</div>
                <div class="spawn-photo-region">${escapeSpawnHtml(cityText.region)}</div>
            </section>

            <section class="spawn-page spawn-page-right">
                ${spawnLanguageToggleHtml()}
                <div class="spawn-book-kicker">${escapeSpawnHtml(title)}</div>
                <div class="spawn-book-subtitle">${escapeSpawnHtml(subtitle)}</div>
                <h1 class="spawn-city-title">${escapeSpawnHtml(cityText.name)}</h1>
                <p class="spawn-city-tagline">${escapeSpawnHtml(cityText.tagline || subtitle)}</p>
                <div class="spawn-rule"></div>
                <p class="spawn-city-description">${escapeSpawnHtml(cityText.description)}</p>

                <div class="spawn-city-facts">
                    <div class="spawn-fact">
                        <span class="spawn-fact-label">${escapeSpawnHtml(t('spawn.region', 'Region'))}</span>
                        <span class="spawn-fact-value">${escapeSpawnHtml(cityText.region)}</span>
                    </div>
                    <div class="spawn-fact">
                        <span class="spawn-fact-label">${escapeSpawnHtml(t('spawn.climate', 'Climate'))}</span>
                        <span class="spawn-fact-value">${escapeSpawnHtml(cityText.climate)}</span>
                    </div>
                    <div class="spawn-fact">
                        <span class="spawn-fact-label">${escapeSpawnHtml(t('spawn.economy', 'Economy'))}</span>
                        <span class="spawn-fact-value">${escapeSpawnHtml(cityText.economy)}</span>
                    </div>
                    <div class="spawn-fact">
                        <span class="spawn-fact-label">${escapeSpawnHtml(t('spawn.danger', 'Danger'))}</span>
                        <span class="spawn-fact-value">${escapeSpawnHtml(cityText.danger)}</span>
                    </div>
                </div>

                <div class="spawn-book-actions">
                    <button id="spawnBackButton" class="spawn-back-button" type="button">${escapeSpawnHtml(t('ui.back', 'Back'))}</button>
                    <span class="spawn-page-number">${escapeSpawnHtml(pageText)}</span>
                    <button id="spawnCharacter" class="spawn-select-button" type="button">${escapeSpawnHtml(selectText)}</button>
                </div>
            </section>

            <button id="right_arrow_spawn" class="spawn-nav-button spawn-nav-next" type="button" aria-label="${escapeSpawnHtml(t('spawn.nextCity', 'Next city'))}">
                <img src="./img/arrow.png" alt="">
            </button>

            <div class="spawn-page-dots">${dots}</div>
        </div>`;

    const payload = {
        SpawnLocationId: location.id,
        SpawnLocationKey: location.key,
        SpawnLocationName: location.name,
    };

    if (requestPreview && spawnBookConfig.previewWorld === true) {
        creatorPostControl('spawnPreview', payload);
    }

    document.getElementById('spawnCharacter')?.addEventListener('click', event => {
        event.preventDefault();
        const button = event.currentTarget;
        creatorPostAction(button, 'spawnCharacter', payload);
    });

    container.querySelectorAll('[data-spawn-language]').forEach(option => {
        option.addEventListener('click', event => {
            event.preventDefault();
            const code = option.dataset.spawnLanguage;
            if (code && code !== spawnBookLanguage()) chooseLanguage(code);
        });
    });

    document.getElementById('spawnBackButton')?.addEventListener('click', event => {
        event.preventDefault();
        const button = event.currentTarget;
        creatorPostAction(button, 'BackToApparenceFromSpawn', {});
    });

    document.getElementById('right_arrow_spawn')?.addEventListener('click', () => {
        setSpawnLocation(actualLocationIndex + 1, true);
    });

    document.getElementById('left_arrow_spawn')?.addEventListener('click', () => {
        setSpawnLocation(actualLocationIndex - 1, true);
    });

    container.querySelectorAll('[data-spawn-index]').forEach(dot => {
        dot.addEventListener('click', () => {
            const index = Number(dot.dataset.spawnIndex);
            if (Number.isInteger(index)) setSpawnLocation(index, true);
        });
    });
}


document.addEventListener('keydown', event => {
    const menu = document.getElementById('SpawnMenu');
    if (!menu || menu.classList.contains('hidden')) return;

    if (event.key === 'ArrowRight' || event.key.toLowerCase() === 'd') {
        event.preventDefault();
        setSpawnLocation(actualLocationIndex + 1, true);
    } else if (event.key === 'ArrowLeft' || event.key.toLowerCase() === 'a') {
        event.preventDefault();
        setSpawnLocation(actualLocationIndex - 1, true);
    } else if (event.key === 'Enter') {
        event.preventDefault();
        document.getElementById('spawnCharacter')?.click();
    }
});


///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                         DOM                                                       //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////

document.addEventListener('DOMContentLoaded', function () {

    // Do this before any optional UI binding. Even if a later optional element
    // is missing, Lua still learns that the Chromium document itself is ready.
    announceCharacterNuiReady(0);

    bindCreatorViewControls();
    syncCreatorViewControls();
    const creatorVisibilityTargets = new Set([
        'BodyPartsMenu', 'CharactersMenu', 'GlobalCharacterMenu', 'EditionMenu', 'PedSelectionMenu',
        'OutfitMenu', 'VariationSettings', 'TintSettings', 'CameraSettings'
    ]);
    // Pin visibility changes every render tick. Observing those (and the
    // controls we modify ourselves) repeatedly forced layout and re-synced UI.
    const creatorVisibilityObserver = new MutationObserver(records => {
        if (records.some(record => creatorVisibilityTargets.has(record.target.id))) {
            scheduleCreatorViewControlsSync();
        }
    });
    creatorVisibilityObserver.observe(document.body, { subtree: true, attributes: true, attributeFilter: ['class'] });
    loadPedStatus();
    loadSexeStatus();
    loadCharCreationInputs();

    ['characterName', 'characterSurname', 'characterTitle', 'characterLore']
        .forEach(id => {
            const input = document.getElementById(id);
            input?.addEventListener('input', () => input.classList.remove('creator-input-invalid'));
            input?.addEventListener('change', () => input.classList.remove('creator-input-invalid'));
        });

    ////////////////////////// SEARCH FUNCTIONALITY //////////////////////////
    const searchPedInput = document.getElementById('searchPed');
    if (searchPedInput) {
        searchPedInput.addEventListener('input', searchPeds);
    }

    ////////////////////////// CANCEL APPARENCE EDITION //////////////////////////
    CancelApparenceEdition = document.getElementById('CancelApparenceEdition');
    if (CancelApparenceEdition) {
        CancelApparenceEdition.addEventListener('click', () => {
            if (document.getElementById('SaveSecondChance')?.dataset.creatorBusy === '1') return;
            creatorPostAction(CancelApparenceEdition, 'CancelApparenceEdition', {
                secondChanceMode: isSecondChanceMode
            }, response => {
                if (response?.ok === true) isSecondChanceMode = false;
            });
        });
    }

    ////////////////////////// SAVE SECOND CHANCE //////////////////////////
    const saveSecondChanceBtn = document.getElementById('SaveSecondChance');
    if (saveSecondChanceBtn) {
        const saveStatus = document.createElement('p');
        saveStatus.id = 'creatorSaveStatus';
        saveStatus.setAttribute('role', 'status');
        saveStatus.style.cssText = 'color:#f2c6a0;white-space:normal;font-size:14px;max-width:340px;';
        saveSecondChanceBtn.insertAdjacentElement('afterend', saveStatus);
        saveSecondChanceBtn.addEventListener('click', () => {
            if (saveSecondChanceBtn.dataset.creatorBusy === '1') return;
            saveStatus.textContent = t('appearance.saving', 'Saving appearance…');
            const request = creatorPostAction(saveSecondChanceBtn, 'SaveSecondChance', {}, response => {
                if (response?.ok === true) {
                    isSecondChanceMode = false;
                    saveStatus.textContent = '';
                } else {
                    saveStatus.textContent = response?.reason === 'session_expired'
                        ? t('appearance.sessionExpired', 'Editing session expired. Reopen the editor to save.')
                        : t('appearance.saveFailed', 'Could not confirm the save. Your editor remains open; please try again.');
                }
            });
            request?.fail(() => {
                saveStatus.textContent = t('appearance.saveFailed', 'Could not confirm the save. Your editor remains open; please try again.');
            });
        });
    }

    ////////////////////////// UNDRESS APPARENCE EDITION //////////////////////////
    const UndressApparenceEdition = document.getElementById('UndressApparenceEdition');
    if (UndressApparenceEdition) {
        UndressApparenceEdition.addEventListener('click', () => {
            hidePedListMenu();
            $.post(`https://${GetParentResourceName()}/UndressApparenceEdition`, JSON.stringify({}));
        });
    }

    setActionButtonContent(document.getElementById('CancelApparenceEdition'), t('ui.back', 'Back'), '↩');
    setActionButtonContent(document.getElementById('ResetApparenceEdition'), t('ui.reset', 'Reset'), '↻');
    setActionButtonContent(document.getElementById('ContinueCreator'), t('character_next', 'Next'), '➜', true);

    ////////////////////////// RESET APPARENCE EDITION //////////////////////////
    const resetAppearanceButton = document.getElementById('ResetApparenceEdition');
    resetAppearanceButton?.addEventListener('click', () => {

        document.getElementById('DeletionConfirmation')?.classList.remove('hidden');

        document.getElementById('DeletionConfirmation').innerHTML = `

                <div id = "DeletionConfirmationElem" >

                <div id = "DeletionConfirmationContent" >

                <div id="DeletionConfirmationTitle">

                    <h1 data-i18n="charSelect.deleteWarning">${t('charSelect.deleteWarning', 'Warning!')}</h1>
                    <p data-i18n="charCreation.resetWarning">${t('charCreation.resetWarning', 'Are you sure you want to cancel the procedure?')}</p>

                </div>

                <div id="DeletionConfirmationInteraction">

                    <a id="cancelResetChanges" class="button_del" data-i18n="ui.cancel">${t('ui.cancel', 'Cancel')}</a>
                    <a id="confirmResetChanges" class="button_del" data-i18n="ui.reset">${t('ui.reset', 'Reset')}</a>

                </div>

                </div>

                </div>
        `;

        //Accept Deletion
        document.getElementById('confirmResetChanges').addEventListener('click', () => {
            $.post(`https://${GetParentResourceName()}/resetApparenceEdition`, JSON.stringify({}));
            document.getElementById('DeletionConfirmation').classList.add('hidden');
        });

        //Cancel Deletion
        document.getElementById('cancelResetChanges').addEventListener('click', () => {
            document.getElementById('DeletionConfirmation').classList.add('hidden');
        });

    });

    ////////////////////////// CANCEL CHARACTER EDITION //////////////////////////
    document.getElementById('CancelCharEdition').addEventListener('click', () => {

        $.post(`https://${GetParentResourceName()}/cancelCharEdition`, JSON.stringify({}));

    });

    ////////////////////////// CANCEL CHARACTER EDITION //////////////////////////
    document.getElementById('CancelCharCreation').addEventListener('click', () => {

        document.getElementById('DeletionConfirmation').classList.remove('hidden');

        document.getElementById('DeletionConfirmation').innerHTML = `

                <div id = "DeletionConfirmationElem" >

                <div id = "DeletionConfirmationContent" >

                <div id="DeletionConfirmationTitle">

                    <h1 data-i18n="charSelect.deleteWarning">${t('charSelect.deleteWarning', 'Warning!')}</h1>
                    <p data-i18n="charCreation.cancelWarning">${t('charCreation.cancelWarning', 'You will lose all changes. Are you sure?')}</p>

                </div>

                <div id="DeletionConfirmationInteraction">

                    <a id="cancelStopCreation" class="button_del" data-i18n="ui.cancel">${t('ui.cancel', 'Cancel')}</a>
                    <a id="confirmStopCreation" class="button_del" data-i18n="ui.confirm">${t('ui.confirm', 'Confirm')}</a>

                </div>

                </div>

                </div>
        `;

        //Accept Deletion
        document.getElementById('confirmStopCreation').addEventListener('click', () => {
            resetCharData();
            hideCharGlobalMenu();
            $.post(`https://${GetParentResourceName()}/cancelCharCreation`, JSON.stringify({}));
            document.getElementById('DeletionConfirmation').classList.add('hidden');
        });

        //Cancel Deletion
        document.getElementById('cancelStopCreation').addEventListener('click', () => {
            document.getElementById('DeletionConfirmation').classList.add('hidden');
        });

    });


    ////////////////////////// IDENTITY -> APPEARANCE //////////////////////////
    const nextChar = document.getElementById('NextChar');
    if (nextChar) {
        nextChar.addEventListener('click', event => {
            event.preventDefault();
            const payload = getCharData();
            if (!validateCharacterIdentity(payload)) return;

            creatorPostAction(nextChar, 'NextChar', payload, response => {
                let result = response;
                if (typeof result === 'string') {
                    try { result = JSON.parse(result); } catch (_) { result = {}; }
                }
                if (result && result.ok === false && result.field) {
                    setCreatorInputInvalid(result.field, true);
                }
            });
        });
    }

    ////////////////////////// APPEARANCE -> SPAWN //////////////////////////
    const continueCreator = document.getElementById('ContinueCreator');
    if (continueCreator) {
        continueCreator.addEventListener('click', event => {
            event.preventDefault();
            creatorPostAction(continueCreator, 'ContinueCreator', {});
        });
    }

    ////////////////////////// CANCEL PED SELECTION //////////////////////////
    cancelCharCreation = document.getElementById('CancelPedSelection');
    cancelCharCreation.addEventListener('click', () => {
        hidePedListMenu();
        $.post(`https://${GetParentResourceName()}/cancelPedSelection`, JSON.stringify({}));
    });


    ////////////////////////// CREATE NEW CHARACTER FROM SELECTOR //////////////////////////
    const createCharacterFromSelector = document.getElementById('CreateCharacterFromSelector');
    if (createCharacterFromSelector) {
        createCharacterFromSelector.addEventListener('click', () => {
            setCreateCharacterSelectorAction(false);
            creatorPostAction(createCharacterFromSelector, 'createNewChar', {});
        });
    }

    ////////////////////////// PLAY SELECTED CHAR //////////////////////////
    PlaySelectedChar = document.getElementById('PlaySelectedChar');
    PlaySelectedChar.addEventListener('click', event => {
        event.preventDefault();
        hidePedListMenu();
        creatorPostAction(PlaySelectedChar, 'PlaySelectedChar', {});
    });

    ////////////////////////// LANGUAGE SELECTED CHAR //////////////////////////
    const languageSelectedChar = document.getElementById('LanguageSelectedChar');
    if (languageSelectedChar) {
        languageSelectedChar.addEventListener('click', event => {
            event.preventDefault();
            showLanguageMenu(false);
        });
    }

    ////////////////////////// DELETE SELECTED CHAR //////////////////////////
    document.getElementById('DeleteSelectedChar').addEventListener('click', () => {

        document.getElementById('DeletionConfirmation').classList.remove('hidden');

        document.getElementById('DeletionConfirmation').innerHTML = `

                <div id = "DeletionConfirmationElem" >

                <div id = "DeletionConfirmationContent" >

                <div id="DeletionConfirmationTitle">

                    <h1 data-i18n="charSelect.deleteWarning">${t('charSelect.deleteWarning', 'Warning!')}</h1>
                    <p data-i18n="charSelect.deleteMessage">${t('charSelect.deleteMessage', 'Are you sure you want to delete this character?')}</p>

                </div>

                <div id="DeletionConfirmationInteraction">

                    <a id="cancelCharDeletion" class="button_del" data-i18n="charSelect.cancelDeletion">${t('charSelect.cancelDeletion', 'Cancel')}</a>
                    <a id="confirmCharDeletion" class="button_del" data-i18n="charSelect.confirmDeletion">${t('charSelect.confirmDeletion', 'Delete')}</a>

                </div>

                </div>

                </div>
        `;

        //Accept Deletion
        document.getElementById('confirmCharDeletion').addEventListener('click', () => {
            hidePedListMenu();
            $.post(`https://${GetParentResourceName()}/DeleteSelectedChar`, JSON.stringify({}));
            document.getElementById('DeletionConfirmation').classList.add('hidden');
        });

        //Cancel Deletion
        document.getElementById('cancelCharDeletion').addEventListener('click', () => {
            document.getElementById('DeletionConfirmation').classList.add('hidden');
        });

    });

    ////////////////////////// DELETE SELECTED CHAR //////////////////////////
    CancelSelectedChar = document.getElementById('CancelSelectedChar');
    CancelSelectedChar.addEventListener('click', () => {
        hidePedListMenu();
        $.post(`https://${GetParentResourceName()}/CancelSelectedChar`, JSON.stringify({}));
    });

    document.getElementById('CancelOutfit').addEventListener('click', () => {
        if (currentOutfitMode === 'clothing' && clothingGroupOpen) {
            returnToClothingBodyAreas();
            return;
        }
        if (currentOutfitMode === 'barber' && barberGroupOpen) {
            returnToBarberBodyAreas();
            return;
        }
        $.post(`https://${GetParentResourceName()}/backToOutfitList`);
    });
});

window.addEventListener('load', () => announceCharacterNuiReady(0), { once: true });

////////////////////////// MATRICE POSITION //////////////////////////


function loadMatricePosition(Matrice, startX, startY, itemName, itemId, XHashes, YHashes) {
    const repere = document.getElementById('repere_' + itemId + '_' + Matrice);
    const selecteur = document.getElementById('selecteur_' + itemId + '_' + Matrice);
    const coordonnees = document.getElementById('coordonnees_' + itemId + '_' + Matrice);


    // const repereRect = repere.getBoundingClientRect();
    // const largeurRect = repereRect.width;
    // const hauteurRect = repereRect.height;

    // selecteur.style.left = centreX + 'px';
    // selecteur.style.top = centreY + 'px';


    actualPostionX = startX * 135;
    actualPostionY = startY * 135;

    creatorDebugLog(actualPostionX, actualPostionY);
    deplacerPoint(actualPostionX, actualPostionY);



    let isDragging = false;

    function deplacerPoint(x, y) {

        x = Math.max(0, Math.min(135, x));
        y = Math.max(0, Math.min(135, y));

        selecteur.style.left = x + 'px';
        selecteur.style.top = y + 'px';

        actualPostionX = x;
        actualPostionY = y;
        coordonnees.textContent = `${JrsI18n.t("character_position", "Position")}: X=${Math.round(x)}, Y=${Math.round(y)}`;


    }

    repere.addEventListener('click', function (e) {
        if (e.target === selecteur) return;

        const rect = repere.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;

        deplacerPoint(x, y);

        creatorDebugLog(actualPostionX / repere.offsetWidth, actualPostionY / repere.offsetHeight);

        creatorPostControl('matriceElem', {
            item: itemName,
            matriceId: Matrice,
            X: actualPostionX / repere.offsetWidth,
            Y: actualPostionY / repere.offsetHeight,
            XHashes: XHashes,
            YHashes: YHashes
        });
    });

    selecteur.addEventListener('mousedown', function (e) {
        isDragging = true;
        e.preventDefault();
        selecteur.style.cursor = 'grabbing';
        e.stopPropagation();
    });

    document.addEventListener('mousemove', function (e) {
        if (!isDragging) return;

        const rect = repere.getBoundingClientRect();
        const x = e.clientX - rect.left;
        const y = e.clientY - rect.top;

        deplacerPoint(x, y);

        creatorPostControl('matriceElem', {
            item: itemName,
            matriceId: Matrice,
            X: actualPostionX / repere.offsetWidth,
            Y: actualPostionY / repere.offsetHeight,
            XHashes: XHashes,
            YHashes: YHashes
        });
    });

    document.addEventListener('mouseup', function () {
        if (isDragging) {
            isDragging = false;
            selecteur.style.cursor = 'grab';

            //creatorDebugLog(actualPostionX / repere.offsetWidth, actualPostionY / repere.offsetHeight);


        }


    });

    document.addEventListener('mouseleave', function () {
        if (isDragging) {
            isDragging = false;
            selecteur.style.cursor = 'grab';
        }
    });
}


///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                        MESSAGES                                                   //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////

function notifyCharacterPresentationReady(mode, token) {
    const numericToken = Number(token);
    if (!Number.isFinite(numericToken) || numericToken <= 0) return;

    const payload = {
        mode: String(mode || ''),
        token: numericToken
    };

    const postReady = (attempt = 0) => {
        let request;
        try {
            request = creatorPost('characterPresentationReady', payload);
        } catch (_) {
            if (attempt < 5) window.setTimeout(() => postReady(attempt + 1), 250);
            return;
        }
        if (request && typeof request.fail === 'function' && attempt < 5) {
            request.fail(() => window.setTimeout(() => postReady(attempt + 1), 250));
        }
    };

    // Two animation frames guarantee that class changes/pin creation have had
    // an opportunity to paint before the RedM loading overlay is removed.
    requestAnimationFrame(() => {
        requestAnimationFrame(() => {
            window.setTimeout(() => postReady(0), 50);
        });
    });
}


let loadingScreenSkipInterval = null;
let loadingScreenSkipDeadline = 0;

function setSelectorLoadingHold(enabled) {
    const menu = document.getElementById('SelectCharMenu');
    if (!menu) return;
    menu.classList.toggle('jrs-loading-hold', enabled === true);
}

function hideLoadingScreenSkipOverlay(releaseSelector = false) {
    if (loadingScreenSkipInterval) {
        window.clearInterval(loadingScreenSkipInterval);
        loadingScreenSkipInterval = null;
    }
    loadingScreenSkipDeadline = 0;

    const overlay = document.getElementById('LoadingScreenSkipOverlay');
    const button = document.getElementById('LoadingScreenSkipButton');
    if (overlay) {
        overlay.classList.add('hidden');
        overlay.setAttribute('aria-hidden', 'true');
    }
    if (button) button.disabled = false;
    if (releaseSelector) setSelectorLoadingHold(false);
}

function showLoadingScreenSkipOverlay(label, seconds) {
    const overlay = document.getElementById('LoadingScreenSkipOverlay');
    const button = document.getElementById('LoadingScreenSkipButton');
    const timer = document.getElementById('LoadingScreenSkipTimer');
    if (!overlay || !button) return;

    const safeSeconds = Math.max(1, Number(seconds) || 60);
    const safeLabel = String(label || 'SKIP').trim() || 'SKIP';

    setSelectorLoadingHold(true);
    button.textContent = safeLabel;
    button.disabled = false;
    overlay.classList.remove('hidden');
    overlay.setAttribute('aria-hidden', 'false');

    loadingScreenSkipDeadline = Date.now() + (safeSeconds * 1000);
    const refreshTimer = () => {
        if (!timer) return;
        const remaining = Math.max(0, Math.ceil((loadingScreenSkipDeadline - Date.now()) / 1000));
        timer.textContent = JrsI18n.f("character_auto_continue_in", remaining);
    };

    if (loadingScreenSkipInterval) window.clearInterval(loadingScreenSkipInterval);
    refreshTimer();
    loadingScreenSkipInterval = window.setInterval(refreshTimer, 250);
}

function bindLoadingScreenSkipButton() {
    const button = document.getElementById('LoadingScreenSkipButton');
    if (!button || button.dataset.bound === '1') return;
    button.dataset.bound = '1';

    button.addEventListener('click', event => {
        event.preventDefault();
        event.stopPropagation();
        if (button.disabled) return;

        button.disabled = true;
        let request;
        try {
            request = creatorPost('characterSkipLoading', {});
        } catch (_) {
            button.disabled = false;
            return;
        }

        if (request && typeof request.fail === 'function') {
            request.fail(() => { button.disabled = false; });
        }
    });
}


// While Character Selection is intentionally held behind jrs_loadingscreen,
// jrs_character owns CEF focus so the SKIP button can be clicked. CEF focus is
// global, so clicks would otherwise stop reaching the loading-screen buttons.
// Forward every click outside SKIP back to the loading screen using normalized
// screen coordinates. This keeps TEAM/HINTS/NEWS/RULES/social/music controls
// interactive for the entire loading period.
let loadingScreenProxyBound = false;

function isLoadingScreenSkipVisible() {
    const overlay = document.getElementById('LoadingScreenSkipOverlay');
    return !!overlay && !overlay.classList.contains('hidden');
}

function bindLoadingScreenInteractionProxy() {
    if (loadingScreenProxyBound) return;
    loadingScreenProxyBound = true;

    document.addEventListener('click', event => {
        if (!isLoadingScreenSkipVisible()) return;

        const skipButton = document.getElementById('LoadingScreenSkipButton');
        if (skipButton && (event.target === skipButton || skipButton.contains(event.target))) {
            return;
        }

        const width = Math.max(1, window.innerWidth || document.documentElement.clientWidth || 1);
        const height = Math.max(1, window.innerHeight || document.documentElement.clientHeight || 1);
        const x = Math.min(1, Math.max(0, Number(event.clientX || 0) / width));
        const y = Math.min(1, Math.max(0, Number(event.clientY || 0) / height));

        // Do not let the click fall through to hidden Character Selection
        // controls while the external loading screen is still covering them.
        event.preventDefault();
        event.stopImmediatePropagation();

        try {
            creatorPost('loadingScreenProxyPointer', {
                action: 'click',
                x,
                y,
                button: Number(event.button || 0),
            });
        } catch (_) {
            // Never block the character UI if the loading resource is stopping.
        }
    }, true);
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
        bindLoadingScreenSkipButton();
        bindLoadingScreenInteractionProxy();
    }, { once: true });
} else {
    bindLoadingScreenSkipButton();
    bindLoadingScreenInteractionProxy();
}

window.addEventListener('message', (event) => {

    if (event.data.type === 'placeElem') {
        pinElem = event.data.pins;
        showBodyPartsMenu();
        createPin(pinElem);
    } else if (event.data.type === 'updateElem') {
        const newPins = event.data.pins;
        if (Array.isArray(newPins)) {
            if (Array.isArray(pinElem) && pinElem.length > 0) {
                newPins.forEach(newP => {
                    const existing = pinElem.find(p => p.id === newP.id);
                    if (existing) {
                        existing.visible = newP.visible;
                        if (newP.startPosition) existing.startPosition = newP.startPosition;
                        if (newP.direction) existing.direction = newP.direction;
                    }
                });
            } else {
                pinElem = newPins;
            }
            schedulePositionPin();
        }
    }

    if (event.data.type === 'openSelectCharMenu') {
        pinPerso = Array.isArray(event.data.pinsSelectChar) ? event.data.pinsSelectChar : [];
        const holdForLoadingScreen = event.data.loadingHold === true;
        try {
            showCharSelectMenu();
            setSelectorLoadingHold(holdForLoadingScreen);
            if (holdForLoadingScreen) {
                setTimeout(() => {
                    setSelectorLoadingHold(false);
                    hideLoadingScreenSkipOverlay(true);
                }, 2000);
            }
            createPinSelection(pinPerso);
            setCreateCharacterSelectorAction(
                event.data.canCreate === true,
                event.data.currentCharacters,
                event.data.maxCharacters
            );
        } catch (error) {
            console.error('[jrs_character] selector presentation error:', error);
            document.getElementById('SelectCharMenu')?.classList.remove('hidden');
        }
        notifyCharacterPresentationReady('selector', event.data.loadingToken);
        requestAnimationFrame(() => requestCharacterFocusRecovery('selector-presented'));
    } else if (event.data.type === 'updateElemSelectCharMenu') {
        pinPerso = Array.isArray(event.data.pinsSelectChar) ? event.data.pinsSelectChar : [];
        createPinSelection(pinPerso);
    }

    if (event.data.type === 'hideSelectCharMenu') {
        hideCharSelectMenu();
        setCreateCharacterSelectorAction(false);
    }

    if (event.data.type === 'hideBodyPartsMenu') {
        hideBodyPartsMenu();
        const pinContainer = document.getElementById('pinContainer');
        pinContainer.innerHTML = '';
    }


    if (event.data.type === 'showEditionMenu') {
        EditionElem = event.data.edition;
        showElementEditionMenu()
    } else if (event.data.type === 'hideEditionMenu') {
        hideElementEditionMenu();
    }

    if (event.data.type === 'showCharGlobalMenu') {
        // Check if this is Second Chance mode
        if (event.data.secondChanceMode) {
            isSecondChanceMode = true;
        } else {
            isSecondChanceMode = false;
        }
        try {
            showCharGlobalMenu();
            if (event.data.charInputs) {
                globalMenuStructure = event.data.charInputs;
            }
        } catch (error) {
            console.error('[jrs_character] creator presentation error:', error);
            document.getElementById('CharactersMenu')?.classList.remove('hidden');
        }
        notifyCharacterPresentationReady('creator', event.data.loadingToken);
        requestAnimationFrame(() => requestCharacterFocusRecovery('creator-presented'));
    }
    
    if (event.data.type === 'showLoadingScreenSkip') {
        showLoadingScreenSkipOverlay(event.data.label, event.data.seconds);
    } else if (event.data.type === 'hideLoadingScreenSkip') {
        hideLoadingScreenSkipOverlay(event.data.releaseSelector === true);
    }

    // Second Chance: Set the flag, the apparence menu will be opened by openEditApparenceMenu
    if (event.data.type === 'showSecondChanceMenu') {
        creatorDebugLog("[SecondChance] Received showSecondChanceMenu message");
        isSecondChanceMode = true;
        creatorDebugLog("[SecondChance] isSecondChanceMode set to:", isSecondChanceMode);
        // showApparenceMenu() will be called by openEditApparenceMenu
    }
    else if (event.data.type === 'hideCharGlobalMenu') {
        hideCharGlobalMenu();
    }
    if (event.data.type === 'changeuserSexe') {
        userSexe = event.data.userSexe;
        loadSexeStatus();
    }
    //Get all character data
    if (event.data.type === 'getAllCharDatas') {
        getCharData();
    }

    //Reset all character data
    if (event.data.type === 'resetCharData') {
        resetCharData();
    }

    //Peds list Menu
    if (event.data.type === 'showPedsList') {
        pedsList = event.data.pedsList;
        showPedListMenu();
    }
    else if (event.data.type === 'hidePedsList') {
        hidePedListMenu();
    }

    // Open Outfit Menu
    if (event.data.type === "openOutfitMenu") {
        creatorDebugLog("Activer le menu outfit")
        currentOutfitMode = event.data.mode || null;
        const outfitTitle = document.getElementById('OutfitMenuTitle');
        if (outfitTitle) {
            outfitTitle.textContent = event.data.title || (event.data.mode === 'clothing' ? JrsI18n.t("character_outfit_title_clothing", "CLOTHING") : JrsI18n.t("character_outfit_title_barber", "HAIR & BARBER"));
        }
        if (event.data.categories) {
            categories = event.data.categories;
        }

        // if (event.data.menu == "wearable") {
        //     this.document.getElementById('CreateOutfit').classList.add('cache');
        // }
        // else {
        //     this.document.getElementById('CreateOutfit').classList.remove('cache');
        // }

        outfitElemId = event.data.outfitId;

        if (event.data.menu == "modify") {
            menuType = "modify";
        }
        else {
            menuType = "default";
        }

        if (event.data.items) {
            items = event.data.items;
        }
        showOutfitMenu();

    }

    if (event.data.type === "updateClothingPins") {
        clothingPinData = Array.isArray(event.data.pins) ? event.data.pins : [];
        renderClothingBodyPins(clothingPinData);
    }

    if (event.data.type === "hideClothingPins") {
        clothingPinData = [];
        const clothingPins = document.getElementById('clothingPinContainer');
        if (clothingPins) clothingPins.innerHTML = '';
        const clothingBodySelector = document.getElementById('ClothingBodySelector');
        if (clothingBodySelector) clothingBodySelector.classList.add('hidden');
    }

    if (event.data.type === "updateBarberPins") {
        barberPinData = Array.isArray(event.data.pins) ? event.data.pins : [];
        renderBarberBodyPins(barberPinData);
    }

    if (event.data.type === "hideBarberPins") {
        barberPinData = [];
        const barberPins = document.getElementById('barberPinContainer');
        if (barberPins) barberPins.innerHTML = '';
        const barberBodySelector = document.getElementById('BarberBodySelector');
        if (barberBodySelector) barberBodySelector.classList.add('hidden');
    }

    // Close Outfit Menu
    if (event.data.type === "closeOutfitMenu") {
        creatorDebugLog("Fermer le menu outfit");
        // hideOutfitMenu already clears the integrated clothing/barber lists,
        // body pins, contextual controls and menu state. The old standalone
        // outfit-list function no longer exists in the integrated creator.
        hideOutfitMenu();
    }

    // Open Edit apparence Menu
    if (event.data.type === "openEditApparenceMenu") {
        creatorDebugLog("Activer le menu apparence")
        if (event.data.skinColours) {
            skinApparenceMenu = event.data.skinColours;
        }

        if (event.data.apparenceMenu) {
            globalApparenceMenu = event.data.apparenceMenu;
        }

        if (Array.isArray(event.data.eyeColours)) {
            eyeGlobalColours = event.data.eyeColours;
        }
        showApparenceMenu();
    } else if (event.data.type === "hideEditApparenceMenu") {
        hideApparenceMenu();
    } else if (event.data.type === "hideGlobalCharacterMenu") {
        hideApparenceMenu();
        isSecondChanceMode = false;
    }


    // Open Spawn Menu
    if (event.data.type === "openSpawnMenu") {
        creatorDebugLog("Activer le menu apparence")
        if (event.data.spawnLocation) {
            spawnLocationList = event.data.spawnLocation;
        }
        spawnBookConfig = event.data.spawnBook || {};
        showSpawnMenu();
    } else if (event.data.type === "hideSpawnMenu") {
        hideSpawnMenu();
    }


    // Open Selected Menu
    if (event.data.type === "openSelectedCharMenu") {
        creatorDebugLog("Activer le menu choix du perso")
        if (event.data.selectedDataChar) {
            showSelectedCharMenu(event.data.selectedDataChar);
        }

    } else if (event.data.type === "hideSelectedCharMenu") {
        hideSelectedCharMenu();
    }

    // Load contextualDatas
    if (event.data.type === "contextualDatas") {

        // Convert to array if it's an object
        const contextualData = Array.isArray(event.data.data) ? event.data.data : [event.data.data];
        const contextualType = contextualData[0]?.contextual
        if (!isInlineOutfitContext()) showContextualMenu(contextualType);
        loadContextualDatas(contextualData);
        creatorDebugLog("Charger les données de l'item", contextualData);
    }

    // Hide contextualDatas
    if (event.data.type === "hidecontextualDatas") {
        creatorDebugLog("Cacher le contextuel");
        hideContextualMenu();
    }


    // Open Eye Menu
    if (event.data.type === "openEyesPersoMenu") {
        creatorDebugLog("Activer le menu choix des yeux du perso")
        if (event.data.eyesColours) {
            eyeApparenceMenu = event.data.eyesColours;
            // The appearance page shows the same list, so keep both in sync.
            eyeGlobalColours = event.data.eyesColours;
            showEyesContextualMenu();
        }


    } else if (event.data.type === "hideEyesPersoMenu") {
        hideEyesContextualMenu();
    }
    window.requestAnimationFrame(syncCreatorViewControls);
});

///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////
//                                    LOAD RED INPUT                                                 //
///////////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////////


function updateRangeBackground(rangeInput) {
    const styleId = 'style_' + rangeInput;
    const oldStyle = document.getElementById(styleId);
    if (oldStyle) {
        oldStyle.parentNode.removeChild(oldStyle);
    }

    const rangeInputElem = document.getElementById(rangeInput);
    if (!rangeInputElem) return;
    const value = Number(rangeInputElem.value);
    const min = Number(rangeInputElem.min || 0);
    const max = Number(rangeInputElem.max || 100);
    const denominator = Math.max(max - min, 1);
    const percentage = Math.max(0, Math.min(100, ((value - min) / denominator) * 100));

    const backgroundStyle = `
        #${rangeInput} {
            height: 6px !important;
            max-height: 6px !important;
            min-height: 6px !important;
            padding: 0 !important;
            margin: 0 !important;
            border: none !important;
            border-radius: 3px !important;
            box-sizing: border-box !important;
            background: linear-gradient(to right,
                #ac0b10 0%,
                #ac0b10 ${percentage}%,
                rgba(0, 0, 0, 0.65) ${percentage}%,
                rgba(0, 0, 0, 0.65) 100%
            ) !important;
        }

        #${rangeInput}::-webkit-slider-runnable-track {
            height: 6px !important;
            max-height: 6px !important;
            min-height: 6px !important;
            border: none !important;
            background: transparent !important;
            border-radius: 3px !important;
        }
        #${rangeInput}::-moz-range-track {
            height: 6px !important;
            border: none !important;
            background: transparent !important;
        }
    `;

    const style = document.createElement('style');
    style.id = styleId;
    style.textContent = backgroundStyle;
    document.head.appendChild(style);
}

/* ---------------------------------------------------------------------------
   Language step
   ---------------------------------------------------------------------------
   The player picks the server language here, on the character screen, before
   any character is chosen. jrs_core owns the value (users.language); this block
   only renders the choice and reports it back.
   --------------------------------------------------------------------------- */

// Every screen the player can still be on before the character spawns.
const PRE_SPAWN_SCREENS = [
    'openSelectCharMenu',
    'showCharGlobalMenu',
    'openSpawnMenu',
    'openEditApparenceMenu',
    'showEditionMenu',
];

let languageOptions = [];
let languageSelected = 'en';
let languageMandatory = false;

function renderLanguageOptions() {
    const host = document.getElementById('LanguageOptions');
    if (!host) return;

    host.innerHTML = '';

    languageOptions.forEach((entry) => {
        const option = document.createElement('a');
        option.href = '#';
        option.className = 'button languageOption';
        if (entry.code === languageSelected) {
            option.classList.add('selected');
        }
        option.setAttribute('data-language', entry.code);

        const native = document.createElement('span');
        native.className = 'languageNative';
        native.textContent = entry.native || entry.label || entry.code;
        option.appendChild(native);

        // The English name stays next to the native one so a player who landed
        // on the wrong language can still recognise the way back.
        if (entry.label && entry.label !== entry.native) {
            const label = document.createElement('span');
            label.className = 'languageLabel';
            label.textContent = entry.label;
            option.appendChild(label);
        }

        option.addEventListener('click', (event) => {
            event.preventDefault();
            chooseLanguage(entry.code);
        });

        host.appendChild(option);
    });
}

function chooseLanguage(code) {
    if (!code) return;
    languageSelected = code;

    // Repaint the character screen immediately; the server confirms right
    // after and pushes the same value back through setLanguage.
    if (typeof window.applyLanguage === 'function') {
        window.applyLanguage(code);
    }
    if (lastSelectedCharData && document.getElementById('ChooseCharacterMenu') && !document.getElementById('ChooseCharacterMenu').classList.contains('hidden')) {
        loadSelectedCharData(lastSelectedCharData);
    }
    renderLanguageOptions();
    updateLanguageSwitchLabel();

    const menu = document.getElementById('LanguageMenu');
    if (menu) {
        const title = menu.querySelector('.language-menu-title') || menu.querySelector('h1');
        if (title) {
            title.textContent = (code === 'ar') ? 'جاري حفظ اللغة...' : 'Saving language...';
        }
    }

    $.post(`https://${GetParentResourceName()}/selectLanguage`, JSON.stringify({ language: code }));
}

function showLanguageMenu(mandatory) {
    languageMandatory = mandatory === true;
    const menu = document.getElementById('LanguageMenu');
    if (!menu) return;
    renderLanguageOptions();
    menu.classList.remove('hidden');
    menu.setAttribute('aria-hidden', 'false');
    const closeBtn = document.getElementById('CloseLanguageMenu');
    if (closeBtn) {
        closeBtn.style.display = languageMandatory ? 'none' : 'inline-block';
    }
}

function hideLanguageMenu() {
    // While the first choice is still outstanding the step cannot be dismissed.
    if (languageMandatory) return;
    const menu = document.getElementById('LanguageMenu');
    if (!menu) return;
    menu.classList.add('hidden');
    menu.setAttribute('aria-hidden', 'true');
}

function setLanguageSwitchVisible(visible) {
    const action = document.getElementById('OpenLanguageMenu');
    if (!action) return;
    action.classList.toggle('hidden', visible !== true);
}

// Keeps the Character Info header's language button showing the language
// actually active right now, whichever path changed it (the switcher's own
// menu, the server pushing setLanguage/jrsLanguage, or a fresh page load).
function updateLanguageSwitchLabel() {
    const label = document.getElementById('OpenLanguageMenuLabel');
    if (!label) return;
    const code = languageSelected || spawnBookLanguage() || 'en';
    label.textContent = String(code).slice(0, 2).toUpperCase();
}

window.addEventListener('message', (event) => {
    const data = event.data || {};

    if (data.type === 'setLanguageOptions') {
        languageOptions = Array.isArray(data.languages) ? data.languages : [];
        if (data.current) {
            languageSelected = data.current;
            if (typeof window.applyLanguage === 'function') {
                window.applyLanguage(languageSelected);
            }
        }
        renderLanguageOptions();
        updateLanguageSwitchLabel();
    }

    if (data.type === 'setLanguage' || data.type === 'jrsLanguage' || data.action === 'jrsLanguage') {
        languageSelected = data.language || data.current || languageSelected;
        if (typeof window.applyLanguage === 'function') {
            window.applyLanguage(languageSelected);
        }
        renderLanguageOptions();
        updateLanguageSwitchLabel();
    }

    if (data.type === 'openLanguageMenu') {
        if (Array.isArray(data.languages) && data.languages.length) {
            languageOptions = data.languages;
        }
        if (data.current) languageSelected = data.current;
        showLanguageMenu(data.mandatory === true);
    }

    if (data.type === 'hideLanguageMenu') {
        languageMandatory = false;
        hideLanguageMenu();
    }

    if (data.type === 'showLanguageSwitch') {
        setLanguageSwitchVisible(data.visible === true);
    }

    // (Changing language used to disconnect the player so every resource
    // reloaded; it applies in place now, so there is no "resetting" state.)

    // The player can change language at any point before the character spawns,
    // so the switcher rides along with every pre-spawn screen: selection,
    // creation, appearance editing and the spawn-point picker. Telling the
    // client on each of them also covers the account with no characters, which
    // opens straight into creation and never sees the selector - that player
    // still gets the mandatory first-run language step.
    if (PRE_SPAWN_SCREENS.indexOf(data.type) !== -1) {
        setLanguageSwitchVisible(true);
        $.post(`https://${GetParentResourceName()}/languageScreenReady`, JSON.stringify({}));
    }

    // The character UI has closed for good and the player is entering the
    // world. The language can still be changed from here on a later visit, or
    // with /language - it applies live either way.
    if (data.type === 'hideLanguageSwitch') {
        languageMandatory = false;
        hideLanguageMenu();
        setLanguageSwitchVisible(false);
        $.post(`https://${GetParentResourceName()}/languageScreenClosed`, JSON.stringify({}));
    }
});

document.addEventListener('DOMContentLoaded', () => {
    const open = document.getElementById('OpenLanguageMenu');
    if (open) {
        open.addEventListener('click', (event) => {
            event.preventDefault();
            showLanguageMenu(false);
        });
    }
    updateLanguageSwitchLabel();

    const langAction = document.getElementById('LanguageSelectedChar');
    if (langAction) {
        langAction.addEventListener('click', (event) => {
            event.preventDefault();
            showLanguageMenu(false);
        });
    }

    const closeLang = document.getElementById('CloseLanguageMenu');
    if (closeLang) {
        closeLang.addEventListener('click', (event) => {
            event.preventDefault();
            hideLanguageMenu();
        });
    }

    const langMenu = document.getElementById('LanguageMenu');
    if (langMenu) {
        langMenu.addEventListener('click', (event) => {
            if (event.target === langMenu && !languageMandatory) {
                hideLanguageMenu();
            }
        });
    }
});
