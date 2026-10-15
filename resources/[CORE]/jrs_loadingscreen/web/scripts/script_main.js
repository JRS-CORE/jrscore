import IMAGES_SCREEN from './script_images.js';
import MUSIC_PLAYER from './script_music.js';
import PROGRESS_INDICATOR from './script_progress.js';
import TEAM_SYSTEM from './script_team.js';
import VIDEO_PLAYER from './script_video.js';
import CONFIG from '../config_main.js';
import LANGUAGE from './script_lang.js';

// The phase list lives in the language packs; this reads whichever one is
// active so a language switch mid-load takes effect on the next tick.
const loadingPhases = () => LANGUAGE.t('phases', []);

// 2.8.0: only plain https links may be handed to invokeNative('openUrl').
const isSafeUrl = (url) => typeof url === 'string' && /^https:\/\/[^\s"'<>]+$/i.test(url);

const LOADING_SCREEN = {
    currentProgress: 0,
    isStarted: false,
    isComplete: false,
    userInfoPoll: null,
    introHideTimer: null,

    start() {
        if (this.isStarted) return;
        this.isStarted = true;

        document.body.classList.add('loaded');
        window.LOADING_PROGRESS = this.currentProgress;

        // Language first: everything built below reads its text through it, and
        // a stored choice from a previous connect applies before the first paint.
        LANGUAGE.init();
        LANGUAGE.onChange(() => {
            this.updateLoadingText();
            const warning = document.getElementById('server-warning');
            if (warning && CONFIG.SERVER_WARNING) {
                warning.textContent = LANGUAGE.pick(CONFIG, 'SERVER_WARNING');
            }
            const desc = document.getElementById('server-description');
            if (desc && CONFIG.SERVER_DESCRIPTION) {
                desc.textContent = LANGUAGE.pick(CONFIG, 'SERVER_DESCRIPTION');
            }
            const userName = document.getElementById('user-name');
            if (userName && !userName.dataset.realName) {
                userName.textContent = LANGUAGE.t('outsider');
            }
            this.setupInfoButtons();
            if (typeof MUSIC_PLAYER.updateMusicTitle === 'function') {
                MUSIC_PLAYER.updateMusicTitle();
            }
            if (typeof TEAM_SYSTEM.refreshLanguage === 'function') {
                TEAM_SYSTEM.refreshLanguage();
            }
        });

        // Everything visible to the player is initialized immediately. We no longer wait
        // for the first loadProgress event or the old 5-second intro timer.
        this.updateUserInfo(window.nuiHandoverData || {});
        this.startUserInfoSync();
        this.setupSocialButtons();
        this.setupInfoButtons();
        this.startBackdrop();

        if (CONFIG.MUSIC.ENABLE || CONFIG.MUSIC.ENABLE_CONTROLS) MUSIC_PLAYER.init();
        TEAM_SYSTEM.init();

        this.showBorderImage();
        this.showUiElements();
        this.showIntroText();
        PROGRESS_INDICATOR.init();
    },

    startUserInfoSync() {
        if (this.userInfoPoll) return;

        let attempts = 0;
        const maxAttempts = 80;

        const sync = () => {
            const handover = window.nuiHandoverData;
            if (handover && typeof handover === 'object' && Object.keys(handover).length > 0) {
                this.updateUserInfo(handover);

                // Once the meaningful fields are present there is no reason to keep polling.
                if (handover.name || handover.avatarUrl || handover.maxPlayers !== undefined) {
                    this.userInfoPoll = null;
                    return;
                }
            }

            attempts += 1;
            if (attempts >= maxAttempts) {
                this.userInfoPoll = null;
                return;
            }

            this.userInfoPoll = setTimeout(sync, 50);
        };

        sync();
    },

    updateUserInfo(data) {
        if (!data || typeof data !== 'object') return;

        const userAvatar = document.querySelector('#user-avatar img');
        const userName = document.getElementById('user-name');
        const userRole = document.getElementById('user-role');
        const playerCountText = document.getElementById('player-count-text');

        if (data.avatarUrl && userAvatar && /^(assets\/|https:\/\/)[^\s"'<>]*$/.test(String(data.avatarUrl))) {
            userAvatar.onerror = () => {
                userAvatar.onerror = null;
                userAvatar.src = 'assets/images/default_avatar.jpg';
            };
            userAvatar.src = data.avatarUrl;
        }

        if (userName) {
            if (data.name && data.name !== 'Outsider') {
                userName.dataset.realName = data.name;
                userName.textContent = data.name;
            } else if (!userName.dataset.realName) {
                userName.textContent = LANGUAGE.t('outsider');
            }
        }

        if (userRole) {
            if (data.role) {
                userRole.textContent = data.role;
                userRole.style.display = 'block';
            } else {
                userRole.textContent = '';
                userRole.style.display = 'none';
            }
        }

        if (playerCountText && data.currentPlayers !== undefined && data.maxPlayers !== undefined) {
            const current = Math.max(0, Math.floor(Number(data.currentPlayers) || 0));
            const max = Math.max(0, Math.floor(Number(data.maxPlayers) || 0));
            playerCountText.textContent = `${current}/${max}`;
        }
    },

    startBackdrop() {
        const video = document.getElementById('video');
        const imageSlider = document.getElementById('image-slider');

        // Video and slideshow are mutually exclusive at runtime. This prevents the
        // unused system from decoding/animating behind the active background.
        if (CONFIG.VIDEO.ENABLE) {
            if (imageSlider) imageSlider.style.display = 'none';
            if (video) video.style.display = 'block';
            VIDEO_PLAYER.init();
            return;
        }

        if (video) {
            video.pause?.();
            video.removeAttribute('src');
            video.style.display = 'none';
        }
        if (imageSlider) imageSlider.style.display = 'block';

        IMAGES_SCREEN.init();
        IMAGES_SCREEN.loadFirstImage();

        if (CONFIG.IMAGES.ENABLE_OVERLAY) {
            const transitionOverlay = document.getElementById('transition-overlay');
            if (transitionOverlay) {
                transitionOverlay.src = 'assets/images/reveal1.png';
                transitionOverlay.classList.add('active');
            }

            IMAGES_SCREEN.startInitialReveal(() => IMAGES_SCREEN.startNormalLoop());
        } else {
            IMAGES_SCREEN.startNormalLoop();
        }
    },

    showIntroText() {
        if (CONFIG.ENABLE_SERVER_LOGO) {
            const serverLogo = document.getElementById('server-logo');
            if (serverLogo && CONFIG.SERVER_LOGO) {
                serverLogo.src = `assets/images/${CONFIG.SERVER_LOGO}`;
                serverLogo.classList.add('active');
            }
        } else {
            const serverName = document.getElementById('server-name');
            if (serverName && CONFIG.SERVER_NAME) {
                serverName.textContent = CONFIG.SERVER_NAME;
                serverName.classList.add('active');
            }
        }

        const serverWarning = document.getElementById('server-warning');
        if (serverWarning && CONFIG.SERVER_WARNING) {
            serverWarning.textContent = LANGUAGE.pick(CONFIG, 'SERVER_WARNING');
            serverWarning.style.display = 'block';
            requestAnimationFrame(() => serverWarning.classList.add('active'));
        }

        const serverDescription = document.getElementById('server-description');
        if (serverDescription && CONFIG.SERVER_DESCRIPTION) {
            serverDescription.textContent = LANGUAGE.pick(CONFIG, 'SERVER_DESCRIPTION');
            serverDescription.style.display = 'block';
            requestAnimationFrame(() => serverDescription.classList.add('active'));
        }

        const introDuration = Math.max(0, Number(CONFIG.INITIAL_REVEAL_DURATION) || 0);
        if (introDuration > 0) {
            this.introHideTimer = setTimeout(() => this.hideIntroText(), introDuration);
        }
    },

    hideIntroText() {
        document.getElementById('server-name')?.classList.remove('active');
        document.getElementById('server-logo')?.classList.remove('active');
        document.getElementById('server-description')?.classList.remove('active');
        document.getElementById('server-warning')?.classList.remove('active');
    },

    showUiElements() {
        document.getElementById('loading-progress-container')?.classList.add('visible');

        if (CONFIG.USER_CARD.ENABLE) {
            document.getElementById('user-info-card')?.classList.add('visible');
        }

        TEAM_SYSTEM.show();

        const toggleBtn = document.getElementById('btn-toggle-controls');
        if (CONFIG.MUSIC.ENABLE_CONTROLS) {
            toggleBtn?.classList.add('active', 'visible');

            const musicControls = document.getElementById('music-controls');
            if (musicControls) {
                musicControls.classList.add('active', 'visible');
                musicControls.classList.remove('hidden');
                musicControls.style.display = 'flex';
            }
        }
    },

    setupSocialButtons() {
        const bindings = [
            ['btn-discord', CONFIG.SOCIALS.DISCORD],
            ['btn-youtube', CONFIG.SOCIALS.YOUTUBE],
            ['btn-website', CONFIG.SOCIALS.WEBSITE],
        ];

        for (const [id, social] of bindings) {
            const button = document.getElementById(id);
            if (!button) continue;

            if (!social?.ENABLE || !isSafeUrl(social.URL)) {
                button.style.display = 'none';
                continue;
            }

            const glyph = String(social.GLYPH || '•');
            const label = social.LABEL || id.replace('btn-', '').toUpperCase();
            const glyphSpan = document.createElement('span');
            glyphSpan.setAttribute('aria-hidden', 'true');
            glyphSpan.textContent = glyph;
            button.replaceChildren(glyphSpan);
            button.setAttribute('aria-label', label);
            button.setAttribute('title', label);
            button.style.display = 'flex';
            button.href = social.URL;
            button.addEventListener('click', (event) => {
                event.preventDefault();
                this.openUrl(social.URL);
            });
        }
    },

    setupInfoButtons() {
        const isAr = LANGUAGE.current === 'ar';
        const translations = (isAr && CONFIG.TRANSLATIONS.INFO_BUTTONS_AR) || CONFIG.TRANSLATIONS.INFO_BUTTONS;
        const entries = [
            ['btn-team', translations.BTN_TEAM],
            ['btn-hints', translations.BTN_HINTS],
            ['btn-news', translations.BTN_NEWS],
            ['btn-rules', translations.BTN_RULES],
        ];

        for (const [id, html] of entries) {
            const button = document.getElementById(id);
            if (button && html) button.innerHTML = html;
        }
    },

    openUrl(url) {
        if (!isSafeUrl(url)) return;

        try {
            if (typeof window.invokeNative === 'function') {
                window.invokeNative('openUrl', url);
            }
        } catch (error) {
            console.warn('[jrs_loadingscreen] unable to open URL', error);
        }
    },

    showBorderImage() {
        if (!CONFIG.IMAGES.ENABLE_BORDER_IMAGE) return;
        document.getElementById('border-image')?.classList.add('active');
    },

    update(value) {
        const safeValue = Number.isFinite(Number(value)) ? Number(value) : 0;
        this.currentProgress = Math.min(100, Math.max(0, Math.floor(safeValue * 100)));
        window.LOADING_PROGRESS = this.currentProgress;

        this.updateUserInfo(window.nuiHandoverData || {});
        this.updateLoadingText();
        PROGRESS_INDICATOR.update(this.currentProgress);

        if (this.currentProgress >= 100 && !this.isComplete) {
            this.isComplete = true;
            const element = document.getElementById('loading-text');
            if (element) element.textContent = LANGUAGE.t('awaitingSelection');
        }
    },

    updateLoadingText() {
        const element = document.getElementById('loading-text');
        if (!element) return;

        if (this.currentProgress >= 100) {
            element.textContent = LANGUAGE.t('awaitingSelection');
            return;
        }

        const phases = loadingPhases();
        if (!phases.length) return;

        const ratio = Math.min(0.999999, Math.max(0, this.currentProgress / 100));
        const index = Math.min(phases.length - 1, Math.floor(ratio * phases.length));

        element.textContent = phases[index];
    },

    prepareForGameReveal() {
        const loadingText = document.getElementById('loading-text');
        if (loadingText) loadingText.textContent = LANGUAGE.t('enteringWorld');
    },
};


function proxyLoadingScreenPointer(data) {
    const nx = Math.min(1, Math.max(0, Number(data?.x) || 0));
    const ny = Math.min(1, Math.max(0, Number(data?.y) || 0));
    const x = Math.round(nx * window.innerWidth);
    const y = Math.round(ny * window.innerHeight);

    let target = document.elementFromPoint(x, y);
    if (!target) return;

    // For range controls, mirror a real click at the cursor position instead of
    // simply calling click(), so volume selection follows the mouse position.
    const range = target.closest?.('input[type="range"]');
    if (range) {
        const rect = range.getBoundingClientRect();
        const ratio = rect.width > 0 ? Math.min(1, Math.max(0, (x - rect.left) / rect.width)) : 0;
        const min = Number(range.min || 0);
        const max = Number(range.max || 100);
        const step = Math.max(Number(range.step || 1), Number.EPSILON);
        const raw = min + ((max - min) * ratio);
        const stepped = Math.round((raw - min) / step) * step + min;
        range.value = String(Math.min(max, Math.max(min, stepped)));
        range.dispatchEvent(new Event('input', { bubbles: true }));
        range.dispatchEvent(new Event('change', { bubbles: true }));
        return;
    }

    target = target.closest?.('button, a, [role="button"], .clickable') || target;
    if (typeof target.click === 'function') {
        target.click();
        return;
    }

    target.dispatchEvent(new MouseEvent('click', {
        bubbles: true,
        cancelable: true,
        clientX: x,
        clientY: y,
        button: Number(data?.button) || 0,
    }));
}

document.addEventListener('DOMContentLoaded', () => {
    LOADING_SCREEN.start();
});

window.addEventListener('message', (event) => {
    const data = event?.data || {};

    if (data.eventName === 'loadProgress') {
        LOADING_SCREEN.start();
        LOADING_SCREEN.update(data.loadFraction);
        return;
    }

    if (data.eventName === 'jrs:close' || data.eventName === 'complete') {
        LOADING_SCREEN.prepareForGameReveal();
        return;
    }

    if (data.type === 'jrs:proxyPointer') {
        proxyLoadingScreenPointer(data);
        return;
    }

    if (data.eventName === 'jrs:devStart') {
        window.location.reload();
    }
});

window.JRS_LOADING_SCREEN = LOADING_SCREEN;
