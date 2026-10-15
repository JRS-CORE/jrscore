/* Family selector and mouse dialogs for the existing JRS stable Vue interface. */
(() => {
  'use strict';
  let payload = {}, state = {}, dialog = null, sending = false, cancelDialog = null;
  window.JrsStableFamily = 'horse';
  window.JrsStableText = key => payload.translations?.[key] || key;
  const text = key => window.JrsStableText(key);
  const post = async (name, data = {}) => {
    const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'jrs_stables';
    try { await fetch(`https://${resource}/${name}`, {method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}); }
    catch (e) { console.error('Stable action failed', e); }
  };
  const button = (label, fn, cls = '') => {
    const b = document.createElement('button'); b.type = 'button'; b.textContent = label; b.className = cls;
    b.addEventListener('click', fn); return b;
  };
  const actionSlots = () => {
    const slots = document.createElement('div'); slots.className = 'wagon-action-buttons';
    for (const action of ['call','returnWagon','cargo','repair','trade']) {
      const b = button('', () => {
        if (dialog) return;
        if (action === 'trade') showDialog({title:text('trade'),hint:text('tradeWarning'),label:text('playerId'),number:true,
          submit:value => post('wagonAction',{action,target:Number(value)})});
        else post('wagonAction', {action});
      });
      b.dataset.action = action; slots.append(b);
    }
    return slots;
  };
  const update = () => {
    const main = document.querySelector('.main[data-v-e43cd170]');
    if (!main) return;
    if (!main.querySelector('.stable-family-tabs')) {
      const tabs = document.createElement('div'); tabs.className = 'stable-family-tabs';
      for (const family of ['horse','wagon']) {
        const b = button('', () => { if (!dialog) post('stableFamily', {family}); }); b.dataset.family = family; tabs.append(b);
      }
      main.querySelector('.main-nav-buttons').before(tabs);
      const actions = document.createElement('div'); actions.className = 'wagon-actions';
      const condition = document.createElement('div'); condition.className = 'wagon-condition'; actions.append(condition);
      main.querySelector('.main-nav-buttons').after(actions);
    }
    for (const b of main.querySelectorAll('.stable-family-tabs button')) {
      const active = b.dataset.family === window.JrsStableFamily;
      const label = text(b.dataset.family === 'wagon' ? 'wagons' : 'horses');
      if (b.textContent !== label) b.textContent = label;
      b.setAttribute('aria-pressed',String(active));
      b.hidden = b.dataset.family === 'horse' && payload.canSwitch === false;
    }
    const isWagon = window.JrsStableFamily === 'wagon';
    const nav = main.querySelectorAll('.main-nav-buttons button');
    const isOwned = isWagon && nav[0]?.classList.contains('active');
    const actions = main.querySelector('.wagon-actions'); actions.hidden = !isOwned;
    // Keep ownership rows and action slots in one scroll area on smaller screens.
    // Vue recreates that area when switching pages, so reattach the slots as needed.
    const scroll = main.querySelector('.scroll-container');
    const slots = main.querySelector('.wagon-action-buttons') || actionSlots();
    if (scroll && slots.parentNode !== scroll) scroll.append(slots);
    slots.hidden = !isOwned;
    main.classList.toggle('with-wagons',isWagon);
    const condition = actions.querySelector('.wagon-condition');
    const label = state.id ? `${text('condition')}: \u2066${Math.round(state.condition ?? 100)} / ${Math.round(state.maxCondition ?? 100)}\u2069` : text('select');
    if (condition.textContent !== label) condition.textContent = label;
    for (const b of slots.querySelectorAll('button')) {
      const action = b.dataset.action, value = text(action);
      if (b.textContent !== value) b.textContent = value;
      b.disabled = action === 'returnWagon' ? !state.activeId : !state.id;
      if (action === 'call' && state.activeId) b.disabled = true;
      if (['repair','cargo'].includes(action) && state.id !== state.activeId) b.disabled = true;
      if (action === 'trade' && state.id === state.activeId) b.disabled = true;
    }
    // Tack belongs to horses; wagons have no gender or tack purchase.
    if (nav[2]) nav[2].hidden = isWagon;
    if (nav[1]) nav[1].hidden = isWagon && payload.canTrade === false;
    const save = main.querySelector('.btn-bottom-main button');
    if (save) save.hidden = isWagon;
  };
  const closeDialog = () => { if (dialog) dialog.remove(); document.querySelector('.main[data-v-e43cd170]')?.classList.remove('naming-wagon'); dialog = null; sending = false; cancelDialog = null; };
  function showDialog(options) {
    closeDialog();
    const main = document.querySelector('.main[data-v-e43cd170]'); if (!main) return;
    cancelDialog = options.cancel;
    dialog = document.createElement('form'); dialog.className = 'wagon-name-dialog';
    dialog.setAttribute('role','dialog'); dialog.setAttribute('aria-modal','true');
    const heading = document.createElement('h2'); heading.textContent = options.title; dialog.append(heading);
    if (options.hint) { const hint = document.createElement('p'); hint.textContent = options.hint; dialog.append(hint); }
    const label = document.createElement('label'); label.textContent = options.label || options.title;
    const input = document.createElement('input'); input.name = 'value'; input.required = true; input.maxLength = 30;
    input.type = options.number ? 'number' : 'text'; input.dir = options.number ? 'ltr' : 'auto';
    if (options.number) {input.min = '1';input.step = '1';} label.append(input); dialog.append(label);
    const row = document.createElement('div'); row.className = 'wagon-dialog-buttons';
    const submit = button(text('confirm'), () => {}); submit.type = 'submit';
    row.append(submit,button(text('cancel'), () => { options.cancel?.(); closeDialog(); })); dialog.append(row);
    dialog.addEventListener('submit', async e => {
      e.preventDefault(); const value = input.value.trim(); if (!value || sending) return;
      sending = true; submit.disabled = true; await options.submit(value); closeDialog();
    });
    main.classList.add('naming-wagon'); main.append(dialog); input.focus();
  }
  window.addEventListener('message', e => {
    const data = e.data; if (!data || typeof data !== 'object') return;
    if (data.action === 'show') {
      payload = data; state = {}; window.JrsStableFamily = data.family || 'horse'; closeDialog();
      document.documentElement.lang = data.language || 'en'; document.documentElement.dir = data.language === 'ar' ? 'rtl' : 'ltr';
      document.body.dataset.family = window.JrsStableFamily; queueMicrotask(update);
    } else if (data.action === 'hide') { closeDialog(); payload = {}; state = {}; }
    else if (data.action === 'wagon:status') { state = data; update(); }
    else if (data.action === 'wagon:name') showDialog({title:data.title,
      submit:name => post('wagonSubmitName',{token:data.token,name}),
      cancel:() => post('wagonSubmitName',{token:data.token,cancel:true})});
  });
  document.addEventListener('keydown', e => {
    if (e.key !== 'Escape' || !document.querySelector('.main[data-v-e43cd170]')) return;
    e.preventDefault();
    if (dialog) {cancelDialog?.();closeDialog();}
    else post('CloseStable', {MenuAction:'cancel'});
  });
  const start = () => new MutationObserver(update).observe(document.getElementById('app'),{childList:true,subtree:true});
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded',start); else start();
})();
