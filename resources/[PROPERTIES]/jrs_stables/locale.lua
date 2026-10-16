-- jrs_stables | Copyright (C) 2026 JRS TEAM | SPDX-License-Identifier: GPL-3.0-or-later | see LICENSE
Locales = {}

function _(str, ...) -- Translate string

	if Locales[Config.defaultlang] ~= nil then

		if Locales[Config.defaultlang][str] ~= nil then
			return string.format(Locales[Config.defaultlang][str], ...)
		else
			return 'Translation [' .. Config.defaultlang .. '][' .. str .. '] does not exist'
		end

	else
		return 'Locale [' .. Config.defaultlang .. '] does not exist'
	end

end

function _U(str, ...) -- Translate string first char uppercase
	return tostring(_(str, ...):gsub("^%l", string.upper))
end