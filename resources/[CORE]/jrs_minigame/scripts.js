// jrs_minigame | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
'use strict';

// Skill bar page. It runs the bar on its own clock and reports once: hit (E / click inside the zone),
// miss (outside the zone) or timeout (the bar filled up without a press).
(function () {
  const card = document.getElementById('card');
  const fill = document.getElementById('fill');
  const zone = document.getElementById('zone');

  let run = null;

  function report(hit) {
    if (!run) return;
    cancelAnimationFrame(run.frame);
    run = null;
    fetch(`https://${GetParentResourceName()}/result`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ hit }),
    }).catch(() => {});
  }

  function press() {
    if (!run) return;
    const at = run.progress;
    report(at >= run.from && at <= run.to);
  }

  function tick(now) {
    if (!run) return;
    run.progress = Math.min(100, ((now - run.began) / run.duration) * 100);
    fill.style.width = run.progress + '%';
    zone.classList.toggle('hot', run.progress >= run.from && run.progress <= run.to);
    if (run.progress >= 100) return report(false);
    run.frame = requestAnimationFrame(tick);
  }

  function open(msg) {
    document.getElementById('title').textContent = msg.text || '';
    document.getElementById('hintText').textContent = msg.hint || '';
    document.body.classList.toggle('rtl', msg.rtl === true);

    zone.style.left = msg.zoneStart + '%';
    zone.style.width = msg.zoneWidth + '%';
    fill.style.width = '0%';
    zone.classList.remove('hot');
    card.hidden = false;

    run = {
      duration: Math.max(1, Number(msg.duration) || 3000),
      from: Number(msg.zoneStart),
      to: Number(msg.zoneStart) + Number(msg.zoneWidth),
      progress: 0,
      began: performance.now(),
      frame: 0,
    };
    run.frame = requestAnimationFrame(tick);
  }

  window.addEventListener('keydown', (e) => { if (e.code === 'KeyE' && !e.repeat) press(); });
  card.addEventListener('mousedown', (e) => { if (e.button === 0) press(); });

  window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.action === 'open') open(msg);
    else if (msg.action === 'close') { card.hidden = true; if (run) { cancelAnimationFrame(run.frame); run = null; } }
  });
})();
