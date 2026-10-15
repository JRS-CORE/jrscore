(() => {
  const modules = {
    input: document.getElementById('jrsInputModule'),
    menu: document.getElementById('jrsMenuModule'),
    notify: document.getElementById('jrsNotifyModule'),
    extinput: document.getElementById('jrsExtInputModule'),
    extlib: document.getElementById('jrsExtLibModule')
  };

  function visible(frame, enabled, interactive) {
    if (!frame) return;
    frame.style.visibility = enabled ? 'visible' : 'hidden';
    frame.style.pointerEvents = interactive && enabled ? 'auto' : 'none';
  }

  /** Forward a message to every loaded module iframe */
  function broadcastToModules(msg) {
    Object.values(modules).forEach(function(frame) {
      if (frame && frame.contentWindow) {
        try { frame.contentWindow.postMessage(msg, '*'); } catch (e) {}
      }
    });
  }

  // Menu: the iframe reports how many menus are open; it takes the mouse while
  // a menu is up (unless another dialog sits on top) and gets the keyboard
  // forwarded when the top page holds the focus.
  let menuOpen = 0;
  let extlibFocus = false;
  function overlayOpen() {
    const vis = (f) => f && f.style.visibility === 'visible' && f.style.pointerEvents === 'auto';
    return vis(modules.input) || vis(modules.extinput) || extlibFocus;
  }
  function syncMenuPointer() {
    if (modules.menu) modules.menu.style.pointerEvents = (menuOpen > 0 && !overlayOpen()) ? 'auto' : 'none';
  }
  window.addEventListener('keydown', (ev) => {
    if (menuOpen <= 0 || overlayOpen()) return;
    const t = ev.target;
    if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
    const keys = ['ArrowUp','ArrowDown','ArrowLeft','ArrowRight','Enter','NumpadEnter','Space','Backspace','Escape','Home','End','PageUp','PageDown','KeyW','KeyS','KeyA','KeyD'];
    if (keys.indexOf(ev.code) === -1) return;
    ev.preventDefault();
    if (modules.menu && modules.menu.contentWindow) {
      modules.menu.contentWindow.postMessage({ __jrsMenuKey: { code: ev.code, key: ev.key, repeat: ev.repeat } }, '*');
    }
  });

  window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || typeof data !== 'object') return;
    if (data.__jrsMenuState) { menuOpen = Number(data.open) || 0; syncMenuPointer(); return; }
    if (data.action === 'jrsPad') {
      broadcastToModules(data);
      return;
    }


    // Forward language changes so iframes can translate data-i18n elements
    if (data.type === 'jrsLanguage' || data.action === 'jrsLanguage') {
      broadcastToModules(data);
      return;
    }

    if (!data.__jrsModule) return;
    const name = String(data.__jrsModule);
    const frame = modules[name];
    if (!frame || !frame.contentWindow) return;
    if (name === 'extlib' && typeof data.focus === 'boolean') { extlibFocus = data.focus; visible(frame, true, data.focus); syncMenuPointer(); return; }
    const payload = data.payload || {};

    if (name === 'input') {
      const opening = (payload.type === 'open_inputs' || payload.type === 'open_answer') && payload.status !== false;
      const closing = (payload.type === 'open_inputs' || payload.type === 'open_answer') && payload.status === false;
      if (opening) visible(frame, true, true);
      if (closing) visible(frame, false, false);
    } else if (name === 'menu') {
      frame.style.visibility = 'visible';
    } else if (name === 'extinput') {
      const show = payload.style !== 'none';
      visible(frame, show, show);
    } else if (name === 'extlib') {
      frame.style.visibility = 'visible';
    } else if (name === 'notify') {
      visible(frame, true, false);
    }

    frame.contentWindow.postMessage(payload, '*');
    syncMenuPointer();
  });
})();
