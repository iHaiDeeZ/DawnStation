-- Tekken 5 (USA) [SLUS-21059]: the European disc's fix (fixes/SCES-53202, where the reasons are), UNTESTED on
-- this disc (2026-11-17). An emulator setting, no game addresses: Sony's field-shift compensation, so the fields of
-- the game's field-mode picture line up instead of jumping half a line every frame (the menus shook).
-- With the game's "psdevwiki Lua script" option on, this script runs instead of psdevwiki's (the launcher runs one
-- script a game); DawnStation's own Widescreen option still applies.

apiRequest(0.1)

local gsObj = getGsObject()

-- the Jak X cores have it; the older core (Bully's build) doesn't
if gsObj.SetDeinterlaceShift then
	gsObj.SetDeinterlaceShift(1)
end
