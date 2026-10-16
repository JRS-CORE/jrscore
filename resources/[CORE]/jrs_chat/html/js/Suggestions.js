// jrs_chat | the command suggestions under the input box
'use strict';

const Suggestions = (() => {
  const known = [];            // { name, help, params: [{ name, help }] }
  const hidden = new Set();    // names removed with chat:removeSuggestion

  function add(suggestion) {
    const params = suggestion.params || [];
    const existing = known.find((s) => s.name === suggestion.name);
    if (existing) {
      if (suggestion.help || suggestion.params) {
        existing.help = suggestion.help || '';
        existing.params = params;
      }
      return;
    }
    hidden.delete(suggestion.name);
    known.push({ name: suggestion.name, help: suggestion.help || '', params });
  }

  const remove = (name) => hidden.add(name);
  const reset = () => { known.length = 0; hidden.clear(); };

  // does the typed text still fit this suggestion (command name first, then its parameters)?
  function fits(suggestion, typed) {
    if (suggestion.name.startsWith(typed)) return true;
    const want = suggestion.name.split(' ');
    const have = typed.split(' ');
    for (let i = 0; i < have.length; i++) {
      if (i >= want.length) return i < want.length + suggestion.params.length;
      if (want[i] !== have[i]) return false;
    }
    return true;
  }

  // the suggestions to show for `typed`, with a `disabled` mark on the parts already past
  function matching(typed) {
    if (!typed) return [];
    return known
      .filter((s) => !hidden.has(s.name) && fits(s, typed))
      .slice(0, CONFIG.suggestionLimit)
      .map((s) => ({
        ...s,
        disabled: !s.name.startsWith(typed),
        params: s.params.map((p, i) => {
          const tail = i === s.params.length - 1 ? '.' : '\\S';
          const pattern = new RegExp(`${s.name} (?:\\w+ ){${i}}(?:${tail}*)$`);
          return { ...p, disabled: !pattern.test(typed) };
        }),
      }));
  }

  const part = (tag, text, cls) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    node.textContent = text;
    return node;
  };

  // fills `list` with the matches; `onPick(text)` is called when one is clicked
  function draw(list, typed, onPick) {
    const shown = matching(typed);
    list.replaceChildren();
    shown.forEach((s) => {
      const li = document.createElement('li');
      li.className = 'suggestion';
      li.style.cursor = 'pointer';
      li.addEventListener('mousedown', (e) => { e.preventDefault(); onPick(`${s.name} `); });

      const line = document.createElement('p');
      line.appendChild(part('span', s.name, s.disabled ? 'disabled' : ''));
      s.params.forEach((p) => line.appendChild(part('span', ` [${p.name}]`, p.disabled ? 'param disabled' : 'param')));
      li.appendChild(line);

      const help = [s.disabled ? '' : s.help, ...s.params.filter((p) => !p.disabled).map((p) => p.help)].filter(Boolean).join(' ');
      li.appendChild(part('small', help, 'help'));
      list.appendChild(li);
    });
    return shown.length;
  }

  return { add, remove, reset, draw };
})();
