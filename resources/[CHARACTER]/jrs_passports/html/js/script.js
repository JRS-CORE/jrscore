// jrs_passports | the passport card. Texts are written with textContent, the photo is a CSS background.
'use strict';

const card = document.getElementById('jrs_passports');
const $ = (id) => document.getElementById(id);
const say = (id, text) => { $(id).textContent = text == null ? '' : String(text); };

let fadeTimer;
function fadeIn(ms) {
  clearTimeout(fadeTimer);
  card.style.transition = `opacity ${ms}ms`;
  card.style.display = 'block';
  requestAnimationFrame(() => { card.style.opacity = '1'; });
}
function fadeOut(ms) {
  card.style.transition = `opacity ${ms}ms`;
  card.style.opacity = '0';
  fadeTimer = setTimeout(() => { card.style.display = 'none'; }, ms);
}

function closeCard() {
  fadeOut(1000);
  fetch('https://jrs_passports/close', { method: 'POST', body: '{}' }).catch(() => {});
}

function fill(info, words) {
  const name = `${info.firstname} ${info.lastname}`;
  say('main-full-name-title', words.fullname);
  say('main-full-name-text', name);
  say('main-dob-title', words.dob);
  say('main-dob-text', info.dob);
  say('main-sex-title', words.sex);
  say('main-sex-text', info.sex);
  say('main-id-text', info.identity_id);
  say('main-signature-title', words.signature);
  say('main-signature-text', name);
  say('main-expiration-title', info.expiration);
  $('main-avatar-image-display').style.backgroundImage = `url("${String(info.avatar_url).replace(/["\\\n]/g, '')}")`;
}

window.addEventListener('message', ({ data }) => {
  if (data.type === 'enable') {
    document.body.style.display = data.enable ? 'block' : 'none';
  } else if (data.action === 'updateInformation') {
    fill(data.info, data.locales);
    $('center-side').style.display = 'block';
    fadeIn(1000);
  } else if (data.action === 'close') {
    closeCard();
  }
});

card.style.display = 'none';
