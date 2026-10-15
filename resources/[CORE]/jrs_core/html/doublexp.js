const jrsDoubleXp = document.getElementById('doubleXpHud');
const jrsDoubleXpMultiplier = document.getElementById('doubleXpMultiplier');
const jrsDoubleXpTitle = document.getElementById('doubleXpTitle');
const jrsDoubleXpTimer = document.getElementById('doubleXpTimer');
const jrsDoubleXpFillClip = document.getElementById('doubleXpFillClip');

const jrsDoubleXpState = {
    active: false,
    multiplier: 1,
    deadlineMs: 0,
    initialSeconds: 0,
};

let jrsDoubleXpTicker = null;

function jrsDoubleXpFormatMultiplier(value) {
    const amount = Math.max(1, Number(value) || 1);
    return Number.isInteger(amount) ? String(amount) : amount.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
}

function jrsDoubleXpGetBoostInfo(multiplier) {
    const m = Math.max(1, Number(multiplier) || 1);
    const i18n = window.JrsI18n;
    if (Math.abs(m - 2) < 0.01) {
        return {
            badge: '2X',
            title: i18n ? i18n.t('core_double_xp', 'DOUBLE XP') : 'DOUBLE XP',
        };
    } else if (Math.abs(m - 3) < 0.01) {
        return {
            badge: '3X',
            title: i18n ? i18n.t('core_triple_xp', 'TRIPLE XP') : 'TRIPLE XP',
        };
    } else if (Math.abs(m - 4) < 0.01) {
        return {
            badge: '4X',
            title: i18n ? i18n.t('core_quad_xp', 'QUAD XP') : 'QUAD XP',
        };
    } else {
        const formatted = jrsDoubleXpFormatMultiplier(m);
        const suffix = i18n ? i18n.t('core_boost_suffix', 'X BOOST') : 'X BOOST';
        return {
            badge: `x${formatted}`,
            title: `${formatted}${suffix}`,
        };
    }
}

function jrsDoubleXpFormatTime(totalSeconds) {
    const total = Math.max(0, Math.ceil(Number(totalSeconds) || 0));
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const seconds = total % 60;

    if (hours > 0) {
        return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
    }
    return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

function jrsDoubleXpStopTicker() {
    if (jrsDoubleXpTicker) {
        clearInterval(jrsDoubleXpTicker);
        jrsDoubleXpTicker = null;
    }
}

function jrsDoubleXpHide() {
    jrsDoubleXpState.active = false;
    jrsDoubleXpStopTicker();
    if (jrsDoubleXp) {
        jrsDoubleXp.classList.add('tier-hidden');
        jrsDoubleXp.classList.remove('is-active', 'is-visible');
        jrsDoubleXp.setAttribute('aria-hidden', 'true');
        jrsDoubleXp.style.display = 'none';
    }
    const card = document.getElementById('levelHudCard');
    if (card) card.classList.remove('has-boost');
    const hud = document.getElementById('levelHud');
    if (hud) hud.classList.remove('has-boost');
}

function jrsDoubleXpRender() {
    if (!jrsDoubleXp || !jrsDoubleXpState.active) return;

    const remainingMs = jrsDoubleXpState.deadlineMs - Date.now();
    const remainingSeconds = Math.max(0, remainingMs / 1000);

    if (remainingSeconds <= 0) {
        jrsDoubleXpHide();
        return;
    }

    const boost = jrsDoubleXpGetBoostInfo(jrsDoubleXpState.multiplier);
    if (jrsDoubleXpMultiplier) {
        jrsDoubleXpMultiplier.textContent = boost.badge;
        jrsDoubleXpMultiplier.setAttribute('data-digits', String(boost.badge.length));
        jrsDoubleXpMultiplier.setAttribute('data-chars', String(boost.badge.length));
    }
    if (jrsDoubleXpTitle) {
        jrsDoubleXpTitle.textContent = boost.title;
    }
    if (jrsDoubleXpTimer) {
        jrsDoubleXpTimer.textContent = jrsDoubleXpFormatTime(remainingSeconds);
    }
    if (jrsDoubleXpFillClip) {
        const base = Math.max(1, jrsDoubleXpState.initialSeconds);
        const percent = Math.max(0, Math.min(100, (remainingSeconds / base) * 100));
        jrsDoubleXpFillClip.style.width = `${percent}%`;
    }
}

function jrsDoubleXpSet(payload = {}) {
    const active = payload.active === true;
    const remainingSeconds = Math.max(0, Math.floor(Number(payload.remainingSeconds) || 0));

    if (!active || remainingSeconds <= 0) {
        jrsDoubleXpHide();
        return;
    }

    jrsDoubleXpState.active = true;
    jrsDoubleXpState.multiplier = Math.max(1, Number(payload.multiplier) || 1);
    jrsDoubleXpState.initialSeconds = Math.max(remainingSeconds, Math.floor(Number(payload.durationSeconds) || 0));
    jrsDoubleXpState.deadlineMs = Date.now() + (remainingSeconds * 1000);

    if (jrsDoubleXp) {
        jrsDoubleXp.classList.remove('tier-hidden');
        jrsDoubleXp.classList.add('is-active');
        jrsDoubleXp.setAttribute('aria-hidden', 'false');
        jrsDoubleXp.style.display = 'block';
    }
    const card = document.getElementById('levelHudCard');
    if (card) card.classList.add('has-boost');
    const hud = document.getElementById('levelHud');
    if (hud) hud.classList.add('has-boost');

    jrsDoubleXpRender();
    jrsDoubleXpStopTicker();
    jrsDoubleXpTicker = setInterval(jrsDoubleXpRender, 250);
}

window.addEventListener('message', (event) => {
    const data = event.data || {};
    switch (data.action) {
        case 'jrsDoubleXP:set':
            jrsDoubleXpSet(data);
            break;
        case 'jrsDoubleXP:hide':
            jrsDoubleXpHide();
            break;
    }
});

window.addEventListener('load', () => {
    jrsDoubleXpHide();
});

if (window.JrsI18n && typeof window.JrsI18n.onChange === 'function') {
    window.JrsI18n.onChange(jrsDoubleXpRender);
}
