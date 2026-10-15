// ---------------------------------------------------------------------------
// Loading screen language
//
// The loading screen is the first thing a player sees, before the character
// screen and before anything else on the server has drawn, so this is where the
// language is offered first. The choice made here is the account's language:
// it is sent to jrs_core, stored on users.language, and everything downstream -
// the character screen included - is already in it.
//
// Three things keep the choice from being lost:
//   * localStorage, so the loading screen itself comes back in the right
//     language on the next connect, instantly, before any round trip
//   * a fetch to the resource's setLanguage callback, retried, so the server
//     stores it on the account
//   * the character screen, which still asks if the account has no stored
//     choice - a player who never touched this toggle is not skipped
// ---------------------------------------------------------------------------

import EN from '../locales/en.js';
import AR from '../locales/ar.js';

const PACKS = { en: EN, ar: AR };
const FALLBACK = 'en';
const DEFAULT_LANG = 'ar';
const RTL = { ar: true };
const STORAGE_KEY = 'jrs_language';

const OPTIONS = [
    { code: 'ar', native: 'العربية', label: 'Arabic' },
    { code: 'en', native: 'English', label: 'English' },
];

const LANGUAGE = {
    current: DEFAULT_LANG,
    listeners: [],

    init() {
        const hasSaved = this.restoreHasSaved();
        this.current = this.restore();
        this.buildToggle();
        this.apply();
        // Only publish to the server if the user has an explicitly saved preference.
        // Avoid auto-publishing on fresh boots so jrs_character can present mandatory picker if unselected.
        if (hasSaved) {
            this.publish(this.current);
        }
    },

    restoreHasSaved() {
        try {
            const saved = window.localStorage.getItem(STORAGE_KEY);
            return !!(saved && PACKS[saved]);
        } catch (e) {
            return false;
        }
    },

    restore() {
        try {
            const saved = window.localStorage.getItem(STORAGE_KEY);
            if (saved && PACKS[saved]) return saved;
        } catch (e) {
            // Private/blocked storage - fall through to the default.
        }
        return DEFAULT_LANG;
    },

    remember(code) {
        try {
            window.localStorage.setItem(STORAGE_KEY, code);
        } catch (e) {
            // Nothing to do; the server copy is the durable one.
        }
    },

    /** Look a key up in the active language, then English. */
    t(key, fallback) {
        const pack = PACKS[this.current] || {};
        if (Object.prototype.hasOwnProperty.call(pack, key)) return pack[key];
        const base = PACKS[FALLBACK] || {};
        if (Object.prototype.hasOwnProperty.call(base, key)) return base[key];
        return fallback !== undefined ? fallback : key;
    },

    /** The right text out of an { X, X_AR } pair in the content config. */
    pick(entry, field) {
        if (!entry) return '';
        if (this.current !== FALLBACK) {
            const localized = entry[field + '_' + this.current.toUpperCase()];
            if (localized) return localized;
        }
        return entry[field] || '';
    },

    isRTL() {
        return RTL[this.current] === true;
    },

    onChange(fn) {
        if (typeof fn === 'function') this.listeners.push(fn);
    },

    set(code) {
        if (!PACKS[code] || code === this.current && this.restoreHasSaved()) return;
        this.current = code;
        this.remember(code);
        this.apply();
        this.publish(code);
    },

    apply() {
        document.documentElement.setAttribute('lang', this.current);
        document.body.classList.toggle('lang-rtl', this.isRTL());

        document.querySelectorAll('[data-i18n]').forEach((el) => {
            if (el.id === 'user-name') {
                if (el.dataset.realName) {
                    el.textContent = el.dataset.realName;
                    return;
                }
                if (window.nuiHandoverData && window.nuiHandoverData.name && window.nuiHandoverData.name !== 'Outsider') {
                    el.dataset.realName = window.nuiHandoverData.name;
                    el.textContent = window.nuiHandoverData.name;
                    return;
                }
            }
            if (el.dataset.i18nDefault === undefined) {
                el.dataset.i18nDefault = el.textContent;
            }
            el.textContent = this.t(el.getAttribute('data-i18n'), el.dataset.i18nDefault);
        });

        this.markToggle();
        this.listeners.forEach((fn) => {
            try { fn(this.current); } catch (e) { console.error('[loadingscreen]', e); }
        });
    },

    // The toggle is built here rather than in index.html so the option list
    // lives in one place alongside the packs.
    buildToggle() {
        const host = document.getElementById('language-toggle');
        if (!host) return;

        host.innerHTML = '';
        const title = document.createElement('div');
        title.className = 'language-toggle-title';
        title.innerHTML = '<span data-i18n="language">اللغة</span>';
        host.appendChild(title);

        const group = document.createElement('div');
        group.className = 'language-toggle-group';

        OPTIONS.forEach((option) => {
            const button = document.createElement('button');
            button.type = 'button';
            button.className = 'language-btn';
            button.dataset.language = option.code;
            button.textContent = option.native;
            button.title = option.label;
            button.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                this.set(option.code);
            });
            group.appendChild(button);
        });
        host.appendChild(group);
    },

    markToggle() {
        document.querySelectorAll('#language-toggle .language-btn').forEach((button) => {
            button.classList.toggle('active', button.dataset.language === this.current);
        });
    },

    publish(code) {
        // The loading screen is a loadscreen NUI: fetch to the resource's own
        // callback is the only way back into Lua from here.
        // 2.8.0: one retry loop at a time - clicking the toggle a few times used
        // to leave several 60-try loops running and racing each other.
        this.publishToken = (this.publishToken || 0) + 1;
        const token = this.publishToken;
        let attempts = 0;
        const maxAttempts = 60;
        const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'jrs_loadingscreen';
        const send = () => {
            if (token !== this.publishToken) return;
            attempts += 1;
            fetch(`https://${resourceName}/setLanguage`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify({ language: code }),
            }).then((res) => {
                if (!res.ok && attempts < maxAttempts) {
                    setTimeout(send, 2000);
                }
            }).catch(() => {
                if (attempts < maxAttempts) {
                    setTimeout(send, 2000);
                }
            });
        };
        send();
    },
};

export default LANGUAGE;
