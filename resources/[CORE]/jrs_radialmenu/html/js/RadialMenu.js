// jrs_radialmenu | the wheel. Draws a ring of sectors as SVG, tracks the highlighted sector and the stack of
// opened submenus. Item titles are written with textContent, so menu data can never inject HTML.
'use strict';

const RadialMenu = (() => {
    const NS = 'http://www.w3.org/2000/svg';
    const MIN_SECTORS = 3;
    const OUTER = 55, INNER = 18, GAP = 3.5;

    const make = (tag, attrs = {}) => {
        const node = document.createElementNS(NS, tag);
        Object.entries(attrs).forEach(([key, value]) => node.setAttribute(key, value));
        return node;
    };

    // point at `angle` degrees clockwise from the top, `radius` away from the middle
    const polar = (angle, radius) => {
        const rad = angle * Math.PI / 180;
        return [Math.sin(rad) * radius, -Math.cos(rad) * radius];
    };
    const fmt = ([x, y]) => `${+x.toFixed(3)} ${+y.toFixed(3)}`;

    // an arc-shaped sector between two angles
    const sectorPath = (from, to) => {
        const gapAngle = (GAP / (Math.PI * 2 * OUTER)) * 360;
        const a = from + gapAngle / 2, b = to - gapAngle / 2;
        return `M${fmt(polar(a, OUTER))}A${OUTER} ${OUTER} 0 0 1 ${fmt(polar(b, OUTER))}` +
               `L${fmt(polar(b, INNER))}A${INNER} ${INNER} 0 0 0 ${fmt(polar(a, INNER))}Z`;
    };

    const nextFrame = (fn) => requestAnimationFrame(() => requestAnimationFrame(fn));

    // sets the class, resolves when the css transition has ended (or after a safety timeout)
    const restyle = (node, cls) => new Promise((resolve) => {
        const end = (event) => {
            if (event && event.target !== node) return;
            node.removeEventListener('transitionend', end);
            resolve();
        };
        node.addEventListener('transitionend', end);
        node.setAttribute('class', cls);
        setTimeout(end, 250);
    });

    // a Font Awesome glyph: 'horse-head' means solid, a full 'fa-brands fa-discord' is used as is
    const glyph = (x, y, name, centred) => {
        const box = make('foreignObject', { x: x - 5, y: y - (centred ? 5 : 8), width: 10, height: 10, class: 'icon' });
        const wrap = document.createElement('div');
        wrap.className = 'icon-wrap';
        const i = document.createElement('i');
        const given = String(name || 'circle-question').trim();
        i.className = given.includes('fa-') ? given : `fa-solid fa-${given}`;
        wrap.appendChild(i);
        box.appendChild(wrap);
        return box;
    };

    return class {
        constructor({ parent, size = 375, onClick = null, onClose = null }) {
            this.size = size;
            this.onClick = onClick;
            this.onClose = onClose;
            this.items = [];            // top level
            this.shown = [];            // items of the ring on screen
            this.rings = [];            // svg elements, the last one is on screen
            this.trail = [];            // item lists of the rings below the visible one

            this.holder = document.createElement('div');
            this.holder.className = 'menuHolder';
            this.holder.style.width = this.holder.style.height = `${size}px`;
            parent.appendChild(this.holder);

            document.addEventListener('wheel', (e) => this.scroll(e.deltaY < 0 ? 1 : -1));
            document.addEventListener('keydown', (e) => this.key(e));
        }

        get ring() { return this.rings[this.rings.length - 1]; }

        setItems(items) { this.items = items; }

        open() {
            if (this.ring) return;
            this.push(this.items, false);
        }

        close() {
            const ring = this.ring;
            if (!ring) return;
            const stale = this.rings.slice(0, -1);
            this.rings = [];
            this.trail = [];
            stale.forEach((node) => node.remove());
            if (this.onClose) this.onClose();
            restyle(ring, 'menu inner').then(() => ring.remove());
        }

        // shows a ring for `list`; a submenu hides the one below it
        push(list, nested) {
            const below = this.ring;
            if (below) this.trail.push(this.shown);
            this.shown = list;

            const ring = this.build(list, nested);
            this.rings.push(ring);
            this.holder.appendChild(ring);
            nextFrame(() => {
                if (below) below.setAttribute('class', 'menu outer');
                ring.setAttribute('class', 'menu');
            });
        }

        pop() {
            const gone = this.rings.pop();
            this.shown = this.trail.pop();
            this.ring.setAttribute('class', 'menu');
            restyle(gone, 'menu inner').then(() => gone.remove());
        }

        build(list, nested) {
            const count = Math.max(list.length, MIN_SECTORS);
            const svg = make('svg', { class: 'menu inner', viewBox: '-50 -50 100 100', width: this.size, height: this.size });
            const span = 360 / count;

            for (let i = 0; i < count; i++) {
                const item = list[i];
                const from = i * span - span / 2, to = from + span;
                const middle = polar((from + to) / 2, INNER + (OUTER - INNER) / 2);
                const g = make('g', { class: item ? (i === 0 ? 'sector selected' : 'sector') : 'dummy' });
                g.appendChild(make('path', { d: sectorPath(from, to) }));

                if (item) {
                    g.dataset.index = i;
                    if (item.title) {
                        const label = make('text', { 'text-anchor': 'middle', x: middle[0], y: middle[1], transform: item.icon ? 'translate(0,8)' : 'translate(0,2)' });
                        label.textContent = item.title;
                        g.appendChild(label);
                    }
                    if (item.icon) g.appendChild(glyph(middle[0], middle[1], item.icon, !item.title));
                }
                svg.appendChild(g);
            }

            const hub = make('g', { class: 'center' });
            hub.appendChild(make('circle', { cx: 0, cy: 0, r: INNER - GAP }));
            hub.appendChild(glyph(0, 0, nested ? 'arrow-left' : 'circle-xmark', true));
            svg.appendChild(hub);

            svg.addEventListener('mouseover', (e) => {
                const g = e.target.closest('g.sector');
                if (g) this.highlight(+g.dataset.index);
            });
            svg.addEventListener('click', (e) => {
                if (e.target.closest('g.sector')) this.choose();
                else if (e.target.closest('g.center')) this.back();
            });
            return svg;
        }

        highlighted() {
            const g = this.ring && this.ring.querySelector('g.selected');
            return g ? +g.dataset.index : -1;
        }

        highlight(index) {
            if (!this.ring || index < 0 || index >= this.shown.length) return;
            const next = this.ring.querySelector(`g[data-index="${index}"]`);
            if (!next) return;
            const old = this.ring.querySelector('g.selected');
            if (old) old.setAttribute('class', 'sector');
            next.setAttribute('class', 'sector selected');
        }

        scroll(step) {
            const n = this.shown.length;
            if (!this.ring || !n) return;
            this.highlight((((Math.max(this.highlighted(), 0) + step) % n) + n) % n);
        }

        choose(index = this.highlighted()) {
            const item = this.shown[index];
            if (!item) return;
            if (item.items) this.push(item.items, true);
            else if (this.onClick) this.onClick(item);
        }

        back() {
            if (this.trail.length) this.pop(); else this.close();
        }

        key(e) {
            if (!this.ring) return;
            if (e.key === 'Escape' || e.key === 'Backspace') { e.preventDefault(); this.back(); }
            else if (e.key === 'Enter') this.choose();
            else if (/^[1-9]$/.test(e.key)) this.choose(+e.key - 1);
        }
    };
})();
