(() => {
  const frame = document.getElementById('jrsTradeModule');
  if (!frame) return;
  function setInteractive(enabled) {
    frame.style.visibility = enabled ? 'visible' : 'hidden';
    frame.style.pointerEvents = enabled ? 'auto' : 'none';
  }
  window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || typeof data !== 'object') return;
    if (data.action === 'jrsPad') {
      if (frame && frame.contentWindow && frame.style.visibility === 'visible') {
        frame.contentWindow.postMessage(data, '*');
      }
      return;
    }


    // Handle callbacks from the trade child iframe back to RedM
    if (data.__jrsTradeCallback) {
      const cbName = String(data.__jrsTradeCallback);
      const cbData = data.data || {};
      if (cbName === 'closeUi' || cbName === 'cancelTrade') {
        setInteractive(false);
      }
      if (typeof $ !== 'undefined' && $.post) {
        $.post('https://jrs_inventory/' + cbName, JSON.stringify(cbData));
      } else {
        fetch('https://jrs_inventory/' + cbName, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json; charset=UTF-8' },
          body: JSON.stringify(cbData)
        }).catch(() => {});
      }
      return;
    }

    // Handle messages from client game down to trade iframe
    if (data.__jrsModule !== 'trade') return;
    const payload = data.payload || {};
    const action = String(payload.action || payload.type || '');
    if (action === 'close' || action === 'hide' || payload.open === false) setInteractive(false);
    else if (action === 'invite' || action === 'state' || action === 'open' || payload.open === true) setInteractive(true);
    if (frame.contentWindow) frame.contentWindow.postMessage(payload, '*');
  });
})();
