// jrs_mdt | the MDT page
// Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
'use strict';

const S = { lang: 'en', officer: null, perms: {}, page: 'home', incidentTypes: [], deletes: {} };

const $ = (id) => document.getElementById(id);

// ------------------------------------------------------------------ small tools

// translated text; "%s" and "%d" are filled from the arguments in order
function t(key, ...args) {
    const text = (WORDS[S.lang] && WORDS[S.lang][key]) || WORDS.en[key] || key;
    let i = 0;
    return text.replace(/%[sd]/g, () => (args[i] !== undefined ? args[i++] : ''));
}

// builds an element: h('div', { class: 'x', onclick: fn }, 'text', child, ...)
function h(tag, props, ...kids) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(props || {})) {
        if (v === undefined || v === null || v === false) continue;
        if (k === 'class') e.className = v;
        else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
        else if (k === 'value') e.value = v;
        else if (k === 'checked') e.checked = v;
        else e.setAttribute(k, v === true ? '' : v);
    }
    const add = (kid) => {
        if (Array.isArray(kid)) kid.forEach(add);
        else if (kid !== null && kid !== undefined && kid !== false) e.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
    };
    kids.forEach(add);
    return e;
}

function call(name, body) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}),
    }).then((r) => r.json()).catch(() => null);
}

function toast(message, kind) {
    const n = h('div', { class: 'toast ' + (kind || '') }, message);
    $('toasts').append(n);
    setTimeout(() => n.remove(), 4500);
}

// shows the answer of an action ({ success, message }) and says whether it worked
function report(result, okText) {
    const ok = !!(result && (result.success === true));
    toast((result && result.message) || (ok ? okText || t('done') : t('failed')), ok ? 'ok' : 'bad');
    return ok;
}

const money = (n) => '$' + Number(n || 0).toLocaleString();

function when(v) {
    if (v === null || v === undefined || v === '') return '';
    const d = new Date(typeof v === 'number' ? v : String(v).replace(' ', 'T'));
    return isNaN(d) ? String(v) : d.toLocaleString(S.lang === 'ar' ? 'ar' : 'en-GB');
}

const fullName = (info) => ((info && info.firstname) || '') + ' ' + ((info && info.lastname) || '');
const can = (perm) => S.perms && S.perms[perm] === true;
const list = (v) => (Array.isArray(v) ? v : []);

// a delete is answered later by a message from the game
function deleteVia(name, body, action) {
    return new Promise((resolve) => {
        S.deletes[action] = resolve;
        call(name, body);
        setTimeout(() => { if (S.deletes[action] === resolve) { delete S.deletes[action]; resolve({ success: false }); } }, 8000);
    });
}

// ------------------------------------------------------------------ modal

function modal(title, body, buttons) {
    const root = $('modalRoot');
    const close = () => shade.remove();
    const foot = h('div', { class: 'mf' }, (buttons || []).map((b) => h('button', {
        class: 'btn ' + (b.cls || ''),
        onclick: async () => { if (!b.click || (await b.click()) !== false) close(); },
    }, b.label)));

    const shade = h('div', { class: 'shade' },
        h('div', { class: 'modal' }, h('div', { class: 'mh' }, title), h('div', { class: 'mb' }, body), foot));
    shade.addEventListener('mousedown', (e) => { if (e.target === shade) close(); });
    root.append(shade);
    return close;
}

const cancelButton = () => ({ label: t('cancel') });

function confirmBox(text) {
    return new Promise((resolve) => {
        modal(t('confirm'), h('p', null, text), [
            { label: t('cancel'), click: () => resolve(false) },
            { label: t('yes'), cls: 'danger', click: () => resolve(true) },
        ]);
    });
}

// a form field: returns the wrapper; read the input through .input
function field(label, input) {
    const w = h('div', null, h('label', null, label), input);
    w.input = input;
    return w;
}

// a text box that searches people as you type and remembers the pick
function personPicker(search, onPick) {
    const results = h('div', { class: 'pick hidden' });
    const box = h('input', { placeholder: t('search_person') });
    const picked = { value: null };
    let timer;

    box.addEventListener('input', () => {
        clearTimeout(timer);
        timer = setTimeout(async () => {
            const found = list(await search(box.value));
            results.classList.toggle('hidden', found.length === 0);
            results.replaceChildren(...found.map((p) => h('div', {
                onclick: () => {
                    picked.value = p;
                    box.value = fullName(p.charinfo) + ' (' + p.citizenid + ')';
                    results.classList.add('hidden');
                    if (onPick) onPick(p);
                },
            }, fullName(p.charinfo), ' ', h('span', { class: 'badge' }, p.citizenid))));
        }, 250);
    });

    const wrap = h('div', null, box, results);
    wrap.picked = picked;
    return wrap;
}

function table(headers, rows, onRow) {
    if (!rows.length) return h('div', { class: 'empty' }, t('nothing'));
    return h('table', null,
        h('thead', null, h('tr', null, headers.map((x) => h('th', null, x)))),
        h('tbody', null, rows.map((cells, i) => h('tr', { class: onRow ? 'click' : '', onclick: onRow ? () => onRow(i) : null },
            cells.map((c) => h('td', null, c))))));
}

const badge = (text, tone) => h('span', { class: 'badge ' + (tone || '') }, text);
const check = (label, on) => h('label', null, h('input', { type: 'checkbox', checked: !!on }), label);

// the four permission check boxes; read with permissionValues()
const PERMISSIONS = ['canCreateRecords', 'canDeleteRecords', 'canManageWarrants', 'isAdmin'];

function permissionBoxes(current) {
    const row = h('div', { class: 'perms' }, PERMISSIONS.map((p) => {
        const l = h('label', null, h('input', { type: 'checkbox', checked: !!(current && current[p]) }), t('perm_' + p));
        l.dataset.perm = p;
        return l;
    }));
    return row;
}

function permissionValues(row) {
    const out = {};
    row.querySelectorAll('label').forEach((l) => { out[l.dataset.perm] = l.querySelector('input').checked; });
    return out;
}

// ------------------------------------------------------------------ navigation

const PAGES = [
    { id: 'home', render: pageHome },
    { id: 'citizens', render: pageCitizens },
    { id: 'warrants', render: pageWarrants },
    { id: 'bolos', render: pageBolos },
    { id: 'reports', render: pageReports },
    { id: 'charges', render: pageCharges },
    { id: 'fines', render: pageFines },
    { id: 'admin', render: pageAdmin, admin: true },
];

function drawNav() {
    $('nav').replaceChildren(...PAGES.filter((p) => !p.admin || can('isAdmin')).map((p) => h('button', {
        class: S.page === p.id ? 'on' : '', onclick: () => go(p.id),
    }, t('nav_' + p.id))));
}

async function go(id) {
    S.page = id;
    drawNav();
    const box = $('content');
    box.replaceChildren(h('div', { class: 'empty' }, t('loading')));
    const page = PAGES.find((p) => p.id === id);
    const fresh = h('div');
    await page.render(fresh);
    if (S.page === id) box.replaceChildren(fresh);
}

// ------------------------------------------------------------------ home

async function pageHome(box) {
    const stats = (await call('getStats')) || {};
    box.append(h('h2', null, t('nav_home')),
        h('div', { class: 'cards' }, [
            ['records', stats.records], ['activeWarrants', stats.activeWarrants], ['activeBolos', stats.activeBolos],
            ['reports', stats.reports], ['unpaidFines', stats.unpaidFines],
        ].map(([k, v]) => h('div', { class: 'card' }, h('div', { class: 'num' }, v || 0), h('div', { class: 'lab' }, t('stat_' + k))))));

    const o = S.officer || {};
    box.append(h('h3', null, t('officer')),
        h('div', { class: 'kv' }, h('span', null, t('name')), h('span', null, o.name || ''),
            h('span', null, t('citizenid')), h('span', null, o.citizenid || ''),
            h('span', null, t('department')), h('span', null, (o.job && o.job.label) || ''),
            h('span', null, t('rank')), h('span', null, (o.permissions && o.permissions.label) || '')));
}

// ------------------------------------------------------------------ citizens

async function pageCitizens(box) {
    const results = h('div');
    const search = h('input', { class: 'grow', placeholder: t('search_citizens') });

    const show = (people) => {
        const rows = list(people).slice(0, 200);
        results.replaceChildren(table([t('name'), t('citizenid'), t('job'), ''], rows.map((p) => [
            fullName(p.charinfo), p.citizenid, (p.job && (p.job.label || p.job.name)) || '', p.isWanted ? badge(t('wanted'), 'red') : '',
        ]), (i) => openCitizen(rows[i].citizenid)));
    };

    let timer;
    search.addEventListener('input', () => {
        clearTimeout(timer);
        timer = setTimeout(async () => show(search.value.trim().length >= 2 ? await call('searchCitizens', { query: search.value.trim() }) : await call('getAllCitizens')), 250);
    });

    box.append(h('h2', null, t('nav_citizens')), h('div', { class: 'bar' }, search), results);
    show(await call('getAllCitizens'));
}

async function openCitizen(citizenid) {
    S.page = 'citizens';
    drawNav();
    const box = $('content');
    box.replaceChildren(h('div', { class: 'empty' }, t('loading')));

    const c = await call('getCitizen', { citizenid });
    if (!c || !c.citizenid) return box.replaceChildren(h('div', { class: 'empty' }, t('nothing')));

    const name = fullName(c.charinfo);
    const info = c.charinfo || {};
    const details = [
        [t('citizenid'), c.citizenid], [t('birthdate'), info.birthdate || info.dob || ''], [t('gender'), info.gender || info.sex || ''],
        [t('job'), c.job && (c.job.label || c.job.name) || ''], [t('status'), c.isWanted ? badge(t('wanted'), 'red') : badge(t('clear'), 'green')],
    ].filter((r) => r[1] !== '');

    const photo = c.profilePicture ? h('img', { class: 'photo', src: c.profilePicture }) : h('div', { class: 'photo' }, t('no_photo'));
    const content = h('div');
    let tab = 'records';

    const tabs = h('div', { class: 'tabs' });
    const paint = async () => {
        tabs.replaceChildren(...['records', 'charges', 'fines'].map((id) => h('button', {
            class: tab === id ? 'on' : '', onclick: () => { tab = id; paint(); },
        }, t('tab_' + id))));
        content.replaceChildren(h('div', { class: 'empty' }, t('loading')));
        const body = h('div');
        await ({ records: citizenRecords, charges: citizenCharges, fines: citizenFines })[tab](body, c, name, () => openCitizen(citizenid));
        content.replaceChildren(body);
    };

    const actions = h('div', { class: 'bar' },
        h('button', { class: 'btn', onclick: () => go('citizens') }, t('back')),
        can('canCreateRecords') && h('button', { class: 'btn', onclick: () => setPhoto(c) }, t('set_photo')),
        can('canCreateRecords') && h('button', { class: 'btn', onclick: () => recordForm(c, name, () => openCitizen(citizenid)) }, t('add_record')),
        can('canManageWarrants') && h('button', { class: 'btn', onclick: () => warrantForm(c, name) }, t('new_warrant')),
        can('canCreateRecords') && h('button', { class: 'btn gold', onclick: () => chargeForm(c, name, () => openCitizen(citizenid)) }, t('issue_charges')));

    box.replaceChildren(h('h2', null, name), actions,
        h('div', { class: 'profile' }, photo, h('div', { class: 'kv' }, details.flatMap((r) => [h('span', null, r[0]), h('span', null, r[1])]))),
        tabs, content);
    paint();
}

function setPhoto(c) {
    const url = h('input', { placeholder: 'https://', value: c.profilePicture || '' });
    modal(t('set_photo'), field(t('photo_url'), url), [
        cancelButton(),
        { label: t('save'), cls: 'gold', click: async () => { report(await call('setProfilePicture', { citizenid: c.citizenid, url: url.value.trim() })); openCitizen(c.citizenid); } },
    ]);
}

async function citizenRecords(box, c, name, reload) {
    const records = list(c.records);
    if (!records.length) return box.append(h('div', { class: 'empty' }, t('nothing')));

    records.forEach((r) => box.append(h('div', { class: 'row' },
        h('div', { class: 'head' }, h('span', { class: 'title' }, r.crime),
            r.fine > 0 && badge(money(r.fine), 'gold'), r.jailtime > 0 && badge(r.jailtime + ' ' + t('months'), 'red'),
            can('canDeleteRecords') && h('button', { class: 'btn danger small', onclick: async () => {
                if (!(await confirmBox(t('delete_q')))) return;
                const result = await deleteVia('deleteRecord', { id: r.id }, 'recordDeleted');
                toast(result.success ? t('done') : t('failed'), result.success ? 'ok' : 'bad');
                reload();
            } }, t('delete'))),
        h('div', { class: 'meta' }, r.officer + ' · ' + when(r.created_at)),
        r.description && h('p', null, r.description))));
}

function recordForm(c, name, reload) {
    const crime = h('input'), description = h('textarea'), fine = h('input', { type: 'number', value: 0 }), jail = h('input', { type: 'number', value: 0 });
    modal(t('add_record'), h('div', null, field(t('crime'), crime), field(t('description'), description), field(t('fine'), fine), field(t('jail_months'), jail)), [
        cancelButton(),
        { label: t('save'), cls: 'gold', click: async () => {
            if (!crime.value.trim()) { toast(t('crime_needed'), 'bad'); return false; }
            report(await call('addRecord', { citizenid: c.citizenid, name, crime: crime.value.trim(), description: description.value, fine: +fine.value || 0, jailtime: +jail.value || 0 }));
            reload();
        } },
    ]);
}

async function citizenCharges(box, c) {
    const [charges, totals] = await Promise.all([call('getIssuedCharges', { citizenid: c.citizenid }), call('getCitizenJailTotals', { citizenid: c.citizenid })]);
    const t0 = totals || {};
    box.append(h('div', { class: 'cards' },
        h('div', { class: 'card' }, h('div', { class: 'num' }, t0.totalJailtime || 0), h('div', { class: 'lab' }, t('total_months'))),
        h('div', { class: 'card' }, h('div', { class: 'num' }, t0.totalServed || 0), h('div', { class: 'lab' }, t('served'))),
        h('div', { class: 'card' }, h('div', { class: 'num' }, t0.outstanding || 0), h('div', { class: 'lab' }, t('outstanding')))), h('h3', null, t('tab_charges')));

    box.append(table([t('charge'), t('fine'), t('jail_months'), t('fine_status'), t('officer'), t('date')], list(charges).map((x) => [
        x.charge_name, money(x.fine), x.jailtime, x.fine_status ? badge(t('fs_' + x.fine_status), x.fine_status === 'paid' ? 'green' : 'red') : '', x.officer, when(x.created_at),
    ])));
}

async function citizenFines(box, c, name, reload) {
    const fines = list(await call('getCitizenFines', { citizenid: c.citizenid }));
    if (!fines.length) return box.append(h('div', { class: 'empty' }, t('nothing')));

    box.append(table(['#', t('amount'), t('fine_status'), t('due'), ''], fines.map((f) => [
        f.id, money(f.total_amount), badge(t('fs_' + f.status), f.status === 'paid' ? 'green' : 'red'), when(f.due_date),
        f.status !== 'paid' && can('canCreateRecords') && h('button', { class: 'btn small', onclick: async () => { report(await call('markFinePaid', { fineId: f.id })); reload(); } }, t('mark_paid')),
    ])));
}

// ------------------------------------------------------------------ issuing charges

async function chargeForm(c, name, reload) {
    const templates = list(await call('getChargeTemplates'));
    const chosen = new Map();
    const attached = new Map();
    const player = h('input', { type: 'number', value: c.playerId || '', placeholder: t('server_id') });

    const pickList = h('div', { class: 'pick' });
    const summary = h('div', { class: 'meta' });
    const filter = h('input', { placeholder: t('search_charges') });

    const refreshSummary = () => {
        const fine = [...chosen.values()].reduce((s, x) => s + (x.fine || 0), 0);
        const jail = [...chosen.values()].reduce((s, x) => s + (x.jailtime || 0), 0);
        summary.textContent = t('charge_summary', chosen.size, money(fine), jail);
    };

    const drawList = () => {
        const q = filter.value.trim().toLowerCase();
        pickList.replaceChildren(...templates.filter((x) => !q || (x.name + ' ' + x.category).toLowerCase().includes(q)).map((x) => h('div', {
            class: chosen.has(x.id) ? 'on' : '',
            onclick: () => { chosen.has(x.id) ? chosen.delete(x.id) : chosen.set(x.id, x); refreshSummary(); drawList(); },
        }, x.name, ' ', badge(x.category), ' ', badge(money(x.fine), 'gold'), ' ', x.jailtime > 0 && badge(x.jailtime + ' ' + t('months'), 'red'))));
    };
    filter.addEventListener('input', drawList);
    drawList();
    refreshSummary();

    const reports = h('div', { class: 'pick hidden' });
    const reportSearch = h('input', { placeholder: t('attach_reports') });
    const chips = h('div', { class: 'meta' });
    let timer;
    reportSearch.addEventListener('input', () => {
        clearTimeout(timer);
        timer = setTimeout(async () => {
            const found = list(await call('getAvailableReportsForAttachment', { query: reportSearch.value.trim() }));
            reports.classList.toggle('hidden', !found.length);
            reports.replaceChildren(...found.map((r) => h('div', { onclick: () => {
                attached.set(r.id, r);
                chips.textContent = [...attached.values()].map((x) => '#' + x.id + ' ' + x.title).join(' · ');
                reports.classList.add('hidden');
            } }, '#' + r.id + ' ' + r.title, ' ', badge(r.type))));
        }, 250);
    });

    modal(t('issue_charges') + ' - ' + name, h('div', null,
        field(t('search_charges'), filter), pickList, summary,
        field(t('server_id_hint'), player),
        field(t('attach_reports'), reportSearch), reports, chips), [
        cancelButton(),
        { label: t('submit'), cls: 'gold', click: async () => {
            if (!chosen.size) { toast(t('pick_charge'), 'bad'); return false; }
            const charges = [...chosen.values()].map((x) => ({ templateId: x.id, name: x.name, description: x.description, fine: x.fine, jailtime: x.jailtime }));
            const answer = await call('submitCharges', {
                citizenid: c.citizenid, citizenName: name, targetPlayerId: player.value ? +player.value : null,
                charges, attachedReportIds: [...attached.keys()], totalJailtime: charges.reduce((s, x) => s + (x.jailtime || 0), 0),
            });
            if (!answer || !answer.success) { toast((answer && answer.message) || t('failed'), 'bad'); return false; }
            setTimeout(reload, 1500);
        } },
    ]);
}

// ------------------------------------------------------------------ warrants

const WARRANT_STATES = ['active', 'served', 'expired'];

async function pageWarrants(box) {
    const warrants = list(await call('getWarrants'));
    box.append(h('h2', null, t('nav_warrants')),
        can('canManageWarrants') && h('div', { class: 'bar' }, h('button', { class: 'btn gold', onclick: () => warrantForm(null) }, t('new_warrant'))));

    box.append(table([t('name'), t('reason'), t('status'), t('officer'), t('date'), ''], warrants.map((w) => [
        h('a', { href: '#', onclick: (e) => { e.preventDefault(); openCitizen(w.citizenid); }, style: 'color:inherit' }, w.name),
        w.reason, badge(t('ws_' + w.status), w.status === 'active' ? 'red' : 'green'), w.officer, when(w.created_at),
        can('canManageWarrants') && h('span', null,
            h('select', { onchange: async (e) => { report(await call('updateWarrant', { id: w.id, status: e.target.value }).then((r) => ({ success: r && r.success }))); go('warrants'); } },
                WARRANT_STATES.map((s) => h('option', { value: s, selected: s === w.status }, t('ws_' + s)))),
            ' ', h('button', { class: 'btn danger small', onclick: async () => {
                if (!(await confirmBox(t('delete_q')))) return;
                const r = await deleteVia('deleteWarrant', { id: w.id }, 'warrantDeleted');
                toast(r.success ? t('done') : t('failed'), r.success ? 'ok' : 'bad');
                go('warrants');
            } }, t('delete'))),
    ])));
}

function warrantForm(citizen, knownName) {
    const picker = citizen ? null : personPicker((q) => call('searchCitizens', { query: q.trim() }));
    const reason = h('textarea');
    modal(t('new_warrant'), h('div', null, citizen ? h('p', null, knownName) : field(t('person'), picker), field(t('reason'), reason)), [
        cancelButton(),
        { label: t('save'), cls: 'gold', click: async () => {
            const target = citizen || (picker.picked.value);
            if (!target || !reason.value.trim()) { toast(t('fill_all'), 'bad'); return false; }
            const ok = await call('addWarrant', { citizenid: target.citizenid, name: knownName || fullName(target.charinfo), reason: reason.value.trim() });
            toast(ok && ok.success ? t('done') : t('failed'), ok && ok.success ? 'ok' : 'bad');
            if (S.page === 'warrants') go('warrants');
        } },
    ]);
}

// ------------------------------------------------------------------ BOLOs

async function pageBolos(box) {
    const bolos = list(await call('getBolos'));
    box.append(h('h2', null, t('nav_bolos')), h('div', { class: 'bar' }, h('button', { class: 'btn gold', onclick: boloForm }, t('new_bolo'))));
    if (!bolos.length) return box.append(h('div', { class: 'empty' }, t('nothing')));

    bolos.forEach((b) => box.append(h('div', { class: 'row' },
        h('div', { class: 'head' }, h('span', { class: 'title' }, b.title),
            can('canDeleteRecords') && h('button', { class: 'btn danger small', onclick: async () => {
                if (!(await confirmBox(t('delete_q')))) return;
                const r = await deleteVia('deleteBolo', { id: b.id }, 'boloDeleted');
                toast(r.success ? t('done') : t('failed'), r.success ? 'ok' : 'bad');
                go('bolos');
            } }, t('delete'))),
        h('div', { class: 'meta' }, b.officer + ' · ' + when(b.created_at) + (b.last_seen ? ' · ' + t('last_seen') + ': ' + b.last_seen : '')),
        b.description && h('p', null, b.description))));
}

function boloForm() {
    const title = h('input'), description = h('textarea'), seen = h('input');
    modal(t('new_bolo'), h('div', null, field(t('title'), title), field(t('description'), description), field(t('last_seen'), seen)), [
        cancelButton(),
        { label: t('save'), cls: 'gold', click: async () => {
            if (!title.value.trim()) { toast(t('fill_all'), 'bad'); return false; }
            const r = await call('addBolo', { title: title.value.trim(), description: description.value, lastSeen: seen.value });
            toast(r && r.success ? t('done') : t('failed'), r && r.success ? 'ok' : 'bad');
            go('bolos');
        } },
    ]);
}

// ------------------------------------------------------------------ reports

function incidentBadge(type) {
    const found = S.incidentTypes.find((x) => x.value === type);
    return badge(found ? found.label : type, 'blue');
}

async function pageReports(box) {
    const reports = list(await call('getReports'));
    box.append(h('h2', null, t('nav_reports')),
        can('canCreateRecords') && h('div', { class: 'bar' }, h('button', { class: 'btn gold', onclick: reportForm }, t('new_report'))));
    if (!reports.length) return box.append(h('div', { class: 'empty' }, t('nothing')));

    reports.forEach((r) => box.append(h('div', { class: 'row', style: 'cursor:pointer', onclick: () => openReport(r.id) },
        h('div', { class: 'head' }, h('span', { class: 'title' }, '#' + r.id + ' ' + r.title), incidentBadge(r.type),
            r.linkedCharge && badge(r.linkedCharge.charge_name, 'gold')),
        h('div', { class: 'meta' }, r.officer + ' · ' + when(r.created_at)))));
}

async function openReport(id) {
    const [r, comments, charges] = await Promise.all([call('getReport', { id }), call('getReportComments', { reportId: id }), call('getReportsWithCharges', { reportId: id })]);
    if (!r || !r.id) return;

    const section = (label, items) => list(items).length ? [h('h3', null, label), h('div', null, list(items).map((x) => badge(typeof x === 'string' ? x : JSON.stringify(x)))) ] : [];
    const thread = h('div', null, list(comments).map((cm) => h('div', { class: 'row' }, h('div', { class: 'meta' }, cm.author + ' · ' + when(cm.created_at)), h('p', null, cm.content))));
    const text = h('textarea', { placeholder: t('write_comment') });

    modal('#' + r.id + ' ' + r.title, h('div', null,
        h('div', { class: 'meta' }, r.officer + ' · ' + when(r.created_at)), incidentBadge(r.type), h('p', { style: 'white-space:pre-wrap' }, r.description || ''),
        section(t('officers'), r.officers), section(t('suspects'), r.suspects), section(t('evidence'), r.evidence),
        list(charges).length ? [h('h3', null, t('linked_charges')), table([t('charge'), t('person'), t('fine')], list(charges).map((x) => [x.charge_name, x.citizen_name, money(x.fine)]))] : null,
        h('h3', null, t('comments')), thread, can('canCreateRecords') && text), [
        can('canDeleteRecords') && { label: t('delete'), cls: 'danger', click: async () => {
            if (!(await confirmBox(t('delete_q')))) return false;
            const res = await deleteVia('deleteReport', { id: r.id }, 'reportDeleted');
            toast(res.success ? t('done') : t('failed'), res.success ? 'ok' : 'bad');
            go('reports');
        } },
        { label: t('close') },
        can('canCreateRecords') && { label: t('comment'), cls: 'gold', click: async () => {
            if (!text.value.trim()) return false;
            const res = await call('addReportComment', { reportId: r.id, content: text.value.trim() });
            toast(res && res.success ? t('done') : t('failed'), res && res.success ? 'ok' : 'bad');
            openReport(r.id);
        } },
    ].filter(Boolean));
}

function reportForm() {
    const title = h('input'), description = h('textarea');
    const type = h('select', null, S.incidentTypes.map((x) => h('option', { value: x.value }, x.label)));
    const officers = h('input'), suspects = h('input'), evidence = h('input');
    const split = (v) => v.split(',').map((x) => x.trim()).filter(Boolean);

    modal(t('new_report'), h('div', null,
        field(t('title'), title), field(t('type'), type), field(t('description'), description),
        field(t('officers') + ' (' + t('comma') + ')', officers), field(t('suspects') + ' (' + t('comma') + ')', suspects), field(t('evidence') + ' (' + t('comma') + ')', evidence)), [
        cancelButton(),
        { label: t('save'), cls: 'gold', click: async () => {
            if (!title.value.trim()) { toast(t('fill_all'), 'bad'); return false; }
            const r = await call('createReport', { title: title.value.trim(), type: type.value, description: description.value, officers: split(officers.value), suspects: split(suspects.value), evidence: split(evidence.value) });
            toast(r && r.success ? t('done') : t('failed'), r && r.success ? 'ok' : 'bad');
            go('reports');
        } },
    ]);
}

// ------------------------------------------------------------------ charges

async function pageCharges(box) {
    let tab = 'issued';
    const body = h('div');
    const tabs = h('div', { class: 'tabs' });

    const paint = async () => {
        tabs.replaceChildren(...['issued', 'templates'].map((id) => h('button', { class: tab === id ? 'on' : '', onclick: () => { tab = id; paint(); } }, t('ct_' + id))));
        body.replaceChildren(h('div', { class: 'empty' }, t('loading')));
        const fresh = h('div');
        await (tab === 'issued' ? issuedCharges : chargeTemplates)(fresh);
        body.replaceChildren(fresh);
    };

    box.append(h('h2', null, t('nav_charges')), tabs, body);
    await paint();
}

async function issuedCharges(box) {
    const results = h('div');
    const search = h('input', { placeholder: t('search_issued') });

    const load = async () => {
        const charges = list(await call('getAllIssuedCharges', { query: search.value.trim() }));
        results.replaceChildren(table(['#', t('person'), t('charge'), t('fine'), t('jail_months'), t('officer'), t('date')], charges.map((x) => [
            x.id, x.citizen_name, x.charge_name, money(x.fine), x.jailtime, x.officer, when(x.created_at),
        ]), (i) => chargeDetails(charges[i])));
    };

    let timer;
    search.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(load, 300); });
    box.append(h('div', { class: 'bar' }, search), results);
    await load();
}

async function chargeDetails(charge) {
    const attachments = list(await call('getChargeAttachments', { chargeId: charge.id }));
    const body = h('div', null,
        h('div', { class: 'kv' },
            h('span', null, t('person')), h('span', null, charge.citizen_name), h('span', null, t('charge')), h('span', null, charge.charge_name),
            h('span', null, t('fine')), h('span', null, money(charge.fine)), h('span', null, t('jail_months')), h('span', null, charge.jailtime),
            h('span', null, t('officer')), h('span', null, charge.officer), h('span', null, t('date')), h('span', null, when(charge.created_at))),
        charge.charge_description && h('p', null, charge.charge_description),
        h('h3', null, t('attached_reports')),
        attachments.length ? attachments.map((a) => h('div', { class: 'row' },
            h('div', { class: 'head' }, h('span', { class: 'title' }, '#' + a.report_id + ' ' + a.report_title), badge(a.report_type, 'blue'),
                h('button', { class: 'btn danger small', onclick: async () => { report(await call('removeAttachmentFromCharge', { chargeId: charge.id, reportId: a.report_id })); chargeDetails(charge); } }, t('detach'))),
            h('div', { class: 'meta' }, a.attached_by_name + ' · ' + when(a.attached_at)))) : h('div', { class: 'empty' }, t('nothing')));

    modal('#' + charge.id + ' ' + charge.charge_name, body, [{ label: t('close') }, { label: t('attach_reports'), cls: 'gold', click: () => { attachForm(charge); } }]);
}

function attachForm(charge) {
    const picked = new Set();
    const results = h('div', { class: 'pick' });
    const search = h('input', { placeholder: t('attach_reports') });

    const load = async () => {
        const found = list(await call('getAvailableReportsForAttachment', { query: search.value.trim() }));
        results.replaceChildren(...found.map((r) => h('div', {
            class: picked.has(r.id) ? 'on' : '', onclick: () => { picked.has(r.id) ? picked.delete(r.id) : picked.add(r.id); load(); },
        }, '#' + r.id + ' ' + r.title, ' ', badge(r.type))));
    };
    let timer;
    search.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(load, 250); });
    load();

    modal(t('attach_reports'), h('div', null, search, results), [
        cancelButton(),
        { label: t('attach'), cls: 'gold', click: async () => {
            if (!picked.size) return false;
            report(await call('attachReportsToCharge', { chargeId: charge.id, reportIds: [...picked] }));
            chargeDetails(charge);
        } },
    ]);
}

const CATEGORIES = ['infraction', 'misdemeanor', 'felony'];

async function chargeTemplates(box) {
    const templates = list(await call('getChargeTemplates'));
    const admin = can('isAdmin');

    if (admin) box.append(h('div', { class: 'bar' }, h('button', { class: 'btn gold', onclick: () => templateForm(null) }, t('new_template'))));
    box.append(table([t('charge'), t('category'), t('fine'), t('jail_months'), ''], templates.map((x) => [
        x.name, badge(x.category), money(x.fine), x.jailtime,
        admin && h('span', null,
            h('button', { class: 'btn small', onclick: () => templateForm(x) }, t('edit')), ' ',
            h('button', { class: 'btn danger small', onclick: async () => {
                if (!(await confirmBox(t('delete_q')))) return;
                const r = await deleteVia('deleteChargeTemplate', { id: x.id }, 'chargeTemplateDeleted');
                report(r);
                go('charges');
            } }, t('delete'))),
    ])));
}

function templateForm(existing) {
    const name = h('input', { value: existing ? existing.name : '' });
    const description = h('textarea', null, existing ? existing.description || '' : '');
    const fine = h('input', { type: 'number', value: existing ? existing.fine : 0 });
    const jail = h('input', { type: 'number', value: existing ? existing.jailtime : 0 });
    const category = h('select', null, CATEGORIES.map((c) => h('option', { value: c, selected: existing && existing.category === c }, c)));

    modal(existing ? t('edit') : t('new_template'), h('div', null,
        field(t('charge'), name), field(t('description'), description), field(t('fine'), fine), field(t('jail_months'), jail), field(t('category'), category)), [
        cancelButton(),
        { label: t('save'), cls: 'gold', click: async () => {
            const body = { name: name.value.trim(), description: description.value, fine: +fine.value || 0, jailtime: +jail.value || 0, category: category.value };
            if (existing) body.id = existing.id;
            report(await call(existing ? 'updateChargeTemplate' : 'addChargeTemplate', body));
            go('charges');
        } },
    ]);
}

// ------------------------------------------------------------------ fines

async function pageFines(box) {
    const fines = list(await call('getAllUnpaidFines'));
    box.append(h('h2', null, t('nav_fines')), table(['#', t('person'), t('amount'), t('fine_status'), t('due'), t('officer'), ''], fines.map((f) => [
        f.id, f.citizen_name, money(f.total_amount), badge(t('fs_' + f.status), 'red'), when(f.due_date), f.officer_name,
        can('canCreateRecords') && h('button', { class: 'btn small', onclick: async () => { report(await call('markFinePaid', { fineId: f.id })); go('fines'); } }, t('mark_paid')),
    ])));
}

// ------------------------------------------------------------------ administration

async function pageAdmin(box) {
    let tab = 'staff';
    const body = h('div');
    const tabs = h('div', { class: 'tabs' });
    const sections = { staff: adminStaff, roles: adminRoles, departments: adminDepartments, audit: adminAudit };

    const paint = async () => {
        tabs.replaceChildren(...Object.keys(sections).map((id) => h('button', { class: tab === id ? 'on' : '', onclick: () => { tab = id; paint(); } }, t('ad_' + id))));
        body.replaceChildren(h('div', { class: 'empty' }, t('loading')));
        const fresh = h('div');
        await sections[tab](fresh, paint);
        body.replaceChildren(fresh);
    };

    S.adminRefresh = paint;
    box.append(h('h2', null, t('nav_admin')), tabs, body);
    await paint();
}

async function adminStaff(box, repaint) {
    const staff = list(await call('getStaff'));
    box.append(h('div', { class: 'bar' }, h('button', { class: 'btn gold', onclick: () => staffForm(null, repaint) }, t('add_staff')),
        h('button', { class: 'btn', onclick: async () => { report(await call('syncStaffFromJobs', {})); repaint(); } }, t('sync_staff'))));

    box.append(table([t('name'), t('citizenid'), t('role'), t('department'), ''], staff.map((m) => [
        m.name, m.citizenid, badge(m.role, 'gold'), (m.department || '') + (m.role_label ? ' · ' + m.role_label : ''),
        h('span', null, h('button', { class: 'btn small', onclick: () => staffForm(m, repaint) }, t('edit')), ' ',
            h('button', { class: 'btn danger small', onclick: async () => {
                if (!(await confirmBox(t('delete_q')))) return;
                report(await call('removeStaff', { citizenid: m.citizenid }));
                repaint();
            } }, t('remove'))),
    ])));
}

async function staffForm(member, repaint) {
    const roles = list(await call('getRoles'));
    const picker = member ? null : personPicker((q) => call('searchCitizensForStaff', { query: q.trim() }));
    const role = h('select', null, roles.map((r) => h('option', { value: r.name, selected: member && member.role === r.name }, r.label)));
    const perms = permissionBoxes(member ? member.permissions : null);

    // choosing a role fills in its permissions
    role.addEventListener('change', () => {
        const found = roles.find((r) => r.name === role.value);
        if (!found) return;
        perms.querySelectorAll('label').forEach((l) => { l.querySelector('input').checked = !!(found.permissions && found.permissions[l.dataset.perm]); });
    });

    modal(member ? member.name : t('add_staff'), h('div', null, member ? null : field(t('person'), picker), field(t('role'), role), field(t('permissions'), perms)), [
        cancelButton(),
        { label: t('save'), cls: 'gold', click: async () => {
            const body = { role: role.value, permissions: permissionValues(perms) };
            if (member) {
                body.citizenid = member.citizenid;
            } else {
                if (!picker.picked.value) { toast(t('fill_all'), 'bad'); return false; }
                body.citizenid = picker.picked.value.citizenid;
            }
            report(await call(member ? 'updateStaffPermissions' : 'addStaff', body));
            repaint();
        } },
    ]);
}

async function adminRoles(box, repaint) {
    const [roles, config] = await Promise.all([call('getRoles'), call('getConfigRoles')]);
    box.append(h('div', { class: 'bar' }, h('button', { class: 'btn gold', onclick: () => roleForm(null, repaint) }, t('new_role'))));

    box.append(table([t('name'), t('role'), t('permissions'), ''], list(roles).map((r) => [
        r.name, r.label, PERMISSIONS.filter((p) => r.permissions && r.permissions[p]).map((p) => badge(t('perm_' + p))),
        h('span', null, h('button', { class: 'btn small', onclick: () => roleForm(r, repaint) }, t('edit')), ' ',
            h('button', { class: 'btn danger small', onclick: async () => {
                if (!(await confirmBox(t('delete_q')))) return;
                report(await deleteVia('deleteRole', { name: r.name }, 'roleDeleted'));
                repaint();
            } }, t('delete'))),
    ])));

    box.append(h('h3', null, t('config_ranks')));
    list(config).forEach((job) => box.append(h('div', { class: 'row' }, h('div', { class: 'head' }, h('span', { class: 'title' }, job.label)),
        h('div', { class: 'meta' }, list(job.grades).map((g) => g.level + ': ' + g.label).join(' · ')))));
}

function roleForm(role, repaint) {
    const name = h('input', { value: role ? role.name : '', disabled: !!role });
    const label = h('input', { value: role ? role.label : '' });
    const perms = permissionBoxes(role ? role.permissions : null);

    modal(role ? t('edit') : t('new_role'), h('div', null, field(t('name'), name), field(t('label'), label), field(t('permissions'), perms)), [
        cancelButton(),
        { label: t('save'), cls: 'gold', click: async () => {
            if (!name.value.trim() || !label.value.trim()) { toast(t('fill_all'), 'bad'); return false; }
            report(await call(role ? 'updateRole' : 'createRole', { name: name.value.trim(), label: label.value.trim(), permissions: permissionValues(perms) }));
            repaint();
        } },
    ]);
}

async function adminDepartments(box, repaint) {
    const [counts, officers] = await Promise.all([call('getJobPlayerCounts'), call('getOfficers')]);

    box.append(h('div', { class: 'cards' }, list(counts).map((c) => h('div', { class: 'card' }, h('div', { class: 'num' }, c.count), h('div', { class: 'lab' }, c.label)))),
        h('div', { class: 'bar', style: 'margin-top:12px' }, h('button', { class: 'btn gold', onclick: () => jobForm(null, repaint) }, t('assign_job'))),
        table([t('name'), t('department'), t('rank'), ''], list(officers).map((o) => [
            o.name, o.jobLabel || '', o.gradeLabel || '',
            h('button', { class: 'btn small', onclick: () => jobForm(o, repaint) }, t('transfer')),
        ])));
}

// assigns a law job to anybody (member == null) or moves a staff member to another department
async function jobForm(member, repaint) {
    const jobs = list(await call('getLawJobs'));
    const picker = member ? null : personPicker((q) => call('searchPlayersForJob', { query: q.trim() }));
    const job = h('select', null, jobs.map((j) => h('option', { value: j.name }, j.label)));
    const grade = h('select');

    const loadGrades = async () => {
        const grades = list(await call('getJobGrades', { jobName: job.value }));
        grade.replaceChildren(...grades.map((g) => h('option', { value: g.level }, g.label)));
    };
    job.addEventListener('change', loadGrades);
    loadGrades();

    modal(member ? member.name : t('assign_job'), h('div', null, member ? null : field(t('person'), picker), field(t('department'), job), field(t('rank'), grade)), [
        cancelButton(),
        { label: t('save'), cls: 'gold', click: async () => {
            const body = { job: job.value, grade: +grade.value };
            if (member) {
                body.citizenid = member.citizenid;
            } else {
                if (!picker.picked.value) { toast(t('fill_all'), 'bad'); return false; }
                body.citizenid = picker.picked.value.citizenid;
            }
            report(await call(member ? 'updateOfficerDepartment' : 'assignLawJob', body));
            repaint();
        } },
    ]);
}

async function adminAudit(box) {
    const logs = list(await call('getAuditLogs', { limit: 150, offset: 0 }));
    box.append(table([t('date'), t('action'), t('target'), t('by'), t('details')], logs.map((l) => [
        when(l.created_at), badge(l.action, 'gold'), (l.target_name || '') + (l.target_id ? ' (' + l.target_id + ')' : ''), l.performed_by_name,
        h('span', { class: 'meta' }, (l.details || '').slice(0, 140)),
    ])));
}

// ------------------------------------------------------------------ jail countdown

function jailMessage(data) {
    const box = $('jail');
    const text = (data.citizenName ? data.citizenName + ' - ' : '') + (data.message || '');

    if (data.status === 'processing') {
        box.classList.remove('hidden');
        $('jailTitle').textContent = t('jail_processing');
        $('jailText').textContent = data.citizenName || '';
        $('jailCount').textContent = data.remaining !== undefined ? data.remaining : '';
        $('jailAbort').classList.remove('hidden');
        $('jailDone').classList.add('hidden');
        return;
    }

    const shown = !box.classList.contains('hidden');
    if (!shown) return toast(text || t('jail_' + data.status), data.status === 'completed' ? 'ok' : 'bad');

    $('jailTitle').textContent = t('jail_' + data.status);
    $('jailText').textContent = text;
    $('jailCount').textContent = '';
    $('jailAbort').classList.add('hidden');
    $('jailDone').classList.remove('hidden');
}

// ------------------------------------------------------------------ messages from the game

const HANDLERS = {
    open(data) {
        S.officer = data.officer;
        S.perms = data.permissions || {};
        S.lang = data.language === 'ar' ? 'ar' : 'en';
        document.body.setAttribute('dir', S.lang === 'ar' ? 'rtl' : 'ltr');
        $('officer').textContent = (data.officer && data.officer.name) || '';
        $('title').textContent = t('title');
        $('jailAbort').textContent = t('abort');
        $('jailDone').textContent = t('ok');
        $('app').classList.remove('hidden');
        call('getIncidentTypes').then((types) => { S.incidentTypes = list(types); });
        go('home');
    },
    close() { $('app').classList.add('hidden'); $('modalRoot').replaceChildren(); },
    jailStatus: jailMessage,
    chargesUpdated(data) { if (data && data.action === 'issued' || data && data.action === 'committed') toast(t('charges_updated'), 'ok'); },
    staffUpdated() { if (S.page === 'admin' && S.adminRefresh) S.adminRefresh(); },
    rolesUpdated() { if (S.page === 'admin' && S.adminRefresh) S.adminRefresh(); },
    jobAssigned() { if (S.page === 'admin' && S.adminRefresh) S.adminRefresh(); },
    departmentUpdated() { if (S.page === 'admin' && S.adminRefresh) S.adminRefresh(); },
};

// the answers of deletes
['recordDeleted', 'warrantDeleted', 'boloDeleted', 'reportDeleted', 'roleDeleted', 'chargeTemplateDeleted'].forEach((action) => {
    HANDLERS[action] = (data) => {
        const resolve = S.deletes[action];
        delete S.deletes[action];
        if (resolve) resolve(data || { success: false });
    };
});

window.addEventListener('message', (event) => {
    const handler = HANDLERS[event.data && event.data.action];
    if (handler) handler(event.data.data || {});
});

document.addEventListener('DOMContentLoaded', () => {
    $('closeBtn').addEventListener('click', () => call('close'));
    $('jailAbort').addEventListener('click', () => call('abortJail'));
    $('jailDone').addEventListener('click', () => $('jail').classList.add('hidden'));
});

document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    const open = $('modalRoot').lastElementChild;
    if (open) open.remove();
    else if (!$('app').classList.contains('hidden')) call('close');
});
