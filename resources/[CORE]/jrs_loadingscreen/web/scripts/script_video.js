import CONFIG from '../config_main.js';

const MASTER_MUTE_KEY = 'jrs_loadingscreen_master_muted';
const MASTER_VOLUME_KEY = 'jrs_loadingscreen_master_volume';

function readStoredMute() {
    try {
        const current = localStorage.getItem(MASTER_MUTE_KEY);
        if (current !== null) return current === 'true';
        return localStorage.getItem('loadingscreen_muted') === 'true';
    } catch (_) {
        return false;
    }
}

function readStoredVolume() {
    try {
        const raw = Number(localStorage.getItem(MASTER_VOLUME_KEY));
        if (Number.isFinite(raw)) return Math.min(100, Math.max(0, raw));
    } catch (_) {}
    return Math.min(100, Math.max(0, Number(CONFIG.MUSIC?.VOLUME) || 0));
}

const VIDEO_PLAYER = {
    video: null,
    initialized: false,
    unlockBound: false,

    reveal() {
        if (!this.video) return;
        this.video.classList.add('ready');
        this.video.play().catch((error) => {
            // Autoplay with audio may be blocked until the first user interaction.
            console.warn('[jrs_loadingscreen] video autoplay blocked:', error);
        });
    },

    init() {
        if (!CONFIG.VIDEO.ENABLE || this.initialized) return;
        this.initialized = true;

        this.video = document.getElementById('video');
        if (!this.video) {
            console.error('[jrs_loadingscreen] video element not found');
            return;
        }

        const file = String(CONFIG.VIDEO.VIDEO || '').trim();
        if (!file) {
            console.error('[jrs_loadingscreen] no video configured');
            return;
        }

        const url = `assets/videos/${file}`;
        const hardMuted = CONFIG.VIDEO.MUTE_VIDEO === true;
        const masterMuted = readStoredMute();
        const masterVolume = readStoredVolume() / 100;

        // Apply the initial state before loading the media to prevent a one-frame
        // volume/mute flash. The music controller may update this state later.
        this.video.muted = hardMuted || masterMuted;
        this.video.defaultMuted = this.video.muted;
        this.video.volume = masterVolume;
        this.video.autoplay = true;
        this.video.playsInline = true;
        this.video.loop = true;
        this.video.preload = 'auto';

        this.video.addEventListener('loadeddata', () => this.reveal(), { once: true });
        this.video.addEventListener('canplay', () => this.reveal(), { once: true });
        this.video.addEventListener('error', () => {
            // Never reveal a failed/blank video element. The local fallback image
            // remains visible underneath.
            this.video?.classList.remove('ready');
            console.warn('[jrs_loadingscreen] background video failed to load');
        });

        this.bindInteractionUnlock();

        if (this.video.getAttribute('src') !== url) {
            this.video.setAttribute('src', url);
        }
        this.video.load();
    },

    bindInteractionUnlock() {
        if (this.unlockBound) return;
        this.unlockBound = true;

        const retry = () => {
            if (!this.video || this.video.ended || !this.video.paused) return;
            // Never force a mute state here. Shared audio controls are allowed to
            // change video.muted after initialization.
            this.video.play().catch(() => {});
        };

        window.addEventListener('pointerdown', retry, { passive: true });
        window.addEventListener('keydown', retry);
    },

    stop() {
        if (!this.video) return;
        this.video.loop = false;
        this.video.pause();
        this.video.classList.remove('ready');
    },
};

export default VIDEO_PLAYER;
