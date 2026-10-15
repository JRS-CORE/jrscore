'use strict';

const SVG_NS = 'http://www.w3.org/2000/svg';
const MIN_SECTORS = 3;

function svgEl(tag, attrs) {
    const el = document.createElementNS(SVG_NS, tag);
    if (attrs) for (const k in attrs) el.setAttribute(k, attrs[k]);
    return el;
}

function num(n) {
    return Number.isInteger(n) ? String(n) : (+n).toFixed(4).replace(/\.?0+$/, '');
}

function degPos(deg, len) {
    const r = deg * Math.PI / 180;
    return { x: Math.sin(r) * len, y: Math.cos(r) * len };
}

function pt(p) { return num(p.x) + ' ' + num(p.y); }

// Resolves after the CSS transition finishes (with a timeout fallback so we never hang)
function setClassAndWait(node, cls) {
    return new Promise((resolve) => {
        let done = false;
        const finish = () => { if (!done) { done = true; node.removeEventListener('transitionend', onEnd); resolve(); } };
        const onEnd = (e) => { if (e.target === node) finish(); };
        node.addEventListener('transitionend', onEnd);
        node.setAttribute('class', cls);
        setTimeout(finish, 250);
    });
}

const nextTick = (fn) => requestAnimationFrame(() => requestAnimationFrame(fn));

class RadialMenu {
    constructor(params) {
        this.size = params.size || 375;
        this.onClick = params.onClick || null;
        this.onClose = params.onClose || null;

        this.radius = 55;
        this.innerRadius = 18;
        this.sectorSpace = 3.5;

        this.menuItems = [];
        this.levelItems = [];
        this.parentMenu = [];
        this.parentItems = [];
        this.currentMenu = null;

        this.holder = document.createElement('div');
        this.holder.className = 'menuHolder';
        this.holder.style.width = this.size + 'px';
        this.holder.style.height = this.size + 'px';
        params.parent.appendChild(this.holder);

        document.addEventListener('wheel', (e) => this.onMouseWheel(e));
        document.addEventListener('keydown', (e) => this.onKeyDown(e));
    }

    setItems(items) { this.menuItems = items; }

    open() {
        if (this.currentMenu) return;
        this.currentMenu = this.createMenu('menu inner', this.menuItems, false);
        this.holder.appendChild(this.currentMenu);
        nextTick(() => this.currentMenu && this.currentMenu.setAttribute('class', 'menu'));
    }

    close() {
        if (!this.currentMenu) return;
        const menu = this.currentMenu;
        this.currentMenu = null;
        this.parentMenu.forEach((m) => m.remove());
        this.parentMenu = [];
        this.parentItems = [];
        if (this.onClose) this.onClose();
        setClassAndWait(menu, 'menu inner').then(() => menu.remove());
    }

    showNestedMenu(item) {
        this.parentMenu.push(this.currentMenu);
        this.parentItems.push(this.levelItems);
        this.currentMenu = this.createMenu('menu inner', item.items, true);
        this.holder.appendChild(this.currentMenu);
        nextTick(() => {
            this.parentMenu[this.parentMenu.length - 1].setAttribute('class', 'menu outer');
            this.currentMenu.setAttribute('class', 'menu');
        });
    }

    returnToParentMenu() {
        const menu = this.currentMenu;
        const parent = this.parentMenu.pop();
        this.levelItems = this.parentItems.pop();
        this.currentMenu = parent;
        parent.setAttribute('class', 'menu');
        setClassAndWait(menu, 'menu inner').then(() => menu.remove());
    }

    handleClick(index) {
        const i = index !== undefined ? index : this.getSelectedIndex();
        const item = this.levelItems[i];
        if (!item) return;
        if (item.items) this.showNestedMenu(item);
        else if (this.onClick) this.onClick(item);
    }

    handleCenterClick() {
        if (this.parentItems.length > 0) this.returnToParentMenu();
        else this.close();
    }

    createMenu(cls, items, nested) {
        this.levelItems = items;
        const count = Math.max(items.length, MIN_SECTORS);
        const scale = this.calcScale(count);
        const svg = svgEl('svg', { class: cls, viewBox: '-50 -50 100 100', width: this.size, height: this.size });

        const step = 360 / count;
        const shift = step / 2 + (items.length === 4 ? 136 : items.length === 5 ? 145 : 241);
        const offset = items.length < count ? -2 : -1;

        for (let i = 0; i < count; i++) {
            let idx = (count - i + offset) % count;
            if (idx < 0) idx += count;
            this.appendSector(svg, shift + step * i, shift + step * (i + 0.99), items[idx] || null, idx, scale);
        }

        this.createCenter(svg, nested ? 'arrow-left' : 'circle-xmark');

        svg.addEventListener('mouseover', (e) => {
            const g = e.target.closest('g.sector');
            if (g) this.setSelectedIndex(parseInt(g.dataset.index, 10));
        });
        svg.addEventListener('click', (e) => {
            if (e.target.closest('g.sector')) this.handleClick();
            else if (e.target.closest('g.center')) this.handleCenterClick();
        });
        return svg;
    }

    createCenter(svg, icon) {
        const g = svgEl('g', { class: 'center' });
        g.appendChild(svgEl('circle', { cx: 0, cy: 0, r: this.innerRadius - this.sectorSpace }));
        g.appendChild(this.createIcon(0, 0, icon, true));
        svg.appendChild(g);
    }

    appendSector(svg, start, end, item, index, scale) {
        const c = this.getSectorCenter(start, end);
        const g = svgEl('g', {
            transform: `translate(${num((1 - scale) * c.x)},${num((1 - scale) * c.y)}) scale(${scale})`,
        });
        g.appendChild(svgEl('path', { d: this.createSectorCmds(start, end, scale) }));

        if (item) {
            g.setAttribute('class', index === 0 ? 'sector selected' : 'sector');
            g.dataset.index = index;
            if (item.title) {
                const text = svgEl('text', { 'text-anchor': 'middle', x: num(c.x), y: num(c.y), transform: item.icon ? 'translate(0,8)' : 'translate(0,2)' });
                text.textContent = item.title; // textContent: never render HTML from menu data
                g.appendChild(text);
            }
            if (item.icon) {
                // createIcon already offsets x/y; no extra transform (foreignObject honours it, nested svg did not)
                g.appendChild(this.createIcon(c.x, c.y, item.icon, !item.title));
            }
        } else {
            g.setAttribute('class', 'dummy');
        }
        svg.appendChild(g);
    }

    // Font Awesome webfont icon. Accepts 'horse-head' (solid) or full classes like 'fa-brands fa-discord'
    createIcon(x, y, name, center) {
        const fo = svgEl('foreignObject', { x: num(x - 5), y: num(y - (center ? 5 : 8)), width: 10, height: 10, class: 'icon' });
        const wrap = document.createElement('div');
        wrap.className = 'icon-wrap';
        const i = document.createElement('i');
        const cls = String(name || 'circle-question').trim();
        i.className = cls.includes('fa-') ? cls : 'fa-solid fa-' + cls;
        wrap.appendChild(i);
        fo.appendChild(wrap);
        return fo;
    }

    createSectorCmds(start, end, scale) {
        const r = this.radius, ir = this.innerRadius;
        const rs = r / scale;
        const delta = ((r - ir) - (r - ir) * scale) / 2;
        const irs = (ir + delta) / scale;
        return 'M' + pt(degPos(start, r)) +
            'A' + rs + ' ' + rs + ' 0 0 0 ' + pt(degPos(end, r)) +
            'L' + pt(degPos(end, ir)) +
            'A' + irs + ' ' + irs + ' 0 0 1 ' + pt(degPos(start, ir)) + 'Z';
    }

    calcScale(count) {
        const circle = Math.PI * 2 * this.radius;
        return ((circle - this.sectorSpace * count) / (Math.PI * 2)) / this.radius;
    }

    getSectorCenter(start, end) {
        return degPos((start + end) / 2, this.innerRadius + (this.radius - this.innerRadius) / 2);
    }

    getSelectedIndex() {
        const node = this.currentMenu && this.currentMenu.querySelector('g.selected');
        return node ? parseInt(node.dataset.index, 10) : -1;
    }

    setSelectedIndex(index) {
        if (!this.currentMenu || index < 0 || index >= this.levelItems.length) return;
        const target = this.currentMenu.querySelector(`g[data-index="${index}"]`);
        if (!target) return;
        const current = this.currentMenu.querySelector('g.selected');
        if (current) current.setAttribute('class', 'sector');
        target.setAttribute('class', 'sector selected');
    }

    selectDelta(delta) {
        const len = this.levelItems.length;
        if (!len) return;
        const i = Math.max(this.getSelectedIndex(), 0);
        this.setSelectedIndex(((i + delta) % len + len) % len);
    }

    onKeyDown(e) {
        if (!this.currentMenu) return;
        if (e.key === 'Escape' || e.key === 'Backspace') {
            e.preventDefault();
            this.handleCenterClick();
        } else if (e.key === 'Enter') {
            this.handleClick();
        } else if (/^[1-9]$/.test(e.key)) {
            this.handleClick(parseInt(e.key, 10) - 1);
        }
    }

    onMouseWheel(e) {
        if (this.currentMenu) this.selectDelta(e.deltaY < 0 ? 1 : -1);
    }
}
