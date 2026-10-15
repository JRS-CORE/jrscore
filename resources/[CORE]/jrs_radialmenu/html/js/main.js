'use strict';

const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'jrs_radialmenu';

function post(name, data) {
    return fetch(`https://${RESOURCE}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}

const menu = new RadialMenu({
    parent: document.body,
    size: 375,
    onClose: () => post('closeRadial'),
    onClick: (item) => {
        if (item.items) return; // submenu, handled by RadialMenu
        if (item.shouldClose !== false) menu.close();
        post('selectItem', { itemData: { id: item.id, event: item.event } });
    },
});

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || data.action !== 'ui') return;
    if (data.radial) {
        menu.setItems(Array.isArray(data.items) ? data.items : []);
        menu.open();
    } else {
        menu.close();
    }
});

// hold-to-open: any key release closes the menu (keybind may be changed server side)
document.addEventListener('keyup', (e) => {
    if (e.key !== 'Escape' && e.key !== 'Backspace' && !/^[1-9]$/.test(e.key)) menu.close();
});
