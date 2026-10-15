// JRS barber - jrs_stable style menu. Mouse (hover / click / arrows / wheel)
// and keyboard (arrows, Enter, Backspace / Escape, A / D rotate, W / S zoom).
const RES = (typeof GetParentResourceName === "function") ? GetParentResourceName() : "jrs_barber";

const TEXT = {
    en: { title: "Barber", style: "Style", colour: "Colour", none: "None", total: "Total", buy: "Buy", back: "Back", of: "of",
          select: "Select", change: "Change", rotate: "Rotate", zoom: "Zoom", free: "Free",
          descStyle: "Left / right to try another style.", descColour: "Left / right to change the colour.", descNone: "Pick a style first." },
    ar: { title: "الحلاق", style: "القصة", colour: "اللون", none: "بدون", total: "المجموع", buy: "شراء", back: "رجوع", of: "من",
          select: "اختيار", change: "تغيير", rotate: "تدوير", zoom: "تقريب", free: "مجاني",
          descStyle: "يمين / يسار لتجربة قصة ثانية.", descColour: "يمين / يسار لتغيير اللون.", descNone: "اختر قصة أول." },
};

let lang = "en";
let cats = [];          // [{ id, label, item, items, colour, colours }]
let rows = [];          // flattened: [{ cat, kind: 'style' | 'colour' }]
let cursor = 0;
let swatches = [];
let prices = {};
let currency = "$";
let busy = false;
let open = false;

const $ = (id) => document.getElementById(id);
const t = (k) => (TEXT[lang] || TEXT.en)[k] || TEXT.en[k] || k;

function post(name, data) {
    return fetch(`https://${RES}/barber:${name}`, {
        method: "POST",
        headers: { "Content-Type": "application/json; charset=UTF-8" },
        body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => ({}));
}

function setLanguage(code) {
    lang = String(code || "en").toLowerCase().startsWith("ar") ? "ar" : "en";
    document.body.classList.toggle("rtl", lang === "ar");
    $("title").textContent = t("title");
    $("totalLabel").textContent = t("total");
    $("buyLabel").textContent = t("buy");
    $("closeLabel").textContent = t("back");
    $("hSelect").textContent = t("select");
    $("hChange").textContent = t("change");
    $("hRotate").textContent = t("rotate");
    $("hZoom").textContent = t("zoom");
}

function setPrice(price) { $("price").textContent = currency + (Number(price) || 0).toFixed(2); }

function catOf(id) { return cats.find((c) => c.id === id); }

function flatten() {
    rows = [];
    cats.forEach((c) => {
        rows.push({ cat: c.id, kind: "style" });
        rows.push({ cat: c.id, kind: "colour" });
    });
    if (cursor >= rows.length) cursor = Math.max(0, rows.length - 1);
}

function rowEnabled(r) {
    const c = catOf(r.cat);
    if (!c) return false;
    if (r.kind === "style") return c.items > 0;
    return c.item > 0 && c.colours > 0;
}

function valueHtml(r) {
    const c = catOf(r.cat);
    if (r.kind === "style") return c.item > 0 ? `${c.item} / ${c.items}` : t("none");
    if (c.item <= 0) return "—";
    const sw = (swatches[c.colour - 1] || {}).hex;
    return (sw ? `<span class="swatch" style="background:${sw}"></span>` : "") + `${c.colour} / ${c.colours}`;
}

function render() {
    const box = $("rows");
    box.innerHTML = "";
    rows.forEach((r, i) => {
        const c = catOf(r.cat);
        const el = document.createElement("div");
        el.className = "row" + (r.kind === "colour" ? " sub" : "") + (rowEnabled(r) ? "" : " off") + (i === cursor ? " on" : "");
        const name = document.createElement("div");
        name.className = "name";
        name.textContent = r.kind === "style" ? c.label : t("colour");
        const st = document.createElement("div");
        st.className = "stepper";
        const l = document.createElement("div"); l.className = "arrow"; l.innerHTML = "&#8249;";
        const v = document.createElement("div"); v.className = "val"; v.innerHTML = valueHtml(r);
        const rr = document.createElement("div"); rr.className = "arrow"; rr.innerHTML = "&#8250;";
        l.onclick = (e) => { e.stopPropagation(); select(i, true); step(-1); };
        rr.onclick = (e) => { e.stopPropagation(); select(i, true); step(1); };
        st.append(l, v, rr);
        el.append(name, st);
        if (r.kind === "style") {
            const cost = document.createElement("div");
            cost.className = "cost";
            const p = Number(prices[r.cat]) || 0;
            cost.textContent = p > 0 ? currency + p.toFixed(2) : t("free");
            el.append(cost);
        }
        el.onmouseenter = () => { if (cursor !== i) select(i, false); };
        el.onclick = () => select(i, true);
        el.onwheel = (e) => { if (cursor === i) { e.preventDefault(); step(e.deltaY < 0 ? 1 : -1); } };
        box.append(el);
    });
    paint(true);
}

function paint(scroll) {
    const els = $("rows").children;
    for (let i = 0; i < els.length; i++) els[i].classList.toggle("on", i === cursor);
    const r = rows[cursor];
    $("count").textContent = rows.length ? `${cursor + 1} ${t("of")} ${rows.length}` : "";
    if (r) {
        const c = catOf(r.cat);
        $("desc").textContent = r.kind === "style" ? t("descStyle") : (c.item > 0 ? t("descColour") : t("descNone"));
    }
    if (scroll && els[cursor]) els[cursor].scrollIntoView({ block: "nearest" });
}

function select(i, scroll) {
    if (!rows.length) return;
    cursor = (i + rows.length) % rows.length;
    paint(scroll);
    post("focus", { category: rows[cursor].cat });
}

function move(d) {
    // skip rows that cannot change (colour of a "None" style)
    for (let n = 0; n < rows.length; n++) {
        cursor = (cursor + d + rows.length) % rows.length;
        if (rowEnabled(rows[cursor])) break;
    }
    paint(true);
    post("focus", { category: rows[cursor].cat });
}

function step(dir) {
    if (busy) return;
    const r = rows[cursor];
    if (!r || !rowEnabled(r)) return;
    const c = catOf(r.cat);
    if (r.kind === "style") {
        let v = c.item + dir;
        if (v > c.items) v = 0;
        if (v < 0) v = c.items;
        c.item = v;
        if (v > 0 && c.colour <= 0) c.colour = 1;
        post("item", { category: c.id, index: v });
    } else {
        let v = c.colour + dir;
        if (v > c.colours) v = 1;
        if (v < 1) v = c.colours;
        c.colour = v;
        post("colour", { category: c.id, index: v });
    }
    render();
}

function flash(id) { const b = $(id); b.classList.add("flash"); setTimeout(() => b.classList.remove("flash"), 120); }

function buy() {
    if (busy) return;
    busy = true;
    flash("buy");
    $("buy").classList.add("disabled");
    post("buy").then((res) => {
        if (!res || !res.ok) { busy = false; $("buy").classList.remove("disabled"); }
    });
}

function back() { if (!busy) { flash("close"); post("close"); } }

function show(data) {
    setLanguage(data.language);
    const tab = (data.tabs || [])[0] || { rows: [] };
    cats = tab.rows || [];
    swatches = data.swatches || [];
    prices = data.prices || {};
    currency = data.currency || "$";
    $("subtitle").textContent = data.subtitle || "";
    busy = false;
    cursor = 0;
    $("buy").classList.remove("disabled");
    setPrice(data.price);
    flatten();
    render();
    open = true;
    $("panel").classList.remove("hidden");
    $("hints").classList.remove("hidden");
}

function hide() {
    open = false;
    $("panel").classList.add("hidden");
    $("hints").classList.add("hidden");
}

window.addEventListener("message", (e) => {
    const data = e.data || {};
    if (data.type === "open") show(data);
    else if (data.type === "close") hide();
    else if (data.type === "row" && data.row) {
        const c = catOf(data.row.id);
        if (c) Object.assign(c, data.row);
        if (typeof data.price !== "undefined") setPrice(data.price);
        if (c) render();
    }
});

$("buy").onclick = buy;
$("close").onclick = back;

// camera: wheel outside the rows zooms
document.addEventListener("wheel", (e) => {
    if (!open || e.target.closest("#rows")) return;
    post("view", { action: e.deltaY < 0 ? "zoomIn" : "zoomOut" });
}, { passive: true });

const held = {};
document.addEventListener("keydown", (e) => {
    if (!open) return;
    const k = e.code;
    if (k === "ArrowUp") { e.preventDefault(); move(-1); }
    else if (k === "ArrowDown") { e.preventDefault(); move(1); }
    else if (k === "ArrowLeft") { e.preventDefault(); step(lang === "ar" ? 1 : -1); }
    else if (k === "ArrowRight") { e.preventDefault(); step(lang === "ar" ? -1 : 1); }
    else if (k === "Enter" || k === "NumpadEnter") { e.preventDefault(); if (!e.repeat) buy(); }
    else if (k === "Backspace" || k === "Escape") { e.preventDefault(); if (!e.repeat) back(); }
    else if (k === "KeyA" || k === "KeyD") {
        e.preventDefault();
        if (held[k]) return;
        held[k] = setInterval(() => post("view", { action: k === "KeyA" ? "rotateLeft" : "rotateRight" }), 40);
    }
    else if (k === "KeyW") post("view", { action: "zoomIn" });
    else if (k === "KeyS") post("view", { action: "zoomOut" });
});
document.addEventListener("keyup", (e) => {
    if (held[e.code]) { clearInterval(held[e.code]); held[e.code] = null; }
});
window.addEventListener("blur", () => { Object.keys(held).forEach((k) => { clearInterval(held[k]); held[k] = null; }); });
