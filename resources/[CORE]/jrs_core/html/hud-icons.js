/* ------------------------------------------------------------------
   Shared HUD icon set for jrs_core - ported from jrs_metabolism.

   Same system as [HUD]/jrs_metabolism/html/jrsui/editor-icons.js: the
   artwork is inline <svg> painted with `currentColor`, held in one
   registry, and dropped into any element carrying a `data-jrs-icon`
   slot attribute. Because the colour is a real CSS `color` and the size
   is a real CSS length, one glyph serves both the HUD and the editor
   rail, follows the HUD editor's Text Colour picker, and needs no PNG.

   Five glyphs are copied byte for byte out of jrs_metabolism so the two
   HUDs cannot drift apart; only the wrapper class name changed
   (editor-tab-svg -> jrs-hud-icon) so jrs_core sizes them with its own
   rule instead of jrs_metabolism's.

   Dirty Money, Level and Town are not here: jrs_metabolism has no
   equivalent widget, so those three keep their existing PNGs.
   ------------------------------------------------------------------ */

window.JRS_HUD_ICONS = {
    /* jrs_metabolism MoneyElement - the cash-on-hand dollar sign */
    money: '<svg xmlns="http://www.w3.org/2000/svg" class="jrs-hud-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" x2="12" y1="2" y2="22"></line><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"></path></svg>',

    /* jrs_metabolism GoldElement - the stacked-coins glyph */
    gold: '<svg xmlns="http://www.w3.org/2000/svg" class="jrs-hud-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M14.265 18.372c.316-.965.474-1.447.797-1.779q.231-.238.527-.386C16 16 16.5 16 17.5 16s1.5 0 1.912.207q.294.148.527.386c.323.332.48.814.797 1.779l.326.995c.394 1.202.591 1.802.297 2.218c-.295.415-.917.415-2.162.415h-3.393c-1.245 0-1.868 0-2.162-.415c-.295-.416-.098-1.016.296-2.218zm-5.501-8c.316-.965.475-1.447.797-1.779q.233-.238.527-.386C10.5 8 11 8 12 8s1.5 0 1.912.207q.294.148.527.386c.322.332.48.814.797 1.779l.326.995c.394 1.202.59 1.802.297 2.218c-.295.415-.917.415-2.163.415h-3.392c-1.246 0-1.868 0-2.162-.415c-.295-.416-.098-1.016.296-2.218zm-5.5 8c.317-.965.475-1.447.798-1.779q.231-.238.527-.386C5 16 5.5 16 6.5 16s1.5 0 1.912.207q.294.148.527.386c.323.332.48.814.797 1.779l.326.995c.394 1.202.591 1.802.297 2.218c-.295.415-.917.415-2.162.415H4.804c-1.245 0-1.868 0-2.162-.415c-.295-.416-.098-1.016.296-2.218zM12 2v2m-4.5-.5L9 5m7.5-1.5L15 5" color="currentColor"></path></svg>',

    /* jrs_metabolism JobElement - the ledger/briefcase glyph */
    job: '<svg xmlns="http://www.w3.org/2000/svg" class="jrs-hud-icon" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"><path d="M5 8h6M5 5h6m-6 6h4M3.5 1.5v13h9v-13z"></path></svg>',

    /* jrs_metabolism UserIdElement - the cowboy hat */
    userId: '<svg xmlns="http://www.w3.org/2000/svg" class="jrs-hud-icon" viewBox="0 0 640 512"><path fill="currentColor" d="M320 64c14.4 0 22.3-7 30.8-14.4C360.4 41.1 370.7 32 392 32c49.3 0 84.4 152.2 97.9 221.9c-42.1 18.2-99 34.1-169.9 34.1s-127.8-15.9-169.9-34.1C163.6 184.2 198.7 32 248 32c21.3 0 31.6 9.1 41.2 17.6C297.7 57 305.6 64 320 64zM111.1 270.7c47.2 24.5 117.5 49.3 209 49.3s161.8-24.8 208.9-49.3c24.8-12.9 49.8-28.3 70.1-47.7c7.9-7.9 20.2-9.2 29.6-3.3c9.5 5.9 13.5 17.9 9.9 28.5c-13.5 37.7-38.4 72.3-66.1 100.6C523.7 398.9 443.6 448 320 448s-203.6-49.1-252.5-99.2c-27.7-28.4-52.6-63-66.1-100.7c-3.6-10.6.4-22.6 9.9-28.5c9.5-5.9 21.7-4.5 29.6 3.3c20.4 19.4 45.3 34.8 70.1 47.7z"></path></svg>',

    /* jrs_metabolism's 'armor' key - it is the pvp shield glyph */
    pvp: '<svg xmlns="http://www.w3.org/2000/svg" class="jrs-hud-icon" viewBox="0 0 24 24"><path fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3a12 12 0 0 0 8.5 3A12 12 0 0 1 12 21A12 12 0 0 1 3.5 6A12 12 0 0 0 12 3"></path></svg>'
};

/* Fills every `data-jrs-icon` slot on the page. Safe to call more than once -
   a slot that already holds its glyph is skipped, so a later re-render never
   rebuilds SVG that is already there. */
function injectJrsHudIcons(root) {
    const icons = window.JRS_HUD_ICONS || {};
    (root || document).querySelectorAll('[data-jrs-icon]').forEach(function(slot) {
        if (slot.firstElementChild) return;
        const svg = icons[slot.getAttribute('data-jrs-icon')];
        if (svg) slot.innerHTML = svg;
    });
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() { injectJrsHudIcons() }, { once: true });
} else {
    injectJrsHudIcons();
}
