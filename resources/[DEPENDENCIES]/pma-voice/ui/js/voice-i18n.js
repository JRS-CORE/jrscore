// JRS: EN/AR labels for the voice HUD. The language comes from jrs_core
// (jrsLanguage NUI message pushed by @jrs_core/shared/jrs_lang_nui.lua);
// app.js keeps it in its reactive state and calls pmaT() while rendering.
(function () {
	var packs = {
		en: {
			call: " [Call] ",
			radio: " Mhz [Radio] ",
			range: " [Range] ",
			modes: { Whisper: "Whisper", Normal: "Normal", Loud: "Loud", Shouting: "Shouting", Custom: "Custom" }
		},
		ar: {
			call: " [مكالمة] ",
			radio: " ميغاهرتز [لاسلكي] ",
			range: " [مدى الصوت] ",
			modes: { Whisper: "همس", Normal: "عادي", Loud: "مرتفع", Shouting: "صراخ", Custom: "مخصص" }
		}
	};

	window.pmaT = function (key, lang) {
		var pack = packs[lang] || packs.en;
		return pack[key] !== undefined ? pack[key] : packs.en[key];
	};

	window.pmaMode = function (name, lang) {
		var pack = packs[lang] || packs.en;
		return pack.modes[name] || name;
	};
})();
