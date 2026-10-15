(() => {
    const toast = document.getElementById('zoneToast');
    const title = document.getElementById('zoneTitle');
    const district = document.getElementById('zoneDistrict');
    const state = document.getElementById('zoneState');
    const details = document.getElementById('zoneDetails');
    const zoneSound = document.getElementById('zoneSound');

    let activeSerial = 0;
    let hideTimer = null;


    function playShowSound(data) {
        if (!zoneSound || data.soundEnabled === false) return;

        const requestedFile = String(data.soundFile || 'assets/zone_open.mp3');
        const currentFile = zoneSound.getAttribute('src') || '';
        if (currentFile !== requestedFile) {
            zoneSound.setAttribute('src', requestedFile);
            zoneSound.load();
        }

        const requestedVolume = Number(data.soundVolume);
        zoneSound.volume = Number.isFinite(requestedVolume)
            ? Math.min(1, Math.max(0, requestedVolume))
            : 0.35;

        try {
            zoneSound.pause();
            zoneSound.currentTime = 0;
            const result = zoneSound.play();
            if (result && typeof result.catch === 'function') {
                result.catch(() => {});
            }
        } catch (_) {}
    }

    function clearHideTimer() {
        if (hideTimer !== null) {
            clearTimeout(hideTimer);
            hideTimer = null;
        }
    }

    function hide(serial) {
        if (serial !== undefined && serial < activeSerial) return;
        clearHideTimer();
        toast.classList.remove('is-visible');
        toast.setAttribute('aria-hidden', 'true');
    }

    function show(data) {
        clearHideTimer();
        activeSerial = Number(data.serial || activeSerial + 1);

        const titleText = String(data.title || '');
        title.textContent = titleText;
        title.classList.toggle('long-title', titleText.length > 20 && titleText.length <= 32);
        title.classList.toggle('extra-long-title', titleText.length > 32);
        district.textContent = String(data.district || '');
        state.textContent = String(data.state || '');
        const detailsText = String(data.details || '');
        if (detailsText.includes('  |  ')) {
            const parts = detailsText.split('  |  ');
            details.innerHTML = parts
                .map(p => `<bdi class="zone-detail-part">${p.trim()}</bdi>`)
                .join('<span class="zone-detail-sep">|</span>');
        } else {
            details.textContent = detailsText;
        }

        toast.style.top = String(data.top || '1.8vh');
        toast.style.width = String(data.width || '340px');
        toast.style.maxWidth = String(data.maxWidth || '82vw');
        toast.style.setProperty('--fade-in', `${Math.max(0, Number(data.fadeIn || 180))}ms`);
        toast.style.setProperty('--fade-out', `${Math.max(0, Number(data.fadeOut || 260))}ms`);

        toast.classList.remove('is-visible');
        void toast.offsetWidth;
        toast.classList.add('is-visible');
        toast.setAttribute('aria-hidden', 'false');
        playShowSound(data);

        const serial = activeSerial;
        hideTimer = setTimeout(() => hide(serial), Math.max(500, Number(data.duration || 4000)));
    }

    window.addEventListener('message', (event) => {
        const data = event.data || {};
        if (data.action === 'showZone') show(data);
        if (data.action === 'hideZone') {
            activeSerial = Math.max(activeSerial, Number(data.serial || activeSerial));
            hide(activeSerial);
        }
    });
})();
