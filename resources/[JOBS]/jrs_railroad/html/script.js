// jrs_railroad | page: station menu and driver HUD
// Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE

const state = { data: {}, tab: '', words: {}, closing: false, closedFromGame: false, localised: false };

// a word from locales/<lang>.json; the English text is the fallback so a half translated file still works
const T = (key, fallback) => (state.words && state.words[key]) || fallback;

const $ = (id) => document.getElementById(id);
const money = (n) => '$' + Math.floor(n || 0).toLocaleString();
const ownCompany = () => state.data.station.company;

function post(endpoint, body) {
    return fetch(`https://${GetParentResourceName()}/${endpoint}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body || {}),
    }).then((r) => r.json()).catch((e) => console.error(e));
}

// ---------------------------------------------------------------- building blocks
// Text goes in as text, never as markup, so names typed by players cannot inject anything.

function node(tag, cls, text) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined) n.textContent = text;
    return n;
}

// only for the few locale strings that carry their own <b> markup
function markup(tag, html) {
    const n = document.createElement(tag);
    n.innerHTML = html;
    return n;
}

function line(label, value, tone) {
    const row = node('div', 'stat-line');
    row.append(node('span', 'stat-label', label), node('span', 'stat-value' + (tone ? ' ' + tone : ''), value));
    return row;
}

function button(label, onClick, tone) {
    const b = node('button', 'wood-btn' + (tone ? ' ' + tone : ''), label);
    if (onClick) b.onclick = onClick;
    return b;
}

function labelled(label, input) {
    const box = node('div', 'field');
    box.append(node('label', 'field-label', label), input);
    return box;
}

function numberInput(value, min, max) {
    const i = node('input', 'field-input');
    i.type = 'number';
    i.min = min;
    if (max !== undefined) i.max = max;
    i.value = value;
    return i;
}

function row(o) {
    const card = node('div', 'row-card' + (o.locked ? ' disabled' : ''));
    if (o.badge) card.append(node('div', 'badge-icon', o.badge));

    const body = node('div', 'row-body');
    body.append(node('h3', undefined, o.title));
    if (o.desc) body.append(node('div', 'row-desc', o.desc));
    card.append(body);

    if (o.pill) card.append(node('span', 'pill' + (o.tone ? ' ' + o.tone : ''), o.pill));
    if (o.click) card.onclick = o.click;
    return card;
}

function paper(o) {
    const card = node('div', 'paper-card');
    if (o.title) card.append(node('h3', undefined, o.title));
    (o.paras || []).forEach((p) => card.append(node('p', undefined, p)));
    if (o.price) card.append(line(o.priceLabel || T('nui_price', 'Price'), o.price, 'gold'));
    return card;
}

function rankName(rank) {
    const r = (state.data.ranks || {})[rank];
    return r ? r.label : T('nui_rank_prefix', 'Rank ') + rank;
}

// "xp / needed for next rank", or MAX
function xpText(membership) {
    const next = (state.data.ranks || {})[(membership.rank || 1) + 1];
    return String(membership.xp || 0) + (next ? ' / ' + next.xpRequired : T('nui_max_suffix', ' (MAX)'));
}

// a click on a row fills the right column; this empties it and gives back the column
function freshDetails() {
    const d = $('stationDetails');
    d.innerHTML = '';
    return d;
}

// ---------------------------------------------------------------- opening and closing

function openStation(data) {
    state.data = data;
    state.words = data.lang || state.words || {};
    translatePage();

    $('stationName').textContent = data.station.label;
    $('stationCompany').textContent = data.station.companyLabel;
    state.tab = '';
    drawTabs();
    $('stationUI').classList.remove('hidden');
    state.closing = false;
}

function closeStation() {
    if (state.closing) return;
    state.closing = true;
    $('stationUI').classList.add('hidden');
    if (!state.closedFromGame) post('closeStation');
    state.closedFromGame = false;
    setTimeout(() => { state.closing = false; }, 500);
}

// buttons that act and then leave the menu
function actAndClose(endpoint, body) {
    post(endpoint, body);
    closeStation();
}

// ---------------------------------------------------------------- tabs (which ones depend on the role)

const OWNER_TABS = ['dashboard', 'drivers', 'trains', 'upgrades', 'supplies', 'missions', 'records'];
const DRIVER_TABS = ['trains', 'upgrades', 'supplies', 'missions', 'mystats', 'records'];

function tabNames() {
    return {
        buycompany: T('nui_tab_buy_company', 'Buy Company'),
        companyinfo: T('nui_tab_company_info', 'Company Info'),
        dashboard: T('nui_tab_my_company', 'My Company'),
        drivers: T('nui_tab_manage_drivers', 'Manage Drivers'),
        trains: T('nui_tab_company_trains', 'Company Trains'),
        upgrades: T('nui_tab_upgrades', 'Upgrades'),
        supplies: T('nui_tab_supplies', 'Supplies'),
        missions: T('nui_tab_missions', 'Missions'),
        records: T('nui_tab_records', 'Records'),
        mystats: T('nui_tab_my_stats', 'My Stats'),
        pending: T('nui_tab_application_pending', 'Application Pending'),
        apply: T('nui_tab_apply_as_driver', 'Apply as Driver'),
    };
}

function tabsFor(role) {
    if (role === 'unowned') return ['buycompany', 'companyinfo'];
    if (role === 'owner') return OWNER_TABS;
    if (role === 'driver') return DRIVER_TABS;
    if (role === 'pending') return ['pending', 'companyinfo'];
    return ['apply', 'companyinfo'];
}

function drawTabs() {
    const names = tabNames();
    const ids = tabsFor(state.data.playerRole);
    if (!ids.includes(state.tab)) state.tab = ids[0];

    $('stationListTitle').textContent = names[state.tab];
    $('stationDetailTitle').textContent = T('nui_details', 'Details');

    const bar = $('stationTabs');
    bar.innerHTML = '';
    ids.forEach((id) => {
        const b = node('button', 'tab-btn' + (id === state.tab ? ' active' : ''), names[id]);
        b.onclick = () => { state.tab = id; drawTabs(); };
        bar.append(b);
    });
    drawContent();
}

function drawContent() {
    const list = $('stationContent');
    const details = $('stationDetails');
    list.innerHTML = '';
    details.innerHTML = '';

    const pages = {
        buycompany: pageBuy, dashboard: pageDashboard, drivers: pageDrivers, trains: pageTrains,
        supplies: pageSupplies, missions: pageMissions, mystats: pageMyStats, apply: pageApply,
        pending: pagePending, companyinfo: pageInfo, records: pageRecords, upgrades: pageUpgrades,
    };
    if (pages[state.tab]) pages[state.tab](list, details);
}

// ---------------------------------------------------------------- pages: strangers

function pageBuy(list, details) {
    const company = state.data.companies[ownCompany()];
    list.append(paper({
        title: company.label, paras: [company.description],
        price: '$' + state.data.companyPurchasePrice.toLocaleString(), priceLabel: T('nui_price', 'Price'),
    }));
    list.append(node('p', 'hint', T('nui_buycompany_hint', 'Purchase this company to hire drivers, manage trains, and earn from missions.')));
    details.append(button(T('nui_purchase_company', 'Purchase Company'), () => actAndClose('buyCompany', { companyId: ownCompany() })));
}

function pageApply(list, details) {
    const company = state.data.companies[ownCompany()];
    list.append(paper({ title: company.label, paras: [company.description, T('nui_hiring_text', 'This company is hiring! Apply to become a train driver.')] }));
    details.append(button(T('nui_tab_apply_as_driver', 'Apply as Driver'), () => actAndClose('applyAsDriver', { companyId: ownCompany() })));
}

function pagePending(list) {
    const box = node('div', 'paper-card');
    box.append(node('h3', undefined, T('nui_tab_application_pending', 'Application Pending')),
        node('p', 'hint', T('nui_waiting_approval', 'Waiting for owner approval. Check back later!')));
    list.append(box);
}

function pageInfo(list) {
    const company = state.data.companies[ownCompany()];
    const owned = state.data.ownership;
    list.append(paper({
        title: owned && owned.company_name ? owned.company_name : company.label,
        paras: [company.description, owned ? T('nui_owner_colon', 'Owner: ') + owned.owner_name : T('nui_not_owned', 'Not owned.')],
    }));
}

// ---------------------------------------------------------------- pages: the owner

function pageDashboard(list, details) {
    const d = state.data;
    const owned = d.ownership || {};
    const balance = Math.floor(d.cashRegister || 0);
    const approved = (d.employees || []).filter((e) => e.status === 'approved').length;
    const membership = d.myMembership || {};

    list.append(
        line(T('nui_company', 'Company'), owned.company_name || d.station.companyLabel),
        line(T('nui_owner', 'Owner'), owned.owner_name || T('nui_you', 'You')),
        line(T('nui_cash_register', 'Cash Register'), money(balance), 'gold'),
        line(T('nui_drivers', 'Drivers'), approved + ' ' + T('nui_word_approved', 'approved') + ', ' + (d.pendingApps || []).length + ' ' + T('nui_word_pending', 'pending')),
        line(T('nui_trains', 'Trains'), (d.companyTrains || []).length),
        node('p', 'lead', T('nui_your_progress', 'Your Progress')),
        line(T('nui_rank', 'Rank'), rankName(membership.rank || 1)),
        line(T('nui_xp', 'XP'), xpText(membership)),
        line(T('nui_tab_missions', 'Missions'), membership.missions_completed || 0));

    const amount = numberInput(balance, 1, balance);
    details.append(labelled(T('nui_withdraw_amount', 'Withdraw Amount'), amount));
    details.append(button(T('nui_withdraw', 'Withdraw'), () => {
        const sum = parseInt(amount.value, 10) || 0;
        if (sum <= 0) return;
        post('withdrawFunds', { companyId: ownCompany(), amount: sum }).then((r) => {
            if (r && r.cashRegister !== undefined) d.cashRegister = r.cashRegister;
            drawContent();
        });
    }));

    const name = node('input', 'field-input');
    name.type = 'text';
    name.maxLength = 50;
    name.value = owned.company_name || '';
    details.append(labelled(T('nui_rename_company', 'Rename Company'), name));
    details.append(button(T('nui_rename', 'Rename'), () => {
        const text = name.value.trim();
        if (text.length >= 3) actAndClose('renameCompany', { companyId: ownCompany(), newName: text });
    }));

    details.append(button(T('nui_sell_company', 'Sell Company'), () => actAndClose('sellCompany', { companyId: ownCompany() }), 'danger'));
}

function personName(p) { return p.firstname + ' ' + p.lastname; }

function pageDrivers(list) {
    const d = state.data;
    const pending = d.pendingApps || [];
    const active = (d.employees || []).filter((e) => e.status === 'approved');

    if (pending.length) {
        list.append(node('p', 'lead', T('nui_pending_applications', 'Pending Applications') + ' (' + pending.length + ')'));
        pending.forEach((app) => list.append(row({
            title: personName(app), badge: '●', pill: T('nui_pending_pill', 'Pending'), tone: 'warn',
            click: () => {
                const panel = freshDetails();
                panel.append(node('h3', undefined, personName(app)), node('p', 'hint', T('nui_applied_to_be_driver', 'Applied to be a driver.')));
                panel.append(button(T('nui_approve', 'Approve'), () => post('approveDriver', { companyId: ownCompany(), employeeId: app.id }).then((r) => {
                    if (r) { d.employees = r.employees; d.pendingApps = r.pendingApps; drawContent(); }
                })));
                panel.append(button(T('nui_reject', 'Reject'), () => post('rejectDriver', { companyId: ownCompany(), employeeId: app.id }).then((r) => {
                    if (r) { d.pendingApps = r.pendingApps; drawContent(); }
                }), 'danger'));
            },
        })));
    }

    list.append(node('p', 'lead', T('nui_active_drivers', 'Active Drivers') + ' (' + active.length + ')'));
    if (!active.length) return list.append(node('p', 'hint', T('nui_no_active_drivers', 'No active drivers.')));

    active.forEach((emp) => list.append(row({
        title: personName(emp), badge: '●', pill: rankName(emp.rank),
        click: () => {
            const panel = freshDetails();
            panel.append(node('h3', undefined, personName(emp)),
                line(T('nui_employee_rank', 'Employee Rank'), rankName(emp.rank)),
                line(T('nui_company_rank_stat', 'Company Rank'), rankName(emp.company_rank)),
                line(T('nui_company_xp', 'Company XP'), emp.company_xp),
                line(T('nui_company_missions', 'Company Missions'), emp.company_missions),
                line(T('nui_earnings', 'Earnings'), money(emp.total_earnings), 'gold'));
            panel.append(button(T('nui_fire_driver', 'Fire Driver'), () => post('fireDriver', { companyId: ownCompany(), employeeId: emp.id }).then((r) => {
                if (r) { d.employees = r.employees; drawContent(); }
            }), 'danger'));
        },
    })));
}

// ---------------------------------------------------------------- pages: trains

// the owner may use every train; a driver only those up to their own rank
function myTopRank() {
    const d = state.data;
    return d.playerRole === 'driver' && d.myEmployeeData ? (d.myEmployeeData.rank || 1) : 5;
}

function deployButtons(panel, train) {
    panel.append(node('p', 'lead', T('nui_deploy_at_station', 'Deploy at This Station')));

    const actions = node('div', 'detail-actions');
    [[T('direction_forward', 'Forward'), '▶', false], [T('direction_reverse', 'Reverse'), '◀', true]].forEach(([name, arrow, reverse]) => {
        actions.append(button(arrow + T('nui_deploy_word', ' Deploy ') + name, () => post('spawnTrain', { trainIndex: train.index, direction: reverse })));
    });
    panel.append(actions, node('p', 'hint', T('nui_spawn_hint', 'Train spawns at 50% fuel, water & condition.')));
}

function pageTrains(list) {
    const trains = state.data.companyTrainConfigs || [];
    if (!trains.length) return list.append(node('p', 'hint', T('nui_no_trains_available', 'No trains available for this company.')));

    const mine = myTopRank();
    trains.forEach((train) => {
        const allowed = mine >= train.requiredRank;
        list.append(row({
            title: train.label,
            desc: train.hasPassengerCars ? T('nui_passenger_train', 'Passenger Train') : T('nui_goods_general', 'Goods & General'),
            badge: '◼', pill: T('nui_spd_short_prefix', 'Spd ') + train.maxSpeed, tone: allowed ? '' : 'warn', locked: !allowed,
            click: () => {
                const panel = freshDetails();
                panel.append(node('h3', undefined, train.label),
                    line(T('nui_max_speed', 'Max Speed'), train.maxSpeed),
                    line(T('nui_max_fuel', 'Max Fuel'), train.maxFuel),
                    line(T('nui_max_water', 'Max Water'), train.maxWater),
                    line(T('hud_condition', 'Condition'), train.maxCondition),
                    line(T('nui_required_rank', 'Required Rank'), rankName(train.requiredRank)),
                    line(T('nui_upgradeable', 'Upgradeable'), train.upgradeable ? T('yes', 'Yes') : T('no', 'No')));

                if (!allowed) {
                    panel.append(node('p', 'hint warn', T('nui_need_rank_prefix', 'You need ') + rankName(train.requiredRank) + T('nui_need_rank_suffix', ' rank to use this train.')));
                } else if (state.data.canSpawn) {
                    deployButtons(panel, train);
                } else {
                    panel.append(node('p', 'hint', T('train_already_spawned', 'You already have a train deployed.')));
                }
            },
        }));
    });
}

// ---------------------------------------------------------------- pages: supplies

function refreshSupplies(r) {
    if (r && r.supplies) { state.data.supplies = r.supplies; drawContent(); }
}

function pageSupplies(list) {
    const d = state.data;
    const items = d.supplyItems || [];
    if (!items.length) return list.append(node('p', 'hint', T('nui_no_supplies_configured', 'No supplies configured.')));

    items.forEach((entry) => {
        const stocked = (d.supplies || []).find((s) => s.item_name === entry.item);
        const qty = stocked ? stocked.quantity : 0;

        list.append(row({
            title: entry.label, badge: '□', pill: T('nui_stock_prefix', 'Stock ') + qty, tone: qty > 0 ? 'good' : 'bad',
            click: () => {
                const panel = freshDetails();
                panel.append(node('h3', undefined, entry.label), line(T('nui_in_stock', 'In Stock'), qty, qty > 0 ? 'ok' : 'bad'));

                if (d.playerRole === 'owner') {
                    const amount = numberInput(5, 1);
                    panel.append(labelled(T('nui_add_quantity', 'Add Quantity'), amount));
                    panel.append(button(T('nui_add_from_inventory', 'Add from Inventory'), () => {
                        const n = parseInt(amount.value, 10) || 0;
                        if (n > 0) post('addSupply', { companyId: ownCompany(), itemName: entry.item, quantity: n }).then(refreshSupplies);
                    }));
                }
                panel.append(button(T('nui_take_one', 'Take 1'), () => post('takeSupply', { companyId: ownCompany(), itemName: entry.item, quantity: 1 }).then(refreshSupplies), 'muted'));
            },
        }));
    });
}

// ---------------------------------------------------------------- pages: missions

function jobCard(list, spec) {
    list.append(node('p', 'lead', spec.heading));
    list.append(row({
        title: spec.title, desc: spec.desc, badge: '✦', pill: spec.pill, tone: 'gold',
        click: () => {
            const panel = freshDetails();
            panel.append(node('h3', undefined, spec.detailTitle), ...spec.body);
            panel.append(node('p', 'hint', T('nui_pay_split', 'Pay split: 50% to you, 50% to company.')));
            panel.append(button(spec.title, () => post('startMission', { missionType: spec.kind })));
        },
    }));
}

function pageMissions(list) {
    const missions = state.data.missions || {};
    const delivery = missions.delivery || {};
    const upkeep = missions.maintenance || {};
    const deliveryLegs = delivery.jobLegs || 1;
    const upkeepLegs = upkeep.jobLegs || 1;
    const deliveryPay = delivery.basePay || 15;

    jobCard(list, {
        kind: 'delivery',
        heading: T('nui_delivery_missions_heading', 'Delivery Missions · Rank 1+'),
        title: T('nui_start_delivery_job', 'Start a Delivery Job'),
        desc: T('nui_autorouted_prefix', 'Auto-routed ') + deliveryLegs + T('nui_autorouted_suffix', '-stop job chain, closest stop first.'),
        pill: '$' + deliveryPay + T('nui_plus_per_stop', '+/stop'),
        detailTitle: T('nui_cargo_delivery_job', 'Cargo Delivery Job'),
        body: [
            markup('p', T('nui_dispatch_prefix', 'The train dispatcher will send you to the <b>') + deliveryLegs + T('nui_dispatch_suffix', '</b> closest delivery stops, one after another.')),
            markup('p', T('nui_basepay_prefix', 'Base pay: <span class="stat-value gold">$') + deliveryPay + T('nui_basepay_suffix', '</span> + destination bonus, per stop.')),
        ],
    });

    jobCard(list, {
        kind: 'maintenance',
        heading: T('nui_rail_maintenance_heading', 'Rail Maintenance · Rank 3+'),
        title: T('nui_start_maintenance_job', 'Start a Maintenance Job'),
        desc: T('nui_traveltoprefix', 'Travel to ') + upkeepLegs + T('nui_traveltosuffix', ' damaged sections, one after another.'),
        pill: '$' + (upkeep.basePay || 25) + T('nui_per_stop', '/stop'),
        detailTitle: T('nui_rail_maintenance_job', 'Rail Maintenance Job'),
        body: [markup('p', T('nui_traveltotheprefix', 'Travel to the <b>') + upkeepLegs + T('nui_traveltothesuffix', '</b> closest damaged track sections, one after another, and repair each one.'))],
    });
}

// ---------------------------------------------------------------- pages: numbers

function pageMyStats(list) {
    const d = state.data;
    const membership = d.myMembership || {};
    list.append(
        line(T('nui_company_rank_stat', 'Company Rank'), rankName(membership.rank || 1)),
        line(T('nui_company_xp', 'Company XP'), xpText(membership)),
        line(T('nui_tab_missions', 'Missions'), membership.missions_completed || 0));
    if (d.myEmployeeData) list.append(line(T('nui_earnings', 'Earnings'), money(d.myEmployeeData.total_earnings), 'gold'));
    list.append(line(T('nui_company', 'Company'), d.station.companyLabel));
}

const PLACES = [['nui_place_1st', '1st'], ['nui_place_2nd', '2nd'], ['nui_place_3rd', '3rd']];

function placeName(index) {
    return PLACES[index] ? T(PLACES[index][0], PLACES[index][1]) : (index + 1) + T('nui_place_nth_suffix', 'th');
}

function pageRecords(list, details) {
    const d = state.data;
    const stats = d.companyStats || {};
    const owned = d.ownership || {};
    const none = T('nui_none', 'None');

    list.append(node('h3', undefined, T('nui_company_records', 'Company Records')),
        line(T('nui_company', 'Company'), owned.company_name || d.station.companyLabel),
        line(T('nui_drivers', 'Drivers'), stats.total_drivers || 0),
        line(T('nui_tab_missions', 'Missions'), stats.total_missions || 0),
        line(T('nui_earnings', 'Earnings'), money(stats.total_earnings), 'gold'),
        line(T('nui_cash_register', 'Cash Register'), money(stats.cash_register)),
        line(T('nui_top_earner', 'Top Earner'), (stats.top_earner || none) + ' (' + money(stats.top_earnings) + ')'),
        line(T('nui_most_missions', 'Most Missions'), (stats.most_missions_name || none) + ' (' + (stats.most_missions_count || 0) + ')'),
        line(T('nui_highest_rank', 'Highest Rank'), (stats.highest_rank_name || none) + ' (' + (stats.highest_rank_label || '-') + ')'));

    const board = [...(d.allCompanyStats || [])].sort((a, b) => (b.total_earnings || 0) - (a.total_earnings || 0));
    if (!board.length) return details.append(node('p', 'hint', T('nui_no_companies_compare', 'No companies to compare yet.')));

    details.append(node('h3', undefined, T('nui_company_leaderboard', 'Company Leaderboard')));
    board.forEach((c, i) => {
        const entry = node('div', 'stat-line');
        entry.append(node('span', 'stat-label', placeName(i) + ' · ' + (c.company_name || c.company_label)),
            node('span', 'stat-value' + (c.company_id === ownCompany() ? ' gold' : ''), money(c.total_earnings)));
        details.append(entry, node('p', 'hint', T('nui_missions_colon', 'Missions: ') + (c.total_missions || 0) + T('nui_drivers_colon', ' · Drivers: ') + (c.total_drivers || 0)));
    });
}

// ---------------------------------------------------------------- pages: upgrades

const UPGRADES = [
    { key: 'speed', name: ['nui_upg_speed', 'Speed'], column: 'upgrade_speed' },
    { key: 'fuel_cap', name: ['nui_upg_fuel_cap', 'Fuel Capacity'], column: 'upgrade_fuel_cap' },
    { key: 'water_cap', name: ['nui_upg_water_cap', 'Water Capacity'], column: 'upgrade_water_cap' },
    { key: 'durability', name: ['nui_upg_durability', 'Durability'], column: 'upgrade_durability' },
];

// the owner, or a driver of engineer rank or above
function mayUpgrade() {
    const d = state.data;
    if (d.playerRole === 'owner') return true;
    return d.playerRole === 'driver' && ((d.myEmployeeData && d.myEmployeeData.rank) || 1) >= 3;
}

function upgradeRow(train, kind, level, allowed) {
    const tiers = (state.data.upgrades || {})[kind.key] || [];
    const top = tiers.length || 3;
    const next = level + 1 <= top ? tiers[level] : null;
    const bonus = level > 0 && tiers[level - 1] ? tiers[level - 1].bonus : 0;
    const name = T(kind.name[0], kind.name[1]);

    const box = node('div', 'upg-row');
    box.append(node('p', 'upg-head', name + ' — ' + T('nui_lvl_label', 'Lvl ') + level + '/' + top + (bonus > 0 ? ' (+' + bonus + ' ' + T('nui_bonus_suffix', 'bonus)') : '')));

    if (level >= top) {
        box.append(node('p', 'hint ok', '✓ ' + T('nui_max_level', 'MAX LEVEL')));
    } else if (next && allowed) {
        const extra = next.itemCost ? ' + ' + next.itemCost.amount + 'x ' + next.itemCost.item : '';
        const caption = T('nui_buy_upgrade_prefix', 'Buy ') + name + ' ' + T('nui_upgrade_lvl_suffix', 'Upgrade (Lvl ') + (level + 1) + ')';
        box.append(node('p', 'hint', '$' + next.cost + extra + '  ·  +' + next.bonus + ' bonus'));

        const buy = button(caption, () => {
            buy.disabled = true;
            buy.textContent = T('nui_purchasing', 'Purchasing...');
            post('purchaseUpgrade', { companyId: ownCompany(), trainModel: train.model, upgradeType: kind.key }).then((r) => {
                if (r && r.companyUpgrades) state.data.companyUpgrades = r.companyUpgrades;
                drawContent();
            }).catch(() => { buy.disabled = false; buy.textContent = caption; });
        });
        box.append(buy);
    } else if (next) {
        box.append(node('p', 'hint', T('nui_next_bonus_prefix', 'Next: +') + next.bonus + T('nui_next_bonus_suffix', ' bonus  ·  Engineer rank required')));
    }
    return box;
}

function pageUpgrades(list) {
    const d = state.data;
    const trains = (d.companyTrainConfigs || []).filter((t) => t.upgradeable);
    if (!trains.length) return list.append(node('p', 'hint', T('nui_no_upgradeable_trains', 'No upgradeable trains for this company.')));

    const allowed = mayUpgrade();
    if (!allowed) list.append(node('p', 'hint', T('nui_upgrade_engineer_required', 'Engineer rank or above required to purchase upgrades. Upgrades apply to everyone who deploys this train.')));

    trains.forEach((train) => {
        const owned = (d.companyUpgrades || []).find((u) => u.train_model === train.model) || null;
        const levelOf = (kind) => (owned ? owned[kind.column] || 0 : 0);
        const total = UPGRADES.reduce((sum, kind) => sum + levelOf(kind), 0);

        list.append(row({
            title: train.label, badge: '▲', pill: total + '/' + UPGRADES.length * 3 + T('nui_upg_suffix', ' upg'),
            click: () => {
                const panel = freshDetails();
                panel.append(node('h3', undefined, train.label));
                UPGRADES.forEach((kind) => panel.append(upgradeRow(train, kind, levelOf(kind), allowed)));
            },
        }));
    });
}

// ---------------------------------------------------------------- driver HUD

function openTrainHUD(data) {
    state.words = data.lang || state.words || {};
    translatePage();
    $('hudTrainLabel').textContent = data.train.label;
    $('hudCompanyLabel').textContent = data.train.companyLabel;
    $('trainHUD').classList.remove('hidden');
}

function closeTrainHUD() { $('trainHUD').classList.add('hidden'); }

// the fixed words of the page, translated once
function translatePage() {
    if (state.localised) return;
    state.localised = true;

    const texts = {
        stationListTitle: ['nui_options', 'Options'], stationDetailTitle: ['nui_details', 'Details'],
        hudSpeedLabel: ['nui_hud_speed_short', 'SPD'], hudFuelLabel: ['nui_hud_fuel_short', 'FUEL'],
        hudWaterLabel: ['nui_hud_water_short', 'H2O'], hudCondLabel: ['nui_hud_cond_short', 'COND'],
        hudEngineLabel: ['nui_hud_engine_label', 'Engine'], hudCruiseLabel: ['nui_hud_cruise_label', 'Cruise'],
        hudJunctionLabel: ['nui_hud_junction_label', 'Junction'], hudStationLabel: ['nui_hud_station_label', 'Station'],
        hudMissionLabel: ['nui_hud_mission_label', 'Mission'], hudKbAccel: ['nui_kb_accel', 'Accel'],
        hudKbBrake: ['nui_kb_brake', 'Brake'], hudKbStop: ['nui_kb_stop', 'Stop'], hudKbCruise: ['nui_kb_cruise', 'Cruise'],
        hudKbSwitch: ['nui_kb_switch', 'Switch'], hudKbWhistle: ['nui_kb_whistle', 'Whistle'],
    };
    Object.entries(texts).forEach(([id, [key, fallback]]) => { if ($(id)) $(id).textContent = T(key, fallback); });

    $('stationBackBtn').title = T('nui_dismiss_title', 'Dismiss');
    $('closeStationBtn').title = T('nui_close_title', 'Close');
}

const percent = (value, max) => (max > 0 ? Math.min(100, Math.round(value / max * 100)) : 0);

function gauge(name, value, max) {
    const p = percent(value, max);
    $('hud' + name + 'Bar').style.width = p + '%';
    $('hud' + name + 'Val').textContent = p + '%';
}

function missionText(info) {
    const kinds = {
        delivery: T('nui_type_delivery', 'Delivery'), npc_transport: T('nui_type_passengers', 'Passengers'),
        maintenance: T('nui_type_maintenance', 'Maintenance'),
    };
    const base = kinds[info.type] || T('nui_active_fallback', 'Active');
    return info.totalLegs > 1 ? base + ' (' + info.leg + '/' + info.totalLegs + ')' : base;
}

function updateHUD(data) {
    $('hudSpeedBar').style.width = percent(data.speed, data.maxSpeed) + '%';
    $('hudSpeedVal').textContent = data.speed;
    gauge('Fuel', data.fuel, data.maxFuel);
    gauge('Water', data.water, data.maxWater);
    gauge('Cond', data.condition, data.maxCondition);

    const engine = $('hudEngine');
    engine.textContent = data.engine ? T('hud_on', 'ON') : T('hud_off', 'OFF');
    engine.className = 'info-value ' + (data.engine ? 'ok' : 'bad');

    $('hudCruise').textContent = data.cruiseForward ? T('nui_fwd_short', 'FWD') : data.cruiseBackward ? T('nui_rev_short', 'REV') : '--';
    $('hudJunction').textContent = data.junctionText || '--';
    $('hudStation').textContent = data.nearestStation || '--';

    const dest = $('hudMissionDest');
    if (data.missionActive && data.missionInfo) {
        $('hudMission').textContent = missionText(data.missionInfo);
        const place = data.missionInfo.destination || data.missionInfo.location;
        dest.textContent = place && place.label ? '→ ' + place.label : '';
    } else {
        $('hudMission').textContent = T('nui_none', 'None');
        dest.textContent = '';
    }
}

// ---------------------------------------------------------------- messages from the game

window.addEventListener('message', (event) => {
    const data = event.data;
    if (data.action === 'openStation') openStation(data);
    else if (data.action === 'closeStation') { state.closedFromGame = true; closeStation(); }
    else if (data.action === 'openTrainHUD') openTrainHUD(data);
    else if (data.action === 'closeTrainHUD') closeTrainHUD();
    else if (data.action === 'updateHUD') updateHUD(data);
});

document.addEventListener('DOMContentLoaded', () => {
    $('closeStationBtn').addEventListener('click', closeStation);
    $('stationBackBtn').addEventListener('click', closeStation);
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeStation(); });
});
