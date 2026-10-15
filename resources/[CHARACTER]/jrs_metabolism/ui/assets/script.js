(() => {
    'use strict';
    const container = document.querySelector('.main-container');
    const options = {strokeWidth: 10, trailColor: 'rgba(224,224,224,.45)', trailWidth: 10,
        easing: 'easeInOut', duration: 500, color: 'rgba(224,224,224,.9)', svgStyle: null};
    const ids = {health: 'health', stamina: 'stamina', hunger: 'hunger', thirst: 'thirst',
        voice: 'voice', horseHealth: 'heart_horse', horseStamina: 'stamina_horse'};
    const circles = {};
    for (const [name, id] of Object.entries(ids)) circles[name] = new ProgressBar.Circle(document.getElementById('prog_circle_' + id), options);
    const clamp = (n, low = 0, high = 1) => Number.isFinite(Number(n)) ? Math.max(low, Math.min(high, Number(n))) : low;
    const decode = data => typeof data === 'string' ? JSON.parse(data) : data;
    function animate(name, value) { circles[name].animate(clamp(value)); }
    function core(id, value) { document.getElementById('prog_fill_' + id).style.height = (clamp(value, 0, 100) * .8) + '%'; }
    const labels = {
        en: {health:'Health', stamina:'Stamina', hunger:'Hunger', thirst:'Thirst', voice:'Voice', horseHealth:'Horse health', horseStamina:'Horse stamina'},
        ar: {health:'الصحة', stamina:'التحمّل', hunger:'الجوع', thirst:'العطش', voice:'الصوت', horseHealth:'صحة الحصان', horseStamina:'تحمّل الحصان'}
    };
    function update(data) {
        const social = decode(data.data);
        if (!social || !social.health || !social.stamina) return;
        animate('health', social.health.normal); animate('stamina', social.stamina.normal);
        animate('hunger', 1 - clamp(social.hunger, 0, 100) / 100);
        animate('thirst', 1 - clamp(social.thirst, 0, 100) / 100);
        core('health', social.health.core); core('stamina', social.stamina.core);
        for (const name of ['hunger', 'thirst']) document.getElementById('prog_circle_' + name).classList.toggle('pulse-red', Number(social[name]) >= 60);
        const horse = data.horse === true;
        document.getElementById('horseH').hidden = !horse;
        document.getElementById('horseS').hidden = !horse;
        if (horse) {
            const values = decode(data.horseStatus) || {};
            animate('horseHealth', Number(values.horseHealthNormal) / Math.max(1, Number(values.horseHealthMax) || 600));
            animate('horseStamina', values.horseStaminaNormal);
            core('heart_horse', values.horseHealthCore); core('stamina_horse', values.horseStaminaCore);
        }
        document.getElementById('prog_circle_voice').parentElement.hidden = data.showVoice === false;
        const language = data.language === 'ar' ? 'ar' : 'en';
        document.documentElement.lang = language;
        for (const [name, id] of Object.entries(ids)) {
            const node = document.getElementById('prog_circle_' + id).parentElement;
            node.setAttribute('aria-label', labels[language][name]); node.title = labels[language][name];
        }
    }
    function position(value) {
        const vertical = value === 'left' || value === 'right';
        document.body.style.flexDirection = vertical ? 'row' : 'column';
        document.body.style.alignItems = 'center';
        document.body.style.justifyContent = value === 'left' ? 'flex-start' : 'flex-end';
        container.style.flexDirection = vertical ? 'column' : 'row';
    }
    window.addEventListener('message', event => {
        const data = event.data;
        if (!data || typeof data !== 'object') return;
        try {
            if (data.action === 'open') container.hidden = false;
            if (data.action === 'close') container.hidden = true;
            if (data.action === 'position') position(data.position);
            if (data.action === 'updateNeeds') update(data);
            if ('talking' in data || 'muted' in data) document.getElementById('prog_circle_voice').style.backgroundColor = data.muted ? 'rgba(252,0,0,.3)' : data.talking ? 'rgba(206,255,153,.3)' : 'transparent';
            if (Number.isFinite(Number(data.range))) animate('voice', Number(data.range) / 32);
        } catch (error) { console.warn('[jrs_metabolism] Invalid HUD message', error.message); }
    });
    if (typeof GetParentResourceName === 'function') {
        const ready = () => fetch('https://' + GetParentResourceName() + '/ready', {method:'POST', headers:{'Content-Type':'application/json'}, body:'{}'}).catch(() => {});
        ready();
        setTimeout(ready, 1000);
    }
})();
