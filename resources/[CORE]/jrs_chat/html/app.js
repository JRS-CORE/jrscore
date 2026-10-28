// ===================================================================
// JRS CHAT | Native RedM NUI Engine
// Copyright (C) 2026 JRS TEAM | All Rights Reserved
// ===================================================================

const chatContainer = document.getElementById('chat-container');
const messagesFeed = document.getElementById('chat-messages');
const inputWrapper = document.getElementById('chat-input-wrapper');
const chatInput = document.getElementById('chat-input');
const suggestionsBox = document.getElementById('chat-suggestions');

let isOpen = false;
let fadeTimeout = null;
let history = [];
let historyIdx = -1;
let registeredSuggestions = [];
let maxMessages = 80;

function post(endpoint, data = {}) {
    const resource = window.GetParentResourceName ? window.GetParentResourceName() : 'jrs_chat';
    return fetch(`https://${resource}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data)
    });
}

function resetFadeTimer() {
    chatContainer.classList.remove('fade-out');
    if (fadeTimeout) clearTimeout(fadeTimeout);

    if (!isOpen) {
        fadeTimeout = setTimeout(() => {
            if (!isOpen) {
                chatContainer.classList.add('fade-out');
            }
        }, 7000);
    }
}

function addMessage(msg) {
    chatContainer.classList.remove('hidden');
    resetFadeTimer();

    const el = document.createElement('div');
    el.className = 'chat-message';

    if (msg.type) {
        el.classList.add(`${msg.type}-message`);
    }

    let tagHtml = '';
    if (msg.tag) {
        tagHtml = `<span class="msg-tag ${msg.type || 'local'}">${msg.tag}</span>`;
    }

    let authorHtml = '';
    if (msg.author) {
        authorHtml = `<span class="msg-author">${msg.author}:</span>`;
    }

    el.innerHTML = `${tagHtml}${authorHtml}<span class="msg-content">${msg.text || ''}</span>`;
    messagesFeed.appendChild(el);

    while (messagesFeed.children.length > maxMessages) {
        messagesFeed.removeChild(messagesFeed.firstChild);
    }

    messagesFeed.scrollTop = messagesFeed.scrollHeight;
}

function openChat() {
    if (isOpen) return;
    isOpen = true;
    chatContainer.classList.remove('hidden');
    chatContainer.classList.remove('fade-out');
    chatContainer.classList.add('active');
    inputWrapper.classList.remove('hidden');
    chatInput.value = '';
    historyIdx = -1;
    setTimeout(() => chatInput.focus(), 50);
}

function closeChat() {
    if (!isOpen) return;
    isOpen = false;
    chatContainer.classList.remove('active');
    inputWrapper.classList.add('hidden');
    suggestionsBox.classList.add('hidden');
    chatInput.blur();
    resetFadeTimer();
    post('closeChat');
}

function updateSuggestions(val) {
    if (!val.startsWith('/') || registeredSuggestions.length === 0) {
        suggestionsBox.classList.add('hidden');
        return;
    }

    const query = val.slice(1).toLowerCase().split(' ')[0];
    const matches = registeredSuggestions.filter(s => s.name.toLowerCase().startsWith(query));

    if (matches.length === 0) {
        suggestionsBox.classList.add('hidden');
        return;
    }

    suggestionsBox.innerHTML = '';
    matches.slice(0, 5).forEach((item, index) => {
        const sEl = document.createElement('div');
        sEl.className = 'suggestion-item';
        if (index === 0) sEl.classList.add('active');

        sEl.innerHTML = `
            <span class="suggestion-cmd">/${item.name}</span>
            <span class="suggestion-desc">${item.help || ''}</span>
        `;
        sEl.onclick = () => {
            chatInput.value = `/${item.name} `;
            chatInput.focus();
            suggestionsBox.classList.add('hidden');
        };
        suggestionsBox.appendChild(sEl);
    });

    suggestionsBox.classList.remove('hidden');
}

chatInput.addEventListener('input', (e) => {
    updateSuggestions(e.target.value);
});

chatInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
        const val = chatInput.value.trim();
        if (val.length > 0) {
            history.unshift(val);
            if (history.length > 30) history.pop();
            post('submitMessage', { message: val });
        }
        closeChat();
    } else if (e.key === 'Escape') {
        closeChat();
    } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        if (historyIdx < history.length - 1) {
            historyIdx++;
            chatInput.value = history[historyIdx];
        }
    } else if (e.key === 'ArrowDown') {
        e.preventDefault();
        if (historyIdx > 0) {
            historyIdx--;
            chatInput.value = history[historyIdx];
        } else if (historyIdx === 0) {
            historyIdx = -1;
            chatInput.value = '';
        }
    }
});

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data) return;

    switch (data.action) {
        case 'open':
            openChat();
            break;
        case 'addMessage':
            addMessage(data.message);
            break;
        case 'clear':
            messagesFeed.innerHTML = '';
            break;
        case 'setSuggestions':
            registeredSuggestions = Array.isArray(data.suggestions) ? data.suggestions : [];
            break;
        case 'addSuggestion':
            if (data.suggestion) registeredSuggestions.push(data.suggestion);
            break;
    }
});
