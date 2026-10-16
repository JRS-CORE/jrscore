// jrs_radialmenu | page glue: talks to the game script and drives the wheel
'use strict';

const PARENT = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'jrs_radialmenu';

const send = (name, body = {}) =>
    fetch(`https://${PARENT}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(body),
    }).catch(() => {});

const wheel = new RadialMenu({
    parent: document.body,
    size: 375,
    onClose: () => send('closeRadial'),
    onClick: (item) => {
        if (item.shouldClose !== false) wheel.close();
        send('selectItem', { itemData: { id: item.id, event: item.event } });
    },
});

window.addEventListener('message', ({ data }) => {
    if (!data || data.action !== 'ui') return;
    if (!data.radial) return wheel.close();
    wheel.setItems(Array.isArray(data.items) ? data.items : []);
    wheel.open();
});

// the wheel opens while a key is held: letting go of any other key closes it
document.addEventListener('keyup', ({ key }) => {
    if (key !== 'Escape' && key !== 'Backspace' && !/^[1-9]$/.test(key)) wheel.close();
});
