/* ---------------------------------------------------------------------------
   JRS shared NUI translation helper
   ---------------------------------------------------------------------------
   Canonical copy. Every NUI page that needs translating gets this file copied
   into its own html/ folder (CEF cannot reliably reach another resource's
   files, and there is no CDN inside the game), alongside:

       html/locales/en.js   ->  JrsI18n.register('en', { key: "text" })
       html/locales/ar.js   ->  JrsI18n.register('ar', { key: "نص" })

   Include order in the page:

       <script src="jrs-i18n.js"></script>
       <script src="locales/en.js"></script>
       <script src="locales/ar.js"></script>

   Mark up the page with data-i18n attributes:

       <h1 data-i18n="inventory.title">Inventory</h1>
       <input data-i18n-placeholder="search.hint">
       <div data-i18n-title="tooltip.sort"></div>

   The English text stays in the markup as the fallback, so the page still
   reads correctly if a pack fails to load.

   The client Lua pushes the player's language with

       SendNUIMessage({ type = 'jrsLanguage', language = JrsLang.Current() })

   which this file listens for. Nothing else is required.
   --------------------------------------------------------------------------- */

(function (global) {
    'use strict';

    var FALLBACK = 'en';
    var RTL = { ar: true };

    var packs = {};
    var current = FALLBACK;
    var listeners = [];

    function register(code, table) {
        if (!code || !table) return;
        packs[code] = Object.assign(packs[code] || {}, table);
        if (code === current) apply();
    }

    /** Look a key up in the active language, then English, then give back the
     *  fallback the caller supplied (usually the text already in the markup). */
    function t(key, fallback) {
        var pack = packs[current];
        if (pack && Object.prototype.hasOwnProperty.call(pack, key)) return pack[key];
        var base = packs[FALLBACK];
        if (base && Object.prototype.hasOwnProperty.call(base, key)) return base[key];
        return fallback !== undefined ? fallback : key;
    }

    /** printf-style, matching the Lua side so one key works in both. */
    function f(key, ...args) {
        var i = 0;
        return String(t(key)).replace(/%[0-9.]*[sdf]/g, function () {
            var value = args[i++];
            return value === undefined ? '' : String(value);
        });
    }

    /** True when some pack we hold actually defines this key.
     *
     *  A page may carry its own translation table alongside this one - the
     *  same data-i18n attributes, resolved by its own code. Writing those
     *  elements from here would replace that table's text with the English
     *  sitting in the markup, so an unknown key is left alone entirely. */
    function known(key) {
        if (!key) return false;
        var pack = packs[current];
        if (pack && Object.prototype.hasOwnProperty.call(pack, key)) return true;
        var base = packs[FALLBACK];
        return !!(base && Object.prototype.hasOwnProperty.call(base, key));
    }

    /* A label element often wraps live markup - a counter span, an input, a
       badge. Writing textContent replaces every child, so the counters and
       fields vanished the moment a translation landed. The label itself is
       carried by the element's own first text node, so rewrite only that node
       and leave the markup children in place. */
    var VOID_LABEL = { BR: 1, IMG: 1, HR: 1, INPUT: 1 };

    function labelNode(el) {
        for (var i = 0; i < el.childNodes.length; i++) {
            var node = el.childNodes[i];
            if (node.nodeType === 3 && node.nodeValue.trim() !== '') return node;
        }
        return null;
    }

    function writeLabel(el, text) {
        if (!el.firstElementChild) { el.textContent = text; return; }
        var node = labelNode(el);
        if (!node) { el.insertBefore(document.createTextNode(text), el.firstChild); return; }
        node.nodeValue = node.nodeValue.match(/^\s*/)[0] + text + node.nodeValue.match(/\s*$/)[0];
    }

    function applyTo(root) {
        (root || document).querySelectorAll('[data-i18n]').forEach(function (el) {
            var key = el.getAttribute('data-i18n');
            if (!known(key)) return;
            if (VOID_LABEL[el.tagName]) return;
            // The markup's own text is the fallback, so a key that is in the
            // English pack but missing from another language still reads.
            if (el.dataset.i18nDefault === undefined) {
                var own = el.firstElementChild ? labelNode(el) : null;
                el.dataset.i18nDefault = el.firstElementChild
                    ? (own ? own.nodeValue.trim() : '')
                    : el.textContent;
            }
            writeLabel(el, t(key, el.dataset.i18nDefault));
        });

        (root || document).querySelectorAll('[data-i18n-placeholder]').forEach(function (el) {
            var key = el.getAttribute('data-i18n-placeholder');
            if (!known(key)) return;
            if (el.dataset.i18nPlaceholderDefault === undefined) {
                el.dataset.i18nPlaceholderDefault = el.placeholder || '';
            }
            el.placeholder = t(key, el.dataset.i18nPlaceholderDefault);
        });

        (root || document).querySelectorAll('[data-i18n-title]').forEach(function (el) {
            var key = el.getAttribute('data-i18n-title');
            if (!known(key)) return;
            if (el.dataset.i18nTitleDefault === undefined) {
                el.dataset.i18nTitleDefault = el.title || '';
            }
            el.title = t(key, el.dataset.i18nTitleDefault);
        });
    }

    function apply() {
        applyTo(document);
        document.documentElement.setAttribute('lang', current);
        document.body && document.body.classList.toggle('jrs-rtl', RTL[current] === true);
        listeners.forEach(function (fn) {
            try { fn(current); } catch (e) { console.error('[jrs-i18n]', e); }
        });
    }

    function setLanguage(code) {
        if (!code || code === current) {
            if (code) apply();
            return current;
        }
        // Keep the requested language while its pack is still loading.
        current = code === 'ar' || code === 'en' ? code : FALLBACK;
        apply();
        return current;
    }

    /* -----------------------------------------------------------------------
       Universal Screen Resolution & Aspect Ratio Adaptation Engine
       -----------------------------------------------------------------------
       Automatically detects screen dimensions, calculates resolution scale,
       sets CSS variables on :root (--jrs-screen-scale, --jrs-s, --jrs-vw, --jrs-vh, etc.)
       and applies resolution classes (res-4k, res-1440p, res-1080p, res-720p,
       aspect-ultrawide, aspect-super-ultrawide).
       ----------------------------------------------------------------------- */
    function updateScreenMetrics() {
        var doc = document.documentElement;
        var body = document.body;
        if (!doc) return;

        var vw = Math.max(320, window.innerWidth || doc.clientWidth || 1920);
        var vh = Math.max(240, window.innerHeight || doc.clientHeight || 1080);
        var aspect = vw / Math.max(1, vh);

        // Baseline: 1080p (height 1080px).
        // 720p -> ~0.667 | 1080p -> 1.000 | 1440p (2K) -> ~1.333 | 2160p (4K UHD) -> 2.000
        var scale = Math.max(0.65, Math.min(2.6, vh / 1080));
        var safeCenterW = Math.min(vw, vh * (16 / 9) * 1.08);

        doc.style.setProperty('--jrs-screen-scale', String(Math.round(scale * 1000) / 1000));
        doc.style.setProperty('--jrs-s', String(Math.round(scale * 1000) / 1000));
        doc.style.setProperty('--jrs-vw', vw + 'px');
        doc.style.setProperty('--jrs-vh', vh + 'px');
        doc.style.setProperty('--jrs-aspect-ratio', String(Math.round(aspect * 100) / 100));
        doc.style.setProperty('--jrs-safe-center-w', Math.round(safeCenterW) + 'px');

        var target = body || doc;
        target.classList.toggle('res-4k', vh >= 1800);
        target.classList.toggle('res-1440p', vh >= 1200 && vh < 1800);
        target.classList.toggle('res-1080p', vh >= 900 && vh < 1200);
        target.classList.toggle('res-720p', vh < 900);
        target.classList.toggle('aspect-ultrawide', aspect >= 2.0 && aspect < 3.0);
        target.classList.toggle('aspect-super-ultrawide', aspect >= 3.0);
    }

    var resizeTimer = null;
    window.addEventListener('resize', function () {
        if (resizeTimer) clearTimeout(resizeTimer);
        resizeTimer = setTimeout(updateScreenMetrics, 30);
    });

    global.JrsI18n = {
        register: register,
        t: t,
        f: f,
        apply: apply,
        applyTo: applyTo,
        setLanguage: setLanguage,
        onChange: function (fn) { if (typeof fn === 'function') listeners.push(fn); },
        get language() { return current; },
        isRTL: function (code) { return RTL[code || current] === true; },
        updateScreenMetrics: updateScreenMetrics,
        get screenScale() { return Math.max(0.65, Math.min(2.6, (window.innerHeight || 1080) / 1080)); }
    };

    window.addEventListener('message', function (event) {
        var data = event.data || {};
        if (data.type === 'jrsLanguage' || data.action === 'jrsLanguage') {
            setLanguage(data.language);
        }
    });

    function ready() {
        updateScreenMetrics();
        apply();
        if (typeof GetParentResourceName === 'function' && typeof fetch === 'function') {
            fetch('https://' + GetParentResourceName() + '/jrsLanguageReady', {
                method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}'
            }).catch(function () {});
        }
    }
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', ready);
    } else {
        ready();
    }
}(window));
