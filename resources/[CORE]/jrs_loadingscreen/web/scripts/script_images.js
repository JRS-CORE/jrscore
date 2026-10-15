import CONFIG from '../config_main.js';

const IMAGES_SCREEN = {
    currentImageIndex: 0,
    imageSlider: null,
    currentImage: null,
    nextImage: null,
    sliderInterval: null,

    transitionOverlay: null,
    transitionIndex: 0,
    transitionInterval: null,
    transitionType: 'reveal',
    waitingToComplete: false,
    onCompleteCallback: null,

    init: function () {
        this.imageSlider = document.getElementById('image-slider');
        this.currentImage = document.getElementById('image-current');
        this.nextImage = document.getElementById('image-next');
        this.transitionOverlay = document.getElementById('transition-overlay');
    },

    stop: function () {
        if (this.sliderInterval) {
            clearInterval(this.sliderInterval);
            this.sliderInterval = null;
        }

        if (this.transitionInterval) {
            clearInterval(this.transitionInterval);
            this.transitionInterval = null;
        }
    },

    waitForBlackFrameToComplete: function (callback) {
        this.waitingToComplete = true;
        if (CONFIG.VIDEO.ENABLE)
            return callback();
        this.onCompleteCallback = callback;
    },

    isOnBlackFrame: function () {
        return (this.transitionType === 'reveal' && this.transitionIndex === 1) ||
            (this.transitionType === 'hide' && this.transitionIndex === 15);
    },

    loadFirstImage: function () {
        if (CONFIG.VIDEO.ENABLE) return;

        if (!CONFIG.IMAGES.IMAGE_LIST || CONFIG.IMAGES.IMAGE_LIST.length === 0) {
            return;
        }

        this.loadImage(0);
    },


    startInitialReveal: function (callback) {
        if (!CONFIG.IMAGES.ENABLE_OVERLAY || !this.transitionOverlay) {
            if (callback) callback();
            return;
        }

        const frameCount = 15;
        const frameDuration = CONFIG.IMAGES.OVERLAY_FRAME_DURATION || 80;
        const sliderDuration = CONFIG.IMAGES.SLIDER_DURATION || 5000;
        let currentFrame = 1;

        this.transitionType = 'reveal';

        const revealInterval = setInterval(() => {
            currentFrame++;
            if (currentFrame <= frameCount) {
                this.loadTransitionFrame(currentFrame);
            } else {
                clearInterval(revealInterval);
                setTimeout(() => {
                    if (callback) callback();
                }, Math.max(0, sliderDuration - (frameCount * frameDuration)));
            }
        }, frameDuration);
    },

    startNormalLoop: function () {
        if (CONFIG.VIDEO.ENABLE) return;

        if (!CONFIG.IMAGES.IMAGE_LIST || CONFIG.IMAGES.IMAGE_LIST.length === 0) {
            return;
        }

        if (!CONFIG.IMAGES.ENABLE_SLIDER || CONFIG.IMAGES.IMAGE_LIST.length === 1) {
            return; // dont play anims if only one image
        }

        this.transitionType = 'hide';

        if (CONFIG.IMAGES.ENABLE_OVERLAY) {
            this.startOverlayLoopFromHide();
        }

        if (CONFIG.IMAGES.ENABLE_SLIDER && CONFIG.IMAGES.IMAGE_LIST.length > 1) {
            this.startSlideshow();
        }
    },

    // loads the first image
    loadImage: function (index) {
        if (!CONFIG.IMAGES.IMAGE_LIST[index]) return;

        const imagePath = `assets/images/${CONFIG.IMAGES.IMAGE_LIST[index].NAME}`;
        this.currentImage.src = imagePath;
        this.currentImage.classList.add('active');

        this.currentImageIndex = index;

    },

    startSlideshow: function () {
        const duration = CONFIG.IMAGES.SLIDER_DURATION || 5000;

        if (CONFIG.IMAGES.ENABLE_OVERLAY) {
            return;
        }

        this.sliderInterval = setInterval(() => {
            this.transitionToNext();
        }, duration);
    },

    transitionToNext: function () {
        const nextIndex = (this.currentImageIndex + 1) % CONFIG.IMAGES.IMAGE_LIST.length;
        const imagePath = `assets/images/${CONFIG.IMAGES.IMAGE_LIST[nextIndex].NAME}`;

        this.nextImage.src = imagePath;

        this.nextImage.style.transition = 'opacity 0.5s ease-in-out';
        this.nextImage.style.opacity = '1';

        this.currentImage.classList.remove('active');
        this.nextImage.classList.add('active');
        this.swapImages(nextIndex);

        setTimeout(() => {
            this.currentImage.style.opacity = '1';
        }, 500);
    },

    swapImages: function (nextIndex) {
        const temp = this.currentImage;
        this.currentImage = this.nextImage;
        this.nextImage = temp;
        this.nextImage.classList.remove('active');
        this.currentImageIndex = nextIndex;
    },

    stopSlideshow: function () {
        if (this.sliderInterval) {
            clearInterval(this.sliderInterval);
            this.sliderInterval = null;
        }
    },

    startOverlayLoopFromHide: function () {
        if (!this.transitionOverlay) return;

        this.transitionOverlay.classList.add('active');

        const sliderDuration = CONFIG.IMAGES.SLIDER_DURATION || 5000;
        const frameDuration = CONFIG.IMAGES.OVERLAY_FRAME_DURATION || 80;

        this.transitionType = 'hide';
        this.transitionIndex = 1;
        this.loadTransitionFrame(1);

        let currentFrame = 16;
        let timeInCurrentCycle = 0;

        this.transitionInterval = setInterval(() => {
            if (this.waitingToComplete && this.isOnBlackFrame()) {
                this.stop();
                if (this.onCompleteCallback) {
                    this.onCompleteCallback();
                }
                return;
            }

            timeInCurrentCycle += frameDuration;
            currentFrame++;

            if (currentFrame <= 30) {
                this.transitionType = 'hide';
                this.transitionIndex = currentFrame - 15;

                if (currentFrame === 30) {
                    if (this.waitingToComplete) {
                        this.stop();
                        if (this.onCompleteCallback) {
                            this.onCompleteCallback();
                        }
                        return;
                    }

                    this.currentImage.style.transition = 'opacity 0.3s ease-in-out';
                    this.currentImage.style.opacity = '0';
                    setTimeout(() => {
                        this.transitionOverlay.classList.remove('active');
                    }, frameDuration - 50);
                }
            } else if (currentFrame <= 45) {
                this.transitionType = 'reveal';
                this.transitionIndex = currentFrame - 30;

                if (currentFrame === 31) {
                    if (this.waitingToComplete) {
                        this.stop();
                        if (this.onCompleteCallback) {
                            this.onCompleteCallback();
                        }
                        return;
                    }

                    this.transitionOverlay.classList.add('active');
                    this.transitionToNext();
                }

                if (currentFrame === 45) {
                    setTimeout(() => {
                        this.transitionOverlay.classList.remove('active');
                    }, frameDuration - 50);
                }
            } else {

                if (timeInCurrentCycle >= sliderDuration) {
                    currentFrame = 16;
                    timeInCurrentCycle = 0;
                    this.transitionType = 'hide';
                    this.transitionIndex = 1;

                    setTimeout(() => {
                        this.transitionOverlay.classList.add('active');
                    }, 10);
                } else {

                    currentFrame = 45;
                    this.transitionIndex = 15;
                }
            }

            this.loadTransitionFrame(this.transitionIndex);
        }, frameDuration);
    },

    startOverlayLoop: function () {
        if (!this.transitionOverlay) return;

        this.transitionOverlay.classList.add('active');

        const sliderDuration = CONFIG.IMAGES.SLIDER_DURATION || 1000;
        const frameDuration = CONFIG.IMAGES.OVERLAY_FRAME_DURATION || 80;

        this.transitionType = 'reveal';
        this.transitionIndex = 1;
        this.loadTransitionFrame(1);

        let currentFrame = 1;
        let timeInCurrentCycle = 0;

        this.transitionInterval = setInterval(() => {
            if (this.waitingToComplete && this.isOnBlackFrame()) {
                this.stop();
                if (this.onCompleteCallback) {
                    this.onCompleteCallback();
                }
                return;
            }

            timeInCurrentCycle += frameDuration;
            currentFrame++;

            if (currentFrame <= 15) {
                this.transitionType = 'reveal';
                this.transitionIndex = currentFrame;

                if (currentFrame === 1) {
                    if (this.waitingToComplete) {
                        this.stop();
                        if (this.onCompleteCallback) {
                            this.onCompleteCallback();
                        }
                        return;
                    }
                }

                if (currentFrame === 15) {
                    setTimeout(() => {
                        this.transitionOverlay.classList.remove('active');
                    }, frameDuration - 50);
                }
            } else if (currentFrame <= 30) {
                this.transitionType = 'hide';
                this.transitionIndex = currentFrame - 15;

                if (currentFrame === 16) {
                    this.transitionOverlay.classList.add('active');
                }

                if (currentFrame === 30) {
                    if (this.waitingToComplete) {
                        this.stop();
                        if (this.onCompleteCallback) {
                            this.onCompleteCallback();
                        }
                        return;
                    }

                    this.currentImage.style.transition = 'opacity 0.3s ease-in-out';
                    this.currentImage.style.opacity = '0';
                    setTimeout(() => {
                        this.transitionOverlay.classList.remove('active');
                    }, frameDuration - 50);
                }
            } else {

                if (timeInCurrentCycle >= sliderDuration) {
                    currentFrame = 1;
                    timeInCurrentCycle = 0;
                    this.transitionType = 'reveal';
                    this.transitionIndex = 1;

                    this.transitionToNext();

                    setTimeout(() => {
                        this.transitionOverlay.classList.add('active');
                    }, 10);
                } else {

                    currentFrame = 30;
                    this.transitionIndex = 15;
                }
            }

            this.loadTransitionFrame(this.transitionIndex);
        }, frameDuration);
    },

    restartOverlayLoop: function () {
        if (this.transitionInterval) {
            clearInterval(this.transitionInterval);
            this.transitionInterval = null;
        }
        this.startOverlayLoop();
    },

    loadTransitionFrame: function (num) {
        if (!this.transitionOverlay) return;
        const imagePath = `assets/images/${this.transitionType}${num}.png`;

        const img = new Image();
        img.onload = () => {
            this.transitionOverlay.src = imagePath;
        };
        img.src = imagePath;
    }
};

export default IMAGES_SCREEN;