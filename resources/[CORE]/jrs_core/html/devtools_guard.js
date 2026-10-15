/**
 * JRS Security - NUI Protection
 * Suppresses developer hotkeys (F12, Ctrl+Shift+I/J/C, Ctrl+U) and right-click context menu.
 * Heuristic console/debugger polling removed to eliminate false-positive CEF kicks.
 */
(function() {
    // Keyboard Shortcut Suppression
    window.addEventListener('keydown', function(e) {
        // F12 (Steam screenshot key: suppress default NUI behavior safely)
        if (e.key === 'F12' || e.keyCode === 123) {
            e.preventDefault();
            e.stopPropagation();
            return false;
        }

        // Ctrl + Shift + I / J / C (DevTools shortcuts)
        if (e.ctrlKey && e.shiftKey && (e.key === 'I' || e.key === 'i' || e.key === 'J' || e.key === 'j' || e.key === 'C' || e.key === 'c' || e.keyCode === 73 || e.keyCode === 74 || e.keyCode === 67)) {
            e.preventDefault();
            e.stopPropagation();
            return false;
        }

        // Ctrl + U (View Source)
        if (e.ctrlKey && (e.key === 'u' || e.key === 'U' || e.keyCode === 85)) {
            e.preventDefault();
            e.stopPropagation();
            return false;
        }
    }, true);

    // Right-Click Context Menu Suppression
    window.addEventListener('contextmenu', function(e) {
        e.preventDefault();
        return false;
    }, true);
})();
