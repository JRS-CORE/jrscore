// jrs_chat | page settings
window.CONFIG = {
  defaultTemplateId: 'default',        // used for messages with two or more arguments
  defaultAltTemplateId: 'defaultAlt',  // used when the message has a single argument
  templates: {                         // static templates, more can be added with chat:addTemplate
    default: '<div class="chat-message">OOC {0}: {1}</div>',
    defaultAlt: '{0}',
    print: '<pre>{0}</pre>',
    'example:important': '<h1>^2{0}</h1>',
  },
  fadeTimeout: 10000,                  // ms until the window fades when nobody is typing
  suggestionLimit: 5,
  maxMessages: 5,
  style: { background: 'transparent', width: '38%', height: '22%' },
};
