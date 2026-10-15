/*
 * JRS controller support for NUI pages - Version 2.5.0 Full Freedom Edition
 *
 * Full gamepad mouse cursor, authentic JRS_STORE styled controls bar,
 * 3D preview rotation & zoom freedom, customizable button bindings & settings modal.
 */
(function () {
    'use strict';
    if (window.__jrsPad) return;

    var Z = 2147483646;
    var DEADZONE = 0.12;
    var BTN = ['a', 'b', 'x', 'y', 'up', 'down', 'left', 'right', 'lb', 'rb', 'lt', 'rt', 'start', 'select', 'l3', 'r3'];
    // jrs_stores artwork shipped in jrs_core (absolute: this script runs inside other resources' pages)
    var TEX = 'nui://jrs_core/html/storeui/';
    var ARROW = 'data:image/svg+xml,' + encodeURIComponent(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 30">' +
        '<path d="M2 2 L2 24 L8 18.5 L12 27.5 L15.6 26 L11.7 17.2 L19.5 17.2 Z" ' +
        'fill="#fff" stroke="#111" stroke-width="1.6" stroke-linejoin="round"/></svg>');

    // ----------------------------------------------------------- Configuration
    var DEFAULT_CFG = {
        speed: 1.0,
        scrollSpeed: 1.0,
        slowdown: 0.50, // 0 = off, 0.7 = light, 0.5 = medium, 0.3 = strong
        btnA: 'a',
        btnB: 'b',
        btnX: 'x',
        btnY: 'y',
        rotate3d: true,
        zoom3d: true,
        dblClick: true,
        alwaysShowHint: true,
        ringEnabled: true
    };

    var CFG = Object.assign({}, DEFAULT_CFG);

    function loadConfig() {
        try {
            var raw = localStorage.getItem('jrs_pad_config_v2');
            if (raw) {
                var d = JSON.parse(raw);
                for (var k in DEFAULT_CFG) {
                    if (d.hasOwnProperty(k)) CFG[k] = d[k];
                }
            }
        } catch (e) {}
    }

    function saveConfig() {
        try {
            localStorage.setItem('jrs_pad_config_v2', JSON.stringify(CFG));
        } catch (e) {}
    }

    loadConfig();

    var S = {
        active: false,
        x: window.innerWidth / 2,
        y: window.innerHeight / 2,
        placed: false,
        lx: 0, ly: 0, rx: 0, ry: 0,
        held: {},
        speed: 1,
        scrollSpeed: 1,
        lastFrame: 0,
        hoverEl: null,
        press: null,        // { el, x, y, moved, range }
        repeat: {},         // dpad auto-repeat timers
        wheelAt: 0,
        hintTimer: 0,
        kb: null,           // on-screen keyboard state
        settingsOpen: false,
        lastClickTime: 0,
        lastClickEl: null,
        lastOrbitAt: 0
    };

    // ------------------------------------------------------------------ DOM
    var root, cursorEl, ringEl, hintEl, styleEl, settingsEl;

    function ensureDom() {
        if (root && document.body && document.body.contains(root)) return;
        if (!document.body) return;
        if (!styleEl) {
            styleEl = document.createElement('style');
            styleEl.textContent = [
                '#jrs-pad-root{position:fixed;inset:0;pointer-events:none;z-index:' + Z + ';font-family:Georgia,Arial,sans-serif}',
                '#jrs-pad-cursor{position:fixed;left:0;top:0;width:24px;height:30px;margin:0;',
                'background:no-repeat 0 0/24px 30px url("' + ARROW + '");filter:drop-shadow(0 1px 3px rgba(0,0,0,.85));',
                'transform-origin:2px 2px;transition:transform .06s ease-out;will-change:transform;pointer-events:none;z-index:2147483647}',
                '#jrs-pad-cursor.jrs-pad-down{transform:scale(.82)}',
                'html.jrs-pad-on,html.jrs-pad-on *{cursor:none!important}',
                '#jrs-pad-ring{position:fixed;left:0;top:0;border:1px solid rgba(217,212,199,.9);border-radius:3px;',
                'box-shadow:0 0 0 1px rgba(0,0,0,.7),0 0 10px rgba(217,212,199,.28);display:none;pointer-events:none;transition:all .08s ease}',

                // jrs_stores skin (store-theme tokens: text #f4f0e7, muted #c3bdb1, accent #d9d4c7,
                // shared tab/panel artwork from html/storeui, same files jrs_stores ships)
                '#jrs-pad-hint{position:fixed;left:50%;bottom:12px;transform:translateX(-50%) translateY(10px);',
                'padding:6px 12px;border-radius:3px;color:#f4f0e7;font-size:12px;',
                'background:linear-gradient(rgba(10,10,10,.72),rgba(10,10,10,.72)),url("' + TEX + 'tab.png") center/100% 100% no-repeat,#0b0a09;',
                'font-family:Georgia,"Times New Roman",serif;letter-spacing:.25px;white-space:nowrap;',
                'border:1px solid rgba(255,255,255,.12);box-shadow:0 8px 24px rgba(0,0,0,.75);text-shadow:0 1px 2px #000;',
                'opacity:0;pointer-events:auto;transition:opacity .25s ease,transform .25s ease;display:flex;align-items:center;gap:8px;user-select:none;z-index:2147483645}',
                '#jrs-pad-hint.jrs-pad-show{opacity:1;transform:translateX(-50%) translateY(0)}',
                '.jrs-pad-item{display:inline-flex;align-items:center;gap:5px;color:#c3bdb1;font-size:12px;font-weight:700}',
                '.jrs-pad-badge{display:inline-flex;align-items:center;justify-content:center;min-width:20px;height:20px;',
                'padding:0 5px;border-radius:2px;background:url("' + TEX + 'tab.png") center/100% 100% no-repeat,#1a1816;color:#f4f0e7;',
                'border:1px solid rgba(255,255,255,.18);font-family:Georgia,serif;font-weight:800;font-size:11px;line-height:1;',
                'text-shadow:0 1px 2px #000}',
                '.jrs-pad-sep{width:1px;height:13px;background:rgba(255,255,255,.14)}',
                '.jrs-pad-cfg-btn{cursor:pointer;display:inline-flex;align-items:center;gap:5px;padding:2px 8px;border-radius:2px;',
                'background:url("' + TEX + 'tab.png") center/100% 100% no-repeat;border:1px solid rgba(255,255,255,.075);color:#f4f0e7;font-weight:700;transition:filter .15s ease,border-color .15s ease}',
                '.jrs-pad-cfg-btn:hover,.jrs-pad-cfg-btn.jrs-pad-hover{color:#fff;border-color:rgba(255,255,255,.2);filter:brightness(1.15)}',

                // Virtual On-Screen Keyboard - jrs_stores skin
                '#jrs-pad-kb{position:fixed;left:50%;bottom:60px;transform:translateX(-50%);pointer-events:auto;padding:12px 14px 12px;',
                'background:linear-gradient(rgba(8,8,8,.55),rgba(8,8,8,.55)),url("' + TEX + 'panel-background.png") center/cover no-repeat,#0b0a09;',
                'border:1px solid rgba(255,255,255,.12);border-radius:3px;',
                'box-shadow:0 14px 48px rgba(0,0,0,.85),0 0 0 1px rgba(0,0,0,.6);',
                'z-index:2147483646;min-width:520px;max-width:96vw;font-family:Georgia,"Times New Roman",serif}',
                '#jrs-pad-kb .jrs-kb-label{text-align:center;font-size:11px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;',
                'color:#8f887c;margin:0 0 9px;padding-bottom:7px;border-bottom:1px solid rgba(255,255,255,.08);user-select:none;text-shadow:0 1px 2px #000}',
                '#jrs-pad-kb .jrs-kb-preview{min-height:34px;max-width:100%;margin:0 0 10px;padding:7px 14px;border-radius:2px;',
                'background:linear-gradient(rgba(7,7,7,.73),rgba(7,7,7,.73)),url("' + TEX + 'tab.png") center/100% 100% no-repeat;',
                'color:#f4f0e7;font-size:16px;overflow:hidden;white-space:nowrap;',
                'text-overflow:ellipsis;border:1px solid rgba(255,255,255,.12);letter-spacing:.3px;',
                'direction:auto;text-align:start}',
                '#jrs-pad-kb .jrs-kb-row{display:flex;justify-content:center;gap:5px;margin:5px 0}',
                '#jrs-pad-kb .jrs-kb-key{min-width:40px;height:42px;padding:0 9px;border-radius:2px;',
                'background:url("' + TEX + 'tab.png") center/100% 100% no-repeat,#1a1816;color:#f4f0e7;font-size:17px;cursor:pointer;',
                'display:flex;align-items:center;justify-content:center;',
                'border:1px solid rgba(255,255,255,.075);text-shadow:0 1px 2px #000;box-shadow:none;',
                'transition:filter .07s ease,border-color .07s ease,color .07s ease,transform .07s ease;',
                'user-select:none;font-weight:700;letter-spacing:.3px}',
                '#jrs-pad-kb .jrs-kb-key:hover,#jrs-pad-kb .jrs-kb-key.jrs-pad-hover{',
                'color:#fff;border-color:rgba(255,255,255,.22);filter:brightness(1.18)}',
                '#jrs-pad-kb .jrs-kb-key:active,#jrs-pad-kb .jrs-kb-key.jrs-pad-active{',
                'color:#d9d4c7;transform:translateY(1px);filter:brightness(.85)}',
                '#jrs-pad-kb .jrs-kb-wide{min-width:160px;flex:1;max-width:220px}',
                '#jrs-pad-kb .jrs-kb-accent{color:#fff;border-color:rgba(217,212,199,.55);font-weight:800;font-size:15px;',
                'box-shadow:inset 0 0 0 1px rgba(217,212,199,.18)}',
                '#jrs-pad-kb .jrs-kb-accent:hover,#jrs-pad-kb .jrs-kb-accent.jrs-pad-hover{border-color:#d9d4c7;filter:brightness(1.25)}',
                '#jrs-pad-kb .jrs-kb-special{background:linear-gradient(rgba(10,10,10,.45),rgba(10,10,10,.45)),url("' + TEX + 'tab.png") center/100% 100% no-repeat,#141210;',
                'color:#c3bdb1;font-size:13px;letter-spacing:.5px}',
                '#jrs-pad-kb .jrs-kb-special:hover,#jrs-pad-kb .jrs-kb-special.jrs-pad-hover{color:#fff}',
                '#jrs-pad-kb .jrs-kb-on{color:#fff;text-decoration:underline;text-underline-offset:3px}',
                // Controller Settings Modal
                '#jrs-pad-settings{position:fixed;left:50%;top:50%;transform:translate(-50%,-50%) scale(.95);',
                'width:min(560px,94vw);max-height:86vh;overflow-y:auto;background:rgba(16,14,12,.98);border:1px solid rgba(214,170,92,.7);',
                'border-radius:10px;box-shadow:0 16px 48px rgba(0,0,0,.9), inset 0 1px 0 rgba(255,255,255,.12);color:#f4f0e7;',
                'font-family:Georgia,"Times New Roman",serif;padding:22px;z-index:2147483647;pointer-events:auto;opacity:0;',
                'visibility:hidden;transition:all .2s ease;scrollbar-width:thin;scrollbar-color:#d6aa5c #151310}',
                '#jrs-pad-settings.is-open{opacity:1;visibility:visible;transform:translate(-50%,-50%) scale(1)}',
                '.jrs-cfg-head{display:flex;align-items:center;justify-content:space-between;padding-bottom:12px;border-bottom:1px solid rgba(214,170,92,.35);margin-bottom:16px}',
                '.jrs-cfg-title{display:flex;align-items:center;gap:10px;font-size:17px;font-weight:700;color:#d6aa5c;letter-spacing:.3px}',
                '.jrs-cfg-close{background:transparent;border:0;color:#c8c1b3;font-size:22px;cursor:pointer;line-height:1;padding:2px 8px;border-radius:4px}',
                '.jrs-cfg-close:hover{color:#fff;background:rgba(255,255,255,.1)}',
                '.jrs-cfg-section{margin-bottom:18px;background:rgba(255,255,255,.025);border:1px solid rgba(214,170,92,.25);border-radius:8px;padding:12px 14px}',
                '.jrs-cfg-section h4{margin:0 0 10px;color:#d6aa5c;font-size:13px;text-transform:uppercase;letter-spacing:.5px;border-bottom:1px solid rgba(214,170,92,.15);padding-bottom:5px}',
                '.jrs-cfg-row{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:8px 0;font-size:13px}',
                '.jrs-cfg-row label{color:#ded7c8;flex:1}',
                '.jrs-cfg-row input[type="range"]{accent-color:#d6aa5c;width:150px;cursor:pointer}',
                '.jrs-cfg-val{min-width:40px;text-align:right;font-family:Arial,sans-serif;font-weight:700;color:#d6aa5c}',
                '.jrs-cfg-select{background:#231f1a;color:#f4f0e7;border:1px solid rgba(214,170,92,.45);border-radius:5px;padding:4px 10px;font-family:inherit;font-size:12px;outline:none;cursor:pointer}',
                '.jrs-cfg-check{display:flex;align-items:center;gap:8px;cursor:pointer;user-select:none;font-size:13px;margin:8px 0;color:#ded7c8}',
                '.jrs-cfg-check input{accent-color:#d6aa5c;width:16px;height:16px;cursor:pointer}',
                '.jrs-cfg-actions{display:flex;justify-content:space-between;gap:10px;margin-top:16px;padding-top:12px;border-top:1px solid rgba(214,170,92,.35)}',
                '.jrs-cfg-btn{padding:7px 18px;border-radius:5px;font-family:inherit;font-weight:700;font-size:13px;cursor:pointer;border:1px solid rgba(214,170,92,.5);transition:all .15s ease}',
                '.jrs-cfg-btn.reset{background:rgba(255,255,255,.06);color:#cfc7b8}',
                '.jrs-cfg-btn.save{background:linear-gradient(180deg,#c99f52 0%,#a37d38 100%);color:#100f0d;border-color:#d6aa5c}'
            ].join('');
            (document.head || document.documentElement).appendChild(styleEl);
        }
        root = document.createElement('div');
        root.id = 'jrs-pad-root';
        root.style.display = 'none';
        ringEl = document.createElement('div');
        ringEl.id = 'jrs-pad-ring';
        cursorEl = document.createElement('div');
        cursorEl.id = 'jrs-pad-cursor';
        hintEl = document.createElement('div');
        hintEl.id = 'jrs-pad-hint';
        settingsEl = document.createElement('div');
        settingsEl.id = 'jrs-pad-settings';

        root.appendChild(ringEl);
        root.appendChild(hintEl);
        root.appendChild(settingsEl);
        root.appendChild(cursorEl);
        document.body.appendChild(root);

        buildSettingsUI();
    }

    function isArabic() {
        var h = document.documentElement, b = document.body;
        return (h.lang || '').toLowerCase().indexOf('ar') === 0 || h.dir === 'rtl' ||
            (b && (b.dir === 'rtl' || b.classList.contains('jrs-rtl')));
    }

    // --------------------------------------------------- Hint Bar (JRS_STORE Style)
    function showHint() {
        ensureDom();
        if (!hintEl) return;
        var ar = isArabic();
        var items = ar
            ? [
                ['LS', 'تحريك'],
                [CFG.btnA.toUpperCase(), 'اختيار'],
                [CFG.btnB.toUpperCase(), 'رجوع'],
                [CFG.btnX.toUpperCase(), 'خيارات'],
                [CFG.btnY.toUpperCase(), 'كيبورد'],
                ['LB/RB', 'تبويبات'],
                ['RS', 'تمرير/3D']
            ]
            : [
                ['LS', 'Move'],
                [CFG.btnA.toUpperCase(), 'Select'],
                [CFG.btnB.toUpperCase(), 'Back'],
                [CFG.btnX.toUpperCase(), 'Options'],
                [CFG.btnY.toUpperCase(), 'Keyboard'],
                ['LB/RB', 'Tabs'],
                ['RS', 'Scroll/3D']
            ];

        hintEl.dir = ar ? 'rtl' : 'ltr';
        var html = items.map(function (i) {
            return '<span class="jrs-pad-item"><span class="jrs-pad-badge">' + i[0] + '</span><span>' + i[1] + '</span></span>';
        }).join('<span class="jrs-pad-sep"></span>');

        html += '<span class="jrs-pad-sep"></span>' +
            '<span class="jrs-pad-cfg-btn" id="jrsPadOpenCfg" title="' + (ar ? 'إعدادات الكنترولر (START)' : 'Controller Settings (START)') + '">' +
            '<span class="jrs-pad-badge" style="min-width:16px;height:16px;font-size:10px">⚙</span>' +
            '<span>' + (ar ? 'الإعدادات' : 'Settings') + '</span></span>';

        hintEl.innerHTML = html;
        var cfgBtn = hintEl.querySelector('#jrsPadOpenCfg');
        if (cfgBtn) {
            cfgBtn.onclick = function (e) { e.preventDefault(); e.stopPropagation(); toggleSettings(true); };
        }

        hintEl.classList.add('jrs-pad-show');
        clearTimeout(S.hintTimer);
        if (!CFG.alwaysShowHint) {
            S.hintTimer = setTimeout(function () { hintEl.classList.remove('jrs-pad-show'); }, 6000);
        }
    }

    // --------------------------------------------------- Controller Settings Modal
    function buildSettingsUI() {
        if (!settingsEl) return;
        var ar = isArabic();
        settingsEl.dir = ar ? 'rtl' : 'ltr';

        var slowdownOpts = [
            { val: 0, text: ar ? 'معطل (0%)' : 'Disabled (0%)' },
            { val: 0.70, text: ar ? 'خفيف (30%)' : 'Light (30%)' },
            { val: 0.50, text: ar ? 'متوسط (50% - افتراضي)' : 'Medium (50% - Default)' },
            { val: 0.30, text: ar ? 'قوي (70%)' : 'Strong (70%)' }
        ];

        var btnOpts = ['a', 'b', 'x', 'y', 'lb', 'rb', 'lt', 'rt'];

        var html = [
            '<div class="jrs-cfg-head">',
            '  <div class="jrs-cfg-title"><span>⚙</span><span>' + (ar ? 'إعدادات يد التحكم والتحكم الكامل' : 'Controller & Navigation Settings') + '</span></div>',
            '  <button class="jrs-cfg-close" id="jrsCfgCloseBtn">×</button>',
            '</div>',

            '<div class="jrs-cfg-section">',
            '  <h4>' + (ar ? 'الحساسية والسرعة' : 'Sensitivity & Speed') + '</h4>',
            '  <div class="jrs-cfg-row">',
            '    <label>' + (ar ? 'سرعة حركة السهم (Cursor Speed)' : 'Cursor Speed') + '</label>',
            '    <input type="range" id="cfgSpd" min="0.5" max="2.5" step="0.1" value="' + CFG.speed + '">',
            '    <span class="jrs-cfg-val" id="cfgSpdVal">' + CFG.speed.toFixed(1) + 'x</span>',
            '  </div>',
            '  <div class="jrs-cfg-row">',
            '    <label>' + (ar ? 'سرعة التمرير (Scroll Speed)' : 'Scroll Speed') + '</label>',
            '    <input type="range" id="cfgScr" min="0.5" max="2.5" step="0.1" value="' + CFG.scrollSpeed + '">',
            '    <span class="jrs-cfg-val" id="cfgScrVal">' + CFG.scrollSpeed.toFixed(1) + 'x</span>',
            '  </div>',
            '  <div class="jrs-cfg-row">',
            '    <label>' + (ar ? 'التباطؤ المغناطيسي فوق الأزرار' : 'Button Magnetism / Slowdown') + '</label>',
            '    <select class="jrs-cfg-select" id="cfgSlow">',
            slowdownOpts.map(function (o) {
                return '<option value="' + o.val + '"' + (Math.abs(CFG.slowdown - o.val) < 0.05 ? ' selected' : '') + '>' + o.text + '</option>';
            }).join(''),
            '    </select>',
            '  </div>',
            '</div>',

            '<div class="jrs-cfg-section">',
            '  <h4>' + (ar ? 'تخصيص أزرار الأفعال' : 'Button Remapping') + '</h4>',
            '  <div class="jrs-cfg-row">',
            '    <label>' + (ar ? 'زر النقر / الاختيار (Select / Click)' : 'Select / Click Button') + '</label>',
            '    <select class="jrs-cfg-select" id="cfgBtnA">',
            btnOpts.map(function (b) { return '<option value="' + b + '"' + (CFG.btnA === b ? ' selected' : '') + '>' + b.toUpperCase() + '</option>'; }).join(''),
            '    </select>',
            '  </div>',
            '  <div class="jrs-cfg-row">',
            '    <label>' + (ar ? 'زر الرجوع / الإلغاء (Back / Cancel)' : 'Back / Cancel Button') + '</label>',
            '    <select class="jrs-cfg-select" id="cfgBtnB">',
            btnOpts.map(function (b) { return '<option value="' + b + '"' + (CFG.btnB === b ? ' selected' : '') + '>' + b.toUpperCase() + '</option>'; }).join(''),
            '    </select>',
            '  </div>',
            '  <div class="jrs-cfg-row">',
            '    <label>' + (ar ? 'زر الخيارات / كليك يمين (Right Click)' : 'Right Click / Context Button') + '</label>',
            '    <select class="jrs-cfg-select" id="cfgBtnX">',
            btnOpts.map(function (b) { return '<option value="' + b + '"' + (CFG.btnX === b ? ' selected' : '') + '>' + b.toUpperCase() + '</option>'; }).join(''),
            '    </select>',
            '  </div>',
            '  <div class="jrs-cfg-row">',
            '    <label>' + (ar ? 'زر لوحة المفاتيح الافتراضية' : 'Virtual Keyboard Button') + '</label>',
            '    <select class="jrs-cfg-select" id="cfgBtnY">',
            btnOpts.map(function (b) { return '<option value="' + b + '"' + (CFG.btnY === b ? ' selected' : '') + '>' + b.toUpperCase() + '</option>'; }).join(''),
            '    </select>',
            '  </div>',
            '</div>',

            '<div class="jrs-cfg-section">',
            '  <h4>' + (ar ? 'حرية المعاينة واختصارات خاصة' : '3D Freedom & Shortcuts') + '</h4>',
            '  <label class="jrs-cfg-check">',
            '    <input type="checkbox" id="cfgRot3d"' + (CFG.rotate3d ? ' checked' : '') + '>',
            '    <span>' + (ar ? 'تدوير الأسلحة والمجسمات 3D بالعصا اليمنى (RS 360° Orbit)' : 'Rotate 3D weapons & models with Right Stick (RS)') + '</span>',
            '  </label>',
            '  <label class="jrs-cfg-check">',
            '    <input type="checkbox" id="cfgZoom3d"' + (CFG.zoom3d ? ' checked' : '') + '>',
            '    <span>' + (ar ? 'تكبير وتصغير المعاينات 3D بالزناد (LT / RT Zoom)' : 'Zoom 3D preview with Triggers (LT/RT)') + '</span>',
            '  </label>',
            '  <label class="jrs-cfg-check">',
            '    <input type="checkbox" id="cfgDblClick"' + (CFG.dblClick ? ' checked' : '') + '>',
            '    <span>' + (ar ? 'نقر مزدوج سريع بـ A لاستخدام الأغراض فوراً' : 'Quick double-tap A for instant use / equip') + '</span>',
            '  </label>',
            '  <label class="jrs-cfg-check">',
            '    <input type="checkbox" id="cfgAlwaysHint"' + (CFG.alwaysShowHint ? ' checked' : '') + '>',
            '    <span>' + (ar ? 'إبقاء شريط توجيهات الكنترولر ظاهراً دائماً' : 'Always keep bottom controller hint bar visible') + '</span>',
            '  </label>',
            '  <label class="jrs-cfg-check">',
            '    <input type="checkbox" id="cfgRing"' + (CFG.ringEnabled ? ' checked' : '') + '>',
            '    <span>' + (ar ? 'إطار التحديد الذهبي على الأزرار' : 'Golden button highlight ring') + '</span>',
            '  </label>',
            '</div>',

            '<div class="jrs-cfg-actions">',
            '  <button class="jrs-cfg-btn reset" id="jrsCfgResetBtn">' + (ar ? 'استعادة الافتراضي' : 'Reset Defaults') + '</button>',
            '  <button class="jrs-cfg-btn save" id="jrsCfgSaveBtn">' + (ar ? 'حفظ وتطبيق' : 'Save & Apply') + '</button>',
            '</div>'
        ].join('\n');

        settingsEl.innerHTML = html;

        // Bind settings events
        var spd = settingsEl.querySelector('#cfgSpd');
        var spdVal = settingsEl.querySelector('#cfgSpdVal');
        if (spd && spdVal) {
            spd.oninput = function () { spdVal.textContent = parseFloat(spd.value).toFixed(1) + 'x'; };
        }

        var scr = settingsEl.querySelector('#cfgScr');
        var scrVal = settingsEl.querySelector('#cfgScrVal');
        if (scr && scrVal) {
            scr.oninput = function () { scrVal.textContent = parseFloat(scr.value).toFixed(1) + 'x'; };
        }

        var closeBtn = settingsEl.querySelector('#jrsCfgCloseBtn');
        if (closeBtn) closeBtn.onclick = function (e) { e.preventDefault(); toggleSettings(false); };

        var resetBtn = settingsEl.querySelector('#jrsCfgResetBtn');
        if (resetBtn) {
            resetBtn.onclick = function (e) {
                e.preventDefault();
                CFG = Object.assign({}, DEFAULT_CFG);
                saveConfig();
                buildSettingsUI();
                showHint();
            };
        }

        var saveBtn = settingsEl.querySelector('#jrsCfgSaveBtn');
        if (saveBtn) {
            saveBtn.onclick = function (e) {
                e.preventDefault();
                applySettingsFromUI();
                saveConfig();
                toggleSettings(false);
                showHint();
            };
        }
    }

    function applySettingsFromUI() {
        if (!settingsEl) return;
        var spd = settingsEl.querySelector('#cfgSpd');
        if (spd) CFG.speed = parseFloat(spd.value) || 1.0;
        var scr = settingsEl.querySelector('#cfgScr');
        if (scr) CFG.scrollSpeed = parseFloat(scr.value) || 1.0;
        var slw = settingsEl.querySelector('#cfgSlow');
        if (slw) CFG.slowdown = parseFloat(slw.value);
        var bA = settingsEl.querySelector('#cfgBtnA');
        if (bA) CFG.btnA = bA.value;
        var bB = settingsEl.querySelector('#cfgBtnB');
        if (bB) CFG.btnB = bB.value;
        var bX = settingsEl.querySelector('#cfgBtnX');
        if (bX) CFG.btnX = bX.value;
        var bY = settingsEl.querySelector('#cfgBtnY');
        if (bY) CFG.btnY = bY.value;
        var r3d = settingsEl.querySelector('#cfgRot3d');
        if (r3d) CFG.rotate3d = r3d.checked;
        var z3d = settingsEl.querySelector('#cfgZoom3d');
        if (z3d) CFG.zoom3d = z3d.checked;
        var dc = settingsEl.querySelector('#cfgDblClick');
        if (dc) CFG.dblClick = dc.checked;
        var ah = settingsEl.querySelector('#cfgAlwaysHint');
        if (ah) CFG.alwaysShowHint = ah.checked;
        var rng = settingsEl.querySelector('#cfgRing');
        if (rng) CFG.ringEnabled = rng.checked;
    }

    function toggleSettings(open) {
        ensureDom();
        if (!settingsEl) return;
        if (typeof open !== 'boolean') open = !S.settingsOpen;
        S.settingsOpen = open;
        if (open) {
            buildSettingsUI();
            settingsEl.classList.add('is-open');
            var firstInput = settingsEl.querySelector('input, select, button');
            if (firstInput) {
                var r = firstInput.getBoundingClientRect();
                moveTo(r.left + r.width / 2, r.top + r.height / 2);
            }
        } else {
            settingsEl.classList.remove('is-open');
        }
    }

    // ------------------------------------------------------- hover styling
    var mirrored = typeof WeakSet === 'function' ? new WeakSet() : null;
    var PSEUDO_RE = /:(hover|active)(?![\w-])/g;

    function mirrorRules(list) {
        for (var i = list.length - 1; i >= 0; i--) {
            var rule = list[i];
            if (rule.cssRules && !rule.selectorText) { mirrorRules(rule.cssRules); continue; }
            var sel = rule.selectorText;
            if (!sel || sel.indexOf(':hover') === -1 && sel.indexOf(':active') === -1) continue;
            var twin = sel.replace(PSEUDO_RE, function (_, p) { return '.jrs-pad-' + p; });
            try {
                (rule.parentRule || rule.parentStyleSheet).insertRule(twin + '{' + rule.style.cssText + '}', i + 1);
            } catch (e) { /* selector the engine rejects: skip */ }
        }
    }

    function mirrorHoverStyles() {
        if (!mirrored) return;
        var sheets = document.styleSheets;
        for (var i = 0; i < sheets.length; i++) {
            var sheet = sheets[i];
            if (mirrored.has(sheet) || sheet.ownerNode === styleEl) continue;
            var rules;
            try { rules = sheet.cssRules; } catch (e) { continue; } // cross-origin
            if (!rules) continue;
            mirrored.add(sheet);
            mirrorRules(rules);
        }
    }

    var observer = null;
    function observeStyles() {
        if (observer || typeof MutationObserver !== 'function') return;
        try {
            observer = new MutationObserver(function () {
                if (S.active) mirrorHoverStyles();
            });
            var target = document.head || document.documentElement;
            if (target) observer.observe(target, { childList: true, subtree: true });
        } catch (e) { /* ignore */ }
    }

    // :hover / :active apply to the element and every ancestor.
    // Allow keyboard keys and settings elements to receive pad-hover/pad-active.
    function markChain(el, cls, on) {
        for (; el && el.nodeType === 1; el = el.parentElement) {
            // Stop at our non-interactive overlay elements (cursor, ring, hint bar)
            // but allow keyboard and settings to be marked
            if (isOurs(el)) {
                var inKb  = S.kb && S.kb.el && S.kb.el.contains(el);
                var inCfg = S.settingsOpen && settingsEl && settingsEl.contains(el);
                if (!inKb && !inCfg) return;
            }
            el.classList.toggle(cls, on);
        }
    }


    // ------------------------------------------------------------- helpers
    function isOurs(el) {
        return !!(el && root && (el === root || root.contains(el)));
    }

    function elementAt(x, y) {
        var el = document.elementFromPoint(x, y);
        // Allow events on keyboard keys and settings modal, but not cursor/ring/hint
        if (isOurs(el)) {
            if (S.kb && S.kb.el.contains(el)) return el;
            if (S.settingsOpen && settingsEl && settingsEl.contains(el)) return el;
            return null;
        }
        return el;
    }


    var TEXT_TYPES = { text: 1, search: 1, password: 1, email: 1, number: 1, tel: 1, url: 1, '': 1 };
    function isTextField(el) {
        if (!el) return false;
        if (el.isContentEditable) return true;
        if (el.tagName === 'TEXTAREA') return !el.readOnly && !el.disabled;
        if (el.tagName === 'INPUT') return TEXT_TYPES[(el.getAttribute('type') || '').toLowerCase()] === 1 && !el.readOnly && !el.disabled;
        return false;
    }

    var CLICK_TAGS = { BUTTON: 1, A: 1, INPUT: 1, SELECT: 1, TEXTAREA: 1, LABEL: 1, SUMMARY: 1, OPTION: 1 };
    var CLICK_ROLES = { button: 1, tab: 1, link: 1, option: 1, menuitem: 1, checkbox: 1, radio: 1, 'switch': 1, slider: 1, listitem: 0 };
    function isClickable(el) {
        if (!el || el.nodeType !== 1 || el === document.body || el === document.documentElement) return false;
        if (el.disabled) return false;
        if (CLICK_TAGS[el.tagName]) return true;
        if (el.isContentEditable) return true;
        if (el.hasAttribute('data-k') || el.hasAttribute('data-action') || el.hasAttribute('data-tab') || el.hasAttribute('data-store-buy') || el.classList.contains('bm-tab') || el.classList.contains('action-card') || el.classList.contains('jrs-kb-key') || el.classList.contains('jrs-cfg-btn') || el.classList.contains('jrs-pad-cfg-btn')) return true;
        var role = el.getAttribute('role');
        if (role && CLICK_ROLES[role] === 1) return true;
        if (typeof el.onclick === 'function' || el.hasAttribute('onclick')) return true;
        var ti = el.getAttribute('tabindex');
        if (ti !== null && ti !== '-1') return true;
        if (el.draggable) return true;
        var cs = window.getComputedStyle(el);
        return cs.cursor === 'pointer';
    }

    function clickableAncestor(el) {
        for (var i = 0; el && i < 8; i++, el = el.parentElement) {
            if (isClickable(el)) return el;
        }
        return null;
    }

    function visibleRect(el) {
        var r = el.getBoundingClientRect();
        if (r.width < 3 || r.height < 3) return null;
        if (r.bottom < 0 || r.right < 0 || r.top > window.innerHeight || r.left > window.innerWidth) return null;
        var cs = window.getComputedStyle(el);
        if (cs.visibility === 'hidden' || cs.pointerEvents === 'none' || parseFloat(cs.opacity) < 0.05) return null;
        return r;
    }

    function scrollableAncestor(el, axis) {
        for (; el && el !== document.documentElement; el = el.parentElement) {
            if (el.nodeType !== 1 || isOurs(el)) continue;
            var cs = window.getComputedStyle(el);
            var ov = axis === 'x' ? cs.overflowX : cs.overflowY;
            if ((ov === 'auto' || ov === 'scroll' || ov === 'overlay') &&
                (axis === 'x' ? el.scrollWidth > el.clientWidth + 1 : el.scrollHeight > el.clientHeight + 1)) {
                return el;
            }
        }
        var se = document.scrollingElement || document.documentElement;
        if (axis === 'x' ? se.scrollWidth > se.clientWidth + 1 : se.scrollHeight > se.clientHeight + 1) return se;
        return null;
    }

    function mouseInit(x, y, button, buttons, related) {
        return {
            bubbles: true, cancelable: true, composed: true, view: window,
            clientX: x, clientY: y, screenX: x, screenY: y, pageX: x, pageY: y,
            button: button || 0, buttons: buttons || 0, detail: 1, relatedTarget: related || null
        };
    }

    function fireMouse(el, type, x, y, button, buttons, related) {
        if (!el) return true;
        var init = mouseInit(x, y, button, buttons, related);
        var ev;
        if (type.indexOf('pointer') === 0 && typeof PointerEvent === 'function') {
            init.pointerId = 1; init.pointerType = 'mouse'; init.isPrimary = true;
            ev = new PointerEvent(type, init);
        } else {
            ev = new MouseEvent(type, init);
        }
        return el.dispatchEvent(ev);
    }

    var KEYCODES = { Escape: 27, Enter: 13, Backspace: 8, Tab: 9, PageUp: 33, PageDown: 34, ArrowUp: 38, ArrowDown: 40, ArrowLeft: 37, ArrowRight: 39, q: 81, e: 69 };
    function fireKey(target, key, types) {
        target = target || document.activeElement || document.body || document;
        var code = KEYCODES[key] || (key.length === 1 ? key.toUpperCase().charCodeAt(0) : 0);
        (types || ['keydown', 'keyup']).forEach(function (t) {
            var ev = new KeyboardEvent(t, {
                key: key, code: key.length === 1 ? 'Key' + key.toUpperCase() : key,
                bubbles: true, cancelable: true, composed: true, view: window
            });
            try {
                Object.defineProperty(ev, 'keyCode', { get: function () { return code; } });
                Object.defineProperty(ev, 'which', { get: function () { return code; } });
                Object.defineProperty(ev, 'charCode', { get: function () { return t === 'keypress' ? code : 0; } });
            } catch (e) { /* ignore */ }
            target.dispatchEvent(ev);
        });
    }

    function setNativeValue(el, value) {
        var proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype
            : el.tagName === 'SELECT' ? HTMLSelectElement.prototype : HTMLInputElement.prototype;
        var desc = Object.getOwnPropertyDescriptor(proto, 'value');
        if (desc && desc.set) desc.set.call(el, value); else el.value = value;
        // Fire both input (React) and change (Vue/standard) so all frameworks update
        el.dispatchEvent(new Event('input',  { bubbles: true, cancelable: true }));
        el.dispatchEvent(new Event('change', { bubbles: true, cancelable: true }));
    }


    // -------------------------------------------------------------- cursor
    function clamp(v, a, b) { return v < a ? a : (v > b ? b : v); }

    function curve(v) {
        var a = Math.abs(v);
        if (a < DEADZONE) return 0;
        var n = (a - DEADZONE) / (1 - DEADZONE);
        return (v < 0 ? -1 : 1) * n * n;
    }

    function render() {
        if (!cursorEl) return;
        cursorEl.style.left = S.x + 'px';
        cursorEl.style.top = S.y + 'px';
        var el = elementAt(S.x, S.y);
        var c = clickableAncestor(el);
        var r = c && c.getBoundingClientRect();
        S.overClickable = !!(r && r.width > 2 && r.height > 2 && r.width < window.innerWidth * 0.95);
        if (S.overClickable && CFG.ringEnabled) {
            ringEl.style.display = 'block';
            ringEl.style.left = (r.left - 3) + 'px';
            ringEl.style.top = (r.top - 3) + 'px';
            ringEl.style.width = (r.width + 2) + 'px';
            ringEl.style.height = (r.height + 2) + 'px';
        } else {
            ringEl.style.display = 'none';
        }
    }

    function updateHover(moved) {
        var el = elementAt(S.x, S.y);
        var buttons = S.press ? 1 : 0;
        if (el !== S.hoverEl) {
            var old = S.hoverEl;
            if (old) markChain(old, 'jrs-pad-hover', false);
            if (el) markChain(el, 'jrs-pad-hover', true);
            if (old && document.contains(old)) {
                fireMouse(old, 'pointerout', S.x, S.y, 0, buttons, el);
                fireMouse(old, 'mouseout', S.x, S.y, 0, buttons, el);
                if (!el || !old.contains(el)) {
                    old.dispatchEvent(new MouseEvent('mouseleave', mouseInit(S.x, S.y, 0, buttons, el)));
                }
            }
            if (el) {
                fireMouse(el, 'pointerover', S.x, S.y, 0, buttons, old);
                fireMouse(el, 'mouseover', S.x, S.y, 0, buttons, old);
                if (!old || !el.contains(old)) {
                    el.dispatchEvent(new MouseEvent('mouseenter', mouseInit(S.x, S.y, 0, buttons, old)));
                }
            }
            S.hoverEl = el;
        }
        if (moved) {
            if (el) {
                fireMouse(el, 'pointermove', S.x, S.y, 0, buttons);
                fireMouse(el, 'mousemove', S.x, S.y, 0, buttons);
            } else {
                fireMouse(document.body, 'mousemove', S.x, S.y, 0, buttons);
            }
        }
    }

    function moveTo(x, y) {
        S.x = clamp(x, 0, window.innerWidth - 1);
        S.y = clamp(y, 0, window.innerHeight - 1);
        S.placed = true;
        if (S.press) {
            if (Math.abs(S.x - S.press.x) + Math.abs(S.y - S.press.y) > 6) S.press.moved = true;
            if (S.press.range) setRangeFromX(S.press.el, S.x);
        }
        updateHover(true);
        render();
    }

    var ticker = 0;
    function startTicker() {
        if (!ticker) ticker = setInterval(function () { frame(performance.now()); }, 16);
    }
    function stopTicker() {
        if (ticker) { clearInterval(ticker); ticker = 0; }
    }

    function frame(t) {
        if (!S.active) return;
        var dt = S.lastFrame ? Math.min(0.05, (t - S.lastFrame) / 1000) : 0.016;
        S.lastFrame = t;
        var scale = Math.max(0.6, window.innerWidth / 1920);

        var mx = curve(S.lx), my = curve(S.ly);
        if (mx || my) {
            var slowdownMult = (S.overClickable && CFG.slowdown > 0) ? CFG.slowdown : 1.0;
            var sp = 1250 * scale * S.speed * CFG.speed * dt * slowdownMult;
            moveTo(S.x + mx * sp, S.y + my * sp);
        }

        var sy = curve(S.ry), sx = curve(S.rx);
        if (sy || sx) {
            // Check if Right Stick should rotate 3D preview
            var rotated = handle3DOrbit(sx, sy, dt);
            if (!rotated) {
                scrollBy(sx, sy, dt, scale);
            }
        }

        dpadRepeat(t);
    }

    // ------------------------------------------------ 3D Preview Freedom
    function find3DPreviewSurface() {
        return document.querySelector(
            '.weapon-preview-surface, #weaponPreviewSurface, #storePreviewZone, .store-preview-zone, .preview-stage, canvas, [data-preview-surface]'
        );
    }

    function handle3DOrbit(sx, sy, dt) {
        if (!CFG.rotate3d) return false;
        var surface = find3DPreviewSurface();
        if (!surface) return false;

        // If cursor is over preview or right half of screen when preview exists
        var r = surface.getBoundingClientRect();
        var inPreviewArea = (S.x >= r.left && S.x <= r.right && S.y >= r.top && S.y <= r.bottom) ||
            (r.width > 200 && S.x > window.innerWidth * 0.42);

        if (!inPreviewArea) return false;

        // Smooth orbit dispatch
        var dx = Math.round(sx * 28);
        var dy = Math.round(sy * 28);

        if (dx || dy) {
            // Check if page has built-in rotation queue
            if (typeof window.queueCameraMotion === 'function') {
                window.queueCameraMotion('rotate', dx, dy);
                return true;
            }

            // Or dispatch pointermove on surface
            var target = surface.querySelector('.weapon-preview-surface') || surface;
            var cx = r.left + r.width / 2;
            var cy = r.top + r.height / 2;
            fireMouse(target, 'pointerdown', cx, cy, 0, 1);
            fireMouse(target, 'pointermove', cx + dx, cy + dy, 0, 1);
            fireMouse(target, 'pointerup', cx + dx, cy + dy, 0, 0);

            // Or trigger direct rotate buttons if present in weapons store
            var now = performance.now();
            if (now - S.lastOrbitAt > 110) {
                S.lastOrbitAt = now;
                if (dx > 8) { var bR = document.getElementById('storeRotateRight'); if (bR) bR.click(); }
                else if (dx < -8) { var bL = document.getElementById('storeRotateLeft'); if (bL) bL.click(); }
                if (dy > 8) { var bD = document.getElementById('storeRotateDown'); if (bD) bD.click(); }
                else if (dy < -8) { var bU = document.getElementById('storeRotateUp'); if (bU) bU.click(); }
            }
            return true;
        }
        return false;
    }

    function scrollBy(sx, sy, dt, scale) {
        var el = elementAt(S.x, S.y) || document.body;
        var amount = 1100 * scale * S.scrollSpeed * CFG.scrollSpeed * dt;
        var vs = sy ? scrollableAncestor(el, 'y') : null;
        var hs = sx ? scrollableAncestor(el, 'x') : null;
        if (vs || hs) {
            if (vs) vs.scrollTop += sy * amount;
            if (hs) hs.scrollLeft += sx * amount;
            updateHover(false);
            render();
            return;
        }

        var now = performance.now();
        if (now - S.wheelAt < 120) return;
        S.wheelAt = now;
        var init = mouseInit(S.x, S.y);
        init.deltaY = sy ? (sy > 0 ? 100 : -100) : 0;
        init.deltaX = sx ? (sx > 0 ? 100 : -100) : 0;
        init.deltaMode = 0;
        el.dispatchEvent(new WheelEvent('wheel', init));
        el.dispatchEvent(new WheelEvent('mousewheel', init));
    }

    // ------------------------------------------------------------- actions
    function rangeInput(el) {
        return el && el.tagName === 'INPUT' && (el.getAttribute('type') || '').toLowerCase() === 'range' ? el : null;
    }

    function setRangeFromX(el, x) {
        var r = el.getBoundingClientRect();
        var min = parseFloat(el.min || 0), max = parseFloat(el.max || 100), step = parseFloat(el.step || 1) || 1;
        var ratio = clamp((x - r.left) / Math.max(1, r.width), 0, 1);
        if (window.getComputedStyle(el).direction === 'rtl') ratio = 1 - ratio;
        var v = min + Math.round((ratio * (max - min)) / step) * step;
        if (String(v) !== el.value) setNativeValue(el, String(clamp(v, min, max)));
    }

    function stepRange(el, dir) {
        var step = parseFloat(el.step || 1) || 1;
        var v = clamp(parseFloat(el.value || 0) + dir * step, parseFloat(el.min || 0), parseFloat(el.max || 100));
        setNativeValue(el, String(v));
        el.dispatchEvent(new Event('change', { bubbles: true }));
    }

    function cycleSelect(el, dir) {
        var n = el.options.length;
        if (!n) return;
        var i = el.selectedIndex;
        for (var k = 0; k < n; k++) {
            i = (i + dir + n) % n;
            if (!el.options[i].disabled) break;
        }
        el.selectedIndex = i;
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
    }

    function pressA() {
        var el = elementAt(S.x, S.y);
        if (!el) return;
        var inKb = S.kb && S.kb.el.contains(el);
        var inCfg = S.settingsOpen && settingsEl && settingsEl.contains(el);
        cursorEl && cursorEl.classList.add('jrs-pad-down');
        markChain(el, 'jrs-pad-active', true);
        fireMouse(el, 'pointerdown', S.x, S.y, 0, 1);
        fireMouse(el, 'mousedown', S.x, S.y, 0, 1);
        var target = clickableAncestor(el) || el;
        var range = rangeInput(target);
        if (!inKb && !inCfg && typeof target.focus === 'function' && (CLICK_TAGS[target.tagName] || target.getAttribute('tabindex') !== null)) {
            try { target.focus({ preventScroll: true }); } catch (e) { /* ignore */ }
        }
        if (range) setRangeFromX(range, S.x);
        S.press = { el: el, target: target, x: S.x, y: S.y, moved: false, range: range };
    }

    function releaseA() {
        cursorEl && cursorEl.classList.remove('jrs-pad-down');
        var p = S.press;
        S.press = null;
        if (!p) return;
        markChain(p.el, 'jrs-pad-active', false);
        var el = elementAt(S.x, S.y) || p.el;
        fireMouse(el, 'pointerup', S.x, S.y, 0, 0);
        fireMouse(el, 'mouseup', S.x, S.y, 0, 0);
        if (p.range) {
            p.range.dispatchEvent(new Event('change', { bubbles: true }));
            return;
        }
        if (p.moved) return; // it was a drag
        var t = p.target;
        if (t && t.tagName === 'SELECT') { cycleSelect(t, 1); return; }
        fireMouse(p.el, 'click', S.x, S.y, 0, 0);

        // Native double-click detection
        if (CFG.dblClick) {
            var now = performance.now();
            if (S.lastClickEl === p.el && (now - S.lastClickTime) < 360) {
                fireMouse(p.el, 'dblclick', S.x, S.y, 0, 0);
                S.lastClickTime = 0;
                S.lastClickEl = null;
            } else {
                S.lastClickTime = now;
                S.lastClickEl = p.el;
            }
        }

        if (isTextField(t) && !(S.kb && S.kb.el.contains(t))) openKeyboard(t);
    }

    function pressX() {
        var el = elementAt(S.x, S.y);
        if (!el) return;
        var t = clickableAncestor(el);
        if (t && t.tagName === 'SELECT') { cycleSelect(t, -1); return; }
        fireMouse(el, 'pointerdown', S.x, S.y, 2, 2);
        fireMouse(el, 'mousedown', S.x, S.y, 2, 2);
        fireMouse(el, 'pointerup', S.x, S.y, 2, 0);
        fireMouse(el, 'mouseup', S.x, S.y, 2, 0);
        fireMouse(el, 'contextmenu', S.x, S.y, 2, 0);
    }

    function pressB() {
        if (S.settingsOpen) { toggleSettings(false); return; }
        if (S.kb) { closeKeyboard(false); return; }

        if (document.activeElement && isTextField(document.activeElement)) {
            try { document.activeElement.blur(); } catch (e) {}
        }

        // Close any active overlays/modals in base menu or store first
        var openModals = document.querySelectorAll('#storeRulesOverlay:not([hidden]), #storeDetailOverlay:not([hidden]), #topupPanel:not([hidden]), #dailyOverlay:not([hidden]), .wpick-overlay:not([hidden]), .bm-modal:not([hidden])');
        for (var m = 0; m < openModals.length; m++) {
            if (openModals[m].offsetWidth > 0 || openModals[m].offsetHeight > 0) {
                var closeM = openModals[m].querySelector('.close-button, .btn-close, .panel-close, [data-action="close"]');
                if (closeM) { closeM.click(); return; }
            }
        }

        // Base Menu close button
        var bmClose = document.getElementById('bmClose');
        if (bmClose && (bmClose.offsetWidth > 0 || bmClose.offsetHeight > 0)) {
            bmClose.click();
            return;
        }

        fireKey(document.activeElement && document.activeElement !== document.body ? document.activeElement : document.body, 'Escape');
    }

    function pressY() {
        if (S.settingsOpen) { toggleSettings(false); return; }
        var a = document.activeElement;
        if (isTextField(a)) { openKeyboard(a); return; }
        var under = clickableAncestor(elementAt(S.x, S.y));
        if (isTextField(under)) {
            try { under.focus({ preventScroll: true }); } catch (e) { /* ignore */ }
            openKeyboard(under);
            return;
        }
        fireKey(a && a !== document.body ? a : document.body, 'Enter', ['keydown', 'keypress', 'keyup']);
    }

    // Spatial navigation: jump the cursor to the nearest clickable in a direction.
    function candidates() {
        var scope = S.settingsOpen ? settingsEl : (S.kb ? S.kb.el : document.body);
        var all = scope.getElementsByTagName('*');
        var out = [];
        var limit = Math.min(all.length, 5000);
        for (var i = 0; i < limit; i++) {
            var el = all[i];
            if (!S.settingsOpen && !S.kb && isOurs(el)) continue;
            if (!isClickable(el)) continue;
            var p = el.parentElement;
            if (p && p !== scope && isClickable(p)) {
                var pr = p.getBoundingClientRect(), er = el.getBoundingClientRect();
                if (pr.width * pr.height <= er.width * er.height * 1.6) continue;
            }
            var r = visibleRect(el);
            if (r) out.push({ el: el, r: r });
        }
        return out;
    }

    function navigate(dir) {
        var focusedRange = rangeInput(document.activeElement);
        if (focusedRange && (dir === 'left' || dir === 'right') && !S.kb) {
            var d = dir === 'right' ? 1 : -1;
            if (window.getComputedStyle(focusedRange).direction === 'rtl') d = -d;
            stepRange(focusedRange, d);
            return;
        }
        var list = candidates();
        var cx = S.x, cy = S.y;
        var cur = clickableAncestor(elementAt(cx, cy));
        var best = null, bestScore = Infinity;
        for (var i = 0; i < list.length; i++) {
            var c = list[i];
            if (c.el === cur) continue;
            var x = c.r.left + c.r.width / 2, y = c.r.top + c.r.height / 2;
            var dx = x - cx, dy = y - cy, primary, secondary;
            if (dir === 'up') { primary = -dy; secondary = Math.abs(dx); }
            else if (dir === 'down') { primary = dy; secondary = Math.abs(dx); }
            else if (dir === 'left') { primary = -dx; secondary = Math.abs(dy); }
            else { primary = dx; secondary = Math.abs(dy); }
            if (primary <= 4) continue;
            var score = primary + secondary * 2.2;
            if (score < bestScore) { bestScore = score; best = c; }
        }
        if (best) {
            try { best.el.scrollIntoView({ block: 'nearest', inline: 'nearest' }); } catch (e) { /* ignore */ }
            var r = best.el.getBoundingClientRect();
            moveTo(r.left + r.width / 2, r.top + r.height / 2);
            return;
        }
        var vert = dir === 'up' || dir === 'down';
        var s = scrollableAncestor(elementAt(cx, cy) || document.body, vert ? 'y' : 'x');
        if (s) {
            if (vert) s.scrollTop += (dir === 'down' ? 1 : -1) * s.clientHeight * 0.6;
            else s.scrollLeft += (dir === 'right' ? 1 : -1) * s.clientWidth * 0.6;
            render();
        }
    }

    function dpadRepeat(t) {
        ['up', 'down', 'left', 'right'].forEach(function (d) {
            var r = S.repeat[d];
            if (!r || !S.held[d]) return;
            if (t - r.since > 380 && t - r.last > 110) { r.last = t; navigate(d); }
        });
    }

    var TAB_SELECTOR = '[role="tab"],.tab,.tabs>*,.tab-btn,.tab-button,.nav-tab,.nav-item,.category,.category-btn,.cat,.cat-btn,[data-tab],[data-category]';
    function isActiveTab(el) {
        return el.classList.contains('active') || el.classList.contains('selected') || el.classList.contains('current') ||
            el.classList.contains('is-active') || el.getAttribute('aria-selected') === 'true';
    }

    function switchTab(dir) {
        // First-class support for JRS Base Menu (jrs_pausemenu)
        var bmNav = document.getElementById('bmTabs');
        if (bmNav && bmNav.offsetWidth > 0) {
            var bmTabs = Array.prototype.filter.call(bmNav.querySelectorAll('.bm-tab'), function (el) {
                return visibleRect(el);
            });
            if (bmTabs.length >= 2) {
                var curIdx = -1;
                for (var j = 0; j < bmTabs.length; j++) {
                    if (isActiveTab(bmTabs[j])) { curIdx = j; break; }
                }
                var nextIdx = ((curIdx < 0 ? 0 : curIdx) + dir + bmTabs.length) % bmTabs.length;
                var targetTab = bmTabs[nextIdx];
                var rBm = targetTab.getBoundingClientRect();
                var xBm = rBm.left + rBm.width / 2, yBm = rBm.top + rBm.height / 2;
                fireMouse(targetTab, 'pointerdown', xBm, yBm, 0, 1);
                fireMouse(targetTab, 'mousedown', xBm, yBm, 0, 1);
                fireMouse(targetTab, 'pointerup', xBm, yBm, 0, 0);
                fireMouse(targetTab, 'mouseup', xBm, yBm, 0, 0);
                fireMouse(targetTab, 'click', xBm, yBm, 0, 0);
                try { targetTab.click(); } catch (e) {}
                moveTo(xBm, yBm);
                return;
            }
        }

        var tabs = Array.prototype.filter.call(document.querySelectorAll(TAB_SELECTOR), function (el) {
            return !isOurs(el) && visibleRect(el);
        });
        if (tabs.length >= 2) {
            var i = -1;
            for (var k = 0; k < tabs.length; k++) { if (isActiveTab(tabs[k])) { i = k; break; } }
            var isHoriz = Math.abs(tabs[0].getBoundingClientRect().top - tabs[1].getBoundingClientRect().top) < 18;
            if (isArabic() && isHoriz) dir = -dir;
            var next = tabs[(i + dir + tabs.length) % tabs.length];
            var r = next.getBoundingClientRect();
            var x = r.left + r.width / 2, y = r.top + r.height / 2;
            fireMouse(next, 'pointerdown', x, y, 0, 1);
            fireMouse(next, 'mousedown', x, y, 0, 1);
            fireMouse(next, 'pointerup', x, y, 0, 0);
            fireMouse(next, 'mouseup', x, y, 0, 0);
            fireMouse(next, 'click', x, y, 0, 0);
            try { next.click(); } catch (e) {}
            moveTo(x, y);
            return;
        }
        fireKey(document.activeElement || document.body, dir < 0 ? 'q' : 'e');
    }

    function pageScroll(dir) {
        // If 3D preview is active, LT and RT can zoom
        if (CFG.zoom3d && find3DPreviewSurface()) {
            if (dir < 0) {
                var zOut = document.getElementById('storeZoomOut');
                if (zOut) { zOut.click(); return; }
            } else {
                var zIn = document.getElementById('storeZoomIn');
                if (zIn) { zIn.click(); return; }
            }
        }
        var s = scrollableAncestor(elementAt(S.x, S.y) || document.body, 'y');
        if (s) { s.scrollTop += dir * s.clientHeight * 0.85; render(); }
        else fireKey(document.activeElement || document.body, dir < 0 ? 'PageUp' : 'PageDown');
    }

    // ------------------------------------------------------ on-screen keyboard
    var LAYOUTS = {
        en: ['1234567890', 'qwertyuiop', 'asdfghjkl', 'zxcvbnm'],
        ar: ['1234567890', 'ضصثقفغعهخحج', 'شسيبلاتنمكط', 'ئءؤرىةوزظذد']
    };

    function openKeyboard(target) {
        ensureDom();
        if (!root) return;
        if (S.kb) closeKeyboard(false);
        var kbEl = document.createElement('div');
        kbEl.id = 'jrs-pad-kb';
        root.appendChild(kbEl);
        S.kb = { el: kbEl, target: target, lang: isArabic() ? 'ar' : 'en', shift: false, symbols: false };
        drawKeyboard();
        // Move cursor to first letter (not label/preview)
        var firstKey = kbEl.querySelector('.jrs-kb-row .jrs-kb-key');
        if (firstKey) { var rr = firstKey.getBoundingClientRect(); moveTo(rr.left + rr.width / 2, rr.top + rr.height / 2); }
    }


    function drawKeyboard() {
        var kb = S.kb;
        if (!kb) return;
        var ar = kb.lang === 'ar';
        var dir = ar ? 'rtl' : 'ltr';
        var rows = LAYOUTS[kb.lang];
        // Focus the target field so selection APIs work
        try { if (document.activeElement !== kb.target) kb.target.focus({ preventScroll: true }); } catch (e) { /* ignore */ }

        // Title
        var fieldName = kb.target.placeholder || kb.target.getAttribute('aria-label') || '';
        var title = fieldName
            ? (ar ? '✏ ' + fieldName : '✏ ' + fieldName)
            : (ar ? '✏ لوحة مفاتيح JRS' : '✏ JRS KEYBOARD');

        var html = '<div class="jrs-kb-label">' + title + '</div>' +
            '<div class="jrs-kb-preview"></div>';

        // Symbols row (always LTR)
        var sym = ar ? '!@#$%^&*()-_+=[]{}|;:\'",<>?/\\`~' : '!@#$%^&*()-_=+[]{}|;:\'",./<>?`~';
        if (kb.symbols) {
            html += '<div class="jrs-kb-row" dir="ltr">';
            Array.prototype.forEach.call(sym.slice(0, 12), function (ch) {
                html += '<div class="jrs-kb-key jrs-kb-special" data-k="' + ch + '">' + ch + '</div>';
            });
            html += '</div>';
            html += '<div class="jrs-kb-row" dir="ltr">';
            Array.prototype.forEach.call(sym.slice(12, 24), function (ch) {
                html += '<div class="jrs-kb-key jrs-kb-special" data-k="' + ch + '">' + ch + '</div>';
            });
            html += '</div>';
        } else {
            rows.forEach(function (row) {
                html += '<div class="jrs-kb-row" dir="' + dir + '">';
                Array.prototype.forEach.call(row, function (ch) {
                    var c = kb.shift && !ar ? ch.toUpperCase() : ch;
                    html += '<div class="jrs-kb-key" data-k="' + c + '">' + c + '</div>';
                });
                html += '</div>';
            });
        }

        // Bottom action row
        html += '<div class="jrs-kb-row">';
        if (!ar) {
            html += '<div class="jrs-kb-key jrs-kb-special" data-k="shift" style="min-width:50px">' +
                (kb.shift ? '<span class="jrs-kb-on">⇧</span>' : '⇧') + '</div>';
        }
        html += '<div class="jrs-kb-key jrs-kb-special" data-k="sym" style="min-width:46px;font-size:12px">' +
            (kb.symbols ? 'ABC' : '!@#') + '</div>';
        html += '<div class="jrs-kb-key jrs-kb-special" data-k="lang" style="min-width:46px;font-size:13px">' +
            (ar ? 'EN' : 'ع') + '</div>';
        html += '<div class="jrs-kb-key jrs-kb-special" data-k="." style="min-width:38px">.</div>';
        html += '<div class="jrs-kb-key jrs-kb-wide" data-k="space">␣</div>';
        html += '<div class="jrs-kb-key jrs-kb-special" data-k="back" style="min-width:48px;font-size:18px">⌫</div>';
        html += '<div class="jrs-kb-key jrs-kb-special" data-k="enter" style="min-width:46px;font-size:18px">↵</div>';
        html += '<div class="jrs-kb-key jrs-kb-accent" data-k="done" style="min-width:48px">✓</div>';
        html += '</div>';

        kb.el.innerHTML = html;
        updatePreview();
        Array.prototype.forEach.call(kb.el.querySelectorAll('.jrs-kb-key'), function (key) {
            key.addEventListener('mousedown', function (e) { e.preventDefault(); });
            key.addEventListener('click', function (e) {
                e.preventDefault();
                e.stopPropagation();
                typeKey(key.getAttribute('data-k'));
            });
        });
    }


    function targetValue(t) { return t.isContentEditable ? t.textContent : (t.value || ''); }

    function updatePreview() {
        if (!S.kb) return;
        var p = S.kb.el.querySelector('.jrs-kb-preview');
        var t = S.kb.target;
        if (!p) return;
        var v = targetValue(t);
        p.textContent = (t.type === 'password') ? v.replace(/./g, '•') : (v || ' ');
        p.dir = S.kb.lang === 'ar' ? 'rtl' : 'ltr';
    }

    function insertText(t, text) {
        if (t.isContentEditable) {
            // Try execCommand first (preserves cursor in contentEditable)
            try {
                t.focus();
                if (document.execCommand && document.execCommand('insertText', false, text)) return;
            } catch (ex) { /* fallback */ }
            t.textContent = t.textContent + text;
            t.dispatchEvent(new Event('input', { bubbles: true }));
            return;
        }
        // Ensure the element is focused so selection positions are valid
        try { if (document.activeElement !== t) t.focus({ preventScroll: true }); } catch (ex) { /* ignore */ }
        var v = t.value || '';
        var max = t.maxLength > 0 ? t.maxLength : Infinity;
        if (v.length >= max) return;
        var s = typeof t.selectionStart === 'number' ? t.selectionStart : v.length;
        var e = typeof t.selectionEnd === 'number' ? t.selectionEnd : v.length;
        try { if (t.type === 'number' || t.type === 'email') { s = e = v.length; } } catch (err) { s = e = v.length; }
        setNativeValue(t, v.slice(0, s) + text + v.slice(e));
        try { t.setSelectionRange(s + text.length, s + text.length); } catch (err) { /* ignore */ }
    }

    function backspace(t) {
        if (t.isContentEditable) {
            try {
                t.focus();
                if (document.execCommand && document.execCommand('delete', false)) return;
            } catch (ex) { /* fallback */ }
            t.textContent = t.textContent.slice(0, -1);
            t.dispatchEvent(new Event('input', { bubbles: true }));
            return;
        }
        try { if (document.activeElement !== t) t.focus({ preventScroll: true }); } catch (ex) { /* ignore */ }
        var v = t.value || '';
        var s = typeof t.selectionStart === 'number' ? t.selectionStart : v.length;
        var e = typeof t.selectionEnd === 'number' ? t.selectionEnd : v.length;
        if (t.type === 'number' || t.type === 'email' || s === null) { s = e = v.length; }
        if (s === e && s > 0) s -= 1;
        setNativeValue(t, v.slice(0, s) + v.slice(e));
        try { t.setSelectionRange(s, s); } catch (err) { /* ignore */ }
    }

    function typeKey(k) {
        var kb = S.kb;
        if (!kb) return;
        var t = kb.target;
        if (!document.contains(t)) { closeKeyboard(false); return; }
        if (k === 'done') { closeKeyboard(true); return; }
        if (k === 'shift') { kb.shift = !kb.shift; drawKeyboard(); return; }
        if (k === 'sym')   { kb.symbols = !kb.symbols; kb.shift = false; drawKeyboard(); return; }
        if (k === 'lang')  { kb.lang = kb.lang === 'en' ? 'ar' : 'en'; kb.shift = false; kb.symbols = false; drawKeyboard(); return; }
        if (k === 'enter') {
            closeKeyboard(true);
            fireKey(t, 'Enter', ['keydown', 'keypress', 'keyup']);
            return;
        }
        if (k === 'back') { backspace(t); fireKey(t, 'Backspace', ['keyup']); }
        else {
            var ch = k === 'space' ? ' ' : k;
            insertText(t, ch);
            fireKey(t, ch, ['keyup']);
            if (kb.shift) { kb.shift = false; drawKeyboard(); return; }
        }
        updatePreview();
    }


    function closeKeyboard(commit) {
        var kb = S.kb;
        if (!kb) return;
        S.kb = null;
        if (kb.el.parentNode) kb.el.parentNode.removeChild(kb.el);
        if (commit && document.contains(kb.target)) {
            kb.target.dispatchEvent(new Event('change', { bubbles: true }));
        }
        var r = document.contains(kb.target) && kb.target.getBoundingClientRect();
        if (r && r.width) moveTo(r.left + r.width / 2, r.top + r.height / 2);
    }

    // ----------------------------------------------------------- lifecycle
    function activate(msg) {
        ensureDom();
        if (!root) return;
        if (typeof msg.speed === 'number') S.speed = msg.speed;
        if (typeof msg.scrollSpeed === 'number') S.scrollSpeed = msg.scrollSpeed;
        if (!S.active) {
            S.active = true;
            root.style.display = 'block';
            document.documentElement.classList.add('jrs-pad-on');
            mirrorHoverStyles();
            observeStyles();
            if (!S.placed) { S.x = window.innerWidth / 2; S.y = window.innerHeight / 2; }
            S.lastFrame = 0;
            showHint();
            updateHover(false);
            render();
            startTicker();
        }
    }

    function deactivate() {
        if (!S.active) return;
        S.active = false;
        stopTicker();
        if (S.press) releaseA();
        if (S.kb) closeKeyboard(false);
        if (S.settingsOpen) toggleSettings(false);
        S.lx = S.ly = S.rx = S.ry = 0;
        S.held = {};
        S.repeat = {};
        if (S.hoverEl) markChain(S.hoverEl, 'jrs-pad-hover', false);
        S.hoverEl = null;
        document.documentElement.classList.remove('jrs-pad-on');
        if (root) root.style.display = 'none';
    }

    // Action router matching user configured buttons
    function actionFor(btn) {
        if (btn === CFG.btnA) return 'a';
        if (btn === CFG.btnB) return 'b';
        if (btn === CFG.btnX) return 'x';
        if (btn === CFG.btnY) return 'y';
        return btn;
    }

    function onButton(name, down) {
        if (down) {
            if (name === 'start') {
                var bmClose = document.getElementById('bmClose');
                if (bmClose && (bmClose.offsetWidth > 0 || bmClose.offsetHeight > 0)) {
                    bmClose.click();
                    return;
                }
                toggleSettings();
                return;
            }
            if (name === 'select') {
                toggleSettings();
                return;
            }

            var act = actionFor(name);

            switch (act) {
                case 'a': pressA(); break;
                case 'b': pressB(); break;
                case 'x': pressX(); break;
                case 'y': pressY(); break;
                case 'lb': switchTab(-1); break;
                case 'rb': switchTab(1); break;
                case 'lt': pageScroll(-1); break;
                case 'rt': pageScroll(1); break;
                case 'r3':
                    var rBtn = document.getElementById('storeRotateReset');
                    if (rBtn) rBtn.click();
                    break;
                case 'up': case 'down': case 'left': case 'right':
                    S.repeat[name] = { since: performance.now(), last: performance.now() };
                    navigate(name);
                    break;
            }
        } else {
            var actUp = actionFor(name);
            if (actUp === 'a') releaseA();
            if (S.repeat[name]) delete S.repeat[name];
        }
    }

    window.addEventListener('message', function (e) {
        var d = e.data;
        if (!d || d.action !== 'jrsPad' || !d.jrsPad) return;
        var m = d.jrsPad;
        if (m.active === false) { deactivate(); return; }
        activate(m);
        if (typeof m.lx === 'number') { S.lx = m.lx; S.ly = m.ly; S.rx = m.rx; S.ry = m.ry; }
        var i;
        if (m.down) for (i = 0; i < m.down.length; i++) { S.held[m.down[i]] = true; onButton(m.down[i], true); }
        if (m.up) for (i = 0; i < m.up.length; i++) { S.held[m.up[i]] = false; onButton(m.up[i], false); }
    });

    function realInput(e) {
        if (!e.isTrusted) return;
        if (typeof e.clientX === 'number' && e.type !== 'keydown') {
            S.x = e.clientX; S.y = e.clientY; S.placed = true;
        }
        if (S.active) deactivate();
    }
    window.addEventListener('mousemove', realInput, true);
    window.addEventListener('mousedown', realInput, true);
    window.addEventListener('keydown', realInput, true);
    window.addEventListener('resize', function () { if (S.active) moveTo(S.x, S.y); });

    (function announce(tries) {
        var res = typeof window.GetParentResourceName === 'function' ? window.GetParentResourceName() : null;
        if (!res || typeof fetch !== 'function') return;
        fetch('https://' + res + '/jrsPadReady', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: '{}'
        }).then(function (r) { return r.text(); }).then(function (t) {
            if (String(t).indexOf('ok') === -1 && tries > 0) setTimeout(function () { announce(tries - 1); }, 3000);
        }).catch(function () {
            if (tries > 0) setTimeout(function () { announce(tries - 1); }, 3000);
        });
    })(20);

    window.__jrsPad = {
        version: 2,
        buttons: BTN,
        config: CFG,
        state: S,
        saveConfig: saveConfig,
        toggleSettings: toggleSettings,
        _elementAt: elementAt,
        _isClickable: isClickable,
        _navigate: navigate,
        _moveTo: moveTo,
        _frame: frame
    };
})();
