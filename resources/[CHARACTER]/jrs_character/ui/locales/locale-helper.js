// JRS Character Creator - translation helper
//
// Every language pack registers itself into window.LocaleTables (see own_en.js /
// own_ar.js) and/or window.JrsI18n (see en.js / ar.js). This helper bridges both,
// ensuring every flat key (e.g. "character_money") and nested key (e.g. "ui.play")
// resolves correctly in the active player language.

let currentLocale = 'ar';

const FALLBACK_LOCALE = 'en';
const RTL_LOCALES = ['ar'];

function tables() {
    return (typeof window !== 'undefined' && window.LocaleTables) || {};
}

// Deep merge, English underneath. Only plain objects recurse; strings replace.
function mergeLocale(base, over) {
    const out = Array.isArray(base) ? base.slice() : Object.assign({}, base);
    Object.keys(over || {}).forEach((key) => {
        const value = over[key];
        if (value && typeof value === 'object' && !Array.isArray(value)
            && out[key] && typeof out[key] === 'object' && !Array.isArray(out[key])) {
            out[key] = mergeLocale(out[key], value);
        } else {
            out[key] = value;
        }
    });
    return out;
}

// Initialize translations
function initLocale(locale = 'ar') {
    const all = tables();
    const base = all[FALLBACK_LOCALE] || {};
    const wanted = all[locale];

    currentLocale = wanted ? locale : (all[FALLBACK_LOCALE] ? FALLBACK_LOCALE : locale);
    window.Locale = wanted ? mergeLocale(base, wanted) : base;

    if (typeof window !== 'undefined' && window.JrsI18n && typeof window.JrsI18n.setLanguage === 'function') {
        window.JrsI18n.setLanguage(currentLocale);
    }

    document.documentElement.setAttribute('lang', currentLocale);
    document.body.classList.toggle('lang-rtl', RTL_LOCALES.indexOf(currentLocale) !== -1);
    document.body.classList.remove('lang-en', 'lang-ar');
    document.body.classList.add('lang-' + currentLocale);
}

function getLocale() {
    return currentLocale;
}

// Get translation by path or flat key (e.g., "ui.cancel", "charSelect.title", "character_money")
function t(path, fallback = null) {
    if (!path) return fallback || '';

    // 1. Try JrsI18n first if registered
    if (typeof window !== 'undefined' && window.JrsI18n && typeof window.JrsI18n.t === 'function') {
        const jrsVal = window.JrsI18n.t(path);
        if (jrsVal !== undefined && jrsVal !== null && jrsVal !== path) {
            return jrsVal;
        }
    }

    // 2. Try window.Locale direct flat key
    if (window.Locale && typeof window.Locale[path] === 'string') {
        return window.Locale[path];
    }

    // 3. Try window.Locale nested path
    if (window.Locale) {
        const keys = path.split('.');
        let value = window.Locale;
        let found = true;
        for (const key of keys) {
            if (value && typeof value === 'object' && key in value) {
                value = value[key];
            } else {
                found = false;
                break;
            }
        }
        if (found && typeof value === 'string') {
            return value;
        }
    }

    return fallback !== null && fallback !== undefined ? fallback : path;
}

// Update all elements with data-i18n attribute
function updateTranslations(root) {
    const scope = root || document;

    // Handle text content translations
    scope.querySelectorAll('[data-i18n]').forEach(element => {
        const key = element.getAttribute('data-i18n');
        if (!key) return;
        if (element.dataset.i18nDefault === undefined) {
            element.dataset.i18nDefault = element.textContent;
        }
        const translation = t(key, element.dataset.i18nDefault);
        if (translation !== undefined && translation !== null && translation !== key) {
            element.textContent = translation;
        } else if (element.dataset.i18nDefault) {
            element.textContent = element.dataset.i18nDefault;
        }
    });

    // Handle placeholder translations
    scope.querySelectorAll('[data-i18n-placeholder]').forEach(element => {
        const key = element.getAttribute('data-i18n-placeholder');
        if (!key) return;
        if (element.dataset.i18nPlaceholderDefault === undefined) {
            element.dataset.i18nPlaceholderDefault = element.placeholder || '';
        }
        const translation = t(key, element.dataset.i18nPlaceholderDefault);
        if (translation !== undefined && translation !== null && translation !== key) {
            element.placeholder = translation;
        } else if (element.dataset.i18nPlaceholderDefault) {
            element.placeholder = element.dataset.i18nPlaceholderDefault;
        }
    });

    // Handle title translations
    scope.querySelectorAll('[data-i18n-title]').forEach(element => {
        const key = element.getAttribute('data-i18n-title');
        if (!key) return;
        if (element.dataset.i18nTitleDefault === undefined) {
            element.dataset.i18nTitleDefault = element.title || '';
        }
        const translation = t(key, element.dataset.i18nTitleDefault);
        if (translation !== undefined && translation !== null && translation !== key) {
            element.title = translation;
        } else if (element.dataset.i18nTitleDefault) {
            element.title = element.dataset.i18nTitleDefault;
        }
    });
}

// Switch language at runtime.
function applyLanguage(locale) {
    initLocale(locale || currentLocale || FALLBACK_LOCALE);
    updateTranslations();
    if (typeof window.onLocaleChanged === 'function') {
        try { window.onLocaleChanged(currentLocale); } catch (e) { console.error(e); }
    }
    return currentLocale;
}

// Kept for callers that still expect the old dynamic loader.
function loadLocale(locale) {
    return Promise.resolve(applyLanguage(locale));
}

// Export for global use
if (typeof window !== 'undefined') {
    window.t = t;
    window.initLocale = initLocale;
    window.getLocale = getLocale;
    window.updateTranslations = updateTranslations;
    window.applyLanguage = applyLanguage;
    window.loadLocale = loadLocale;
    window.isRTLLocale = function (locale) {
        return RTL_LOCALES.indexOf(locale || currentLocale) !== -1;
    };

    // Auto-update translations when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            initLocale(currentLocale);
            updateTranslations();
        });
    } else {
        initLocale(currentLocale);
        updateTranslations();
    }
}
