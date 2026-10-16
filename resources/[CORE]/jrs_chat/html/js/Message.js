// jrs_chat | turns a chat message (template + arguments) into the HTML that is shown
'use strict';

const Message = (() => {
  const ESCAPES = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' };
  const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (c) => ESCAPES[c]);

  const STYLES = {
    '*': 'font-weight: bold;',
    _: 'text-decoration: underline;',
    '~': 'text-decoration: line-through;',
    '=': 'text-decoration: underline line-through;',
    r: 'text-decoration: none;font-weight: normal;',
  };

  // ^0..^9 switch the colour; ^* ^_ ^~ ^= style the rest of the line until ^r
  function colorize(text) {
    let html = '<span>' + text.replace(/\^([0-9])/g, (_, n) => `</span><span class="color-${n}">`) + '</span>';
    const styled = /\^(_|\*|=|~|\/|r)(.*?)(?=$|\^r|<\/em>)/;
    while (styled.test(html)) {
      html = html.replace(styled, (_, code, inner) => `<em style="${STYLES[code]}">${inner}</em>`);
    }
    return html.replace(/<span[^>]*><\/span[^>]*>/g, '');
  }

  // old-style `color` ([r, g, b]) wraps the first argument
  const tint = (text, rgb) => `<span style="color: rgb(${rgb[0]}, ${rgb[1]}, ${rgb[2]})">${text}</span>`;

  // `message` = { template, templateId, args, color, multiline }; `templates` maps id -> template
  function render(message, templates) {
    const args = Array.isArray(message.args) ? message.args : [];
    let templateId = message.templateId || CONFIG.defaultTemplateId;
    let template = message.template;

    if (!template) {
      if (templateId === CONFIG.defaultTemplateId && args.length === 1) templateId = CONFIG.defaultAltTemplateId;
      template = templates[templateId] || '';
    }

    const filled = template.replace(/{(\d+)}/g, (whole, index) => {
      if (args[index] === undefined || args[index] === null) return whole;
      const safe = escapeHtml(args[index]);
      return index === '0' && message.color ? tint(safe, message.color) : safe;
    });
    return colorize(filled);
  }

  function element(message, templates) {
    const row = document.createElement('div');
    row.className = message.multiline ? 'msg multiline' : 'msg';
    const body = document.createElement('span');
    body.innerHTML = render(message, templates);
    row.appendChild(body);
    return row;
  }

  return { render, element };
})();
