import CONFIG from '../config_main.js';
import LANGUAGE from './script_lang.js';

const MASTER_MUTE_KEY = 'jrs_loadingscreen_master_muted';
const MASTER_VOLUME_KEY = 'jrs_loadingscreen_master_volume';
const FAVORITES_KEY = 'jrs_loadingscreen_favorites';

const MUSIC_PLAYER = {
    audio: null,
    currentTrackIndex: 0,
    favorites: [],
    controlsBound: false,
    unlockBound: false,
    masterMuted: false,
    masterVolume: 1,
    musicOwnsAudio: false,

    init() {
        if ((!CONFIG.MUSIC.ENABLE && !CONFIG.MUSIC.ENABLE_CONTROLS) || this.audio) return;

        this.audio = document.getElementById('music-audio');
        if (!this.audio) {
            console.error('[jrs_loadingscreen] music audio element not found');
            return;
        }

        this.masterMuted = this.readStoredMute();
        this.masterVolume = this.readStoredVolume() / 100;
        this.audio.preload = 'auto';

        if (CONFIG.MUSIC.ENABLE) {
            this.loadFavorites();
            this.pickInitialTrack();
        } else {
            this.favorites = [];
            this.updateMusicTitle();
        }
        this.applyMasterAudioState();
        this.bindAudioEvents();
        this.setupControls();
        this.bindInteractionUnlock();

        if (this.shouldAutoPlay()) this.safePlay('autoplay');
    },

    readStoredMute() {
        try {
            const current = localStorage.getItem(MASTER_MUTE_KEY);
            if (current !== null) return current === 'true';
            return localStorage.getItem('loadingscreen_muted') === 'true';
        } catch (_) {
            return false;
        }
    },

    readStoredVolume() {
        try {
            const stored = Number(localStorage.getItem(MASTER_VOLUME_KEY));
            if (Number.isFinite(stored)) return Math.min(100, Math.max(0, stored));
        } catch (_) {}

        return Math.min(100, Math.max(0, Number(CONFIG.MUSIC.VOLUME) || 0));
    },

    persistMasterState() {
        try {
            localStorage.setItem(MASTER_MUTE_KEY, String(this.masterMuted));
            localStorage.removeItem('loadingscreen_muted');
            localStorage.setItem(MASTER_VOLUME_KEY, String(Math.round(this.masterVolume * 100)));
        } catch (_) {}
    },

    getList() {
        return Array.isArray(CONFIG.MUSIC.MUSIC_LIST) ? CONFIG.MUSIC.MUSIC_LIST : [];
    },

    getVideoTarget() {
        if (CONFIG.VIDEO?.ENABLE !== true) return null;
        return document.getElementById('video');
    },

    applyMasterAudioState() {
        const volume = Math.min(1, Math.max(0, Number(this.masterVolume) || 0));

        if (this.audio) {
            this.audio.volume = volume;
            this.audio.muted = this.masterMuted;
        }

        const video = this.getVideoTarget();
        if (video) {
            video.volume = volume;
            // MUTE_VIDEO is a hard config lock. Master controls may mute an audible
            // video, but they can never unmute one explicitly disabled in config.
            video.muted = CONFIG.VIDEO.MUTE_VIDEO === true
                ? true
                : (this.masterMuted || this.musicOwnsAudio);
        }

        this.updateMuteButton();
        this.syncVolumeSlider();
    },

    shouldAutoPlay() {
        if (!CONFIG.MUSIC.ENABLE || CONFIG.MUSIC.AUTO_PLAY === false) return false;
        // Avoid two audio streams starting over each other. Controls remain visible.
        return !(CONFIG.VIDEO?.ENABLE === true && CONFIG.VIDEO?.MUTE_VIDEO === false);
    },

    pickInitialTrack() {
        const list = this.getList();
        if (!list.length) {
            this.updateMusicTitle();
            return;
        }

        if (this.favorites.length) {
            const favorite = this.favorites[Math.floor(Math.random() * this.favorites.length)];
            const index = list.findIndex((track) => track.NAME === favorite);
            this.currentTrackIndex = index >= 0 ? index : Math.floor(Math.random() * list.length);
        } else {
            this.currentTrackIndex = Math.floor(Math.random() * list.length);
        }

        this.loadCurrentTrack(false);
    },

    loadCurrentTrack(autoplay = true) {
        const list = this.getList();
        if (!this.audio || !list.length) return;

        const track = list[this.currentTrackIndex];
        if (!track?.NAME) return;

        const wanted = `assets/audio/${track.NAME}`;
        if (this.audio.getAttribute('src') !== wanted) {
            this.audio.src = wanted;
            this.audio.load();
        }

        this.updateMusicTitle();
        this.updateFavoriteButton();
        if (autoplay) this.safePlay('track_change');
    },

    bindAudioEvents() {
        if (!this.audio) return;

        this.audio.addEventListener('play', () => {
            this.musicOwnsAudio = true;
            this.applyMasterAudioState();
            this.updatePlayPauseButton();
        });
        this.audio.addEventListener('pause', () => {
            this.musicOwnsAudio = false;
            this.applyMasterAudioState();
            this.updatePlayPauseButton();
        });
        this.audio.addEventListener('ended', () => this.nextTrack());
        this.audio.addEventListener('error', () => {
            console.warn('[jrs_loadingscreen] audio failed to load:', this.audio?.currentSrc || this.audio?.src || 'unknown');
        });
    },

    bindInteractionUnlock() {
        if (this.unlockBound) return;
        this.unlockBound = true;

        const unlock = () => {
            if (!this.audio || !this.audio.paused || !this.shouldAutoPlay()) return;
            this.safePlay('first_user_interaction');
        };

        window.addEventListener('pointerdown', unlock, { once: true, passive: true });
        window.addEventListener('keydown', unlock, { once: true });
    },

    async safePlay(reason = 'unknown') {
        if (!this.audio || !this.audio.getAttribute('src')) return false;

        try {
            await this.audio.play();
            this.updatePlayPauseButton();
            return true;
        } catch (error) {
            console.warn(`[jrs_loadingscreen] audio play blocked (${reason})`, error);
            this.updatePlayPauseButton();
            return false;
        }
    },

    setupControls() {
        if (!CONFIG.MUSIC.ENABLE_CONTROLS || this.controlsBound) return;
        this.controlsBound = true;

        const controlsDiv = document.getElementById('music-controls');
        const btnToggle = document.getElementById('btn-toggle-controls');
        const btnPrevious = document.getElementById('btn-previous');
        const btnPlayPause = document.getElementById('btn-play-pause');
        const btnNext = document.getElementById('btn-next');
        const btnMute = document.getElementById('btn-mute');
        const btnFavorite = document.getElementById('btn-favorite');
        const volumeSlider = document.getElementById('volume-slider');
        const musicEnabled = CONFIG.MUSIC.ENABLE === true;

        // Mute/volume are master controls and remain available for video audio even
        // when the music player is disabled. Music-only transport controls are hidden.
        [btnPrevious, btnPlayPause, btnNext, btnFavorite].forEach((button) => {
            if (button) button.style.display = musicEnabled ? '' : 'none';
        });

        btnToggle?.classList.add('active');
        if (controlsDiv) {
            controlsDiv.classList.add('active', 'visible');
            controlsDiv.classList.remove('hidden');
            controlsDiv.style.display = 'flex';
        }

        btnToggle?.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            if (!controlsDiv) return;

            const opening = controlsDiv.classList.contains('hidden');
            if (opening) {
                controlsDiv.style.display = 'flex';
                requestAnimationFrame(() => {
                    controlsDiv.classList.remove('hidden');
                    controlsDiv.classList.add('visible');
                });
            } else {
                controlsDiv.classList.add('hidden');
                controlsDiv.classList.remove('visible');
                setTimeout(() => {
                    if (controlsDiv.classList.contains('hidden')) controlsDiv.style.display = 'none';
                }, 320);
            }
        });

        btnPrevious?.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            this.previousTrack();
        });

        btnPlayPause?.addEventListener('click', async (event) => {
            event.preventDefault();
            event.stopPropagation();
            await this.togglePlayPause();
        });

        btnNext?.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            this.nextTrack();
        });

        btnMute?.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            this.toggleMute();
        });

        btnFavorite?.addEventListener('click', (event) => {
            event.preventDefault();
            event.stopPropagation();
            this.toggleFavorite();
        });

        volumeSlider?.addEventListener('input', (event) => {
            event.stopPropagation();
            this.setVolume(event.target.value);
        });

        if (btnPrevious) btnPrevious.innerHTML = CONFIG.TRANSLATIONS.MUSIC_CONTROLS.BTN_PREVIOUS;
        if (btnNext) btnNext.innerHTML = CONFIG.TRANSLATIONS.MUSIC_CONTROLS.BTN_NEXT;

        this.updatePlayPauseButton();
        this.updateMuteButton();
        this.updateFavoriteButton();
        this.syncVolumeSlider();
    },

    nextTrack() {
        const list = this.getList();
        if (!this.audio || !list.length) return;
        if (list.length === 1) {
            this.audio.currentTime = 0;
            this.safePlay('next_single_track');
            return;
        }
        this.currentTrackIndex = (this.currentTrackIndex + 1) % list.length;
        this.loadCurrentTrack(true);
    },

    previousTrack() {
        const list = this.getList();
        if (!this.audio || !list.length) return;
        if (list.length === 1) {
            this.audio.currentTime = 0;
            this.safePlay('previous_single_track');
            return;
        }
        this.currentTrackIndex = (this.currentTrackIndex - 1 + list.length) % list.length;
        this.loadCurrentTrack(true);
    },

    async togglePlayPause() {
        if (!this.audio || !this.audio.getAttribute('src')) return;
        if (this.audio.paused) await this.safePlay('play_button');
        else this.audio.pause();
        this.updatePlayPauseButton();
    },

    updatePlayPauseButton() {
        const button = document.getElementById('btn-play-pause');
        if (!button) return;
        button.innerHTML = this.audio && !this.audio.paused
            ? CONFIG.TRANSLATIONS.MUSIC_CONTROLS.BTN_PAUSE
            : CONFIG.TRANSLATIONS.MUSIC_CONTROLS.BTN_PLAY;
    },

    updateMusicTitle() {
        const title = document.getElementById('music-title');
        const list = this.getList();
        const track = list[this.currentTrackIndex];
        if (!title) return;
        if (CONFIG.MUSIC.ENABLE !== true) {
            const isAr = LANGUAGE.current === 'ar';
            title.textContent = CONFIG.VIDEO?.ENABLE === true ? (isAr ? 'صوت الفيديو' : 'VIDEO AUDIO') : (isAr ? 'الصوت' : 'AUDIO');
            return;
        }
        title.textContent = track?.TITLE || track?.NAME || LANGUAGE.t('noTrack', 'AUDIO');
    },

    toggleMute() {
        this.masterMuted = !this.masterMuted;
        this.persistMasterState();
        this.applyMasterAudioState();
    },

    updateMuteButton() {
        const button = document.getElementById('btn-mute');
        if (!button) return;
        button.innerHTML = this.masterMuted
            ? CONFIG.TRANSLATIONS.MUSIC_CONTROLS.BTN_UNMUTE
            : CONFIG.TRANSLATIONS.MUSIC_CONTROLS.BTN_MUTE;
    },

    syncVolumeSlider() {
        const slider = document.getElementById('volume-slider');
        if (!slider || slider.matches(':active')) return;
        slider.value = String(Math.round(this.masterVolume * 100));
    },

    setVolume(value) {
        this.masterVolume = Math.min(100, Math.max(0, Number(value) || 0)) / 100;
        if (this.masterVolume > 0 && this.masterMuted) this.masterMuted = false;
        this.persistMasterState();
        this.applyMasterAudioState();
    },

    loadFavorites() {
        try {
            const saved = JSON.parse(localStorage.getItem(FAVORITES_KEY) || '[]');
            this.favorites = Array.isArray(saved) ? saved : [];
        } catch (_) {
            this.favorites = [];
        }
    },

    saveFavorites() {
        try {
            localStorage.setItem(FAVORITES_KEY, JSON.stringify(this.favorites));
        } catch (_) {}
    },

    toggleFavorite() {
        const list = this.getList();
        const track = list[this.currentTrackIndex];
        if (!track?.NAME) return;

        const index = this.favorites.indexOf(track.NAME);
        if (index >= 0) this.favorites.splice(index, 1);
        else this.favorites.push(track.NAME);

        this.saveFavorites();
        this.updateFavoriteButton();
    },

    updateFavoriteButton() {
        const button = document.getElementById('btn-favorite');
        const list = this.getList();
        const track = list[this.currentTrackIndex];
        if (!button) return;

        const favorite = !!track?.NAME && this.favorites.includes(track.NAME);
        button.innerHTML = favorite
            ? CONFIG.TRANSLATIONS.MUSIC_CONTROLS.BTN_FAVORITE_REMOVE
            : CONFIG.TRANSLATIONS.MUSIC_CONTROLS.BTN_FAVORITE_ADD;
        button.classList.toggle('active', favorite);
        button.disabled = !track?.NAME;
    },
};

export default MUSIC_PLAYER;
