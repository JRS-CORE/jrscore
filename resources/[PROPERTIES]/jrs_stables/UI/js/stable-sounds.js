/* Short local sounds for the horse and wagon menu. */
(() => {
  'use strict';
  const volume = 0.28;
  const pools = {};
  for (const name of ['open','close','select','purchase']) {
    pools[name] = Array.from({length:name === 'select' ? 3 : 1}, () => {
      const sound = new Audio(`audio/${name}.wav`);
      sound.preload = 'auto'; sound.volume = volume;
      return sound;
    });
  }
  let visible = false, closing = null, lastSelect = 0;
  const play = name => {
    const sounds = pools[name];
    const sound = sounds.find(item => item.paused || item.ended) || sounds[0];
    sound.currentTime = 0;
    const result = sound.play();
    if (result?.catch) result.catch(() => {});
  };
  window.addEventListener('message', ({data}) => {
    if (data?.action === 'show') {
      if (closing !== null) { clearTimeout(closing); closing = null; }
      if (!visible) play('open');
      visible = true;
    } else if (data?.action === 'hide' && visible) {
      if (closing !== null) clearTimeout(closing);
      // Language/family refreshes hide and rebuild the same open menu.
      closing = setTimeout(() => {
        visible = false; closing = null; play('close');
      }, 140);
    }
  });
  document.addEventListener('click', event => {
    if (!visible) return;
    const target = event.target instanceof Element && event.target.closest(
      'button,[data-horse-id],[data-horse-model],.title[data-v-190398ee]'
    );
    if (!target || target.disabled || target.closest('[hidden]') || target.id === 'cancel') return;
    const confirm = typeof window.JrsStableText === 'function' && window.JrsStableText('confirm');
    if (target.classList.contains('modal-btn') &&
        (target.querySelector('img') || target.textContent.trim() === confirm)) {
      play('purchase'); return;
    }
    const now = performance.now();
    if (now - lastSelect < 50) return;
    lastSelect = now; play('select');
  }, true);
})();
