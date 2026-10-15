const CONFIG = {
    SERVER_NAME: "JRS CORE",
    SERVER_DESCRIPTION: "",
    SERVER_WARNING: "YOUR STORY BEGINS ON THE AMERICAN FRONTIER",
    SERVER_WARNING_AR: "قصتك تبدأ على حدود الغرب الأمريكي",
    ENABLE_SERVER_LOGO: false,
    SERVER_LOGO: "logo.png",

    INITIAL_REVEAL_DURATION: 5000,

    // Music and video are off in the public release: add your own files to assets/audio and
    // assets/videos, list them below and set ENABLE to true. (None are bundled on purpose.)
    MUSIC: {
        ENABLE: false,
        // Master audio controls stay available even when music itself is disabled.
        ENABLE_CONTROLS: true,
        VOLUME: 7,
        AUTO_PLAY: true,
        MUSIC_LIST: [
            // { TITLE: "My song", NAME: "song.mp3" },
        ],
    },

    VIDEO: {
        ENABLE: false,
        VIDEO: "background.mp4", // put your own file in assets/videos and set ENABLE to true
        MUTE_VIDEO: false,
    },

    IMAGES: {
        ENABLE_SLIDER: true,
        SLIDER_STYLE: "fade-in",
        SLIDER_DURATION: 10000,
        ENABLE_OVERLAY: true,
        OVERLAY_FRAME_DURATION: 80,
        ENABLE_BORDER_IMAGE: true,
        IMAGE_LIST: [
            { NAME: "image_1.jpg" },
            { NAME: "image_2.jpg" },
            { NAME: "image_3.jpg" },
            { NAME: "image_4.jpg" },
            { NAME: "image_5.jpg" },
            { NAME: "image_6.jpg" },
            { NAME: "image_7.jpg" },
            { NAME: "image_8.jpg" },
        ],
    },

    USER_CARD: {
        ENABLE: true,
    },

    SOCIALS: {
        DISCORD: {
            ENABLE: true,
            LABEL: "DISCORD",
            URL: "https://discord.gg/your-invite",
            GLYPH: "D",
        },
        YOUTUBE: {
            ENABLE: true,
            LABEL: "YOUTUBE",
            URL: "https://www.youtube.com/",
            GLYPH: "▶",
        },
        WEBSITE: {
            ENABLE: true,
            LABEL: "WEBSITE",
            URL: "https://www.youtube.com/",
            GLYPH: "◎",
        },
    },

    TRANSLATIONS: {
        MUSIC_CONTROLS: {
            BTN_PREVIOUS: '<span class="control-glyph">⏮</span>',
            BTN_NEXT: '<span class="control-glyph">⏭</span>',
            BTN_PLAY: '<span class="control-glyph">▶</span>',
            BTN_PAUSE: '<span class="control-glyph">Ⅱ</span>',
            BTN_MUTE: '<span class="control-glyph">🔊</span>',
            BTN_UNMUTE: '<span class="control-glyph">🔇</span>',
            BTN_FAVORITE_ADD: '<span class="control-glyph">☆</span>',
            BTN_FAVORITE_REMOVE: '<span class="control-glyph">★</span>',
        },
        INFO_BUTTONS: {
            BTN_TEAM: '<span class="info-symbol">♟</span><span>TEAM</span>',
            BTN_HINTS: '<span class="info-symbol">✦</span><span>HINTS</span>',
            BTN_NEWS: '<span class="info-symbol">▤</span><span>NEWS</span>',
            BTN_RULES: '<span class="info-symbol">★</span><span>RULES</span>',
        },
        INFO_BUTTONS_AR: {
            BTN_TEAM: '<span class="info-symbol">♟</span><span>الفريق</span>',
            BTN_HINTS: '<span class="info-symbol">✦</span><span>إرشادات</span>',
            BTN_NEWS: '<span class="info-symbol">▤</span><span>الأخبار</span>',
            BTN_RULES: '<span class="info-symbol">★</span><span>القوانين</span>',
        },
    },
};

export default CONFIG;
