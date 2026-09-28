-- Alts Forever translations. Text is written in English in the code and looked up here:
-- L["Total"] gives the player's language when a translation exists, the English otherwise.
-- Each language's file (Locale_deDE.lua ...) fills ns.L only on a client in that language.
-- Words the game already translates (standings, Yes/No, "Requires %s (%d)") come from
-- Blizzard's own strings instead.
local _, ns = ...

ns.L = setmetatable({}, { __index = function(_, text) return text end })
