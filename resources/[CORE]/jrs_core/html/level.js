const jrsLevelHud = document.getElementById('levelHud');
const jrsLevelHudCard = document.getElementById('levelHudCard');
const jrsRankNumber = document.getElementById('rankNumber');
const jrsXpFillClip = document.getElementById('xpFillClip');
const jrsXpMetaValue = document.getElementById('xpMetaValue');
const jrsXpWrap = document.getElementById('xpWrap');
const jrsXpBar = document.getElementById('xpBar');
const jrsXpMeta = document.getElementById('xpMeta');
const jrsLevelMaxText = document.getElementById('levelMaxText');

const jrsLevelToast = document.getElementById('levelToast');
const jrsLevelToastTitle = document.getElementById('levelToastTitle');
const jrsLevelToastOld = document.getElementById('levelToastOld');
const jrsLevelToastNew = document.getElementById('levelToastNew');

const jrsLevelState = {
    visible: false,
    level: 1,
    progress: 0,
    currentXp: 0,
    requiredXp: 200,
    isMaxLevel: false,
};

let jrsLevelToastTimer = null;

function jrsLevelClamp(value, min, max) {
    return Math.min(max, Math.max(min, Number(value) || 0));
}

function jrsRenderLevelHud() {
    if (!jrsLevelHud) return;

    jrsLevelHud.classList.toggle('is-visible', !!jrsLevelState.visible);
    // The block stays in the tree for the XP boost banner it now carries, so
    // the hidden flag belongs to the card that actually fades out.
    if (jrsLevelHudCard) jrsLevelHudCard.setAttribute('aria-hidden', jrsLevelState.visible ? 'false' : 'true');

    if (jrsLevelState.isMaxLevel) {
        if (jrsRankNumber) {
            jrsRankNumber.textContent = window.JrsI18n ? window.JrsI18n.t('core_max', 'MAX') : 'MAX';
            jrsRankNumber.setAttribute('data-digits', '3');
            jrsRankNumber.classList.add('rankBadge__number--max');
        }
        if (jrsXpWrap) jrsXpWrap.classList.add('is-max');
        if (jrsXpBar) jrsXpBar.style.display = 'none';
        if (jrsXpMeta) jrsXpMeta.style.display = 'none';
        if (jrsLevelMaxText) jrsLevelMaxText.style.display = 'block';
        return;
    }

    if (jrsRankNumber) jrsRankNumber.classList.remove('rankBadge__number--max');
    if (jrsXpWrap) jrsXpWrap.classList.remove('is-max');
    if (jrsXpBar) jrsXpBar.style.display = '';
    if (jrsXpMeta) jrsXpMeta.style.display = '';
    if (jrsLevelMaxText) jrsLevelMaxText.style.display = 'none';

    const levelText = String(Math.max(1, Math.floor(Number(jrsLevelState.level) || 1)));
    const digits = Math.min(3, levelText.length);

    if (jrsRankNumber) {
        jrsRankNumber.textContent = levelText;
        jrsRankNumber.setAttribute('data-digits', String(digits));
    }

    if (jrsXpFillClip) {
        jrsXpFillClip.style.width = `${jrsLevelClamp(jrsLevelState.progress, 0, 100)}%`;
    }
    if (jrsXpMetaValue) {
        const xpSuffix = window.JrsI18n ? window.JrsI18n.t('core_xp_suffix', 'XP') : 'XP';
        jrsXpMetaValue.textContent = `${Math.floor(jrsLevelState.currentXp)} / ${Math.floor(jrsLevelState.requiredXp)} ${xpSuffix}`;
    }
}

function jrsPatchLevelHud(payload = {}) {
    const oldLevel = jrsLevelState.level;
    if (payload.level !== undefined) jrsLevelState.level = payload.level;
    if (payload.progress !== undefined) jrsLevelState.progress = payload.progress;
    if (payload.currentXp !== undefined) jrsLevelState.currentXp = payload.currentXp;
    if (payload.requiredXp !== undefined) jrsLevelState.requiredXp = payload.requiredXp;
    if (payload.visible !== undefined) jrsLevelState.visible = !!payload.visible;
    if (payload.isMaxLevel !== undefined) jrsLevelState.isMaxLevel = !!payload.isMaxLevel;

    if (payload.level !== undefined && payload.level !== oldLevel && jrsRankNumber) {
        jrsRankNumber.classList.remove('rank-pulse');
        void jrsRankNumber.offsetWidth;
        jrsRankNumber.classList.add('rank-pulse');
        setTimeout(() => {
            if (jrsRankNumber) jrsRankNumber.classList.remove('rank-pulse');
        }, 600);
    }
    jrsRenderLevelHud();
}

function jrsHideLevelToast() {
    if (!jrsLevelToast) return;
    jrsLevelToast.classList.remove('is-visible', 'is-up', 'is-down');
    jrsLevelToast.setAttribute('aria-hidden', 'true');
}

function jrsShowLevelToast(payload = {}) {
    if (!jrsLevelToast || !jrsLevelToastTitle || !jrsLevelToastOld || !jrsLevelToastNew) return;

    const kind = payload.toastType === 'down' ? 'down' : 'up';
    const oldLevel = Math.max(1, Math.floor(Number(payload.oldLevel) || 1));
    const newLevel = Math.max(1, Math.floor(Number(payload.newLevel) || 1));
    const duration = Math.max(500, Math.floor(Number(payload.duration) || 2600));

    const titleUp = window.JrsI18n ? window.JrsI18n.t('core_level_up', 'LEVEL UP') : 'LEVEL UP';
    const titleDown = window.JrsI18n ? window.JrsI18n.t('core_level_down', 'LEVEL DOWN') : 'LEVEL DOWN';
    jrsLevelToastTitle.textContent = kind === 'down' ? titleDown : titleUp;
    jrsLevelToastOld.textContent = String(oldLevel);
    jrsLevelToastNew.textContent = String(newLevel);

    jrsLevelToast.classList.remove('is-up', 'is-down');
    jrsLevelToast.classList.add(kind === 'down' ? 'is-down' : 'is-up');
    jrsLevelToast.classList.add('is-visible');
    jrsLevelToast.setAttribute('aria-hidden', 'false');

    if (jrsLevelToastTimer) clearTimeout(jrsLevelToastTimer);
    jrsLevelToastTimer = setTimeout(() => {
        jrsHideLevelToast();
        jrsLevelToastTimer = null;
    }, duration);
}

window.addEventListener('message', (event) => {
    const data = event.data || {};

    switch (data.action) {
        case 'jrsLevel:init':
            jrsRenderLevelHud();
            break;
        case 'jrsLevel:show':
            jrsPatchLevelHud({ ...data, visible: true });
            break;
        case 'jrsLevel:update':
            jrsPatchLevelHud(data);
            break;
        case 'jrsLevel:hide':
            jrsPatchLevelHud({ visible: false });
            break;
        case 'jrsLevel:toast':
            jrsShowLevelToast(data);
            break;
    }
});

if (window.JrsI18n && typeof window.JrsI18n.onChange === 'function') {
    window.JrsI18n.onChange(jrsRenderLevelHud);
}

window.addEventListener('load', jrsRenderLevelHud);
jrsRenderLevelHud();
