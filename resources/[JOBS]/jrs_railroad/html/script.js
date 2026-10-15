let stationData = {};
let activeTab = '';
let lang = {};

// Looks up a locale string sent from Lua (locales/<lang>.json); falls
// back to the given English default if the key is missing so the UI
// never breaks even if a translation is incomplete.
function t(key, fallback) {
    return (lang && lang[key]) || fallback;
}
let isClosing = false;
let closedByLua = false;

function nuiFetch(endpoint, data) {
    return fetch(`https://${GetParentResourceName()}/${endpoint}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data || {})
    }).then(r => r.json()).catch(e => console.error(e));
}

// ========== DOM HELPERS ==========
// Safe by default: `text` is always rendered as plain text (never parsed as
// markup), so server/player-controlled strings (company names, driver
// names, etc.) can never inject HTML/script into the NUI. Use elHTML()
// instead, and only for developer-authored locale strings that
// intentionally carry literal markup (e.g. "<b>...</b>").
function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
}

function elHTML(tag, cls, html) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (html !== undefined) e.innerHTML = html;
    return e;
}

function rowCard(o) {
    const card = el('div', 'row-card' + (o.locked ? ' disabled' : ''));
    if (o.badge) card.appendChild(el('div', 'badge-icon', o.badge));
    const body = el('div', 'row-body');
    body.appendChild(el('h3', undefined, o.title));
    if (o.desc) body.appendChild(el('div', 'row-desc', o.desc));
    card.appendChild(body);
    if (o.pill) card.appendChild(el('span', 'pill' + (o.pillClass ? ' ' + o.pillClass : ''), o.pill));
    if (o.onClick) card.onclick = o.onClick;
    return card;
}

function paperCard(o) {
    const card = el('div', 'paper-card');
    if (o.title) card.appendChild(el('h3', undefined, o.title));
    (o.paras || []).forEach(t => card.appendChild(el('p', undefined, t)));
    if (o.price) {
        const row = el('div', 'stat-line');
        row.appendChild(el('span', 'stat-label', o.priceLabel || t('nui_price', 'Price')));
        row.appendChild(el('span', 'stat-value gold', o.price));
        card.appendChild(row);
    }
    return card;
}

function statLine(label, value, cls) {
    const row = el('div', 'stat-line');
    row.appendChild(el('span', 'stat-label', label));
    row.appendChild(el('span', 'stat-value' + (cls ? ' ' + cls : ''), value));
    return row;
}

function woodBtn(label, onClick, variant) {
    const b = el('button', 'wood-btn' + (variant ? ' ' + variant : ''), label);
    if (onClick) b.onclick = onClick;
    return b;
}

function field(label, input) {
    const f = el('div', 'field');
    f.appendChild(el('label', 'field-label', label));
    f.appendChild(input);
    return f;
}

// ========== STATION MENU ==========
function openStation(data) {
    stationData = data;
    lang = data.lang || lang || {};
    applyStaticLocale();
    document.getElementById('stationName').textContent = data.station.label;
    document.getElementById('stationCompany').textContent = data.station.companyLabel;
    activeTab = '';
    renderTabs();
    document.getElementById('stationUI').classList.remove('hidden');
    isClosing = false;
}

function closeStation() {
    if (isClosing) return;
    isClosing = true;
    document.getElementById('stationUI').classList.add('hidden');
    if (!closedByLua) {
        nuiFetch('closeStation').catch(() => {});
    }
    closedByLua = false;
    setTimeout(() => { isClosing = false; }, 500);
}

// Safety: force-close if UI gets stuck
function safeClose() {
    isClosing = false;
    closedByLua = false;
    document.getElementById('stationUI').classList.add('hidden');
    nuiFetch('closeStation').catch(() => {});
}

// ========== ROLE-BASED TABS ==========
function renderTabs() {
    const tabsEl = document.getElementById('stationTabs');
    tabsEl.innerHTML = '';
    const role = stationData.playerRole;
    let tabs = [];

    if (role === 'unowned') {
        tabs = [{ id: 'buycompany', label: t('nui_tab_buy_company', 'Buy Company') }, { id: 'companyinfo', label: t('nui_tab_company_info', 'Company Info') }];
    } else if (role === 'owner') {
        tabs = [
            { id: 'dashboard', label: t('nui_tab_my_company', 'My Company') },
            { id: 'drivers', label: t('nui_tab_manage_drivers', 'Manage Drivers') },
            { id: 'trains', label: t('nui_tab_company_trains', 'Company Trains') },
            { id: 'upgrades', label: t('nui_tab_upgrades', 'Upgrades') },
            { id: 'supplies', label: t('nui_tab_supplies', 'Supplies') },
            { id: 'missions', label: t('nui_tab_missions', 'Missions') },
            { id: 'records', label: t('nui_tab_records', 'Records') },
        ];
    } else if (role === 'driver') {
        tabs = [
            { id: 'trains', label: t('nui_tab_company_trains', 'Company Trains') },
            { id: 'upgrades', label: t('nui_tab_upgrades', 'Upgrades') },
            { id: 'supplies', label: t('nui_tab_supplies', 'Supplies') },
            { id: 'missions', label: t('nui_tab_missions', 'Missions') },
            { id: 'mystats', label: t('nui_tab_my_stats', 'My Stats') },
            { id: 'records', label: t('nui_tab_records', 'Records') },
        ];
    } else if (role === 'pending') {
        tabs = [{ id: 'pending', label: t('nui_tab_application_pending', 'Application Pending') }, { id: 'companyinfo', label: t('nui_tab_company_info', 'Company Info') }];
    } else {
        tabs = [{ id: 'apply', label: t('nui_tab_apply_as_driver', 'Apply as Driver') }, { id: 'companyinfo', label: t('nui_tab_company_info', 'Company Info') }];
    }

    if (!activeTab || !tabs.find(t => t.id === activeTab)) activeTab = tabs[0].id;
    const current = tabs.find(t => t.id === activeTab);
    document.getElementById('stationListTitle').textContent = current ? current.label : t('nui_options', 'Options');
    document.getElementById('stationDetailTitle').textContent = t('nui_details', 'Details');

    tabs.forEach(tab => {
        const btn = document.createElement('button');
        btn.className = 'tab-btn' + (activeTab === tab.id ? ' active' : '');
        btn.textContent = tab.label;
        btn.onclick = () => { activeTab = tab.id; renderTabs(); };
        tabsEl.appendChild(btn);
    });
    renderContent();
}

function renderContent() {
    const content = document.getElementById('stationContent');
    const details = document.getElementById('stationDetails');
    content.innerHTML = '';
    details.innerHTML = '';

    const fn = {
        buycompany: renderBuyCompany, dashboard: renderDashboard, drivers: renderDrivers,
        trains: renderTrains, supplies: renderSupplies, missions: renderMissions,
        mystats: renderMyStats, apply: renderApply, pending: renderPending, companyinfo: renderCompanyInfo,
        records: renderRecords, upgrades: renderUpgrades,
    };
    if (fn[activeTab]) fn[activeTab](content, details);
}

// ========== BUY COMPANY (unowned) ==========
function renderBuyCompany(content, details) {
    const comp = stationData.companies[stationData.station.company];
    content.appendChild(paperCard({
        title: comp.label,
        paras: [comp.description],
        price: '$' + stationData.companyPurchasePrice.toLocaleString(),
        priceLabel: t('nui_price', 'Price'),
    }));
    content.appendChild(el('p', 'hint', t('nui_buycompany_hint', 'Purchase this company to hire drivers, manage trains, and earn from missions.')));
    details.appendChild(woodBtn(t('nui_purchase_company', 'Purchase Company'), () => { nuiFetch('buyCompany', { companyId: stationData.station.company }).catch(() => {}); closeStation(); }));
}

// ========== OWNER DASHBOARD ==========
function renderDashboard(content, details) {
    const o = stationData.ownership || {};
    const bal = Math.floor(stationData.cashRegister || 0);
    const empCount = (stationData.employees || []).filter(e => e.status === 'approved').length;
    const pendCount = (stationData.pendingApps || []).length;
    const trainCount = (stationData.companyTrains || []).length;
    const membership = stationData.myMembership || {};
    const ranks = stationData.ranks || {};
    const rankLabel = ranks[membership.rank] ? ranks[membership.rank].label : t('nui_rank_prefix', 'Rank ') + (membership.rank || 1);
    const nextRank = ranks[(membership.rank || 1) + 1];

    content.appendChild(statLine(t('nui_company', 'Company'), o.company_name || stationData.station.companyLabel));
    content.appendChild(statLine(t('nui_owner', 'Owner'), o.owner_name || t('nui_you', 'You')));
    content.appendChild(statLine(t('nui_cash_register', 'Cash Register'), '$' + bal.toLocaleString(), 'gold'));
    content.appendChild(statLine(t('nui_drivers', 'Drivers'), empCount + ' ' + t('nui_word_approved', 'approved') + ', ' + pendCount + ' ' + t('nui_word_pending', 'pending')));
    content.appendChild(statLine(t('nui_trains', 'Trains'), trainCount));

    content.appendChild(el('p', 'lead', t('nui_your_progress', 'Your Progress')));
    content.appendChild(statLine(t('nui_rank', 'Rank'), rankLabel));
    content.appendChild(statLine(t('nui_xp', 'XP'), String(membership.xp || 0) + (nextRank ? ' / ' + nextRank.xpRequired : t('nui_max_suffix', ' (MAX)'))));
    content.appendChild(statLine(t('nui_tab_missions', 'Missions'), membership.missions_completed || 0));

    // Withdraw
    const wInput = el('input', 'field-input');
    wInput.type = 'number'; wInput.min = 1; wInput.max = bal; wInput.value = bal;
    details.appendChild(field(t('nui_withdraw_amount', 'Withdraw Amount'), wInput));
    details.appendChild(woodBtn(t('nui_withdraw', 'Withdraw'), () => {
        const amt = parseInt(wInput.value) || 0;
        if (amt > 0) {
            nuiFetch('withdrawFunds', { companyId: stationData.station.company, amount: amt }).then(r => {
                if (r && r.cashRegister !== undefined) stationData.cashRegister = r.cashRegister;
                renderContent();
            }).catch(() => {});
        }
    }));

    // Rename
    const rInput = el('input', 'field-input');
    rInput.type = 'text'; rInput.maxLength = 50; rInput.value = o.company_name || '';
    details.appendChild(field(t('nui_rename_company', 'Rename Company'), rInput));
    details.appendChild(woodBtn(t('nui_rename', 'Rename'), () => {
        const name = rInput.value.trim();
        if (name.length >= 3) { nuiFetch('renameCompany', { companyId: stationData.station.company, newName: name }).catch(() => {}); closeStation(); }
    }));

    // Sell
    details.appendChild(woodBtn(t('nui_sell_company', 'Sell Company'), () => { nuiFetch('sellCompany', { companyId: stationData.station.company }).catch(() => {}); closeStation(); }, 'danger'));
}

// ========== MANAGE DRIVERS (owner) ==========
function renderDrivers(content, details) {
    const pending = stationData.pendingApps || [];
    const employees = (stationData.employees || []).filter(e => e.status === 'approved');
    const ranks = stationData.ranks || {};

    if (pending.length > 0) {
        content.appendChild(el('p', 'lead', t('nui_pending_applications', 'Pending Applications') + ' (' + pending.length + ')'));
        pending.forEach(app => {
            const card = rowCard({
                title: app.firstname + ' ' + app.lastname,
                badge: '●',
                pill: t('nui_pending_pill', 'Pending'),
                pillClass: 'warn',
                onClick: () => {
                    details.innerHTML = '';
                    details.appendChild(el('h3', undefined, app.firstname + ' ' + app.lastname));
                    details.appendChild(el('p', 'hint', t('nui_applied_to_be_driver', 'Applied to be a driver.')));
                    details.appendChild(woodBtn(t('nui_approve', 'Approve'), () => nuiFetch('approveDriver', { companyId: stationData.station.company, employeeId: app.id }).then(r => { if (r) { stationData.employees = r.employees; stationData.pendingApps = r.pendingApps; renderContent(); } })));
                    details.appendChild(woodBtn(t('nui_reject', 'Reject'), () => nuiFetch('rejectDriver', { companyId: stationData.station.company, employeeId: app.id }).then(r => { if (r) { stationData.pendingApps = r.pendingApps; renderContent(); } }), 'danger'));
                },
            });
            content.appendChild(card);
        });
    }

    content.appendChild(el('p', 'lead', t('nui_active_drivers', 'Active Drivers') + ' (' + employees.length + ')'));
    if (employees.length === 0) {
        content.appendChild(el('p', 'hint', t('nui_no_active_drivers', 'No active drivers.')));
    } else {
        employees.forEach(emp => {
            const rankLabel = ranks[emp.rank] ? ranks[emp.rank].label : t('nui_rank_prefix', 'Rank ') + emp.rank;
            const card = rowCard({
                title: emp.firstname + ' ' + emp.lastname,
                badge: '●',
                pill: rankLabel,
                onClick: () => {
                    details.innerHTML = '';
                    details.appendChild(el('h3', undefined, emp.firstname + ' ' + emp.lastname));
                    const cRankLabel = ranks[emp.company_rank] ? ranks[emp.company_rank].label : t('nui_rank_prefix', 'Rank ') + emp.company_rank;
                    details.appendChild(statLine(t('nui_employee_rank', 'Employee Rank'), rankLabel));
                    details.appendChild(statLine(t('nui_company_rank_stat', 'Company Rank'), cRankLabel));
                    details.appendChild(statLine(t('nui_company_xp', 'Company XP'), emp.company_xp));
                    details.appendChild(statLine(t('nui_company_missions', 'Company Missions'), emp.company_missions));
                    details.appendChild(statLine(t('nui_earnings', 'Earnings'), '$' + Math.floor(emp.total_earnings), 'gold'));
                    details.appendChild(woodBtn(t('nui_fire_driver', 'Fire Driver'), () => { nuiFetch('fireDriver', { companyId: stationData.station.company, employeeId: emp.id }).then(r => { if (r) { stationData.employees = r.employees; renderContent(); } }).catch(() => {}); }, 'danger'));
                },
            });
            content.appendChild(card);
        });
    }
}

// ========== COMPANY TRAINS (owner + driver) ==========
function renderTrains(content, details) {
    const configs = stationData.companyTrainConfigs || [];
    const ranks = stationData.ranks || {};
    const role = stationData.playerRole;

    // Get driver rank (owner = max rank 5, driver = their rank)
    let playerRank = 5;
    if (role === 'driver' && stationData.myEmployeeData) {
        playerRank = stationData.myEmployeeData.rank || 1;
    }

    if (configs.length === 0) {
        content.appendChild(el('p', 'hint', t('nui_no_trains_available', 'No trains available for this company.')));
        return;
    }

    configs.forEach(tc => {
        const canUse = playerRank >= tc.requiredRank;
        const rankLabel = ranks[tc.requiredRank] ? ranks[tc.requiredRank].label : t('nui_rank_prefix', 'Rank ') + tc.requiredRank;
        const card = rowCard({
            title: tc.label,
            desc: tc.hasPassengerCars ? t('nui_passenger_train', 'Passenger Train') : t('nui_goods_general', 'Goods & General'),
            badge: '◼',
            pill: t('nui_spd_short_prefix', 'Spd ') + tc.maxSpeed,
            pillClass: canUse ? '' : 'warn',
            locked: !canUse,
            onClick: () => {
                details.innerHTML = '';
                details.appendChild(el('h3', undefined, tc.label));
                details.appendChild(statLine(t('nui_max_speed', 'Max Speed'), tc.maxSpeed));
                details.appendChild(statLine(t('nui_max_fuel', 'Max Fuel'), tc.maxFuel));
                details.appendChild(statLine(t('nui_max_water', 'Max Water'), tc.maxWater));
                details.appendChild(statLine(t('hud_condition', 'Condition'), tc.maxCondition));
                details.appendChild(statLine(t('nui_required_rank', 'Required Rank'), rankLabel));
                details.appendChild(statLine(t('nui_upgradeable', 'Upgradeable'), tc.upgradeable ? t('yes', 'Yes') : t('no', 'No')));

                if (!canUse) {
                    details.appendChild(el('p', 'hint warn', t('nui_need_rank_prefix', 'You need ') + rankLabel + t('nui_need_rank_suffix', ' rank to use this train.')));
                } else if (stationData.canSpawn) {
                    details.appendChild(el('p', 'lead', t('nui_deploy_at_station', 'Deploy at This Station')));
                    const actions = el('div', 'detail-actions');
                    const dirLabels = [t('direction_forward', 'Forward'), t('direction_reverse', 'Reverse')];
                    dirLabels.forEach((dir, i) => {
                        actions.appendChild(woodBtn((i === 0 ? '\u25B6' : '\u25C0') + t('nui_deploy_word', ' Deploy ') + dir, () => nuiFetch('spawnTrain', { trainIndex: tc.index, direction: i === 1 })));
                    });
                    details.appendChild(actions);
                    details.appendChild(el('p', 'hint', t('nui_spawn_hint', 'Train spawns at 50% fuel, water & condition.')));
                } else {
                    details.appendChild(el('p', 'hint', t('train_already_spawned', 'You already have a train deployed.')));
                }
            },
        });
        content.appendChild(card);
    });
}

// ========== SUPPLIES (owner: add, driver/owner: take) ==========
function renderSupplies(content, details) {
    const supplies = stationData.supplies || [];
    const items = stationData.supplyItems || [];
    const role = stationData.playerRole;
    const companyId = stationData.station.company;

    if (items.length === 0) {
        content.appendChild(el('p', 'hint', t('nui_no_supplies_configured', 'No supplies configured.')));
        return;
    }

    items.forEach(si => {
        const stock = supplies.find(s => s.item_name === si.item);
        const qty = stock ? stock.quantity : 0;
        const card = rowCard({
            title: si.label,
            badge: '□',
            pill: t('nui_stock_prefix', 'Stock ') + qty,
            pillClass: qty > 0 ? 'good' : 'bad',
            onClick: () => {
                details.innerHTML = '';
                details.appendChild(el('h3', undefined, si.label));
                details.appendChild(statLine(t('nui_in_stock', 'In Stock'), qty, qty > 0 ? 'ok' : 'bad'));
                if (role === 'owner') {
                    const addInput = el('input', 'field-input');
                    addInput.type = 'number'; addInput.min = 1; addInput.value = 5;
                    details.appendChild(field(t('nui_add_quantity', 'Add Quantity'), addInput));
                    details.appendChild(woodBtn(t('nui_add_from_inventory', 'Add from Inventory'), () => {
                        const amt = parseInt(addInput.value) || 0;
                        if (amt > 0) nuiFetch('addSupply', { companyId, itemName: si.item, quantity: amt }).then(r => { if (r && r.supplies) { stationData.supplies = r.supplies; renderContent(); } }).catch(() => {});
                    }));
                }
                details.appendChild(woodBtn(t('nui_take_one', 'Take 1'), () => nuiFetch('takeSupply', { companyId, itemName: si.item, quantity: 1 }).then(r => { if (r && r.supplies) { stationData.supplies = r.supplies; renderContent(); } }), 'muted'));
            },
        });
        content.appendChild(card);
    });
}

// ========== MISSIONS (one-click jobs: script auto-picks closest stop) ==========
function renderMissions(content, details) {
    const mCfg = stationData.missions || {};
    const deliveryCfg = mCfg.delivery || {};
    const maintenanceCfg = mCfg.maintenance || {};
    const deliveryLegs = deliveryCfg.jobLegs || 1;
    const maintenanceLegs = maintenanceCfg.jobLegs || 1;

    // -- DELIVERY JOB --
    content.appendChild(el('p', 'lead', t('nui_delivery_missions_heading', 'Delivery Missions · Rank 1+')));
    content.appendChild(rowCard({
        title: t('nui_start_delivery_job', 'Start a Delivery Job'),
        desc: t('nui_autorouted_prefix', 'Auto-routed ') + deliveryLegs + t('nui_autorouted_suffix', '-stop job chain, closest stop first.'),
        badge: '✦',
        pill: '$' + (deliveryCfg.basePay || 15) + t('nui_plus_per_stop', '+/stop'),
        pillClass: 'gold',
        onClick: () => {
            details.innerHTML = '';
            details.appendChild(el('h3', undefined, t('nui_cargo_delivery_job', 'Cargo Delivery Job')));
            details.appendChild(elHTML('p', undefined, t('nui_dispatch_prefix', 'The train dispatcher will send you to the <b>') + deliveryLegs + t('nui_dispatch_suffix', '</b> closest delivery stops, one after another.')));
            details.appendChild(elHTML('p', undefined, t('nui_basepay_prefix', 'Base pay: <span class="stat-value gold">$') + (deliveryCfg.basePay || 15) + t('nui_basepay_suffix', '</span> + destination bonus, per stop.')));
            details.appendChild(el('p', 'hint', t('nui_pay_split', 'Pay split: 50% to you, 50% to company.')));
            details.appendChild(woodBtn(t('nui_start_delivery_job', 'Start a Delivery Job'), () => nuiFetch('startMission', { missionType: 'delivery' })));
        },
    }));

    // -- RAIL MAINTENANCE JOB --
    content.appendChild(el('p', 'lead', t('nui_rail_maintenance_heading', 'Rail Maintenance · Rank 3+')));
    content.appendChild(rowCard({
        title: t('nui_start_maintenance_job', 'Start a Maintenance Job'),
        desc: t('nui_traveltoprefix', 'Travel to ') + maintenanceLegs + t('nui_traveltosuffix', ' damaged sections, one after another.'),
        badge: '✦',
        pill: '$' + (maintenanceCfg.basePay || 25) + t('nui_per_stop', '/stop'),
        pillClass: 'gold',
        onClick: () => {
            details.innerHTML = '';
            details.appendChild(el('h3', undefined, t('nui_rail_maintenance_job', 'Rail Maintenance Job')));
            details.appendChild(elHTML('p', undefined, t('nui_traveltotheprefix', 'Travel to the <b>') + maintenanceLegs + t('nui_traveltothesuffix', '</b> closest damaged track sections, one after another, and repair each one.')));
            details.appendChild(el('p', 'hint', t('nui_pay_split', 'Pay split: 50% to you, 50% to company.')));
            details.appendChild(woodBtn(t('nui_start_maintenance_job', 'Start a Maintenance Job'), () => nuiFetch('startMission', { missionType: 'maintenance' })));
        },
    }));
}

// ========== MY STATS (driver) ==========
function renderMyStats(content) {
    const emp = stationData.myEmployeeData;
    const membership = stationData.myMembership || {};
    const ranks = stationData.ranks || {};

    const rankLabel = ranks[membership.rank] ? ranks[membership.rank].label : t('nui_rank_prefix', 'Rank ') + (membership.rank || 1);
    const nextRank = ranks[(membership.rank || 1) + 1];

    content.appendChild(statLine(t('nui_company_rank_stat', 'Company Rank'), rankLabel));
    content.appendChild(statLine(t('nui_company_xp', 'Company XP'), String(membership.xp || 0) + (nextRank ? ' / ' + nextRank.xpRequired : t('nui_max_suffix', ' (MAX)'))));
    content.appendChild(statLine(t('nui_tab_missions', 'Missions'), membership.missions_completed || 0));
    if (emp) content.appendChild(statLine(t('nui_earnings', 'Earnings'), '$' + Math.floor(emp.total_earnings), 'gold'));
    content.appendChild(statLine(t('nui_company', 'Company'), stationData.station.companyLabel));
}

// ========== COMPANY RECORDS ==========
function renderRecords(content, details) {
    const stats = stationData.companyStats || {};
    const o = stationData.ownership || {};
    const allStats = stationData.allCompanyStats || [];

    // This company's records
    content.appendChild(el('h3', undefined, t('nui_company_records', 'Company Records')));
    content.appendChild(statLine(t('nui_company', 'Company'), o.company_name || stationData.station.companyLabel));
    content.appendChild(statLine(t('nui_drivers', 'Drivers'), stats.total_drivers || 0));
    content.appendChild(statLine(t('nui_tab_missions', 'Missions'), stats.total_missions || 0));
    content.appendChild(statLine(t('nui_earnings', 'Earnings'), '$' + Math.floor(stats.total_earnings || 0).toLocaleString(), 'gold'));
    content.appendChild(statLine(t('nui_cash_register', 'Cash Register'), '$' + Math.floor(stats.cash_register || 0).toLocaleString()));
    content.appendChild(statLine(t('nui_top_earner', 'Top Earner'), (stats.top_earner || t('nui_none', 'None')) + ' ($' + Math.floor(stats.top_earnings || 0).toLocaleString() + ')'));
    content.appendChild(statLine(t('nui_most_missions', 'Most Missions'), (stats.most_missions_name || t('nui_none', 'None')) + ' (' + (stats.most_missions_count || 0) + ')'));
    content.appendChild(statLine(t('nui_highest_rank', 'Highest Rank'), (stats.highest_rank_name || t('nui_none', 'None')) + ' (' + (stats.highest_rank_label || '-') + ')'));

    // Leaderboard: all companies compared
    if (allStats.length > 0) {
        const sorted = [...allStats].sort((a, b) => (b.total_earnings || 0) - (a.total_earnings || 0));
        details.appendChild(el('h3', undefined, t('nui_company_leaderboard', 'Company Leaderboard')));
        sorted.forEach((cs, idx) => {
            const place = idx === 0 ? t('nui_place_1st', '1st') : idx === 1 ? t('nui_place_2nd', '2nd') : idx === 2 ? t('nui_place_3rd', '3rd') : (idx + 1) + t('nui_place_nth_suffix', 'th');
            const isCurrent = cs.company_id === stationData.station.company;
            const item = el('div', 'stat-line');
            item.appendChild(el('span', 'stat-label', place + ' · ' + (cs.company_name || cs.company_label)));
            item.appendChild(el('span', 'stat-value' + (isCurrent ? ' gold' : ''), '$' + Math.floor(cs.total_earnings || 0).toLocaleString()));
            details.appendChild(item);
            details.appendChild(el('p', 'hint', t('nui_missions_colon', 'Missions: ') + (cs.total_missions || 0) + t('nui_drivers_colon', ' · Drivers: ') + (cs.total_drivers || 0)));
        });
    } else {
        details.appendChild(el('p', 'hint', t('nui_no_companies_compare', 'No companies to compare yet.')));
    }
}

// ========== APPLY (visitor) ==========
function renderApply(content, details) {
    const comp = stationData.companies[stationData.station.company];
    content.appendChild(paperCard({
        title: comp.label,
        paras: [comp.description, t('nui_hiring_text', 'This company is hiring! Apply to become a train driver.')],
    }));
    details.appendChild(woodBtn(t('nui_tab_apply_as_driver', 'Apply as Driver'), () => { nuiFetch('applyAsDriver', { companyId: stationData.station.company }).catch(() => {}); closeStation(); }));
}

// ========== PENDING ==========
function renderPending(content) {
    const box = el('div', 'paper-card');
    box.appendChild(el('h3', undefined, t('nui_tab_application_pending', 'Application Pending')));
    box.appendChild(el('p', 'hint', t('nui_waiting_approval', 'Waiting for owner approval. Check back later!')));
    content.appendChild(box);
}

// ========== COMPANY INFO ==========
function renderCompanyInfo(content) {
    const comp = stationData.companies[stationData.station.company];
    const o = stationData.ownership;
    content.appendChild(paperCard({
        title: (o && o.company_name) ? o.company_name : comp.label,
        paras: [comp.description, o ? t('nui_owner_colon', 'Owner: ') + o.owner_name : t('nui_not_owned', 'Not owned.')],
    }));
}

// ========== TRAIN HUD ==========
function openTrainHUD(data) {
    lang = data.lang || lang || {};
    applyStaticLocale();
    document.getElementById('hudTrainLabel').textContent = data.train.label;
    document.getElementById('hudCompanyLabel').textContent = data.train.companyLabel;
    document.getElementById('trainHUD').classList.remove('hidden');
}
function closeTrainHUD() { document.getElementById('trainHUD').classList.add('hidden'); }

let staticLocaleApplied = false;
function applyStaticLocale() {
    if (staticLocaleApplied) return;
    staticLocaleApplied = true;
    const setText = (id, key, fallback) => {
        const e = document.getElementById(id);
        if (e) e.textContent = t(key, fallback);
    };
    const setTitle = (id, key, fallback) => {
        const e = document.getElementById(id);
        if (e) e.title = t(key, fallback);
    };
    setTitle('stationBackBtn', 'nui_dismiss_title', 'Dismiss');
    setTitle('closeStationBtn', 'nui_close_title', 'Close');
    setText('stationListTitle', 'nui_options', 'Options');
    setText('stationDetailTitle', 'nui_details', 'Details');
    setText('hudSpeedLabel', 'nui_hud_speed_short', 'SPD');
    setText('hudFuelLabel', 'nui_hud_fuel_short', 'FUEL');
    setText('hudWaterLabel', 'nui_hud_water_short', 'H2O');
    setText('hudCondLabel', 'nui_hud_cond_short', 'COND');
    setText('hudEngineLabel', 'nui_hud_engine_label', 'Engine');
    setText('hudCruiseLabel', 'nui_hud_cruise_label', 'Cruise');
    setText('hudJunctionLabel', 'nui_hud_junction_label', 'Junction');
    setText('hudStationLabel', 'nui_hud_station_label', 'Station');
    setText('hudMissionLabel', 'nui_hud_mission_label', 'Mission');
    setText('hudKbAccel', 'nui_kb_accel', 'Accel');
    setText('hudKbBrake', 'nui_kb_brake', 'Brake');
    setText('hudKbStop', 'nui_kb_stop', 'Stop');
    setText('hudKbCruise', 'nui_kb_cruise', 'Cruise');
    setText('hudKbSwitch', 'nui_kb_switch', 'Switch');
    setText('hudKbWhistle', 'nui_kb_whistle', 'Whistle');
}

function updateHUD(data) {
    const pct = (val, max) => max > 0 ? Math.min(100, Math.round((val / max) * 100)) : 0;
    document.getElementById('hudSpeedBar').style.width = pct(data.speed, data.maxSpeed) + '%';
    document.getElementById('hudSpeedVal').textContent = data.speed;
    document.getElementById('hudFuelBar').style.width = pct(data.fuel, data.maxFuel) + '%';
    document.getElementById('hudFuelVal').textContent = pct(data.fuel, data.maxFuel) + '%';
    document.getElementById('hudWaterBar').style.width = pct(data.water, data.maxWater) + '%';
    document.getElementById('hudWaterVal').textContent = pct(data.water, data.maxWater) + '%';
    document.getElementById('hudCondBar').style.width = pct(data.condition, data.maxCondition) + '%';
    document.getElementById('hudCondVal').textContent = pct(data.condition, data.maxCondition) + '%';

    const engineEl = document.getElementById('hudEngine');
    engineEl.textContent = data.engine ? t('hud_on', 'ON') : t('hud_off', 'OFF');
    engineEl.className = 'info-value ' + (data.engine ? 'ok' : 'bad');

    let ct = '--';
    if (data.cruiseForward) ct = t('nui_fwd_short', 'FWD'); else if (data.cruiseBackward) ct = t('nui_rev_short', 'REV');
    document.getElementById('hudCruise').textContent = ct;
    document.getElementById('hudJunction').textContent = data.junctionText || '--';
    document.getElementById('hudStation').textContent = data.nearestStation || '--';

    // Mission + destination
    const missionEl = document.getElementById('hudMission');
    const destEl = document.getElementById('hudMissionDest');
    if (data.missionActive && data.missionInfo) {
        const typeLabels = { delivery: t('nui_type_delivery', 'Delivery'), npc_transport: t('nui_type_passengers', 'Passengers'), maintenance: t('nui_type_maintenance', 'Maintenance') };
        let label = typeLabels[data.missionInfo.type] || t('nui_active_fallback', 'Active');
        if (data.missionInfo.totalLegs && data.missionInfo.totalLegs > 1) {
            label += ' (' + data.missionInfo.leg + '/' + data.missionInfo.totalLegs + ')';
        }
        missionEl.textContent = label;
        const dest = data.missionInfo.destination || data.missionInfo.location;
        destEl.textContent = dest && dest.label ? '\u2192 ' + dest.label : '';
    } else {
        missionEl.textContent = t('nui_none', 'None');
        destEl.textContent = '';
    }
}

// ========== UPGRADES ==========
function getUpgradeBonusLevel(upgradeType, level) {
    if (!level || level <= 0) return 0;
    const tiers = (stationData.upgrades || {})[upgradeType];
    if (!tiers || !tiers[level - 1]) return 0;
    return tiers[level - 1].bonus || 0;
}

function getCompanyTrainUpgrade(trainModel) {
    return (stationData.companyUpgrades || []).find(u => u.train_model === trainModel) || null;
}

function renderUpgrades(content, details) {
    const configs = (stationData.companyTrainConfigs || []).filter(tc => tc.upgradeable);
    const upgCfg = stationData.upgrades || {};
    const isOwner = stationData.playerRole === 'owner';
    const empRank = stationData.myEmployeeData ? (stationData.myEmployeeData.rank || 1) : 1;
    const canUpgrade = isOwner || (stationData.playerRole === 'driver' && empRank >= 3);
    const companyId = stationData.station.company;

    const upgTypes = [
        { key: 'speed',      label: t('nui_upg_speed', 'Speed'),          field: 'upgrade_speed' },
        { key: 'fuel_cap',   label: t('nui_upg_fuel_cap', 'Fuel Capacity'),  field: 'upgrade_fuel_cap' },
        { key: 'water_cap',  label: t('nui_upg_water_cap', 'Water Capacity'), field: 'upgrade_water_cap' },
        { key: 'durability', label: t('nui_upg_durability', 'Durability'),     field: 'upgrade_durability' },
    ];

    if (configs.length === 0) {
        content.appendChild(el('p', 'hint', t('nui_no_upgradeable_trains', 'No upgradeable trains for this company.')));
        return;
    }

    if (!canUpgrade) {
        content.appendChild(el('p', 'hint', t('nui_upgrade_engineer_required', 'Engineer rank or above required to purchase upgrades. Upgrades apply to everyone who deploys this train.')));
    }

    configs.forEach(tc => {
        const upg = getCompanyTrainUpgrade(tc.model);
        const totalUpg = upgTypes.reduce((s, u) => s + (upg ? (upg[u.field] || 0) : 0), 0);
        const maxUpg = upgTypes.length * 3;
        const card = rowCard({
            title: tc.label,
            badge: '▲',
            pill: totalUpg + '/' + maxUpg + t('nui_upg_suffix', ' upg'),
            onClick: () => {
                details.innerHTML = '';
                details.appendChild(el('h3', undefined, tc.label));
                upgTypes.forEach(upgType => {
                    const curLvl = upg ? (upg[upgType.field] || 0) : 0;
                    const tiers = upgCfg[upgType.key] || [];
                    const maxLvl = tiers.length || 3;
                    const nextLvl = curLvl + 1;
                    const nextData = nextLvl <= maxLvl ? tiers[nextLvl - 1] : null;
                    const curBonus = curLvl > 0 && tiers[curLvl - 1] ? tiers[curLvl - 1].bonus : 0;

                    const row = el('div', 'upg-row');
                    row.appendChild(el('p', 'upg-head', upgType.label + ' \u2014 ' + t('nui_lvl_label', 'Lvl ') + curLvl + '/' + maxLvl + (curBonus > 0 ? ' (+' + curBonus + ' ' + t('nui_bonus_suffix', 'bonus)') : '')));

                    if (curLvl >= maxLvl) {
                        row.appendChild(el('p', 'hint ok', '\u2713 ' + t('nui_max_level', 'MAX LEVEL')));
                    } else if (canUpgrade && nextData) {
                        const itemTxt = nextData.itemCost ? ' + ' + nextData.itemCost.amount + 'x ' + nextData.itemCost.item : '';
                        row.appendChild(el('p', 'hint', '$' + nextData.cost + itemTxt + '  \u00B7  +' + nextData.bonus + ' bonus'));
                        const btn = woodBtn(t('nui_buy_upgrade_prefix', 'Buy ') + upgType.label + ' ' + t('nui_upgrade_lvl_suffix', 'Upgrade (Lvl ') + nextLvl + ')', () => {
                            btn.disabled = true; btn.textContent = t('nui_purchasing', 'Purchasing...');
                            nuiFetch('purchaseUpgrade', { companyId, trainModel: tc.model, upgradeType: upgType.key }).then(r => {
                                if (r && r.companyUpgrades) stationData.companyUpgrades = r.companyUpgrades;
                                renderContent();
                            }).catch(() => { btn.disabled = false; btn.textContent = t('nui_buy_upgrade_prefix', 'Buy ') + upgType.label + ' ' + t('nui_upgrade_lvl_suffix', 'Upgrade (Lvl ') + nextLvl + ')'; });
                        });
                        row.appendChild(btn);
                    } else if (!canUpgrade && nextData) {
                        row.appendChild(el('p', 'hint', t('nui_next_bonus_prefix', 'Next: +') + nextData.bonus + t('nui_next_bonus_suffix', ' bonus  \u00B7  Engineer rank required')));
                    }
                    details.appendChild(row);
                });
            },
        });
        content.appendChild(card);
    });
}

// ========== EVENTS ==========
window.addEventListener('message', (event) => {
    const { action } = event.data;
    if      (action === 'openStation')    openStation(event.data);
    else if (action === 'closeStation')   { closedByLua = true; closeStation(); }
    else if (action === 'openTrainHUD')   openTrainHUD(event.data);
    else if (action === 'closeTrainHUD')  closeTrainHUD();
    else if (action === 'updateHUD')      updateHUD(event.data);
});

document.addEventListener('DOMContentLoaded', () => {
    document.getElementById('closeStationBtn').addEventListener('click', closeStation);
    document.getElementById('stationBackBtn').addEventListener('click', closeStation);
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeStation(); });
});