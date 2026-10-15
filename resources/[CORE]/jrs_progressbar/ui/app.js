// jrs_progressbar | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
'use strict';

// jrs_progressbar page: draws whatever the client script tells it to. No timers decide anything here,
// the Lua side owns the lifetime of every bar.
(function () {
  const root = document.getElementById('pb');
  const fill = root.querySelector('.pb-fill');
  const arc = root.querySelector('.pb-arc');
  const lineText = root.querySelector('.pb-line-text');
  const ringText = root.querySelector('.pb-ring-text');
  const count = root.querySelector('.pb-count');

  const THEMES = ['linear', 'circle', 'innercircle'];
  let animations = [];
  let ticker = null;

  function stopAll() {
    animations.forEach((a) => a.cancel());
    animations = [];
    if (ticker) { clearInterval(ticker); ticker = null; }
  }

  // Values come from other scripts: only let through what CSS itself accepts.
  function safeColor(value, fallback) {
    return typeof value === 'string' && CSS.supports('color', value) ? value : fallback;
  }
  function safeWidth(value, fallback) {
    return typeof value === 'string' && /^\d+(\.\d+)?(px|vw|vh|%|rem|em)$/.test(value) ? value : fallback;
  }

  function show(d) {
    stopAll();
    const theme = THEMES.includes(d.theme) ? d.theme : 'linear';
    const total = Math.max(1, Number(d.total) || 1);
    const left = Math.min(total, Math.max(0, Number(d.left) || 0));
    const done = 1 - left / total;

    root.dataset.theme = theme;
    root.style.setProperty('--pb-color', safeColor(d.color, 'rgb(242, 238, 231)'));
    root.style.setProperty('--pb-width', safeWidth(d.width, '20vw'));
    lineText.textContent = ringText.textContent = String(d.text || '');
    root.hidden = false;

    const opts = { duration: left, easing: 'linear', fill: 'forwards' };
    if (theme === 'linear') {
      animations.push(fill.animate([{ width: (done * 100) + '%' }, { width: '100%' }], opts));
    } else {
      animations.push(arc.animate([{ strokeDashoffset: 100 * (1 - done) }, { strokeDashoffset: 0 }], opts));
    }

    if (theme === 'innercircle') {
      const endsAt = performance.now() + left;
      const paint = () => { count.textContent = Math.max(0, Math.ceil((endsAt - performance.now()) / 1000)) + 's'; };
      paint();
      ticker = setInterval(paint, 200);
    }
  }

  function hide() {
    stopAll();
    root.hidden = true;
  }

  window.addEventListener('message', (event) => {
    const d = event.data || {};
    if (d.action === 'show') show(d);
    else if (d.action === 'hide') hide();
  });
})();
