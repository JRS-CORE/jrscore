// jrs_lockpick | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
'use strict';

// Lockpick game. The player aims a pick with the mouse and turns the lock with A/D (or the arrows).
// The closer the pick is to the hidden sweet spot, the further the lock can turn before it jams.
// Jamming wears the pick down; a broken pick costs one of the allowed tries.

(function () {
  const RULES = {
    quarter: 90,          // degrees the lock must turn to open
    reach: 90,            // the pick can swing this far either side
    sweetMargin: 4,       // degrees around the sweet spot that count as perfect
    falloff: 45,          // degrees away from the sweet spot where the lock cannot move at all
    stiffest: 0.02,       // share of the quarter turn that is still possible at that distance
    turnSpeed: 0.12,      // degrees per millisecond
    mouseDamping: 2,      // pixels of mouse movement per degree of pick movement
    wear: 20,             // health lost per jam
    wearEvery: 150,       // ms between two jams that hurt
    snapTime: 700,        // ms the break animation takes
  };
  const PUSH_KEYS = new Set(['KeyA', 'KeyD', 'KeyW', 'KeyS', 'ArrowLeft', 'ArrowRight']);

  const stage = document.getElementById('stage');
  const plug = document.getElementById('plug');
  const pick = document.getElementById('pick');
  const picksOut = document.getElementById('picks');

  let game = null;        // null while nothing is running

  const clamp = (v, lo, hi) => Math.min(Math.max(v, lo), hi);

  function post(name, data) {
    fetch(`https://${GetParentResourceName()}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data || {}),
    }).catch(() => {});
  }

  function draw() {
    pick.style.transform = `rotate(${game.aim}deg)`;
    plug.style.transform = `rotate(${game.turn}deg)`;
  }

  function newPick() {
    game.aim = 0;
    game.turn = 0;
    game.health = 100;
    game.lastWear = 0;
    pick.classList.remove('snap');
    draw();
  }

  function end(opened) {
    if (!game) return;
    cancelAnimationFrame(game.frame);
    game = null;
    stage.hidden = true;
    post('done', { opened });
  }

  // how far the lock may turn with the pick where it is now
  function allowance() {
    const off = Math.abs(game.aim - game.sweet) - RULES.sweetMargin;
    const distance = clamp(off, 0, RULES.falloff);
    const share = 1 - (1 - RULES.stiffest) * (distance / RULES.falloff);
    return share * RULES.quarter;
  }

  function wearPick(now) {
    if (now - game.lastWear < RULES.wearEvery) return;
    game.lastWear = now;
    game.health -= RULES.wear;
    game.turn = Math.max(0, game.turn - 2);             // small kick back
    if (game.health <= 0) snapPick();
  }

  function snapPick() {
    game.busy = true;
    game.tries -= 1;
    picksOut.textContent = String(Math.max(0, game.tries));
    pick.classList.add('snap');
    setTimeout(() => {
      if (!game) return;
      if (game.tries <= 0) return end(false);
      game.busy = false;
      newPick();
    }, RULES.snapTime);
  }

  function frame(now) {
    if (!game) return;
    const dt = Math.min(50, now - (game.last || now));
    game.last = now;

    if (!game.busy) {
      if (game.pushing) {
        game.turn += RULES.turnSpeed * dt;
        if (game.turn >= RULES.quarter) {
          game.turn = RULES.quarter;
          draw();
          return end(true);
        }
        const limit = allowance();
        if (game.turn >= limit) {
          game.turn = limit;
          wearPick(now);
        }
      } else if (game.turn > 0) {
        game.turn = Math.max(0, game.turn - RULES.turnSpeed * dt);
      }
      if (!game) return;
      draw();
    }
    game.frame = requestAnimationFrame(frame);
  }

  function start(msg) {
    const text = msg.text || {};
    document.getElementById('help').textContent = text.help || '';
    document.getElementById('picksLabel').textContent = text.picks || '';
    document.getElementById('escLabel').textContent = text.esc || '';
    document.body.classList.toggle('rtl', msg.rtl === true);

    const picks = clamp(Number(msg.picks) || 5, 1, 10);
    game = {
      tries: picks,
      sweet: (Math.random() * 2 - 1) * RULES.reach,      // stays the same for the whole lock
      pushing: false,
      busy: false,
      lastX: null,
      last: 0,
    };
    picksOut.textContent = String(picks);
    newPick();
    stage.hidden = false;
    game.frame = requestAnimationFrame(frame);
  }

  window.addEventListener('mousemove', (e) => {
    if (!game || game.busy) return;
    if (game.lastX !== null) {
      game.aim = clamp(game.aim + (e.clientX - game.lastX) / RULES.mouseDamping, -RULES.reach, RULES.reach);
    }
    game.lastX = e.clientX;
  });
  document.addEventListener('mouseleave', () => { if (game) game.lastX = null; });

  window.addEventListener('keydown', (e) => {
    if (game && PUSH_KEYS.has(e.code)) game.pushing = true;
  });
  window.addEventListener('keyup', (e) => {
    if (!game) return;
    if (PUSH_KEYS.has(e.code)) game.pushing = false;
    if (e.code === 'Escape') end(false);
  });

  window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.action === 'start') start(msg);
    else if (msg.action === 'stop') end(false);
  });
})();
