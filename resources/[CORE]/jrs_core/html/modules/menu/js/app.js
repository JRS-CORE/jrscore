/* JRS Core menu (MenuData) - jrs_stable layout with the jrs_stores artwork.
   Works with the mouse (hover / click / wheel / buttons) and the keyboard
   (arrows, Enter/Space, Backspace/Escape, Home/End, PageUp/PageDown).
   Protocol is unchanged: { ac: 'open'|'close'|'key', ns, id, dt, key }. */
(function () {
    'use strict';

    var RES = 'jrs_core';
    var TEXT = {
        en: { select: 'Select', back: 'Back', of: 'of', empty: 'Nothing here' },
        ar: { select: 'اختيار', back: 'رجوع', of: 'من', empty: 'لا يوجد شيء' }
    };
    var lang = 'en';
    var pool = {};      // pool[ns][id] = data
    var cursor = {};    // cursor[ns][id] = index
    var stack = [];     // [{ns,id}]
    var root = document.getElementById('menus');
    var lastSfx = 0;

    function t(k) { return (TEXT[lang] || TEXT.en)[k] || TEXT.en[k]; }

    function post(name, body) {
        try {
            fetch('https://' + RES + '/' + name, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(body || {})
            }).catch(function () {});
        } catch (e) {}
    }

    function sfx() {
        var now = Date.now();
        if (now - lastSfx < 60) return;
        lastSfx = now;
        post('jrs:sfx');
    }

    function tellParent() {
        try { window.parent.postMessage({ __jrsMenuState: true, open: stack.length }, '*'); } catch (e) {}
    }

    function top() { return stack[stack.length - 1]; }
    function topMenu() { var s = top(); return s && pool[s.ns] && pool[s.ns][s.id] ? { s: s, m: pool[s.ns][s.id] } : null; }

    function sideOf(align) {
        align = String(align || 'top-left');
        if (align === 'center' || align === 'top' || align === 'bottom') return 'center';
        if (align.indexOf('right') !== -1) return 'right';
        return 'left';
    }

    function el(tag, cls, html) {
        var n = document.createElement(tag);
        if (cls) n.className = cls;
        if (html !== undefined && html !== null) n.innerHTML = html;
        return n;
    }

    function sliderLabel(e) {
        if (Array.isArray(e.options)) {
            var o = e.options[e.value];
            if (o && typeof o === 'object') return o.label || o.text || o.name || String(e.value);
            return o === undefined ? String(e.value) : String(o);
        }
        return String(e.value === undefined ? '' : e.value);
    }

    function sliderBounds(e) {
        if (Array.isArray(e.options)) return { min: 0, max: e.options.length - 1 };
        return { min: e.min === undefined ? 0 : Number(e.min), max: e.max === undefined ? Infinity : Number(e.max) };
    }

    function imageUrl(img) {
        if (!img || typeof img !== 'string') return null;
        if (/^(nui|https?|data):/i.test(img) || img.indexOf('/') !== -1) return img;
        return 'nui://jrs_inventory/html/img/items/' + img + (/\.(png|webp|jpg)$/i.test(img) ? '' : '.png');
    }

    function isDisabled(e) { return !!(e && (e.disabled || e.isNotSelectable || e.unselectable)); }

    /* ------------------------------------------------------------- render */
    function panelId(ns, id) { return 'jm_' + String(ns).replace(/[^\w-]/g, '_') + '__' + String(id).replace(/[^\w-]/g, '_'); }

    function buildPanel(ns, id) {
        var data = pool[ns][id];
        var side = sideOf(data.align);
        var p = el('div', 'jm-panel side-' + side + (lang === 'ar' ? ' rtl' : ''));
        p.id = panelId(ns, id);

        var head = el('div', 'jm-head');
        var back = el('div', 'jm-back', '<i class="fas fa-chevron-left"></i>');
        back.title = t('back');
        back.addEventListener('click', function (ev) { ev.stopPropagation(); dismiss(ns, id); });
        head.appendChild(back);
        head.appendChild(el('div', 'jm-title', data.title || ''));
        head.appendChild(el('div', 'jm-sub', data.subtext || ''));
        p.appendChild(head);

        var list = el('div', 'jm-list');
        var els = data.elements || [];
        if (!els.length) list.appendChild(el('div', 'jm-empty', t('empty')));
        els.forEach(function (e, i) { list.appendChild(buildRow(ns, id, e, i)); });
        p.appendChild(list);

        p.appendChild(el('div', 'jm-desc', ''));

        var foot = el('div', 'jm-foot');
        var bSel = el('div', 'jm-btn primary', '<span class="jm-key">&#8629;</span><span>' + t('select') + '</span>');
        bSel.addEventListener('click', function () { flash(bSel); confirm(ns, id); });
        var count = el('div', 'jm-count', '');
        var bBack = el('div', 'jm-btn', '<span class="jm-key">&#9003;</span><span>' + t('back') + '</span>');
        bBack.addEventListener('click', function () { flash(bBack); dismiss(ns, id); });
        foot.appendChild(bSel); foot.appendChild(count); foot.appendChild(bBack);
        p.appendChild(foot);

        list.addEventListener('wheel', function () { /* native scroll */ }, { passive: true });
        return p;
    }

    function buildRow(ns, id, e, i) {
        var row = el('div', 'jm-row' + (isDisabled(e) ? ' disabled' : ''));
        row.dataset.i = i;
        var img = imageUrl(e.image || e.img);
        if (img) {
            var im = el('img', 'jm-ico');
            im.src = img;
            im.onerror = function () { im.remove(); };
            row.appendChild(im);
        }
        row.appendChild(el('div', 'jm-name', e.label !== undefined ? e.label : (e.title || '')));

        if (e.type === 'slider') {
            var s = el('div', 'jm-slider');
            var l = el('div', 'jm-arrow', '<i class="fas fa-chevron-left"></i>');
            var v = el('div', 'jm-val', '');
            var r = el('div', 'jm-arrow', '<i class="fas fa-chevron-right"></i>');
            l.addEventListener('click', function (ev) { ev.stopPropagation(); setCursor(ns, id, i, true); step(ns, id, -1); });
            r.addEventListener('click', function (ev) { ev.stopPropagation(); setCursor(ns, id, i, true); step(ns, id, 1); });
            s.appendChild(l); s.appendChild(v); s.appendChild(r);
            row.appendChild(s);
            row.addEventListener('wheel', function (ev) {
                if (cursor[ns][id] !== i) return;
                ev.preventDefault();
                step(ns, id, ev.deltaY < 0 ? 1 : -1);
            }, { passive: false });
        } else if (e.rightLabel || e.price !== undefined) {
            row.appendChild(el('div', 'jm-right', e.rightLabel || ('$' + e.price)));
        }

        row.addEventListener('mouseenter', function () {
            if (cursor[ns] && cursor[ns][id] !== i) setCursor(ns, id, i, true, true);
        });
        row.addEventListener('click', function () {
            setCursor(ns, id, i, true, true);
            confirm(ns, id); // same as Enter (slider values change with the arrows / wheel / keys)
        });
        updateRowValue(row, e);
        return row;
    }

    function updateRowValue(row, e) {
        if (e.type !== 'slider') return;
        var b = sliderBounds(e);
        var v = row.querySelector('.jm-val');
        if (v) v.innerHTML = sliderLabel(e);
        var arrows = row.querySelectorAll('.jm-arrow');
        if (arrows[0]) arrows[0].classList.toggle('off', Number(e.value) <= b.min);
        if (arrows[1]) arrows[1].classList.toggle('off', Number(e.value) >= b.max);
    }

    function draw() {
        root.innerHTML = '';
        for (var ns in pool) {
            for (var id in pool[ns]) root.appendChild(buildPanel(ns, id));
        }
        showTop();
        tellParent();
    }

    function showTop() {
        var nodes = root.querySelectorAll('.jm-panel');
        for (var i = 0; i < nodes.length; i++) nodes[i].classList.remove('show');
        var s = top();
        if (!s) return;
        var p = document.getElementById(panelId(s.ns, s.id));
        if (p) { p.classList.add('show'); paintCursor(s.ns, s.id, true); }
    }

    function paintCursor(ns, id, scroll) {
        var p = document.getElementById(panelId(ns, id));
        if (!p) return;
        var data = pool[ns][id];
        var els = data.elements || [];
        var pos = cursor[ns][id] || 0;
        var rows = p.querySelectorAll('.jm-row');
        for (var i = 0; i < rows.length; i++) rows[i].classList.toggle('on', i === pos);
        var cur = els[pos];
        p.querySelector('.jm-desc').innerHTML = cur && cur.desc ? cur.desc : '';
        p.querySelector('.jm-count').textContent = els.length ? ((pos + 1) + ' ' + t('of') + ' ' + els.length) : '';
        if (scroll && rows[pos]) rows[pos].scrollIntoView({ block: 'nearest' });
    }

    /* -------------------------------------------------------------- logic */
    function attach(ns, id, data) {
        data = data || {};
        data.elements = Array.isArray(data.elements) ? data.elements : [];
        if (!pool[ns]) pool[ns] = {};
        if (!cursor[ns]) cursor[ns] = {};
        if (pool[ns][id]) detach(ns, id, true);

        var start = 0, found = false;
        data.elements.forEach(function (e, i) {
            if (!e || typeof e !== 'object') { data.elements[i] = e = { label: String(e) }; }
            if (e.type === undefined) e.type = 'default';
            e._ns = ns; e._id = id;
            if (e.selected && !found) { start = i; found = true; } else e.selected = false;
        });
        pool[ns][id] = data;
        cursor[ns][id] = start;
        if (data.elements[start]) data.elements[start].selected = true;
        stack.push({ ns: ns, id: id });
        draw();
    }

    function detach(ns, id, silent) {
        if (pool[ns]) delete pool[ns][id];
        for (var i = 0; i < stack.length; i++) {
            if (stack[i].ns === ns && stack[i].id === id) { stack.splice(i, 1); break; }
        }
        if (!silent) draw();
    }

    function payload(ns, id, current) {
        return { _ns: ns, _id: id, current: current, elements: pool[ns][id].elements };
    }

    function setCursor(ns, id, i, fromUser, quiet) {
        var data = pool[ns] && pool[ns][id];
        if (!data || !data.elements.length) return;
        var len = data.elements.length;
        i = ((i % len) + len) % len;
        if (cursor[ns][id] === i) return;
        cursor[ns][id] = i;
        data.elements.forEach(function (e, k) { e.selected = (k === i); });
        paintCursor(ns, id, !quiet);
        if (fromUser) { post('jrs:sync', payload(ns, id, data.elements[i])); sfx(); }
    }

    function move(delta) {
        var tm = topMenu(); if (!tm) return;
        setCursor(tm.s.ns, tm.s.id, (cursor[tm.s.ns][tm.s.id] || 0) + delta, true);
    }

    function jump(toEnd) {
        var tm = topMenu(); if (!tm || !tm.m.elements.length) return;
        setCursor(tm.s.ns, tm.s.id, toEnd ? tm.m.elements.length - 1 : 0, true);
    }

    function step(ns, id, dir) {
        var data = pool[ns] && pool[ns][id];
        if (!data) return;
        var e = data.elements[cursor[ns][id]];
        if (!e || e.type !== 'slider') return;
        var b = sliderBounds(e);
        var hop = e.hop !== undefined ? Number(e.hop) : 1;
        var val = Number(e.value) || 0;
        var next = val + dir * hop;
        if (dir > 0 && b.min > 0 && val === b.min && e.hop !== undefined && !Array.isArray(e.options)) next = hop; // legacy hop rule
        next = Math.max(b.min, Math.min(b.max, next));
        if (next === val) return;
        e.value = next;
        var p = document.getElementById(panelId(ns, id));
        var row = p && p.querySelectorAll('.jm-row')[cursor[ns][id]];
        if (row) updateRowValue(row, e);
        post('jrs:sync', payload(ns, id, e));
        sfx();
    }

    function confirm(ns, id) {
        var s = (ns !== undefined) ? { ns: ns, id: id } : top();
        if (!s || !pool[s.ns] || !pool[s.ns][s.id]) return;
        var data = pool[s.ns][s.id];
        var e = data.elements[cursor[s.ns][s.id]];
        if (!e || isDisabled(e)) return;
        post('jrs:select', payload(s.ns, s.id, e));
    }

    function dismiss(ns, id) {
        var s = (ns !== undefined) ? { ns: ns, id: id } : top();
        if (!s) return;
        post('jrs:back', { _ns: s.ns, _id: s.id });
    }

    function flash(node) {
        if (!node) return;
        node.classList.add('flash');
        setTimeout(function () { node.classList.remove('flash'); }, 120);
    }

    function flashFooter(which) {
        var s = top(); if (!s) return;
        var p = document.getElementById(panelId(s.ns, s.id));
        if (p) flash(p.querySelectorAll('.jm-btn')[which === 'back' ? 1 : 0]);
    }

    function key(k) {
        var tm = topMenu(); if (!tm) return;
        switch (k) {
            case 'ENTER': flashFooter('select'); confirm(); break;
            case 'BACKSPACE': flashFooter('back'); dismiss(); break;
            case 'TOP': move(-1); break;
            case 'DOWN': move(1); break;
            case 'LEFT': step(tm.s.ns, tm.s.id, -1); break;
            case 'RIGHT': step(tm.s.ns, tm.s.id, 1); break;
            case 'HOME': jump(false); break;
            case 'END': jump(true); break;
            case 'PGUP': move(-5); break;
            case 'PGDN': move(5); break;
        }
    }

    var KEYMAP = {
        ArrowUp: 'TOP', ArrowDown: 'DOWN', ArrowLeft: 'LEFT', ArrowRight: 'RIGHT',
        Enter: 'ENTER', NumpadEnter: 'ENTER', Space: 'ENTER',
        Backspace: 'BACKSPACE', Escape: 'BACKSPACE',
        Home: 'HOME', End: 'END', PageUp: 'PGUP', PageDown: 'PGDN',
        KeyW: 'TOP', KeyS: 'DOWN', KeyA: 'LEFT', KeyD: 'RIGHT'
    };

    function onKeyDown(ev) {
        if (!stack.length) return;
        var k = KEYMAP[ev.code] || KEYMAP[ev.key];
        if (!k) return;
        ev.preventDefault();
        if (ev.repeat && (k === 'ENTER' || k === 'BACKSPACE')) return;
        key(k);
    }
    window.addEventListener('keydown', onKeyDown);

    function setLanguage(code) {
        code = String(code || 'en').toLowerCase().indexOf('ar') === 0 ? 'ar' : 'en';
        if (code === lang) return;
        lang = code;
        if (stack.length) draw();
    }

    window.handleEvent = function (msg) {
        if (!msg || typeof msg !== 'object') return;
        if (msg.type === 'jrsLanguage' || msg.action === 'jrsLanguage') { setLanguage(msg.language); return; }
        if (msg.__jrsMenuKey) { var k = msg.__jrsMenuKey; onKeyDown({ code: k.code, key: k.key, repeat: !!k.repeat, preventDefault: function () {} }); return; }
        switch (msg.ac) {
            case 'open': attach(String(msg.ns), String(msg.id), msg.dt); break;
            case 'close': if (pool[msg.ns] && pool[msg.ns][msg.id]) detach(String(msg.ns), String(msg.id)); break;
            case 'closeAll': pool = {}; cursor = {}; stack = []; draw(); break;
            case 'key': key(msg.key); break;
        }
    };

    window.addEventListener('message', function (e) { window.handleEvent(e.data); });
    window.__jrsMenu = { key: key, state: function () { return { stack: stack.slice(), pool: pool }; } };
})();
