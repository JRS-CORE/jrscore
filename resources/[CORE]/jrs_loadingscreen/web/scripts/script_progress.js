const PROGRESS_INDICATOR = {
    fill: null,
    percent: null,
    icon: null,

    init() {
        this.fill = document.getElementById('loading-progress-fill');
        this.percent = document.getElementById('loading-progress-percent');
        this.icon = document.querySelector('#loading-progress-icon .progress-glyph');
        this.update(window.LOADING_PROGRESS || 0);
    },

    update(progress) {
        const value = Math.min(100, Math.max(0, Number(progress) || 0));

        if (!this.fill) this.fill = document.getElementById('loading-progress-fill');
        if (!this.percent) this.percent = document.getElementById('loading-progress-percent');
        if (!this.icon) this.icon = document.querySelector('#loading-progress-icon .progress-glyph');

        if (this.fill) this.fill.style.width = `${value}%`;
        if (this.percent) this.percent.textContent = `${Math.round(value)}%`;
        if (this.icon) this.icon.style.transform = `rotate(${value * 1.8}deg)`;
    },

    stop() {
        // No animation loop is used, so there is nothing to cancel.
    },
};

export default PROGRESS_INDICATOR;
