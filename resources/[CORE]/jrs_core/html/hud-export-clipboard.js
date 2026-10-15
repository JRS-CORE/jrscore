// jrs_core - HUD export clipboard copy (2026-09-06).
// server/hud_export.lua now applies an admin's exported HUD layout straight
// into the live config/config.lua and sends the same table text here, purely
// so it also lands on the OS clipboard. Clipboard access only exists on the
// client (there is no server-side "set clipboard" native), so this has to
// happen in the NUI page. Self-contained listener, no dependency on main.js.
(function () {
	function fallbackCopy(text) {
		try {
			var ta = document.createElement('textarea')
			ta.value = text
			ta.style.position = 'fixed'
			ta.style.opacity = '0'
			document.body.appendChild(ta)
			ta.focus()
			ta.select()
			document.execCommand('copy')
			document.body.removeChild(ta)
		} catch (error) {
			console.error('[jrs_core] HUD export clipboard fallback failed', error)
		}
	}

	window.addEventListener('message', function (event) {
		var data = event.data
		if (!data || data.action !== 'hudExport:copy') return
		var text = typeof data.text === 'string' ? data.text : ''
		if (!text) return

		if (navigator.clipboard && navigator.clipboard.writeText) {
			navigator.clipboard.writeText(text).catch(function () { fallbackCopy(text) })
		} else {
			fallbackCopy(text)
		}
	})
})()
