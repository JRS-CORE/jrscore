// jrs_chat | the chat window: messages, the input box, history and chat themes
'use strict';

(() => {
  const windowEl = document.getElementById('window');
  const messagesEl = document.getElementById('messages');
  const inputBox = document.getElementById('input-box');
  const input = document.getElementById('input');
  const suggestBox = document.getElementById('suggestions');
  const suggestList = document.getElementById('suggestion-list');

  const templates = { ...CONFIG.templates };
  const themeBackups = [];            // [id, old template] pairs to undo a theme
  let typing = false;
  let fadeTimer = null;
  let focusTimer = null;
  const history = [];
  let historyAt = -1;

  Object.assign(windowEl.style, CONFIG.style);

  const post = (name, body) =>
    fetch(`https://jrs_chat/${name}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(body || {}),
    }).catch(() => {});

  // ------------------------------------------------------------------ window visibility

  const showWindow = () => windowEl.classList.remove('faded');

  function armFade() {
    clearTimeout(fadeTimer);
    fadeTimer = setTimeout(() => { if (!typing) windowEl.classList.add('faded'); }, CONFIG.fadeTimeout);
  }

  function addMessage(message) {
    messagesEl.appendChild(Message.element(message, templates));
    while (messagesEl.children.length > CONFIG.maxMessages) messagesEl.firstChild.remove();
    showWindow();
    armFade();
    messagesEl.scrollTop = messagesEl.scrollHeight;
  }

  const warn = (text) => addMessage({ args: [text], template: '^3<b>CHAT-WARN</b>: ^0{0}' });

  // ------------------------------------------------------------------ the input box

  function fitInput() {
    input.style.height = '5px';
    input.style.height = `${input.scrollHeight + 2}px`;
  }

  function drawSuggestions() {
    const count = Suggestions.draw(suggestList, input.value, fill);
    suggestBox.style.display = count > 0 ? '' : 'none';
  }

  function fill(text) {
    input.value = text;
    input.focus();
    input.setSelectionRange(text.length, text.length);
    fitInput();
    drawSuggestions();
  }

  function openInput() {
    typing = true;
    inputBox.style.display = '';
    showWindow();
    clearTimeout(fadeTimer);
    clearInterval(focusTimer);
    focusTimer = setInterval(() => input.focus(), 100);
    input.focus();
  }

  function closeInput(canceled) {
    if (canceled) post('chatResult', { canceled: true });
    typing = false;
    input.value = '';
    inputBox.style.display = 'none';
    suggestBox.style.display = 'none';
    clearInterval(focusTimer);
    armFade();
  }

  function send() {
    const text = input.value;
    if (text === '') return closeInput(true);
    post('chatResult', { message: text });
    history.unshift(text);
    historyAt = -1;
    closeInput(false);
  }

  // up / down walk through what was sent before
  function walkHistory(older) {
    if (older && historyAt + 1 < history.length) input.value = history[++historyAt];
    else if (!older && historyAt - 1 >= 0) input.value = history[--historyAt];
    else if (!older && historyAt - 1 === -1) { historyAt = -1; input.value = ''; }
  }

  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowUp' || e.key === 'ArrowDown') { e.preventDefault(); walkHistory(e.key === 'ArrowUp'); }
    else if (e.key === 'PageUp') messagesEl.scrollTop -= 100;
    else if (e.key === 'PageDown') messagesEl.scrollTop += 100;
    else if (e.key === 'Enter') { e.preventDefault(); send(); }
  });
  input.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') return closeInput(true);
    fitInput();
    drawSuggestions();
  });

  // ------------------------------------------------------------------ themes from other resources

  function removeThemes() {
    document.querySelectorAll('[data-theme]').forEach((node) => node.remove());
    themeBackups.reverse().forEach(([id, old]) => { templates[id] = old; });
    themeBackups.length = 0;
  }

  function addTheme(id, theme) {
    const attach = (node) => { node.setAttribute('data-theme', id); document.head.appendChild(node); };

    if (theme.style) {
      const style = document.createElement('style');
      style.appendChild(document.createTextNode(theme.style));
      attach(style);
    }
    if (theme.styleSheet) {
      const link = document.createElement('link');
      link.rel = 'stylesheet';
      link.href = theme.baseUrl + theme.styleSheet;
      attach(link);
    }
    if (theme.script) {
      const script = document.createElement('script');
      script.src = theme.baseUrl + theme.script;
      attach(script);
    }
    Object.entries(theme.msgTemplates || {}).forEach(([tplId, html]) => {
      themeBackups.push([tplId, templates[tplId]]);
      templates[tplId] = html;
    });
  }

  // ------------------------------------------------------------------ what the game script tells us

  const handlers = {
    ON_SCREEN_STATE_CHANGE: ({ shouldHide }) => windowEl.classList.toggle('hidden', shouldHide),
    ON_OPEN: openInput,
    ON_MESSAGE: ({ message }) => addMessage(message),
    ON_CLEAR: () => { messagesEl.replaceChildren(); history.length = 0; historyAt = -1; },
    ON_SUGGESTION_ADD: ({ suggestion }) => Suggestions.add(suggestion),
    ON_SUGGESTION_REMOVE: ({ name }) => Suggestions.remove(name),
    ON_COMMANDS_RESET: () => Suggestions.reset(),
    ON_TEMPLATE_ADD: ({ template }) => {
      if (templates[template.id]) warn(`Tried to add duplicate template '${template.id}'`);
      else templates[template.id] = template.html;
    },
    ON_UPDATE_THEMES: ({ themes }) => {
      removeThemes();
      Object.entries(themes).forEach(([id, theme]) => addTheme(id, theme));
    },
  };

  window.addEventListener('message', (event) => {
    const data = event.data || event.detail;       // `detail` lets the page be tested in a browser
    const handle = data && handlers[data.type];
    if (handle) handle(data);
  });

  post('loaded');
})();
