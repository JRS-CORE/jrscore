/* ==========================================================================
   jrs_notify - JRS unified synchronized notification renderer.

   Features:
   - Intelligent Arabic & text normalization to prevent duplicate/overlapping toasts.
   - Active toast detection: renews/refreshes existing toasts instead of stacking duplicates.
   - Synchronized queue manager (طابور متزامن) with staggered entry to prevent burst overlap.
   - Smooth lifecycle transitions (show, pulse refresh, and smooth collapsing hide).
   - Independent dock isolation so notifications don't jump across the screen.
   ========================================================================== */

const NOTIFY_ICONS = {
    success: 'fa-circle-check',
    error:   'fa-triangle-exclamation',
    warning: 'fa-triangle-exclamation',
    reward:  'fa-coins',
    info:    'fa-circle-info'
};

const NOTIFY_SOUNDS = {
    info:    'sounds/selected.mp3',
    warning: 'sounds/collect_fail.mp3',
    error:   'sounds/collect_fail.mp3',
    success: 'sounds/collect_success.mp3',
    reward:  'sounds/coins.mp3'
};

const POSITIONS = new Set(['top-right', 'top-left', 'top-center', 'bottom-center', 'bottom-right', 'bottom-left']);
const ARABIC_REGEX = /[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]/;

let menuOpen = false;
let maxVisible = 4;
let defaultPosition = 'top-right';
let menuOpenPosition = 'top-right';

let _lastNotifySoundAt = 0;

// Queue and active tracking
const activeToasts = new Map(); // dedupeKey -> { element, timer, hide, data }
const notificationQueue = [];
let isProcessingQueue = false;
let recentDedupeHistory = []; // { key, at }

function escapeHtml(value) {
    return String(value === null || value === undefined ? '' : value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

// Normalize text for duplicate detection (cleans arabic diacritics, alefs, punctuation, extra spaces)
function normalizeMessage(str) {
    if (str === null || str === undefined) return '';
    return String(str)
        .trim()
        .replace(/[\u064B-\u065F\u0670]/g, '') // remove tashkeel
        .replace(/[إأآٱ]/g, 'ا') // normalize alef
        .replace(/ة/g, 'ه')     // normalize teh marbuta
        .replace(/[.!?؛،,:…_—\-]+$/g, '') // strip trailing punctuation
        .replace(/\s+/g, ' ')  // normalize whitespace
        .toLowerCase();
}

function playNotifySound(file, volume, gap, kind) {
    if (file === false || file === 'false') return;
    file = file || NOTIFY_SOUNDS[kind];
    if (!file) return;
    const now = Date.now();
    const minGap = Math.max(0, Number(gap) || 200);
    if ((now - _lastNotifySoundAt) < minGap) return;
    _lastNotifySoundAt = now;
    try {
        const audio = new Audio(String(file));
        audio.volume = Math.max(0, Math.min(1, Number(volume) || .28));
        audio.play().catch(() => {});
    } catch (_) {}
}

function resolvePosition(position) {
    const requested = String(position || '');
    if (POSITIONS.has(requested)) return requested;
    return menuOpen ? menuOpenPosition : defaultPosition;
}

function getStack(position) {
    const dock = resolvePosition(position);
    let stack = document.getElementById(`notifyStack-${dock}`);
    if (!stack) {
        const defaultStack = document.getElementById('notifyStack');
        if (defaultStack && (!defaultStack.dataset.dock || defaultStack.dataset.dock === dock)) {
            defaultStack.id = `notifyStack-${dock}`;
            defaultStack.dataset.dock = dock;
            defaultStack.className = `notify-stack pos-${dock}`;
            return defaultStack;
        }
        stack = document.createElement('div');
        stack.id = `notifyStack-${dock}`;
        stack.dataset.dock = dock;
        stack.className = `notify-stack pos-${dock}`;
        document.body.appendChild(stack);
    }
    return stack;
}

function hideToast(dedupeKey) {
    const active = activeToasts.get(dedupeKey);
    if (!active) return;
    activeToasts.delete(dedupeKey);
    if (active.timer) clearTimeout(active.timer);

    const el = active.element;
    if (el) {
        el.classList.remove('show');
        el.classList.add('hide');
        setTimeout(() => {
            if (el.parentNode) el.parentNode.removeChild(el);
        }, 280);
    }
}

function displayToast(data, dedupeKey, rawText, rawTitle) {
    const stack = getStack(data.position);
    if (!stack) return;

    const kind = NOTIFY_ICONS[data.notifyType] ? data.notifyType : 'info';
    playNotifySound(data.sound, data.soundVolume, data.soundGap, kind);

    const ms = Math.max(2000, Number(data.duration) || 4500);

    // Keep visible toasts bounded per stack - smoothly retire oldest
    const currentChildren = Array.from(stack.children).filter(c => !c.classList.contains('hide'));
    while (currentChildren.length >= Math.max(1, maxVisible)) {
        const oldest = currentChildren.shift();
        for (const [key, val] of activeToasts.entries()) {
            if (val.element === oldest) {
                hideToast(key);
                break;
            }
        }
        if (oldest && !oldest.classList.contains('hide')) {
            oldest.classList.add('hide');
            setTimeout(() => { if (oldest.parentNode) oldest.parentNode.removeChild(oldest); }, 280);
        }
    }

    const toast = document.createElement('div');
    toast.className = `notify-toast type-${kind}`;

    const isArabicText = ARABIC_REGEX.test(rawText);
    const isArabicTitle = ARABIC_REGEX.test(rawTitle);
    if (isArabicText) toast.classList.add('has-arabic-text');
    if (isArabicTitle) toast.classList.add('has-arabic-title');

    const glyph = `<i class="fa-solid ${NOTIFY_ICONS[kind]}"></i>`;
    toast.innerHTML =
        `<div class="notify-icon">${glyph}</div>` +
        '<div class="notify-body">' +
            `<div class="notify-title">${escapeHtml(rawTitle || (typeof JrsI18n !== 'undefined' ? JrsI18n.t('brand_name', 'JRS CORE') : 'JRS CORE'))}</div>` +
            `<div class="notify-text">${escapeHtml(rawText)}</div>` +
        '</div>';

    if (data.image) {
        const slot = toast.querySelector('.notify-icon');
        const img = new Image();
        img.alt = '';
        img.onload = () => {
            if (!slot.isConnected) return;
            slot.innerHTML = '';
            slot.appendChild(img);
        };
        img.onerror = () => {};
        img.src = String(data.image);
    }

    stack.appendChild(toast);
    requestAnimationFrame(() => requestAnimationFrame(() => toast.classList.add('show')));

    const hideTimer = setTimeout(() => {
        hideToast(dedupeKey);
    }, ms);

    activeToasts.set(dedupeKey, {
        element: toast,
        timer: hideTimer
    });
}

function processQueue() {
    if (isProcessingQueue || notificationQueue.length === 0) return;
    isProcessingQueue = true;

    const item = notificationQueue.shift();
    displayToast(item.data, item.dedupeKey, item.rawText, item.rawTitle);

    // Stagger subsequent notifications by 320ms so multiple notifications enter smoothly in sync without overlap
    setTimeout(() => {
        isProcessingQueue = false;
        if (notificationQueue.length > 0) {
            processQueue();
        }
    }, 320);
}

function showNotification(data) {
    if (!data) return;
    const rawText = data.text === null || data.text === undefined ? '' : String(data.text).trim();
    if (!rawText) return;

    const rawTitle = data.title === null || data.title === undefined ? '' : String(data.title).trim();
    const normText = normalizeMessage(rawText);
    const normTitle = normalizeMessage(rawTitle);
    const dedupeKey = `${normTitle}|${normText}`;
    const now = Date.now();

    // 1. Check if identical notification is ALREADY visibly active on screen!
    if (activeToasts.has(dedupeKey)) {
        const active = activeToasts.get(dedupeKey);
        if (active && active.element && active.element.isConnected && !active.element.classList.contains('hide')) {
            // Refresh duration and pulse instead of creating a stacked duplicate ("تدبيل")
            clearTimeout(active.timer);
            const ms = Math.max(2500, Number(data.duration) || 4500);
            active.timer = setTimeout(() => hideToast(dedupeKey), ms);

            active.element.classList.remove('pulse');
            void active.element.offsetWidth; // trigger reflow
            active.element.classList.add('pulse');

            const kind = NOTIFY_ICONS[data.notifyType] ? data.notifyType : 'info';
            playNotifySound(data.sound, data.soundVolume, data.soundGap, kind);
            return;
        }
    }

    // 2. Check if identical notification is already waiting in the synchronization queue
    if (notificationQueue.some(item => item.dedupeKey === dedupeKey)) {
        return;
    }

    // 3. Rolling deduplication memory window (3000ms)
    recentDedupeHistory = recentDedupeHistory.filter(item => (now - item.at) < 3000);
    if (recentDedupeHistory.some(item => item.key === dedupeKey && (now - item.at) < 1800)) {
        return;
    }
    recentDedupeHistory.push({ key: dedupeKey, at: now });

    // Handled by a higher NUI layer (such as jrs_admin when panel is open)
    if (data.soundOnly === true) {
        const kind = NOTIFY_ICONS[data.notifyType] ? data.notifyType : 'info';
        playNotifySound(data.sound, data.soundVolume, data.soundGap, kind);
        return;
    }

    // Push into the synchronized queue
    notificationQueue.push({
        data: data,
        dedupeKey: dedupeKey,
        rawText: rawText,
        rawTitle: rawTitle
    });

    processQueue();
}

function clearNotifications() {
    notificationQueue.length = 0;
    for (const key of Array.from(activeToasts.keys())) {
        hideToast(key);
    }
    activeToasts.clear();
    recentDedupeHistory = [];
    _lastNotifySoundAt = 0;
}

window.addEventListener('message', function (event) {
    const data = event.data || {};

    switch (data.type) {
        case 'show_notification':
            showNotification(data);
            break;

        case 'notify_settings':
            if (typeof data.maxVisible === 'number') maxVisible = data.maxVisible;
            if (POSITIONS.has(String(data.defaultPosition))) defaultPosition = String(data.defaultPosition);
            if (POSITIONS.has(String(data.menuOpenPosition))) menuOpenPosition = String(data.menuOpenPosition);
            break;

        case 'notify_menu_state':
            menuOpen = data.menuOpen === true;
            break;

        case 'clear_notifications':
            clearNotifications();
            break;
    }
});

/* Tell the Lua side we exist so it can push the configured positions and stack
   size. Without this the page would keep its built-in defaults whenever the
   client script started before the page finished loading. */
fetch('https://jrs_core/ready', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: '{}'
}).catch(() => {});
