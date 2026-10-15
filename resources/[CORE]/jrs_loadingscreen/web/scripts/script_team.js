import SERVER from '../config_staff.js';
import LANGUAGE from './script_lang.js';

// Content in config_staff.js carries an optional _AR sibling per text field
// (NAME/NAME_AR, DESCRIPTION/DESCRIPTION_AR, ...). This reads whichever the
// active language calls for and falls back to the English field.
// 2.8.0: card markup is built with innerHTML, so every value is escaped - a
// quote in a name (common in Arabic copy) used to break the alt attribute and
// anything HTML-shaped in config would have been injected as markup.
const escapeHtml = (value) => String(value ?? '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
const text = (entry, field) => escapeHtml(LANGUAGE.pick(entry, field));
// Card images must be local assets or https; anything else uses the default.
const safeImage = (src) => {
    const value = String(src || '');
    if (/^(assets\/|https:\/\/)[^"'<>\s]*$/.test(value)) return escapeHtml(value);
    return 'assets/images/default_avatar.jpg';
};

const TEAM_SYSTEM = {
    isTeamVisible: false,
    isHintsVisible: false,
    isNewsVisible: false,
    isRulesVisible: false,
    isDragging: false,
    startX: 0,
    currentRotation: 0,
    autoScrollInterval: null,
    idleTimeout: null,
    autoScrollSpeed: 0.2,
    cardAngles: [],
    sideFeedTimers: { team: null, rules: null, news: null, hints: null },
    sideFeedIndexes: { team: 0, rules: 0, news: 0, hints: 0 },

    init: function () {
        const btnTeam = document.getElementById('btn-team');
        const btnHints = document.getElementById('btn-hints');
        const btnNews = document.getElementById('btn-news');
        const btnRules = document.getElementById('btn-rules');

        if (btnTeam) {
            btnTeam.addEventListener('click', () => {
                this.toggleTeam();
            });
        }

        if (btnHints) {
            btnHints.addEventListener('click', () => {
                this.toggleHints();
            });
        }

        if (btnNews) {
            btnNews.addEventListener('click', () => {
                this.toggleNews();
            });
        }

        if (btnRules) {
            btnRules.addEventListener('click', () => {
                this.toggleRules();
            });
        }

        this.generateTeamCards();
        this.generateHintCards();
        this.generateNewsCards();
        this.generateRulesCards();
        this.generateSideFeeds();

        this.setupDragScroll('team-cards-wrapper');
        this.setupDragScroll('hints-cards-wrapper');
        this.setupDragScroll('news-cards-wrapper');
        this.setupDragScroll('rules-cards-wrapper');
        this.setupResponsiveResize();
    },

    // Re-render everything that carries copy. Called when the player switches
    // language on the loading screen, so the cards and the scrolling side feeds
    // change over with the rest of the screen instead of staying English.
    refreshLanguage: function () {
        this.generateTeamCards();
        this.generateHintCards();
        this.generateNewsCards();
        this.generateRulesCards();
        this.generateSideFeeds();
    },

    generateTeamCards: function () {
        const wrapper = document.getElementById('team-cards-wrapper');
        if (!wrapper || !SERVER.CARDS) return;

        wrapper.innerHTML = '';

        SERVER.CARDS.forEach((member, index) => {
            const card = document.createElement('div');
            card.className = 'team-card';
            card.dataset.index = index;

            card.innerHTML = `
                <img src="${safeImage(member.IMAGE)}" alt="${text(member, 'NAME')}" class="card-image">
                <div class="card-title">${text(member, 'NAME')}</div>
                <div class="card-role">${text(member, 'ROLE')}</div>
                <div class="card-description">${text(member, 'DESCRIPTION')}</div>
            `;

            card.style.display = 'none';
            card.style.opacity = '0';
            wrapper.appendChild(card);
        });

    },

    generateHintCards: function () {
        const wrapper = document.getElementById('hints-cards-wrapper');
        if (!wrapper || !SERVER.HINTS) return;

        wrapper.innerHTML = '';

        SERVER.HINTS.forEach((hint, index) => {
            const card = document.createElement('div');
            card.className = 'hint-card';
            card.dataset.index = index;

            card.innerHTML = `
                <img src="${safeImage(hint.IMAGE)}" alt="${text(hint, 'NAME')}" class="card-image">
                <div class="card-title">${text(hint, 'NAME')}</div>
                <div class="card-description">${text(hint, 'DESCRIPTION')}</div>
            `;

            card.style.display = 'none';
            card.style.opacity = '0';
            wrapper.appendChild(card);
        });

    },

    generateNewsCards: function () {
        const wrapper = document.getElementById('news-cards-wrapper');
        if (!wrapper || !SERVER.NEWS) return;

        wrapper.innerHTML = '';

        SERVER.NEWS.forEach((news, index) => {
            const card = document.createElement('div');
            card.className = 'news-card';
            card.dataset.index = index;

            card.innerHTML = `
                <img src="${safeImage(news.IMAGE)}" alt="${text(news, 'TITLE')}" class="card-image">
                <div class="card-title">${text(news, 'TITLE')}</div>
                <div class="card-description">${text(news, 'DESCRIPTION')}</div>
            `;

            card.style.display = 'none';
            card.style.opacity = '0';
            wrapper.appendChild(card);
        });

    },

    generateRulesCards: function () {
        const wrapper = document.getElementById('rules-cards-wrapper');
        if (!wrapper || !SERVER.RULES) return;

        wrapper.innerHTML = '';

        SERVER.RULES.forEach((rule, index) => {
            const card = document.createElement('div');
            card.className = 'rules-card';
            card.dataset.index = index;

            card.innerHTML = `
                <div class="card-title">${text(rule, 'TITLE')}</div>
                <div class="card-description">${text(rule, 'DESCRIPTION')}</div>
            `;

            card.style.display = 'none';
            card.style.opacity = '0';
            wrapper.appendChild(card);
        });

    },

    generateSideFeeds: function () {
        this.generateSideFeed('team', SERVER.CARDS || []);
        this.generateSideFeed('rules', SERVER.RULES || []);
        this.generateSideFeed('news', SERVER.NEWS || []);
        this.generateSideFeed('hints', SERVER.HINTS || []);

        if (!this.sideFeedsBound) {
            this.sideFeedsBound = true;
            ['team', 'rules', 'news', 'hints'].forEach((type) => {
                const panel = document.getElementById(`${type}-side-panel`);
                if (!panel) return;
                panel.addEventListener('mouseenter', () => this.stopSideFeed(type));
                panel.addEventListener('mouseleave', () => this.startSideFeed(type));
            });
        }
    },

    generateSideFeed: function (type, items) {
        const track = document.getElementById(`${type}-side-track`);
        if (!track) return;

        track.innerHTML = '';
        this.sideFeedIndexes[type] = 0;

        items.forEach((item, index) => {
            const card = document.createElement('div');
            card.className = `side-feed-card side-feed-card-${type}`;
            card.dataset.index = index;

            const image = safeImage(item.IMAGE);
            const titleMap = {
                team: text(item, 'NAME') || 'STAFF',
                rules: text(item, 'TITLE') || 'RULE',
                news: text(item, 'TITLE') || 'NEWS',
                hints: text(item, 'NAME') || 'HINT',
            };
            const title = titleMap[type] || 'INFO';
            const secondary = type === 'team'
                ? text(item, 'ROLE')
                : text(item, 'DESCRIPTION');
            const description = type === 'team' ? text(item, 'DESCRIPTION') : '';
            const secondaryClass = type === 'team' ? 'side-feed-card-subtitle' : 'side-feed-card-description';

            card.innerHTML = `
                <img src="${image}" alt="${title}" class="side-feed-thumb">
                <div class="side-feed-copy">
                    <div class="side-feed-card-title">${title}</div>
                    ${secondary ? `<div class="${secondaryClass}">${secondary}</div>` : ''}
                    ${description ? `<div class="side-feed-card-description">${description}</div>` : ''}
                </div>
            `;

            track.appendChild(card);
        });

        requestAnimationFrame(() => this.updateSideFeed(type));
    },

    updateSideFeed: function (type) {
        const track = document.getElementById(`${type}-side-track`);
        const viewport = document.getElementById(`${type}-side-viewport`);
        if (!track || !viewport) return;

        const cards = Array.from(track.querySelectorAll('.side-feed-card'));
        const count = cards.length;
        if (!count) return;

        const activeIndex = ((this.sideFeedIndexes[type] % count) + count) % count;
        const step = Math.max(1, viewport.clientHeight / 3);

        cards.forEach((card, index) => {
            let delta = activeIndex - index;
            while (delta > count / 2) delta -= count;
            while (delta < -count / 2) delta += count;

            const distance = Math.abs(delta);
            const isVisible = distance <= 1.05;
            const y = delta * step;
            const scale = distance < 0.1 ? 1 : 0.88;
            const opacity = distance < 0.1 ? 1 : (isVisible ? 0.48 : 0);

            card.classList.toggle('is-visible', isVisible);
            card.classList.toggle('is-current', distance < 0.1);
            card.style.transform = `translateY(-50%) translateY(${y}px) scale(${scale})`;
            card.style.opacity = String(opacity);
            card.style.zIndex = String(30 - Math.round(distance * 5));
        });
    },

    startSideFeed: function (type) {
        this.stopSideFeed(type);

        const panelConfig = SERVER.SIDE_FEEDS?.[type.toUpperCase()];
        if (!panelConfig?.ENABLE) return;

        const track = document.getElementById(`${type}-side-track`);
        const cards = track ? track.querySelectorAll('.side-feed-card') : [];
        if (cards.length <= 1) return;

        const interval = Math.max(1800, Number(panelConfig.INTERVAL) || 4500);
        this.sideFeedTimers[type] = window.setInterval(() => {
            this.sideFeedIndexes[type] = (this.sideFeedIndexes[type] + 1) % cards.length;
            this.updateSideFeed(type);
        }, interval);
    },

    stopSideFeed: function (type) {
        if (this.sideFeedTimers[type]) {
            clearInterval(this.sideFeedTimers[type]);
            this.sideFeedTimers[type] = null;
        }
    },

    stopSideFeeds: function () {
        this.stopSideFeed('team');
        this.stopSideFeed('rules');
        this.stopSideFeed('news');
        this.stopSideFeed('hints');
    },

    toggleTeam: function () {
        const container = document.getElementById('team-cards-container');
        const btnTeam = document.getElementById('btn-team');
        const cards = container.querySelectorAll('.team-card');
        const wrapper = document.getElementById('team-cards-wrapper');


        if (this.isTeamVisible) {
            this.stopAutoScroll();

            this.hideCardsStaggered(cards, () => {
                container.classList.remove('active');
                this.isTeamVisible = false;
            });
            btnTeam.classList.remove('active');
        } else {
            if (this.isHintsVisible) {
                const hintsContainer = document.getElementById('hints-cards-container');
                const hintCards = hintsContainer.querySelectorAll('.hint-card');
                const btnHints = document.getElementById('btn-hints');

                this.stopAutoScroll();

                this.hideCardsStaggered(hintCards, () => {
                    hintsContainer.classList.remove('active');
                    this.isHintsVisible = false;
                    btnHints.classList.remove('active');

                    container.classList.add('active');
                    btnTeam.classList.add('active');
                    this.isTeamVisible = true;

                    this.showCardsStaggered(cards, wrapper);

                    this.startIdleTimer(wrapper);
                });
            } else if (this.isNewsVisible) {
                const newsContainer = document.getElementById('news-cards-container');
                const newsCards = newsContainer.querySelectorAll('.news-card');
                const btnNews = document.getElementById('btn-news');

                this.stopAutoScroll();

                this.hideCardsStaggered(newsCards, () => {
                    newsContainer.classList.remove('active');
                    this.isNewsVisible = false;
                    btnNews.classList.remove('active');

                    container.classList.add('active');
                    btnTeam.classList.add('active');
                    this.isTeamVisible = true;

                    this.showCardsStaggered(cards, wrapper);

                    this.startIdleTimer(wrapper);
                });
            } else if (this.isRulesVisible) {
                const rulesContainer = document.getElementById('rules-cards-container');
                const rulesCards = rulesContainer.querySelectorAll('.rules-card');
                const btnRules = document.getElementById('btn-rules');

                this.stopAutoScroll();

                this.hideCardsStaggered(rulesCards, () => {
                    rulesContainer.classList.remove('active');
                    this.isRulesVisible = false;
                    btnRules.classList.remove('active');

                    container.classList.add('active');
                    btnTeam.classList.add('active');
                    this.isTeamVisible = true;

                    this.showCardsStaggered(cards, wrapper);

                    this.startIdleTimer(wrapper);
                });
            } else {
                container.classList.add('active');
                btnTeam.classList.add('active');
                this.isTeamVisible = true;

                this.showCardsStaggered(cards, wrapper);

                this.startIdleTimer(wrapper);
            }
        }
    },

    toggleHints: function () {
        const container = document.getElementById('hints-cards-container');
        const btnHints = document.getElementById('btn-hints');
        const cards = container.querySelectorAll('.hint-card');
        const wrapper = document.getElementById('hints-cards-wrapper');


        if (this.isHintsVisible) {
            this.stopAutoScroll();

            this.hideCardsStaggered(cards, () => {
                container.classList.remove('active');
                this.isHintsVisible = false;
            });
            btnHints.classList.remove('active');
        } else {
            if (this.isTeamVisible) {
                const teamContainer = document.getElementById('team-cards-container');
                const teamCards = teamContainer.querySelectorAll('.team-card');
                const btnTeam = document.getElementById('btn-team');

                this.stopAutoScroll();

                this.hideCardsStaggered(teamCards, () => {
                    teamContainer.classList.remove('active');
                    this.isTeamVisible = false;
                    btnTeam.classList.remove('active');

                    container.classList.add('active');
                    btnHints.classList.add('active');
                    this.isHintsVisible = true;

                    this.showCardsStaggered(cards, wrapper);

                    this.startIdleTimer(wrapper);
                });
            } else if (this.isNewsVisible) {
                const newsContainer = document.getElementById('news-cards-container');
                const newsCards = newsContainer.querySelectorAll('.news-card');
                const btnNews = document.getElementById('btn-news');

                this.stopAutoScroll();

                this.hideCardsStaggered(newsCards, () => {
                    newsContainer.classList.remove('active');
                    this.isNewsVisible = false;
                    btnNews.classList.remove('active');

                    container.classList.add('active');
                    btnHints.classList.add('active');
                    this.isHintsVisible = true;

                    this.showCardsStaggered(cards, wrapper);

                    this.startIdleTimer(wrapper);
                });
            } else if (this.isRulesVisible) {
                const rulesContainer = document.getElementById('rules-cards-container');
                const rulesCards = rulesContainer.querySelectorAll('.rules-card');
                const btnRules = document.getElementById('btn-rules');

                this.stopAutoScroll();

                this.hideCardsStaggered(rulesCards, () => {
                    rulesContainer.classList.remove('active');
                    this.isRulesVisible = false;
                    btnRules.classList.remove('active');

                    container.classList.add('active');
                    btnHints.classList.add('active');
                    this.isHintsVisible = true;

                    this.showCardsStaggered(cards, wrapper);

                    this.startIdleTimer(wrapper);
                });
            } else {
                container.classList.add('active');
                btnHints.classList.add('active');
                this.isHintsVisible = true;

                this.showCardsStaggered(cards, wrapper);

                this.startIdleTimer(wrapper);
            }
        }
    },

    toggleNews: function () {
        const container = document.getElementById('news-cards-container');
        const btnNews = document.getElementById('btn-news');
        const cards = container.querySelectorAll('.news-card');
        const wrapper = document.getElementById('news-cards-wrapper');

        if (this.isNewsVisible) {
            this.stopAutoScroll();

            this.hideCardsStaggered(cards, () => {
                container.classList.remove('active');
                this.isNewsVisible = false;
            });
            btnNews.classList.remove('active');
        } else {
            if (this.isTeamVisible) {
                const teamContainer = document.getElementById('team-cards-container');
                const teamCards = teamContainer.querySelectorAll('.team-card');
                const btnTeam = document.getElementById('btn-team');

                this.stopAutoScroll();

                this.hideCardsStaggered(teamCards, () => {
                    teamContainer.classList.remove('active');
                    this.isTeamVisible = false;
                    btnTeam.classList.remove('active');

                    container.classList.add('active');
                    btnNews.classList.add('active');
                    this.isNewsVisible = true;

                    this.showCardsStaggered(cards, wrapper);

                    this.startIdleTimer(wrapper);
                });
            } else if (this.isHintsVisible) {
                const hintsContainer = document.getElementById('hints-cards-container');
                const hintsCards = hintsContainer.querySelectorAll('.hint-card');
                const btnHints = document.getElementById('btn-hints');

                this.stopAutoScroll();

                this.hideCardsStaggered(hintsCards, () => {
                    hintsContainer.classList.remove('active');
                    this.isHintsVisible = false;
                    btnHints.classList.remove('active');

                    container.classList.add('active');
                    btnNews.classList.add('active');
                    this.isNewsVisible = true;

                    this.showCardsStaggered(cards, wrapper);

                    this.startIdleTimer(wrapper);
                });
            } else if (this.isRulesVisible) {
                const rulesContainer = document.getElementById('rules-cards-container');
                const rulesCards = rulesContainer.querySelectorAll('.rules-card');
                const btnRules = document.getElementById('btn-rules');

                this.stopAutoScroll();

                this.hideCardsStaggered(rulesCards, () => {
                    rulesContainer.classList.remove('active');
                    this.isRulesVisible = false;
                    btnRules.classList.remove('active');

                    container.classList.add('active');
                    btnNews.classList.add('active');
                    this.isNewsVisible = true;

                    this.showCardsStaggered(cards, wrapper);

                    this.startIdleTimer(wrapper);
                });
            } else {
                container.classList.add('active');
                btnNews.classList.add('active');
                this.isNewsVisible = true;

                this.showCardsStaggered(cards, wrapper);

                this.startIdleTimer(wrapper);
            }
        }
    },

    toggleRules: function () {
        const container = document.getElementById('rules-cards-container');
        const btnRules = document.getElementById('btn-rules');
        const cards = container.querySelectorAll('.rules-card');
        const wrapper = document.getElementById('rules-cards-wrapper');

        if (this.isRulesVisible) {
            this.stopAutoScroll();

            this.hideCardsStaggered(cards, () => {
                container.classList.remove('active');
                this.isRulesVisible = false;
            });
            btnRules.classList.remove('active');
        } else {
            if (this.isTeamVisible) {
                const teamContainer = document.getElementById('team-cards-container');
                const teamCards = teamContainer.querySelectorAll('.team-card');
                const btnTeam = document.getElementById('btn-team');

                this.stopAutoScroll();

                this.hideCardsStaggered(teamCards, () => {
                    teamContainer.classList.remove('active');
                    this.isTeamVisible = false;
                    btnTeam.classList.remove('active');

                    container.classList.add('active');
                    btnRules.classList.add('active');
                    this.isRulesVisible = true;

                    this.showCardsStaggered(cards, wrapper);

                    this.startIdleTimer(wrapper);
                });
            } else if (this.isHintsVisible) {
                const hintsContainer = document.getElementById('hints-cards-container');
                const hintsCards = hintsContainer.querySelectorAll('.hint-card');
                const btnHints = document.getElementById('btn-hints');

                this.stopAutoScroll();

                this.hideCardsStaggered(hintsCards, () => {
                    hintsContainer.classList.remove('active');
                    this.isHintsVisible = false;
                    btnHints.classList.remove('active');

                    container.classList.add('active');
                    btnRules.classList.add('active');
                    this.isRulesVisible = true;

                    this.showCardsStaggered(cards, wrapper);

                    this.startIdleTimer(wrapper);
                });
            } else if (this.isNewsVisible) {
                const newsContainer = document.getElementById('news-cards-container');
                const newsCards = newsContainer.querySelectorAll('.news-card');
                const btnNews = document.getElementById('btn-news');

                this.stopAutoScroll();

                this.hideCardsStaggered(newsCards, () => {
                    newsContainer.classList.remove('active');
                    this.isNewsVisible = false;
                    btnNews.classList.remove('active');

                    container.classList.add('active');
                    btnRules.classList.add('active');
                    this.isRulesVisible = true;

                    this.showCardsStaggered(cards, wrapper);

                    this.startIdleTimer(wrapper);
                });
            } else {
                container.classList.add('active');
                btnRules.classList.add('active');
                this.isRulesVisible = true;

                this.showCardsStaggered(cards, wrapper);

                this.startIdleTimer(wrapper);
            }
        }
    },

    showCardsStaggered: function (cards, wrapper) {
        if (wrapper) {
            this.updateCircularPositions(wrapper);
        }

        cards.forEach((card, index) => {
            setTimeout(() => {
                card.classList.add('visible');
                card.classList.remove('hiding');
                card.style.display = 'flex';
            }, index * 20);
        });
    },

    hideCardsStaggered: function (cards, callback) {
        const cardsArray = Array.from(cards);

        cardsArray.forEach((card, index) => {
            setTimeout(() => {
                card.classList.add('hiding');
                card.classList.remove('visible');
                card.style.opacity = '0';
                card.style.display = 'none';
            }, index * 15);
        });

        setTimeout(() => {
            if (callback) callback();
        }, cardsArray.length * 30 + 50);
    },

    setupDragScroll: function (wrapperId) {
        const wrapper = document.getElementById(wrapperId);
        if (!wrapper) return;

        let startRotation = 0;
        this.isDragging = false;

        wrapper.addEventListener('mousedown', (e) => {
            this.isDragging = true;
            this.stopAutoScroll();
            wrapper.style.cursor = 'grabbing';
            this.startX = e.pageX;
            startRotation = this.currentRotation;
        });

        wrapper.addEventListener('mousemove', (e) => {
            if (!this.isDragging) return;
            e.preventDefault();
            const deltaX = e.pageX - this.startX;
            const rotationSpeed = 0.2;
            this.currentRotation = startRotation + deltaX * rotationSpeed;
            this.updateCircularPositions(wrapper);
        });

        const endDrag = () => {
            if (!this.isDragging) return;
            this.isDragging = false;
            wrapper.style.cursor = 'grab';
            if (this.isTeamVisible || this.isHintsVisible || this.isNewsVisible || this.isRulesVisible) this.startIdleTimer(wrapper);
        };

        wrapper.addEventListener('mouseup', endDrag);
        wrapper.addEventListener('mouseleave', endDrag);

        let clickStartX = 0;
        wrapper.addEventListener('mousedown', (e) => (clickStartX = e.pageX));
        wrapper.addEventListener('click', (e) => {
            if (Math.abs(e.pageX - clickStartX) > 5) e.preventDefault();
        });
    },


    setupResponsiveResize: function () {
        let resizeTimer = null;

        const refreshActiveCarousel = () => {
            const activeWrapper =
                (this.isTeamVisible && document.getElementById('team-cards-wrapper')) ||
                (this.isHintsVisible && document.getElementById('hints-cards-wrapper')) ||
                (this.isNewsVisible && document.getElementById('news-cards-wrapper')) ||
                (this.isRulesVisible && document.getElementById('rules-cards-wrapper'));

            if (activeWrapper) this.updateCircularPositions(activeWrapper);
        };

        const onResize = () => {
            if (resizeTimer) clearTimeout(resizeTimer);
            resizeTimer = setTimeout(refreshActiveCarousel, 80);
        };

        window.addEventListener('resize', onResize, { passive: true });
        window.addEventListener('orientationchange', onResize, { passive: true });
    },


    updateCircularPositions: function (wrapper) {
        if (!wrapper) return;

        const cards = Array.from(wrapper.querySelectorAll('.team-card, .hint-card, .news-card, .rules-card'));
        const n = cards.length;
        if (!n) return;

        const step = 360 / n;
        const viewportWidth = Math.max(1, window.innerWidth || 1920);
        const viewportHeight = Math.max(1, window.innerHeight || 1080);
        const radius = Math.max(220, Math.min(viewportWidth * 0.27, viewportHeight * 0.60));
        const slotSpacingDeg = viewportWidth <= 1500 ? 26 : 30;
        const rotationSlot = -this.currentRotation / step;

        cards.forEach((card, index) => {
            // Find the shortest wrapped distance from this card to the current
            // center. Unlike the old -2..2 slot loop, every DOM card is handled
            // exactly once, so 1-4 card sets cannot overwrite themselves.
            let delta = index - rotationSlot;
            while (delta > n / 2) delta -= n;
            while (delta < -n / 2) delta += n;

            const visible = n <= 5 || Math.abs(delta) <= 2.05;
            if (!visible) {
                card.style.display = 'none';
                card.style.opacity = '0';
                card.style.visibility = 'hidden';
                return;
            }

            const angle = delta * slotSpacingDeg;
            const rad = angle * Math.PI / 180;
            const x = Math.sin(rad) * radius;
            const z = Math.cos(rad) * radius;
            const distance = Math.min(Math.abs(delta) / 2, 1);
            const scale = 1 - (0.3 * distance);
            const opacity = 1 - (0.4 * distance);

            card.style.position = 'absolute';
            card.style.left = '50%';
            card.style.top = '50%';
            card.style.transformOrigin = 'center center';
            card.style.transform = `translate(-50%, -50%) translate3d(${x}px, 0, ${z}px) scale(${scale})`;
            card.style.zIndex = String(1000 + Math.round(z));
            card.style.opacity = String(opacity);
            card.style.display = 'flex';
            card.style.visibility = 'visible';
        });
    },


    startIdleTimer: function (wrapper) {

        this.stopAutoScroll();
        if (this.idleTimeout) {
            clearTimeout(this.idleTimeout);
        }

        this.idleTimeout = setTimeout(() => {
            this.startAutoScroll(wrapper);
        }, 3000);
    },

    startAutoScroll: function (wrapper) {
        if (!wrapper || this.autoScrollInterval) return;

        let lastFrame = performance.now();
        const tick = (now) => {
            if (!this.autoScrollInterval) return;

            const elapsed = Math.min(100, Math.max(0, now - lastFrame));
            if (elapsed >= 30) {
                this.currentRotation += this.autoScrollSpeed * (elapsed / 16.6667);
                this.updateCircularPositions(wrapper);
                lastFrame = now;
            }

            this.autoScrollInterval = requestAnimationFrame(tick);
        };

        this.autoScrollInterval = requestAnimationFrame(tick);
    },

    stopAutoScroll: function () {
        if (this.autoScrollInterval) {
            cancelAnimationFrame(this.autoScrollInterval);
            this.autoScrollInterval = null;
        }
        if (this.idleTimeout) {
            clearTimeout(this.idleTimeout);
            this.idleTimeout = null;
        }
    },

    show: function () {
        const infoButtons = document.getElementById('info-buttons');
        if (infoButtons) {
            infoButtons.classList.add('visible');
        }

        const visibilityMap = {
            team: SERVER.SIDE_FEEDS?.TEAM?.ENABLE !== false && (SERVER.CARDS || []).length > 0,
            rules: SERVER.SIDE_FEEDS?.RULES?.ENABLE !== false && (SERVER.RULES || []).length > 0,
            news: SERVER.SIDE_FEEDS?.NEWS?.ENABLE !== false && (SERVER.NEWS || []).length > 0,
            hints: SERVER.SIDE_FEEDS?.HINTS?.ENABLE !== false && (SERVER.HINTS || []).length > 0,
        };

        Object.entries(visibilityMap).forEach(([type, enabled]) => {
            document.getElementById(`${type}-side-panel`)?.classList.toggle('visible', enabled);
            this.updateSideFeed(type);
            if (enabled) this.startSideFeed(type);
        });
    },

    hide: function () {
        const infoButtons = document.getElementById('info-buttons');
        if (infoButtons) {
            infoButtons.classList.remove('visible');
        }

        ['team', 'rules', 'news', 'hints'].forEach((type) => {
            document.getElementById(`${type}-side-panel`)?.classList.remove('visible');
        });
        this.stopSideFeeds();

        if (this.isTeamVisible) {
            this.toggleTeam();
        }
        if (this.isHintsVisible) {
            this.toggleHints();
        }
        if (this.isNewsVisible) {
            this.toggleNews();
        }
        if (this.isRulesVisible) {
            this.toggleRules();
        }
    }
};

export default TEAM_SYSTEM;

