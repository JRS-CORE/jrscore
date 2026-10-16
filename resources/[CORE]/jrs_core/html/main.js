
var rgbStart = [139,195,74]
var rgbEnd = [183,28,28]

var hudDebug = false
var hudSuppressed = true
var hudEditorActive = false
var hudLayout = {}
var hudLayoutBeforeEdit = {}
var hudDragState = null
var hudSelectedElement = 'PlayerGold'
var hudConfigVisibility = {}

// Multi-select + link (ported from jrs_metabolism's editor, 2026-09-04):
// hudSelected is the ordered ctrl-click selection (hudSelectedElement always
// equals its last entry - the "primary" whose controls the panel shows).
// hudLinkGroups is separate and session-only (never saved): editing the
// primary's scale/colour/visibility while it is linked fans the same value
// out to every other member, each of which still keeps its own separate
// entry in hudLayout and saves independently.
var hudSelected = ['PlayerGold']
var hudLinkGroups = []

// Which settings page the panel is on. The rail's element tabs all share
// data-hud-tab="element", so the active tab is (page, selected element) -
// see applyHudEditorTabState().
var hudEditorTab = 'general'

// Cross-HUD hand-off, sent by Lua with hudEditor:open (Config.HudEditor.link).
// null means "no other HUD to hand over to" - either the config switched it
// off or that resource is not running - and the button stays hidden.
var hudEditorLink = null

// Custom aiming reticle ("Crosshair" tab). Not a positioned HUD element - no
// x/y/scale, just which of the 12 shapes to draw and an optional colour tint -
// so it lives in hudLayout.crosshair rather than HUD_LAYOUT_IDS, with its own
// collect/apply pair instead of the generic per-element one.
//
// The shapes are flat-colour PNGs, not text/SVG that can take a plain
// `color:`, so tinting them uses a CSS filter - a fixed palette of pre-computed
// filter chains rather than deriving one from an arbitrary hex value.
var CROSSHAIR_SHAPE_COUNT = 12
var CROSSHAIR_COLORS = {
	white:  'brightness(0) invert(1)',
	red:    'brightness(0) saturate(100%) invert(16%) sepia(100%) saturate(7484%) hue-rotate(1deg) brightness(100%) contrast(118%)',
	green:  'brightness(0) saturate(100%) invert(68%) sepia(91%) saturate(748%) hue-rotate(70deg) brightness(104%) contrast(105%)',
	blue:   'brightness(0) saturate(100%) invert(38%) sepia(98%) saturate(2245%) hue-rotate(190deg) brightness(103%) contrast(105%)',
	yellow: 'brightness(0) saturate(100%) invert(92%) sepia(82%) saturate(749%) hue-rotate(358deg) brightness(104%) contrast(105%)',
	pink:   'brightness(0) saturate(100%) invert(46%) sepia(96%) saturate(1760%) hue-rotate(292deg) brightness(103%) contrast(105%)',
	purple: 'brightness(0) saturate(100%) invert(27%) sepia(98%) saturate(2346%) hue-rotate(265deg) brightness(103%) contrast(104%)',
	cyan:   'brightness(0) saturate(100%) invert(82%) sepia(29%) saturate(7493%) hue-rotate(139deg) brightness(102%) contrast(101%)',
	orange: 'brightness(0) saturate(100%) invert(56%) sepia(91%) saturate(1632%) hue-rotate(1deg) brightness(103%) contrast(105%)',
	black:  'brightness(0)'
}
var crosshairSettings = { shape: 0, color: 'white', v: 2 }
// 0 = game default reticle (no overlay), 1..12 = custom shapes. Layouts saved
// before the default tile existed have no v:2 and there shape 1 meant default.
var CROSSHAIR_LAYOUT_VERSION = 2
var crosshairAiming = false

// During a resource restart while the player is already in-game, Lua can send
// the initial hud:setSuppressed message before this page has finished loading
// and attached its message listener - that message is then lost forever, and
// nothing resends it once Lua believes the HUD is already in the right state.
// Telling Lua once this page is actually ready to receive messages closes
// that race (same pattern as jrs_metabolism's html/script.js notifyNuiReady).
let jrsCoreNuiReadyAcknowledged = false

function notifyJrsCoreNuiReady() {
	if (jrsCoreNuiReadyAcknowledged) return

	fetch(`https://${GetParentResourceName()}/jrsCoreHudNuiReady`, {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: "{}"
	}).then(function(response) {
		if (!response.ok) throw new Error('HTTP ' + response.status)
		jrsCoreNuiReadyAcknowledged = true
	}).catch(function() {
		setTimeout(notifyJrsCoreNuiReady, 1000)
	})
}

if (document.readyState === "loading") {
	document.addEventListener("DOMContentLoaded", function() { setTimeout(notifyJrsCoreNuiReady, 50) }, { once: true })
} else {
	setTimeout(notifyJrsCoreNuiReady, 50)
}

const HUD_LAYOUT_IDS = ['PlayerGold', 'PlayerMoney', 'PlayerDirtyMoney', 'id', 'job', 'xp', 'town', 'pvp', 'doubleXpHud']

// All compact HUD elements are shown by default. Players can hide them with /hud,
// or move, resize and switch single elements off through the /editcorehud editor.
const HUD_DEFAULT_HIDDEN = {
	PlayerGold: true,
	PlayerMoney: true,
	PlayerDirtyMoney: true,
	id: true,
	job: true,
	xp: true,
	town: true,
	pvp: true,
	doubleXpHud: true
}

// Elements that live inside another HUD block and are positioned by CSS alone.
const HUD_PINNED_IDS = { doubleXpHud: true }

const HUD_ELEMENT_NAMES = {
	PlayerGold: 'Gold',
	PlayerMoney: 'Money',
	PlayerDirtyMoney: 'Dirty Money',
	id: 'Player ID',
	job: 'Job',
	xp: 'Level',
	town: 'Town',
	pvp: 'PVP Status',
	doubleXpHud: 'XP Boost'
}

// ---------- Core Progress Bar (Parchment Style) ----------
const coreProg = {
	root: null,
	brand: null,
	label: null,
	fill: null,
	icon: null,
	pct: null,
	init: function() {
		this.root = document.getElementById('core-progressbar');
		this.brand = document.getElementById('core-progress-brand');
		this.label = document.getElementById('core-progress-label');
		this.fill = document.getElementById('core-progress-fill');
		this.icon = document.getElementById('core-progress-icon');
		this.pct = document.getElementById('core-progress-pct');
	},
	setVisible: function(show) {
		if (!this.root) this.init();
		if (!this.root) return;
		this.root.setAttribute('aria-hidden', show ? 'false' : 'true');
		this.root.classList.toggle('visible', Boolean(show));
	},
	update: function(progress, label, brand) {
		if (!this.root) this.init();
		if (!this.root) return;
		const pct = Math.max(0, Math.min(100, Number(progress) || 0));
		if (this.fill) this.fill.style.width = pct + '%';
		if (this.icon) this.icon.style.left = pct + '%';
		if (this.pct) this.pct.textContent = Math.round(pct) + '%';
		if (label !== undefined && this.label) {
			let displayLabel = label;
			if (window.JrsI18n && typeof label === 'string' && label.trim() !== '') {
				displayLabel = window.JrsI18n.t(label, window.JrsI18n.t(label.toLowerCase(), label));
			}
			this.label.textContent = String(displayLabel || (window.JrsI18n ? window.JrsI18n.t('core_working', 'Working...') : 'Working...'));
		}
		if (brand !== undefined && this.brand) {
			let displayBrand = brand;
			if (window.JrsI18n && typeof brand === 'string' && brand.trim() !== '') {
				displayBrand = window.JrsI18n.t(brand, window.JrsI18n.t(brand.toLowerCase(), brand));
			}
			if (!displayBrand || displayBrand === 'undefined' || displayBrand === '') {
				displayBrand = window.JrsI18n ? window.JrsI18n.t('core_redempire', 'JRS') : 'JRS';
			}
			this.brand.textContent = String(displayBrand);
		}
	}
};

function setCoreProgScale() {
	const responsiveScale = (window.innerHeight / 860) * 0.72;
	const s = Math.max(0.62, Math.min(1.15, responsiveScale));
	document.documentElement.style.setProperty('--core-prog-scale', s.toFixed(3));
}
window.addEventListener('resize', setCoreProgScale);
setTimeout(setCoreProgScale, 100);

$(document).ready(function() {
	if (hudDebug) console.log('[jrs_core:HUD] NUI page loaded')
	coreProg.init();
	setCoreProgScale();
	window.addEventListener('message', function(event) {
		if (event.data.action === "coreProgressShow") {
			coreProg.update(event.data.progress || 0, event.data.label, event.data.brand);
			coreProg.setVisible(true);
			return;
		} else if (event.data.action === "coreProgressUpdate") {
			coreProg.update(event.data.progress, event.data.label, event.data.brand);
			return;
		} else if (event.data.action === "coreProgressHide") {
			coreProg.setVisible(false);
			return;
		}
		if (typeof event.data.type === 'string' && event.data.type.indexOf('jrslib:') === 0) {
			const frame = document.getElementById('jrsLibUi')
			if (frame && frame.contentWindow) {
				frame.style.pointerEvents = ((event.data.type === 'jrslib:open_inputs' || event.data.type === 'jrslib:open_answer') && event.data.status === true) ? 'auto' : 'none'
				frame.contentWindow.postMessage(event.data, '*')
			}
			return
		}
		if (event.data.action == "setValuejrscore"){
			if (hudDebug) console.log('[jrs_core:HUD] received setValuejrscore: ' + event.data.key + ' = ' + event.data.value)
			if (!hudSuppressed) $("#ui").stop(true, true).fadeIn(150)
			if (event.data.key == "job"){
				setJobIcons(event.data.icon)
			}
			setValuee(event.data.key, event.data.value)
			if (event.data.tooltip !== undefined) {
				$('#' + event.data.key).attr('title', event.data.tooltip)
			}
			if (event.data.progress !== undefined) {
				$('#' + event.data.key).attr('data-progress', event.data.progress)
			}
		} else if (event.data.action == "close") {
			if (hudDebug) console.log('[jrs_core:HUD] received close')
          $("#ui").fadeOut();
		} else if (event.data.action == "toggleVisibility") {
			if (hudDebug) console.log('[jrs_core:HUD] received toggleVisibility: ' + event.data.key + ' = ' + event.data.visible)
			setVisibility(event.data.key, event.data.visible)
		} else if (event.data.action == "setPvpState") {
			setPvpState(event.data.enabled === true)
		} else if (event.data.action == "setPvpIdle") {
			setPvpIdle(event.data.idle === true)
		} else if (event.data.action == "hud:setSuppressed") {
			setHudSuppressed(event.data.suppressed === true)
		} else if (event.data.action == "hud:applyLayout") {
			applyHudLayout(event.data.layout || {})
		} else if (event.data.action == "hudEditor:open") {
			applyHudEditorLink(event.data.link)
			applyHudExportAccess(event.data.canExportDefaults === true)
			setCrosshairTabVisibility(event.data.crosshairEnabled !== false)
			openHudEditor(event.data.layout || hudLayout, event.data.focusTab)
		} else if (event.data.action == "hudEditor:forceClose") {
			forceCloseHudEditor()
		} else if (event.data.action == "jrs_crosshair:visibility" || event.data.action == "crosshair:visibility") {
			setCrosshairAiming(event.data.visible === true)
         }
	});

	HUD_LAYOUT_IDS.forEach(function(id) {
		const element = document.getElementById(id)
		if (element) element.addEventListener('pointerdown', beginHudDrag)
	})


	document.querySelectorAll('[data-hud-action]').forEach(function(button) {
		button.addEventListener('click', function() {
			handleHudEditorAction(button.getAttribute('data-hud-action'))
		})
	})

	document.querySelectorAll('[data-hud-element]').forEach(function(button) {
		button.addEventListener('click', function(event) {
			selectHudElement(button.getAttribute('data-hud-element'), { ctrlKey: event.ctrlKey || event.metaKey })
		})
	})

	const colorPicker = document.getElementById('hudColorInput')
	const colorHex = document.getElementById('hudColorHex')
	if (colorPicker) colorPicker.addEventListener('input', function() { setSelectedHudColor(colorPicker.value) })
	if (colorHex) colorHex.addEventListener('change', function() {
		if (HEX_COLOR_RE.test(colorHex.value)) setSelectedHudColor(colorHex.value)
	})
	const colorReset = document.getElementById('hudColorReset')
	if (colorReset) colorReset.addEventListener('click', function() { setSelectedHudColor('') })

	const linkBtn = document.getElementById('hudLinkBtn')
	const unlinkBtn = document.getElementById('hudUnlinkBtn')
	if (linkBtn) linkBtn.addEventListener('click', linkSelectedHudElements)
	if (unlinkBtn) unlinkBtn.addEventListener('click', unlinkSelectedHudElements)

	document.querySelectorAll('[data-hud-tab]').forEach(function(button) {
		button.addEventListener('click', function() {
			setHudEditorTab(button.getAttribute('data-hud-tab'))
		})
	})

	const scaleInput = document.getElementById('hudScaleInput')
	if (scaleInput) {
		scaleInput.addEventListener('input', function() {
			setSelectedHudScale(Number(scaleInput.value) / 100)
		})
	}

	document.querySelectorAll('[data-hud-scale-step]').forEach(function(button) {
		button.addEventListener('click', function() {
			const settings = ensureHudElementSettings(hudSelectedElement)
			setSelectedHudScale(settings.scale + Number(button.getAttribute('data-hud-scale-step') || 0))
		})
	})

	const visibilityToggle = document.getElementById('hudVisibilityToggle')
	if (visibilityToggle) visibilityToggle.addEventListener('click', toggleSelectedHudVisibility)

	// General page "Element Visibility" chips - same control jrs_metabolism's
	// editor puts on its General tab. These toggle straight from the grid
	// rather than going through the current selection.
	document.querySelectorAll('[data-hud-toggle]').forEach(function(chip) {
		chip.addEventListener('click', function() {
			toggleHudElementVisibility(chip.getAttribute('data-hud-toggle'))
		})
	})

	document.querySelectorAll('[data-crosshair-shape]').forEach(function(card) {
		card.addEventListener('click', function() {
			setCrosshairShape(Number(card.getAttribute('data-crosshair-shape')))
		})
	})

	document.querySelectorAll('[data-crosshair-color]').forEach(function(swatch) {
		swatch.addEventListener('click', function() {
			setCrosshairColor(swatch.getAttribute('data-crosshair-color'))
		})
	})

	setupHudEditorWindow()

	window.addEventListener('pointermove', moveHudDrag)
	window.addEventListener('pointerup', endHudDrag)
	window.addEventListener('pointercancel', endHudDrag)
	window.addEventListener('resize', handleHudResize)
	document.addEventListener('keydown', function(event) {
		if (hudEditorActive && event.key === 'Escape') handleHudEditorAction('cancel')
	})
});

function postHudEditorCallback(name, payload) {
	return fetch('https://' + GetParentResourceName() + '/' + name, {
		method: 'POST',
		headers: { 'Content-Type': 'application/json; charset=UTF-8' },
		body: JSON.stringify(payload || {})
	}).catch(function(error) {
		if (hudDebug) console.error('[jrs_core:HUD] callback failed', name, error)
	})
}

function cloneHudLayout(layout) {
	return JSON.parse(JSON.stringify(layout || {}))
}

const HEX_COLOR_RE = /^#[0-9a-fA-F]{6}$/

function normalizeHudPoint(point) {
	if (!point || typeof point !== 'object') return null
	const x = Number(point.x)
	const y = Number(point.y)
	if (!Number.isFinite(x) || !Number.isFinite(y)) return null
	const scale = Number(point.scale)
	return {
		x: Math.min(1, Math.max(0, x)),
		y: Math.min(1, Math.max(0, y)),
		scale: Number.isFinite(scale) ? Math.min(1.8, Math.max(0.5, scale)) : 1,
		visible: point.visible !== false,
		color: HEX_COLOR_RE.test(point.color) ? point.color : ''
	}
}

function ensureHudElementSettings(id) {
	if (!HUD_LAYOUT_IDS.includes(id)) id = HUD_LAYOUT_IDS[0]
	if (!hudLayout[id] || typeof hudLayout[id] !== 'object') hudLayout[id] = {}
	const settings = hudLayout[id]
	const scale = Number(settings.scale)
	settings.scale = Number.isFinite(scale) ? Math.min(1.8, Math.max(0.5, scale)) : 1
	// Shown unless this element was switched off (editor / saved layout)
	settings.visible = settings.visible !== false
	// "" means "keep this element's own default colour" (the hardcoded
	// per-#id rule in style.css) rather than forcing white on everything.
	settings.color = HEX_COLOR_RE.test(settings.color) ? settings.color : ''
	return settings
}

function applyHudElementSettings(id) {
	const element = document.getElementById(id)
	if (!element) return
	// Routed through ensureHudElementSettings (rather than reading hudLayout[id]
	// directly) so the HUD_DEFAULT_HIDDEN fallback above is applied the first
	// time an element is ever rendered, not only once the editor is opened.
	const settings = ensureHudElementSettings(id)
	element.style.setProperty('--hud-scale', settings.scale)
	if (HEX_COLOR_RE.test(settings.color)) {
		element.style.setProperty('--hud-color', settings.color)
	} else {
		element.style.removeProperty('--hud-color')
	}
	element.classList.toggle('hud-user-hidden', settings.visible === false)
	element.classList.toggle('hud-config-hidden', hudConfigVisibility[id] === false)
}

function clearHudElementPosition(element) {
	element.classList.remove('hud-custom-position')
	element.style.position = ''
	element.style.left = ''
	element.style.top = ''
	element.style.right = ''
	element.style.bottom = ''
	element.style.zIndex = ''
}

function placeHudElement(element, point) {
	const safePoint = normalizeHudPoint(point)
	if (!safePoint) return
	const rect = element.getBoundingClientRect()
	const maxLeft = Math.max(0, window.innerWidth - Math.max(1, rect.width))
	const maxTop = Math.max(0, window.innerHeight - Math.max(1, rect.height))
	element.classList.add('hud-custom-position')
	element.style.position = 'fixed'
	element.style.right = 'auto'
	element.style.bottom = 'auto'
	element.style.left = Math.round(safePoint.x * maxLeft) + 'px'
	element.style.top = Math.round(safePoint.y * maxTop) + 'px'
	element.style.zIndex = '9000'
}

function normalizeCrosshairSettings(value) {
	let shape = Math.round(Number(value && value.shape))
	if (!Number.isFinite(shape)) shape = 0
	if (Number(value && value.v) !== CROSSHAIR_LAYOUT_VERSION && shape === 1) shape = 0
	const color = value && value.color
	return {
		shape: Math.min(CROSSHAIR_SHAPE_COUNT, Math.max(0, shape)),
		color: Object.prototype.hasOwnProperty.call(CROSSHAIR_COLORS, color) ? color : 'white',
		v: CROSSHAIR_LAYOUT_VERSION
	}
}

function crosshairImageSrc(shape) {
	return 'img/crosshair/crosshair' + shape + '.png?v=2'
}

function renderCrosshairPreview() {
	const isDefault = crosshairSettings.shape < 1
	const preview = document.getElementById('crosshairEditorPreview')
	if (preview) {
		if (!isDefault) preview.src = crosshairImageSrc(crosshairSettings.shape)
		preview.hidden = isDefault
	}
	const label = document.getElementById('crosshairEditorPreviewDefault')
	if (label) label.hidden = !isDefault
}

function setCrosshairTabVisibility(enabled) {
	const tab = document.querySelector('[data-hud-tab="crosshair"]')
	if (tab) tab.style.display = enabled ? '' : 'none'
	const groupHeader = document.querySelector('[data-i18n="core_gameplay"]')
	if (groupHeader) groupHeader.style.display = enabled ? '' : 'none'
	const page = document.querySelector('[data-hud-page="crosshair"]')
	if (page) page.style.display = enabled ? '' : 'none'
}

function applyCrosshairSettings(value) {
	crosshairSettings = normalizeCrosshairSettings(value)
	document.documentElement.style.setProperty('--crosshair-filter', CROSSHAIR_COLORS[crosshairSettings.color])
	const reticle = document.getElementById('crosshairReticle')
	if (reticle && crosshairSettings.shape >= 1) reticle.src = crosshairImageSrc(crosshairSettings.shape)
	renderCrosshairPreview()
	if (hudEditorActive) renderCrosshairControls()
	renderCrosshairVisibility()
}

function collectCrosshairSettings() {
	return { shape: crosshairSettings.shape, color: crosshairSettings.color, v: CROSSHAIR_LAYOUT_VERSION }
}

// Driven every frame by client/crosshair.lua's aiming-detection thread - kept
// independent of the compact HUD's own hud:setSuppressed (a player can aim
// with the HUD suppressed, e.g. while a non-blocking overlay is open).
function setCrosshairAiming(visible) {
	crosshairAiming = visible === true
	renderCrosshairVisibility()
}

function renderCrosshairVisibility() {
	const reticle = document.getElementById('crosshairReticle')
	const custom = crosshairSettings.shape >= 1
	const visible = custom && (hudEditorActive ? hudEditorTab === 'crosshair' : crosshairAiming)
	if (reticle) reticle.classList.toggle('is-aiming', visible)
}

function applyHudLayout(layout) {
	hudLayout = cloneHudLayout(layout)
	HUD_LAYOUT_IDS.forEach(function(id) {
		const element = document.getElementById(id)
		if (!element) return
		clearHudElementPosition(element)
		applyHudElementSettings(id)
	})
	applyCrosshairSettings(hudLayout.crosshair)
	requestAnimationFrame(function() {
		HUD_LAYOUT_IDS.forEach(function(id) {
			const element = document.getElementById(id)
			if (element && hudLayout[id] && !HUD_PINNED_IDS[id]) placeHudElement(element, hudLayout[id])
		})
		if (hudEditorActive) renderHudEditorControls()
	})
}

function materializeHudElements() {
	const positions = []
	HUD_LAYOUT_IDS.forEach(function(id) {
		const element = document.getElementById(id)
		if (!element || HUD_PINNED_IDS[id]) return
		const rect = element.getBoundingClientRect()
		positions.push({ element: element, left: rect.left, top: rect.top })
	})
	positions.forEach(function(item) {
		item.element.classList.add('hud-custom-position')
		item.element.style.position = 'fixed'
		item.element.style.right = 'auto'
		item.element.style.bottom = 'auto'
		item.element.style.left = Math.round(item.left) + 'px'
		item.element.style.top = Math.round(item.top) + 'px'
		item.element.style.zIndex = '9000'
	})
}

function collectHudLayout() {
	const result = {}
	HUD_LAYOUT_IDS.forEach(function(id) {
		const element = document.getElementById(id)
		if (!element) return
		const rect = element.getBoundingClientRect()
		const maxLeft = Math.max(1, window.innerWidth - Math.max(1, rect.width))
		const maxTop = Math.max(1, window.innerHeight - Math.max(1, rect.height))
		const current = hudLayout[id] || {}
		// A pinned element keeps whatever coordinate is already on file (0,0 for
		// a fresh layout). Writing its live rect would only save a position that
		// applyHudLayout is going to ignore anyway.
		const pinned = !!HUD_PINNED_IDS[id]
		result[id] = {
			x: pinned ? (Number(current.x) || 0) : Math.min(1, Math.max(0, rect.left / maxLeft)),
			y: pinned ? (Number(current.y) || 0) : Math.min(1, Math.max(0, rect.top / maxTop)),
			scale: Number.isFinite(Number(current.scale)) ? Math.min(1.8, Math.max(0.5, Number(current.scale))) : 1,
			visible: false,
			color: HEX_COLOR_RE.test(current.color) ? current.color : ''
		}
	})
	result.crosshair = collectCrosshairSettings()
	return result
}

function setHudSuppressed(suppressed) {
	hudSuppressed = suppressed === true
	document.body.classList.toggle('hud-suppressed', hudSuppressed)
	if (hudSuppressed) {
		$("#ui").stop(true, true).hide()
		if (hudEditorActive) forceCloseHudEditor()
	} else {
		$("#ui").stop(true, true).fadeIn(150)
	}
}

function openHudEditor(layout, focusTab) {
	if (hudEditorActive) return
	// Lua already validated every precondition (character ready, not dead,
	// layout loaded, config enabled).  If the HUD is still suppressed from a
	// stale periodic tick, force it visible now — the editor needs the HUD on
	// screen to let the player drag elements around.
	if (hudSuppressed) setHudSuppressed(false)
	hudLayoutBeforeEdit = cloneHudLayout(layout || hudLayout)
	hudEditorActive = true
	document.body.classList.add('hud-editing')
	restoreHudEditorWindow()
	const crosshairTab = document.querySelector('[data-hud-tab="crosshair"]')
	const crosshairVisible = !crosshairTab || crosshairTab.style.display !== 'none'
	if (focusTab === 'crosshair' && !crosshairVisible) focusTab = 'general'
	setHudEditorTab(focusTab || 'general')
	applyHudLayout(layout || hudLayout)
	requestAnimationFrame(function() {
		materializeHudElements()
		hudLayout = collectHudLayout()
		selectHudElement(hudSelectedElement)
		const panel = document.getElementById('hudEditorPanel')
		if (panel) panel.setAttribute('aria-hidden', 'false')
	})
}

function finishHudEditor() {
	hudEditorActive = false
	hudDragState = null
	renderCrosshairVisibility()
	document.body.classList.remove('hud-editing')
	document.querySelectorAll('.hud-dragging').forEach(function(element) {
		element.classList.remove('hud-dragging')
	})
	document.querySelectorAll('.hud-selected').forEach(function(element) {
		element.classList.remove('hud-selected')
	})
	document.querySelectorAll('.hud-linked').forEach(function(element) {
		element.classList.remove('hud-linked')
	})
	document.querySelectorAll('.hud-editor-inactive').forEach(function(element) {
		element.classList.remove('hud-editor-inactive')
	})
	document.querySelectorAll('[data-hud-editor-state]').forEach(function(element) {
		element.removeAttribute('data-hud-editor-state')
	})
	restoreHudEditorWindow()
	const panel = document.getElementById('hudEditorPanel')
	if (panel) panel.setAttribute('aria-hidden', 'true')
}

/* ------------------------------------------------- editor window chrome */
// Header drag, minimise-to-dock and rail resizing, ported from
// jrs_metabolism's html/jrsui/editor.js so both editors behave the same.

function restoreHudEditorWindow() {
	const menu = document.getElementById('hudEditorMenu')
	const dock = document.getElementById('editorDock')
	if (menu) menu.classList.remove('is-minimized', 'is-dragging')
	if (dock) dock.classList.remove('show')
}

function minimizeHudEditorWindow() {
	const menu = document.getElementById('hudEditorMenu')
	const dock = document.getElementById('editorDock')
	if (menu) menu.classList.add('is-minimized')
	if (dock) dock.classList.add('show')
}

function setupHudEditorWindow() {
	const menu = document.getElementById('hudEditorMenu')
	if (!menu) return

	const minimizeBtn = document.getElementById('editorMinimize')
	const restoreBtn = document.getElementById('editorRestore')
	if (minimizeBtn) minimizeBtn.addEventListener('click', minimizeHudEditorWindow)
	if (restoreBtn) restoreBtn.addEventListener('click', restoreHudEditorWindow)

	let windowDrag = null
	let railResize = null
	const header = document.getElementById('editorHeader')
	const rail = document.getElementById('editorTabs')
	const handle = document.getElementById('editorResize')

	function setWindowPosition(x, y) {
		menu.style.setProperty('--jrs-editor-x', x + 'px')
		menu.style.setProperty('--jrs-editor-y', y + 'px')
		menu.classList.add('is-positioned')
	}

	if (header) {
		header.addEventListener('mousedown', function(event) {
			if (event.button !== 0 || event.target.closest('.editor-header-btn')) return
			const rect = menu.getBoundingClientRect()
			// Switch off the centring transform before moving, or every drag
			// would jump by half the panel size.
			setWindowPosition(rect.left, rect.top)
			windowDrag = {
				dx: event.clientX - rect.left,
				dy: event.clientY - rect.top,
				w: rect.width,
				h: rect.height
			}
			menu.classList.add('is-dragging')
			event.preventDefault()
		})
	}

	if (handle && rail) {
		handle.addEventListener('mousedown', function(event) {
			if (event.button !== 0) return
			railResize = { x: event.clientX, w: rail.getBoundingClientRect().width }
			event.preventDefault()
		})
	}

	document.addEventListener('mousemove', function(event) {
		if (windowDrag) {
			const maxLeft = Math.max(0, window.innerWidth - windowDrag.w)
			const maxTop = Math.max(0, window.innerHeight - windowDrag.h)
			setWindowPosition(
				Math.min(Math.max(0, event.clientX - windowDrag.dx), maxLeft),
				Math.min(Math.max(0, event.clientY - windowDrag.dy), maxTop)
			)
			return
		}
		if (railResize && rail) {
			rail.style.width = Math.min(420, Math.max(140, railResize.w + (event.clientX - railResize.x))) + 'px'
		}
	})

	document.addEventListener('mouseup', function() {
		if (windowDrag) menu.classList.remove('is-dragging')
		windowDrag = null
		railResize = null
	})
}

function forceCloseHudEditor() {
	if (!hudEditorActive) return
	applyHudLayout(hudLayoutBeforeEdit)
	finishHudEditor()
}

function handleHudEditorAction(action) {
	if (!hudEditorActive) return
	if (action === 'save') {
		hudLayout = collectHudLayout()
		const saved = cloneHudLayout(hudLayout)
		finishHudEditor()
		applyHudLayout(saved)
		postHudEditorCallback('hudEditorSave', { layout: saved })
		return
	}
	if (action === 'switch') {
		// Same save path as 'save', then Lua opens the other HUD's editor. The
		// button is a way to carry on editing, not a way to discard edits.
		if (!hudEditorLink) return
		hudLayout = collectHudLayout()
		const saved = cloneHudLayout(hudLayout)
		finishHudEditor()
		applyHudLayout(saved)
		postHudEditorCallback('hudEditorSwitch', { layout: saved })
		return
	}
	if (action === 'export') {
		// Exports whatever is currently laid out in the editor, not just the
		// last-saved state - matches jrs_metabolism's own Export Defaults,
		// which does not require Save first either. Does not close the editor.
		postHudEditorCallback('hudEditorExport', { layout: collectHudLayout() })
		return
	}
	if (action === 'reset') {
		// Remove every saved inline position first so the elements return to the
		// original CSS stack. A second frame makes sure the browser has finished
		// rebuilding that default layout before we freeze the editor positions.
		hudDragState = null
		applyHudLayout({})
		requestAnimationFrame(function() {
			requestAnimationFrame(function() {
				materializeHudElements()
				hudLayout = collectHudLayout()
				selectHudElement(HUD_LAYOUT_IDS[0])
			})
		})
		return
	}
	applyHudLayout(hudLayoutBeforeEdit)
	finishHudEditor()
	postHudEditorCallback('hudEditorCancel', {})
}

function beginHudDrag(event) {
	if (!hudEditorActive || event.button !== 0) return
	const element = event.currentTarget
	selectHudElement(element.id, { ctrlKey: event.ctrlKey || event.metaKey, fromClick: true })
	// Pinned elements are still selectable - so scale/colour/visibility can be
	// changed from the panel - they just cannot be dragged out of their block.
	if (HUD_PINNED_IDS[element.id]) {
		event.preventDefault()
		return
	}
	const rect = element.getBoundingClientRect()
	hudDragState = {
		element: element,
		offsetX: event.clientX - rect.left,
		offsetY: event.clientY - rect.top,
		pointerId: event.pointerId
	}
	element.classList.add('hud-dragging')
	if (element.setPointerCapture) element.setPointerCapture(event.pointerId)
	event.preventDefault()
}

function moveHudDrag(event) {
	if (!hudDragState || event.pointerId !== hudDragState.pointerId) return
	const element = hudDragState.element
	const rect = element.getBoundingClientRect()
	const left = Math.min(Math.max(0, event.clientX - hudDragState.offsetX), Math.max(0, window.innerWidth - rect.width))
	const top = Math.min(Math.max(0, event.clientY - hudDragState.offsetY), Math.max(0, window.innerHeight - rect.height))
	element.style.left = Math.round(left) + 'px'
	element.style.top = Math.round(top) + 'px'
	event.preventDefault()
}

function endHudDrag(event) {
	if (!hudDragState || (event.pointerId !== undefined && event.pointerId !== hudDragState.pointerId)) return
	hudDragState.element.classList.remove('hud-dragging')
	hudDragState = null
}

function handleHudResize() {
	if (hudEditorActive) {
		const current = collectHudLayout()
		applyHudLayout(current)
		requestAnimationFrame(materializeHudElements)
		return
	}
	applyHudLayout(hudLayout)
}

function selectHudElement(id, options) {
	if (!HUD_LAYOUT_IDS.includes(id)) id = HUD_LAYOUT_IDS[0]
	const ctrl = !!(options && options.ctrlKey)
	const fromClick = !!(options && options.fromClick)

	if (ctrl) {
		const index = hudSelected.indexOf(id)
		if (index === -1) hudSelected.push(id)
		else if (hudSelected.length > 1) hudSelected.splice(index, 1)
		// else: last remaining member, ctrl-click does nothing - always keep one.
	} else {
		// A plain click always narrows the selection down to just this one
		// and makes it primary - there is no group-drag here (unlike
		// jrs_metabolism's selection.js) that would need a click to leave an
		// existing multi-selection intact.
		hudSelected = [id]
	}

	hudSelectedElement = hudSelected[hudSelected.length - 1]

	HUD_LAYOUT_IDS.forEach(function(elementId) {
		const element = document.getElementById(elementId)
		if (element) element.classList.toggle('hud-selected', hudSelected.indexOf(elementId) !== -1 && hudEditorActive)
	})

	// Clicking an actual on-screen HUD element (not just a rail thumbnail)
	// should jump straight to its settings page, same as jrs_metabolism's
	// selection.js does for its own widgets - otherwise the click only
	// highlights the element while the panel stays on whatever page/tab it
	// already happened to be showing (General, Crosshair, ...).
	if (fromClick && hudEditorActive && hudEditorTab !== 'element') {
		setHudEditorTab('element')
	}

	renderHudEditorControls()
}

/* -------------------------------------------------------------- linking */
// Session-only, never saved - same model as jrs_metabolism's editor.
function hudGroupIndexFor(id) {
	return hudLinkGroups.findIndex(function(group) { return group.indexOf(id) !== -1 })
}

function hudLinkedMembersOf(id) {
	const index = hudGroupIndexFor(id)
	return index === -1 ? [id] : hudLinkGroups[index].slice()
}

function linkSelectedHudElements() {
	if (hudSelected.length < 2) return
	const merged = {}
	hudSelected.forEach(function(id) { merged[id] = true })
	hudLinkGroups = hudLinkGroups.filter(function(group) {
		const overlaps = group.some(function(id) { return merged[id] })
		if (overlaps) group.forEach(function(id) { merged[id] = true })
		return !overlaps
	})
	hudLinkGroups.push(Object.keys(merged))
	renderHudEditorControls()
}

function unlinkSelectedHudElements() {
	if (!hudSelected.length) return
	const leaving = {}
	hudSelected.forEach(function(id) { leaving[id] = true })
	hudLinkGroups = hudLinkGroups
		.map(function(group) { return group.filter(function(id) { return !leaving[id] }) })
		.filter(function(group) { return group.length > 1 })
	renderHudEditorControls()
}

function getHudElementName(id) {
	if (window.JrsI18n) {
		return window.JrsI18n.t('core_hud_name_' + id, HUD_ELEMENT_NAMES[id] || id)
	}
	return HUD_ELEMENT_NAMES[id] || id
}

function renderHudEditorControls() {
	const settings = ensureHudElementSettings(hudSelectedElement)
	const selectedName = document.getElementById('hudSelectedName')
	const scaleInput = document.getElementById('hudScaleInput')
	const scaleValue = document.getElementById('hudScaleValue')
	const visibilityToggle = document.getElementById('hudVisibilityToggle')
	const colorPicker = document.getElementById('hudColorInput')
	const colorHex = document.getElementById('hudColorHex')
	const selectionNote = document.getElementById('hudSelectionNote')
	const linkBtn = document.getElementById('hudLinkBtn')
	const unlinkBtn = document.getElementById('hudUnlinkBtn')

	const names = hudSelected.map(function(id) { return getHudElementName(id) })
	if (selectedName) {
		selectedName.textContent = hudSelected.length > 1
			? getHudElementName(hudSelectedElement) + ' (+' + (hudSelected.length - 1) + ')'
			: getHudElementName(hudSelectedElement)
	}
	if (selectionNote) {
		selectionNote.textContent = hudSelected.length > 1 ? names.join(', ') : ''
	}
	if (scaleInput) scaleInput.value = String(Math.round(settings.scale * 100))
	if (scaleValue) scaleValue.textContent = Math.round(settings.scale * 100) + '%'
	if (visibilityToggle) visibilityToggle.setAttribute('aria-checked', settings.visible !== false ? 'true' : 'false')
	const currentColor = HEX_COLOR_RE.test(settings.color) ? settings.color : '#ffffff'
	if (colorPicker) colorPicker.value = currentColor
	if (colorHex) colorHex.value = currentColor

	const anyLinked = hudSelected.some(function(id) { return hudGroupIndexFor(id) !== -1 })
	if (linkBtn) linkBtn.hidden = hudSelected.length < 2
	if (unlinkBtn) unlinkBtn.hidden = !anyLinked

	document.querySelectorAll('[data-hud-element]').forEach(function(row) {
		const id = row.getAttribute('data-hud-element')
		const rowSettings = hudLayout[id] || {}
		const userVisible = rowSettings.visible !== false
		const serverVisible = hudConfigVisibility[id] !== false
		row.classList.toggle('is-selected', hudSelected.indexOf(id) !== -1)
		row.classList.toggle('is-linked', hudGroupIndexFor(id) !== -1)
		row.classList.toggle('is-hidden', !userVisible || !serverVisible)
		const status = row.querySelector('small') || row.querySelector('strong')
		if (status) {
			const text = !serverVisible ?
				(window.JrsI18n ? window.JrsI18n.t('core_server_off', 'SERVER OFF') : 'SERVER OFF') :
				(userVisible ? (window.JrsI18n ? window.JrsI18n.t('core_active', 'ACTIVE') : 'ACTIVE') :
				(window.JrsI18n ? window.JrsI18n.t('core_not_active', 'NOT ACTIVE') : 'NOT ACTIVE'));
			status.textContent = text;
		}
	})

	document.querySelectorAll('[data-hud-toggle]').forEach(function(chip) {
		const id = chip.getAttribute('data-hud-toggle')
		const chipSettings = hudLayout[id] || {}
		const serverVisible = hudConfigVisibility[id] !== false
		chip.classList.toggle('on', serverVisible && chipSettings.visible !== false)
		chip.classList.toggle('is-server-off', !serverVisible)
	})

	// The world-side elements carry the violet "linked" outline, active/not active badge,
	// and inactive amber tint so the state is clear on screen.
	HUD_LAYOUT_IDS.forEach(function(id) {
		const element = document.getElementById(id)
		if (element) {
			element.classList.toggle('hud-linked', hudEditorActive && hudGroupIndexFor(id) !== -1)
			const settings = hudLayout[id] || {}
			const isInactive = settings.visible === false || hudConfigVisibility[id] === false
			element.classList.toggle('hud-editor-inactive', hudEditorActive && isInactive)
			const label = HUD_ELEMENT_NAMES[id] || id
			const stateText = isInactive ? 'NOT ACTIVE' : 'ACTIVE'
			element.setAttribute('data-hud-editor-state', label + ' · ' + stateText)
		}
	})

	// The rail's element tabs share one `data-hud-tab="element"`, so which of
	// them draws as active depends on the current selection, not on the tab
	// name alone - hence re-running the tab pass from here.
	applyHudEditorTabState()
}

function applyHudEditorTabState() {
	document.querySelectorAll('[data-hud-tab]').forEach(function(button) {
		const elementId = button.getAttribute('data-hud-element')
		const active = button.getAttribute('data-hud-tab') === hudEditorTab
			&& (!elementId || elementId === hudSelectedElement)
		button.classList.toggle('active', active)
		button.setAttribute('aria-selected', active ? 'true' : 'false')
	})
	document.querySelectorAll('[data-hud-page]').forEach(function(page) {
		page.classList.toggle('active', page.getAttribute('data-hud-page') === hudEditorTab)
	})
}

function setHudEditorTab(tabName) {
	hudEditorTab = String(tabName || 'general')
	applyHudEditorTabState()
	if (hudEditorTab === 'crosshair') {
		renderCrosshairControls()
	}
	renderCrosshairVisibility()
}

function renderCrosshairControls() {
	document.querySelectorAll('[data-crosshair-shape]').forEach(function(card) {
		card.classList.toggle('is-selected', Number(card.getAttribute('data-crosshair-shape')) === crosshairSettings.shape)
	})
	document.querySelectorAll('[data-crosshair-color]').forEach(function(swatch) {
		swatch.classList.toggle('is-selected', swatch.getAttribute('data-crosshair-color') === crosshairSettings.color)
	})
	renderCrosshairPreview()
}

function setCrosshairShape(shape) {
	if (!hudEditorActive) return
	crosshairSettings = normalizeCrosshairSettings({ shape: shape, color: crosshairSettings.color, v: CROSSHAIR_LAYOUT_VERSION })
	applyCrosshairSettings(crosshairSettings)
}

function setCrosshairColor(color) {
	if (!hudEditorActive) return
	crosshairSettings = normalizeCrosshairSettings({ shape: crosshairSettings.shape, color: color, v: CROSSHAIR_LAYOUT_VERSION })
	applyCrosshairSettings(crosshairSettings)
}

function applyHudEditorLink(link) {
	hudEditorLink = (link && link.enabled === true) ? link : null

	const section = document.getElementById('hudLinkSection')
	const button = document.getElementById('hudSwitchBtn')
	const hint = document.getElementById('hudSwitchHint')
	if (!section) return

	section.hidden = !hudEditorLink
	if (!hudEditorLink) return

	if (button) button.textContent = hudEditorLink.label || 'Other HUD'
	if (hint) hint.textContent = hudEditorLink.hint || ''
}

// Developer-only "Export Defaults" section (2026-09-05). server/hud_export.lua
// already refuses the export server-side for anyone who isn't an admin - this
// only stops the section (and the fact this feature exists) from being shown
// to a player who'd just get a "no permission" toast. Hidden by default in
// the HTML, so a missing/old flag fails closed.
function applyHudExportAccess(canExport) {
	const section = document.getElementById('hudDeveloperSection')
	if (section) section.hidden = canExport !== true
}

function toggleHudElementVisibility(id) {
	if (!hudEditorActive || HUD_LAYOUT_IDS.indexOf(id) === -1) return
	const settings = ensureHudElementSettings(id)
	settings.visible = settings.visible === false
	applyHudElementSettings(id)
	renderHudEditorControls()
}

function setSelectedHudScale(value) {
	if (!hudEditorActive) return
	const scale = Math.min(1.8, Math.max(0.5, Number(value) || 1))
	hudLinkedMembersOf(hudSelectedElement).forEach(function(id) {
		ensureHudElementSettings(id).scale = scale
		applyHudElementSettings(id)
	})
	renderHudEditorControls()
}

function toggleSelectedHudVisibility() {
	if (!hudEditorActive) return
	const next = ensureHudElementSettings(hudSelectedElement).visible === false
	hudLinkedMembersOf(hudSelectedElement).forEach(function(id) {
		ensureHudElementSettings(id).visible = next
		applyHudElementSettings(id)
	})
	renderHudEditorControls()
}

function setSelectedHudColor(value) {
	if (!hudEditorActive) return
	const color = HEX_COLOR_RE.test(value) ? value : ''
	hudLinkedMembersOf(hudSelectedElement).forEach(function(id) {
		ensureHudElementSettings(id).color = color
		applyHudElementSettings(id)
	})
	renderHudEditorControls()
}

function setVisibility(key, visible) {
	hudConfigVisibility[key] = visible === true
	applyHudElementSettings(key)
	if (hudEditorActive) renderHudEditorControls()
}

let currentPvpState = true;
const lastHudValues = {
	xp: null,
	job: null,
	id: null
};

function formatHudValue(key, value) {
	if (key === 'xp') {
		if (value === undefined || value === null || value === '') return value;
		const str = String(value);
		const match = str.match(/\d+/);
		const lvl = match ? match[0] : str;
		const prefix = window.JrsI18n ? window.JrsI18n.t('core_level_prefix', 'LV ') : 'LV ';
		return prefix + lvl;
	} else if (key === 'job') {
		if (value === undefined || value === null || value === '' || value === 0 || value === '0') {
			return window.JrsI18n ? window.JrsI18n.t('job_unemployed', 'Unemployed') : '0';
		}
		const clean = String(value).toLowerCase().trim().replace(/[^a-z0-9_]/g, '_');
		return window.JrsI18n ? window.JrsI18n.t('job_' + clean, value) : value;
	} else if (key === 'id') {
		if (value === undefined || value === null || value === '') return value;
		const prefix = window.JrsI18n ? window.JrsI18n.t('core_id_prefix', 'ID: ') : '';
		return prefix ? (prefix + value) : value;
	}
	return value;
}

function setPvpState(enabled) {
	if (enabled !== undefined) currentPvpState = (enabled === true);
	const element = document.getElementById('pvp');
	if (!element) return;
	element.classList.toggle('pvp-enabled', currentPvpState);
	element.classList.toggle('pvp-disabled', !currentPvpState);
	// :scope > span for the same reason as setValuee above.
	const label = element.querySelector(':scope > span');
	if (label) {
		label.textContent = currentPvpState ?
			(window.JrsI18n ? window.JrsI18n.t('core_pvp_on', 'PVP ON') : 'PVP ON') :
			(window.JrsI18n ? window.JrsI18n.t('core_pvp_off', 'PVP OFF') : 'PVP OFF');
	}
	element.title = currentPvpState ?
		(window.JrsI18n ? window.JrsI18n.t('core_pvp_enabled_title', 'Player combat is enabled') : 'Player combat is enabled') :
		(window.JrsI18n ? window.JrsI18n.t('core_pvp_disabled_title', 'Player combat is disabled') : 'Player combat is disabled');
}

// Client sends this after the player stands still for a few seconds (and
// clears it the moment they move again, or the PVP state itself changes) so
// the icon fades out of the way like the compass does when idle.
function setPvpIdle(idle) {
	const element = document.getElementById('pvp');
	if (!element) return;
	element.classList.toggle('pvp-idle-hidden', idle === true);
}

function updateWeight(weight){


	var bgcolor = colourGradient(weight/100, rgbEnd, rgbStart)
	$('#weight .bg').css('height', weight+'%')
	$('#weight .bg').css('background-color', 'rgb(' + bgcolor[0] +','+ bgcolor[1] +','+ bgcolor[2] +')')
}

function setValuee(key, value){
	if (lastHudValues.hasOwnProperty(key)) {
		lastHudValues[key] = value;
		value = formatHudValue(key, value);
	}
	// Direct child only. The ported SVG icons (html/hud-icons.js) live in their
	// own slot inside .icon, so a descendant `#id span` selector would also
	// match anything nested there and overwrite the artwork with the value.
	$('#'+key+' > span').html(value);
}

if (window.JrsI18n && typeof window.JrsI18n.onChange === 'function') {
	window.JrsI18n.onChange(function() {
		setPvpState();
		for (const k in lastHudValues) {
			if (lastHudValues[k] !== null) {
				$('#' + k + ' > span').html(formatHudValue(k, lastHudValues[k]));
			}
		}
		if (hudEditorActive) renderHudEditorControls();
	});
}


const DEFAULT_JOB_ICON = 'img/jobs/default.png'

// The Job widget now draws jrs_metabolism's single ledger glyph (see
// html/hud-icons.js), which is what that HUD does for every profession - so
// by default there is no per-job artwork to swap in and setJobIcons only has
// to keep the glyph in place.
//
// Flip this to true to go back to the old behaviour: img/jobs/<job>.png, with
// img/jobs/default.png as the fallback for a job that has no artwork. Nine of
// those files still ship (delivery, doctor, gunsmith, hunter, mining,
// offpolice, police, trainings, unemployed), so nothing has to be restored
// first - but they total ~16MB for icons drawn at 24px.
const JOB_USE_PER_JOB_ARTWORK = false

function getJobIconPath(value) {
	const jobName = String(value ?? '').trim()

	if (!jobName) {
		return DEFAULT_JOB_ICON
	}

	// Encode the job name so spaces and special characters cannot break the path.
	return 'img/jobs/' + encodeURIComponent(jobName) + '.png'
}

function applyJobIcon(selector, value) {
	const image = $(selector)

	// If the requested job image does not exist, use the default icon once.
	image.off('error.jrsJobIcon').one('error.jrsJobIcon', function() {
		$(this).off('error.jrsJobIcon').attr('src', DEFAULT_JOB_ICON)
	})

	image.attr('src', getJobIconPath(value))
}

// Swaps the <span data-jrs-icon> slot back to an <img> (or the other way) so
// the per-job switch above can be flipped without editing ui.html.
function setJobIconMode(container, value) {
	const slot = container.querySelector('.icon')
	if (!slot) return

	if (!JOB_USE_PER_JOB_ARTWORK) {
		if (!slot.querySelector('[data-jrs-icon]')) {
			slot.innerHTML = '<span class="icon-slot" data-jrs-icon="job"></span>'
			if (typeof injectJrsHudIcons === 'function') injectJrsHudIcons(slot)
		}
		return
	}

	if (!slot.querySelector('img')) slot.innerHTML = '<img alt="">'
	applyJobIcon('#' + container.id + ' img', value)
}

function setJobIcons(value){
	const container = document.getElementById('job')
	if (container) setJobIconMode(container, value)
}

function setJob2Icons(value){
	const container = document.getElementById('job2')
	if (container) setJobIconMode(container, value)
}




function CloseNUI() {

  $("#ui").fadeOut();

 // ResetAll();

	//$.post('http://jrs_tattooUi/close', JSON.stringify({}));
}

//API Shit
function colourGradient(p, rgb_beginning, rgb_end){
    var w = p * 2 - 1;

    var w1 = (w + 1) / 2.0;
    var w2 = 1 - w1;

    var rgb = [parseInt(rgb_beginning[0] * w1 + rgb_end[0] * w2),
        parseInt(rgb_beginning[1] * w1 + rgb_end[1] * w2),
            parseInt(rgb_beginning[2] * w1 + rgb_end[2] * w2)];
    return rgb;
};
