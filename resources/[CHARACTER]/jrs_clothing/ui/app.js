// JRS Core Free - shared store UI (clothing + barber)
const RES = (typeof GetParentResourceName === "function") ? GetParentResourceName() : "jrs_clothing";
const NS = RES === "jrs_barber" ? "barber" : "clothing";

const TEXT = {
    en: { clothing: "TAILOR", barber: "BARBER", item: "Item", colour: "Colour", none: "None", total: "Total", buy: "Buy", close: "Close" },
    ar: { clothing: "الخياط", barber: "الحلاق", item: "القطعة", colour: "اللون", none: "بدون", total: "المجموع", buy: "شراء", close: "إغلاق" },
};

let lang = "en";
let tabs = [];
let activeTab = null;
let swatches = [];
let currency = "$";
let busy = false;

const $ = (id) => document.getElementById(id);
const t = (k) => (TEXT[lang] || TEXT.en)[k] || k;

function post(name, data) {
    return fetch(`https://${RES}/${NS}:${name}`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => ({}));
}

function setLanguage(code) {
    lang = code === "ar" ? "ar" : "en";
    document.body.classList.toggle("rtl", lang === "ar");
    $("title").textContent = t(NS);
    $("totalLabel").textContent = t("total");
    $("buy").textContent = t("buy");
    $("close").textContent = t("close");
}

function setPrice(price) {
    $("price").textContent = currency + (Number(price) || 0).toFixed(2);
}

function findRow(id) {
    for (const tab of tabs) for (const row of tab.rows) if (row.id === id) return row;
    return null;
}

function stepper(label, value, total, noneAllowed, onChange, swatchFor) {
    const wrap = document.createElement("div");
    wrap.className = "stepper" + (total > 0 ? "" : " off");
    const lbl = document.createElement("span");
    lbl.className = "lbl";
    lbl.textContent = label;
    const prev = document.createElement("button");
    prev.innerHTML = "&#8249;";
    const next = document.createElement("button");
    next.innerHTML = "&#8250;";
    const val = document.createElement("span");
    val.className = "val";
    if (value > 0) {
        const sw = swatchFor ? swatchFor(value) : null;
        val.innerHTML = (sw ? `<span class="swatch" style="background:${sw}"></span>` : "") + `${value} / ${total}`;
    } else {
        val.textContent = noneAllowed ? t("none") : `- / ${total}`;
    }
    const min = noneAllowed ? 0 : 1;
    const step = (dir) => {
        if (busy || total <= 0) return;
        let v = value + dir;
        if (v > total) v = min;
        if (v < min) v = total;
        onChange(v);
    };
    prev.onclick = () => step(lang === "ar" ? 1 : -1);
    next.onclick = () => step(lang === "ar" ? -1 : 1);
    wrap.append(lbl, prev, val, next);
    return wrap;
}

function renderRow(row) {
    const el = document.createElement("div");
    el.className = "row";
    el.dataset.id = row.id;
    const name = document.createElement("div");
    name.className = "name";
    name.textContent = row.label;
    el.append(name);
    el.append(stepper(t("item"), row.item, row.items, true, (v) => {
        row.item = v;
        row.colour = v > 0 ? 1 : 0;
        rerender(row);
        post("item", { category: row.id, index: v });
    }));
    const colourSwatch = row.swatches ? (v) => (swatches[v - 1] || {}).hex : null;
    el.append(stepper(t("colour"), row.colour, row.item > 0 ? row.colours : 0, false, (v) => {
        row.colour = v;
        rerender(row);
        post("colour", { category: row.id, index: v });
    }, colourSwatch));
    el.onmouseenter = () => post("focus", { category: row.id, group: activeTab });
    return el;
}

function rerender(row) {
    const el = document.querySelector(`.row[data-id="${CSS.escape(row.id)}"]`);
    if (el) el.replaceWith(renderRow(row));
}

function renderRows() {
    const box = $("rows");
    box.innerHTML = "";
    const tab = tabs.find((x) => x.id === activeTab) || tabs[0];
    if (!tab) return;
    tab.rows.forEach((row) => box.append(renderRow(row)));
}

function renderTabs() {
    const box = $("tabs");
    box.innerHTML = "";
    $("tabs").classList.toggle("hidden", tabs.length < 2);
    tabs.forEach((tab) => {
        const b = document.createElement("button");
        b.textContent = tab.label;
        if (tab.id === activeTab) b.classList.add("active");
        b.onclick = () => {
            activeTab = tab.id;
            renderTabs();
            renderRows();
            post("focus", { category: tab.id, group: tab.id });
        };
        box.append(b);
    });
}

function open(data) {
    setLanguage(data.language);
    tabs = data.tabs || [];
    swatches = data.swatches || [];
    currency = data.currency || "$";
    activeTab = tabs.length ? tabs[0].id : null;
    busy = false;
    $("buy").disabled = false;
    setPrice(data.price);
    renderTabs();
    renderRows();
    $("panel").classList.remove("hidden");
    $("rotate").classList.remove("hidden");
}

function close() {
    $("panel").classList.add("hidden");
    $("rotate").classList.add("hidden");
}

window.addEventListener("message", (e) => {
    const data = e.data || {};
    if (data.type === "open") open(data);
    else if (data.type === "close") close();
    else if (data.type === "row" && data.row) {
        const row = findRow(data.row.id);
        if (row) Object.assign(row, data.row);
        if (typeof data.price !== "undefined") setPrice(data.price);
        if (row) rerender(row);
    }
});

$("buy").onclick = () => {
    if (busy) return;
    busy = true;
    $("buy").disabled = true;
    post("buy").then((res) => {
        if (!res || !res.ok) {
            busy = false;
            $("buy").disabled = false;
        }
    });
};
$("close").onclick = () => { if (!busy) post("close"); };
document.querySelectorAll("#rotate button").forEach((b) => {
    b.onclick = () => post("rotate", { dir: b.dataset.dir });
});
document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !busy && !$("panel").classList.contains("hidden")) post("close");
});
