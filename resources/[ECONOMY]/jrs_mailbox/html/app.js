// jrs_mailbox | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
'use strict';

// Mailbox page. Everything shown is placed with textContent: letters are plain text and can never
// run markup in another player's page.
(function () {
  const $ = (id) => document.getElementById(id);
  const app = $('app');

  let text = {};
  let letters = [];          // the inbox as last loaded
  let people = [];           // everyone a letter can go to
  let pickedId = null;       // open letter
  const deleted = new Set(); // ids removed in this visit
  const read = new Set();    // ids opened in this visit

  function post(name, data) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => null);
  }

  const t = (key) => text[key] || '';
  const view = (name) => { app.dataset.view = name; };

  // ---------------------------------------------------------------- inbox

  function dateLabel(stamp) {
    const d = new Date(stamp);
    return Number.isNaN(d.getTime()) ? '' : d.toLocaleString();
  }

  function drawLetters() {
    const list = $('letters');
    list.replaceChildren();
    const visible = letters.filter((l) => !deleted.has(l.id));

    for (const letter of visible) {
      const row = document.createElement('li');
      row.dataset.id = letter.id;
      if (!letter.opened && !read.has(letter.id)) row.classList.add('unread');
      if (letter.id === pickedId) row.classList.add('picked');

      const who = document.createElement('span');
      who.className = 'who';
      who.textContent = `${t('from')} ${letter.from}`;
      const when = document.createElement('span');
      when.className = 'when';
      when.textContent = dateLabel(letter.at);
      row.append(who, when);

      row.addEventListener('click', () => pick(letter.id));
      list.append(row);
    }
    $('emptyNote').hidden = visible.length > 0;
    if (!visible.length) { $('readFrom').textContent = ''; $('readBody').textContent = ''; }
    $('deleteBtn').disabled = $('answerBtn').disabled = !pickedId;
  }

  function pick(id) {
    pickedId = id;
    read.add(id);
    const letter = letters.find((l) => l.id === id);
    $('readFrom').textContent = letter ? `${t('from')} ${letter.from}` : '';
    $('readBody').textContent = letter ? letter.message : '';
    drawLetters();
  }

  // report what changed, then close
  function leave() {
    const changes = { delete: [...deleted], read: [...read].filter((id) => !deleted.has(id)) };
    if (changes.delete.length || changes.read.length) post('update', changes);
    app.hidden = true;
    pickedId = null;
    deleted.clear();
    read.clear();
    post('close');
  }

  // ---------------------------------------------------------------- write

  function drawPeople(filter) {
    const select = $('people');
    const needle = (filter || '').trim().toLowerCase();
    select.replaceChildren();
    for (const person of people) {
      if (needle && !person.name.toLowerCase().includes(needle)) continue;
      const option = document.createElement('option');
      option.value = person.id;
      option.textContent = person.name;
      select.append(option);
    }
    if (select.options.length) select.selectedIndex = 0;
  }

  function openCompose(toId) {
    view('compose');
    $('letterText').value = '';
    $('filter').value = '';
    drawPeople('');
    if (toId) $('people').value = toId;
    $('letterText').focus();
  }

  async function sendLetter() {
    const to = $('people').value;
    const message = $('letterText').value.trim();
    if (!to || !message) return;
    $('sendBtn').disabled = true;
    const ok = await post('send', { to, message });
    $('sendBtn').disabled = false;
    if (ok) view('inbox');
  }

  async function sendShout() {
    const message = $('shoutText').value.trim();
    if (!message) return;
    $('shoutSend').disabled = true;
    const ok = await post('shout', { message });
    $('shoutSend').disabled = false;
    if (ok) leave();
  }

  // ---------------------------------------------------------------- wiring

  $('closeBtn').addEventListener('click', leave);
  $('writeBtn').addEventListener('click', () => openCompose());
  $('cancelBtn').addEventListener('click', () => view('inbox'));
  $('sendBtn').addEventListener('click', sendLetter);
  $('shoutCancel').addEventListener('click', leave);
  $('shoutSend').addEventListener('click', sendShout);
  $('filter').addEventListener('input', (e) => drawPeople(e.target.value));

  $('deleteBtn').addEventListener('click', () => {
    if (!pickedId) return;
    deleted.add(pickedId);
    pickedId = null;
    drawLetters();
  });

  $('answerBtn').addEventListener('click', () => {
    const letter = letters.find((l) => l.id === pickedId);
    if (!letter) return;
    const target = people.find((p) => p.name === letter.from);
    openCompose(target && target.id);
  });

  window.addEventListener('keyup', (e) => { if (e.code === 'Escape' && !app.hidden) leave(); });

  window.addEventListener('message', (event) => {
    const msg = event.data || {};
    if (msg.action !== 'open') return;

    text = msg.text || {};
    letters = msg.letters || [];
    people = msg.people || [];
    document.body.classList.toggle('rtl', msg.rtl === true);

    $('title').textContent = t('title');
    $('closeBtn').textContent = t('close');
    $('writeBtn').textContent = t('write');
    $('deleteBtn').textContent = t('delete');
    $('answerBtn').textContent = t('answer');
    $('cancelBtn').textContent = $('shoutCancel').textContent = t('cancel');
    $('sendBtn').textContent = $('shoutSend').textContent = t('send');
    $('emptyNote').textContent = t('empty');
    $('toLabel').textContent = t('destination');
    $('filter').placeholder = t('search');
    $('letterText').placeholder = $('shoutText').placeholder = t('yourMessage');

    app.hidden = false;
    if (msg.mode === 'shout') {
      view('shout');
      $('shoutText').value = '';
      $('shoutText').focus();
    } else {
      view('inbox');
      pickedId = null;
      drawLetters();
    }
  });
})();
